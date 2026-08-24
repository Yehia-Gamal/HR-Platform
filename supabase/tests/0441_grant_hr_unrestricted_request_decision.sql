-- pgTAP test for migration 0441 — مُحدَّث لعقد 0462.
-- صلاحيات HR (hr-manager / hr-specialist) ما زالت ممنوحة في role_permissions،
-- لكن 0462 ألغى تجاوز القرار غير المقيد: قرار الطلب يسير بالمسار الطبيعي فقط
-- (مدير مباشر / أبو عمار وفق شروطه / full_access).
-- Validates:
--   ① hr-manager لا يعتمد طلباً جديداً لم تتجاوز مهلته (42501)
--   ② hr-specialist لا يعتمد طلباً قديماً متجاوزاً (42501)
--   ③ خطوات الطلب تبقى مفتوحة بعد رفض محاولة HR
--   ④ أبو عمار ما زال مقيداً على الطلب الجديد (تحكم)
--   ⑤ ضابط العمليات ما زال ممنوعاً (تحكم)
--   ⑥ HR لا يعتمد طلبه الذاتي (حماية فساد قائمة)
--   ⑦ لا يُسجَّل أي إجراء باسم HR على الطلب المرفوض محاولته

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

do $fixture$
declare
  v_entity uuid := '99000000-0000-4000-8000-000000000000';
  v_dept   uuid := '99000000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, '0441-LE', 'كيان 0441');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, '0441-D', 'إدارة 0441');

  insert into auth.users(id, email, aud, role) values
    ('99000000-0000-4000-8000-000000000101', '0441-emp@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000102', '0441-mgr@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000103', '0441-ops@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000104', '0441-officer@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000105', '0441-hrmgr@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000106', '0441-hrspec@test.local', 'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('99000000-0000-4000-8000-000000000201', '99000000-0000-4000-8000-000000000101',
     '0441-EMP', 'موظف 0441', v_dept, 'active', true, current_date - 1000),
    ('99000000-0000-4000-8000-000000000202', '99000000-0000-4000-8000-000000000102',
     '0441-MGR', 'مدير 0441', v_dept, 'active', true, current_date - 1500),
    ('99000000-0000-4000-8000-000000000203', '99000000-0000-4000-8000-000000000103',
     '0441-OPS', 'أبو عمار 0441', v_dept, 'active', true, current_date - 1200),
    ('99000000-0000-4000-8000-000000000204', '99000000-0000-4000-8000-000000000104',
     '0441-OFF', 'ضابط عمليات 0441', v_dept, 'active', true, current_date - 1100),
    ('99000000-0000-4000-8000-000000000205', '99000000-0000-4000-8000-000000000105',
     '0441-HRM', 'مدير موارد بشرية 0441', v_dept, 'active', true, current_date - 1300),
    ('99000000-0000-4000-8000-000000000206', '99000000-0000-4000-8000-000000000106',
     '0441-HRS', 'أخصائي موارد بشرية 0441', v_dept, 'active', true, current_date - 1200);

  insert into public.profiles(id, employee_id, status) values
    ('99000000-0000-4000-8000-000000000101', '99000000-0000-4000-8000-000000000201', 'active'),
    ('99000000-0000-4000-8000-000000000102', '99000000-0000-4000-8000-000000000202', 'active'),
    ('99000000-0000-4000-8000-000000000103', '99000000-0000-4000-8000-000000000203', 'active'),
    ('99000000-0000-4000-8000-000000000104', '99000000-0000-4000-8000-000000000204', 'active'),
    ('99000000-0000-4000-8000-000000000105', '99000000-0000-4000-8000-000000000205', 'active'),
    ('99000000-0000-4000-8000-000000000106', '99000000-0000-4000-8000-000000000206', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('99000000-0000-4000-8000-000000000201', '99000000-0000-4000-8000-000000000202', 'primary', current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000103', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-manager-1';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000104', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-officer';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000105', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'hr-manager';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000106', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'hr-specialist';
end
$fixture$;

create or replace function pg_temp.act_as_0441(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

create temporary table t0441_runtime(kind text primary key, id uuid);
grant select, insert, update on t0441_runtime to authenticated;

do $emp$
declare
  v_req public.requests;
begin
  -- FRESH: جديد لم تتجاوز مهلته
  perform pg_temp.act_as_0441('99000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000202',
    'طلب جديد 0441', 'لم تتجاوز مهلته', jsonb_build_object('leaveType','annual'));
  insert into t0441_runtime values('FRESH', v_req.id);
  reset role;
  -- OLD: قديم متجاوز عند خطوة 1
  perform pg_temp.act_as_0441('99000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000202',
    'طلب قديم 0441', 'متجاوز', jsonb_build_object('leaveType','annual'));
  insert into t0441_runtime values('OLD', v_req.id);
  reset role;
  -- FRESH2: للتحكم (أبو عمار / ضابط العمليات)
  perform pg_temp.act_as_0441('99000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000202',
    'طلب تحكم 0441', 'لم تتجاوز مهلته', jsonb_build_object('leaveType','annual'));
  insert into t0441_runtime values('FRESH2', v_req.id);
  reset role;
  -- OWN: طلب يقدّمه موظف HR نفسه (لاختبار منع الموافقة الذاتية)
  perform pg_temp.act_as_0441('99000000-0000-4000-8000-000000000105');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000202',
    'طلب HR الذاتي 0441', 'اختبار ذاتي', jsonb_build_object('leaveType','annual'));
  insert into t0441_runtime values('OWN', v_req.id);
  reset role;
end $emp$;

-- OLD: محاكاة مرور 10 أيام — خطوة 1 active متجاوزة
update public.request_steps set
  escalation_deadline = now() - interval '10 days',
  due_at = now() - interval '10 days',
  status = 'active',
  updated_at = now()
where request_id = (select id from t0441_runtime where kind='OLD')
  and step_order = 1;

-- ═══ ① hr-manager مرفوض على الطلب الجديد (المسار الطبيعي فقط — 0462) ═══
select pg_temp.act_as_0441('99000000-0000-4000-8000-000000000105');
set local role authenticated;

select throws_ok(
  $live$select public.decide_request((select id from t0441_runtime where kind='FRESH'), 'approve', 'HR مدير: طلب جديد')$live$,
  '42501', null, '① hr-manager لا يعتمد الطلب الجديد قبل انتهاء المهلة (0462 ألغى التجاوز)');

select is(
  (select status from public.requests
   where id = (select id from t0441_runtime where kind='FRESH')),
  'pending', '① طلب HR يبقى معلقاً بعد رفض المحاولة');

select is(
  (select count(*)::integer from public.request_actions
   where request_id = (select id from t0441_runtime where kind='FRESH')
     and actor_employee_id = '99000000-0000-4000-8000-000000000205'),
  0, '⑦ لا يُسجَّل أي إجراء باسم HR على الطلب');

select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from t0441_runtime where kind='FRESH')
     and status in ('active','pending','escalated')),
  2, '③ خطوتا الطلب ما زالتا مفتوحتين بعد رفض محاولة HR');

reset role;

-- ═══ ② hr-specialist مرفوض على الطلب القديم المتجاوز ═══
select pg_temp.act_as_0441('99000000-0000-4000-8000-000000000106');
set local role authenticated;

select throws_ok(
  $live$select public.decide_request((select id from t0441_runtime where kind='OLD'), 'approve', 'HR أخصائي: طلب قديم')$live$,
  '42501', null, '② hr-specialist لا يعتمد الطلب القديم المتجاوز (0462)');

reset role;

-- ═══ ④-⑤ تحكم: أبو عمار وضابط العمليات ما زالا مقيدين على الجديد ═══
select pg_temp.act_as_0441('99000000-0000-4000-8000-000000000103');
set local role authenticated;
select throws_ok(
  $live$select public.decide_request((select id from t0441_runtime where kind='FRESH2'), 'approve', 'أبو عمار مبكراً')$live$,
  '42501', null, '④ أبو عمار ما زال ممنوعاً من الطلب الجديد قبل المهلة');
reset role;

select pg_temp.act_as_0441('99000000-0000-4000-8000-000000000104');
set local role authenticated;
select throws_ok(
  $live$select public.decide_request((select id from t0441_runtime where kind='FRESH2'), 'approve', 'ضابط عمليات')$live$,
  '42501', null, '⑤ ضابط العمليات ممنوع من الطلب الجديد');
reset role;

-- ═══ ⑥ HR لا يعتمد طلبه الذاتي ═══
select pg_temp.act_as_0441('99000000-0000-4000-8000-000000000105');
set local role authenticated;
select throws_ok(
  $live$select public.decide_request((select id from t0441_runtime where kind='OWN'), 'approve', 'HR يعتمد طلبه')$live$,
  '42501', null, '⑥ HR لا يعتمد طلبه الذاتي (حماية فساد قائمة)');
reset role;

select * from finish();
rollback;