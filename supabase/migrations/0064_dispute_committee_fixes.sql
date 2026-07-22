-- Migration 0064: fixes for the problems & disputes committee workflow (0059).
--
-- 1. P0 — dispute_cases.case_type CHECK was defined inline in 0008 with only the
--    six legacy values (grievance/disciplinary/harassment/conflict/misconduct/
--    other). Migration 0059 rewrote submit_my_dispute to insert twelve new
--    case_type values, so every new submission violates the old CHECK and fails.
--    We drop the legacy CHECK and add a widened, named one matching the RPC.
-- 2. Migration 0059 references five permission codes in RPC bodies and grant
--    statements that were never inserted into public.permissions
--    (disputes.case.accept, disputes.committee.manage, disputes.session.manage,
--    disputes.decision.issue, disputes.appeal.review). Full-access roles (admin
--    and the executive secretary / Main Admin) already pass every check via
--    current_is_full_access(); this closes the gap so committee roles can be
--    granted these capabilities by role instead of only via committee membership.

begin;

-- ---------------------------------------------------------------------------
-- 1. Widen the case_type CHECK on dispute_cases.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  -- Drop any CHECK constraint on dispute_cases that still restricts case_type to
  -- the legacy value set (matched by its definition), regardless of its name.
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'dispute_cases'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%case_type%'
  loop
    execute format('alter table public.dispute_cases drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.dispute_cases
  add constraint dispute_cases_case_type_check
  check (case_type in (
    'employee_conflict','inappropriate_conduct','verbal_abuse','management_chain',
    'direct_manager','department_conflict','misunderstanding','work_environment',
    'donor_beneficiary','administrative_violation','agreement_breach','other',
    -- legacy values retained so historical rows and the create_my_dispute
    -- compatibility wrapper's 'other' fallback never trip the constraint.
    'grievance','disciplinary','harassment','conflict','misconduct'
  ));

-- ---------------------------------------------------------------------------
-- 2. Insert the permission codes 0059 relies on but never created.
-- ---------------------------------------------------------------------------
insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('disputes.case.accept','disputes','case','accept','قبول أو رفض القضايا الواردة','critical',true),
 ('disputes.committee.manage','disputes','committee','manage','تشكيل وإدارة أعضاء اللجنة','critical',true),
 ('disputes.session.manage','disputes','session','manage','جدولة الجلسات وتوثيق المحاضر','sensitive',true),
 ('disputes.decision.issue','disputes','decision','issue','إصدار قرارات اللجنة','critical',true),
 ('disputes.appeal.review','disputes','appeal','review','مراجعة الاعتراضات والبتّ فيها','critical',true)
on conflict(code) do update set
 description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

-- Committee members / chair / secretary drive assigned cases through the
-- workflow. The executive secretary is is_full_access (Main Admin) and needs no
-- explicit rows; the executive director keeps its escalation-review grants.
insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id,p.id,'assigned_cases',p.is_sensitive
from public.roles r
join public.permissions p on p.code = any(array[
 'disputes.portal.access','disputes.case.transition',
 'disputes.statement.manage','disputes.action.manage','disputes.session.manage',
 'disputes.case.accept','disputes.committee.manage','disputes.decision.issue',
 'disputes.appeal.review'
])
where r.slug in ('committee-member','committee-chair','committee-secretary',
                 'operations-manager-1','operations-manager-2')
on conflict(role_id,permission_id,scope) do update set requires_reason=excluded.requires_reason;

commit;
