-- pgTAP test for migration 0454: attendance events archival policy
-- Validates:
--   ① archive table exists, RLS enabled, locked for authenticated
--   ② archive function signature, guard, and grants
--   ③ functional move: old events leave the live table and land in the archive

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(9);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① البنية والقفل
-- ═══════════════════════════════════════════════════════════════════════════

select has_table(
  'public', 'attendance_events_archive',
  '0454: جدول الأرشفة موجود');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.attendance_events_archive'::regclass),
  '0454: RLS مفعّل على الأرشيف');

set local role authenticated;
-- 42501 يتطلب تجربة القراءة بصلاحية غير خارقة (postgres يتجاوز الصلاحيات وRLS)
set local role authenticated;
select throws_ok(
  'select * from public.attendance_events_archive limit 1',
  '42501', null,
  '0454: المستخدم العادي ممنوع من قراءة الأرشيف');
reset role;
reset role;

-- ═══════════════════════════════════════════════════════════════════════════
-- ② الدالة
-- ═══════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'archive_old_attendance_events', array['int','int'],
  '0454: دالة الأرشفة بالتوقيع الصحيح');

select function_privs_are(
  'public', 'archive_old_attendance_events', array['int','int'],
  'service_role', array['EXECUTE'],
  '0454: service_role فقط ينفذ الأرشفة');

select throws_ok(
  'select public.archive_old_attendance_events(25, 50)',
  '22023', 'INVALID_BATCH',
  '0454: حجم الدفعة الصغير مرفوض');

-- ═══════════════════════════════════════════════════════════════════════════
-- ③ النقل الوظيفي — حدث قديم ينتقل، وحديث يبقى
-- ═══════════════════════════════════════════════════════════════════════════

insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('aaaaaaaa-0000-4000-8000-000000045401', 'authenticated', 'authenticated',
        'archive-0454@example.com', 'x', '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.employees (id, user_id, employee_code, full_name_ar, status, is_active)
values ('bbbbbbbb-0000-4000-8000-000000045401', 'aaaaaaaa-0000-4000-8000-000000045401',
        'T-0454', 'موظف اختبار الأرشفة', 'active', true);

insert into public.attendance_events (employee_id, event_type, event_at, status)
values
  ('bbbbbbbb-0000-4000-8000-000000045401', 'CHECK_IN',  now() - interval '30 months', 'accepted'),
  ('bbbbbbbb-0000-4000-8000-000000045401', 'CHECK_IN',  now(), 'accepted');

select public.archive_old_attendance_events();

select is(
  (select count(*)::int from public.attendance_events
   where employee_id = 'bbbbbbbb-0000-4000-8000-000000045401'
     and event_at < date_trunc('month', now()) - make_interval(months => 25)),
  0, '0454: الحدث القديم غادر الجدول الحي');

select is(
  (select count(*)::int from public.attendance_events_archive
   where employee_id = 'bbbbbbbb-0000-4000-8000-000000045401'),
  1, '0454: الحدث القديم وصل الأرشيف');

select is(
  (select count(*)::int from public.attendance_events
   where employee_id = 'bbbbbbbb-0000-4000-8000-000000045401'
     and event_at >= date_trunc('month', now()) - make_interval(months => 25)),
  1, '0454: الحدث الحديث بقي في الجدول الحي');

select * from finish();
rollback;