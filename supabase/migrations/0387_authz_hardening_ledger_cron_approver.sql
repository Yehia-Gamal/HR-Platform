-- ══════════════════════════════════════════════════════════════════════
-- 0387: تصحيح ثغرات SECURITY DEFINER في 0382/0384/0385
--
-- P0 — apply_leave_ledger_entry (0382):
--   أُعطيت عن طريق الخطأ لـ authenticated رغم تقييدها في 0106 و0227.
--   الدالة تُغيّر أرصدة الإجازات لأي موظف — لا يجوز استدعاؤها من الويب.
--   الإصلاح: سحب EXECUTE من authenticated، الإبقاء على service_role
--   (تُستدعى حصراً من: trigger functions + cron jobs + RPCs أخرى SECURITY DEFINER).
--
-- MEDIUM — get_cron_health (0384):
--   SECURITY DEFINER بلا فحص صلاحية → تمرير RLS → تكشف لكل authenticated
--   عن سجل صحة الـ Cron. الإصلاح: إعادة الكتابة بـ plpgsql + فحص current_is_full_access().
--
-- MEDIUM — resolve_request_approver (0385):
--   تكشف هيكل الإدارة لأي authenticated بالجملة.
--   الإصلاح: تقييد الاستدعاء المباشر لـ service_role + الدوال الداخلية؛
--   المستخدمون العاديون يصلون إليها عبر submit_my_request (SECURITY DEFINER chain).
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

-- ── P0: apply_leave_ledger_entry ─────────────────────────────────────────────
-- سحب الصلاحية من authenticated — تُستدعى حصراً عبر chain داخلي
REVOKE EXECUTE ON FUNCTION public.apply_leave_ledger_entry(
  integer, integer, text, numeric, text, text, date
) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.apply_leave_ledger_entry(
  integer, integer, text, numeric, text, text, date
) TO service_role;

-- ── MEDIUM: get_cron_health — إضافة فحص الصلاحية ────────────────────────────
CREATE OR REPLACE FUNCTION public.get_cron_health()
RETURNS TABLE(
  job_name     text,
  last_run     timestamptz,
  minutes_ago  numeric,
  last_status  text,
  is_healthy   boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- مسموح فقط لـ: full-access أو service_role
  IF auth.role() <> 'service_role' AND NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      l.job_name,
      max(l.ran_at)                                          AS last_run,
      round(extract(epoch FROM now() - max(l.ran_at)) / 60, 1) AS minutes_ago,
      (array_agg(l.status ORDER BY l.ran_at DESC))[1]       AS last_status,
      max(l.ran_at) > now() - INTERVAL '30 minutes'         AS is_healthy
    FROM public.cron_health_log l
    GROUP BY l.job_name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_cron_health() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_health() TO service_role;
-- يُمنح full_access_users استدعاؤها عبر has_permission check داخل الدالة
GRANT EXECUTE ON FUNCTION public.get_cron_health() TO authenticated;

-- ── MEDIUM: resolve_request_approver — تقييد الاستدعاء المباشر ───────────────
-- الدالة تكشف هيكل الإدارة؛ authenticated يصلون إليها عبر submit_my_request فقط
REVOKE EXECUTE ON FUNCTION public.resolve_request_approver(integer, text)
FROM authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_request_approver(integer, text)
TO service_role;

COMMIT;
