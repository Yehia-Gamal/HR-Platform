-- =====================================================================
-- 0410: إصلاح الجداء الديكارتي في get_mobile_operations_center
--   1. الموظف الهدف لديه 2 مهمات + 3 مهمات + قافلتان.
--      الـ RPC القديم (0408) كان يعيد 2×3×2 = 12 عنصر مهمات وعدّادات مضخّمة.
--      الصحيح: tasks=2, missions=3, convoys=2.
--   2. الحارس: الموظف العادي يُرفض 42501، الصلاحية الكاملة يقرأ.
--   3. أسماء الموظفين وحالة الطلبات تُحل من الجداول المرتبطة.
-- 11 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

-- تعطيل trigger الإشعارات لتجنب أخطاء الـ fixture
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

select has_function(
  'public', 'get_mobile_operations_center', array[]::text[],
  '0410: دالة get_mobile_operations_center موجودة'
);

select ok(
  NOT has_function_privilege('anon', 'public.get_mobile_operations_center()', 'EXECUTE'),
  '0410: anon لا تملك EXECUTE على get_mobile_operations_center'
);

select ok(
  has_function_privilege('authenticated', 'public.get_mobile_operations_center()', 'EXECUTE'),
  '0410: authenticated لديها EXECUTE على get_mobile_operations_center'
);

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
declare
  v_le         uuid := 'b4a40000-0000-4000-8000-000000000000';
  v_dept       uuid := 'b4a40000-0000-4000-8000-000000000010';
  v_user_admin uuid := 'b4a40000-0000-4000-8000-000000000001';
  v_user_emp   uuid := 'b4a40000-0000-4000-8000-000000000002';
  v_emp_admin  uuid := 'b4a40000-0000-4000-8000-000000000011';
  v_emp_target uuid := 'b4a40000-0000-4000-8000-000000000012';
  v_role_admin uuid;
  v_role_emp   uuid;
  v_req_m1     uuid := 'b4a40000-0000-4000-8000-000000000101';
  v_req_m2     uuid := 'b4a40000-0000-4000-8000-000000000102';
  v_req_m3     uuid := 'b4a40000-0000-4000-8000-000000000103';
  v_req_c1     uuid := 'b4a40000-0000-4000-8000-000000000104';
  v_req_c2     uuid := 'b4a40000-0000-4000-8000-000000000105';
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'B4A4-LE', 'كيان اختبار مركز العمليات 0410');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'B4A4-D1', 'إدارة اختبار 0410');

  insert into auth.users (id, email, aud, role) values
    (v_user_admin, 'b4a4-admin@test.local', 'authenticated', 'authenticated'),
    (v_user_emp,   'b4a4-emp@test.local',   'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    (v_emp_admin,  v_user_admin, 'B4A4-ADM', 'مسؤول الاختبار', v_dept, 'active', true, false),
    (v_emp_target, v_user_emp,   'B4A4-TGT', 'موظف الهدف',     v_dept, 'active', true, false);

  insert into public.profiles (id, employee_id, status) values
    (v_user_admin, v_emp_admin,  'active'),
    (v_user_emp,   v_emp_target, 'active');

  select id into v_role_admin from public.roles where is_full_access = true order by slug limit 1;
  select id into v_role_emp from public.roles where slug = 'employee';

  insert into public.user_roles (user_id, role_id) values
    (v_user_admin, v_role_admin),
    (v_user_emp,   v_role_emp);

  -- 3 طلبات مأمورية بحالات مختلفة + قافلتان
  insert into public.requests (id, request_type, employee_id, status) values
    (v_req_m1, 'mission', v_emp_target, 'approved'),
    (v_req_m2, 'mission', v_emp_target, 'pending'),
    (v_req_m3, 'mission', v_emp_target, 'rejected'),
    (v_req_c1, 'convoy',  v_emp_target, 'pending'),
    (v_req_c2, 'convoy',  v_emp_target, 'approved');

  insert into public.missions (id, request_id, employee_id, destination, purpose, start_at, end_at) values
    (v_req_m1, v_req_m1, v_emp_target, 'المنصورة', 'معاينة موقع', '2026-08-01 08:00+03', '2026-08-01 14:00+03'),
    (v_req_m2, v_req_m2, v_emp_target, 'طنطا',     'تسليم مساعدات', '2026-08-03 08:00+03', '2026-08-03 15:00+03'),
    (v_req_m3, v_req_m3, v_emp_target, 'الزقازيق', 'اجتماع تعاون', '2026-08-05 09:00+03', '2026-08-05 13:00+03');

  insert into public.convoy_requests (id, request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, passengers_count, vehicles_count) values
    (v_req_c1, v_req_c1, v_emp_target, 'قافلة المساعدات', 'القاهرة', 'المنصورة', '2026-08-06 07:00+03', '2026-08-06 18:00+03', 12, 2),
    (v_req_c2, v_req_c2, v_emp_target, 'قافلة الكساء',     'القاهرة', 'طنطا',     '2026-08-08 07:00+03', '2026-08-08 17:00+03', 8, 1);

  -- مهمتان: واحدة عاجلة وواحدة عادية (كلاهما مفتوح)
  insert into public.tasks (id, title, description, assignee_employee_id, priority, status) values
    ('b4a40000-0000-4000-8000-000000000201', 'تجهيز سيارات القافلة', 'فحص المركبات', v_emp_target, 'urgent', 'in_progress'),
    ('b4a40000-0000-4000-8000-000000000202', 'طباعة كشوف التوزيع',   'إعداد الوثائق', v_emp_target, 'medium', 'pending');
end
$fixture$;

-- =====================================================================
-- الموظف العادي يُرفض (42501)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"b4a40000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'b4a40000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_mobile_operations_center()$$,
  '42501', null,
  '0410: الموظف العادي لا يقرأ مركز العمليات (لا tasks.read ولا operations.*)'
);

-- =====================================================================
-- الصلاحية الكاملة يقرأ — والنتائج بلا جداء ديكارتي
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"b4a40000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'b4a40000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select is(
  (select jsonb_array_length(public.get_mobile_operations_center() -> 'tasks')),
  2,
  '0410: المهمات 2 وليست 2×3×2 (لا تضخيم ديكارتي)'
);

select is(
  (select (public.get_mobile_operations_center() -> 'summary' ->> 'openTasks')::int),
  2,
  '0410: openTasks = 2 (مهمتان مفتوحتان)'
);

select is(
  (select (public.get_mobile_operations_center() -> 'summary' ->> 'urgentTasks')::int),
  1,
  '0410: urgentTasks = 1 (مهمة عاجلة واحدة)'
);

select is(
  (select jsonb_array_length(public.get_mobile_operations_center() -> 'missions')),
  3,
  '0410: المأموريات 3 وليست مضاعفة'
);

select is(
  (select jsonb_array_length(public.get_mobile_operations_center() -> 'convoys')),
  2,
  '0410: القوافل 2 وليست مضاعفة'
);

select is(
  (select (public.get_mobile_operations_center() -> 'missions')
          @> '[{"id":"b4a40000-0000-4000-8000-000000000101","status":"approved"}]'::jsonb),
  true,
  '0410: حالة المأمورية تُحل من جدول requests (approved)'
);

select is(
  (select (public.get_mobile_operations_center() -> 'tasks')
          @> '[{"id":"b4a40000-0000-4000-8000-000000000201","assigneeName":"موظف الهدف"}]'::jsonb),
  true,
  '0410: اسم المسند إليه يُحل من جدول employees'
);

reset role;
select * from finish();
rollback;
