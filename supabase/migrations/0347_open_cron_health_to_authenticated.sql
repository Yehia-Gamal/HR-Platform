-- ================================================================================
-- 0347: Open cron health RPCs to authenticated admins with internal guard
-- ================================================================================
-- السياق: get_cron_health_summary() و get_cron_job_health() محجورتان على
-- postgres/service_role فقط (0244). الويب (لوحة المراقبة) لا يستطيع قراءتهما
-- لأنه يستدعي عبر authenticated. الحل:
--   - الدالتان SECURITY DEFINER → لا يمكن الاعتماد على RLS، بل فحص داخلي:
--     current_is_full_access() OR has_permission('observability.read')
--     OR has_permission('admin.observability') (نفس شرط observability_events).
--   - ثم GRANT EXECUTE إلى authenticated.

BEGIN;

-- ─── إعادة تعريف summary مع الفحص الداخلي ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_cron_health_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('observability.read')
    OR public.has_permission('admin.observability')
  ) THEN
    RAISE EXCEPTION 'insufficient privilege for cron health summary' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'total_jobs', COUNT(*),
    'active', COUNT(*) FILTER (WHERE active),
    'failing', COUNT(*) FILTER (WHERE health_status = 'failing'),
    'unstable', COUNT(*) FILTER (WHERE health_status = 'unstable'),
    'healthy', COUNT(*) FILTER (WHERE health_status = 'healthy'),
    'never_run', COUNT(*) FILTER (WHERE health_status = 'never_run'),
    'disabled', COUNT(*) FILTER (WHERE health_status = 'disabled'),
    'checked_at', now(),
    'failures_24h_total', COALESCE(SUM(failures_24h), 0)
  )
  INTO result
  FROM public.cron_job_health;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_health_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_health_summary() TO authenticated, service_role;

-- ─── إعادة تعريف القائمة التفصيلية مع الفحص الداخلي ────────────────────────
CREATE OR REPLACE FUNCTION public.get_cron_job_health()
RETURNS SETOF public.cron_job_health
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('observability.read')
    OR public.has_permission('admin.observability')
  ) THEN
    RAISE EXCEPTION 'insufficient privilege for cron job health' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT * FROM public.cron_job_health;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_job_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_job_health() TO authenticated, service_role;

COMMIT;
