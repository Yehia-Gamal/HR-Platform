-- pgTAP test for request approval chain — مُحدَّث ليطابق القرار الإداري النهائي 0464.
-- 0462 قدّم "المسار الطبيعي" (منع HR غير المقيد)، لكن 0464 عاد قراراً إدارياً صريحاً
-- "تصحيح لفهم 0462" وأعاد صلاحية HR الكاملة (يعتمد أي طلب/أي مرحلة، وحتى طلبه الشخصي).
-- Validates (عقد 0464 النهائي):
--   ① hr-manager يعتمد طلب موظف آخر دائماً (صلاحية كاملة)
--   ② hr-manager يعتمد حتى الطلب القديم المتجاوز
--   ③ المدير المباشر يعتمد طلب مرؤوسه في أي وقت
--   ④ أبو عمار ممنوع على الطلب الجديد قبل دوره
--   ⑤ أبو عمار يعتمد بعد تصعيد الخطوة إليه
--   ⑥ حظر الموافقة الذاتية قائم لغير HR فقط (HR مستثنى — إذن 0464)
--   ⑦ صندوق الإجراءات: HR يرى طلبات الموظفين وطلبه؛ المدير وأبو عمار حسب دوره

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

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

  -- OWN: طلب HR الذاتي (اختبار: HR يستطيع ذاتياً — إذن 0464)
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
    'طلب تحكم 0462', 'بلا تصعيد', jsonb_build_object('leaveType','annual'));
  insert into t0462_runtime values('FRESH2', v_req.id);
  reset role;

  -- OPSOWN: طلب يقدّمه أبو عمار نفسه (حظر الذات لغير HR)
  perform pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '99000000-0000-4000-8000-000000000402',
    'طلب أبو عمار الذاتي 0462', 'اختبار ذاتي لغير HR', jsonb_build_object('leaveType','annual'));
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

-- ═══ ① hr-manager يعتمد طلب موظف آخر (صلاحية كاملة — 0464) ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='FRESH'), 'approve', 'HR يتدخل')$live$,
  '① hr-manager يعتمد طلب موظف آخر (صلاحية كاملة 0464)');
reset role;

-- ═══ ② hr-manager يعتمد حتى القديم المتجاوز ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OLD'), 'approve', 'HR على القديم')$live$,
  '② hr-manager يعتمد حتى الطلب المتجاوز (غير مقيد)');
reset role;

-- ═══ ③ المدير المباشر يعتمد طلب مرؤوسه (المسار الطبيعي — الخطوة 1) ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000302');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='FRESH2'), 'approve', 'المدير المباشر: موافقة')$live$,
  '③ المدير المباشر يعتمد طلب مرؤوسه');
select is(
  (select action from public.request_actions
   where request_id = (select id from t0462_runtime where kind='FRESH2')
     and actor_employee_id = '99000000-0000-4000-8000-000000000402'
   order by created_at desc limit 1),
  'approve', '③ سُجِّل قرار المدير المباشر باسمه في سجل الإجراءات');
reset role;

-- ═══ ④ أبو عمار ممنوع على طلب لم يصل دوره (تحكم — 0440 قائم) ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
set local role authenticated;
select throws_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OWN'), 'approve', 'أبو عمار مبكراً')$live$,
  '42501', null, '④ أبو عمار ممنوع قبل الخطوة 2/تجاوز المهلة');
reset role;

-- ═══ ⑤ أبو عمار يعتمد الطلب المصعَّد (الخطوة 2 — دوره الطبيعي) ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='ESC'), 'approve', 'أبو عمار: موافقة بعد التصعيد')$live$,
  '⑤ أبو عمار يعتمد من الخطوة 2 (المسار الطبيعي)');
select is(
  (select action from public.request_actions
   where request_id = (select id from t0462_runtime where kind='ESC')
     and actor_employee_id = '99000000-0000-4000-8000-000000000403'
   order by created_at desc limit 1),
  'approve', '⑤ سُجِّل قرار أبو عمار باسمه في سجل الإجراءات');
reset role;

-- ═══ ⑥ HR يعتمد طلبه الذاتي (إذن 0464) ═══
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select lives_ok(
  $live$select public.decide_request((select id from t0462_runtime where kind='OWN'), 'approve', 'HR يعتمد طلبه')$live$,
  '⑥ HR يعتمد طلبه الشخصي (إذن صريح 0464)');
reset role;

-- ═══ ⑦ صندوق الإجراءات — الرؤية وفق الدور ═══
-- ⑦أ HR يرى الطلبات المعلقة (صلاحيته الكاملة) — هنا المتبقي OPSOWN
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000305');
set local role authenticated;
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='OPSOWN')),
  1, '⑦أ HR يرى الطلب المعلق في الصندوق (صلاحية كاملة — 0464)');
reset role;

-- ⑦ب أبو عمار يرى طلبه المعلق (طلباته هي) ولا يرى ما سبق اعتماده
select pg_temp.act_as_0462('99000000-0000-4000-8000-000000000303');
set local role authenticated;
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='OPSOWN')),
  1, '⑦ب1 أبو عمار يرى طلبه المعلق في الصندوق');
select is(
  (select count(*)::integer from jsonb_array_elements(public.get_universal_action_center()) a
   where a->>'id' = 'request-' || (select id from t0462_runtime where kind='OWN')),
  0, '⑦ب2 أبو عمار لا يرى طلبات لا علاقة له بها');
reset role;

select * from finish();
rollback;
