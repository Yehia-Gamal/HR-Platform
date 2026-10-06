-- =====================================================================
-- 0648: التصعيد التلقائي من الكرون — السياسة الحالية من البداية للنهاية
-- ---------------------------------------------------------------------
-- السياسة (قرار المالك): 0567 — المضاعفة ثم الإيقاف تلقائياً؛
-- 0616 — الحساب الرئيسي يخضع للغرامة لكنه محمي من الإيقاف؛
-- 0648 — تلك الحماية بالمعرّف لا بالاسم.
--
-- ⚠ سياق الكرون الحقيقي = request.jwt.claims **لم تُضبط قط** في الجلسة (NULL).
-- ضبطها إلى '' ليس مكافئاً: حارس employees يتخطى عند IS NULL فقط. لذلك
-- لا يستدعي هذا الملف set_config إطلاقاً (يحلّ محل اختبار 0550 الذي حاكى
-- الكرون بـ '' ورسّخ سياسة «الإيقاف اليدوي» التي أبطلتها 0567).
--
-- يثبت:
--   1) الدورة تكتمل دون خطأ (مضاعفة + إيقاف في تشغيل واحد)
--   2) موظف عادي: الغرامة suspended/500، والموظف والملف موقوفان
--   3) موظف اسمه «يحيى … جمال» وليس الحساب الرئيسي: يُوقف كأي موظف (0648)
--   4) الحساب الرئيسي (بالمعرّف): الغرامة مستحقة 500، والحساب لا يُوقف (0616)
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(9);

do $fixture$
declare
  v_le     uuid := 'f6480000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f6480000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f6480000-0000-4000-8000-000000000003';
  v_x      uuid := 'f6480000-0000-4000-8000-000000000011';
  v_y      uuid := 'f6480000-0000-4000-8000-000000000012';
  v_acc    uuid := 'b452c987-ae08-4e12-8433-272cc66c85f9';
  v_user_x uuid := 'f6480000-0000-4000-8000-000000000021';
  v_user_y uuid := 'f6480000-0000-4000-8000-000000000022';
  v_date   date := current_date - 7;
begin
  -- يوم عمل مضمون: الجمعة والعطلات معفاة فتُلغى الغرامة بدل تصعيدها
  while extract(isodow from v_date)::integer = 5
     or exists (select 1 from public.public_holidays where holiday_date = v_date) loop
    v_date := v_date - 1;
  end loop;

  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0648', 'كيان 0648');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0648', 'إدارة 0648');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0648', 'وظيفة 0648');

  insert into auth.users(id, email, aud, role) values
    (v_user_x, 'x-0648@test.local', 'authenticated', 'authenticated'),
    (v_user_y, 'y-0648@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values
    (v_x,   v_user_x, 'E-0648-X',   'موظف عادي 0648',      v_dept, v_jt, 'active', true, current_date - 300, '+201000006480'),
    (v_y,   v_user_y, 'E-0648-Y',   'يحيى أحمد جمال 0648', v_dept, v_jt, 'active', true, current_date - 300, '+201000006481'),
    (v_acc, null,     'E-0648-ACC', 'الحساب الرئيسي 0648', v_dept, v_jt, 'active', true, current_date - 900, '+201000006482');

  insert into public.profiles(id, employee_id, status) values
    (v_user_x, v_x, 'active'),
    (v_user_y, v_y, 'active');

  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes, original_amount, current_amount, status, escalation_level)
  values
    (v_x,   v_date, 20, 20.00, 20.00, 'pending_payment', 'initial'),
    (v_y,   v_date, 20, 20.00, 20.00, 'pending_payment', 'initial'),
    (v_acc, v_date, 20, 20.00, 20.00, 'pending_payment', 'initial');
end $fixture$;

-- =====================================================================
-- 0) سياق الكرون الحقيقي
-- =====================================================================
select ok(current_setting('request.jwt.claims', true) is null,
  'سياق الكرون: request.jwt.claims غير مضبوطة (NULL) كما في pg_cron');

-- =====================================================================
-- 1) الدورة تكتمل
-- =====================================================================
select lives_ok($rt$ select public.auto_escalate_instant_penalties() $rt$,
  'التصعيد من الكرون يكتمل دون خطأ');

-- =====================================================================
-- 2) موظف عادي: مضاعفة ثم إيقاف في تشغيل واحد
-- =====================================================================
select is(
  (select status || '/' || current_amount::text from public.instant_attendance_penalties
    where employee_id = 'f6480000-0000-4000-8000-000000000011'),
  'suspended/500.00',
  'موظف عادي: الغرامة suspended بقيمة 500');

select is((select status from public.employees where id = 'f6480000-0000-4000-8000-000000000011'),
  'suspended', 'موظف عادي: الموظف موقوف');

select is((select status from public.profiles where employee_id = 'f6480000-0000-4000-8000-000000000011'),
  'suspended', 'موظف عادي: الملف موقوف');

-- =====================================================================
-- 3) اسم يشبه اسم الحساب الرئيسي لا يمنح الحماية (0648)
-- =====================================================================
select is((select status from public.employees where id = 'f6480000-0000-4000-8000-000000000012'),
  'suspended',
  '0648: موظف اسمه «يحيى … جمال» ليس الحساب الرئيسي — يُوقف كأي موظف');

-- =====================================================================
-- 4) الحساب الرئيسي (بالمعرّف): الغرامة مستحقة، والحساب محمي (0616)
-- =====================================================================
select is((select status from public.employees where id = 'b452c987-ae08-4e12-8433-272cc66c85f9'),
  'active',
  '0616: الحساب الرئيسي لا يُوقف');

select is(
  (select escalation_level || '/' || current_amount::text from public.instant_attendance_penalties
    where employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'),
  'doubled/500.00',
  '0616: غرامة الحساب الرئيسي تبقى مستحقة ومضاعفة');

select isnt(
  (select status from public.instant_attendance_penalties
    where employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'),
  'suspended',
  '0616: غرامة الحساب الرئيسي لا تُوسم suspended');

select * from finish();
rollback;
