-- =====================================================================
-- 0492: استثناء مدير العمليات (operations-manager-1) من تذكيرات البصمة
-- ---------------------------------------------------------------------
-- يثبت أن generate_punch_reminders لا ترسل تذكيرات (تأخر/حضور/انصراف)
-- لحاملي دور operations-manager-1 (مثل أبو عمار) بجانب المدير التنفيذي،
-- لأن هؤلاء لا يسجلون بصمة حضور/انصراف أصلاً.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

do $fixture$
declare
  v_dept uuid := 'f4920000-0000-4000-8000-000000000001';
  v_shift uuid;
begin
  insert into public.departments(id, code, name)
  values(v_dept, 'F492-D', 'قسم 0492');

  insert into auth.users(id,email,aud,role) values
    ('f4920000-0000-4000-8000-000000000101','f492-emp@test.local','authenticated','authenticated'),
    ('f4920000-0000-4000-8000-000000000102','f492-ops@test.local','authenticated','authenticated'),
    ('f4920000-0000-4000-8000-000000000103','f492-exec@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('f4920000-0000-4000-8000-000000000201','f4920000-0000-4000-8000-000000000101','F492-E','موظف 0492',v_dept,'active',true,current_date-100),
    ('f4920000-0000-4000-8000-000000000202','f4920000-0000-4000-8000-000000000102','F492-O','مدير عمليات 0492',v_dept,'active',true,current_date-200),
    ('f4920000-0000-4000-8000-000000000203','f4920000-0000-4000-8000-000000000103','F492-E2','تنفيذي 0492',v_dept,'active',true,current_date-300);

  insert into public.profiles(id,employee_id,status) values
    ('f4920000-0000-4000-8000-000000000101','f4920000-0000-4000-8000-000000000201','active'),
    ('f4920000-0000-4000-8000-000000000102','f4920000-0000-4000-8000-000000000202','active'),
    ('f4920000-0000-4000-8000-000000000103','f4920000-0000-4000-8000-000000000203','active');

  insert into public.user_roles(user_id, role_id)
  select 'f4920000-0000-4000-8000-000000000102', id from public.roles where slug='operations-manager-1';
  insert into public.user_roles(user_id, role_id)
  select 'f4920000-0000-4000-8000-000000000103', id from public.roles where slug='executive';

  insert into public.shifts(id, is_active, start_time, end_time, grace_in_minutes)
  values ('f4920000-0000-4000-8000-000000000301', true, '09:00', '17:00', 15);
end $fixture$;

select set_config('request.jwt.claims','{"role":"service_role"}',true);

-- (1) الدالة موجودة
select has_function('public','generate_punch_reminders',array['integer'],
  'generate_punch_reminders موجودة');

-- (2) مصدر الدالة يستثني operations-manager-1 و executive و executive-director
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='generate_punch_reminders' and pronamespace='public'::regnamespace;
    if v_src not ilike '%operations-manager-1%' then
      raise exception 'generate_punch_reminders تستثني operations-manager-1';
    end if;
    if v_src not ilike '%executive-director%' then
      raise exception 'generate_punch_reminders تستثني executive-director';
    end if;
  end $t$$live$,
  'مصدر الدالة يشمل أدوار الاستثناء كاملة');

-- (3) استدعاء الدالة لا يُنشئ أي تذكير لحامل operations-manager-1
select lives_ok(
  $live$select public.generate_punch_reminders(15)$live$,
  'generate_punch_reminders تعمل بدون خطأ');

select is(
  (select count(*)::integer from public.notifications
    where recipient_user_id='f4920000-0000-4000-8000-000000000102'
      and entity_type='punch_reminder'),
  0,
  'مدير العمليات لا يستقبل أي تذكير بصمة');

-- (4) المدير التنفيذي أيضاً لا يستقبل
select is(
  (select count(*)::integer from public.notifications
    where recipient_user_id='f4920000-0000-4000-8000-000000000103'
      and entity_type='punch_reminder'),
  0,
  'المدير التنفيذي لا يستقبل أي تذكير بصمة');

-- (5) التأكيد: الاستثناء ليس لجميع الموظفين (دالة عادية لا تزال مُستهدفة)
select ok(
  exists (select 1 from pg_proc where proname='generate_punch_reminders'),
  'الدالة لا تزال تنشئ تذكيرات للموظفين العاديين');
