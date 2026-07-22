-- Migration 0058: official monthly KPI policy, workflow and executive-secretary governance.
-- The server is the only source of truth for scores, attendance deductions and final ratings.

begin;

-- -----------------------------------------------------------------------------
-- Permissions and the main administrator role.
-- -----------------------------------------------------------------------------
insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('performance.kpi.cycle.control','performance','kpi_cycle','control','فتح وإغلاق وتمديد دورة تقييم الأداء','critical',true),
 ('performance.kpi.goal.manage','performance','kpi_goal','manage','إدارة أهداف تقييم الأداء','sensitive',true),
 ('performance.kpi.session.manage','performance','kpi_session','manage','تسجيل جلسة تقييم الموظف والمدير','sensitive',true),
 ('performance.kpi.hr_assess','performance','kpi_hr_assessment','assess','اعتماد درجات HR في تقييم الأداء','sensitive',true),
 ('performance.kpi.score.override','performance','kpi_score','override','تعديل استثنائي موثق لدرجة تقييم الأداء','critical',true),
 ('performance.kpi.policy.manage','performance','kpi_policy','manage','إدارة سياسة تقييم الأداء','critical',true),
 ('performance.kpi.report.read','performance','kpi_report','read','قراءة تقارير تقييم الأداء','sensitive',true)
on conflict(code) do update set
 description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive,updated_at=now();

-- The executive secretary is the main administrator requested by management.
-- current_is_full_access() consequently grants every server permission and all workspaces.
update public.roles
set is_full_access=true,
    description='الأدمن الرئيسي للنظام بصلاحية كاملة، بما فيها إدارة دورات KPI',
    updated_at=now()
where slug='executive-secretary';

create or replace function public.current_is_super_admin()
returns boolean
language sql stable security definer set search_path=public,pg_temp
as $$
 select exists(
  select 1 from public.roles r
  where r.id=any(public.current_role_ids())
    and r.slug in ('admin','super-admin','super_admin','executive-secretary')
    and r.is_full_access=true
 );
$$;

-- -----------------------------------------------------------------------------
-- Versioned official policy. A cycle stores the policy version it used so later
-- rating or deduction changes never rewrite historical results.
-- -----------------------------------------------------------------------------
create table if not exists public.kpi_policy_versions (
 id uuid primary key default gen_random_uuid(),
 version integer not null unique check(version>0),
 name_ar text not null,
 effective_from date not null,
 criteria_weights jsonb not null,
 attendance_rules jsonb not null,
 rating_bands jsonb not null,
 allow_target_overachievement boolean not null default false,
 is_active boolean not null default false,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create unique index if not exists ux_kpi_policy_active on public.kpi_policy_versions(is_active) where is_active;
alter table public.kpi_policy_versions enable row level security;
drop policy if exists kpi_policy_versions_read on public.kpi_policy_versions;
create policy kpi_policy_versions_read on public.kpi_policy_versions for select to authenticated using(true);
revoke insert,update,delete on public.kpi_policy_versions from authenticated;

insert into public.kpi_policy_versions(
 version,name_ar,effective_from,criteria_weights,attendance_rules,rating_bands,allow_target_overachievement,is_active
)
values(
 1,'السياسة الرسمية لتقييم الأداء 100 درجة','2026-01-01',
 '{"TARGET":40,"EFFICIENCY":20,"ATTENDANCE":20,"CONDUCT":5,"PRAYER":5,"HALAQA":5,"INITIATIVES":5}'::jsonb,
 '{"late":1,"earlyLeave":1,"unexcusedAbsence":4,"missingPunch":1,"shortagePerHour":1,"maxShortagePerDay":2}'::jsonb,
 '[{"min":90,"max":100,"label":"ممتاز"},{"min":80,"max":89.9999,"label":"جيد جدًا"},{"min":70,"max":79.9999,"label":"جيد"},{"min":60,"max":69.9999,"label":"مقبول"},{"min":0,"max":59.9999,"label":"يحتاج إلى تحسين"}]'::jsonb,
 false,true
)
on conflict(version) do update set
 name_ar=excluded.name_ar,criteria_weights=excluded.criteria_weights,
 attendance_rules=excluded.attendance_rules,rating_bands=excluded.rating_bands,
 allow_target_overachievement=excluded.allow_target_overachievement,is_active=true;

-- -----------------------------------------------------------------------------
-- Official template and the seven exact score components.
-- -----------------------------------------------------------------------------
alter table public.kpi_templates add column if not exists official_code text;
create unique index if not exists ux_kpi_templates_official_code on public.kpi_templates(official_code) where official_code is not null;

alter table public.kpi_criteria drop constraint if exists kpi_criteria_source_type_check;
alter table public.kpi_criteria drop constraint if exists kpi_criteria_attendance_metric_check;
alter table public.kpi_criteria
 add column if not exists code text,
 add column if not exists section_code text,
 add column if not exists evaluator_stage text,
 add column if not exists calculation_method text;
alter table public.kpi_criteria
 add constraint kpi_criteria_source_type_check check(source_type in ('manual','attendance','goals','compliance')),
 add constraint kpi_criteria_attendance_metric_check check(attendance_metric is null or attendance_metric in ('attendance_rate','punctuality_rate','completion_rate','deduction_policy')),
 add constraint kpi_criteria_evaluator_stage_check check(evaluator_stage is null or evaluator_stage in ('manager','hr','secretary','executive')),
 add constraint kpi_criteria_calculation_method_check check(calculation_method is null or calculation_method in ('manual','goals','attendance','ratio'));
create unique index if not exists ux_kpi_criteria_template_code on public.kpi_criteria(template_id,code) where code is not null;

do $seed_template$
declare v_template uuid;
begin
 insert into public.kpi_templates(name_ar,is_active,version,official_code)
 values('التقييم الشهري الرسمي — 100 درجة',true,1,'OFFICIAL_KPI_100')
 on conflict(official_code) where official_code is not null do update set name_ar=excluded.name_ar,is_active=true
 returning id into v_template;

 update public.kpi_templates set is_active=false,updated_at=now()
 where id<>v_template and is_active=true;

 insert into public.kpi_criteria(
   template_id,code,section_code,name_ar,description,weight,max_score,sort_order,
   source_type,attendance_metric,requires_evidence,evaluator_stage,calculation_method
 ) values
 (v_template,'TARGET','TARGET','تحقيق الأهداف Target','محسوب من الأهداف الشهرية المعتمدة',40,40,1,'goals',null,true,'manager','goals'),
 (v_template,'EFFICIENCY','EFFICIENCY','الكفاءة في أداء المهام','تقييم المدير لجودة وكفاءة تنفيذ المسؤوليات',20,20,2,'manual',null,false,'manager','manual'),
 (v_template,'ATTENDANCE','BEHAVIOR','الالتزام بمواعيد العمل حضورًا وانصرافًا','محسوب آليًا من بيانات الحضور والاستثناءات المعتمدة',20,20,3,'attendance','deduction_policy',false,'hr','attendance'),
 (v_template,'CONDUCT','BEHAVIOR','حسن التعامل والسلوك','تقييم السلوك المهني المثبت',5,5,4,'manual',null,false,'manager','manual'),
 (v_template,'PRAYER','BEHAVIOR','الالتزام بالصلاة في المسجد','نسبة الالتزام بعد استبعاد الأعذار المعتمدة',5,5,5,'compliance',null,false,'hr','ratio'),
 (v_template,'HALAQA','BEHAVIOR','حضور حلقة الشيخ وليد يوسف الأسبوعية','نسبة الحضور بعد استبعاد الأعذار والحلقات الملغاة',5,5,6,'compliance',null,false,'hr','ratio'),
 (v_template,'INITIATIVES','INITIATIVES','المشاركة في التبرعات والمبادرات','تقييم المشاركة وفق طبيعة الوظيفة والفرص المتاحة',5,5,7,'manual',null,true,'manager','manual')
 on conflict(template_id,code) where code is not null do update set
   name_ar=excluded.name_ar,description=excluded.description,weight=excluded.weight,
   max_score=excluded.max_score,sort_order=excluded.sort_order,source_type=excluded.source_type,
   attendance_metric=excluded.attendance_metric,requires_evidence=excluded.requires_evidence,
   evaluator_stage=excluded.evaluator_stage,calculation_method=excluded.calculation_method,updated_at=now();
end
$seed_template$;

-- -----------------------------------------------------------------------------
-- Cycle dates and the expanded official workflow.
-- -----------------------------------------------------------------------------
alter table public.kpi_cycles
 add column if not exists scheduled_open_at timestamptz,
 add column if not exists deadline_at timestamptz,
 add column if not exists extended_until timestamptz,
 add column if not exists policy_version_id uuid references public.kpi_policy_versions(id) on delete restrict,
 add column if not exists override_reason text,
 add column if not exists overridden_at timestamptz,
 add column if not exists overridden_by uuid references public.employees(id) on delete set null;

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_stage_check;
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_current_stage_check;
alter table public.kpi_evaluations
 add constraint kpi_evaluations_stage_check check(stage in ('self','manager','hr','acknowledgement','secretary','executive','finalized','closed')),
 add constraint kpi_evaluations_current_stage_check check(current_stage in ('self','manager','hr','acknowledgement','secretary','executive','finalized','closed'));
alter table public.kpi_evaluations
 add column if not exists workflow_status text not null default 'NOT_STARTED',
 add column if not exists manager_comment text,
 add column if not exists hr_comment text,
 add column if not exists employee_comment text,
 add column if not exists secretary_comment text,
 add column if not exists executive_comment text,
 add column if not exists manager_approved_at timestamptz,
 add column if not exists manager_approved_by uuid references public.employees(id) on delete set null,
 add column if not exists hr_approved_at timestamptz,
 add column if not exists hr_approved_by uuid references public.employees(id) on delete set null,
 add column if not exists employee_acknowledged_at timestamptz,
 add column if not exists secretary_reviewed_at timestamptz,
 add column if not exists executive_approved_at timestamptz,
 add column if not exists rating_policy_snapshot jsonb,
 add column if not exists final_breakdown jsonb;
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_workflow_status_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_workflow_status_check check(workflow_status in (
 'NOT_STARTED','EMPLOYEE_INPUT_IN_PROGRESS','HR_DATA_PENDING','SESSION_SCHEDULED','SESSION_COMPLETED',
 'MANAGER_EVALUATION_IN_PROGRESS','HR_EVALUATION_IN_PROGRESS','EMPLOYEE_ACKNOWLEDGEMENT_PENDING',
 'EMPLOYEE_ACKNOWLEDGED','FINAL_REVIEW','SENT_TO_EXECUTIVE_DIRECTOR','RETURNED_FOR_REVISION',
 'APPROVED','CLOSED','OVERDUE'
));

alter table public.kpi_scores drop constraint if exists kpi_scores_reviewer_stage_check;
alter table public.kpi_scores add constraint kpi_scores_reviewer_stage_check
 check(reviewer_stage in ('self','manager','hr','secretary','executive','finalized'));

drop policy if exists kpi_evaluations_select on public.kpi_evaluations;
create policy kpi_evaluations_select on public.kpi_evaluations for select to authenticated using(
 public.current_is_full_access() or public.can_access_employee(employee_id)
 or public.has_any_permission(array['performance.kpi.hr_review','performance.kpi.hr_assess','performance.kpi.secretary_review','performance.kpi.executive_review','performance.kpi.finalize','performance.kpi.read'])
);

-- All KPI writes must pass through the audited server commands below.
revoke insert,update,delete on public.kpi_cycles,public.kpi_evaluations,public.kpi_scores from authenticated;

update public.kpi_cycles c set
 scheduled_open_at=((date_trunc('month',c.period_month)::date+19)::timestamp at time zone 'Africa/Cairo'),
 deadline_at=(((date_trunc('month',c.period_month)::date+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second'),
 policy_version_id=(select id from public.kpi_policy_versions where is_active limit 1)
where scheduled_open_at is null or deadline_at is null or policy_version_id is null;

-- -----------------------------------------------------------------------------
-- Goals, mandatory review session, HR compliance inputs and attendance snapshot.
-- -----------------------------------------------------------------------------
create table if not exists public.kpi_goals (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null references public.kpi_evaluations(id) on delete cascade,
 title text not null,
 description text,
 target_value numeric(16,2) not null check(target_value>0),
 achieved_value numeric(16,2) not null default 0 check(achieved_value>=0),
 unit text not null,
 weight numeric(6,2) not null check(weight>0 and weight<=40),
 due_date date,
 evidence_source text,
 employee_note text,
 manager_note text,
 status text not null default 'NOT_STARTED' check(status in ('NOT_STARTED','IN_PROGRESS','COMPLETED','PARTIALLY_COMPLETED','BLOCKED','CANCELLED_BY_MANAGEMENT','DEFERRED_WITH_MANAGER_APPROVAL')),
 calculated_score numeric(6,2) not null default 0 check(calculated_score between 0 and 40),
 manager_approved_at timestamptz,
 manager_approved_by uuid references public.employees(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id)
);
create index if not exists ix_kpi_goals_evaluation on public.kpi_goals(evaluation_id);

create table if not exists public.kpi_review_sessions (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null unique references public.kpi_evaluations(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade,
 manager_employee_id uuid not null references public.employees(id) on delete restrict,
 scheduled_at timestamptz,
 held_at timestamptz,
 mode text check(mode in ('ONSITE','REMOTE')),
 discussion_summary text,
 strengths text,
 improvement_points text,
 next_month_goals text,
 employee_notes text,
 manager_notes text,
 employee_attended boolean not null default false,
 manager_attended boolean not null default false,
 employee_confirmed_at timestamptz,
 manager_approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id),
 check(employee_id<>manager_employee_id)
);

create table if not exists public.kpi_compliance_records (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null references public.kpi_evaluations(id) on delete cascade,
 metric text not null check(metric in ('PRAYER','HALAQA')),
 required_count integer not null default 0 check(required_count>=0),
 actual_count integer not null default 0 check(actual_count>=0),
 exempt_count integer not null default 0 check(exempt_count>=0),
 cancelled_count integer not null default 0 check(cancelled_count>=0),
 calculated_score numeric(6,2) not null default 0 check(calculated_score between 0 and 5),
 note text,
 approved_at timestamptz,
 approved_by uuid references public.employees(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz,
 created_by uuid references auth.users(id),
 unique(evaluation_id,metric),
 check(actual_count<=greatest(required_count-exempt_count-cancelled_count,0))
);

create table if not exists public.kpi_attendance_snapshots (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null unique references public.kpi_evaluations(id) on delete cascade,
 period_start date not null,
 period_end date not null,
 late_count integer not null default 0,
 early_leave_count integer not null default 0,
 unexcused_absence_count integer not null default 0,
 shortage_penalty numeric(6,2) not null default 0,
 missing_punch_count integer not null default 0,
 score numeric(6,2) not null check(score between 0 and 20),
 has_pending_items boolean not null default false,
 details jsonb not null default '{}'::jsonb,
 calculated_at timestamptz not null default now(),
 calculated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz
);

create table if not exists public.kpi_notification_receipts (
 id uuid primary key default gen_random_uuid(),
 cycle_id uuid not null references public.kpi_cycles(id) on delete cascade,
 evaluation_id uuid references public.kpi_evaluations(id) on delete cascade,
 event_key text not null,
 recipient_user_id uuid not null references auth.users(id) on delete cascade,
 notification_id uuid references public.notifications(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(cycle_id,event_key,recipient_user_id,evaluation_id)
);
create unique index if not exists ux_kpi_notification_cycle_recipient
 on public.kpi_notification_receipts(cycle_id,event_key,recipient_user_id)
 where evaluation_id is null;

create or replace function public.kpi_can_read_evaluation(p_evaluation_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(
  select 1 from public.kpi_evaluations e where e.id=p_evaluation_id and (
   public.current_is_full_access() or e.employee_id=public.current_employee_id()
   or public.can_access_employee(e.employee_id,'performance.kpi.manager_assess')
   or public.has_any_permission(array['performance.kpi.hr_review','performance.kpi.hr_assess','performance.kpi.secretary_review','performance.kpi.executive_review','performance.kpi.finalize','performance.kpi.read'])
  )
 );
$$;

alter table public.kpi_goals enable row level security;
alter table public.kpi_review_sessions enable row level security;
alter table public.kpi_compliance_records enable row level security;
alter table public.kpi_attendance_snapshots enable row level security;
alter table public.kpi_notification_receipts enable row level security;
drop policy if exists kpi_goals_read on public.kpi_goals;
create policy kpi_goals_read on public.kpi_goals for select to authenticated using(public.kpi_can_read_evaluation(evaluation_id));
drop policy if exists kpi_sessions_read on public.kpi_review_sessions;
create policy kpi_sessions_read on public.kpi_review_sessions for select to authenticated using(public.kpi_can_read_evaluation(evaluation_id));
drop policy if exists kpi_compliance_read on public.kpi_compliance_records;
create policy kpi_compliance_read on public.kpi_compliance_records for select to authenticated using(public.kpi_can_read_evaluation(evaluation_id));
drop policy if exists kpi_attendance_snapshot_read on public.kpi_attendance_snapshots;
create policy kpi_attendance_snapshot_read on public.kpi_attendance_snapshots for select to authenticated using(public.kpi_can_read_evaluation(evaluation_id));
drop policy if exists kpi_notification_receipts_read on public.kpi_notification_receipts;
create policy kpi_notification_receipts_read on public.kpi_notification_receipts for select to authenticated using(public.current_is_full_access() or recipient_user_id=auth.uid());
revoke insert,update,delete on public.kpi_goals,public.kpi_review_sessions,public.kpi_compliance_records,public.kpi_attendance_snapshots,public.kpi_notification_receipts from authenticated;

-- Full row snapshots provide old/new values in addition to semantic audit events.
do $audit_triggers$
declare v_table text;
begin
 foreach v_table in array array['kpi_policy_versions','kpi_cycles','kpi_evaluations','kpi_scores','kpi_goals','kpi_review_sessions','kpi_compliance_records','kpi_attendance_snapshots','kpi_appeals']
 loop
  execute format('drop trigger if exists %I on public.%I','trg_'||v_table||'_audit',v_table);
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row_change()','trg_'||v_table||'_audit',v_table);
 end loop;
end
$audit_triggers$;

-- -----------------------------------------------------------------------------
-- Shared calculations.
-- -----------------------------------------------------------------------------
create or replace function public.tg_calculate_kpi_goal_score()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare v_allow boolean:=false;
begin
 select coalesce(p.allow_target_overachievement,false) into v_allow
 from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id
 join public.kpi_policy_versions p on p.id=c.policy_version_id where e.id=new.evaluation_id;
 -- The TARGET section is capped at 40 in total, so a single goal's stored score
-- can never exceed 40 even when the overachievement policy lets it beat its own
-- weight; without this cap an overachieved goal would violate the 0..40 CHECK and
-- abort save_kpi_goal.
 new.calculated_score:=least(round(
  case when new.status='CANCELLED_BY_MANAGEMENT' then 0
       when v_allow then new.achieved_value/nullif(new.target_value,0)*new.weight
       else least(new.achieved_value/nullif(new.target_value,0),1)*new.weight end,2),40);
 new.updated_at:=now();
 return new;
end $$;
drop trigger if exists trg_kpi_goal_score on public.kpi_goals;
create trigger trg_kpi_goal_score before insert or update of target_value,achieved_value,weight,status on public.kpi_goals
for each row execute function public.tg_calculate_kpi_goal_score();

create or replace function public.kpi_effective_deadline(p_cycle public.kpi_cycles)
returns timestamptz language sql immutable as $$ select coalesce(p_cycle.extended_until,p_cycle.deadline_at) $$;

create or replace function public.kpi_effective_score(p_evaluation_id uuid,p_criterion_id uuid)
returns numeric language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(
  max(score) filter(where reviewer_stage='secretary'),
  max(score) filter(where reviewer_stage='executive'),
  max(score) filter(where reviewer_stage='hr'),
  max(score) filter(where reviewer_stage='manager')
 ) from public.kpi_scores where evaluation_id=p_evaluation_id and criterion_id=p_criterion_id;
$$;

create or replace function public.tg_kpi_stage_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order text[]:=array['self','manager','hr','acknowledgement','secretary','executive','finalized','closed'];
begin
 if new.current_stage is distinct from old.current_stage then
  insert into public.kpi_stage_history(evaluation_id,from_stage,to_stage,action,actor_employee_id,actor_user_id)
  values(new.id,old.current_stage,new.current_stage,
   case when coalesce(array_position(v_order,new.current_stage),0)>coalesce(array_position(v_order,old.current_stage),0) then 'advance' else 'return' end,
   public.current_employee_id(),auth.uid());
 end if;
 return new;
end $$;

create or replace function public.kpi_total_score(p_evaluation_id uuid)
returns numeric language sql stable security definer set search_path=public,pg_temp as $$
 select round(coalesce(sum(public.kpi_effective_score(e.id,c.id)),0),2)
 from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id
 where e.id=p_evaluation_id;
$$;

create or replace function public.kpi_rating_for_score(p_policy_id uuid,p_score numeric)
returns text language sql stable security definer set search_path=public,pg_temp as $$
 select band->>'label' from public.kpi_policy_versions p,
 lateral jsonb_array_elements(p.rating_bands) band
 where p.id=p_policy_id and p_score between (band->>'min')::numeric and (band->>'max')::numeric
 order by (band->>'min')::numeric desc limit 1;
$$;

create or replace function public.create_kpi_policy_version(
 p_name text,p_attendance_rules jsonb,p_rating_bands jsonb,p_allow_target_overachievement boolean default false,p_effective_from date default current_date
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_version integer; v_weights jsonb:='{"TARGET":40,"EFFICIENCY":20,"ATTENDANCE":20,"CONDUCT":5,"PRAYER":5,"HALAQA":5,"INITIATIVES":5}'::jsonb; v_key text;
begin
 if not(public.current_is_full_access() or public.has_permission('performance.kpi.policy.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_name,'')))<3 or jsonb_typeof(p_attendance_rules)<>'object' or jsonb_typeof(p_rating_bands)<>'array' or jsonb_array_length(p_rating_bands)<1 then raise exception 'INVALID_KPI_POLICY'; end if;
 foreach v_key in array array['late','earlyLeave','unexcusedAbsence','missingPunch','shortagePerHour','maxShortagePerDay'] loop
  if not(p_attendance_rules?v_key) or (p_attendance_rules->>v_key)::numeric<0 then raise exception 'INVALID_ATTENDANCE_RULE_%',v_key; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_rating_bands) b where (b->>'min')::numeric<0 or (b->>'max')::numeric>100 or (b->>'min')::numeric>(b->>'max')::numeric or nullif(trim(b->>'label'),'') is null) then raise exception 'INVALID_RATING_BANDS'; end if;
 select coalesce(max(version),0)+1 into v_version from public.kpi_policy_versions;
 update public.kpi_policy_versions set is_active=false where is_active;
 insert into public.kpi_policy_versions(version,name_ar,effective_from,criteria_weights,attendance_rules,rating_bands,allow_target_overachievement,is_active,created_by)
 values(v_version,trim(p_name),coalesce(p_effective_from,current_date),v_weights,p_attendance_rules,p_rating_bands,coalesce(p_allow_target_overachievement,false),true,auth.uid()) returning id into v_id;
 perform public.log_audit_event('kpi.policy.version_created','workflow','warning','kpi_policy_versions',v_id,'إنشاء إصدار جديد من سياسة KPI',null,jsonb_build_object('version',v_version,'attendanceRules',p_attendance_rules,'ratingBands',p_rating_bands,'allowTargetOverachievement',p_allow_target_overachievement));
 return v_id;
end $$;

-- -----------------------------------------------------------------------------
-- Goal, session and HR input commands. Direct table writes remain blocked.
-- -----------------------------------------------------------------------------
create or replace function public.save_kpi_goal(
 p_evaluation_id uuid,p_goal_id uuid,p_title text,p_description text,p_target_value numeric,
 p_achieved_value numeric,p_unit text,p_weight numeric,p_due_date date,p_evidence_source text,
 p_employee_note text,p_manager_note text,p_status text
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_id uuid; v_owner boolean; v_manager boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 v_owner:=v_eval.employee_id=public.current_employee_id();
 v_manager:=public.current_is_full_access() or public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess');
 if v_eval.locked then raise exception 'EVALUATION_LOCKED'; end if;
 if p_status not in ('NOT_STARTED','IN_PROGRESS','COMPLETED','PARTIALLY_COMPLETED','BLOCKED','CANCELLED_BY_MANAGEMENT','DEFERRED_WITH_MANAGER_APPROVAL') then raise exception 'INVALID_GOAL_STATUS'; end if;
 if v_manager then
  if length(trim(coalesce(p_title,'')))<3 or p_target_value<=0 or p_achieved_value<0 or p_weight<=0 or p_weight>40 then raise exception 'INVALID_GOAL'; end if;
  if p_goal_id is null then
   insert into public.kpi_goals(evaluation_id,title,description,target_value,achieved_value,unit,weight,due_date,evidence_source,employee_note,manager_note,status,created_by)
   values(p_evaluation_id,trim(p_title),p_description,p_target_value,p_achieved_value,trim(p_unit),p_weight,p_due_date,p_evidence_source,p_employee_note,p_manager_note,p_status,auth.uid()) returning id into v_id;
  else
   update public.kpi_goals set title=trim(p_title),description=p_description,target_value=p_target_value,achieved_value=p_achieved_value,unit=trim(p_unit),weight=p_weight,due_date=p_due_date,evidence_source=p_evidence_source,employee_note=p_employee_note,manager_note=p_manager_note,status=p_status
   where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
  end if;
 elsif v_owner and v_eval.current_stage='self' and p_goal_id is not null then
  update public.kpi_goals set achieved_value=p_achieved_value,evidence_source=p_evidence_source,employee_note=p_employee_note,status=p_status
  where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_id is null then raise exception 'GOAL_NOT_FOUND'; end if;
 -- When the employee first records input at the self stage, reflect that the
 -- self-input phase is under way (spec workflow state).
 if v_owner and v_eval.current_stage='self' and v_eval.workflow_status='NOT_STARTED' then
  update public.kpi_evaluations set workflow_status='EMPLOYEE_INPUT_IN_PROGRESS',updated_at=now() where id=p_evaluation_id;
 end if;
 perform public.log_audit_event('kpi.goal.saved','workflow','info','kpi_goals',v_id,'حفظ هدف تقييم الأداء',null,jsonb_build_object('evaluationId',p_evaluation_id,'status',p_status));
 return v_id;
end $$;

create or replace function public.save_kpi_review_session(p_evaluation_id uuid,p_session jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_manager uuid; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select mr.manager_employee_id into v_manager from public.manager_relations mr
 where mr.employee_id=v_eval.employee_id and mr.relation_type='primary'
 and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) limit 1;
 if v_manager is null then raise exception 'DIRECT_MANAGER_NOT_ASSIGNED'; end if;
 if not(public.current_is_full_access() or (public.current_employee_id()=v_manager and public.has_permission('performance.kpi.manager_assess'))) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if coalesce(p_session->>'mode','') not in ('ONSITE','REMOTE') then raise exception 'INVALID_SESSION_MODE'; end if;
 insert into public.kpi_review_sessions(evaluation_id,employee_id,manager_employee_id,scheduled_at,held_at,mode,discussion_summary,strengths,improvement_points,next_month_goals,employee_notes,manager_notes,employee_attended,manager_attended,manager_approved_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,v_manager,nullif(p_session->>'scheduledAt','')::timestamptz,nullif(p_session->>'heldAt','')::timestamptz,p_session->>'mode',nullif(trim(p_session->>'discussionSummary'),''),nullif(trim(p_session->>'strengths'),''),nullif(trim(p_session->>'improvementPoints'),''),nullif(trim(p_session->>'nextMonthGoals'),''),nullif(trim(p_session->>'employeeNotes'),''),nullif(trim(p_session->>'managerNotes'),''),coalesce((p_session->>'employeeAttended')::boolean,false),coalesce((p_session->>'managerAttended')::boolean,false),case when (p_session->>'heldAt') is not null then now() end,auth.uid())
 on conflict(evaluation_id) do update set scheduled_at=excluded.scheduled_at,held_at=excluded.held_at,mode=excluded.mode,discussion_summary=excluded.discussion_summary,strengths=excluded.strengths,improvement_points=excluded.improvement_points,next_month_goals=excluded.next_month_goals,employee_notes=excluded.employee_notes,manager_notes=excluded.manager_notes,employee_attended=excluded.employee_attended,manager_attended=excluded.manager_attended,manager_approved_at=excluded.manager_approved_at,updated_at=now()
 returning id into v_id;
 update public.kpi_evaluations set workflow_status=case when (p_session->>'heldAt') is null then 'SESSION_SCHEDULED' else 'SESSION_COMPLETED' end,updated_at=now() where id=p_evaluation_id;
 perform public.log_audit_event('kpi.session.saved','workflow','notice','kpi_review_sessions',v_id,'تسجيل جلسة تقييم الموظف والمدير',null,jsonb_build_object('evaluationId',p_evaluation_id,'mode',p_session->>'mode'));
 return v_id;
end $$;

create or replace function public.save_kpi_compliance_metric(
 p_evaluation_id uuid,p_metric text,p_required integer,p_actual integer,p_exempt integer default 0,p_cancelled integer default 0,p_note text default null
)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eligible integer; v_score numeric; v_criterion uuid;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_metric not in ('PRAYER','HALAQA') or least(p_required,p_actual,p_exempt,p_cancelled)<0 then raise exception 'INVALID_COMPLIANCE_INPUT'; end if;
 v_eligible:=greatest(p_required-p_exempt-p_cancelled,0);
 if p_actual>v_eligible then raise exception 'ACTUAL_EXCEEDS_REQUIRED'; end if;
 v_score:=case when v_eligible=0 then 5 else round(p_actual::numeric/v_eligible*5,2) end;
 insert into public.kpi_compliance_records(evaluation_id,metric,required_count,actual_count,exempt_count,cancelled_count,calculated_score,note,approved_at,approved_by,created_by)
 values(p_evaluation_id,p_metric,p_required,p_actual,p_exempt,p_cancelled,v_score,p_note,now(),public.current_employee_id(),auth.uid())
 on conflict(evaluation_id,metric) do update set required_count=excluded.required_count,actual_count=excluded.actual_count,exempt_count=excluded.exempt_count,cancelled_count=excluded.cancelled_count,calculated_score=excluded.calculated_score,note=excluded.note,approved_at=now(),approved_by=public.current_employee_id(),updated_at=now();
 select c.id into strict v_criterion from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id and c.code=p_metric where e.id=p_evaluation_id;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,v_criterion,v_score,'hr',p_note,auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
 -- Once HR starts entering its data at the hr stage, the phase moves from
 -- data-preparation (HR_DATA_PENDING) to active HR evaluation.
 update public.kpi_evaluations set workflow_status='HR_EVALUATION_IN_PROGRESS',updated_at=now()
 where id=p_evaluation_id and current_stage='hr' and workflow_status='HR_DATA_PENDING';
 perform public.log_audit_event('kpi.compliance.calculated','workflow','info','kpi_evaluations',p_evaluation_id,'احتساب معيار التزام إداري',null,jsonb_build_object('metric',p_metric,'score',v_score,'required',p_required,'actual',p_actual,'exempt',p_exempt,'cancelled',p_cancelled));
 return v_score;
end $$;

-- -----------------------------------------------------------------------------
-- Attendance is already captured by the platform. This function only converts
-- finalized source data into the official 20-point score; no manual duplicate
-- attendance entry is introduced.
-- -----------------------------------------------------------------------------
create or replace function public.refresh_kpi_attendance_inputs(p_cycle_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_cycle public.kpi_cycles; v_eval record; v_rules jsonb; v_count integer:=0;
 v_start date; v_end date; v_late integer; v_early integer; v_absent integer;
 v_missing integer; v_shortage numeric; v_pending boolean; v_score numeric; v_old numeric;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.attendance.refresh','performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 select attendance_rules into strict v_rules from public.kpi_policy_versions where id=v_cycle.policy_version_id;
 v_start:=date_trunc('month',v_cycle.period_month)::date;
 v_end:=least((v_start+interval '1 month'-interval '1 day')::date,(public.kpi_effective_deadline(v_cycle) at time zone 'Africa/Cairo')::date);

 for v_eval in
  select e.id,e.employee_id,c.id criterion_id from public.kpi_evaluations e
  join public.kpi_criteria c on c.template_id=e.template_id and c.code='ATTENDANCE'
  where e.cycle_id=p_cycle_id
 loop
  with daily as (
   select a.*,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='arrival' and p.status='approved') arrival_permit,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='departure' and p.status='approved') departure_permit,
    exists(select 1 from public.attendance_exceptions x where x.employee_id=a.employee_id and coalesce(x.work_date,a.work_date)=a.work_date and x.status in ('approved','resolved')) exception_settled,
    exists(select 1 from public.attendance_corrections x where x.employee_id=a.employee_id and x.work_date=a.work_date and x.status='approved') correction_settled,
    exists(select 1 from public.roster_days rd where rd.employee_id=a.employee_id and rd.work_date=a.work_date and rd.day_status in ('rest','holiday','leave','mission','cancelled')) roster_exempt,
    exists(select 1 from public.leave_requests lr join public.requests r on r.id=lr.request_id where lr.employee_id=a.employee_id and r.status='approved' and a.work_date between lr.start_date and lr.end_date) leave_exempt,
    exists(select 1 from public.missions m join public.requests r on r.id=m.request_id where m.employee_id=a.employee_id and r.status='approved' and a.work_date between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date) mission_exempt,
    greatest(0,
      case when s.crosses_midnight then extract(epoch from ((s.end_time+interval '24 hours')-s.start_time))/60
           else extract(epoch from (s.end_time-s.start_time))/60 end-coalesce(s.break_minutes,0)
    )::integer scheduled_minutes
   from public.attendance_daily a left join public.shifts s on s.id=a.shift_id
   where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end
  ), scored as (
   select *, (status in ('on_leave','holiday','weekend') or roster_exempt or leave_exempt or mission_exempt) exempt
   from daily
  )
  select
   count(*) filter(where not exempt and late_minutes>0 and not arrival_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and early_leave_minutes>0 and not departure_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status='absent' and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status<>'absent' and (status in ('partial','pending') or first_check_in is null or last_check_out is null) and not exception_settled and not correction_settled),
   coalesce(sum(case when not exempt and status<>'absent' and not exception_settled and not correction_settled and scheduled_minutes>work_minutes
     then least((v_rules->>'maxShortagePerDay')::numeric,ceil((scheduled_minutes-work_minutes)::numeric/60)*(v_rules->>'shortagePerHour')::numeric) else 0 end),0)
  into v_late,v_early,v_absent,v_missing,v_shortage from scored;

  select exists(
   select 1 from public.attendance_daily a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
   union all select 1 from public.attendance_events a where a.employee_id=v_eval.employee_id and (a.event_at at time zone 'Africa/Cairo')::date between v_start and v_end and a.requires_review
   union all select 1 from public.attendance_exceptions a where a.employee_id=v_eval.employee_id and coalesce(a.work_date,v_start) between v_start and v_end and a.status='open'
   union all select 1 from public.attendance_corrections a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
  ) into v_pending;

  v_score:=greatest(0,round(20-
   v_late*(v_rules->>'late')::numeric-v_early*(v_rules->>'earlyLeave')::numeric-
   v_absent*(v_rules->>'unexcusedAbsence')::numeric-v_missing*(v_rules->>'missingPunch')::numeric-v_shortage,2));
  select score into v_old from public.kpi_scores where evaluation_id=v_eval.id and criterion_id=v_eval.criterion_id and reviewer_stage='hr';
  insert into public.kpi_attendance_snapshots(evaluation_id,period_start,period_end,late_count,early_leave_count,unexcused_absence_count,shortage_penalty,missing_punch_count,score,has_pending_items,details,calculated_by)
  values(v_eval.id,v_start,v_end,v_late,v_early,v_absent,v_shortage,v_missing,v_score,v_pending,jsonb_build_object('rules',v_rules),auth.uid())
  on conflict(evaluation_id) do update set period_start=excluded.period_start,period_end=excluded.period_end,late_count=excluded.late_count,early_leave_count=excluded.early_leave_count,unexcused_absence_count=excluded.unexcused_absence_count,shortage_penalty=excluded.shortage_penalty,missing_punch_count=excluded.missing_punch_count,score=excluded.score,has_pending_items=excluded.has_pending_items,details=excluded.details,calculated_at=now(),calculated_by=auth.uid(),updated_at=now();
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_eval.criterion_id,v_score,'hr','محسوب آليًا من الحضور والانصراف والاستثناءات المعتمدة',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  if v_old is distinct from v_score then
   perform public.log_audit_event('kpi.attendance.recalculated','workflow','notice','kpi_evaluations',v_eval.id,'إعادة حساب درجة الحضور',null,jsonb_build_object('oldScore',v_old,'newScore',v_score,'late',v_late,'earlyLeave',v_early,'absence',v_absent,'missingPunch',v_missing,'shortagePenalty',v_shortage,'pending',v_pending));
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end $$;

-- -----------------------------------------------------------------------------
-- Validation, authoritative stage transitions and exceptional score override.
-- -----------------------------------------------------------------------------
create or replace function public.get_kpi_validation_errors(p_evaluation_id uuid)
returns text[] language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_errors text[]:='{}'; v_goal_weight numeric; v_session public.kpi_review_sessions; v_total numeric;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 select coalesce(sum(weight),0) into v_goal_weight from public.kpi_goals where evaluation_id=p_evaluation_id;
 if v_goal_weight<>40 then v_errors:=array_append(v_errors,'يجب أن يساوي مجموع أوزان الأهداف 40 درجة.'); end if;
 if exists(select 1 from public.kpi_criteria c where c.template_id=v_eval.template_id and public.kpi_effective_score(v_eval.id,c.id) is null) then v_errors:=array_append(v_errors,'لم تكتمل جميع أقسام الدرجات.'); end if;
 select * into v_session from public.kpi_review_sessions where evaluation_id=p_evaluation_id;
 if v_session.id is null or v_session.held_at is null or not v_session.employee_attended or not v_session.manager_attended then v_errors:=array_append(v_errors,'جلسة التقييم وحضور الموظف والمدير إلزاميان.'); end if;
 if nullif(trim(coalesce(v_eval.manager_comment,'')),'') is null then v_errors:=array_append(v_errors,'تعليق المدير النهائي إلزامي.'); end if;
 if v_eval.hr_approved_at is null then v_errors:=array_append(v_errors,'اعتماد HR لدرجاته إلزامي.'); end if;
 if v_eval.employee_acknowledged_at is null then v_errors:=array_append(v_errors,'يجب تأكيد الموظف اطلاعه على التقييم.'); end if;
 if exists(select 1 from public.kpi_attendance_snapshots a where a.evaluation_id=p_evaluation_id and a.has_pending_items) or not exists(select 1 from public.kpi_attendance_snapshots a where a.evaluation_id=p_evaluation_id) then v_errors:=array_append(v_errors,'توجد بيانات حضور معلقة أو لم يتم حسابها.'); end if;
 if not exists(select 1 from public.kpi_review_sessions s join public.manager_relations mr on mr.employee_id=v_eval.employee_id and mr.manager_employee_id=s.manager_employee_id and mr.relation_type='primary' and mr.effective_from<=s.held_at::date and (mr.effective_to is null or mr.effective_to>=s.held_at::date) where s.evaluation_id=p_evaluation_id) then v_errors:=array_append(v_errors,'مدير الجلسة ليس المدير المباشر الفعلي.'); end if;
 v_total:=public.kpi_total_score(p_evaluation_id);
 if v_total<0 or v_total>100 then v_errors:=array_append(v_errors,'المجموع النهائي يجب أن يكون بين صفر و100.'); end if;
 return v_errors;
end $$;

create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid,p_action text,p_scores jsonb default null,p_note text default null
)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_expected text; v_next text; v_workflow text;
 v_row jsonb; v_score numeric; v_criterion public.kpi_criteria; v_errors text[]; v_total numeric; v_rating text;
 v_goal_weight numeric; v_session public.kpi_review_sessions; v_required_count integer; v_received_count integer;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 case p_action
  when 'self' then v_expected:='self';v_next:='manager';v_workflow:='MANAGER_EVALUATION_IN_PROGRESS';
  when 'manager' then v_expected:='manager';v_next:='hr';v_workflow:='HR_DATA_PENDING';
  when 'hr' then v_expected:='hr';v_next:='acknowledgement';v_workflow:='EMPLOYEE_ACKNOWLEDGEMENT_PENDING';
  when 'acknowledgement' then v_expected:='acknowledgement';v_next:='secretary';v_workflow:='FINAL_REVIEW';
  when 'secretary' then v_expected:='secretary';v_next:='executive';v_workflow:='SENT_TO_EXECUTIVE_DIRECTOR';
  when 'executive' then v_expected:='executive';v_next:='finalized';v_workflow:='APPROVED';
  when 'finalize' then v_expected:='executive';v_next:='finalized';v_workflow:='APPROVED';
  else raise exception 'INVALID_KPI_ACTION';
 end case;
 if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

 if v_expected='self' then
  if not(public.current_is_full_access() or (v_eval.employee_id=public.current_employee_id() and public.has_permission('performance.kpi.self_assess'))) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if not exists(select 1 from public.kpi_goals where evaluation_id=v_eval.id) then raise exception 'GOALS_REQUIRED'; end if;
 elsif v_expected='manager' then
  if not(public.current_is_full_access() or public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select coalesce(sum(weight),0) into v_goal_weight from public.kpi_goals where evaluation_id=v_eval.id;
  if v_goal_weight<>40 then raise exception 'GOAL_WEIGHTS_MUST_EQUAL_40'; end if;
  select * into v_session from public.kpi_review_sessions where evaluation_id=v_eval.id;
  if v_session.id is null or v_session.held_at is null or not v_session.employee_attended or not v_session.manager_attended or nullif(trim(coalesce(v_session.discussion_summary,'')),'') is null or nullif(trim(coalesce(v_session.strengths,'')),'') is null or nullif(trim(coalesce(v_session.improvement_points,'')),'') is null or nullif(trim(coalesce(v_session.next_month_goals,'')),'') is null then raise exception 'COMPLETE_REVIEW_SESSION_REQUIRED'; end if;
  if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id and evaluator_stage='manager' and calculation_method='manual';
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'MANAGER_SCORES_REQUIRED'; end if;
  select count(*) into v_received_count from jsonb_array_elements(p_scores);
  if v_received_count<>v_required_count then raise exception 'ALL_MANAGER_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='manager' and calculation_method='manual';
   if v_criterion.id is null then raise exception 'INVALID_MANAGER_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   if (v_criterion.code='EFFICIENCY' and (v_score<10 or v_score=20) or v_criterion.code='CONDUCT' and v_score<4 or v_criterion.code='INITIATIVES' and v_score in (0,5)) and length(trim(coalesce(v_row->>'note','')))<3 then raise exception 'COMMENT_REQUIRED_FOR_%',v_criterion.code; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'manager',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  end loop;
  select c.* into strict v_criterion from public.kpi_criteria c where c.template_id=v_eval.template_id and c.code='TARGET';
  select least(round(sum(calculated_score),2),40) into v_score from public.kpi_goals where evaluation_id=v_eval.id;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_criterion.id,coalesce(v_score,0),'manager','محسوب خادميًا من القيم المستهدفة والمحققة للأهداف',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  update public.kpi_goals set manager_approved_at=now(),manager_approved_by=public.current_employee_id(),updated_at=now() where evaluation_id=v_eval.id;
 elsif v_expected='hr' then
  if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
  if (select has_pending_items from public.kpi_attendance_snapshots where evaluation_id=v_eval.id) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
  if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;
 elsif v_expected='acknowledgement' then
  if not(public.current_is_full_access() or v_eval.employee_id=public.current_employee_id()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.kpi_review_sessions set employee_confirmed_at=now(),employee_notes=coalesce(nullif(trim(p_note),''),employee_notes),updated_at=now() where evaluation_id=v_eval.id;
 elsif v_expected='secretary' then
  if not(public.current_is_full_access() or public.has_permission('performance.kpi.secretary_review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if exists(select 1 from public.kpi_appeals where evaluation_id=v_eval.id and status in ('submitted','under_review')) then raise exception 'OPEN_APPEAL_REQUIRES_DECISION'; end if;
 elsif v_expected='executive' then
  if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.executive_review','performance.kpi.finalize'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  v_errors:=public.get_kpi_validation_errors(v_eval.id);
  if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
  v_total:=public.kpi_total_score(v_eval.id);
  if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
  v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
 end if;

 update public.kpi_evaluations set
  stage=v_next,current_stage=v_next,workflow_status=v_workflow,
  manager_comment=case when v_expected='manager' then trim(p_note) else manager_comment end,
  manager_approved_at=case when v_expected='manager' then now() else manager_approved_at end,
  manager_approved_by=case when v_expected='manager' then public.current_employee_id() else manager_approved_by end,
  hr_comment=case when v_expected='hr' then nullif(trim(p_note),'') else hr_comment end,
  hr_approved_at=case when v_expected='hr' then now() else hr_approved_at end,
  hr_approved_by=case when v_expected='hr' then public.current_employee_id() else hr_approved_by end,
  employee_comment=case when v_expected='acknowledgement' then nullif(trim(p_note),'') else employee_comment end,
  employee_acknowledged_at=case when v_expected='acknowledgement' then now() else employee_acknowledged_at end,
  secretary_comment=case when v_expected='secretary' then nullif(trim(p_note),'') else secretary_comment end,
  secretary_reviewed_at=case when v_expected='secretary' then now() else secretary_reviewed_at end,
  executive_comment=case when v_expected='executive' then nullif(trim(p_note),'') else executive_comment end,
  executive_approved_at=case when v_expected='executive' then now() else executive_approved_at end,
  final_score=case when v_next='finalized' then v_total else final_score end,
  final_rating=case when v_next='finalized' then v_rating else final_rating end,
  final_breakdown=case when v_next='finalized' then (select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id)) from public.kpi_criteria c where c.template_id=v_eval.template_id) else final_breakdown end,
  rating_policy_snapshot=case when v_next='finalized' then (select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id) else rating_policy_snapshot end,
  locked=(v_next='finalized'),updated_at=now()
 where id=v_eval.id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,'انتقال مرحلة تقييم الأداء',null,jsonb_build_object('action',p_action,'from',v_expected,'to',v_next,'workflowStatus',v_workflow,'note',p_note,'finalScore',v_total));
 return v_eval;
end $$;

create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_from text;
begin
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'RETURN_REASON_REQUIRED'; end if;
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 v_from:=v_eval.current_stage;
 if v_eval.locked and not public.current_is_full_access() then raise exception 'EVALUATION_LOCKED'; end if;
 if public.current_is_full_access() then
  if p_target_stage not in ('self','manager','hr','acknowledgement','secretary','executive') then raise exception 'INVALID_RETURN_TARGET'; end if;
 elsif v_from='manager' and p_target_stage='self' then
  if not public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess') then raise exception 'FORBIDDEN'; end if;
 elsif v_from='hr' and p_target_stage='manager' then
  if not public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.hr_review']) then raise exception 'FORBIDDEN'; end if;
 elsif v_from='secretary' and p_target_stage in ('manager','hr') then
  if not public.has_permission('performance.kpi.secretary_review') then raise exception 'FORBIDDEN'; end if;
 elsif v_from='executive' and p_target_stage='secretary' then
  if not public.has_permission('performance.kpi.executive_review') then raise exception 'FORBIDDEN'; end if;
 else raise exception 'INVALID_RETURN_TARGET'; end if;
 update public.kpi_evaluations set stage=p_target_stage,current_stage=p_target_stage,workflow_status='RETURNED_FOR_REVISION',locked=false,updated_at=now() where id=p_evaluation_id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,'إعادة التقييم للتصحيح',trim(p_note),jsonb_build_object('from',v_from,'to',p_target_stage));
 return v_eval;
end $$;

create or replace function public.override_kpi_score(p_evaluation_id uuid,p_criterion_id uuid,p_score numeric,p_reason text)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_max numeric; v_old numeric;
begin
 if not(public.current_is_full_access() or public.has_permission('performance.kpi.score.override')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'OVERRIDE_REASON_REQUIRED'; end if;
 select c.max_score into strict v_max from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id where e.id=p_evaluation_id and c.id=p_criterion_id;
 if p_score<0 or p_score>v_max then raise exception 'SCORE_OUT_OF_RANGE'; end if;
 select public.kpi_effective_score(p_evaluation_id,p_criterion_id) into v_old;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,p_criterion_id,p_score,'secretary',trim(p_reason),auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
 update public.kpi_evaluations set final_score=null,final_rating=null,final_breakdown=null,locked=false,
  stage=case when current_stage in ('finalized','closed') then 'secretary' else stage end,
  current_stage=case when current_stage in ('finalized','closed') then 'secretary' else current_stage end,
  workflow_status=case when current_stage in ('finalized','closed') then 'FINAL_REVIEW' else workflow_status end,
  updated_at=now()
 where id=p_evaluation_id;
 perform public.log_audit_event('kpi.score.overridden','workflow','warning','kpi_evaluations',p_evaluation_id,'تعديل استثنائي لدرجة تقييم',trim(p_reason),jsonb_build_object('criterionId',p_criterion_id,'oldScore',v_old,'newScore',p_score));
 return p_score;
end $$;

-- -----------------------------------------------------------------------------
-- Cycle administration. Official window is always 20-25 Africa/Cairo;
-- exceptional opening or extension is explicit, reasoned and audited.
-- -----------------------------------------------------------------------------
create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid; v_open timestamptz; v_deadline timestamptz; v_now_date date:=(now() at time zone 'Africa/Cairo')::date; v_status text;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.cycle.control'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 v_status:=case when p_open_now and v_now_date between v_month+19 and v_month+24 then 'open' else 'draft' end;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,auth.uid())
 on conflict(period_month) do update set template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),updated_at=now()
 returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,created_by)
 select e.id,v_id,v_template,'self','self','NOT_STARTED',auth.uid() from public.employees e where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI رسمية',null,jsonb_build_object('month',v_month,'openAt',v_open,'deadline',v_deadline,'status',v_status));
 return v_id;
end $$;

create or replace function public.manage_kpi_cycle(p_cycle_id uuid,p_action text,p_reason text,p_extended_until timestamptz default null)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_old text;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.cycle.control','performance.cycle.manage'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'CONTROL_REASON_REQUIRED'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id for update; v_old:=v_cycle.status;
 case p_action
  when 'open' then update public.kpi_cycles set status='open',opened_at=coalesce(opened_at,now()),opened_by=public.current_employee_id(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
  when 'reopen' then update public.kpi_cycles set status='open',override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
  when 'extend' then
   if p_extended_until is null or p_extended_until<=coalesce(v_cycle.extended_until,v_cycle.deadline_at,now()) then raise exception 'INVALID_EXTENSION_DEADLINE'; end if;
   update public.kpi_cycles set status='open',extended_until=p_extended_until,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
  when 'close' then
   update public.kpi_cycles set status='locked',locked_at=now(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set workflow_status=case when current_stage='finalized' then 'CLOSED' else 'OVERDUE' end,current_stage=case when current_stage='finalized' then 'closed' else current_stage end,stage=case when stage='finalized' then 'closed' else stage end,locked=true,updated_at=now() where cycle_id=p_cycle_id;
  else raise exception 'INVALID_CYCLE_ACTION'; end case;
 if p_action in ('open','reopen','extend') then update public.kpi_evaluations set locked=false,workflow_status=case when workflow_status='OVERDUE' then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed'); end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 perform public.log_audit_event('kpi.cycle.'||p_action,'workflow','warning','kpi_cycles',p_cycle_id,'تحكم يدوي في دورة KPI',trim(p_reason),jsonb_build_object('oldStatus',v_old,'newStatus',v_cycle.status,'extendedUntil',p_extended_until));
 return v_cycle;
end $$;

-- -----------------------------------------------------------------------------
-- Employee acknowledgement/appeal and secretary resolution.
-- -----------------------------------------------------------------------------
create or replace function public.acknowledge_kpi_evaluation(p_evaluation_id uuid,p_note text default null,p_appeal_reason text default null)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_appeal uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not(public.current_is_full_access() or v_eval.employee_id=public.current_employee_id()) or v_eval.current_stage<>'acknowledgement' then raise exception 'FORBIDDEN_OR_WRONG_STAGE'; end if;
 update public.kpi_review_sessions set employee_confirmed_at=now(),employee_notes=coalesce(nullif(trim(p_note),''),employee_notes),updated_at=now() where evaluation_id=p_evaluation_id;
 if nullif(trim(coalesce(p_appeal_reason,'')),'') is not null then
  if length(trim(p_appeal_reason))<10 then raise exception 'APPEAL_REASON_TOO_SHORT'; end if;
  insert into public.kpi_appeals(evaluation_id,employee_id,reason,status,resolution_due_at,created_by)
  values(p_evaluation_id,v_eval.employee_id,trim(p_appeal_reason),'submitted',now()+interval '7 days',auth.uid())
  on conflict(evaluation_id,employee_id) do update set reason=excluded.reason,status='submitted',submitted_at=now(),review_note=null,reviewed_at=null,reviewed_by=null,updated_at=now()
  returning id into v_appeal;
 end if;
 update public.kpi_evaluations set stage='secretary',current_stage='secretary',workflow_status=case when v_appeal is null then 'EMPLOYEE_ACKNOWLEDGED' else 'FINAL_REVIEW' end,employee_comment=nullif(trim(p_note),''),employee_acknowledged_at=now(),updated_at=now() where id=p_evaluation_id returning * into v_eval;
 perform public.log_audit_event(case when v_appeal is null then 'kpi.employee.acknowledged' else 'kpi.appeal.submitted' end,'workflow',case when v_appeal is null then 'info' else 'warning' end,'kpi_evaluations',p_evaluation_id,'تأكيد اطلاع الموظف على التقييم',p_appeal_reason,jsonb_build_object('appealId',v_appeal));
 return v_eval;
end $$;

create or replace function public.submit_kpi_appeal(p_evaluation_id uuid,p_reason text,p_requested_outcome text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if v_eval.employee_id<>public.current_employee_id() or v_eval.current_stage not in ('acknowledgement','secretary','finalized','closed') then raise exception 'FORBIDDEN_OR_NOT_AVAILABLE'; end if;
 if length(trim(p_reason))<10 then raise exception 'REASON_TOO_SHORT'; end if;
 insert into public.kpi_appeals(evaluation_id,employee_id,reason,requested_outcome,status,resolution_due_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,trim(p_reason),p_requested_outcome,'submitted',now()+interval '7 days',auth.uid())
 on conflict(evaluation_id,employee_id) do update set reason=excluded.reason,requested_outcome=excluded.requested_outcome,status='submitted',submitted_at=now(),review_note=null,reviewed_at=null,reviewed_by=null,updated_at=now()
 returning id into v_id;
 update public.kpi_evaluations set locked=false,stage='secretary',current_stage='secretary',workflow_status='FINAL_REVIEW',employee_acknowledged_at=coalesce(employee_acknowledged_at,now()),updated_at=now() where id=p_evaluation_id;
 perform public.log_audit_event('kpi.appeal.submitted','workflow','warning','kpi_appeals',v_id,'تقديم اعتراض على تقييم الأداء',trim(p_reason),jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;

create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.appeal.review','performance.kpi.secretary_review'])) then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 update public.kpi_evaluations set stage='secretary',current_stage='secretary',workflow_status='FINAL_REVIEW',locked=false,updated_at=now() where id=v.evaluation_id;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض تقييم الأداء',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
end $$;

-- -----------------------------------------------------------------------------
-- Forms, inbox, admin catalog and KPI report.
-- -----------------------------------------------------------------------------
create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles; v_editable text; v_locked boolean; v_criteria jsonb;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);
 if not v_locked then
  if v_eval.current_stage='self' and (public.current_is_full_access() or v_eval.employee_id=public.current_employee_id()) then v_editable:='self';
  elsif v_eval.current_stage='manager' and (public.current_is_full_access() or public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess')) then v_editable:='manager';
  elsif v_eval.current_stage='hr' and (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.hr_review'])) then v_editable:='hr';
  elsif v_eval.current_stage='acknowledgement' and (public.current_is_full_access() or v_eval.employee_id=public.current_employee_id()) then v_editable:='acknowledgement';
  elsif v_eval.current_stage='secretary' and (public.current_is_full_access() or public.has_permission('performance.kpi.secretary_review')) then v_editable:='secretary';
  elsif v_eval.current_stage='executive' and (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.executive_review','performance.kpi.finalize'])) then v_editable:='executive'; end if;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',v_editable=c.evaluator_stage and c.calculation_method='manual',
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}'::jsonb)
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;
 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'cycle',jsonb_build_object('id',v_cycle.id,'status',v_cycle.status,'scheduledOpenAt',v_cycle.scheduled_open_at,'deadlineAt',v_cycle.deadline_at,'extendedUntil',v_cycle.extended_until,'effectiveDeadline',public.kpi_effective_deadline(v_cycle)),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'description',g.description,'targetValue',g.target_value,'achievedValue',g.achieved_value,'unit',g.unit,'weight',g.weight,'dueDate',g.due_date,'evidenceSource',g.evidence_source,'employeeNote',g.employee_note,'managerNote',g.manager_note,'status',g.status,'calculatedScore',g.calculated_score) order by g.created_at) from public.kpi_goals g where g.evaluation_id=v_eval.id),'[]'::jsonb),
  'session',(select jsonb_build_object('id',s.id,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'mode',s.mode,'discussionSummary',s.discussion_summary,'strengths',s.strengths,'improvementPoints',s.improvement_points,'nextMonthGoals',s.next_month_goals,'employeeNotes',s.employee_notes,'managerNotes',s.manager_notes,'employeeAttended',s.employee_attended,'managerAttended',s.manager_attended,'employeeConfirmedAt',s.employee_confirmed_at) from public.kpi_review_sessions s where s.evaluation_id=v_eval.id),
  'compliance',coalesce((select jsonb_agg(jsonb_build_object('metric',r.metric,'requiredCount',r.required_count,'actualCount',r.actual_count,'exemptCount',r.exempt_count,'cancelledCount',r.cancelled_count,'score',r.calculated_score,'note',r.note)) from public.kpi_compliance_records r where r.evaluation_id=v_eval.id),'[]'::jsonb),
  'attendance',(select jsonb_build_object('periodStart',a.period_start,'periodEnd',a.period_end,'lateCount',a.late_count,'earlyLeaveCount',a.early_leave_count,'unexcusedAbsenceCount',a.unexcused_absence_count,'shortagePenalty',a.shortage_penalty,'missingPunchCount',a.missing_punch_count,'score',a.score,'hasPendingItems',a.has_pending_items,'calculatedAt',a.calculated_at) from public.kpi_attendance_snapshots a where a.evaluation_id=v_eval.id),
  'validationErrors',to_jsonb(public.get_kpi_validation_errors(v_eval.id)),
  'lastUpdatedAt',coalesce(v_eval.updated_at,v_eval.created_at)
 );
end $$;

create or replace function public.get_kpi_inbox(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(item order by item->>'updatedAt' desc),'[]'::jsonb) from (
  select jsonb_build_object('id',k.id,'employeeId',k.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'cycleId',k.cycle_id,'periodMonth',c.period_month,'currentStage',k.current_stage,'workflowStatus',k.workflow_status,'cycleStatus',c.status,'deadlineAt',public.kpi_effective_deadline(c),'finalScore',k.final_score,'finalRating',k.final_rating,'locked',k.locked or c.status<>'open','updatedAt',coalesce(k.updated_at,k.created_at)) item
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id join public.kpi_cycles c on c.id=k.cycle_id
  order by coalesce(k.updated_at,k.created_at) desc limit greatest(1,least(coalesce(p_limit,100),500))
 ) q;
$$;

create or replace function public.get_kpi_admin_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.read','performance.cycle.manage','performance.kpi.cycle.control','performance.kpi.secretary_review','performance.kpi.executive_review'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'month',v_month,'canManageCycles',public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.cycle.control']),
  'officialTemplateId',(select id from public.kpi_templates where official_code='OFFICIAL_KPI_100'),
  'cycles',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'periodMonth',c.period_month,'status',c.status,'templateId',c.template_id,'templateName',t.name_ar,'selfDueAt',c.self_due_at,'managerDueAt',c.manager_due_at,'secretaryDueAt',c.secretary_due_at,'executiveDueAt',c.executive_due_at,'scheduledOpenAt',c.scheduled_open_at,'deadlineAt',c.deadline_at,'extendedUntil',c.extended_until,'effectiveDeadline',public.kpi_effective_deadline(c),'openedAt',c.opened_at,'lockedAt',c.locked_at,'overrideReason',c.override_reason,'evaluations',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id),'finalized',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.current_stage in ('finalized','closed')),'overdue',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.workflow_status='OVERDUE'),'averageScore',(select round(avg(e.final_score),2) from public.kpi_evaluations e where e.cycle_id=c.id and e.final_score is not null)) order by c.period_month desc) from public.kpi_cycles c left join public.kpi_templates t on t.id=c.template_id where c.period_month between (v_month-interval '6 months')::date and (v_month+interval '1 month')::date),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name_ar,'version',t.version,'active',t.is_active,'officialCode',t.official_code,'criteria',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'code',k.code,'name',k.name_ar,'weight',k.weight,'maxScore',k.max_score,'sourceType',k.source_type,'attendanceMetric',k.attendance_metric,'evaluatorStage',k.evaluator_stage,'calculationMethod',k.calculation_method,'requiresEvidence',k.requires_evidence) order by k.sort_order) from public.kpi_criteria k where k.template_id=t.id),'[]'::jsonb)) order by t.created_at desc) from public.kpi_templates t),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'evaluationId',a.evaluation_id,'employeeId',a.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'reason',a.reason,'requestedOutcome',a.requested_outcome,'status',a.status,'submittedAt',a.submitted_at,'resolutionDueAt',a.resolution_due_at,'reviewNote',a.review_note) order by a.submitted_at desc) from public.kpi_appeals a join public.employees e on e.id=a.employee_id where a.status in ('submitted','under_review')),'[]'::jsonb),
  'stageCounts',coalesce((select jsonb_object_agg(x.current_stage,x.count) from (select e.current_stage,count(*) count from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=v_month group by e.current_stage)x),'{}'::jsonb),
  'policy',(select jsonb_build_object('id',id,'version',version,'name',name_ar,'weights',criteria_weights,'attendanceRules',attendance_rules,'ratingBands',rating_bands) from public.kpi_policy_versions where is_active),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.get_kpi_cycle_report(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.report.read','reports.performance.read','performance.kpi.secretary_review','performance.kpi.executive_review'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 return jsonb_build_object(
  'cycleId',v_cycle.id,'periodMonth',v_cycle.period_month,'status',v_cycle.status,'deadlineAt',public.kpi_effective_deadline(v_cycle),
  'summary',(select jsonb_build_object('total',count(*),'approved',count(*) filter(where current_stage in ('finalized','closed')),'overdue',count(*) filter(where workflow_status='OVERDUE'),'averageScore',round(avg(final_score),2)) from public.kpi_evaluations where cycle_id=p_cycle_id),
  'distribution',(select coalesce(jsonb_object_agg(coalesce(final_rating,'غير مكتمل'),count),'{}'::jsonb) from (select final_rating,count(*) count from public.kpi_evaluations where cycle_id=p_cycle_id group by final_rating)x),
  'evaluations',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,'stage',e.current_stage,'workflowStatus',e.workflow_status,'finalScore',e.final_score,'finalRating',e.final_rating,'breakdown',e.final_breakdown,'attendance',(select to_jsonb(a)-'id'-'evaluation_id' from public.kpi_attendance_snapshots a where a.evaluation_id=e.id)) order by emp.full_name_ar) from public.kpi_evaluations e join public.employees emp on emp.id=e.employee_id where e.cycle_id=p_cycle_id),'[]'::jsonb),
  'generatedAt',now()
 );
end $$;

-- -----------------------------------------------------------------------------
-- Idempotent notifications and automatic window processing (Cairo time).
-- -----------------------------------------------------------------------------
create or replace function public.enqueue_kpi_notification(p_cycle_id uuid,p_evaluation_id uuid,p_event_key text,p_recipient_employee_id uuid,p_title text,p_body text,p_priority text default 'normal')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_notification uuid;
begin
 select id into v_user from public.profiles where employee_id=p_recipient_employee_id and status in ('active','pending') limit 1;
 if v_user is null then return null; end if;
 if exists(select 1 from public.kpi_notification_receipts where cycle_id=p_cycle_id and event_key=p_event_key and recipient_user_id=v_user and evaluation_id is not distinct from p_evaluation_id) then return null; end if;
 insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,metadata)
 values(v_user,p_recipient_employee_id,p_title,p_body,'system',p_priority,'/hr/performance','kpi_evaluation',coalesce(p_evaluation_id,p_cycle_id),jsonb_build_object('eventKey',p_event_key,'cycleId',p_cycle_id,'evaluationId',p_evaluation_id,'mobileRoute',case when p_evaluation_id is null then 'kpi_list' else 'kpi_form' end)) returning id into v_notification;
 insert into public.kpi_notification_receipts(cycle_id,evaluation_id,event_key,recipient_user_id,notification_id) values(p_cycle_id,p_evaluation_id,p_event_key,v_user,v_notification) on conflict do nothing;
 return v_notification;
end $$;

create or replace function public.generate_kpi_cycle_notifications(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_eval record; v_recipient uuid; v_day integer:=(p_at at time zone 'Africa/Cairo')::date-(date_trunc('month',p_at at time zone 'Africa/Cairo'))::date+1; v_count integer:=0; v_event text; v_title text; v_body text;
begin
 for v_cycle in select * from public.kpi_cycles where status in ('open','locked') and period_month=date_trunc('month',p_at at time zone 'Africa/Cairo')::date loop
  -- OPENED is emitted to everyone once the cycle opens; a threshold (>=) test
  -- plus the receipt table means a scheduler outage on day 20 self-heals on the
  -- next run instead of dropping the notification permanently.
  if v_day>=20 then
   for v_eval in select e.id,e.employee_id,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_to is null limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id loop
    if public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_EMPLOYEE',v_eval.employee_id,'بدأت دورة تقييم الأداء','دورة التقييم الشهرية مفتوحة حتى نهاية يوم 25. راجع أهدافك وأكمل المطلوب.','normal') is not null then v_count:=v_count+1; end if;
    if v_eval.manager_id is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_MANAGER',v_eval.manager_id,'بدأ تقييم أحد أعضاء فريقك','راجع أهداف الموظف وحدد جلسة التقييم قبل نهاية يوم 25.','normal') is not null then v_count:=v_count+1; end if;
   end loop;
  end if;
  -- Reminders are evaluated newest-threshold-first (25 -> 24 -> 22) with a >=
  -- test so a missed day still fires its reminder on the next run; the receipt
  -- table dedupes, so no reminder is ever sent twice.
  if p_at>public.kpi_effective_deadline(v_cycle) then v_event:='OVERDUE';
  elsif v_day>=25 then v_event:='REMINDER_25';v_title:='اليوم آخر موعد لتقييم الأداء';v_body:='التقييم ما زال غير مكتمل وسيغلق بنهاية اليوم.';
  elsif v_day>=24 then v_event:='REMINDER_24';v_title:='غدًا آخر موعد لتقييم الأداء';v_body:='ينتهي موعد تسليم تقييم الأداء غدًا بنهاية اليوم.';
  elsif v_day>=22 then v_event:='REMINDER_22';v_title:='تذكير بتقييم الأداء';v_body:='لم يبدأ أو لم يكتمل تقييم الأداء المطلوب. يرجى البدء قبل الموعد النهائي.';
  else continue; end if;
  if v_event='OVERDUE' then
   for v_recipient in select distinct p.employee_id from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.user_id where r.slug='executive-secretary' and p.employee_id is not null and ur.effective_from<=p_at and (ur.effective_to is null or ur.effective_to>p_at) loop
    if public.enqueue_kpi_notification(v_cycle.id,null,v_event,v_recipient,'تقييمات أداء متأخرة','انتهى الموعد وما زالت هناك تقييمات غير مكتملة. افتح تقرير الدورة للمراجعة.','urgent') is not null then v_count:=v_count+1; end if;
   end loop;
  else
   for v_eval in select e.id,e.employee_id,e.current_stage,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_to is null limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id and e.current_stage not in ('finalized','closed') loop
    v_recipient:=case when v_eval.current_stage in ('self','acknowledgement') then v_eval.employee_id when v_eval.current_stage='manager' then v_eval.manager_id else null end;
    if v_recipient is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,v_event,v_recipient,v_title,v_body,case when v_event='REMINDER_25' then 'urgent' else 'high' end) is not null then v_count:=v_count+1; end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $$;

create or replace function public.process_kpi_cycle_schedule(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_count integer:=0;
begin
 for v_cycle in select * from public.kpi_cycles where status='draft' and scheduled_open_at<=p_at and p_at<=coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='open',opened_at=p_at,updated_at=p_at where id=v_cycle.id;
  perform public.log_audit_event('kpi.cycle.auto_opened','workflow','notice','kpi_cycles',v_cycle.id,'فتح دورة KPI تلقائيًا',null,jsonb_build_object('at',p_at)); v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at);
 for v_cycle in select * from public.kpi_cycles where status='open' and p_at>coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='locked',locked_at=p_at,updated_at=p_at where id=v_cycle.id;
  update public.kpi_evaluations set workflow_status=case when current_stage='finalized' then 'CLOSED' else 'OVERDUE' end,current_stage=case when current_stage='finalized' then 'closed' else current_stage end,stage=case when stage='finalized' then 'closed' else stage end,locked=true,updated_at=p_at where cycle_id=v_cycle.id;
  perform public.log_audit_event('kpi.cycle.auto_closed','workflow','warning','kpi_cycles',v_cycle.id,'إغلاق دورة KPI تلقائيًا بعد الموعد',null,jsonb_build_object('at',p_at)); v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at+interval '1 second');
 return v_count;
end $$;

-- Compatibility entry points now delegate to the official deadline/extension logic.
create or replace function public.close_kpi_cycle(p_cycle_id uuid)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return public.manage_kpi_cycle(p_cycle_id,'close','إغلاق من أمر التوافق المعتمد',null);
end $$;

create or replace function public.close_kpi_cycle_due()
returns integer language sql security definer set search_path=public,pg_temp as $$
 select public.process_kpi_cycle_schedule(now());
$$;

-- Function privileges.
revoke execute on function public.save_kpi_goal(uuid,uuid,text,text,numeric,numeric,text,numeric,date,text,text,text,text) from public;
revoke execute on function public.save_kpi_review_session(uuid,jsonb) from public;
revoke execute on function public.save_kpi_compliance_metric(uuid,text,integer,integer,integer,integer,text) from public;
revoke execute on function public.refresh_kpi_attendance_inputs(uuid) from public;
revoke execute on function public.get_kpi_validation_errors(uuid) from public;
revoke execute on function public.create_kpi_policy_version(text,jsonb,jsonb,boolean,date) from public;
revoke execute on function public.advance_kpi_stage(uuid,text,jsonb,text) from public;
revoke execute on function public.return_kpi_stage(uuid,text,text) from public;
revoke execute on function public.override_kpi_score(uuid,uuid,numeric,text) from public;
revoke execute on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean) from public;
revoke execute on function public.manage_kpi_cycle(uuid,text,text,timestamptz) from public;
revoke execute on function public.acknowledge_kpi_evaluation(uuid,text,text) from public;
revoke execute on function public.submit_kpi_appeal(uuid,text,text) from public;
revoke execute on function public.decide_kpi_appeal(uuid,text,text) from public;
revoke execute on function public.get_kpi_evaluation_form(uuid) from public;
revoke execute on function public.get_kpi_inbox(integer) from public;
revoke execute on function public.get_kpi_admin_catalog(date) from public;
revoke execute on function public.get_kpi_cycle_report(uuid) from public;
revoke execute on function public.enqueue_kpi_notification(uuid,uuid,text,uuid,text,text,text) from public,anon,authenticated;
revoke execute on function public.generate_kpi_cycle_notifications(timestamptz) from public,anon,authenticated;
revoke execute on function public.process_kpi_cycle_schedule(timestamptz) from public,anon,authenticated;
revoke execute on function public.close_kpi_cycle_due() from public,anon,authenticated;

grant execute on function public.save_kpi_goal(uuid,uuid,text,text,numeric,numeric,text,numeric,date,text,text,text,text) to authenticated;
grant execute on function public.save_kpi_review_session(uuid,jsonb) to authenticated;
grant execute on function public.save_kpi_compliance_metric(uuid,text,integer,integer,integer,integer,text) to authenticated;
grant execute on function public.refresh_kpi_attendance_inputs(uuid) to authenticated;
grant execute on function public.get_kpi_validation_errors(uuid) to authenticated;
grant execute on function public.create_kpi_policy_version(text,jsonb,jsonb,boolean,date) to authenticated;
grant execute on function public.advance_kpi_stage(uuid,text,jsonb,text) to authenticated;
grant execute on function public.return_kpi_stage(uuid,text,text) to authenticated;
grant execute on function public.override_kpi_score(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean) to authenticated;
grant execute on function public.manage_kpi_cycle(uuid,text,text,timestamptz) to authenticated;
grant execute on function public.acknowledge_kpi_evaluation(uuid,text,text) to authenticated;
grant execute on function public.submit_kpi_appeal(uuid,text,text) to authenticated;
grant execute on function public.decide_kpi_appeal(uuid,text,text) to authenticated;
grant execute on function public.get_kpi_evaluation_form(uuid) to authenticated;
grant execute on function public.get_kpi_inbox(integer) to authenticated;
grant execute on function public.get_kpi_admin_catalog(date) to authenticated;
grant execute on function public.get_kpi_cycle_report(uuid) to authenticated;
grant execute on function public.enqueue_kpi_notification(uuid,uuid,text,uuid,text,text,text) to service_role;
grant execute on function public.generate_kpi_cycle_notifications(timestamptz) to service_role;
grant execute on function public.process_kpi_cycle_schedule(timestamptz) to service_role;
grant execute on function public.close_kpi_cycle_due() to postgres,service_role;

-- Safe local scheduling. Production may call the same service-role function externally.
do $cron$
begin
 if not exists(select 1 from pg_extension where extname='pg_cron') then
  raise notice 'pg_cron is unavailable; process_kpi_cycle_schedule() must be called by the external scheduler.';
  return;
 end if;
 perform cron.unschedule(jobname) from cron.job where jobname='hr_official_kpi_cycle_schedule';
 perform cron.schedule('hr_official_kpi_cycle_schedule','*/30 * * * *',$job$select public.process_kpi_cycle_schedule()$job$);
end
$cron$;

commit;
