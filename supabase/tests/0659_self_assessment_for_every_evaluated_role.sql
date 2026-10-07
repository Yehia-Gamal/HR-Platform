-- =====================================================================
-- 0659: التقييم الذاتي لمن يحمل دورًا إداريًا وحده
-- ---------------------------------------------------------------------
-- يثبت:
--   1) كل دور غير كامل الوصول (عدا أدوار اللجنة) يملك self_assess بنطاق self
--   2) مدير مباشر بدور direct-manager وحده يرسل تقييمه الذاتي فينتقل إلى
--      مراجعة المدير (كان FORBIDDEN فيبقى «متأخرًا» إلى الأبد)
--   3) المنح لا يوسّع النطاق: المدير نفسه لا يرسل التقييم الذاتي لغيره
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(5);

insert into auth.users(id, email, aud, role) values
 ('86590000-0000-4000-8000-000000000001', 'kpi659-mgr@test.local', 'authenticated', 'authenticated'),
 ('86590000-0000-4000-8000-000000000002', 'kpi659-boss@test.local', 'authenticated', 'authenticated'),
 ('86590000-0000-4000-8000-000000000003', 'kpi659-emp@test.local', 'authenticated', 'authenticated');

insert into public.employees(id, user_id, employee_code, full_name_ar, status, is_active, birth_date, hire_date) values
 ('86591000-0000-4000-8000-000000000001', '86590000-0000-4000-8000-000000000001', 'KPI659-MGR', 'مدير مباشر 0659', 'active', true, '1986-01-01', '2016-01-01'),
 ('86591000-0000-4000-8000-000000000002', '86590000-0000-4000-8000-000000000002', 'KPI659-BOSS', 'مدير إدارة 0659', 'active', true, '1980-01-01', '2010-01-01'),
 ('86591000-0000-4000-8000-000000000003', '86590000-0000-4000-8000-000000000003', 'KPI659-EMP', 'موظف 0659', 'active', true, '1994-01-01', '2021-01-01');

insert into public.profiles(id, employee_id, status)
select user_id, id, 'active' from public.employees
 where id in ('86591000-0000-4000-8000-000000000001',
              '86591000-0000-4000-8000-000000000002',
              '86591000-0000-4000-8000-000000000003');

-- المدير المباشر يحمل direct-manager وحده — كما في الإنتاج
insert into public.user_roles(user_id, role_id, effective_from)
select x.user_id, r.id, now()
  from (values
    ('86590000-0000-4000-8000-000000000001'::uuid, 'direct-manager'),
    ('86590000-0000-4000-8000-000000000002'::uuid, 'department-manager'),
    ('86590000-0000-4000-8000-000000000003'::uuid, 'employee')
  ) x(user_id, slug)
  join public.roles r on r.slug = x.slug;

insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
 ('86591000-0000-4000-8000-000000000001', '86591000-0000-4000-8000-000000000002', 'primary', current_date),
 ('86591000-0000-4000-8000-000000000003', '86591000-0000-4000-8000-000000000001', 'primary', current_date);

create temporary table t0659(cycle_id uuid, mgr_eval uuid, emp_eval uuid);
grant select on t0659 to authenticated;

-- دورة مفتوحة + تقييمان في مرحلة «ذاتي» (نمط 0036)
do $setup$
declare v_template uuid; v_policy uuid; v_cycle uuid;
begin
  select id into v_template from public.kpi_templates where official_code = 'OFFICIAL_KPI_100';
  select id into v_policy from public.kpi_policy_versions where is_active limit 1;
  insert into public.kpi_cycles(period_month, status, template_id, scheduled_open_at, deadline_at,
    self_due_at, manager_due_at, opened_at, policy_version_id, use_parallel_flow)
  values (date '2098-07-01', 'open', v_template, now(), date '2098-09-15',
    date '2098-09-15', date '2098-09-15', now(), v_policy, false)
  on conflict (period_month) do update set status = 'open', updated_at = now()
  returning id into v_cycle;

  insert into public.kpi_evaluations(employee_id, cycle_id, template_id, stage, current_stage, workflow_status, locked)
  values
    ('86591000-0000-4000-8000-000000000001', v_cycle, v_template, 'self', 'self', 'OPEN_FOR_SELF_EVALUATION', false),
    ('86591000-0000-4000-8000-000000000003', v_cycle, v_template, 'self', 'self', 'OPEN_FOR_SELF_EVALUATION', false)
  on conflict (employee_id, cycle_id, template_id) do update
    set stage = 'self', current_stage = 'self', workflow_status = 'OPEN_FOR_SELF_EVALUATION',
        locked = false, updated_at = now();

  insert into t0659(cycle_id, mgr_eval, emp_eval)
  select v_cycle,
         (select id from public.kpi_evaluations where cycle_id = v_cycle and employee_id = '86591000-0000-4000-8000-000000000001'),
         (select id from public.kpi_evaluations where cycle_id = v_cycle and employee_id = '86591000-0000-4000-8000-000000000003');
end $setup$;

-- =====================================================================
-- 1) كل دور غير كامل الوصول (عدا اللجنة) يملك self_assess بنطاق self
-- =====================================================================
select is(
  (select coalesce(string_agg(r.slug, ', ' order by r.slug), '')
     from public.roles r
    where not coalesce(r.is_full_access, false)
      and r.slug not like 'committee-%'
      and not exists (
        select 1 from public.role_permissions rp
          join public.permissions p on p.id = rp.permission_id
         where rp.role_id = r.id and p.code = 'performance.kpi.self_assess' and rp.scope = 'self')),
  '',
  'كل دور غير كامل الوصول يملك التقييم الذاتي بنطاق self');

-- =====================================================================
-- 2) المدير المباشر (direct-manager وحده) يرسل تقييمه الذاتي
-- =====================================================================
select set_config('request.jwt.claims', '{"sub":"86590000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '86590000-0000-4000-8000-000000000001', true);
set local role authenticated;

select ok(public.has_permission('performance.kpi.self_assess'),
  'مدير مباشر بدور direct-manager وحده يملك صلاحية التقييم الذاتي');

select lives_ok(
  $rt$
    select public.advance_kpi_stage(
      (select mgr_eval from t0659),
      'self',
      (select jsonb_agg(jsonb_build_object('criterion_id', c.id, 'score', round(c.max_score * 0.8, 2), 'note', 'تقييم ذاتي'))
         from public.kpi_criteria c
        where c.template_id = (select template_id from public.kpi_evaluations where id = (select mgr_eval from t0659))),
      'اكتمل التقييم الذاتي')
  $rt$,
  'المدير المباشر يرسل تقييمه الذاتي (كان FORBIDDEN)');

-- =====================================================================
-- 3) المنح لا يوسّع النطاق: لا يرسل التقييم الذاتي لموظفه
-- =====================================================================
select throws_ok(
  $rt$
    select public.advance_kpi_stage(
      (select emp_eval from t0659),
      'self',
      (select jsonb_agg(jsonb_build_object('criterion_id', c.id, 'score', 1, 'note', 'محاولة'))
         from public.kpi_criteria c
        where c.template_id = (select template_id from public.kpi_evaluations where id = (select emp_eval from t0659))),
      'محاولة عن الغير')
  $rt$,
  '42501', null,
  'المدير لا يرسل التقييم الذاتي لموظف آخر (الملكية ما زالت شرطًا)');

reset role;

select is(
  (select current_stage from public.kpi_evaluations where id = (select mgr_eval from t0659)),
  'manager_review',
  'تقييم المدير انتقل إلى مراجعة مديره');

select * from finish();
rollback;
