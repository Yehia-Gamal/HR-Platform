-- pgTAP test for migration 0467: cron health queue-lag alerts
-- Validates:
--   ① extended verify_critical_cron_jobs keeps its signature and stays callable
--   ② healthy state opens none of the three new alert keys
--   ③ a flood of recent failed push jobs opens notification_push_failures_spike

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① الدالة الموسّعة موجودة وتعمل بلا أخطاء
-- ═══════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'verify_critical_cron_jobs', '{}'::text[],
  '0467: دالة فاحص الصحة بالتوقيع نفسه (بلا معاملات)');

select lives_ok(
  'select * from public.verify_critical_cron_jobs()',
  '0467: الفاحص يعمل تحت postgres دون استثناء');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② الحالة الصحية لا تفتح أي تنبيه من الثلاثة الجديدة
-- ═══════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.system_alerts
   where alert_key in (
     'notification_dispatch_stalled',
     'integration_outbox_lag',
     'notification_push_failures_spike')
     and status = 'open'),
  0,
  '0467: بيئة اختبار صحية بلا تنبيهات طوابير مفتوحة');

-- ═══════════════════════════════════════════════════════════════════════════
-- ③ فيض إشعارات push الفاشلة يفتح التنبيه P2 ثم يُحسم عند الزوال
-- ═══════════════════════════════════════════════════════════════════════════

insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('aaaaaaaa-0000-4000-8000-000000046701', 'authenticated', 'authenticated',
        'lag-0467@example.com', 'x', '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.notification_jobs (recipient_user_id, channel, status, idempotency_key)
select 'aaaaaaaa-0000-4000-8000-000000046701', 'push', 'failed',
       't0467-' || g::text
from generate_series(1, 55) g;

select public.verify_critical_cron_jobs();

select is(
  (select count(*)::int from public.system_alerts
   where alert_key = 'notification_push_failures_spike' and status = 'open'),
  1,
  '0467: 55 فاشلاً خلال أسبوع يفتح تنبيه الفيض');

delete from public.notification_jobs where idempotency_key like 't0467-%';

select public.verify_critical_cron_jobs();

select is(
  (select count(*)::int from public.system_alerts
   where alert_key = 'notification_push_failures_spike' and status = 'resolved'),
  1,
  '0467: زوال السبب يحسم التنبيه إلى resolved');

select * from finish();
rollback;
