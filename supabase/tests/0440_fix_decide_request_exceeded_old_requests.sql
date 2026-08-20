-- pgTAP test for migration 0440: قرار الطلبات القديمة المتجاوزة لمهلة التصعيد.
-- Validates:
--   ① مدير التشغيل 1 (أبو عمار) يعتمد طلباً عالقاً عند خطوة 1 ومهلته منتهية
--   ② أبو عمار يعتمد طلباً قديماً بلا خطوة 2 (وسمُه escalated)
--   ③ أبو عمار ما زال ممنوعاً من الطلبات الجديدة قبل انتهاء مهلة المدير
--   ④ ضابط العمليات (ليس operations-manager-1) ممنوع حتى على الطلبات المتجاوزة
--   ⑤ المدير المباشر يعتمد المتجاوز كما كان (لا تغيير)
--   ⑥ التحكم: الطلب المصعّد طبيعياً إلى خطوة 2 يعتمد من أبو عمار

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

do $fixture$
declare
  v_entity uuid := '98000000-0000-4000-8000-000000000000';
  v_dept   uuid := '98000000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, '0440-LE', 'كيان 0440');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, '0440-D', 'إدارة 0440');

  insert into auth.users(id, email, aud, role) values
    ('98000000-0000-4000-8000-000000000101', '0440-emp@test.local', 'authenticated', 'authenticated'),
    ('98000000-0000-4000-8000-000000000102', '0440-mgr@test.local', 'authenticated', 'authenticated'),
    ('98000000-0000-4000-8000-000000000103', '0440-ops@test.local', 'authenticated', 'authenticated'),
    ('98000000-0000-4000-8000-000000000104', '0440-officer@test.local', 'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('98000000-0000-4000-8000-000000000201', '98000000-0000-4000-8000-000000000101',
     '0440-EMP', 'موظف 0440', v_dept, 'active', true, current_date - 1000),
    ('98000000-0000-4000-8000-000000000202', '98000000-0000-4000-8000-000000000102',
     '0440-MGR', 'مدير 0440', v_dept, 'active', true, current_date - 1500),
    ('98000000-0000-4000-8000-000000000203', '98000000-0000-4000-8000-000000000103',
     '0440-OPS', 'أبو عمار 0440', v_dept, 'active', true, current_date - 1200),
    ('98000000-0000-4000-8000-000000000204', '98000000-0000-4000-8000-000000000104',
     '0440-OFF', 'ضابط عمليات 0440', v_dept, 'active', true, current_date - 1100);

  insert into public.profiles(id, employee_id, status) values
    ('98000000-0000-4000-8000-000000000101', '98000000-0000-4000-8000-000000000201', 'active'),
    ('98000000-0000-4000-8000-000000000102', '98000000-0000-4000-8000-000000000202', 'active'),
    ('98000000-0000-4000-8000-000000000103', '98000000-0000-4000-8000-000000000203', 'active'),
    ('98000000-0000-4000-8000-000000000104', '98000000-0000-4000-8000-000000000204', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('98000000-0000-4000-8000-000000000201', '98000000-0000-4000-8000-000000000202', 'primary', current_date);

  -- أبو عمار: operations-manager-1 — ضابط العمليات: operations-officer فقط
  insert into public.user_roles(user_id, role_id, effective_from)
    select '98000000-0000-4000-8000-000000000103', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-manager-1';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '98000000-0000-4000-8000-000000000104', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-officer';
end
$fixture$;

create or replace function pg_temp.act_as_0440(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

create temporary table t0440_runtime(kind text primary key, id uuid);
grant select, insert, update on t0440_runtime to authenticated;

-- إنشاء الطلبات
do $emp$
declare
  v_req public.requests;
begin
  perform pg_temp.act_as_0440('98000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '98000000-0000-4000-8000-000000000202',
    'طلب متجاوز 0440', 'عالق عند خطوة 1', jsonb_build_object('leaveType','annual'));
  insert into t0440_runtime values('STUCK', v_req.id);
  reset role;
  perform pg_temp.act_as_0440('98000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '98000000-0000-4000-8000-000000000202',
    'طلب بلا خطوة 2 0440', 'بنية قديمة', jsonb_build_object('leaveType','annual'));
  insert into t0440_runtime values('NOSTEP2', v_req.id);
  reset role;
  perform pg_temp.act_as_0440('98000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '98000000-0000-4000-8000-000000000202',
    'طلب صُعّد 0440', 'خطوة 2 نشطة', jsonb_build_object('leaveType','annual'));
  insert into t0440_runtime values('ESCALATED', v_req.id);
  reset role;
  perform pg_temp.act_as_0440('98000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '98000000-0000-4000-8000-000000000202',
    'طلب جديد 0440', 'لم تتجاوز مهلته', jsonb_build_object('leaveType','annual'));
  insert into t0440_runtime values('FRESH', v_req.id);
  reset role;
  perform pg_temp.act_as_0440('98000000-0000-4000-8000-000000000101');
  set local role authenticated;
  v_req := public.submit_request('leave', null,
    '98000000-0000-4000-8000-000000000202',
    'طلب متجاوز آخر 0440', 'لاختبار الضابط والمدير', jsonb_build_object('leaveType','annual'));
  insert into t0440_runtime values('OLD2', v_req.id);
  reset role;
end $emp$;

-- محاكاة مرور 10 أيام على الخطوة 1 لكل الطلبات القديمة
update public.request_steps set
  escalation_deadline = now() - interval '10 days',
  due_at = now() - interval '10 days'
where request_id in (select id from t0440_runtime where kind in ('STUCK','NOSTEP2','ESCALATED','OLD2'))
  and step_order = 1;

-- OLD2: خطوة 1 active متجاوزة (كحالة STUCK تماماً — لا يصعّد الكروان)
update public.request_steps set status = 'active', updated_at = now()
where request_id = (select id from t0440_runtime where kind='OLD2') and step_order = 1;

-- STUCK: الخطوة 1 active (الكروان لم يصعّد — الوضع الحقيقي للطلبات العالقة)
update public.request_steps set status = 'active', updated_at = now()
where request_id = (select id from t0440_runtime where kind='STUCK') and step_order = 1;

-- NOSTEP2: حذف الخطوة 2 (أقدم البنى) — الخطوة 1 escalated
delete from public.request_steps
where request_id = (select id from t0440_runtime where kind='NOSTEP2') and step_order = 2;
update public.request_steps set status = 'escalated', escalated_at = now() - interval '9 days', updated_at = now()
where request_id = (select id from t0440_runtime where kind='NOSTEP2') and step_order = 1;

-- ESCALATED: صُعّد طبيعياً — خطوة 2 active بمهلة منتهية أيضاً
update public.request_steps set status = 'escalated', escalated_at = now() - interval '9 days', updated_at = now()
where request_id = (select id from t0440_runtime where kind='ESCALATED') and step_order = 1;
update public.request_steps set status = 'active', due_at = now() - interval '8 days',
  escalation_deadline = now() - interval '8 days', updated_at = now()
where request_id = (select id from t0440_runtime where kind='ESCALATED') and step_order = 2;

-- ═══ ①-③ كأبو عمار (operations-manager-1) ═══
select pg_temp.act_as_0440('98000000-0000-4000-8000-000000000103');
set local role authenticated;

select lives_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='STUCK'), 'approve', 'أبو عمار: الطلب العالق')$live$,
  '① أبو عمار يعتمد الطلب العالق عند خطوة 1 بمهلة منتهية');

select is(
  (select status from public.requests
   where id = (select id from t0440_runtime where kind='STUCK')),
  'approved', '① الطلب العالق أصبح معتمداً');

select lives_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='NOSTEP2'), 'approve', 'أبو عمار: بلا خطوة 2')$live$,
  '② أبو عمار يعتمد الطلب القديم بلا خطوة 2 (escalated)');

select lives_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='ESCALATED'), 'approve', 'أبو عمار: خطوة 2')$live$,
  '⑥ التحكم: أبو عمار يعتمد الطلب المصعّد طبيعياً إلى خطوة 2');

select throws_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='FRESH'), 'approve', 'أبو عمار مبكراً')$live$,
  '42501', null, '③ أبو عمار ما زال ممنوعاً من الطلب الجديد قبل انتهاء مهلة المدير');

reset role;

-- ═══ ④ ضابط العمليات (ليس operations-manager-1) ═══
select pg_temp.act_as_0440('98000000-0000-4000-8000-000000000104');
set local role authenticated;

select throws_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='OLD2'), 'approve', 'ضابط عمليات يحاول')$live$,
  '42501', null, '④ ضابط العمليات ممنوع حتى على الطلبات المتجاوزة (أبو عمار فقط)');

reset role;

-- ═══ ⑤ المدير المباشر ═══
select pg_temp.act_as_0440('98000000-0000-4000-8000-000000000102');
set local role authenticated;

select lives_ok(
  $live$select public.decide_request((select id from t0440_runtime where kind='OLD2'), 'approve', 'المدير المباشر')$live$,
  '⑤ المدير المباشر يعتمد الطلب المتجاوز (لا تغيير)');

reset role;

-- ═══ تحقق إضافي: إغلاق كل خطوات الطلب العالق بعد الاعتماد ═══
select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from t0440_runtime where kind='STUCK')
     and status in ('active','pending','escalated')),
  0, 'أُغلقت جميع خطوات الطلب العالق بعد الاعتماد');

select * from finish();
rollback;