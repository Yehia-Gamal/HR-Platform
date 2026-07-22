-- =====================================================================
-- 0066: ربط تكليفات العمل (قافلة/فاندي) بـ KPI مع منع الاحتساب المزدوج
-- =====================================================================
-- المرجع: المواصفة الرسمية (البنود 10،15،20).
-- المبدأ:
--   * القافلة والفاندي يمكن أن تُسهم في معيار «المشاركة في المبادرات/التبرعات»
--     (INITIATIVES = 5 درجات) — مع منع احتساب نفس النشاط مرتين.
--   * الفاندي لموظف له مستهدف مالي يمكن ربطه بـ kpi_goals (TARGET).
--   * لا يجوز احتساب نفس التكليف مرتين داخل KPI (البند 20) — نضمن ذلك بجدول
--     ربط فريد (assignment_id, evaluation_id).
-- ملاحظة: احتساب INITIATIVES النهائي يظل قرار المدير (source_type=manual)؛ هذا
--   الجدول يوثّق المشاركة ويمنع التكرار ويوفّر مصدرًا للمراجعة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) جدول ربط التكليف بتقييم KPI (يمنع الاحتساب المزدوج).
-- ---------------------------------------------------------------------
create table if not exists public.kpi_assignment_contributions (
  id                 uuid primary key default gen_random_uuid(),
  assignment_id      uuid not null references public.work_assignments(id) on delete cascade,
  evaluation_id      uuid not null references public.kpi_evaluations(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  contribution_type  text not null check (contribution_type in ('INITIATIVES','TARGET')),
  points             numeric(6,2),
  amount             numeric(14,2),
  note               text,
  created_at         timestamptz not null default now(),
  created_by         uuid references auth.users(id),
  -- منع الاحتساب المزدوج لنفس التكليف داخل نفس التقييم لنفس البند.
  unique(assignment_id, evaluation_id, contribution_type)
);
comment on table public.kpi_assignment_contributions is
  'ربط تكليفات العمل (قافلة/فاندي) بتقييمات KPI مع منع احتساب النشاط مرتين (البند 20).';

create index if not exists ix_kpi_ac_evaluation on public.kpi_assignment_contributions(evaluation_id);
create index if not exists ix_kpi_ac_employee on public.kpi_assignment_contributions(employee_id);

alter table public.kpi_assignment_contributions enable row level security;

drop policy if exists kpi_ac_select on public.kpi_assignment_contributions;
create policy kpi_ac_select on public.kpi_assignment_contributions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['performance.kpi.read','performance.kpi.hr_assess','performance.kpi.hr_review'])
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );
revoke insert, update, delete on public.kpi_assignment_contributions from authenticated;

-- ---------------------------------------------------------------------
-- 2) RPC: تسجيل مساهمة تكليف في معيار INITIATIVES (idempotent، لا تكرار).
--    للمخوّل بتقييم KPI أو المدير المسؤول. لا يتجاوز سقف المعيار (5 درجات).
-- ---------------------------------------------------------------------
create or replace function public.link_assignment_to_initiatives(
  p_assignment_id uuid,
  p_evaluation_id uuid,
  p_points numeric default 5,
  p_note text default null
)
returns public.kpi_assignment_contributions
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_me uuid := public.current_employee_id();
  v_asg public.work_assignments;
  v_emp uuid;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess','performance.kpi.hr_review'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_points is null or p_points < 0 or p_points > 5 then
    raise exception 'INITIATIVES_POINTS_OUT_OF_RANGE (0..5)' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'assignment not found' using errcode='P0002'; end if;
  if v_asg.assignment_type not in ('CONVOY','FUNDRAISING') then
    raise exception 'only convoy/fundraising contribute to initiatives' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, points, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'INITIATIVES', p_points, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (منع الاحتساب المزدوج)' using errcode='23505';
  end if;

  perform public.log_audit_event(
    'kpi.assignment.initiatives.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'ربط تكليف بمعيار المبادرات', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'points', p_points,
                       'assignmentType', v_asg.assignment_type));
  return v_row;
end $$;
revoke execute on function public.link_assignment_to_initiatives(uuid,uuid,numeric,text) from public;
grant execute on function public.link_assignment_to_initiatives(uuid,uuid,numeric,text) to authenticated;

-- ---------------------------------------------------------------------
-- 3) RPC: ربط الفاندي بمستهدف مالي (kpi_goals / TARGET) للموظف المكلّف بمستهدف.
--    ينشئ/يحدّث هدفًا من نوع مالي ويسجّل المساهمة (idempotent، لا تكرار).
-- ---------------------------------------------------------------------
create or replace function public.link_fundraising_to_target(
  p_assignment_id uuid,
  p_evaluation_id uuid,
  p_weight numeric default 40,
  p_note text default null
)
returns public.kpi_assignment_contributions
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_asg public.work_assignments;
  v_emp uuid;
  v_goal_id uuid;
  v_achieved numeric;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_weight is null or p_weight <= 0 or p_weight > 40 then
    raise exception 'TARGET_WEIGHT_OUT_OF_RANGE (0..40]' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'assignment not found' using errcode='P0002'; end if;
  if v_asg.assignment_type <> 'FUNDRAISING' then
    raise exception 'only fundraising links to financial target' using errcode='22023';
  end if;
  if v_asg.target_amount is null or v_asg.target_amount <= 0 then
    raise exception 'assignment has no financial target' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  -- المحقق: مجموع محقق المشاركين إن وُجد، وإلا achieved_amount على التكليف.
  select coalesce(sum(achieved_amount), 0) into v_achieved
  from public.work_assignment_participants
  where assignment_id = p_assignment_id and employee_id = v_emp;
  if v_achieved = 0 then v_achieved := coalesce(v_asg.achieved_amount, 0); end if;

  -- سجّل المساهمة أولًا لضمان منع التكرار.
  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, amount, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'TARGET', v_achieved, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (منع الاحتساب المزدوج)' using errcode='23505';
  end if;

  -- أنشئ/حدّث هدف TARGET المالي.
  insert into public.kpi_goals(
    evaluation_id, title, description, target_value, achieved_value, unit, weight,
    evidence_source, created_by)
  values(
    p_evaluation_id, format('مستهدف فاندي: %s', v_asg.title), p_note,
    v_asg.target_amount, v_achieved, 'EGP', p_weight,
    'work_assignments', auth.uid())
  returning id into v_goal_id;

  perform public.log_audit_event(
    'kpi.assignment.target.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'ربط فاندي بمستهدف مالي', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'goalId', v_goal_id,
                       'target', v_asg.target_amount, 'achieved', v_achieved));
  return v_row;
end $$;
revoke execute on function public.link_fundraising_to_target(uuid,uuid,numeric,text) from public;
grant execute on function public.link_fundraising_to_target(uuid,uuid,numeric,text) to authenticated;

-- =====================================================================
-- نهاية Migration 0066
-- =====================================================================
