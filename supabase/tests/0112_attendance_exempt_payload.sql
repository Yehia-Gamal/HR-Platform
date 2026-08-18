-- 0112: إعفاء الحضور عند اعتماد مأمورية/أذن (0317 — إعادة تعريف
-- tg_request_approved_attendance_exempt لقراءة التواريخ من payload الطلب).
-- السيناريو:
--   * طلب مأمورية payload.startDate/endDate → عند الاعتماد تُكتب
--     attendance_daily.status='present' + استثناء manual_adjustment لكل يوم.
--   * إذن تأخير payload.permitDate → present + late_minutes=0 + استثناء late.
--   * توسيع notifications.category CHECK ليشمل فئة 'attendance' (لا تفشل).
-- الميزة الأصلية كانت تقرأ جدول missions (ميت) — هنا نثبت قراءة payload.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(8);

do $fixture$
declare
  v_le    uuid := 'd1700000-0000-4000-8000-000000000001';
  v_dept  uuid := 'd1700000-0000-4000-8000-000000000002';
  v_shift uuid := 'd1700000-0000-4000-8000-000000000003';
  v_emp   uuid := 'd1600000-0000-4000-8000-000000000001';
  v_user  uuid := 'd1500000-0000-4000-8000-000000000001';
  v_mgr   uuid := 'd1600000-0000-4000-8000-000000000002';
  v_user_m uuid := 'd1500000-0000-4000-8000-000000000002';
  v_mission uuid;
  v_late    uuid;
  v_day1  date := (now() at time zone 'Africa/Cairo')::date;
  v_day2  date := (now() at time zone 'Africa/Cairo')::date + 1;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0112', 'كيان 0112');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0112', 'إدارة 0112');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0112', 'وردية 0112', '09:00', '17:00', false, 0, 0, 0, true);

  insert into auth.users(id, email, aud, role)
    values
    (v_user,   'emp-0112@test.local', 'authenticated', 'authenticated'),
    (v_user_m, 'mgr-0112@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, hire_date)
    values
    (v_emp, v_user, 'E-0112-A', 'موظف مأمورية', v_dept, 'active', true, current_date - 300),
    (v_mgr, v_user_m, 'E-0112-B', 'مدير 0112', v_dept, 'active', true, current_date - 800);

  insert into public.profiles(id, employee_id, status)
    values
    (v_user,   v_emp, 'active'),
    (v_user_m, v_mgr, 'active');

  -- الموظف غائب اليوم وغداً
  insert into public.attendance_daily(employee_id, work_date, shift_id, status)
    values
    (v_emp, v_day1, v_shift, 'absent'),
    (v_emp, v_day2, v_shift, 'absent');

  -- طلب مأمورية (غير معتمد بعد)
  insert into public.requests(request_type, employee_id, manager_employee_id,
    status, workflow_status, title, payload)
    values ('mission', v_emp, v_mgr, 'pending', 'in_review', 'مأمورية 0112',
            jsonb_build_object('startDate', to_char(v_day1,'YYYY-MM-DD'),
                               'endDate',   to_char(v_day2,'YYYY-MM-DD')))
    returning id into v_mission;

  -- إذن تأخير (غير معتمد بعد)
  insert into public.requests(request_type, employee_id, manager_employee_id,
    status, workflow_status, title, payload)
    values ('late_permit', v_emp, v_mgr, 'pending', 'in_review', 'إذن تأخير 0112',
            jsonb_build_object('permitDate', to_char(v_day1,'YYYY-MM-DD')))
    returning id into v_late;

  perform set_config('app.t0112_mission', v_mission::text, false);
  perform set_config('app.t0112_late', v_late::text, false);
end $fixture$;

-- =====================================================================
-- 1) المأمورية: اعتماد الطلب يُحفّز التريجر
-- =====================================================================
update public.requests
  set status = 'approved', updated_at = now()
  where id = nullif(current_setting('app.t0112_mission', true), '')::uuid;

select is(
  (select status from public.attendance_daily
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and work_date = ((now() at time zone 'Africa/Cairo')::date)),
  'on_leave',
  'يوم المأمورية الأول on_leave (لا غياب — 0429)');

select is(
  (select status from public.attendance_daily
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and work_date = ((now() at time zone 'Africa/Cairo')::date + 1)),
  'on_leave',
  'يوم المأمورية الثاني on_leave (لا غياب — 0429)');

select is(
  (select count(*)::text from public.attendance_exceptions
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and kind = 'manual_adjustment'
      and description like '%مأمورية%'),
  '2',
  'استثناءان manual_adjustment بأيام المأمورية');

select ok(
  exists (
    select 1 from public.audit_events
    where event_type = 'request.attendance_exempted'
      and target_table = 'attendance_daily'),
  'اعتماد المأمورية سُجّل في audit_events');

-- =====================================================================
-- 2) إذن التأخير: permitDate من payload → present و late_minutes=0
-- =====================================================================
update public.requests
  set status = 'approved', updated_at = now()
  where id = nullif(current_setting('app.t0112_late', true), '')::uuid;

select is(
  (select status from public.attendance_daily
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and work_date = ((now() at time zone 'Africa/Cairo')::date)),
  'on_leave',
  'إذن التأخير لا يغيّر الحالة (يظل on_leave — 0429)');

select is(
  (select late_minutes from public.attendance_daily
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and work_date = ((now() at time zone 'Africa/Cairo')::date)),
  0,
  'إذن التأخير المعتمد يصفّر دقائق التأخير (late_minutes=0)');

select is(
  (select count(*)::text from public.attendance_exceptions
    where employee_id = 'd1600000-0000-4000-8000-000000000001'
      and kind = 'late'),
  '1',
  'استثناء late مسجل لإذن التأخير');

-- =====================================================================
-- 3) توسيع notifications.category CHECK (0317) يسمح بفئة attendance
-- =====================================================================
select lives_ok(
  $q$ insert into public.notifications(
    recipient_user_id, recipient_employee_id, title, body, category, priority)
  values ('d1500000-0000-4000-8000-000000000001',
          'd1600000-0000-4000-8000-000000000001',
          'تنبيه حضور', 'اختبار', 'attendance', 'normal') $q$,
  'فئة attendance مقبولة في notifications.category بعد توسيع CHECK');

select * from finish();
rollback;
