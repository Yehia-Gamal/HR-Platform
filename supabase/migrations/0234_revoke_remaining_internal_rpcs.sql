-- ═══════════════════════════════════════════════════════════════
-- 0234: سد الثغرات المتبقية — الجولة الخامسة
-- دوال داخلية لا تُستدعى من الواجهة (web/mobile) مطلقاً
-- جميعها تُستدعى فقط من:
--   • دوال SECURITY DEFINER أخرى (تعمل كـ postgres)
--   • Edge Functions (service_role)
--   • pg_cron (postgres)
--
-- P1:
--   1. log_audit_event — حقن أحداث تدقيق مزيفة
--   2. nudge_notification_dispatcher — تفعيل HTTP call داخلي
--   3. process_dispute_sla — عملية نظام (SLA disputes)
--   4. close_kpi_cycle_due — عملية مجدولة (KPI)
--   5. list_retention_video_candidates — تسريب قائمة الفيديوهات
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- P1-1: log_audit_event — سحب من authenticated
-- تُستدعى من triggers و SECURITY DEFINER functions فقط
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'log_audit_event'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-2: nudge_notification_dispatcher — سحب من authenticated
-- تُستدعى من SECURITY DEFINER functions عبر perform فقط
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'nudge_notification_dispatcher'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-3: process_dispute_sla — سحب من authenticated
-- عملية نظام تُستدعى من scheduled job أو service_role
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'process_dispute_sla'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-4: close_kpi_cycle_due — سحب من authenticated
-- عملية مجدولة تُستدعى من pg_cron
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'close_kpi_cycle_due'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-5: list_retention_video_candidates — سحب من authenticated
-- تُستدعى من Edge Function retention-cleanup فقط
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'list_retention_video_candidates'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

COMMIT;
