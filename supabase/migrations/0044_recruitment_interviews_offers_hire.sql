-- Migration 0044: ATS write-side RPCs — interview scheduling, job offers lifecycle, and hire finalization.
-- The tables (interviews, interview_panel, job_offers, applications) already exist since 0010 with RLS on
-- recruitment.interview.manage / recruitment.offer.manage; get_recruitment_workbench_catalog (0033) already
-- reads interviews[] and offers[]. This migration adds the missing admin write surface so the ATS workbench
-- can schedule interviews, manage offers, and finalize a hire. All writes are SECURITY DEFINER RPCs with an
-- explicit permission check and a fixed search_path. No table changes; no changes to 0001–0043.

-- =====================================================================
-- RPC: schedule_interview_admin — create/update an interview + panel
-- =====================================================================
create or replace function public.schedule_interview_admin(
  p_application_id uuid,
  p_mode text,
  p_scheduled_at timestamptz,
  p_location_or_link text default null,
  p_panelists uuid[] default null,
  p_interview_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_panelist uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.interview.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.applications where id = p_application_id) then raise exception 'APPLICATION_NOT_FOUND'; end if;
  if coalesce(p_mode,'') not in ('onsite','remote') then raise exception 'INVALID_MODE'; end if;

  if p_interview_id is null then
    insert into public.interviews(application_id, mode, scheduled_at, location_or_link, status, created_by)
    values (p_application_id, p_mode, p_scheduled_at, nullif(trim(p_location_or_link),''), 'scheduled', auth.uid())
    returning id into v_id;
  else
    update public.interviews
      set mode = p_mode, scheduled_at = p_scheduled_at, location_or_link = nullif(trim(p_location_or_link),''), updated_at = now()
      where id = p_interview_id and application_id = p_application_id
      returning id into v_id;
    if v_id is null then raise exception 'INTERVIEW_NOT_FOUND'; end if;
  end if;

  if p_panelists is not null then
    foreach v_panelist in array p_panelists loop
      insert into public.interview_panel(interview_id, panelist_id, created_by)
      values (v_id, v_panelist, auth.uid())
      on conflict (interview_id, panelist_id) do nothing;
    end loop;
  end if;

  perform public.log_audit_event('recruitment.interview_scheduled','workflow','info','interviews',v_id,
    'جدولة/تحديث مقابلة توظيف', null, jsonb_build_object('applicationId',p_application_id,'mode',p_mode));
  return jsonb_build_object('interviewId', v_id, 'scheduledAt', p_scheduled_at);
end $$;

-- =====================================================================
-- RPC: decide_interview_admin — mark an interview completed/cancelled/no_show
-- =====================================================================
create or replace function public.decide_interview_admin(
  p_interview_id uuid,
  p_status text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_app uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.interview.manage')) then raise exception 'FORBIDDEN'; end if;
  if coalesce(p_status,'') not in ('completed','cancelled','no_show') then raise exception 'INVALID_STATUS'; end if;
  update public.interviews set status = p_status, updated_at = now()
    where id = p_interview_id and status = 'scheduled'
    returning application_id into v_app;
  if v_app is null then raise exception 'INTERVIEW_NOT_ACTIONABLE'; end if;
  perform public.log_audit_event('recruitment.interview_'||p_status,'workflow','info','interviews',p_interview_id,
    'تحديث حالة مقابلة', null, jsonb_build_object('applicationId',v_app,'status',p_status));
  return jsonb_build_object('interviewId', p_interview_id, 'status', p_status);
end $$;

-- =====================================================================
-- RPC: create_job_offer_admin — create a draft offer (auto-versioned per application)
-- =====================================================================
create or replace function public.create_job_offer_admin(
  p_application_id uuid,
  p_title text default null,
  p_salary numeric default null,
  p_contract_type text default null,
  p_start_date date default null,
  p_expires_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_version integer;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.offer.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.applications where id = p_application_id and status = 'active') then raise exception 'APPLICATION_NOT_ACTIVE'; end if;
  select coalesce(max(version),0) + 1 into v_version from public.job_offers where application_id = p_application_id;

  insert into public.job_offers(application_id, salary, title, contract_type, start_date, expires_at, status, version, created_by)
  values (p_application_id, p_salary, nullif(trim(p_title),''), nullif(trim(p_contract_type),''), p_start_date, p_expires_at, 'draft', v_version, auth.uid())
  returning id into v_id;

  perform public.log_audit_event('recruitment.offer_created','workflow','info','job_offers',v_id,
    'إنشاء عرض توظيف', null, jsonb_build_object('applicationId',p_application_id,'version',v_version));
  return jsonb_build_object('offerId', v_id, 'version', v_version, 'status', 'draft');
end $$;

-- =====================================================================
-- RPC: transition_job_offer_admin — advance an offer through its lifecycle
-- Allowed: draft→pending→approved→sent→accepted|declined; any non-terminal→withdrawn.
-- =====================================================================
create or replace function public.transition_job_offer_admin(
  p_offer_id uuid,
  p_action text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_current text; v_next text; v_app uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.offer.manage')) then raise exception 'FORBIDDEN'; end if;
  select status, application_id into v_current, v_app from public.job_offers where id = p_offer_id for update;
  if v_current is null then raise exception 'OFFER_NOT_FOUND'; end if;

  v_next := case
    when p_action = 'submit'   and v_current = 'draft'    then 'pending'
    when p_action = 'approve'  and v_current = 'pending'  then 'approved'
    when p_action = 'send'     and v_current = 'approved' then 'sent'
    when p_action = 'accept'   and v_current = 'sent'     then 'accepted'
    when p_action = 'decline'  and v_current = 'sent'     then 'declined'
    when p_action = 'withdraw' and v_current in ('draft','pending','approved','sent') then 'withdrawn'
    else null
  end;
  if v_next is null then raise exception 'INVALID_OFFER_TRANSITION'; end if;

  update public.job_offers set status = v_next, updated_at = now() where id = p_offer_id;
  perform public.log_audit_event('recruitment.offer_'||v_next,'workflow','info','job_offers',p_offer_id,
    'انتقال حالة عرض توظيف', null, jsonb_build_object('applicationId',v_app,'from',v_current,'to',v_next));
  return jsonb_build_object('offerId', p_offer_id, 'status', v_next);
end $$;

-- =====================================================================
-- RPC: hire_from_application_admin — recruitment-side finalization of a hire.
-- Requires an accepted offer. Marks the application hired and returns candidate details so the
-- admin completes account provisioning via the existing admin-create-employee flow. Auth-user
-- creation is intentionally NOT performed here (it lives in the admin-create-employee edge function),
-- keeping the recruitment write path free of auth-side entanglement.
-- =====================================================================
create or replace function public.hire_from_application_admin(
  p_application_id uuid
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_status text; v_candidate record;
begin
  if not (public.current_is_full_access()
          or (public.has_permission('recruitment.candidate.manage')
              and public.has_permission('recruitment.offer.manage'))) then
    raise exception 'FORBIDDEN';
  end if;

  select status into v_status from public.applications where id = p_application_id for update;
  if v_status is null then raise exception 'APPLICATION_NOT_FOUND'; end if;
  if v_status <> 'active' then raise exception 'APPLICATION_NOT_ACTIVE'; end if;
  if not exists (select 1 from public.job_offers where application_id = p_application_id and status = 'accepted') then
    raise exception 'NO_ACCEPTED_OFFER';
  end if;

  update public.applications set status = 'hired', updated_at = now() where id = p_application_id;

  select c.full_name, c.email_norm, c.phone_norm into v_candidate
  from public.applications a join public.candidates c on c.id = a.candidate_id
  where a.id = p_application_id;

  perform public.log_audit_event('recruitment.application_hired','workflow','notice','applications',p_application_id,
    'اعتماد تعيين مرشح', null, jsonb_build_object('candidateName',v_candidate.full_name));
  return jsonb_build_object(
    'applicationId', p_application_id,
    'status', 'hired',
    'candidateName', v_candidate.full_name,
    'candidateEmail', v_candidate.email_norm,
    'candidatePhone', v_candidate.phone_norm);
end $$;

revoke all on function public.schedule_interview_admin(uuid, text, timestamptz, text, uuid[], uuid) from public, anon;
revoke all on function public.decide_interview_admin(uuid, text) from public, anon;
revoke all on function public.create_job_offer_admin(uuid, text, numeric, text, date, timestamptz) from public, anon;
revoke all on function public.transition_job_offer_admin(uuid, text) from public, anon;
revoke all on function public.hire_from_application_admin(uuid) from public, anon;

grant execute on function public.schedule_interview_admin(uuid, text, timestamptz, text, uuid[], uuid) to authenticated;
grant execute on function public.decide_interview_admin(uuid, text) to authenticated;
grant execute on function public.create_job_offer_admin(uuid, text, numeric, text, date, timestamptz) to authenticated;
grant execute on function public.transition_job_offer_admin(uuid, text) to authenticated;
grant execute on function public.hire_from_application_admin(uuid) to authenticated;
