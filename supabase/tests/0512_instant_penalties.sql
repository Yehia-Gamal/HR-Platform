-- =====================================================================
-- 0512: نظام الغرامات الفورية للتأخير (0511)
-- ---------------------------------------------------------------------
-- يثبت:
--   1) جدول instant_attendance_penalties مع RLS وفهارس
--   2) calc_instant_penalty_amount — كل الشرايح (سماح/20/50/150)
--   3) generate_instant_penalty — إنشاء + منع التكرار + فترة السماح
--   4) confirm_instant_penalty_payment — سداد + رفع التعليق
--   5) get_instant_penalties — استعلام مع فلاتر
--   6) get_employees_with_pending_instant_penalties — المطالبين بالدفع
--   7) lift_instant_penalty_suspension — رفع التعليق بدون دفع
--   8) الحماية: anon ممنوع، موظف عادي مرفوض
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(28);

-- =====================================================================
-- Fixture: كيان + إدارة + وظيفة + موظف مسؤول (full-access) + موظف عادي
-- =====================================================================
do $fixture$
declare
  v_le   uuid := 'f5120000-0000-4000-8000-000000000001';
  v_dept uuid := 'f5120000-0000-4000-8000-000000000002';
  v_jt   uuid := 'f5120000-0000-4000-8000-000000000003';
  v_admin uuid := 'f5120000-0000-4000-8000-000000000011';
  v_emp  uuid := 'f5120000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f5120000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f5120000-0000-4000-8000-000000000022';
  v_role uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0512', 'كيان 0512');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0512', 'إدارة 0512');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0512', 'وظيفة 0512');

  insert into auth.users(id, email, aud, role)
    values
    (v_user_a, 'admin-0512@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0512@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
    values
    (v_admin, v_user_a, 'E-0512-A', 'مسؤول 0512', v_dept, v_jt, 'active', true, current_date - 500, '+201000000512'),
    (v_emp,   v_user_e, 'E-0512-B', 'موظف 0512',  v_dept, v_jt, 'active', true, current_date - 300, '+201000000513');

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_a, v_admin, 'active'),
    (v_user_e, v_emp,   'active');

  -- دور admin بصلاحية كاملة
  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0512', 'أدمن 0512', 'Admin 0512', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0512';
  insert into public.user_roles(user_id, role_id)
    values (v_user_a, v_role)
    on conflict do nothing;

  perform set_config('app.t0512_admin', v_admin::text, false);
  perform set_config('app.t0512_emp', v_emp::text, false);
  perform set_config('app.t0512_user_a', v_user_a::text, false);
end $fixture$;

-- =====================================================================
-- 1) البنية: الجدول موجود + RLS مفعّل + الدوال موجودة
-- =====================================================================
select has_table('public', 'instant_attendance_penalties', 'جدول instant_attendance_penalties موجود');

select ok(
  (select relrowsecurity from pg_class where relname = 'instant_attendance_penalties'),
  'RLS مفعّل على instant_attendance_penalties');

select has_function('public', 'calc_instant_penalty_amount', array['integer'],
  'calc_instant_penalty_amount(integer) موجودة');
select has_function('public', 'generate_instant_penalty', array['uuid', 'date', 'integer'],
  'generate_instant_penalty(uuid, date, integer) موجودة');
select has_function('public', 'confirm_instant_penalty_payment', array['uuid', 'text'],
  'confirm_instant_penalty_payment(uuid, text) موجودة');
select has_function('public', 'get_instant_penalties', array['uuid', 'text', 'date', 'date', 'integer', 'integer'],
  'get_instant_penalties(...) موجودة');
select has_function('public', 'get_employees_with_pending_instant_penalties', array[]::text[],
  'get_employees_with_pending_instant_penalties() موجودة');
select has_function('public', 'lift_instant_penalty_suspension', array['uuid', 'text'],
  'lift_instant_penalty_suspension(uuid, text) موجودة');

-- =====================================================================
-- 2) calc_instant_penalty_amount — كل الشرايح
-- =====================================================================
select is(public.calc_instant_penalty_amount(0),   0.00::numeric, '0 دقيقة = فترة سماح (0 ج.م)');
select is(public.calc_instant_penalty_amount(10),  0.00::numeric, '10 دقائق = فترة سماح (0 ج.م)');
select is(public.calc_instant_penalty_amount(15),  0.00::numeric, '15 دقيقة = آخر لحظة سماح (0 ج.م)');
select is(public.calc_instant_penalty_amount(16), 20.00::numeric, '16 دقيقة = 20 ج.م');
select is(public.calc_instant_penalty_amount(30), 20.00::numeric, '30 دقيقة = 20 ج.م');
select is(public.calc_instant_penalty_amount(31), 50.00::numeric, '31 دقيقة = 50 ج.م');
select is(public.calc_instant_penalty_amount(60), 50.00::numeric, '60 دقيقة = 50 ج.م');
select is(public.calc_instant_penalty_amount(61), 150.00::numeric, '61 دقيقة = 150 ج.م');
select is(public.calc_instant_penalty_amount(120), 150.00::numeric, '120 دقيقة = 150 ج.م');
select is(public.calc_instant_penalty_amount(180), 150.00::numeric, '180 دقيقة = 150 ج.م (الحد الأقصى)');

-- =====================================================================
-- 3) الحماية: anon ممنوع
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon', 'public.calc_instant_penalty_amount(integer)', 'EXECUTE'),
  false, 'anon لا ينفّذ calc_instant_penalty_amount');
select is(pg_catalog.has_function_privilege('anon', 'public.generate_instant_penalty(uuid, date, integer)', 'EXECUTE'),
  false, 'anon لا ينفّذ generate_instant_penalty');
select is(pg_catalog.has_function_privilege('anon', 'public.get_instant_penalties(uuid, text, date, date, integer, integer)', 'EXECUTE'),
  false, 'anon لا ينفّذ get_instant_penalties');

-- =====================================================================
-- 4) جلسة المسؤول (full-access) — إنشاء غرامة
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f5120000-0000-4000-8000-000000000021","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'f5120000-0000-4000-8000-000000000021',
  true);

-- إنشاء غرامة لتأخير 25 دقيقة (20 ج.م)
select lives_ok(
  format($q$ select public.generate_instant_penalty(
    %L::uuid, current_date, 25) $q$,
    current_setting('app.t0512_emp', true)::uuid),
  'إنشاء غرامة فورية لتأخير 25 دقيقة يُنفذ بنجاح');

-- التحقق من وجود الغرامة
select is(
  (select count(*)::int from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  1,
  'تم إنشاء غرامة واحدة للموظف');

-- التحقق من المبلغ
select is(
  (select current_amount::numeric from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  20.00::numeric,
  'المبلغ الحالي = 20 ج.م');

-- التحقق من الحالة الأولية
select is(
  (select status from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  'pending_payment',
  'الحالة = pending_payment');

-- =====================================================================
-- 5) منع التكرار: إنشاء غرامة لنفس الموظف/التاريخ
-- =====================================================================
select lives_ok(
  format($q$ select public.generate_instant_penalty(
    %L::uuid, current_date, 45) $q$,
    current_setting('app.t0512_emp', true)::uuid),
  'محاولة إنشاء غرامة مكررة (نفس التاريخ) لا تفشل');

-- لا يجب أن يزيد العدد
select is(
  (select count(*)::int from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  1,
  'لا تزال غرامة واحدة فقط (منع التكرار)');

-- =====================================================================
-- 6) فترة السماح: تأخير 10 دقائق = لا غرامة
-- =====================================================================
-- إنشاء غرامة لموظف آخر بتأخير 10 دقائق
select lives_ok(
  format($q$ select public.generate_instant_penalty(
    %L::uuid, current_date, 10) $q$,
    'f5120000-0000-4000-8000-000000000099'::uuid),
  'محاولة إنشاء غرامة لتأخير 10 دقائق (فترة سماح)');

-- لا يجب أن يُنشأ سجل لأن المبلغ = 0
select is(
  (select count(*)::int from public.instant_attendance_penalties
   where employee_id = 'f5120000-0000-4000-8000-000000000099'),
  0,
  'لا تُنشأ غرامة لتأخير 10 دقائق (فترة سماح)');

-- =====================================================================
-- 7) استعلام get_instant_penalties
-- =====================================================================
select is(
  (select jsonb_array_length(public.get_instant_penalties(null, null, null, null, null, null))),
  1,
  'get_instant_penalties يعرض غرامة واحدة');

-- فلتر الحالة
select is(
  (select jsonb_array_length(public.get_instant_penalties(null, 'pending_payment', null, null, null, null))),
  1,
  'فلتر pending_payment يعرض الغرامة');

select is(
  (select jsonb_array_length(public.get_instant_penalties(null, 'paid', null, null, null, null))),
  0,
  'فلتر paid لا يعرض شيئاً');

-- =====================================================================
-- 8) تأكيد الدفع
-- =====================================================================
select lives_ok(
  format($q$ select public.confirm_instant_penalty_payment(
    (select id from public.instant_attendance_penalties limit 1),
    'تم الدفع يدوياً') $q$),
  'تأكيد الدفع يُنفذ بنجاح');

select is(
  (select status from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  'paid',
  'الحالة تصبح paid بعد التأكيد');

select ok(
  (select paid_at is not null from public.instant_attendance_penalties
   where employee_id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  'paid_at يُملأ بعد التأكيد');

-- =====================================================================
-- 9) الموظفين المطالبين بالدفع — لا يوجد بعد الدفع
-- =====================================================================
select is(
  (select jsonb_array_length(public.get_employees_with_pending_instant_penalties())),
  0,
  'لا يوجد موظفين مطالبين بالدفع بعد السداد');

-- =====================================================================
-- 10) lift_instant_penalty_suspension — رفع التعليق بدون دفع
-- =====================================================================
-- إنشاء غرامة جديدة ثم تعليقها يدوياً
insert into public.instant_attendance_penalties(
  employee_id, work_date, late_minutes,
  original_amount, current_amount, currency,
  status, escalation_level, created_by
) values (
  nullif(current_setting('app.t0512_emp', true), '')::uuid,
  current_date - 5, 90,
  150.00, 150.00, 'EGP',
  'suspended', 'suspended', nullif(current_setting('app.t0512_user_a', true), '')::uuid
);

select lives_ok(
  format($q$ select public.lift_instant_penalty_suspension(
    (select id from public.instant_attendance_penalties
     where status = 'suspended' limit 1),
    'إعفاء إداري') $q$),
  'lift_instant_penalty_suspension يُنفذ بنجاح');

-- التحقق من إعادة تفعيل الحساب
select is(
  (select status from public.employees
   where id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  'active',
  'حالة الموظف تعود active بعد رفع التعليق');

select is(
  (select is_active from public.employees
   where id = nullif(current_setting('app.t0512_emp', true), '')::uuid),
  true,
  'is_active يعود true بعد رفع التعليق');

-- =====================================================================
-- 11) الحماية: الموظف العادي لا يستطيع الإنشاء
-- =====================================================================
reset role;

do $set_emp$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5120000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'f5120000-0000-4000-8000-000000000022', true);
end $set_emp$;

select throws_ok($$
  select public.generate_instant_penalty(
    'f5120000-0000-4000-8000-000000000012'::uuid, current_date, 25)
$$, 42501, '42501',
  'الموظف العادي لا يستطيع إنشاء غرامة فورية (42501)');

select throws_ok($$
  select public.confirm_instant_penalty_payment(
    (select id from public.instant_attendance_penalties limit 1), null)
$$, 42501, '42501',
  'الموظف العادي لا يستطيع تأكيد الدفع (42501)');

select throws_ok($$
  select public.lift_instant_penalty_suspension(
    (select id from public.instant_attendance_penalties
     where status = 'suspended' limit 1), null)
$$, 42501, '42501',
  'الموظف العادي لا يستطيع رفع التعليق (42501)');

reset role;

select * from finish();
rollback;
