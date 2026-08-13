-- pgTAP: اختبارات تدقيق أمني — search_path hardening + USING(true) allowlist
-- Agent 11 — Database Security Continuous
-- Validates migration 0163_v23_security_search_path_hardening.sql

BEGIN;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
SELECT plan(27);

-- ════════════════════════════════════════════════════════════════
-- 1. search_path مثبت على الدوال المُصلحة في 0160
-- ════════════════════════════════════════════════════════════════

-- server_now
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'server_now'
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  ),
  'server_now() has pinned search_path'
);

-- set_updated_at
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'set_updated_at'
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  ),
  'set_updated_at() has pinned search_path'
);

-- tg_set_updated_at
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'tg_set_updated_at'
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  ),
  'tg_set_updated_at() has pinned search_path'
);

-- kpi_effective_deadline
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'kpi_effective_deadline'
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  ),
  'kpi_effective_deadline() has pinned search_path'
);


-- ════════════════════════════════════════════════════════════════
-- 2. كل دوال SECURITY DEFINER لها search_path
-- ════════════════════════════════════════════════════════════════

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
   AND p.prosecdef = true
   AND NOT EXISTS (
     SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'
   ))::integer,
  0,
  'صفر دوال SECURITY DEFINER بدون search_path'
);


-- ════════════════════════════════════════════════════════════════
-- 3. USING(true) فقط على جداول مرجعية مسموحة
--    (Default Deny — الجداول الحساسة يجب ألا تحتوي على using(true))
-- ════════════════════════════════════════════════════════════════

-- الجداول المحظور أن تحتوي using(true) — بيانات حساسة
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'employees' AND qual = 'true'
  ),
  'employees — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'attendance_events' AND qual = 'true'
  ),
  'attendance_events — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'requests' AND qual = 'true'
  ),
  'requests — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'kpi_evaluations' AND qual = 'true'
  ),
  'kpi_evaluations — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'dispute_cases' AND qual = 'true'
  ),
  'dispute_cases — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'audit_events' AND qual = 'true'
  ),
  'audit_events — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'security_events' AND qual = 'true'
  ),
  'security_events — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'login_auth_attempts' AND qual = 'true'
  ),
  'login_auth_attempts — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'employee_locations' AND qual = 'true'
  ),
  'employee_locations — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'live_location_requests' AND qual = 'true'
  ),
  'live_location_requests — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications' AND qual = 'true'
  ),
  'notifications — لا using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'leave_balances' AND qual = 'true'
  ),
  'leave_balances — لا using(true)'
);


-- ════════════════════════════════════════════════════════════════
-- 4. RLS مفعل على كل الجداول الحساسة
-- ════════════════════════════════════════════════════════════════

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.employees'::regclass),
  'RLS مفعل على employees'
);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.attendance_events'::regclass),
  'RLS مفعل على attendance_events'
);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.requests'::regclass),
  'RLS مفعل على requests'
);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.kpi_evaluations'::regclass),
  'RLS مفعل على kpi_evaluations'
);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.audit_events'::regclass),
  'RLS مفعل على audit_events'
);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.employee_locations'::regclass),
  'RLS مفعل على employee_locations'
);


-- ════════════════════════════════════════════════════════════════
-- 5. الدوال الأمنية الحساسة — REVOKE من PUBLIC
-- ════════════════════════════════════════════════════════════════

SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'provision_employee_record — no anon EXECUTE'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'provision_employee_record' LIMIT 1;

SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'record_attendance_event — no anon EXECUTE'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'record_attendance_event' LIMIT 1;


-- ════════════════════════════════════════════════════════════════
-- 6. الدوال المصلحة — الجسم لم يتغير (تحقق وظيفي)
-- ════════════════════════════════════════════════════════════════

-- server_now returns current time (within 2 seconds)
SELECT ok(
  abs(extract(epoch FROM (public.server_now() - now()))) < 2,
  'server_now() returns current timestamp'
);

-- kpi_effective_deadline returns coalesce correctly
-- (can only test signature exists; full test needs kpi_cycles row)
SELECT has_function('public', 'kpi_effective_deadline', ARRAY['public.kpi_cycles'],
  'kpi_effective_deadline(kpi_cycles) exists');


SELECT * FROM finish();
ROLLBACK;
