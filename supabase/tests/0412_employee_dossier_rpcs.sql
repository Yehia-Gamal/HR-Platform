-- =====================================================================
-- 0412: دوال ملف الموظف الشامل (Dossier) — migration 0412
--   1. الدوال الأربع موجودة بالتواقيع الصحيحة (uuid, integer).
--   2. الأذونات: anon لا EXECUTE، authenticated لديها EXECUTE.
--   3. الحارس: الموظف العادي يُرفض 42501 على كل الدوال.
--   4. الصلاحية الكاملة تقرأ بيانات موظف واحد عبر كل دوال الملف:
--      طلبات المواقع + المهام + تقييمات KPI + القرارات المنشورة
--      مع حل الأسماء (requestedByName / createdByName) وعلامات الإقرار.
--   5. حدّ p_limit يعمل (tasks بـ p_limit=1 يعيد عنصراً واحداً).
-- 23 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(23);

-- تعطيل trigger الإشعارات لتجنب أخطاء الـ fixture
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

-- =====================================================================
-- 1) الدوال موجودة
-- =====================================================================
select has_function(
  'public', 'get_employee_location_requests', array['uuid', 'integer'],
  '0412: get_employee_location_requests(uuid, integer) موجودة'
);

select has_function(
  'public', 'get_employee_tasks_admin', array['uuid', 'integer'],
  '0412: get_employee_tasks_admin(uuid, integer) موجودة'
);

select has_function(
  'public', 'get_employee_kpi_evaluations_admin', array['uuid', 'integer'],
  '0412: get_employee_kpi_evaluations_admin(uuid, integer) موجودة'
);

select has_function(
  'public', 'get_employee_published_decisions_admin', array['uuid', 'integer'],
  '0412: get_employee_published_decisions_admin(uuid, integer) موجودة'
);

-- =====================================================================
-- 2) الأذونات
-- =====================================================================
select ok(
  NOT has_function_privilege('anon', 'public.get_employee_location_requests(uuid, integer)', 'EXECUTE'),
  '0412: anon لا تملك EXECUTE على get_employee_location_requests'
);

select ok(
  has_function_privilege('authenticated', 'public.get_employee_location_requests(uuid, integer)', 'EXECUTE'),
  '0412: authenticated لديها EXECUTE على get_employee_location_requests'
);

select ok(
  NOT has_function_privilege('anon', 'public.get_employee_published_decisions_admin(uuid, integer)', 'EXECUTE'),
  '0412: anon لا تملك EXECUTE على get_employee_published_decisions_admin'
);

select ok(
  has_function_privilege('authenticated', 'public.get_employee_published_decisions_admin(uuid, integer)', 'EXECUTE'),
  '0412: authenticated لديها EXECUTE على get_employee_published_decisions_admin'
);

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
declare
  v_le         uuid := 'c4a40000-0000-4000-8000-000000000000';
  v_dept       uuid := 'c4a40000-0000-4000-8000-000000000010';
  v_user_admin uuid := 'c4a40000-0000-4000-8000-000000000001';
  v_user_emp   uuid := 'c4a40000-0000-4000-8000-000000000002';
  v_user_norm  uuid := 'c4a40000-0000-4000-8000-000000000003';
  v_emp_admin  uuid := 'c4a40000-0000-4000-8000-000000000011';
  v_emp_target uuid := 'c4a40000-0000-4000-8000-000000000012';
  v_emp_norm   uuid := 'c4a40000-0000-4000-8000-000000000013';
  v_role_admin uuid;
  v_role_emp   uuid;
  v_cycle      uuid := 'c4a40000-0000-4000-8000-000000000301';
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'C4A4-LE', 'كيان اختبار الملف الشامل 0412');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'C4A4-D1', 'إدارة اختبار 0412');

  insert into auth.users (id, email, aud, role) values
    (v_user_admin, 'c4a4-admin@test.local', 'authenticated', 'authenticated'),
    (v_user_emp,   'c4a4-emp@test.local',   'authenticated', 'authenticated'),
    (v_user_norm,  'c4a4-norm@test.local',  'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    (v_emp_admin,  v_user_admin, 'C4A4-ADM', 'مسؤول الاختبار', v_dept, 'active', true, false),
    (v_emp_target, v_user_emp,   'C4A4-TGT', 'موظف الهدف',     v_dept, 'active', true, false),
    (v_emp_norm,   v_user_norm,  'C4A4-NRM', 'موظف عادي',      v_dept, 'active', true, false);

  insert into public.profiles (id, employee_id, status) values
    (v_user_admin, v_emp_admin,  'active'),
    (v_user_emp,   v_emp_target, 'active'),
    (v_user_norm,  v_emp_norm,   'active');

  select id into v_role_admin from public.roles where is_full_access = true order by slug limit 1;
  select id into v_role_emp from public.roles where slug = 'employee';

  insert into public.user_roles (user_id, role_id) values
    (v_user_admin, v_role_admin),
    (v_user_emp,   v_role_emp),
    (v_user_norm,  v_role_emp);

  -- طلبا موقع للموظف الهدف (من المسؤول)
  insert into public.live_location_requests
    (id, employee_id, requested_by, reason, status, purpose, responded_at, starts_at, expires_at, duration_minutes)
  values
    ('c4a40000-0000-4000-8000-000000000101', v_emp_target, v_emp_admin, 'تحقق أمني',
     'completed', 'verification', '2026-08-10 11:00+03', '2026-08-10 10:00+03', '2026-08-10 10:30+03', 30),
    ('c4a40000-0000-4000-8000-000000000102', v_emp_target, v_emp_admin, 'متابعة ميدانية',
     'active', 'safety', null, '2026-08-12 09:00+03', '2026-08-12 10:00+03', 60);

  -- مهمتان مسندتان للموظف الهدف (من المسؤول)
  insert into public.tasks (id, title, description, assignee_employee_id, priority, status, created_by_employee_id)
  values
    ('c4a40000-0000-4000-8000-000000000201', 'تجهيز التقرير الشهري', 'تجميع البيانات', v_emp_target, 'high', 'in_progress', v_emp_admin),
    ('c4a40000-0000-4000-8000-000000000202', 'مراجعة كشف المصروفات', 'تدقيق الإيصالات', v_emp_target, 'medium', 'pending', v_emp_admin);

  -- دورة KPI وتقييم واحد مختوم للموظف الهدف
  insert into public.kpi_cycles (id, period_month, status)
  values (v_cycle, '2026-07-01', 'open');

  insert into public.kpi_evaluations
    (id, employee_id, cycle_id, stage, current_stage, workflow_status, final_score, final_rating, manager_comment, hr_comment, locked)
  values
    ('c4a40000-0000-4000-8000-000000000302', v_emp_target, v_cycle,
     'finalized', 'finalized', 'APPROVED', 87.5, 'ممتاز', 'أداء متميز', 'معتمد', true);

  -- قراران منشوران: عام للجميع + مخصص للموظف عبر قائمة المستلمين
  insert into public.administrative_decisions
    (id, decision_number, title, category, status, target_type, effective_date, expiry_date, published_at)
  values
    ('c4a40000-0000-4000-8000-000000000401', 'D-0412-1', 'قرار عام لائحة الانضباط', 'policy', 'published', 'all',
     '2026-08-01', '2026-12-31', '2026-08-01 10:00+03'),
    ('c4a40000-0000-4000-8000-000000000402', 'D-0412-2', 'قرار مخصص لموظف', 'hr', 'published', 'employee',
     '2026-08-05', null, '2026-08-05 10:00+03');

  insert into public.decision_recipients (decision_id, employee_id)
  values ('c4a40000-0000-4000-8000-000000000402', v_emp_target);

  -- قرأ الموظف الهدف القرار العام وأقرّ به (القرار المخصص لم يُقرأ بعد)
  insert into public.decision_reads (decision_id, employee_id, acknowledged, acknowledged_at)
  values ('c4a40000-0000-4000-8000-000000000401', v_emp_target, true, '2026-08-02 09:00+03');
end
$fixture$;

-- =====================================================================
-- 3) الحارس: الموظف العادي يُرفض 42501
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"c4a40000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'c4a40000-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_employee_location_requests('c4a40000-0000-4000-8000-000000000012', 10)$$,
  '42501', null,
  '0412: الموظف العادي لا يقرأ طلبات المواقع (لا people.employee.read ولا مديرية)'
);

select throws_ok(
  $$select public.get_employee_tasks_admin('c4a40000-0000-4000-8000-000000000012', 10)$$,
  '42501', null,
  '0412: الموظف العادي لا يقرأ مهام موظف آخر'
);

select throws_ok(
  $$select public.get_employee_kpi_evaluations_admin('c4a40000-0000-4000-8000-000000000012', 10)$$,
  '42501', null,
  '0412: الموظف العادي لا يقرأ تقييمات KPI'
);

select throws_ok(
  $$select public.get_employee_published_decisions_admin('c4a40000-0000-4000-8000-000000000012', 10)$$,
  '42501', null,
  '0412: الموظف العادي لا يقرأ قرارات موظف آخر'
);

-- =====================================================================
-- 4) الصلاحية الكاملة تقرأ بيانات الملف
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"c4a40000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'c4a40000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select is(
  (select jsonb_array_length(
     public.get_employee_location_requests('c4a40000-0000-4000-8000-000000000012', 100))),
  2,
  '0412: طلبات المواقع = 2'
);

select is(
  (select public.get_employee_location_requests('c4a40000-0000-4000-8000-000000000012', 100)
          @> '[{"id":"c4a40000-0000-4000-8000-000000000101","status":"completed","purpose":"verification","durationMinutes":30,"requestedByName":"مسؤول الاختبار"}]'::jsonb),
  true,
  '0412: طلب الموقع يحل اسم الطالب من جدول employees'
);

select is(
  (select jsonb_array_length(
     public.get_employee_tasks_admin('c4a40000-0000-4000-8000-000000000012', 100))),
  2,
  '0412: المهام = 2'
);

select is(
  (select public.get_employee_tasks_admin('c4a40000-0000-4000-8000-000000000012', 100)
          @> '[{"id":"c4a40000-0000-4000-8000-000000000201","title":"تجهيز التقرير الشهري","priority":"high","status":"in_progress","createdByName":"مسؤول الاختبار"}]'::jsonb),
  true,
  '0412: المهمة تحل اسم المُنشئ من جدول employees'
);

select is(
  (select jsonb_array_length(
     public.get_employee_kpi_evaluations_admin('c4a40000-0000-4000-8000-000000000012', 10))),
  1,
  '0412: تقييمات KPI = 1'
);

select is(
  (select public.get_employee_kpi_evaluations_admin('c4a40000-0000-4000-8000-000000000012', 10)
          @> '[{"id":"c4a40000-0000-4000-8000-000000000302","periodMonth":"2026-07-01","currentStage":"finalized","workflowStatus":"APPROVED","cycleStatus":"open","finalRating":"ممتاز","locked":true}]'::jsonb),
  true,
  '0412: تقييم KPI يعرض الدورة والمرحلة والرتبة النهائية'
);

select is(
  (select (public.get_employee_kpi_evaluations_admin('c4a40000-0000-4000-8000-000000000012', 10)
           #> '{0,finalScore}')::text),
  '87.50',
  '0412: finalScore يُسلسل بشكل صحيح'
);

select is(
  (select jsonb_array_length(
     public.get_employee_published_decisions_admin('c4a40000-0000-4000-8000-000000000012', 100))),
  2,
  '0412: القرارات = 2 (قرار عام + قرار مخصص عبر المستلمين)'
);

select is(
  (select public.get_employee_published_decisions_admin('c4a40000-0000-4000-8000-000000000012', 100)
          @> '[{"id":"c4a40000-0000-4000-8000-000000000401","decisionNumber":"D-0412-1","category":"policy","isRead":true,"acknowledged":true}]'::jsonb),
  true,
  '0412: القرار المقروء يعرض isRead=true و acknowledged=true'
);

select is(
  (select public.get_employee_published_decisions_admin('c4a40000-0000-4000-8000-000000000012', 100)
          @> '[{"id":"c4a40000-0000-4000-8000-000000000402","decisionNumber":"D-0412-2","category":"hr","isRead":false,"acknowledged":false}]'::jsonb),
  true,
  '0412: القرار غير المقروء يعرض isRead=false و acknowledged=false'
);

select is(
  (select jsonb_array_length(
     public.get_employee_tasks_admin('c4a40000-0000-4000-8000-000000000012', 1))),
  1,
  '0412: p_limit=1 يقصّ النتائج إلى عنصر واحد'
);

reset role;
select * from finish();
rollback;
