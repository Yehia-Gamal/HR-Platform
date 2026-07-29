-- تعزيز أمني — الجولة الثانية
-- 1. سحب صلاحية EXECUTE من PUBLIC (لا anon فقط) على جميع الدوال المخصصة
-- 2. إعادة منح authenticated + service_role
-- 3. حماية auth_invite_log
-- 4. إضافة triggers مفقودة لـ updated_at
-- 5. ضبط الصلاحيات الافتراضية للدوال الجديدة مستقبلاً

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. REVOKE EXECUTE FROM PUBLIC + anon على جميع الدوال المخصصة
--    (يعالج أن migration 0207 سحب من anon فقط بينما PUBLIC يمنحها ضمنياً)
--    نستثني: handle_new_user, activate_employee_after_first_login, get_public_release_policy
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname NOT IN (
        'handle_new_user',
        'activate_employee_after_first_login',
        'get_public_release_policy'
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        JOIN pg_extension e ON d.refobjid = e.oid
        WHERE d.objid = p.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || r.sig || ' FROM PUBLIC, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || r.sig || ' TO authenticated, service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- 2. صلاحيات افتراضية: الدوال الجديدة لا تُمنح لـ PUBLIC تلقائياً
-- ═══════════════════════════════════════════════════════════════

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════
-- 3. حماية جدول auth_invite_log — قراءة فقط للمصادَق عليهم
-- ═══════════════════════════════════════════════════════════════

REVOKE ALL ON TABLE public.auth_invite_log FROM anon, authenticated;
GRANT SELECT ON TABLE public.auth_invite_log TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 4. إضافة triggers مفقودة لـ updated_at
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'announcement_acknowledgements',
    'decision_execution_items',
    'decision_poll_votes',
    'decision_recipients',
    'kpi_appeals',
    'kpi_attendance_snapshots',
    'kpi_compliance_records',
    'kpi_review_sessions',
    'permissions',
    'roles',
    'survey_responses'
  ]
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS set_updated_at ON public.%I', tbl
    );
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
      tbl
    );
  END LOOP;
END
$$;

COMMIT;
