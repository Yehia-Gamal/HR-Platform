-- =====================================================================
-- 0704: اختبار دورة حياة المأمورية الكاملة مع التقرير الاختياري والانصراف المباشر
-- ---------------------------------------------------------------------
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- Fixture
do $fixture$
declare
  v_le   uuid := 'b7040000-0000-4000-8000-000000000001';
  v_dept uuid := 'b7040000-0000-4000-8000-000000000002';
  v_user uuid := 'b7040000-0000-4000-8000-000000000003';
  v_emp  uuid := 'b7040000-0000-4000-8000-000000000004';
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'M704-LE', 'كيان اختبار المأمورية');
  insert into public.departments(id, legal_entity_id, code, name) values(v_dept, v_le, 'M704-D', 'إدارة الاختبار');

  insert into auth.users(id, email, aud, role) values(v_user, 'm704-emp@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, birth_date, hire_date)
  values(v_emp, v_user, 'M704-EMP', 'موظف تجربة المأمورية', v_dept, 'active', true, '1990-01-01', '2020-01-01');

  insert into public.profiles(id, employee_id, status) values(v_user, v_emp, 'active');

  insert into public.user_roles(user_id, role_id)
  select v_user, r.id from public.roles r where r.slug = 'employee';

  create temp table pg_temp.m704_state(req_id uuid, rtype text) on commit drop;
end $fixture$;

-- ضبط سياق الجلسة للموظف
do $set_ctx$
begin
  perform set_config('request.jwt.claims', '{"sub":"b7040000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'b7040000-0000-4000-8000-000000000003', true);
end $set_ctx$;

-- 1) تسجيل مأمورية لليوم الحالي
select lives_ok($$
  insert into pg_temp.m704_state(req_id, rtype)
  select (public.submit_my_request(
    'mission',
    'مأمورية عمل خارجية ميدانية',
    'متابعة أعمال الفرع الخارجي',
    jsonb_build_object(
      'startDate', to_char((now() at time zone 'Africa/Cairo')::date, 'YYYY-MM-DD'),
      'endDate',   to_char((now() at time zone 'Africa/Cairo')::date, 'YYYY-MM-DD'),
      'location',  'فرع المحافظة',
      'startTime', '09:00'
    )
  )).id, 'mission_1'
$$, 'تسجيل طلب مأمورية لليوم ينجح فوراً');

-- 2) التأكد من بدء تنفيذ المأمورية تلقائياً (in_progress)
select is(
  (select me.status from public.mission_executions me
   join pg_temp.m704_state s on s.req_id = me.request_id where s.rtype = 'mission_1'),
  'in_progress',
  'المأمورية تبدأ مباشرة بحالة in_progress فور تسجيلها'
);

-- 3) فحص حالة الحضور المقترحة get_my_attendance_state أثناء المأمورية
select is(
  (select public.get_my_attendance_state()->>'suggestedAction'),
  'MISSION_IN_PROGRESS',
  'الإجراء المقترح أثناء سريان المأمورية هو MISSION_IN_PROGRESS وليس CHECK_OUT'
);

select is(
  (select public.get_my_attendance_state()->'missionToday'->>'execStatus'),
  'in_progress',
  'حالة مأمورية اليوم هي in_progress'
);

-- 4) إنهاء المأمورية بتقرير فارغ تماماً وخيار العودة للمقر (withCheckout = false)
select lives_ok($$
  select public.end_my_mission(
    (select req_id from pg_temp.m704_state where rtype = 'mission_1'),
    '', -- تقرير فارغ لا يُلزم بأي أحرف
    null,
    false -- عودة للدوام بالجمعية
  )
$$, 'إنهاء المأمورية بتقرير فارغ تماماً وخيار العودة ينجح بلا استثناء');

-- 5) التحقق من حفظ التقرير الافتراضي واكتمال التنفيذ
select is(
  (select me.status from public.mission_executions me
   join pg_temp.m704_state s on s.req_id = me.request_id where s.rtype = 'mission_1'),
  'completed',
  'حالة تنفيذ المأمورية تصبح completed بعد الإنهاء'
);

select is(
  (select me.report from public.mission_executions me
   join pg_temp.m704_state s on s.req_id = me.request_id where s.rtype = 'mission_1'),
  'تم إنجاز المأمورية بنجاح',
  'يتم اعتماد نص افتراضي للتقرير عند تركه فارغاً'
);

-- 6) التحقق من أن حالة الحضور أصبحت تقترح بصمة الانصراف العادية CHECK_OUT
select is(
  (select public.get_my_attendance_state()->>'suggestedAction'),
  'CHECK_OUT',
  'بعد إنهاء المأمورية والعودة، يتحول الإجراء المقترح تلقائياً إلى CHECK_OUT لاستكمال الدوام وبصم الانصراف'
);

select ok(
  (select (public.get_my_attendance_state()->>'todayCheckOutAt') is null),
  'لم يُسجل انصراف بعد ودوام الموظف مستمر في المقر'
);

-- 7) تجربة السيناريو الثاني: مأمورية أخرى تنتهي مع الانصراف الميداني المباشر (withCheckout = true)
select lives_ok($$
  insert into pg_temp.m704_state(req_id, rtype)
  select (public.submit_my_request(
    'mission',
    'مأمورية ثانية مسائية',
    'تسليم تقارير رسمية',
    jsonb_build_object(
      'startDate', to_char((now() at time zone 'Africa/Cairo')::date, 'YYYY-MM-DD'),
      'endDate',   to_char((now() at time zone 'Africa/Cairo')::date, 'YYYY-MM-DD'),
      'location',  'وزارة التضامن',
      'startTime', '14:00'
    )
  )).id, 'mission_2'
$$, 'تسجيل مأمورية ثانية ينجح');

select lives_ok($$
  select public.end_my_mission(
    (select req_id from pg_temp.m704_state where rtype = 'mission_2'),
    null, -- تقرير فارغ null
    'تم التسليم بنجاح',
    true, -- إنهاء مع الانصراف الميداني المباشر
    30.0444, 31.2357, 15.0, false
  )
$$, 'إنهاء المأمورية الثانية مع الانصراف الميداني ينجح');

-- 8) التحقق من اكتمال اليوم وتوثيق حدث CHECK_OUT
select is(
  (select public.get_my_attendance_state()->>'suggestedAction'),
  'DAY_COMPLETED',
  'بعد الإنهاء مع الانصراف الميداني، يتحول اليوم تلقائياً إلى DAY_COMPLETED'
);

select finish();
rollback;
