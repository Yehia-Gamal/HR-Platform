-- pgTAP: V23 §1E — rate limiting expansion (migration 0174)
-- تتحقق من: جدول rate_limit_log، دالة check_rate_limit، الدوال المتخصصة
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions, pg_temp;
SELECT plan(22);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) جدول rate_limit_log
-- ═══════════════════════════════════════════════════════════════════════
SELECT has_table('public', 'rate_limit_log',
  'rate_limit_log table exists');

SELECT has_column('public', 'rate_limit_log', 'id',
  'rate_limit_log has id column');

SELECT has_column('public', 'rate_limit_log', 'user_id',
  'rate_limit_log has user_id column');

SELECT has_column('public', 'rate_limit_log', 'domain',
  'rate_limit_log has domain column');

SELECT has_column('public', 'rate_limit_log', 'created_at',
  'rate_limit_log has created_at column');

-- RLS مفعل
SELECT ok(
  coalesce(
    (SELECT relrowsecurity FROM pg_class
     WHERE relname = 'rate_limit_log'
       AND relnamespace = 'public'::regnamespace),
    false
  ),
  'rate_limit_log has RLS enabled'
);

-- فهرس البحث
SELECT has_index('public', 'rate_limit_log', 'idx_rate_limit_log_lookup',
  'rate_limit_log lookup index exists');

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الدالة العامة check_rate_limit
-- ═══════════════════════════════════════════════════════════════════════
SELECT has_function('public', 'check_rate_limit', ARRAY['text', 'integer', 'integer'],
  'check_rate_limit(text, integer, integer) exists');

SELECT ok(
  coalesce(
    (SELECT p.prosecdef FROM pg_proc p
     JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'check_rate_limit'
       AND p.pronargs = 3),
    false
  ),
  'check_rate_limit is SECURITY DEFINER'
);

SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'check_rate_limit'
      AND EXISTS(SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  ),
  'check_rate_limit has pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) 6 دوال متخصصة موجودة
-- ═══════════════════════════════════════════════════════════════════════
SELECT has_function('public', 'check_employee_create_rate_limit',
  'check_employee_create_rate_limit() exists');

SELECT has_function('public', 'check_role_assign_rate_limit',
  'check_role_assign_rate_limit() exists');

SELECT has_function('public', 'check_device_register_rate_limit',
  'check_device_register_rate_limit() exists');

SELECT has_function('public', 'check_attendance_punch_rate_limit',
  'check_attendance_punch_rate_limit() exists');

SELECT has_function('public', 'check_location_request_rate_limit',
  'check_location_request_rate_limit() exists');

SELECT has_function('public', 'check_post_publish_rate_limit',
  'check_post_publish_rate_limit() exists');

-- ═══════════════════════════════════════════════════════════════════════
-- 4) كل الدوال المتخصصة SECURITY DEFINER مع search_path
-- ═══════════════════════════════════════════════════════════════════════
SELECT ok(
  coalesce(
    (SELECT every(p.prosecdef) FROM pg_proc p
     JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public'
       AND p.proname IN (
         'check_employee_create_rate_limit',
         'check_role_assign_rate_limit',
         'check_device_register_rate_limit',
         'check_attendance_punch_rate_limit',
         'check_location_request_rate_limit',
         'check_post_publish_rate_limit'
       )),
    false
  ),
  'all 6 specialized rate-limit functions are SECURITY DEFINER'
);

SELECT ok(
  coalesce(
    (SELECT every(
       EXISTS(SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
     )
     FROM pg_proc p
     JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public'
       AND p.proname IN (
         'check_employee_create_rate_limit',
         'check_role_assign_rate_limit',
         'check_device_register_rate_limit',
         'check_attendance_punch_rate_limit',
         'check_location_request_rate_limit',
         'check_post_publish_rate_limit'
       )),
    false
  ),
  'all 6 specialized rate-limit functions have pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 5) صلاحيات: الدالة العامة لا تُنفذ من anon وتُنفذ من authenticated
-- ═══════════════════════════════════════════════════════════════════════
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'check_rate_limit'
      AND p.pronargs = 3
      AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  'check_rate_limit not executable by anon role'
);

SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'check_rate_limit'
      AND p.pronargs = 3
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  'check_rate_limit executable by authenticated role'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 6) RLS policies تمنع الوصول المباشر
-- ═══════════════════════════════════════════════════════════════════════
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_policies
    WHERE tablename = 'rate_limit_log' AND schemaname = 'public'
      AND policyname = 'rate_limit_log_deny_select'
  ),
  'deny select policy exists on rate_limit_log'
);

SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_policies
    WHERE tablename = 'rate_limit_log' AND schemaname = 'public'
      AND policyname = 'rate_limit_log_deny_insert'
  ),
  'deny insert policy exists on rate_limit_log'
);

SELECT * FROM finish();
ROLLBACK;
