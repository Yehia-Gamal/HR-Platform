-- Migration 0052: P2/P3 audit remediation (HR_PLATFORM_DEEP_AUDIT_V8_AR.md)
-- (أُعيد ترقيمه من 0051 لحل تعارض ترقيم مع 0051_schedule_remaining_edge_functions)
-- ============================================================================
-- Database-side fixes for the P2/P3 findings that were deferred from 0050:
--   SDEF-01  [P2] revoke default PUBLIC EXECUTE on DEFINER RPCs (0033/0035/0036)
--   CTB-02   [P2] service_requests: requester cannot self-transition to
--                 privileged statuses (resolved/closed/assigned/in_progress)
--   CTB-04   [P2] security_events.handled_by is server-forced to auth.uid()
--   DISPUTE-01[P2] quorum counts only active committee members of THIS case
--   RLS-03   [P3] course-materials storage read scoped to enrolled/authorized
-- All idempotent (drop/replace). Edge-function (ESI-*) and web (CTB-01) fixes
-- are applied outside SQL.
-- ============================================================================

begin;

-- ============================================================================
-- SDEF-01 [P2] — Revoke the default PUBLIC EXECUTE grant left on SECURITY
-- DEFINER RPCs in 0033/0035/0036. Each keeps its authenticated grant + internal
-- guard; this removes the anon-reachable entrypoint (defense in depth), matching
-- the pattern used in 0025/0038/0044.
-- ============================================================================

-- 0036 (payroll/people-finance)
revoke execute on function public.get_people_finance_catalog() from public, anon;
revoke execute on function public.get_my_payslips() from public, anon;

-- 0035 (enterprise / service portal)
revoke execute on function public.get_enterprise_management_catalog() from public, anon;
revoke execute on function public.get_my_service_portal() from public, anon;
revoke execute on function public.submit_my_service_request(uuid,text,text,text,jsonb) from public, anon;

-- 0033 (learning / documents / reports / recruitment)
revoke execute on function public.get_learning_admin_catalog() from public, anon;
revoke execute on function public.upsert_learning_course_admin(uuid,text,text,text,text,text,text,integer,boolean,numeric,integer,boolean) from public, anon;
revoke execute on function public.enroll_employee_course_admin(uuid,uuid,uuid) from public, anon;
revoke execute on function public.transition_learning_enrollment(uuid,text,integer,numeric) from public, anon;
revoke execute on function public.get_my_learning_catalog() from public, anon;
revoke execute on function public.get_document_studio_catalog() from public, anon;
revoke execute on function public.upsert_document_template_admin(uuid,text,text,text,text,boolean,boolean,boolean,boolean,boolean) from public, anon;
revoke execute on function public.get_report_scheduler_catalog() from public, anon;
revoke execute on function public.upsert_scheduled_report_admin(uuid,text,text,text,text,text,smallint,smallint,smallint,text[],boolean) from public, anon;
revoke execute on function public.get_recruitment_workbench_catalog() from public, anon;
revoke execute on function public.move_application_stage_admin(uuid,uuid,text) from public, anon;

-- ============================================================================
-- CTB-04 [P2] — Force security_events.handled_by server-side.
-- A BEFORE UPDATE trigger overwrites any client-supplied handled_by with the
-- actual caller (auth.uid()) whenever the event transitions to handled, so the
-- incident-handler audit field cannot be forged.
-- ============================================================================

create or replace function public.tg_security_events_force_handler()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- On transition to handled (or any update that sets handled = true), pin the
  -- handler identity and timestamp to the real caller; ignore client values.
  if new.handled is true then
    new.handled_by := auth.uid();
    new.handled_at := coalesce(new.handled_at, now());
  end if;
  return new;
end $$;

drop trigger if exists trg_security_events_force_handler on public.security_events;
create trigger trg_security_events_force_handler
  before update on public.security_events
  for each row execute function public.tg_security_events_force_handler();

-- ============================================================================
-- CTB-02 [P2] — Restrict requester self-transitions on service_requests.
-- The RLS policy still lets the requester update their own row (needed for
-- cancel / satisfaction), but a BEFORE UPDATE trigger blocks a non-privileged
-- requester from driving the ticket into agent-only statuses. Managers
-- (service.request.manage) and full-access are unaffected.
-- ============================================================================

create or replace function public.tg_service_requests_guard_status()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_privileged boolean;
begin
  if new.status is distinct from old.status then
    v_privileged := public.current_is_full_access()
                    or public.has_permission('service.request.manage');
    if not v_privileged then
      -- A plain requester may only cancel their own ticket (or leave it as-is).
      if new.status <> 'cancelled' then
        raise exception 'SERVICE_REQUEST_STATUS_FORBIDDEN: only staff may set status %', new.status
          using errcode = '42501';
      end if;
      -- Requester may not fabricate a resolution timestamp.
      new.resolved_at := old.resolved_at;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_service_requests_guard_status on public.service_requests;
create trigger trg_service_requests_guard_status
  before update on public.service_requests
  for each row execute function public.tg_service_requests_guard_status();

-- ============================================================================
-- DISPUTE-01 [P2] — Quorum counts only ACTIVE committee members of THIS case.
-- finalize_dispute_session and issue_dispute_decision previously counted any
-- committee_member row (including inactive/recused members, or members of
-- another case) toward quorum. Redefine both to validate membership.
-- ============================================================================

create or replace function public.finalize_dispute_session(p_session_id uuid,p_minutes text,p_attendance jsonb,p_outcome text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.dispute_sessions; v_case public.dispute_cases; v_item jsonb; v_member uuid; v_present integer:=0;
begin
 select * into strict v_session from public.dispute_sessions where id=p_session_id for update; select * into strict v_case from public.dispute_cases where id=v_session.case_id for update;
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=v_case.id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_minutes))<20 or jsonb_typeof(p_attendance)<>'array' then raise exception 'INVALID_MINUTES'; end if;
 delete from public.dispute_session_attendance where session_id=p_session_id;
 for v_item in select * from jsonb_array_elements(p_attendance) loop
  v_member:=(v_item->>'committeeMemberId')::uuid;
  -- Only active committee members of THIS case may be recorded / counted.
  if not exists(select 1 from public.committee_members cm where cm.id=v_member and cm.case_id=v_case.id and cm.is_active) then
    raise exception 'INVALID_COMMITTEE_MEMBER: % is not an active member of this case', v_member using errcode='22023';
  end if;
  insert into public.dispute_session_attendance(session_id,committee_member_id,attendance_status,signed_at,signature_method,created_by)
  values(p_session_id,v_member,coalesce(v_item->>'status','present'),case when coalesce(v_item->>'status','present') in ('present','remote') then now() end,case when coalesce(v_item->>'status','present') in ('present','remote') then 'manual_verified' end,auth.uid());
  if coalesce(v_item->>'status','present') in ('present','remote') then v_present:=v_present+1; end if;
 end loop;
 if v_present<v_case.committee_quorum then raise exception 'QUORUM_NOT_MET'; end if;
 update public.dispute_sessions set status='held',held_at=now(),minutes=trim(p_minutes),outcome=p_outcome,updated_at=now() where id=p_session_id;
 update public.dispute_cases set status='decision_pending',updated_at=now() where id=v_case.id;
end $$;

create or replace function public.issue_dispute_decision(p_case_id uuid,p_session_id uuid,p_text text,p_rationale text,p_outcome text,p_owner_id uuid default null,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_case public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.decision.issue') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee='chair' and is_active)) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_case from public.dispute_cases where id=p_case_id for update;
 if v_case.status not in ('decision_pending','in_hearing','under_investigation') or length(trim(p_text))<20 or length(trim(p_rationale))<20 then raise exception 'INVALID_DECISION'; end if;
 -- Quorum recount counts only active committee members of this case.
 if not exists(
   select 1 from public.dispute_sessions s
   where s.id=p_session_id and s.case_id=p_case_id and s.status='held'
     and (
       select count(*) from public.dispute_session_attendance a
       join public.committee_members cm on cm.id=a.committee_member_id
       where a.session_id=s.id and a.attendance_status in ('present','remote')
         and cm.case_id=p_case_id and cm.is_active
     ) >= v_case.committee_quorum
 ) then raise exception 'HELD_SESSION_WITH_QUORUM_REQUIRED'; end if;
 v_number:='DEC-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_decisions(case_id,session_id,decision_number,decision_text,rationale,outcome_type,implementation_owner_id,implementation_due_at,status,approved_at,approved_by,issued_at,created_by)
 values(p_case_id,p_session_id,v_number,trim(p_text),trim(p_rationale),p_outcome,p_owner_id,p_due_at,'issued',now(),public.current_employee_id(),now(),auth.uid()) returning id into v_id;
 update public.dispute_cases set status='resolved',resolved_at=now(),resolution_summary=trim(p_text),appeal_deadline=now()+interval '7 days',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata) values(p_case_id,'decision_issued',v_case.status,'resolved',p_text,public.current_employee_id(),auth.uid(),jsonb_build_object('decisionId',v_id)); return v_id;
end $$;

-- ============================================================================
-- RLS-03 [P3] — Scope course-materials storage reads.
-- Previously any authenticated user could read every object. Restrict to
-- full-access, course managers, or employees enrolled in the course whose id is
-- the object's first folder segment (mirroring the employee-documents prefix
-- pattern). Uploads (write) were already gated by learning.course.manage.
-- ============================================================================

drop policy if exists course_materials_storage_read on storage.objects;
create policy course_materials_storage_read on storage.objects for select to authenticated using (
  bucket_id='course-materials' and (
    public.current_is_full_access()
    or public.has_permission('learning.course.manage')
    or exists (
      select 1 from public.learning_enrollments en
      where en.employee_id = public.current_employee_id()
        and en.course_id::text = (storage.foldername(name))[1]
    )
  )
);

commit;
