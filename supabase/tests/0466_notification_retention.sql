-- pgTAP test for migration 0466: failed notification jobs retention
-- Validates:
--   ① function signature, guard, and grants
--   ② argument validation (retention window / batch size)
--   ③ functional purge: old failed jobs deleted, recent failed and sent kept

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① الدالة والمنح
-- ═══════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'purge_old_failed_notification_jobs', array['int','int'],
  '0466: دالة الاحتفاظ بالتوقيع الصحيح');

select function_privs_are(
  'public', 'purge_old_failed_notification_jobs', array['int','int'],
  'service_role', array['EXECUTE'],
  '0466: service_role يملك EXECUTE');

select function_privs_are(
  'public', 'purge_old_failed_notification_jobs', array['int','int'],
  'authenticated', '{}'::text[],
  '0466: authenticated بلا أي منحة على الدالة');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② التحقق من المدخلات
-- ═══════════════════════════════════════════════════════════════════════════

set local role service_role;
select throws_ok(
  'select public.purge_old_failed_notification_jobs(3, 100)',
  '22023', 'INVALID_RETENTION',
  '0466: نافذة احتفاظ أقل من 7 أيام مرفوضة');
reset role;

set local role service_role;
select throws_ok(
  'select public.purge_old_failed_notification_jobs(30, 0)',
  '22023', 'INVALID_BATCH',
  '0466: حجم دفعة غير صالح مرفوض');
reset role;

-- ═══════════════════════════════════════════════════════════════════════════
-- ③ التنظيف الوظيفي — الفاشل القديم يُحذف، والحديث والمرسل يبقيان
-- ═══════════════════════════════════════════════════════════════════════════

insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('aaaaaaaa-0000-4000-8000-000000046601', 'authenticated', 'authenticated',
        'retention-0466@example.com', 'x', '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.notification_jobs (recipient_user_id, channel, status, idempotency_key, created_at)
values
  ('aaaaaaaa-0000-4000-8000-000000046601', 'push', 'failed', 't0466-old-failed',
   now() - interval '40 days'),
  ('aaaaaaaa-0000-4000-8000-000000046601', 'push', 'failed', 't0466-new-failed',
   now() - interval '2 days'),
  ('aaaaaaaa-0000-4000-8000-000000046601', 'in_app', 'sent', 't0466-old-sent',
   now() - interval '40 days');

set local role service_role;
select is(
  public.purge_old_failed_notification_jobs(),
  1,
  '0466: حُذف صف فاشل واحد فقط (القديم)');
reset role;

select is(
  (select count(*)::int from public.notification_jobs
   where recipient_user_id = 'aaaaaaaa-0000-4000-8000-000000046601'
     and idempotency_key = 't0466-old-failed'),
  0, '0466: الصف الفاشل القديم غادر الجدول');

select is(
  (select count(*)::int from public.notification_jobs
   where recipient_user_id = 'aaaaaaaa-0000-4000-8000-000000046601'),
  2, '0466: الفاشل الحديث والمرسل القديم بقيا');

select * from finish();
rollback;
