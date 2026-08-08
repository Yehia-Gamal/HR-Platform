-- 0113: F6 — مشاركة موقع استباقية للمدير التنفيذي (0319)
--        F7 — إشعار المدير المباشر بدخول/انصراف موظفيه (0319)
-- يغطي:
--   * تسجيل live_location_requests.active + نقطة employee_locations.
--   * إشعار location/urgent للمدير التنفيذي.
--   * منع تكرار المشاركة النشطة (23505).
--   * تريجر إشعار المدير عند first_check_in ثم عند last_check_out.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(9);

do $fixture$
declare
  v_le    uuid := 'd1900000-0000-4000-8000-000000000001';
  v_dept  uuid := 'd1900000-0000-4000-8000-000000000002';
  v_shift uuid := 'd1900000-0000-4000-8000-000000000003';
  v_emp   uuid := 'd1800000-0000-4000-8000-000000000001'; -- يشارك موقعه
  v_mgr   uuid := 'd1800000-0000-4000-8000-000000000002'; -- مديره المباشر (F7)
  v_exec  uuid := 'd1800000-0000-4000-8000-000000000003'; -- المدير التنفيذي (F6)
  v_user_e uuid := 'd1700000-0000-4000-8000-000000000001';
  v_user_m uuid := 'd1700000-0000-4000-8000-000000000002';
  v_user_x uuid := 'd1700000-0000-4000-8000-000000000003';
  v_exec_role uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0113', 'كيان 0113');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0113', 'إدارة 0113');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0113', 'وردية 0113', '09:00', '17:00', false, 0, 0, 0, true);

  insert into auth.users(id, email, aud, role)
    values
    (v_user_e, 'emp-0113@test.local', 'authenticated', 'authenticated'),
    (v_user_m, 'mgr-0113@test.local', 'authenticated', 'authenticated'),
    (v_user_x, 'exec-0113@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, hire_date)
    values
    (v_emp,  v_user_e, 'E-0113-A', 'موظف يشارك', v_dept, 'active', true, current_date - 300),
    (v_mgr,  v_user_m, 'E-0113-B', 'مدير مباشر', v_dept, 'active', true, current_date - 800),
    (v_exec, v_user_x, 'E-0113-C', 'المدير التنفيذي', v_dept, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_e, v_emp,  'active'),
    (v_user_m, v_mgr,  'active'),
    (v_user_x, v_exec, 'active');

  -- علاقة إدارية (F7): المدير المباشر
  insert into public.manager_relations(manager_employee_id, employee_id, relation_type)
    values (v_mgr, v_emp, 'primary');

  -- دور المدير التنفيذي (F6): get_system_setting_text الافتراضي = 'executive-director'
  insert into public.roles(slug, name_ar, is_system, is_full_access, is_capability)
  values ('executive-director', 'المدير التنفيذي', true, false, false)
  on conflict (slug) do nothing
  returning id into v_exec_role;
  select id into v_exec_role from public.roles where slug = 'executive-director';

  insert into public.user_roles(user_id, role_id)
    values (v_user_x, v_exec_role)
    on conflict (user_id, role_id) do nothing;

  -- موظف غائب اليوم (F7 سيكتب الدخول)
  insert into public.attendance_daily(employee_id, work_date, shift_id, status)
    values (v_emp, (now() at time zone 'Africa/Cairo')::date, v_shift, 'absent');
end $fixture$;

-- =====================================================================
-- جلسة الموظف: مشاركة موقع استباقية
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1700000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1700000-0000-4000-8000-000000000001',
  true);

select lives_ok(
  $q$ select public.share_my_location_proactively(
    31.22, 29.91, 12.5, 90, 'رحلة ميدانية', 'mobile', 87) $q$,
  'المشاركة الاستباقية تُنفذ بنجاح');

select is(
  (select status from public.live_location_requests
    where employee_id = 'd1800000-0000-4000-8000-000000000001'),
  'active',
  'سُجّل طلب موقع نشط للموظف');

select is(
  (select requested_by from public.live_location_requests
    where employee_id = 'd1800000-0000-4000-8000-000000000001'),
  'd1800000-0000-4000-8000-000000000003',
  'المستفيد هو المدير التنفيذي');

select ok(
  exists (
    select 1 from public.employee_locations
    where employee_id = 'd1800000-0000-4000-8000-000000000001'
      and source = 'mobile'
      and latitude = 31.22 and longitude = 29.91),
  'نقطة الموقع الفورية سُجلت في employee_locations');

-- منع التكرار: مشاركة ثانية والموظف لديه مشاركة نشطة
select throws_ok(
  $q$ select public.share_my_location_proactively(
    31.25, 29.95, null, 60, 'تكرار', 'mobile', null) $q$,
  '23505',
  null,
  'لا يُسمح بمشاركة ثانية مع وجود مشاركة نشطة');

reset role;

-- =====================================================================
-- F7: تسجيل دخول/خروج يُشعر المدير المباشر.
-- يُنفَّذ بصفة postgres (الكتابة على attendance_daily محصورة بصلاحية
-- معالجة الحضور — RLS تمنع الموظف؛ التريجر يشتغل تلقائياً بعد التحديث).
-- الدخول والخروج حدثان منفصلان زمنياً — تحديثان منفصلان.
update public.attendance_daily
  set first_check_in = now() - interval '30 minutes',
      status = 'present',
      updated_at = now()
  where employee_id = 'd1800000-0000-4000-8000-000000000001'
    and work_date = (now() at time zone 'Africa/Cairo')::date;

select is(
  (select count(*)::text from public.notifications
    where recipient_employee_id = 'd1800000-0000-4000-8000-000000000002'
      and category = 'attendance'
      and metadata->>'event' = 'attendance_check_in'),
  '1',
  'المدير المباشر استُشعر بدخول الموظف (attendance_check_in)');

update public.attendance_daily
  set last_check_out = now() + interval '8 hours',
      updated_at = now()
  where employee_id = 'd1800000-0000-4000-8000-000000000001'
    and work_date = (now() at time zone 'Africa/Cairo')::date;

select is(
  (select count(*)::text from public.notifications
    where recipient_employee_id = 'd1800000-0000-4000-8000-000000000002'
      and category = 'attendance'
      and metadata->>'event' = 'attendance_check_out'),
  '1',
  'المدير المباشر استُشعر بخروج الموظف (attendance_check_out)');

-- إشعار عاجل للمدير التنفيذي (F6) — فئة location
select is(
  (select count(*)::text from public.notifications
    where recipient_employee_id = 'd1800000-0000-4000-8000-000000000003'
      and category = 'location'
      and priority = 'urgent'),
  '1',
  'المدير التنفيذي استُشعر بإشعار location/urgent عند المشاركة');

-- بدون تغيير للدخول/الخروج لا يُنشأ إشعار جديد
update public.attendance_daily
  set status = 'present', updated_at = now()
  where employee_id = 'd1800000-0000-4000-8000-000000000001'
    and work_date = (now() at time zone 'Africa/Cairo')::date;

select is(
  (select count(*)::text from public.notifications
    where recipient_employee_id = 'd1800000-0000-4000-8000-000000000002'
      and category = 'attendance'),
  '2',
  'تحديث بلا تغيير في أوقات الدخول/الخروج لا يُنشئ إشعارات إضافية');

select * from finish();
rollback;
