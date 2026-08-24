-- pgTAP test for migration 0464: HR صلاحية كاملة + المسار الطبيعي + الصندوق
-- Validates:
--   1-2 صندوق HR يرى طلبات الآخرين وطلبه
--   3 صندوق المدير يرى طلب مرؤوسه
--   4-6 صندوق أبو عمار: المصعَّد والمتجاوز نعم، ما قبل دوره لا
--   7 HR يعتمد طلبه الشخصي (إذن صريح — التعديل الوحيد على 0441)
--   8 HR يعتمد أي طلب (0441 مستعادة)
--   9 المدير المباشر يعتمد بعد التصعيد وتجاوز الوقت (أي وقت/أي يوم)
--   10 أبو عمار: المتجاوز نعم / الجديد قبل دوره لا / ذاته لا (حظر لغير HR)

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

do $fixture$
declare
  v_entity uuid := '99000000-0000-4000-8000-000000000000';
  v_dept   uuid := '99000000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, '0462-LE', 'كيان 0462');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, '0462-D', 'إدارة 0462');

  insert into auth.users(id, email, aud, role) values
    ('99000000-0000-4000-8000-000000000301', '0462-emp@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000302', '0462-mgr@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000303', '0462-ops@test.local', 'authenticated', 'authenticated'),
    ('99000000-0000-4000-8000-000000000305', '0462-hrmgr@test.local', 'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('99000000-0000-4000-8000-000000000401', '99000000-0000-4000-8000-000000000301',
     '0462-EMP', 'موظف 0462', v_dept, 'active', true, current_date - 1000),
    ('99000000-0000-4000-8000-000000000402', '99000000-0000-4000-8000-000000000302',
     '0462-MGR', 'مدير 0462', v_dept, 'active', true, current_date - 1500),
    ('99000000-0000-4000-8000-000000000403', '99000000-0000-4000-8000-000000000303',
     '0462-OPS', 'أبو عمار 0462', v_dept, 'active', true, current_date - 1200),
    ('99000000-0000-4000-8000-000000000405', '99000000-0000-4000-8000-000000000305',
     '0462-HRM', 'مدير موارد بشرية 0462', v_dept, 'active', true, current_date - 1300);

  insert into public.profiles(id, employee_id, status) values
    ('99000000-0000-4000-8000-000000000301', '99000000-0000-4000-8000-000000000401', 'active'),
    ('99000000-0000-4000-8000-000000000302', '99000000-0000-4000-8000-000000000402', 'active'),
    ('99000000-0000-4000-8000-000000000303', '99000000-0000-4000-8000-000000000403', 'active'),
    ('99000000-0000-4000-8000-000000000305', '99000000-0000-4000-8000-000000000405', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('99000000-0000-4000-8000-000000000401', '99000000-0000-4000-8000-000000000402', 'primary', current_date),
    ('99000000-0000-4000-8000-000000000405', '99000000-0000-4000-8000-000000000402', 'primary', current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000303', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-manager-1';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '99000000-0000-4000-8000-000000000305', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'hr-manager';
end
$fixture$;

create or replace function pg_temp.act_as_0462(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

create temporary table t0462_runtime(kind text primary key, id uuid);
grant select, insert, update on t0462_runtime to authenticated;

do $emp$
declare
  v_req public.requests;
begin
  -- FRESH: طلب جديد لم تتجاوز مهلته (خطوة 1 = المدير المباشر)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000301');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب جديد 0462', 'لم تتجاوز مهلته', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('FRESH', v_req.id);
  reset role;

  -- ESC: طلب سيُصعَّد إلى الخطوة 2 (أبو عمار)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000301');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب مصعَّد 0462', 'سيصل لأبو عمار', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('ESC', v_req.id);
  reset role;

  -- OLD: طلب قديم متجاوز المهلة عند خطوة 1 (أبو عمار يتدخل بند 0440)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000301');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب قديم 0462', 'متجاوز المهلة', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('OLD', v_req.id);
  reset role;

  -- OWN: طلب HR الذاتي (اختبار حظر الذات)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب HR الذاتي 0462', 'اختبار ذاتي', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('OWN', v_req.id);
  reset role;

  -- FRESH2: طلب تحكم يبقى معلقاً (أبو عمار ممنوع عليه قبل دوره)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000301');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب تحكم معلق 0464', 'بلا تصعيد', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('FRESH2', v_req.id);
  reset role;

  -- OPSOWN: طلب يقدّمه أبو عمار نفسه (اختبار حظر الذات لغير HR)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب أبو عمار الذاتي 0464', 'اختبار ذاتي لغير HR', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('OPSOWN', v_req.id);
  reset role;
end $emp$;

-- OLD: محاكاة تجاوز 10 أيام عند الخطوة 1
update public.request_steps set
  escalation_deadline = now() - interval '10 days',
  due_at = now() - interval '10 days',
  status = 'active',
  updated_at = now()
where request_id = (select id from t0462_runtime where kind='OLD')
  and step_order = 1;

-- ESC: محاكاة تصعيد الخطوة 1 وانتقال الدور للخطوة 2 (أبو عمار)
update public.request_steps set
  status = 'escalated',
  escalation_deadline = now() - interval '1 day',
  updated_at = now()
where request_id = (select id from t0462_runtime where kind='ESC')
  and step_order = 1;
update public.request_steps set
  status = 'active',
  updated_at = now()
where request_id = (select id from t0462_runtime where kind='ESC')
  and step_order = 2;
update public.requests set
  workflow_status = 'escalated',
  updated_at = now()
where id = (select id from t0462_runtime where kind='ESC');

-- ═══ صندوق الإجراءات: الرؤية قبل أي قرارات ═══
-- HR يرى طلبات الموظفين المعلقة (صلاحيته الكاملة) وطلبته هو أيضاً
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='FRESH')),
  1, '1 HR يرى الطلب المعلق لموظف آخر في الصندوق');
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='OWN')),
  1, '2 HR يرى طلبه الشخصي المعلق في الصندوق');
reset role;

-- المدير المباشر يرى طلب مرؤوسه المعلق
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000302');
set local role authenticated;
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='FRESH2')),
  1, '3 المدير المباشر يرى الطلب المعلق لمرؤوسه');
reset role;

-- أبو عمار يرى المصعَّد إليه والمتجاوز، ولا يرى ما لم يصل دوره
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
set local role authenticated;
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='ESC')),
  1, '4 أبو عمار يرى الطلب المصعَّد إليه');
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='OLD')),
  1, '5 أبو عمار يرى الطلب المتجاوز (0440)');
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='FRESH2')),
  1, '6 أبو عمار يرى المعلق كذلك — دوره يحمل صلاحية اعتماد تنظيمية (0416)');
reset role;

-- ═══ القرارات ═══
-- 7 HR يعتمد طلبه الشخصي (إذن صريح — 0464)
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OWN'), 'approve', 'HR على طلبه — إذن 0464')$live$,
  '7 HR يعتمد طلبه الشخصي (صلاحية كاملة)');
reset role;

-- 8 HR يعتمد طلب موظف آخر (غير مقيد كما في 0441)
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='FRESH'), 'approve', 'HR غير مقيد')$live$,
  '8 HR يعتمد أي طلب في أي وقت (0441 مستعادة)');
reset role;

-- 9 المدير المباشر يعتمد طلباً بعد تصعيده لأبو عمار (أي وقت — 0464)
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000302');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='ESC'), 'approve', 'المدير بعد التصعيد')$live$,
  '9 المدير المباشر يعتمد بعد التصعيد وتجاوز الوقت');
reset role;

-- 10 أبو عمار يعتمد الطلب المتجاوز (0440)
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OLD'), 'approve', 'أبو عمار على المتجاوز')$live$,
  '10 أبو عمار يعتمد المتجاوز — المسار الطبيعي');
select throws_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='FRESH2'), 'approve', 'أبو عمار مبكراً')$live$,
  '42501', null, '10ب أبو عمار ممنوع قبل دوره على الطلب الجديد');
select throws_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OPSOWN'), 'approve', 'أبو عمار على طلبه')$live$,
  '42501', null, '10ج حظر الذات قائم لغير HR');
reset role;

select * from finish();
rollback;
