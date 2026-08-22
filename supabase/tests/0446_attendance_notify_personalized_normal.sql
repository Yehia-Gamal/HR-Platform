-- 0446: تخصيص نصوص إشعارات الحضور وتصفية «العاجلة»
-- يثبت أن:
--   1) إشعار المدير المباشر والتنفيذي بعنوان شخصي «وصل فلان للعمل بالمجمع»
--      عند الدخول و«خرج فلان من المجمع» عند الانصراف (لا عناوين عامة).
--   2) إشعار المدير التنفيذي بأولوية normal دون وسوم full-screen —
--      لا يغرق قسم «تنبيهات عاجلة».
--   3) المدير المباشر يبقى بأولوية low والموظف بإشعاره الذاتي كما هو.
--   4) لا يُشعر التنفيذي عن حضور/انصراف نفسه.
--   5) التريجر لم يعُد يستخدم notify_executive_fullscreen، ولا توجد أي
--      إشعارات حضور مخزنة بأولوية urgent/high.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(13);

-- ═════════════════════════════════════════════════════════════════════
-- Fixtures: موظف + مدير مباشر + مدير تنفيذي
-- ═════════════════════════════════════════════════════════════════════
insert into auth.users (id, email, aud, role)
values
  ('04460000-0000-4000-8000-000000000001', 'tst-0446-emp@test.local',  'authenticated', 'authenticated'),
  ('04460000-0000-4000-8000-000000000002', 'tst-0446-mgr@test.local',  'authenticated', 'authenticated'),
  ('04460000-0000-4000-8000-000000000003', 'tst-0446-exec@test.local', 'authenticated', 'authenticated');

insert into public.employees (id, employee_code, full_name_ar, is_active, status)
values
  ('04460000-0000-4000-8000-000000000101', 'TST-0446-EMP',  'موظف اختبار 0446',   true, 'active'),
  ('04460000-0000-4000-8000-000000000102', 'TST-0446-MGR',  'مدير اختبار 0446',   true, 'active'),
  ('04460000-0000-4000-8000-000000000103', 'TST-0446-EXEC', 'تنفيذي اختبار 0446', true, 'active');

insert into public.profiles (id, employee_id)
values
  ('04460000-0000-4000-8000-000000000001', '04460000-0000-4000-8000-000000000101'),
  ('04460000-0000-4000-8000-000000000002', '04460000-0000-4000-8000-000000000102'),
  ('04460000-0000-4000-8000-000000000003', '04460000-0000-4000-8000-000000000103');

insert into public.roles (slug, name_ar, is_system, is_full_access)
values ('executive-director', 'المدير التنفيذي', true, true)
on conflict (slug) do nothing;

insert into public.user_roles (user_id, role_id)
select '04460000-0000-4000-8000-000000000003', id
from public.roles where slug = 'executive-director'
on conflict do nothing;

insert into public.manager_relations (
  employee_id, manager_employee_id, relation_type,
  effective_from, effective_to
) values (
  '04460000-0000-4000-8000-000000000101',
  '04460000-0000-4000-8000-000000000102',
  'primary', current_date, null
);

-- ═════════════════════════════════════════════════════════════════════
-- 1) دخول موظف: عناوين شخصية وأولويات صحيحة
-- ═════════════════════════════════════════════════════════════════════
insert into public.attendance_daily (
  employee_id, work_date, first_check_in
) values (
  '04460000-0000-4000-8000-000000000101',
  current_date, current_timestamp
);

select is(
  (select title from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000102'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'),
  'وصل موظف للعمل بالمجمع',
  '(1) عنوان المدير المباشر شخصي «وصل موظف للعمل بالمجمع»'
);

select is(
  (select priority from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000102'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'),
  'low',
  '(2) أولوية إشعار المدير المباشر low'
);

select is(
  (select title from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'
      and metadata->>'employeeId' = '04460000-0000-4000-8000-000000000101'),
  'وصل موظف للعمل بالمجمع',
  '(3) عنوان التنفيذي شخصي «وصل موظف للعمل بالمجمع»'
);

select is(
  (select priority from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'
      and metadata->>'employeeId' = '04460000-0000-4000-8000-000000000101'),
  'normal',
  '(4) أولوية إشعار التنفيذي normal (لا urgent)'
);

select is(
  (select metadata->>'fullScreen' from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'
      and metadata->>'employeeId' = '04460000-0000-4000-8000-000000000101'),
  null,
  '(5) لا وسم fullScreen في إشعار التنفيذي'
);

select ok(
  (select body from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_in'
      and metadata->>'employeeId' = '04460000-0000-4000-8000-000000000101')
    like '%دخل الساعة%',
  '(6) متن الإشعار يحمل وقت الدخول'
);

select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000101'
      and entity_type = 'attendance_daily'
      and metadata->>'self' = 'true'
      and title = 'تم تسجيل حضورك'),
  1,
  '(7) الموظف يتلقى تأكيده الذاتي «تم تسجيل حضورك»'
);

-- ═════════════════════════════════════════════════════════════════════
-- 2) انصراف نفس الموظف: عنوان «خرج … من المجمع»
-- ═════════════════════════════════════════════════════════════════════
update public.attendance_daily
set last_check_out = current_timestamp
where employee_id = '04460000-0000-4000-8000-000000000101'
  and work_date = current_date;

select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_out'),
  1,
  '(8) التنفيذي تلقى إشعار انصراف واحداً'
);

select is(
  (select title from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'event' = 'attendance_check_out'),
  'خرج موظف من المجمع',
  '(9) عنوان الانصراف شخصي «خرج موظف من المجمع»'
);

-- ═════════════════════════════════════════════════════════════════════
-- 3) حضور المدير التنفيذي نفسه: إشعار ذاتي فقط دون إشعار تنفيذي عنه
-- ═════════════════════════════════════════════════════════════════════
insert into public.attendance_daily (
  employee_id, work_date, first_check_in
) values (
  '04460000-0000-4000-8000-000000000103',
  current_date, current_timestamp
);

select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'self' = 'true'),
  1,
  '(10) التنفيذي يتلقى تأكيداً ذاتياً لحضوره'
);

select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = '04460000-0000-4000-8000-000000000103'
      and entity_type = 'attendance_daily'
      and metadata->>'self' is null
      and metadata->>'employeeId' = '04460000-0000-4000-8000-000000000103'),
  0,
  '(11) لا يُنشأ إشعار تنفيذي عن حضور التنفيذي نفسه'
);

-- ═════════════════════════════════════════════════════════════════════
-- 4) التريجر بلا قناة العاجلة ولا توجد إشعارات حضور عاجلة مخزنة
-- ═════════════════════════════════════════════════════════════════════
select is(
  (select count(*)::int from pg_proc
    where proname = 'tg_attendance_daily_notify_manager'
      and prosrc ~ 'notify_executive_fullscreen'),
  0,
  '(12) مصدر التريجر لم يعُد يستدعي notify_executive_fullscreen'
);

select is(
  (select count(*)::int from public.notifications
    where category = 'attendance'
      and priority in ('urgent', 'high')),
  0,
  '(13) لا توجد أي إشعارات حضور بأولوية urgent/high بعد التصحيح'
);

select finish();
rollback;
