-- =====================================================================
-- 0222: مهام صيانة مجدولة — تنظيف سجل Rate Limit + مراقبة الخصوصية
--       + تدقيق صلاحيات EXECUTE الشهري
--
-- المرجع:
--   • 0176 — rate_limit_log (التنظيف كان معلقًا في تعليق)
--   • 0038 — privacy_requests (طلبات الخصوصية)
--   • 0011 — security_events (أحداث أمنية)
--   • 0207/0209 — حماية anon EXECUTE
--
-- المكونات:
--   1) تنظيف يومي لسجل rate_limit_log (أقدم من 7 أيام)
--   2) فحص أسبوعي لطلبات الخصوصية المتأخرة (> 30 يوم بدون حل)
--   3) تدقيق شهري لصلاحيات EXECUTE على دوال anon
--
-- جميع المهام تستخدم pg_cron وتكتب النتائج في security_events.
-- حراسة IF EXISTS على كل جدول مطلوب.
-- =====================================================================

DO $migration$
DECLARE
  v_has_cron        boolean;
  v_has_rate_log    boolean;
  v_has_privacy     boolean;
  v_has_sec_events  boolean;
BEGIN

  -- ═══════════════════════════════════════════════════════════════════
  -- 0) التحقق من وجود إضافة pg_cron
  -- ═══════════════════════════════════════════════════════════════════
  SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) INTO v_has_cron;

  IF NOT v_has_cron THEN
    RAISE NOTICE '⏭ pg_cron غير مُثبت — تُتخطى جميع الجدولات.';
    RETURN;
  END IF;

  -- التحقق من وجود الجداول المطلوبة
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'rate_limit_log'
  ) INTO v_has_rate_log;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'privacy_requests'
  ) INTO v_has_privacy;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'security_events'
  ) INTO v_has_sec_events;

  -- ═══════════════════════════════════════════════════════════════════
  -- إزالة الجدولات السابقة (idempotent)
  -- ═══════════════════════════════════════════════════════════════════
  PERFORM cron.unschedule(jobname)
    FROM cron.job
    WHERE jobname IN (
      'cleanup-rate-limit-log',
      'privacy-request-deadline-check',
      'audit-anon-function-grants'
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- 1) تنظيف يومي لسجل Rate Limit — حذف الأقدم من 7 أيام
  --    (كان معلقًا في تعليق داخل 0176)
  --    الموعد: الساعة 3 فجرًا يوميًا
  -- ═══════════════════════════════════════════════════════════════════
  IF v_has_rate_log THEN
    PERFORM cron.schedule(
      'cleanup-rate-limit-log',
      '0 3 * * *',
      $$DELETE FROM public.rate_limit_log
        WHERE created_at < now() - interval '7 days'$$
    );
    RAISE NOTICE '✅ تمت جدولة تنظيف rate_limit_log (يوميًا 03:00).';
  ELSE
    RAISE NOTICE '⏭ جدول rate_limit_log غير موجود — تُتخطى الجدولة.';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 2) فحص أسبوعي لطلبات الخصوصية المتأخرة
  --    طلبات بحالة submitted/in_review أقدم من 30 يومًا → حدث أمني warning
  --    الموعد: كل اثنين الساعة 9 صباحًا
  -- ═══════════════════════════════════════════════════════════════════
  IF v_has_privacy AND v_has_sec_events THEN
    PERFORM cron.schedule(
      'privacy-request-deadline-check',
      '0 9 * * 1',
      $$INSERT INTO public.security_events
          (event_type, severity, outcome, details, created_at)
        SELECT
          'privacy_request_overdue',
          'warning',
          'detected',
          jsonb_build_object(
            'request_id', id,
            'status', status,
            'days_overdue', EXTRACT(DAY FROM now() - created_at)::int
          ),
          now()
        FROM public.privacy_requests
        WHERE status IN ('submitted', 'in_review')
          AND created_at < now() - interval '30 days'$$
    );
    RAISE NOTICE '✅ تمت جدولة فحص طلبات الخصوصية المتأخرة (أسبوعيًا).';
  ELSE
    RAISE NOTICE '⏭ privacy_requests أو security_events غير موجود — تُتخطى الجدولة.';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 3) تدقيق شهري لصلاحيات EXECUTE على دوال anon
  --    أي دالة public يملك anon صلاحية EXECUTE عليها
  --    (باستثناء القائمة البيضاء) → حدث أمني critical
  --    الموعد: أول يوم من كل شهر الساعة 2 فجرًا
  -- ═══════════════════════════════════════════════════════════════════
  IF v_has_sec_events THEN
    PERFORM cron.schedule(
      'audit-anon-function-grants',
      '0 2 1 * *',
      $$INSERT INTO public.security_events
          (event_type, severity, outcome, details, created_at)
        SELECT
          'anon_function_grant_detected',
          'critical',
          'detected',
          jsonb_build_object(
            'function', routine_name,
            'schema', routine_schema,
            'audit_month', to_char(now(), 'YYYY-MM')
          ),
          now()
        FROM information_schema.routine_privileges
        WHERE grantee = 'anon'
          AND privilege_type = 'EXECUTE'
          AND routine_schema = 'public'
          AND routine_name NOT IN ('get_public_release_policy')$$
    );
    RAISE NOTICE '✅ تمت جدولة تدقيق صلاحيات anon EXECUTE (شهريًا).';
  ELSE
    RAISE NOTICE '⏭ جدول security_events غير موجود — تُتخطى جدولة التدقيق.';
  END IF;

END
$migration$;
