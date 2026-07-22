-- Migration 0059: end-to-end problems and disputes committee workflow.
--
-- This migration deliberately extends the existing dispute_* model instead of
-- creating a second complaints module. It closes the confidentiality gap,
-- adds the 24-hour intake SLA, multi-party statements, structured minutes,
-- decision execution, settlements, receipts, notifications and audit events.

begin;

-- ---------------------------------------------------------------------------
-- Permissions and the two operational-manager roles used by the association.
-- The title remains an operations title; committee access is a capability and
-- does not turn either manager into a formally titled executive deputy.
-- ---------------------------------------------------------------------------

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('disputes.portal.access','disputes','portal','access','الدخول إلى مساحة لجنة حل المشكلات','sensitive',true),
 ('disputes.case.read_all','disputes','case','read_all','قراءة جميع قضايا اللجنة','critical',true),
 ('disputes.case.transition','disputes','case','transition','إدارة انتقالات مسار القضية','critical',true),
 ('disputes.case.escalate','disputes','case','escalate','تصعيد القضية وإعادتها','critical',true),
 ('disputes.statement.manage','disputes','statement','manage','طلب الإفادات وإدارة الملاحظات','sensitive',true),
 ('disputes.action.manage','disputes','action','manage','متابعة تنفيذ قرارات اللجنة','sensitive',true),
 ('disputes.executive.manage','disputes','executive','manage','مراجعة واعتماد القضايا المصعدة','critical',true)
on conflict(code) do update set
 description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

insert into public.roles(slug,name_ar,name_en,description,is_system,is_full_access)
values
 ('operations-manager-1','مدير التشغيل 1','Operations Manager 1','إدارة التشغيل الأولى والمشاركة في لجنة حل المشكلات عند التكليف',true,false),
 ('operations-manager-2','مدير التشغيل 2','Operations Manager 2','إدارة التشغيل الثانية والمشاركة في لجنة حل المشكلات عند التكليف',true,false),
 ('committee-secretary','مقرر لجنة حل المشكلات','Dispute Committee Secretary','إدارة الجلسات والمحاضر للقضايا المسندة',true,false)
on conflict(slug) do update set
 name_ar=excluded.name_ar,name_en=excluded.name_en,description=excluded.description,is_system=true;

insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id,p.id,'assigned_cases',p.is_sensitive
from public.roles r
join public.permissions p on p.code = any(array[
 'disputes.portal.access','disputes.statement.manage','disputes.session.manage'
])
where r.slug in ('operations-manager-1','operations-manager-2','committee-member','committee-chair','committee-secretary')
on conflict(role_id,permission_id,scope) do update set requires_reason=excluded.requires_reason;

insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id,p.id,'organization',p.is_sensitive
from public.roles r
join public.permissions p on p.code = any(array[
 'disputes.portal.access','disputes.case.read_all','disputes.executive.manage',
 'disputes.case.escalate','disputes.appeal.review'
])
where r.slug='executive-director'
on conflict(role_id,permission_id,scope) do update set requires_reason=excluded.requires_reason;

-- ---------------------------------------------------------------------------
-- Canonical states and clear priority labels.
-- ---------------------------------------------------------------------------

alter table public.dispute_cases drop constraint if exists dispute_cases_severity_check;
update public.dispute_cases set severity=case
 when severity in ('low','medium') then 'normal'
 when severity='high' then 'urgent'
 else 'critical' end;
alter table public.dispute_cases alter column severity set default 'normal';
alter table public.dispute_cases add constraint dispute_cases_severity_check
 check(severity in ('normal','urgent','critical'));

alter table public.dispute_cases drop constraint if exists dispute_cases_status_check;
update public.dispute_cases set status=case status
 when 'under_investigation' then 'under_review'
 when 'in_hearing' then 'session_scheduled'
 when 'decision_pending' then 'committee_deliberation'
 when 'resolved' then 'decision_issued'
 when 'escalated' then 'escalated_to_executive'
 when 'cancelled' then 'cancelled_by_employee'
 when 'appealed' then 'reopened'
 else status end;
alter table public.dispute_cases add constraint dispute_cases_status_check check(status in (
 'draft','submitted','needs_more_information','accepted','rejected','under_review',
 'waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed',
 'committee_deliberation','settlement_pending','escalated_to_executive',
 'returned_to_committee','decision_issued','closed','reopened','cancelled_by_employee'
));
alter table public.dispute_cases alter column status set default 'submitted';

alter table public.dispute_cases
 add column if not exists incident_at timestamptz,
 add column if not exists incident_location text,
 add column if not exists requested_action text,
 add column if not exists witnesses_present boolean not null default false,
 add column if not exists direct_manager_contacted boolean,
 add column if not exists amicable_resolution_attempted boolean,
 add column if not exists amicable_resolution_result text,
 add column if not exists truth_confirmed boolean not null default false,
 add column if not exists confidentiality_accepted boolean not null default false,
 add column if not exists shareable_summary text,
 add column if not exists review_due_at timestamptz,
 add column if not exists review_extended_at timestamptz,
 add column if not exists review_extension_reason text,
 add column if not exists respondent_notified_at timestamptz,
 add column if not exists escalated_at timestamptz,
 add column if not exists escalated_by uuid references public.employees(id) on delete set null,
 add column if not exists closed_at timestamptz,
 add column if not exists closed_by uuid references public.employees(id) on delete set null,
 add column if not exists closure_reason text,
 add column if not exists reopened_at timestamptz;

update public.dispute_cases
set review_due_at=coalesce(review_due_at,opened_at+interval '24 hours'),
    truth_confirmed=true,
    confidentiality_accepted=true
where review_due_at is null;

create index if not exists ix_dispute_cases_review_sla
 on public.dispute_cases(review_due_at,status)
 where status in ('submitted','needs_more_information');
create index if not exists ix_dispute_cases_priority_status on public.dispute_cases(severity,status,opened_at desc);

-- ---------------------------------------------------------------------------
-- Multi-party cases, statements, structured attendance, settlements and read
-- receipts. Existing evidence/actions/sessions/decisions are extended.
-- ---------------------------------------------------------------------------

create table if not exists public.dispute_parties(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete restrict,
 party_type text not null check(party_type in ('complainant','respondent','witness','related')),
 notification_status text not null default 'withheld' check(notification_status in ('withheld','queued','notified','read')),
 notified_at timestamptz,
 statement_requested_at timestamptz,
 statement_submitted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id),
 unique(case_id,employee_id,party_type)
);

create table if not exists public.dispute_statements(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 party_id uuid references public.dispute_parties(id) on delete set null,
 submitted_by uuid not null references public.employees(id) on delete restrict,
 statement_type text not null check(statement_type in ('complainant','respondent','witness','clarification','committee_note','recommendation','executive_note')),
 statement_text text not null check(length(trim(statement_text))>=10),
 visibility text not null default 'committee_only' check(visibility in ('committee_only','submitter_and_committee','parties','complainant','respondent')),
 submitted_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);

create table if not exists public.dispute_session_participants(
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.dispute_sessions(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete restrict,
 participant_role text not null check(participant_role in ('complainant','respondent','witness','committee','guest')),
 attendance_status text not null default 'invited' check(attendance_status in ('invited','present','remote','absent','excused')),
 acknowledged_at timestamptz,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 unique(session_id,employee_id,participant_role)
);

create table if not exists public.dispute_settlements(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.dispute_cases(id) on delete cascade,
 apology_from uuid references public.employees(id) on delete set null,
 apology_to uuid references public.employees(id) on delete set null,
 settlement_type text not null check(settlement_type in ('verbal_apology','written_apology','group_apology','undertaking','mediation','follow_up','other')),
 apology_text text,
 publication_place text,
 due_at timestamptz,
 status text not null default 'pending' check(status in ('pending','completed','waived','failed')),
 confirmed_by uuid references public.employees(id) on delete set null,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id)
);

create table if not exists public.dispute_decision_receipts(
 decision_id uuid not null references public.dispute_decisions(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade,
 acknowledged_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 primary key(decision_id,employee_id)
);

alter table public.dispute_sessions
 add column if not exists ends_at timestamptz,
 add column if not exists modality text check(modality in ('in_person','remote','hybrid')),
 add column if not exists minutes_data jsonb not null default '{}'::jsonb,
 add column if not exists recommendation text,
 add column if not exists follow_up_at timestamptz,
 add column if not exists internal_notes text;

alter table public.dispute_evidence
 add column if not exists storage_path text,
 add column if not exists mime_type text,
 add column if not exists file_size_bytes bigint,
 add column if not exists visibility text not null default 'committee_only'
   check(visibility in ('committee_only','submitter_and_committee','parties')),
 add column if not exists deleted_at timestamptz,
 add column if not exists deleted_by uuid references public.employees(id) on delete set null,
 add column if not exists deletion_reason text;

alter table public.dispute_decisions
 add column if not exists decision_type text,
 add column if not exists party_visible_text text,
 add column if not exists requires_implementation boolean not null default false,
 add column if not exists supersedes_decision_id uuid references public.dispute_decisions(id) on delete set null,
 add column if not exists amendment_reason text;

alter table public.dispute_actions
 add column if not exists assigned_to uuid references public.employees(id) on delete set null,
 add column if not exists due_at timestamptz,
 add column if not exists execution_status text check(execution_status in ('pending','in_progress','completed','cancelled','failed')),
 add column if not exists completion_proof text,
 add column if not exists completed_at timestamptz,
 add column if not exists visibility text not null default 'committee_only'
   check(visibility in ('committee_only','parties','complainant','respondent'));

create index if not exists ix_dispute_parties_employee on public.dispute_parties(employee_id,notification_status);
create index if not exists ix_dispute_statements_case on public.dispute_statements(case_id,submitted_at);
create index if not exists ix_dispute_execution_due on public.dispute_actions(due_at,execution_status)
 where execution_status in ('pending','in_progress');
create index if not exists ix_dispute_settlements_due on public.dispute_settlements(due_at,status) where status='pending';

do $$ declare t text; begin
 foreach t in array array['dispute_parties','dispute_settlements'] loop
  execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s',t);
  execute format('create trigger trg_%1$s_updated_at before update on public.%1$s for each row execute function public.tg_set_updated_at()',t);
 end loop;
 foreach t in array array['dispute_parties','dispute_statements','dispute_session_participants','dispute_settlements','dispute_decision_receipts'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

-- Backfill the original actor/respondent columns into the multi-party model.
insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,notified_at)
select id,actor_employee_id,'complainant','read',opened_at from public.dispute_cases where actor_employee_id is not null
on conflict(case_id,employee_id,party_type) do nothing;
insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,notified_at)
select id,respondent_employee_id,'respondent',case when respondent_notified_at is null then 'withheld' else 'notified' end,respondent_notified_at
from public.dispute_cases where respondent_employee_id is not null
on conflict(case_id,employee_id,party_type) do nothing;

-- ---------------------------------------------------------------------------
-- Server-authoritative access. A named respondent no longer sees a case merely
-- because their id was selected; access begins only after committee notice.
-- ---------------------------------------------------------------------------

create or replace function public.can_access_dispute(p_case_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select public.current_is_full_access()
 or public.has_permission('disputes.case.read_all')
 or exists(
  select 1 from public.dispute_cases c where c.id=p_case_id and (
   c.actor_employee_id=public.current_employee_id()
   or c.assigned_to=public.current_employee_id()
   or exists(select 1 from public.committee_members m where m.case_id=c.id and m.employee_id=public.current_employee_id() and m.is_active)
   or exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=public.current_employee_id() and dp.party_type<>'complainant' and dp.notified_at is not null)
  )
 )
$$;

drop policy if exists dispute_cases_select on public.dispute_cases;
create policy dispute_cases_select on public.dispute_cases for select to authenticated using(public.can_access_dispute(id));

drop policy if exists dispute_evidence_select on public.dispute_evidence;
create policy dispute_evidence_select on public.dispute_evidence for select to authenticated using(
 deleted_at is null and (
  public.current_is_full_access() or public.has_permission('disputes.case.read_all')
  or submitted_by=public.current_employee_id()
  or exists(select 1 from public.committee_members cm where cm.case_id=dispute_evidence.case_id and cm.employee_id=public.current_employee_id() and cm.is_active)
  or (visibility='parties' and public.can_access_dispute(case_id))
 )
);

drop policy if exists dispute_parties_read on public.dispute_parties;
create policy dispute_parties_read on public.dispute_parties for select to authenticated using(
 public.current_is_full_access() or public.has_permission('disputes.case.read_all')
 or employee_id=public.current_employee_id()
 or exists(select 1 from public.dispute_cases c where c.id=case_id and c.actor_employee_id=public.current_employee_id())
 or exists(select 1 from public.committee_members cm where cm.case_id=dispute_parties.case_id and cm.employee_id=public.current_employee_id() and cm.is_active)
);
drop policy if exists dispute_statements_read on public.dispute_statements;
create policy dispute_statements_read on public.dispute_statements for select to authenticated using(
 public.current_is_full_access() or public.has_permission('disputes.case.read_all')
 or submitted_by=public.current_employee_id()
 or exists(select 1 from public.committee_members cm where cm.case_id=dispute_statements.case_id and cm.employee_id=public.current_employee_id() and cm.is_active)
 or (visibility='parties' and public.can_access_dispute(case_id))
 or (visibility='complainant' and exists(select 1 from public.dispute_cases c where c.id=case_id and c.actor_employee_id=public.current_employee_id()))
 or (visibility='respondent' and exists(select 1 from public.dispute_parties dp where dp.case_id=dispute_statements.case_id and dp.employee_id=public.current_employee_id() and dp.party_type='respondent' and dp.notified_at is not null))
);
drop policy if exists dispute_session_participants_read on public.dispute_session_participants;
create policy dispute_session_participants_read on public.dispute_session_participants for select to authenticated using(
 employee_id=public.current_employee_id() or exists(select 1 from public.dispute_sessions s where s.id=session_id and public.can_access_dispute(s.case_id))
);
drop policy if exists dispute_settlements_read on public.dispute_settlements;
create policy dispute_settlements_read on public.dispute_settlements for select to authenticated using(public.can_access_dispute(case_id));
drop policy if exists dispute_decision_receipts_read on public.dispute_decision_receipts;
create policy dispute_decision_receipts_read on public.dispute_decision_receipts for select to authenticated using(
 employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('disputes.case.read_all')
);

revoke insert,update,delete on public.dispute_parties,public.dispute_statements,public.dispute_session_participants,public.dispute_settlements,public.dispute_decision_receipts from authenticated;

-- Private evidence bucket. Object names are case-id/random-name.ext.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('dispute-evidence','dispute-evidence',false,15728640,array[
 'application/pdf','image/jpeg','image/png','image/webp',
 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'audio/mpeg','audio/mp4','video/mp4','text/plain'
])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists dispute_evidence_storage_read on storage.objects;
create policy dispute_evidence_storage_read on storage.objects for select to authenticated using(
 bucket_id='dispute-evidence' and exists(
  select 1 from public.dispute_evidence e
  where e.storage_path=name and e.deleted_at is null and (
   public.current_is_full_access() or public.has_permission('disputes.case.read_all')
   or e.submitted_by=public.current_employee_id()
   or exists(select 1 from public.committee_members cm where cm.case_id=e.case_id and cm.employee_id=public.current_employee_id() and cm.is_active)
   or (e.visibility='parties' and public.can_access_dispute(e.case_id))
  )
 )
);
drop policy if exists dispute_evidence_storage_insert on storage.objects;
create policy dispute_evidence_storage_insert on storage.objects for insert to authenticated with check(
 bucket_id='dispute-evidence' and exists(
  select 1 from public.dispute_cases c
  where (storage.foldername(name))[1]=c.id::text and (
   c.actor_employee_id=public.current_employee_id() or public.current_is_full_access()
   or exists(select 1 from public.committee_members cm where cm.case_id=c.id and cm.employee_id=public.current_employee_id() and cm.is_active)
  )
 )
);
drop policy if exists dispute_evidence_storage_delete on storage.objects;
create policy dispute_evidence_storage_delete on storage.objects for delete to authenticated using(
 bucket_id='dispute-evidence' and public.current_is_full_access()
);

-- ---------------------------------------------------------------------------
-- Deduplicated notifications.
-- ---------------------------------------------------------------------------

create unique index if not exists ux_dispute_notification_event
on public.notifications(recipient_employee_id,entity_id,(metadata->>'eventKey'))
where category='dispute' and metadata ? 'eventKey';

create or replace function public.enqueue_dispute_notification(
 p_case_id uuid,p_recipient_employee_id uuid,p_event_key text,p_title text,p_body text,
 p_priority text default 'normal',p_action_url text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_id uuid;
begin
 select user_id into v_user from public.employees where id=p_recipient_employee_id and is_active and not is_deleted;
 if v_user is null then return null; end if;
 insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,metadata,created_by)
 values(v_user,p_recipient_employee_id,p_title,p_body,'dispute',p_priority,coalesce(p_action_url,'/admin/disputes?case='||p_case_id::text),'dispute_case',p_case_id,jsonb_build_object('eventKey',p_event_key,'caseId',p_case_id,'mobileRoute','disputes'),auth.uid())
 on conflict(recipient_employee_id,entity_id,(metadata->>'eventKey')) where category='dispute' and metadata ? 'eventKey' do nothing
 returning id into v_id;
 return v_id;
end $$;

create or replace function public.notify_dispute_admins(p_case_id uuid,p_event_key text,p_title text,p_body text,p_priority text default 'normal')
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid;
begin
 for v_emp in
  select distinct e.id from public.employees e
  join public.user_roles ur on ur.user_id=e.user_id and ur.effective_from<=now() and (ur.effective_to is null or ur.effective_to>now())
  join public.roles r on r.id=ur.role_id
  where e.is_active and not e.is_deleted and (r.slug='executive-secretary' or r.is_full_access)
 loop
  perform public.enqueue_dispute_notification(p_case_id,v_emp,p_event_key,p_title,p_body,p_priority);
 end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Intake directory and submission.
-- ---------------------------------------------------------------------------

create or replace function public.get_dispute_participant_directory(p_search text default null,p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'name',q.full_name_ar,'employeeCode',q.employee_code,'department',q.department
 ) order by q.full_name_ar),'[]'::jsonb)
 from (
  select e.id,e.full_name_ar,e.employee_code,d.name department
  from public.employees e left join public.departments d on d.id=e.department_id
  where e.status='active' and e.is_active and not e.is_deleted
   and e.id is distinct from public.current_employee_id()
   and (coalesce(trim(p_search),'')='' or e.full_name_ar ilike '%'||trim(p_search)||'%' or e.employee_code ilike '%'||trim(p_search)||'%')
  order by e.full_name_ar limit greatest(1,least(coalesce(p_limit,100),200))
 ) q
$$;

create or replace function public.submit_my_dispute(
 p_title text,p_description text,p_case_type text,p_priority text default 'normal',
 p_incident_at timestamptz default null,p_incident_location text default null,
 p_parties jsonb default '[]'::jsonb,p_witnesses jsonb default '[]'::jsonb,
 p_direct_manager_contacted boolean default null,p_amicable_attempted boolean default null,
 p_amicable_result text default null,p_requested_action text default null,
 p_confidential boolean default true,p_truth_confirmed boolean default false,
 p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text; v_item jsonb; v_party uuid; v_first_respondent uuid;
begin
 if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode='42501'; end if;
 if length(trim(coalesce(p_title,'')))<5 or length(trim(coalesce(p_description,'')))<20 then raise exception 'INVALID_CASE' using errcode='22023'; end if;
 if not p_truth_confirmed or not p_confidentiality_accepted then raise exception 'REQUIRED_CONFIRMATIONS_MISSING' using errcode='22023'; end if;
 if p_case_type not in ('employee_conflict','inappropriate_conduct','verbal_abuse','management_chain','direct_manager','department_conflict','misunderstanding','work_environment','donor_beneficiary','administrative_violation','agreement_breach','other') then raise exception 'INVALID_CASE_TYPE' using errcode='22023'; end if;
 if p_priority not in ('normal','urgent') then raise exception 'EMPLOYEE_PRIORITY_NOT_ALLOWED' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_parties,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_witnesses,'[]'::jsonb))<>'array' then raise exception 'INVALID_PARTIES' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(p_parties,'[]'::jsonb))=0 then raise exception 'AT_LEAST_ONE_PARTY_REQUIRED' using errcode='22023'; end if;

 v_number:='CASE-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_cases(case_number,title,description,case_type,status,severity,actor_employee_id,is_confidential,privacy_level,opened_at,
  incident_at,incident_location,requested_action,witnesses_present,direct_manager_contacted,amicable_resolution_attempted,amicable_resolution_result,
  truth_confirmed,confidentiality_accepted,review_due_at,created_by)
 values(v_number,trim(p_title),trim(p_description),p_case_type,'submitted',p_priority,v_emp,p_confidential,'restricted',now(),
  p_incident_at,nullif(trim(p_incident_location),''),nullif(trim(p_requested_action),''),jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb))>0,
  p_direct_manager_contacted,p_amicable_attempted,nullif(trim(p_amicable_result),''),true,true,now()+interval '24 hours',auth.uid()) returning id into v_id;

 insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,notified_at,created_by)
 values(v_id,v_emp,'complainant','read',now(),auth.uid());

 for v_item in select * from jsonb_array_elements(coalesce(p_parties,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_PARTY' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,case when coalesce(v_item->>'type','respondent') in ('respondent','related') then coalesce(v_item->>'type','respondent') else 'respondent' end,'withheld',auth.uid())
  on conflict(case_id,employee_id,party_type) do nothing;
  if v_first_respondent is null and coalesce(v_item->>'type','respondent')='respondent' then v_first_respondent=v_party; end if;
 end loop;
 for v_item in select * from jsonb_array_elements(coalesce(p_witnesses,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_WITNESS' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,'witness','withheld',auth.uid()) on conflict(case_id,employee_id,party_type) do nothing;
 end loop;
 update public.dispute_cases set respondent_employee_id=v_first_respondent where id=v_id;
 insert into public.dispute_actions(case_id,action_type,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(v_id,'submit','submitted','تم تقديم المشكلة',v_emp,auth.uid(),jsonb_build_object('priority',p_priority));
 perform public.log_audit_event('dispute.submitted','workflow','notice','dispute_cases',v_id,'تقديم مشكلة جديدة',null,jsonb_build_object('caseNumber',v_number,'priority',p_priority));
 perform public.notify_dispute_admins(v_id,'submitted','مشكلة جديدة تنتظر المراجعة',v_number||' — '||trim(p_title),case when p_priority='urgent' then 'urgent' else 'high' end);
 return v_id;
end $$;

-- Compatibility entrypoint used by older clients.
create or replace function public.create_my_dispute(p_title text,p_description text,p_case_type text default 'other',p_respondent_employee_id uuid default null,p_severity text default 'normal',p_confidential boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return public.submit_my_dispute(p_title,p_description,
  case p_case_type when 'conflict' then 'employee_conflict' when 'harassment' then 'inappropriate_conduct' when 'misconduct' then 'administrative_violation' else 'other' end,
  case when p_severity in ('urgent','high') then 'urgent' else 'normal' end,
  null,null,case when p_respondent_employee_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('employeeId',p_respondent_employee_id,'type','respondent')) end,
  '[]'::jsonb,null,null,null,'متابعة المشكلة واتخاذ الإجراء المناسب',p_confidential,true,true);
end $$;

create or replace function public.cancel_my_dispute(p_case_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 if v.actor_employee_id<>public.current_employee_id() or v.status not in ('draft','submitted') or v.accepted_at is not null then raise exception 'CANNOT_CANCEL' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
 update public.dispute_cases set status='cancelled_by_employee',cancelled_at=now(),cancellation_reason=trim(p_reason),updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id)
 values(p_case_id,'cancel_by_employee',v.status,'cancelled_by_employee',trim(p_reason),public.current_employee_id(),auth.uid());
 perform public.log_audit_event('dispute.cancelled_by_employee','workflow','notice','dispute_cases',p_case_id,'إلغاء المشكلة قبل قبولها',trim(p_reason));
end $$;

-- ---------------------------------------------------------------------------
-- Controlled workflow transitions and the 24-hour SLA.
-- ---------------------------------------------------------------------------

create or replace function public.transition_dispute_case(p_case_id uuid,p_action text,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases; v_next text; v_target uuid; v_priority text; v_role_ok boolean;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 v_role_ok:=public.current_is_full_access() or public.has_permission('disputes.case.transition');
 if p_action in ('escalate','return_to_committee') then v_role_ok:=v_role_ok or public.has_permission('disputes.case.escalate') or public.has_permission('disputes.executive.manage'); end if;
 if not v_role_ok then raise exception 'FORBIDDEN' using errcode='42501'; end if;

 v_next:=case p_action
  when 'request_more_information' then 'needs_more_information'
  when 'accept' then 'accepted'
  when 'reject' then 'rejected'
  when 'start_review' then 'under_review'
  when 'request_respondent_statement' then 'waiting_for_respondent'
  when 'request_witness_statement' then 'waiting_for_witness'
  when 'start_deliberation' then 'committee_deliberation'
  when 'settlement_pending' then 'settlement_pending'
  when 'escalate' then 'escalated_to_executive'
  when 'return_to_committee' then 'returned_to_committee'
  when 'close' then 'closed'
  when 'reopen' then 'reopened'
  when 'force_status' then p_metadata->>'status'
  else null end;

 if p_action='extend_review' then
  if v.status not in ('submitted','needs_more_information') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'EXTENSION_NOT_ALLOWED' using errcode='22023'; end if;
  update public.dispute_cases set review_due_at=greatest(coalesce(review_due_at,now()),now())+interval '24 hours',review_extended_at=now(),review_extension_reason=trim(p_reason),updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id) values(p_case_id,'extend_review',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid());
  perform public.log_audit_event('dispute.review_extended','workflow','warning','dispute_cases',p_case_id,'تمديد مهلة مراجعة المشكلة',trim(p_reason));
  return v.status;
 end if;

 if p_action='change_priority' then
  v_priority=p_metadata->>'priority';
  if v_priority not in ('normal','urgent','critical') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'INVALID_PRIORITY_CHANGE' using errcode='22023'; end if;
  update public.dispute_cases set severity=v_priority,updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata) values(p_case_id,'change_priority',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid(),jsonb_build_object('from',v.severity,'to',v_priority));
  perform public.log_audit_event('dispute.priority_changed','workflow','warning','dispute_cases',p_case_id,'تغيير أولوية المشكلة',trim(p_reason),jsonb_build_object('from',v.severity,'to',v_priority));
  return v.status;
 end if;

 if v_next is null then raise exception 'UNKNOWN_ACTION' using errcode='22023'; end if;
 if p_action='request_more_information' and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('accept','reject') and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action='start_review' and v.status not in ('accepted','reopened','returned_to_committee') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('request_respondent_statement','request_witness_statement') and v.status not in ('accepted','under_review','waiting_for_respondent','waiting_for_witness') then raise exception 'INVALID_STATE'; end if;
 if p_action='close' then
  if v.status not in ('decision_issued','settlement_pending') then raise exception 'CLOSE_NOT_ALLOWED'; end if;
  if exists(select 1 from public.dispute_actions where case_id=p_case_id and execution_status in ('pending','in_progress','failed')) or exists(select 1 from public.dispute_settlements where case_id=p_case_id and status='pending') then raise exception 'PENDING_IMPLEMENTATION'; end if;
 end if;
 if p_action='force_status' and (not public.current_is_full_access() or v_next not in ('submitted','needs_more_information','accepted','rejected','under_review','waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed','committee_deliberation','settlement_pending','escalated_to_executive','returned_to_committee','decision_issued','closed','reopened','cancelled_by_employee')) then raise exception 'INVALID_FORCE_STATUS'; end if;
 if p_action in ('reject','request_more_information','escalate','return_to_committee','close','reopen','force_status') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;

 if p_action='accept' then
  update public.dispute_cases set accepted_at=coalesce(accepted_at,now()),accepted_by=public.current_employee_id(),decision_due_at=coalesce(decision_due_at,now()+interval '7 days') where id=p_case_id;
 elsif p_action in ('request_respondent_statement','request_witness_statement') then
  v_target=(p_metadata->>'employeeId')::uuid;
  update public.dispute_parties set notification_status='notified',notified_at=coalesce(notified_at,now()),statement_requested_at=now(),updated_at=now()
  where case_id=p_case_id and employee_id=v_target and party_type=case when p_action='request_witness_statement' then 'witness' else 'respondent' end;
  if not found then raise exception 'PARTY_NOT_FOUND' using errcode='P0002'; end if;
  update public.dispute_cases set shareable_summary=coalesce(nullif(trim(p_metadata->>'summary'),''),shareable_summary,'توجد مشكلة تتطلب إفادتك'),respondent_notified_at=case when p_action='request_respondent_statement' then coalesce(respondent_notified_at,now()) else respondent_notified_at end where id=p_case_id;
  perform public.enqueue_dispute_notification(p_case_id,v_target,p_action||':'||v_target::text,
   case when p_action='request_witness_statement' then 'طلب إفادة شاهد' else 'طلب إفادة بشأن مشكلة' end,
   coalesce(nullif(trim(p_metadata->>'summary'),''),'يرجى فتح قسم الشكاوى وتقديم إفادتك.'),'high');
 elsif p_action='escalate' then
  update public.dispute_cases set escalated_at=now(),escalated_by=public.current_employee_id() where id=p_case_id;
  for v_target in select distinct e.id from public.employees e join public.user_roles ur on ur.user_id=e.user_id join public.roles r on r.id=ur.role_id where r.slug='executive-director' and ur.effective_from<=now() and (ur.effective_to is null or ur.effective_to>now()) loop
   perform public.enqueue_dispute_notification(p_case_id,v_target,'escalated:'||v_target::text,'قضية مصعدة للمدير التنفيذي',coalesce(trim(p_reason),'تتطلب مراجعة تنفيذية'),'urgent');
  end loop;
 elsif p_action='close' then
  update public.dispute_cases set closed_at=now(),closed_by=public.current_employee_id(),closure_reason=trim(p_reason) where id=p_case_id;
 elsif p_action='reopen' then
  update public.dispute_cases set reopened_at=now(),closed_at=null,closed_by=null where id=p_case_id;
 end if;

 update public.dispute_cases set status=v_next,updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,p_action,v.status,v_next,nullif(trim(p_reason),''),public.current_employee_id(),auth.uid(),coalesce(p_metadata,'{}'::jsonb));
 perform public.log_audit_event('dispute.'||p_action,'workflow',case when p_action in ('escalate','force_status') then 'warning' else 'notice' end,'dispute_cases',p_case_id,'تغيير مسار المشكلة',p_reason,jsonb_build_object('from',v.status,'to',v_next));

 if v.actor_employee_id is not null and p_action in ('accept','reject','request_more_information','escalate','return_to_committee','close','reopen') then
  perform public.enqueue_dispute_notification(p_case_id,v.actor_employee_id,p_action||':actor',
   case p_action when 'accept' then 'تم قبول المشكلة للدراسة' when 'reject' then 'تم رفض المشكلة شكليًا' when 'request_more_information' then 'مطلوب استكمال بيانات المشكلة' when 'escalate' then 'تم تصعيد المشكلة' when 'return_to_committee' then 'أعيدت المشكلة إلى اللجنة' when 'close' then 'تم إغلاق المشكلة' else 'أعيد فتح المشكلة' end,
   coalesce(nullif(trim(p_reason),''),'يمكنك متابعة الحالة من قسم الشكاوى.'),case when p_action in ('reject','request_more_information') then 'high' else 'normal' end);
 end if;
 return v_next;
end $$;

create or replace function public.accept_dispute_case(p_case_id uuid,p_assigned_to uuid,p_quorum integer default 2,p_due_at timestamptz default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['disputes.case.accept','disputes.case.transition'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if not exists(select 1 from public.employees where id=p_assigned_to and status='active' and is_active and not is_deleted) then raise exception 'INVALID_ASSIGNEE'; end if;
 perform public.transition_dispute_case(p_case_id,'accept',null,'{}'::jsonb);
 update public.dispute_cases set assigned_to=p_assigned_to,committee_quorum=greatest(p_quorum,1),decision_due_at=coalesce(p_due_at,now()+interval '7 days'),updated_at=now() where id=p_case_id;
end $$;

-- ---------------------------------------------------------------------------
-- Committee, statements, evidence, sessions and minutes.
-- ---------------------------------------------------------------------------

create or replace function public.set_dispute_committee(p_case_id uuid,p_members jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item jsonb; v_emp uuid; v_role text; v_status text; v_voters integer;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.committee.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then raise exception 'COMMITTEE_TOO_SMALL'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 if v_status not in ('accepted','under_review','returned_to_committee','reopened') then raise exception 'INVALID_STATE'; end if;
 delete from public.committee_members where case_id=p_case_id;
 for v_item in select * from jsonb_array_elements(p_members) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','member');
  if v_role not in ('chair','secretary','member','observer','advisor') then raise exception 'INVALID_COMMITTEE_ROLE'; end if;
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_COMMITTEE_MEMBER'; end if;
  if exists(select 1 from public.dispute_parties where case_id=p_case_id and employee_id=v_emp) then raise exception 'PARTY_CANNOT_JOIN_COMMITTEE'; end if;
  insert into public.committee_members(case_id,committee_name,employee_id,role_in_committee,created_by)
  values(p_case_id,'لجنة حل المشكلات والخلافات',v_emp,v_role,auth.uid());
 end loop;
 if not exists(select 1 from public.committee_members where case_id=p_case_id and role_in_committee='chair') then raise exception 'CHAIR_REQUIRED'; end if;
 select count(*) into v_voters from public.committee_members where case_id=p_case_id and role_in_committee in ('chair','secretary','member') and is_active;
 if (select committee_quorum from public.dispute_cases where id=p_case_id)>v_voters then raise exception 'QUORUM_EXCEEDS_VOTERS'; end if;
 update public.dispute_cases set status='under_review',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'committee_assigned',v_status,'under_review',public.current_employee_id(),auth.uid(),jsonb_build_object('members',jsonb_array_length(p_members)));
 perform public.log_audit_event('dispute.committee_assigned','workflow','notice','dispute_cases',p_case_id,'تشكيل لجنة المشكلة',null,jsonb_build_object('members',jsonb_array_length(p_members)));
end $$;

create or replace function public.submit_dispute_statement(p_case_id uuid,p_statement_type text,p_statement_text text,p_visibility text default 'committee_only')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_case public.dispute_cases; v_party public.dispute_parties; v_id uuid; v_committee boolean;
begin
 if v_emp is null or length(trim(coalesce(p_statement_text,'')))<10 then raise exception 'INVALID_STATEMENT'; end if;
 select * into strict v_case from public.dispute_cases where id=p_case_id for update;
 v_committee:=exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=v_emp and is_active);
 select * into v_party from public.dispute_parties where case_id=p_case_id and employee_id=v_emp order by case when party_type='complainant' then 0 else 1 end limit 1;
 if not v_committee and v_party.id is null then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if not v_committee and v_party.party_type<>'complainant' and v_party.notified_at is null then raise exception 'NOT_NOTIFIED' using errcode='42501'; end if;
 if not v_committee and v_party.party_type='complainant' and v_case.status<>'needs_more_information' and p_statement_type='clarification' then raise exception 'CLARIFICATION_NOT_REQUESTED'; end if;
 if p_statement_type not in ('complainant','respondent','witness','clarification','committee_note','recommendation','executive_note') or p_visibility not in ('committee_only','submitter_and_committee','parties','complainant','respondent') then raise exception 'INVALID_STATEMENT_TYPE'; end if;
 if not v_committee and p_statement_type in ('committee_note','recommendation','executive_note') then raise exception 'FORBIDDEN'; end if;
 insert into public.dispute_statements(case_id,party_id,submitted_by,statement_type,statement_text,visibility,created_by)
 values(p_case_id,v_party.id,v_emp,p_statement_type,trim(p_statement_text),p_visibility,auth.uid()) returning id into v_id;
 if v_party.id is not null then update public.dispute_parties set statement_submitted_at=now(),updated_at=now() where id=v_party.id; end if;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'statement_added',v_case.status,v_case.status,'تمت إضافة إفادة',v_emp,auth.uid(),jsonb_build_object('statementId',v_id,'type',p_statement_type));
 perform public.log_audit_event('dispute.statement_added','data','notice','dispute_statements',v_id,'إضافة إفادة للمشكلة',null,jsonb_build_object('caseId',p_case_id,'type',p_statement_type));
 perform public.notify_dispute_admins(p_case_id,'statement:'||v_id::text,'إفادة جديدة في مشكلة',coalesce(v_case.case_number,'')||' — تمت إضافة إفادة جديدة','normal');
 return v_id;
end $$;

create or replace function public.register_dispute_evidence(p_case_id uuid,p_title text,p_storage_path text,p_mime_type text,p_file_size_bytes bigint,p_visibility text default 'committee_only',p_description text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
 if not public.can_access_dispute(p_case_id) or length(trim(coalesce(p_title,'')))<2 or p_file_size_bytes<=0 or p_file_size_bytes>15728640 then raise exception 'INVALID_EVIDENCE'; end if;
 if split_part(p_storage_path,'/',1)<>p_case_id::text or p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','audio/mpeg','audio/mp4','video/mp4','text/plain') then raise exception 'INVALID_EVIDENCE_FILE'; end if;
 if p_visibility not in ('committee_only','submitter_and_committee','parties') then raise exception 'INVALID_VISIBILITY'; end if;
 insert into public.dispute_evidence(case_id,evidence_type,title,description,storage_path,mime_type,file_size_bytes,submitted_by,visibility,is_confidential,created_by)
 values(p_case_id,case when p_mime_type like 'image/%' then 'photo' when p_mime_type like 'audio/%' then 'audio' when p_mime_type like 'video/%' then 'video' else 'document' end,trim(p_title),nullif(trim(p_description),''),p_storage_path,p_mime_type,p_file_size_bytes,v_emp,p_visibility,p_visibility<>'parties',auth.uid()) returning id into v_id;
 perform public.log_audit_event('dispute.evidence_added','data','notice','dispute_evidence',v_id,'إضافة دليل للمشكلة',null,jsonb_build_object('caseId',p_case_id,'mimeType',p_mime_type));
 return v_id;
end $$;

create or replace function public.schedule_dispute_session_v2(p_case_id uuid,p_type text,p_scheduled_at timestamptz,p_ends_at timestamptz default null,p_location text default null,p_modality text default 'in_person',p_participants jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_emp uuid; v_role text; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_scheduled_at<=now() or (p_ends_at is not null and p_ends_at<=p_scheduled_at) or p_modality not in ('in_person','remote','hybrid') then raise exception 'INVALID_SESSION'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_sessions(case_id,session_type,scheduled_at,ends_at,location,modality,status,created_by)
 values(p_case_id,p_type,p_scheduled_at,p_ends_at,nullif(trim(p_location),''),p_modality,'scheduled',auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','guest');
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_SESSION_PARTICIPANT'; end if;
  insert into public.dispute_session_participants(session_id,employee_id,participant_role,created_by) values(v_id,v_emp,v_role,auth.uid()) on conflict do nothing;
  perform public.enqueue_dispute_notification(p_case_id,v_emp,'session:'||v_id::text,'تم تحديد جلسة للمشكلة','موعد الجلسة: '||to_char(p_scheduled_at at time zone 'Africa/Cairo','YYYY-MM-DD HH24:MI'),'high');
 end loop;
 update public.dispute_cases set status='session_scheduled',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'session_scheduled',v_status,'session_scheduled',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',v_id,'scheduledAt',p_scheduled_at));
 perform public.log_audit_event('dispute.session_scheduled','workflow','notice','dispute_sessions',v_id,'تحديد جلسة للمشكلة',null,jsonb_build_object('caseId',p_case_id));
 return v_id;
end $$;

create or replace function public.schedule_dispute_session(p_case_id uuid,p_type text,p_scheduled_at timestamptz,p_location text default null)
returns uuid language sql security definer set search_path=public,pg_temp as $$
 select public.schedule_dispute_session_v2(p_case_id,p_type,p_scheduled_at,null,p_location,'in_person','[]'::jsonb)
$$;

-- Remove the ambiguous legacy overload before exposing the corrected signature.
drop function if exists public.finalize_dispute_session(uuid,text,text,jsonb);
drop function if exists public.finalize_dispute_session(uuid,text,jsonb,text);

create or replace function public.finalize_dispute_session_v2(p_session_id uuid,p_minutes text,p_attendance jsonb,p_outcome text default null,p_minutes_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.dispute_sessions; v_case public.dispute_cases; v_item jsonb; v_member uuid; v_present integer:=0;
begin
 select * into strict v_session from public.dispute_sessions where id=p_session_id for update;
 select * into strict v_case from public.dispute_cases where id=v_session.case_id for update;
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=v_case.id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_session.status<>'scheduled' or length(trim(coalesce(p_minutes,'')))<20 or jsonb_typeof(p_attendance)<>'array' then raise exception 'INVALID_MINUTES'; end if;
 delete from public.dispute_session_attendance where session_id=p_session_id;
 for v_item in select * from jsonb_array_elements(p_attendance) loop
  v_member=(v_item->>'committeeMemberId')::uuid;
  if not exists(select 1 from public.committee_members cm where cm.id=v_member and cm.case_id=v_case.id and cm.is_active) then raise exception 'INVALID_COMMITTEE_MEMBER' using errcode='22023'; end if;
  insert into public.dispute_session_attendance(session_id,committee_member_id,attendance_status,signed_at,signature_method,created_by)
  values(p_session_id,v_member,coalesce(v_item->>'status','present'),case when coalesce(v_item->>'status','present') in ('present','remote') then now() end,case when coalesce(v_item->>'status','present') in ('present','remote') then 'manual_verified' end,auth.uid());
  if coalesce(v_item->>'status','present') in ('present','remote') then v_present=v_present+1; end if;
 end loop;
 if v_present<v_case.committee_quorum then raise exception 'QUORUM_NOT_MET'; end if;
 update public.dispute_sessions set status='held',held_at=now(),minutes=trim(p_minutes),outcome=nullif(trim(p_outcome),''),minutes_data=coalesce(p_minutes_data,'{}'::jsonb),recommendation=nullif(trim(p_minutes_data->>'recommendation'),''),follow_up_at=nullif(p_minutes_data->>'followUpAt','')::timestamptz,internal_notes=nullif(trim(p_minutes_data->>'internalNotes'),''),updated_at=now() where id=p_session_id;
 update public.dispute_cases set status='committee_deliberation',updated_at=now() where id=v_case.id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(v_case.id,'session_completed',v_case.status,'committee_deliberation',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',p_session_id,'present',v_present));
 perform public.log_audit_event('dispute.session_completed','workflow','notice','dispute_sessions',p_session_id,'حفظ محضر جلسة المشكلة',null,jsonb_build_object('caseId',v_case.id,'present',v_present));
end $$;

create or replace function public.finalize_dispute_session(p_session_id uuid,p_minutes text,p_attendance jsonb,p_outcome text default null)
returns void language sql security definer set search_path=public,pg_temp as $$
 select public.finalize_dispute_session_v2(p_session_id,p_minutes,p_attendance,p_outcome,'{}'::jsonb)
$$;

-- ---------------------------------------------------------------------------
-- Decisions, settlements, implementation and closure.
-- ---------------------------------------------------------------------------

create or replace function public.issue_dispute_decision(p_case_id uuid,p_session_id uuid,p_text text,p_rationale text,p_outcome text,p_owner_id uuid default null,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_case public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.decision.issue') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee='chair' and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_case from public.dispute_cases where id=p_case_id for update;
 if v_case.status not in ('committee_deliberation','session_completed','returned_to_committee','escalated_to_executive') or length(trim(coalesce(p_text,'')))<20 or length(trim(coalesce(p_rationale,'')))<20 then raise exception 'INVALID_DECISION'; end if;
 if not exists(select 1 from public.dispute_sessions s where s.id=p_session_id and s.case_id=p_case_id and s.status='held' and (select count(*) from public.dispute_session_attendance a join public.committee_members cm on cm.id=a.committee_member_id where a.session_id=s.id and a.attendance_status in ('present','remote') and cm.case_id=p_case_id and cm.is_active)>=v_case.committee_quorum) then raise exception 'HELD_SESSION_WITH_QUORUM_REQUIRED'; end if;
 v_number='DEC-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_decisions(case_id,session_id,decision_number,decision_text,party_visible_text,rationale,outcome_type,decision_type,implementation_owner_id,implementation_due_at,requires_implementation,status,approved_at,approved_by,issued_at,created_by)
 values(p_case_id,p_session_id,v_number,trim(p_text),trim(p_text),trim(p_rationale),p_outcome,p_outcome,p_owner_id,p_due_at,p_owner_id is not null or p_due_at is not null,'issued',now(),public.current_employee_id(),now(),auth.uid()) returning id into v_id;
 update public.dispute_cases set status='decision_issued',resolved_at=now(),resolution_summary=trim(p_text),appeal_deadline=now()+interval '7 days',updated_at=now() where id=p_case_id;
 if p_owner_id is not null then
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,assigned_to,due_at,execution_status,visibility,metadata)
  values(p_case_id,'decision_implementation',v_case.status,'decision_issued',trim(p_text),public.current_employee_id(),auth.uid(),p_owner_id,p_due_at,'pending','parties',jsonb_build_object('decisionId',v_id));
  perform public.enqueue_dispute_notification(p_case_id,p_owner_id,'implementation:'||v_id::text,'إجراء مطلوب لتنفيذ قرار','يرجى تنفيذ الإجراء المسند وتسجيل إثبات التنفيذ.',case when p_due_at is not null and p_due_at<now()+interval '48 hours' then 'urgent' else 'high' end);
 else
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
  values(p_case_id,'decision_issued',v_case.status,'decision_issued',trim(p_text),public.current_employee_id(),auth.uid(),jsonb_build_object('decisionId',v_id));
 end if;
 perform public.log_audit_event('dispute.decision_issued','workflow','warning','dispute_decisions',v_id,'إصدار قرار اللجنة',null,jsonb_build_object('caseId',p_case_id,'decisionNumber',v_number));
 perform public.enqueue_dispute_notification(p_case_id,v_case.actor_employee_id,'decision:actor:'||v_id::text,'صدر قرار في المشكلة','يمكنك الاطلاع على القرار وتأكيد استلامه من قسم الشكاوى.','high');
 perform public.enqueue_dispute_notification(p_case_id,dp.employee_id,'decision:party:'||v_id::text,'صدر قرار في المشكلة','يمكنك الاطلاع على الجزء المصرح به من القرار.','high') from public.dispute_parties dp where dp.case_id=p_case_id and dp.party_type in ('respondent','related') and dp.notified_at is not null;
 return v_id;
end $$;

create or replace function public.record_dispute_settlement(p_case_id uuid,p_type text,p_from uuid,p_to uuid,p_text text default null,p_publication_place text default null,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.action.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN'; end if;
 if p_type not in ('verbal_apology','written_apology','group_apology','undertaking','mediation','follow_up','other') then raise exception 'INVALID_SETTLEMENT'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_settlements(case_id,apology_from,apology_to,settlement_type,apology_text,publication_place,due_at,created_by)
 values(p_case_id,p_from,p_to,p_type,nullif(trim(p_text),''),nullif(trim(p_publication_place),''),p_due_at,auth.uid()) returning id into v_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,assigned_to,due_at,execution_status,visibility,metadata)
 values(p_case_id,'settlement_implementation',v_status,'settlement_pending',coalesce(nullif(trim(p_text),''),p_type),public.current_employee_id(),auth.uid(),p_from,p_due_at,'pending','parties',jsonb_build_object('settlementId',v_id));
 update public.dispute_cases set status='settlement_pending',updated_at=now() where id=p_case_id;
 if p_from is not null then perform public.enqueue_dispute_notification(p_case_id,p_from,'settlement:'||v_id::text,'تسوية تنتظر التنفيذ','يرجى تنفيذ التسوية في الموعد المحدد وتسجيل التأكيد.','high'); end if;
 perform public.log_audit_event('dispute.settlement_recorded','workflow','notice','dispute_settlements',v_id,'تسجيل تسوية للمشكلة',null,jsonb_build_object('caseId',p_case_id,'type',p_type));
 return v_id;
end $$;

create or replace function public.complete_dispute_action(p_action_id uuid,p_proof text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_actions; v_settlement uuid;
begin
 select * into strict v from public.dispute_actions where id=p_action_id for update;
 if v.execution_status not in ('pending','in_progress','failed') or not(public.current_is_full_access() or public.has_permission('disputes.action.manage') or v.assigned_to=public.current_employee_id()) then raise exception 'ACTION_COMPLETION_FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_proof,'')))<5 then raise exception 'PROOF_REQUIRED'; end if;
 update public.dispute_actions set execution_status='completed',completion_proof=trim(p_proof),completed_at=now() where id=p_action_id;
 v_settlement=nullif(v.metadata->>'settlementId','')::uuid;
 if v_settlement is not null then update public.dispute_settlements set status='completed',confirmed_by=public.current_employee_id(),completed_at=now(),updated_at=now() where id=v_settlement; end if;
 if nullif(v.metadata->>'decisionId','') is not null and not exists(select 1 from public.dispute_actions where case_id=v.case_id and execution_status in ('pending','in_progress','failed') and id<>p_action_id) then
  update public.dispute_decisions set status='implemented',implemented_at=now(),updated_at=now() where id=(v.metadata->>'decisionId')::uuid;
 end if;
 perform public.log_audit_event('dispute.action_completed','workflow','notice','dispute_actions',p_action_id,'تنفيذ إجراء قرار',trim(p_proof),jsonb_build_object('caseId',v.case_id));
 perform public.notify_dispute_admins(v.case_id,'action-completed:'||p_action_id::text,'تم تنفيذ إجراء في مشكلة','تم تسجيل إثبات التنفيذ، ويمكن مراجعة القضية للإغلاق.','normal');
end $$;

create or replace function public.acknowledge_dispute_decision(p_decision_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_case uuid;
begin
 select case_id into strict v_case from public.dispute_decisions where id=p_decision_id and status in ('issued','implemented');
 if not public.can_access_dispute(v_case) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 insert into public.dispute_decision_receipts(decision_id,employee_id,created_by) values(p_decision_id,v_emp,auth.uid()) on conflict do nothing;
 perform public.log_audit_event('dispute.decision_acknowledged','workflow','info','dispute_decisions',p_decision_id,'تأكيد الاطلاع على القرار');
end $$;

create or replace function public.submit_dispute_appeal(p_decision_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_dec public.dispute_decisions; v_case public.dispute_cases; v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
 select * into strict v_dec from public.dispute_decisions where id=p_decision_id;
 select * into strict v_case from public.dispute_cases where id=v_dec.case_id for update;
 if not exists(select 1 from public.dispute_parties where case_id=v_case.id and employee_id=v_emp and party_type in ('complainant','respondent') and (party_type='complainant' or notified_at is not null)) or now()>v_case.appeal_deadline or length(trim(coalesce(p_reason,'')))<20 then raise exception 'APPEAL_NOT_ALLOWED'; end if;
 insert into public.dispute_appeals(case_id,decision_id,appellant_employee_id,reason,created_by) values(v_case.id,p_decision_id,v_emp,trim(p_reason),auth.uid()) returning id into v_id;
 perform public.notify_dispute_admins(v_case.id,'appeal:'||v_id::text,'اعتراض جديد على قرار',coalesce(v_case.case_number,'')||' — يتطلب مراجعة','high');
 perform public.log_audit_event('dispute.appeal_submitted','workflow','warning','dispute_appeals',v_id,'تقديم اعتراض على القرار',null,jsonb_build_object('caseId',v_case.id));
 return v_id;
end $$;

create or replace function public.decide_dispute_appeal(p_appeal_id uuid,p_decision text,p_resolution text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_appeals; v_case public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.appeal.review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v from public.dispute_appeals where id=p_appeal_id for update;
 select * into strict v_case from public.dispute_cases where id=v.case_id for update;
 if v.status not in ('submitted','under_review') or p_decision not in ('accepted','rejected') or length(trim(coalesce(p_resolution,'')))<10 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 update public.dispute_appeals set status=p_decision,resolution=trim(p_resolution),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then update public.dispute_cases set status='reopened',reopened_at=now(),updated_at=now() where id=v.case_id; end if;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(v.case_id,'appeal_'||p_decision,v_case.status,case when p_decision='accepted' then 'reopened' else v_case.status end,trim(p_resolution),public.current_employee_id(),auth.uid(),jsonb_build_object('appealId',p_appeal_id));
 perform public.enqueue_dispute_notification(v.case_id,v.appellant_employee_id,'appeal-decision:'||p_appeal_id::text,case when p_decision='accepted' then 'تم قبول الاعتراض وإعادة فتح المشكلة' else 'تم رفض الاعتراض' end,trim(p_resolution),'high');
 perform public.log_audit_event('dispute.appeal_'||p_decision,'workflow','warning','dispute_appeals',p_appeal_id,'البت في اعتراض',trim(p_resolution));
end $$;

-- ---------------------------------------------------------------------------
-- Rich committee catalog and privacy-safe employee portal.
-- ---------------------------------------------------------------------------

create or replace function public.get_dispute_operations_catalog(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.portal.access') or public.has_permission('disputes.case.read_all') or exists(select 1 from public.committee_members where employee_id=public.current_employee_id() and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return jsonb_build_object(
  'cases',coalesce((select jsonb_agg(jsonb_build_object(
   'id',c.id,'caseNumber',c.case_number,'title',c.title,'description',c.description,'caseType',c.case_type,'status',c.status,'priority',c.severity,
   'actorId',c.actor_employee_id,'actorName',a.full_name_ar,'actorDepartment',ad.name,
   'respondentId',c.respondent_employee_id,'respondentName',r.full_name_ar,
   'assignedTo',c.assigned_to,'assignedName',ass.full_name_ar,'openedAt',c.opened_at,'updatedAt',c.updated_at,
   'acceptedAt',c.accepted_at,'reviewDueAt',c.review_due_at,'decisionDueAt',c.decision_due_at,'overdue',(c.status in ('submitted','needs_more_information') and c.review_due_at<now()),
   'incidentAt',c.incident_at,'incidentLocation',c.incident_location,'requestedAction',c.requested_action,
   'directManagerContacted',c.direct_manager_contacted,'amicableAttempted',c.amicable_resolution_attempted,'amicableResult',c.amicable_resolution_result,
   'confidential',c.is_confidential,'privacyLevel',c.privacy_level,'quorum',c.committee_quorum,'closureReason',c.closure_reason,
   'parties',coalesce((select jsonb_agg(jsonb_build_object('id',dp.id,'employeeId',dp.employee_id,'name',pe.full_name_ar,'type',dp.party_type,'notificationStatus',dp.notification_status,'notifiedAt',dp.notified_at,'statementSubmittedAt',dp.statement_submitted_at) order by dp.party_type,pe.full_name_ar) from public.dispute_parties dp join public.employees pe on pe.id=dp.employee_id where dp.case_id=c.id),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'employeeId',m.employee_id,'name',me.full_name_ar,'role',m.role_in_committee,'active',m.is_active) order by m.role_in_committee) from public.committee_members m join public.employees me on me.id=m.employee_id where m.case_id=c.id),'[]'::jsonb),
   'statements',coalesce((select jsonb_agg(jsonb_build_object('id',st.id,'submittedBy',st.submitted_by,'submittedByName',se.full_name_ar,'type',st.statement_type,'text',st.statement_text,'visibility',st.visibility,'submittedAt',st.submitted_at) order by st.submitted_at desc) from public.dispute_statements st join public.employees se on se.id=st.submitted_by where st.case_id=c.id),'[]'::jsonb),
   'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',ev.id,'title',ev.title,'description',ev.description,'type',ev.evidence_type,'mimeType',ev.mime_type,'storagePath',ev.storage_path,'visibility',ev.visibility,'submittedAt',ev.submitted_at,'submittedByName',ee.full_name_ar) order by ev.submitted_at desc) from public.dispute_evidence ev left join public.employees ee on ee.id=ev.submitted_by where ev.case_id=c.id and ev.deleted_at is null),'[]'::jsonb),
   'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'type',s.session_type,'scheduledAt',s.scheduled_at,'endsAt',s.ends_at,'heldAt',s.held_at,'status',s.status,'location',s.location,'modality',s.modality,'minutes',s.minutes,'minutesData',s.minutes_data,'outcome',s.outcome,'recommendation',s.recommendation,'followUpAt',s.follow_up_at,
    'attendance',coalesce((select jsonb_agg(jsonb_build_object('committeeMemberId',sa.committee_member_id,'employeeId',cm.employee_id,'name',ae.full_name_ar,'status',sa.attendance_status)) from public.dispute_session_attendance sa join public.committee_members cm on cm.id=sa.committee_member_id join public.employees ae on ae.id=cm.employee_id where sa.session_id=s.id),'[]'::jsonb)) order by s.scheduled_at desc) from public.dispute_sessions s where s.case_id=c.id),'[]'::jsonb),
   'decision',(select jsonb_build_object('id',d.id,'number',d.decision_number,'text',d.decision_text,'rationale',d.rationale,'outcome',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,'ownerId',d.implementation_owner_id,'ownerName',oe.full_name_ar,'dueAt',d.implementation_due_at,'implementedAt',d.implemented_at) from public.dispute_decisions d left join public.employees oe on oe.id=d.implementation_owner_id where d.case_id=c.id order by d.created_at desc limit 1),
   'actions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'type',x.action_type,'note',x.note,'assignedTo',x.assigned_to,'assignedName',xe.full_name_ar,'dueAt',x.due_at,'status',x.execution_status,'proof',x.completion_proof,'completedAt',x.completed_at,'createdAt',x.created_at) order by x.created_at desc) from public.dispute_actions x left join public.employees xe on xe.id=x.assigned_to where x.case_id=c.id and x.execution_status is not null),'[]'::jsonb),
   'settlements',coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'type',z.settlement_type,'fromName',zf.full_name_ar,'toName',zt.full_name_ar,'text',z.apology_text,'publicationPlace',z.publication_place,'dueAt',z.due_at,'status',z.status,'completedAt',z.completed_at) order by z.created_at desc) from public.dispute_settlements z left join public.employees zf on zf.id=z.apology_from left join public.employees zt on zt.id=z.apology_to where z.case_id=c.id),'[]'::jsonb),
   'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'decisionId',ap.decision_id,'appellantId',ap.appellant_employee_id,'appellantName',ape.full_name_ar,'reason',ap.reason,'status',ap.status,'submittedAt',ap.submitted_at,'resolution',ap.resolution) order by ap.submitted_at desc) from public.dispute_appeals ap join public.employees ape on ape.id=ap.appellant_employee_id where ap.case_id=c.id),'[]'::jsonb)
  ) order by case when c.status in ('submitted','needs_more_information') then 0 else 1 end,c.review_due_at,c.opened_at desc)
  from public.dispute_cases c
  left join public.employees a on a.id=c.actor_employee_id left join public.departments ad on ad.id=a.department_id
  left join public.employees r on r.id=c.respondent_employee_id left join public.employees ass on ass.id=c.assigned_to
  where (p_status is null or c.status=p_status) and public.can_access_dispute(c.id)),'[]'::jsonb),
  'summary',jsonb_build_object(
   'new',count(*) filter(where status='submitted'),
   'overdue',count(*) filter(where status in ('submitted','needs_more_information') and review_due_at<now()),
   'urgent',count(*) filter(where severity='urgent' and status not in ('closed','rejected','cancelled_by_employee')),
   'critical',count(*) filter(where severity='critical' and status not in ('closed','rejected','cancelled_by_employee')),
   'waitingStatements',count(*) filter(where status in ('waiting_for_respondent','waiting_for_witness')),
   'escalated',count(*) filter(where status='escalated_to_executive'),
   'pendingExecution',(select count(*) from public.dispute_actions where execution_status in ('pending','in_progress','failed')),
   'closed',count(*) filter(where status='closed'),
   'averageResolutionHours',coalesce(round(avg(extract(epoch from (closed_at-opened_at))/3600) filter(where closed_at is not null)::numeric,1),0)
  ),
  'pendingAppeals',(select count(*) from public.dispute_appeals where status in ('submitted','under_review')),
  'lastUpdatedAt',now()
 ) from public.dispute_cases where public.can_access_dispute(id);
end $$;

create or replace function public.get_my_dispute_portal()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id();
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 return jsonb_build_object(
  'cases',coalesce((select jsonb_agg(jsonb_build_object(
   'id',c.id,'caseNumber',c.case_number,'title',case when c.actor_employee_id=v_emp then c.title else 'طلب إفادة من لجنة حل المشكلات' end,
   'description',case when c.actor_employee_id=v_emp then c.description else c.shareable_summary end,
   'caseType',c.case_type,'status',c.status,'priority',c.severity,'incidentAt',case when c.actor_employee_id=v_emp then c.incident_at else null end,
   'requestedAction',case when c.actor_employee_id=v_emp then c.requested_action else null end,
   'respondentName',case when c.actor_employee_id=v_emp then respondent.full_name_ar else null end,
   'openedAt',c.opened_at,'reviewDueAt',c.review_due_at,'acceptedAt',c.accepted_at,'decisionDueAt',c.decision_due_at,
   'canCancel',(c.actor_employee_id=v_emp and c.status in ('draft','submitted') and c.accepted_at is null),
   'isActor',(c.actor_employee_id=v_emp),
   'requiresStatement',exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.statement_requested_at is not null and dp.statement_submitted_at is null),
   'statementType',(select case dp.party_type when 'respondent' then 'respondent' when 'witness' then 'witness' else 'clarification' end from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.statement_requested_at is not null and dp.statement_submitted_at is null order by dp.statement_requested_at desc limit 1),
   'nextSessionAt',(select min(s.scheduled_at) from public.dispute_sessions s join public.dispute_session_participants sp on sp.session_id=s.id where s.case_id=c.id and sp.employee_id=v_emp and s.status='scheduled' and s.scheduled_at>now()),
   'actions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'type',x.action_type,'note',x.note,'dueAt',x.due_at,'status',x.execution_status,'canComplete',x.assigned_to=v_emp)) from public.dispute_actions x where x.case_id=c.id and x.execution_status is not null and (x.visibility='parties' or x.assigned_to=v_emp)),'[]'::jsonb)
  ) order by c.opened_at desc)
  from public.dispute_cases c left join public.employees respondent on respondent.id=c.respondent_employee_id
  where c.actor_employee_id=v_emp or exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.party_type<>'complainant' and dp.notified_at is not null)),'[]'::jsonb),
  'decisions',coalesce((select jsonb_agg(jsonb_build_object(
   'id',d.id,'caseId',d.case_id,'decisionNumber',d.decision_number,'decisionText',coalesce(d.party_visible_text,d.decision_text),
   'rationale','','outcomeType',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,
   'acknowledged',exists(select 1 from public.dispute_decision_receipts dr where dr.decision_id=d.id and dr.employee_id=v_emp),
   'canAppeal',(now()<=c.appeal_deadline and not exists(select 1 from public.dispute_appeals a where a.decision_id=d.id and a.appellant_employee_id=v_emp))
  ) order by d.issued_at desc) from public.dispute_decisions d join public.dispute_cases c on c.id=d.case_id
   where d.status in ('issued','implemented') and (c.actor_employee_id=v_emp or exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.party_type='respondent' and dp.notified_at is not null))),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'caseId',a.case_id,'decisionId',a.decision_id,'reason',a.reason,'status',a.status,'submittedAt',a.submitted_at,'resolution',a.resolution) order by a.submitted_at desc) from public.dispute_appeals a where a.appellant_employee_id=v_emp),'[]'::jsonb),
  'lastUpdatedAt',now()
 );
end $$;

-- ---------------------------------------------------------------------------
-- SLA alerts. The function is idempotent because notifications use eventKey.
-- ---------------------------------------------------------------------------

create or replace function public.process_dispute_sla(p_limit integer default 500)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_case record; v_count integer:=0;
begin
 for v_case in select id,case_number,title,review_due_at,severity from public.dispute_cases where status in ('submitted','needs_more_information') and review_due_at<=now()+interval '2 hours' order by review_due_at limit greatest(1,least(coalesce(p_limit,500),2000)) loop
  perform public.notify_dispute_admins(v_case.id,case when v_case.review_due_at<=now() then 'sla-overdue' else 'sla-due-soon' end,
   case when v_case.review_due_at<=now() then 'تجاوزت مشكلة مهلة المراجعة' else 'اقترب انتهاء مهلة مراجعة مشكلة' end,
   coalesce(v_case.case_number,'')||' — '||v_case.title,case when v_case.review_due_at<=now() or v_case.severity='critical' then 'urgent' else 'high' end);
  v_count=v_count+1;
 end loop;
 return v_count;
end $$;

do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='hr_dispute_sla';
  perform cron.schedule('hr_dispute_sla','*/15 * * * *',$job$ select public.process_dispute_sla(500); $job$);
 end if;
end $$;

-- ---------------------------------------------------------------------------
-- Execution grants: direct table writes remain revoked; all mutations run via
-- these security-definer workflow functions.
-- ---------------------------------------------------------------------------

revoke all on function public.enqueue_dispute_notification(uuid,uuid,text,text,text,text,text) from public;
revoke all on function public.notify_dispute_admins(uuid,text,text,text,text) from public;
revoke all on function public.process_dispute_sla(integer) from public,authenticated;
grant execute on function public.process_dispute_sla(integer) to service_role;

revoke execute on function public.get_dispute_participant_directory(text,integer) from public;
grant execute on function public.get_dispute_participant_directory(text,integer) to authenticated;
revoke execute on function public.submit_my_dispute(text,text,text,text,timestamptz,text,jsonb,jsonb,boolean,boolean,text,text,boolean,boolean,boolean) from public;
grant execute on function public.submit_my_dispute(text,text,text,text,timestamptz,text,jsonb,jsonb,boolean,boolean,text,text,boolean,boolean,boolean) to authenticated;
revoke execute on function public.transition_dispute_case(uuid,text,text,jsonb) from public;
grant execute on function public.transition_dispute_case(uuid,text,text,jsonb) to authenticated;
revoke execute on function public.submit_dispute_statement(uuid,text,text,text) from public;
grant execute on function public.submit_dispute_statement(uuid,text,text,text) to authenticated;
revoke execute on function public.register_dispute_evidence(uuid,text,text,text,bigint,text,text) from public;
grant execute on function public.register_dispute_evidence(uuid,text,text,text,bigint,text,text) to authenticated;
revoke execute on function public.schedule_dispute_session_v2(uuid,text,timestamptz,timestamptz,text,text,jsonb) from public;
grant execute on function public.schedule_dispute_session_v2(uuid,text,timestamptz,timestamptz,text,text,jsonb) to authenticated;
revoke execute on function public.finalize_dispute_session_v2(uuid,text,jsonb,text,jsonb) from public;
grant execute on function public.finalize_dispute_session_v2(uuid,text,jsonb,text,jsonb) to authenticated;
revoke execute on function public.finalize_dispute_session(uuid,text,jsonb,text) from public;
grant execute on function public.finalize_dispute_session(uuid,text,jsonb,text) to authenticated;
revoke execute on function public.record_dispute_settlement(uuid,text,uuid,uuid,text,text,timestamptz) from public;
grant execute on function public.record_dispute_settlement(uuid,text,uuid,uuid,text,text,timestamptz) to authenticated;
revoke execute on function public.complete_dispute_action(uuid,text) from public;
grant execute on function public.complete_dispute_action(uuid,text) to authenticated;
revoke execute on function public.acknowledge_dispute_decision(uuid) from public;
grant execute on function public.acknowledge_dispute_decision(uuid) to authenticated;

-- Existing compatibility functions keep their authenticated grants.
revoke execute on function public.get_dispute_operations_catalog(text) from public;
grant execute on function public.get_dispute_operations_catalog(text) to authenticated;
revoke execute on function public.get_my_dispute_portal() from public;
grant execute on function public.get_my_dispute_portal() to authenticated;

commit;
