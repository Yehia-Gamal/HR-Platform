-- Migration 0030: controlled dispute intake, committee governance, quorum, decisions and appeals
begin;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('disputes.case.create','disputes','case','create','إنشاء شكوى أو قضية','normal',false),
 ('disputes.case.accept','disputes','case','accept','قبول القضية وبدء المعالجة','sensitive',true),
 ('disputes.committee.manage','disputes','committee','manage','تشكيل وإدارة لجان القضايا','critical',true),
 ('disputes.session.manage','disputes','session','manage','إدارة جلسات ومحاضر القضايا','sensitive',true),
 ('disputes.decision.issue','disputes','decision','issue','إصدار قرار لجنة','critical',true),
 ('disputes.appeal.review','disputes','appeal','review','مراجعة اعتراضات القضايا','critical',true)
on conflict(code) do nothing;

alter table public.dispute_cases drop constraint if exists dispute_cases_status_check;
alter table public.dispute_cases add constraint dispute_cases_status_check check(status in ('submitted','accepted','under_investigation','in_hearing','decision_pending','resolved','closed','escalated','dismissed','cancelled','appealed'));
alter table public.dispute_cases alter column status set default 'submitted';
alter table public.dispute_cases
 add column if not exists accepted_at timestamptz,
 add column if not exists accepted_by uuid references public.employees(id) on delete set null,
 add column if not exists cancelled_at timestamptz,
 add column if not exists cancellation_reason text,
 add column if not exists committee_quorum integer not null default 2 check(committee_quorum>=1),
 add column if not exists decision_due_at timestamptz,
 add column if not exists privacy_level text not null default 'restricted' check(privacy_level in ('restricted','committee_only','executive_only')),
 add column if not exists appeal_deadline timestamptz;

create table if not exists public.dispute_conflict_declarations (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 committee_member_id uuid not null references public.committee_members(id) on delete cascade,
 has_conflict boolean not null,
 details text,
 declared_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 unique(case_id,committee_member_id)
);

create table if not exists public.dispute_session_attendance (
 session_id uuid not null references public.dispute_sessions(id) on delete cascade,
 committee_member_id uuid not null references public.committee_members(id) on delete cascade,
 attendance_status text not null default 'present' check(attendance_status in ('present','absent','excused','remote')),
 signed_at timestamptz,
 signature_method text check(signature_method in ('passkey','otp','manual_verified')),
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 primary key(session_id,committee_member_id)
);

create table if not exists public.dispute_decisions (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 session_id uuid references public.dispute_sessions(id) on delete set null,
 decision_number text not null unique,
 decision_text text not null,
 rationale text not null,
 outcome_type text not null check(outcome_type in ('dismissed','mediation','warning','corrective_action','disciplinary_recommendation','escalation','other')),
 implementation_owner_id uuid references public.employees(id) on delete set null,
 implementation_due_at timestamptz,
 status text not null default 'draft' check(status in ('draft','approved','issued','implemented','revoked')),
 approved_at timestamptz,
 approved_by uuid references public.employees(id) on delete set null,
 issued_at timestamptz,
 implemented_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id)
);

create table if not exists public.dispute_appeals (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 decision_id uuid not null references public.dispute_decisions(id) on delete cascade,
 appellant_employee_id uuid not null references public.employees(id) on delete cascade,
 reason text not null,
 status text not null default 'submitted' check(status in ('submitted','under_review','accepted','rejected','closed')),
 submitted_at timestamptz not null default now(),
 resolution text,
 reviewed_by uuid references public.employees(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id),
 unique(decision_id,appellant_employee_id)
);

create table if not exists public.dispute_actions (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 action_type text not null,
 from_status text,
 to_status text,
 note text,
 actor_employee_id uuid references public.employees(id) on delete set null,
 actor_user_id uuid references auth.users(id),
 created_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);

create index if not exists ix_dispute_decisions_case on public.dispute_decisions(case_id,status);
create index if not exists ix_dispute_appeals_status on public.dispute_appeals(status,submitted_at);
create index if not exists ix_dispute_actions_case on public.dispute_actions(case_id,created_at);

do $$ declare t text; begin
 foreach t in array array['dispute_decisions','dispute_appeals'] loop
  execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s',t);
  execute format('create trigger trg_%1$s_updated_at before update on public.%1$s for each row execute function public.tg_set_updated_at()',t);
 end loop;
 foreach t in array array['dispute_conflict_declarations','dispute_session_attendance','dispute_decisions','dispute_appeals','dispute_actions'] loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

create or replace function public.can_access_dispute(p_case_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select public.current_is_full_access() or public.has_permission('disputes.case.manage') or exists(
  select 1 from public.dispute_cases c where c.id=p_case_id and (
   c.actor_employee_id=public.current_employee_id() or c.respondent_employee_id=public.current_employee_id() or c.assigned_to=public.current_employee_id()
   or exists(select 1 from public.committee_members m where m.case_id=c.id and m.employee_id=public.current_employee_id() and m.is_active)
  )
 )
$$;

-- Replace direct writes with RPC-only workflow.
drop policy if exists dispute_cases_select on public.dispute_cases;
create policy dispute_cases_select on public.dispute_cases for select to authenticated using(public.can_access_dispute(id));
drop policy if exists dispute_cases_insert on public.dispute_cases;
drop policy if exists dispute_cases_update on public.dispute_cases;
drop policy if exists dispute_cases_delete on public.dispute_cases;
revoke insert,update,delete on public.dispute_cases from authenticated;

drop policy if exists dispute_sessions_select on public.dispute_sessions;
create policy dispute_sessions_select on public.dispute_sessions for select to authenticated using(public.can_access_dispute(case_id));
drop policy if exists dispute_sessions_write on public.dispute_sessions;
revoke insert,update,delete on public.dispute_sessions from authenticated;

drop policy if exists dispute_evidence_select on public.dispute_evidence;
create policy dispute_evidence_select on public.dispute_evidence for select to authenticated using(public.can_access_dispute(case_id));
drop policy if exists dispute_evidence_write on public.dispute_evidence;
revoke insert,update,delete on public.dispute_evidence from authenticated;

drop policy if exists committee_members_select on public.committee_members;
create policy committee_members_select on public.committee_members for select to authenticated using(employee_id=public.current_employee_id() or (case_id is not null and public.can_access_dispute(case_id)));
drop policy if exists committee_members_write on public.committee_members;
revoke insert,update,delete on public.committee_members from authenticated;

create policy dispute_conflicts_read on public.dispute_conflict_declarations for select to authenticated using(public.can_access_dispute(case_id));
create policy dispute_attendance_read on public.dispute_session_attendance for select to authenticated using(exists(select 1 from public.dispute_sessions s where s.id=session_id and public.can_access_dispute(s.case_id)));
create policy dispute_decisions_read on public.dispute_decisions for select to authenticated using(public.can_access_dispute(case_id));
create policy dispute_appeals_read on public.dispute_appeals for select to authenticated using(appellant_employee_id=public.current_employee_id() or public.can_access_dispute(case_id));
create policy dispute_actions_read on public.dispute_actions for select to authenticated using(public.can_access_dispute(case_id));
revoke insert,update,delete on public.dispute_conflict_declarations,public.dispute_session_attendance,public.dispute_decisions,public.dispute_appeals,public.dispute_actions from authenticated;

create or replace function public.create_my_dispute(p_title text,p_description text,p_case_type text default 'grievance',p_respondent_employee_id uuid default null,p_severity text default 'medium',p_confidential boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text;
begin
 if v_emp is null or length(trim(p_title))<5 or length(trim(p_description))<20 then raise exception 'INVALID_CASE'; end if;
 if p_respondent_employee_id=v_emp then raise exception 'SELF_RESPONDENT_FORBIDDEN'; end if;
 v_number:='CASE-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_cases(case_number,title,description,case_type,status,severity,actor_employee_id,respondent_employee_id,is_confidential,privacy_level,opened_at,created_by)
 values(v_number,trim(p_title),trim(p_description),p_case_type,'submitted',p_severity,v_emp,p_respondent_employee_id,p_confidential,'restricted',now(),auth.uid()) returning id into v_id;
 insert into public.dispute_actions(case_id,action_type,to_status,note,actor_employee_id,actor_user_id) values(v_id,'submit','submitted','تم تقديم القضية',v_emp,auth.uid()); return v_id;
end $$;

create or replace function public.cancel_my_dispute(p_case_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 if v.actor_employee_id<>public.current_employee_id() or v.status<>'submitted' or v.accepted_at is not null then raise exception 'CANNOT_CANCEL'; end if;
 if length(trim(p_reason))<5 then raise exception 'REASON_REQUIRED'; end if;
 update public.dispute_cases set status='cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason),updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id) values(p_case_id,'cancel','submitted','cancelled',trim(p_reason),public.current_employee_id(),auth.uid());
end $$;

create or replace function public.accept_dispute_case(p_case_id uuid,p_assigned_to uuid,p_quorum integer default 2,p_due_at timestamptz default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['disputes.case.accept','disputes.case.manage'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 if v.status<>'submitted' then raise exception 'INVALID_STATE'; end if;
 update public.dispute_cases set status='accepted',accepted_at=now(),accepted_by=public.current_employee_id(),assigned_to=p_assigned_to,committee_quorum=greatest(p_quorum,1),decision_due_at=coalesce(p_due_at,now()+interval '7 days'),updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id) values(p_case_id,'accept','submitted','accepted',public.current_employee_id(),auth.uid());
end $$;

create or replace function public.set_dispute_committee(p_case_id uuid,p_members jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item jsonb; v_emp uuid; v_role text; v_actor uuid; v_respondent uuid;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.committee.manage')) then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then raise exception 'COMMITTEE_TOO_SMALL'; end if;
 select actor_employee_id,respondent_employee_id into strict v_actor,v_respondent from public.dispute_cases where id=p_case_id for update;
 delete from public.committee_members where case_id=p_case_id;
 for v_item in select * from jsonb_array_elements(p_members) loop
  v_emp:=(v_item->>'employeeId')::uuid; v_role:=coalesce(v_item->>'role','member');
  if v_emp in (v_actor,v_respondent) then raise exception 'PARTY_CANNOT_JOIN_COMMITTEE'; end if;
  insert into public.committee_members(case_id,committee_name,employee_id,role_in_committee,created_by) values(p_case_id,'لجنة حل المشاكل والخلافات',v_emp,v_role,auth.uid());
 end loop;
 if not exists(select 1 from public.committee_members where case_id=p_case_id and role_in_committee='chair') then raise exception 'CHAIR_REQUIRED'; end if;
 update public.dispute_cases set status='under_investigation',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata) values(p_case_id,'committee_assigned','accepted','under_investigation',public.current_employee_id(),auth.uid(),jsonb_build_object('members',jsonb_array_length(p_members)));
end $$;

create or replace function public.declare_dispute_conflict(p_case_id uuid,p_has_conflict boolean,p_details text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_member uuid;
begin
 select id into strict v_member from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and is_active;
 insert into public.dispute_conflict_declarations(case_id,committee_member_id,has_conflict,details,created_by) values(p_case_id,v_member,p_has_conflict,p_details,auth.uid())
 on conflict(case_id,committee_member_id) do update set has_conflict=excluded.has_conflict,details=excluded.details,declared_at=now();
 if p_has_conflict then update public.committee_members set is_active=false,removed_at=now(),updated_at=now() where id=v_member; end if;
end $$;

create or replace function public.schedule_dispute_session(p_case_id uuid,p_type text,p_scheduled_at timestamptz,p_location text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN'; end if;
 insert into public.dispute_sessions(case_id,session_type,scheduled_at,location,status,created_by) values(p_case_id,p_type,p_scheduled_at,p_location,'scheduled',auth.uid()) returning id into v_id;
 update public.dispute_cases set status='in_hearing',updated_at=now() where id=p_case_id and status in ('accepted','under_investigation'); return v_id;
end $$;

create or replace function public.finalize_dispute_session(p_session_id uuid,p_minutes text,p_outcome text,p_attendance jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.dispute_sessions; v_case public.dispute_cases; v_item jsonb; v_member uuid; v_present integer:=0;
begin
 select * into strict v_session from public.dispute_sessions where id=p_session_id for update; select * into strict v_case from public.dispute_cases where id=v_session.case_id for update;
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=v_case.id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_minutes))<20 or jsonb_typeof(p_attendance)<>'array' then raise exception 'INVALID_MINUTES'; end if;
 delete from public.dispute_session_attendance where session_id=p_session_id;
 for v_item in select * from jsonb_array_elements(p_attendance) loop
  v_member:=(v_item->>'committeeMemberId')::uuid;
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
 if not exists(select 1 from public.dispute_sessions s where s.id=p_session_id and s.case_id=p_case_id and s.status='held' and (select count(*) from public.dispute_session_attendance a where a.session_id=s.id and a.attendance_status in ('present','remote'))>=v_case.committee_quorum) then raise exception 'HELD_SESSION_WITH_QUORUM_REQUIRED'; end if;
 v_number:='DEC-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_decisions(case_id,session_id,decision_number,decision_text,rationale,outcome_type,implementation_owner_id,implementation_due_at,status,approved_at,approved_by,issued_at,created_by)
 values(p_case_id,p_session_id,v_number,trim(p_text),trim(p_rationale),p_outcome,p_owner_id,p_due_at,'issued',now(),public.current_employee_id(),now(),auth.uid()) returning id into v_id;
 update public.dispute_cases set status='resolved',resolved_at=now(),resolution_summary=trim(p_text),appeal_deadline=now()+interval '7 days',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata) values(p_case_id,'decision_issued',v_case.status,'resolved',p_text,public.current_employee_id(),auth.uid(),jsonb_build_object('decisionId',v_id)); return v_id;
end $$;

create or replace function public.submit_dispute_appeal(p_decision_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_dec public.dispute_decisions; v_case public.dispute_cases; v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
 select * into strict v_dec from public.dispute_decisions where id=p_decision_id; select * into strict v_case from public.dispute_cases where id=v_dec.case_id for update;
 if v_emp not in (v_case.actor_employee_id,v_case.respondent_employee_id) or now()>v_case.appeal_deadline or length(trim(p_reason))<20 then raise exception 'APPEAL_NOT_ALLOWED'; end if;
 insert into public.dispute_appeals(case_id,decision_id,appellant_employee_id,reason,created_by) values(v_case.id,p_decision_id,v_emp,trim(p_reason),auth.uid()) returning id into v_id;
 update public.dispute_cases set status='appealed',updated_at=now() where id=v_case.id; return v_id;
end $$;

create or replace function public.decide_dispute_appeal(p_appeal_id uuid,p_decision text,p_resolution text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_appeals;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.appeal.review')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.dispute_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') or p_decision not in ('accepted','rejected') or length(trim(p_resolution))<10 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 update public.dispute_appeals set status=p_decision,resolution=trim(p_resolution),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 update public.dispute_cases set status=case when p_decision='accepted' then 'under_investigation' else 'resolved' end,updated_at=now() where id=v.case_id;
end $$;

create or replace function public.get_dispute_operations_catalog(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.case.manage') or exists(select 1 from public.committee_members where employee_id=public.current_employee_id() and is_active)) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object('cases',coalesce((select jsonb_agg(jsonb_build_object(
  'id',c.id,'caseNumber',c.case_number,'title',c.title,'caseType',c.case_type,'status',c.status,'severity',c.severity,'actorId',c.actor_employee_id,'actorName',a.full_name_ar,'respondentId',c.respondent_employee_id,'respondentName',r.full_name_ar,'assignedTo',c.assigned_to,'assignedName',ass.full_name_ar,'openedAt',c.opened_at,'acceptedAt',c.accepted_at,'decisionDueAt',c.decision_due_at,'quorum',c.committee_quorum,
  'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'employeeId',m.employee_id,'name',me.full_name_ar,'role',m.role_in_committee,'active',m.is_active) order by m.role_in_committee) from public.committee_members m join public.employees me on me.id=m.employee_id where m.case_id=c.id),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'type',s.session_type,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'status',s.status,'location',s.location,'outcome',s.outcome) order by s.scheduled_at desc) from public.dispute_sessions s where s.case_id=c.id),'[]'::jsonb),
  'decision', (select jsonb_build_object('id',d.id,'number',d.decision_number,'text',d.decision_text,'outcome',d.outcome_type,'status',d.status,'issuedAt',d.issued_at) from public.dispute_decisions d where d.case_id=c.id order by d.created_at desc limit 1)
 ) order by c.created_at desc) from public.dispute_cases c left join public.employees a on a.id=c.actor_employee_id left join public.employees r on r.id=c.respondent_employee_id left join public.employees ass on ass.id=c.assigned_to where (p_status is null or c.status=p_status) and public.can_access_dispute(c.id)),'[]'::jsonb),
 'pendingAppeals',coalesce((select count(*) from public.dispute_appeals where status in ('submitted','under_review')),0),'lastUpdatedAt',now());
end $$;

revoke execute on function public.can_access_dispute(uuid) from public; grant execute on function public.can_access_dispute(uuid) to authenticated;
revoke execute on function public.create_my_dispute(text,text,text,uuid,text,boolean) from public; grant execute on function public.create_my_dispute(text,text,text,uuid,text,boolean) to authenticated;
revoke execute on function public.cancel_my_dispute(uuid,text) from public; grant execute on function public.cancel_my_dispute(uuid,text) to authenticated;
revoke execute on function public.accept_dispute_case(uuid,uuid,integer,timestamptz) from public; grant execute on function public.accept_dispute_case(uuid,uuid,integer,timestamptz) to authenticated;
revoke execute on function public.set_dispute_committee(uuid,jsonb) from public; grant execute on function public.set_dispute_committee(uuid,jsonb) to authenticated;
revoke execute on function public.declare_dispute_conflict(uuid,boolean,text) from public; grant execute on function public.declare_dispute_conflict(uuid,boolean,text) to authenticated;
revoke execute on function public.schedule_dispute_session(uuid,text,timestamptz,text) from public; grant execute on function public.schedule_dispute_session(uuid,text,timestamptz,text) to authenticated;
revoke execute on function public.finalize_dispute_session(uuid,text,text,jsonb) from public; grant execute on function public.finalize_dispute_session(uuid,text,text,jsonb) to authenticated;
revoke execute on function public.issue_dispute_decision(uuid,uuid,text,text,text,uuid,timestamptz) from public; grant execute on function public.issue_dispute_decision(uuid,uuid,text,text,text,uuid,timestamptz) to authenticated;
revoke execute on function public.submit_dispute_appeal(uuid,text) from public; grant execute on function public.submit_dispute_appeal(uuid,text) to authenticated;
revoke execute on function public.decide_dispute_appeal(uuid,text,text) from public; grant execute on function public.decide_dispute_appeal(uuid,text,text) to authenticated;
revoke execute on function public.get_dispute_operations_catalog(text) from public; grant execute on function public.get_dispute_operations_catalog(text) to authenticated;

commit;
