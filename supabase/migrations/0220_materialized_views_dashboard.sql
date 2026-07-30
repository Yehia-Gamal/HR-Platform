-- Migration 0220: عروض مادية (Materialized Views) للوحة المعلومات
-- تُسرّع الاستعلامات الثقيلة المتكررة بتخزين نتائجها مسبقاً
-- تُحدَّث كل ساعتين عبر pg_cron أو يدوياً عبر refresh_all_materialized_views()

BEGIN;

-- =====================================================================
-- 1. mv_daily_attendance_summary — ملخص الحضور اليومي
--    المصدر: attendance_daily (التجميع اليومي لحضور الموظفين)
-- =====================================================================

DO $mv_attendance$
BEGIN
  -- تحقق من وجود الجدول المصدر
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'attendance_daily'
  ) THEN
    RAISE NOTICE 'جدول attendance_daily غير موجود؛ تُخطّى إنشاء mv_daily_attendance_summary.';
    RETURN;
  END IF;

  -- حذف العرض القديم إن وُجد لإعادة الإنشاء
  DROP MATERIALIZED VIEW IF EXISTS public.mv_daily_attendance_summary CASCADE;

  CREATE MATERIALIZED VIEW public.mv_daily_attendance_summary AS
  SELECT
    ad.work_date                                          AS date,
    -- العدد الكلي: جميع السجلات (يمثل الموظفين المتوقع حضورهم)
    count(*)                                              AS total_expected,
    -- الحاضرون: present أو late أو partial (جميعهم حضروا فعلياً)
    count(*) FILTER (WHERE ad.status IN ('present','late','partial'))
                                                          AS total_present,
    -- الغائبون
    count(*) FILTER (WHERE ad.status = 'absent')          AS total_absent,
    -- المتأخرون
    count(*) FILTER (WHERE ad.status = 'late')            AS total_late,
    -- متوسط دقائق التأخير (فقط لمن تأخر فعلاً)
    COALESCE(
      round(avg(ad.late_minutes) FILTER (WHERE ad.late_minutes > 0), 1),
      0
    )                                                     AS avg_delay_minutes
  FROM public.attendance_daily ad
  GROUP BY ad.work_date
  ORDER BY ad.work_date DESC
  WITH NO DATA;  -- لا تُملأ تلقائياً؛ أول REFRESH يملؤها

  COMMENT ON MATERIALIZED VIEW public.mv_daily_attendance_summary IS
    'ملخص الحضور اليومي المُجمَّع: عدد الحاضرين/الغائبين/المتأخرين ومتوسط التأخير لكل يوم.';

  -- فهرس فريد على التاريخ — مطلوب لـ REFRESH CONCURRENTLY
  CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_daily_att_summary_date
    ON public.mv_daily_attendance_summary (date);

  -- ملء أولي
  REFRESH MATERIALIZED VIEW public.mv_daily_attendance_summary;

  RAISE NOTICE 'تم إنشاء mv_daily_attendance_summary بنجاح.';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'خطأ أثناء إنشاء mv_daily_attendance_summary: % — %', SQLSTATE, SQLERRM;
END;
$mv_attendance$;


-- =====================================================================
-- 2. mv_department_headcount — عدد الموظفين حسب الإدارة
--    المصدر: employees + departments
-- =====================================================================

DO $mv_headcount$
BEGIN
  -- تحقق من وجود الجداول المصدر
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'employees'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'departments'
  ) THEN
    RAISE NOTICE 'جدول employees أو departments غير موجود؛ تُخطّى إنشاء mv_department_headcount.';
    RETURN;
  END IF;

  DROP MATERIALIZED VIEW IF EXISTS public.mv_department_headcount CASCADE;

  CREATE MATERIALIZED VIEW public.mv_department_headcount AS
  SELECT
    d.id                                                   AS department_id,
    d.name                                                 AS department_name,
    -- الموظفون النشطون (is_active وغير محذوفين)
    count(*) FILTER (WHERE e.is_active = true
                       AND e.is_deleted = false)           AS active_count,
    -- الموظفون غير النشطين (ما عدا المحذوفين)
    count(*) FILTER (WHERE e.is_active = false
                       AND e.is_deleted = false)           AS inactive_count,
    -- الإجمالي (بدون المحذوفين)
    count(*) FILTER (WHERE e.is_deleted = false)           AS total
  FROM public.departments d
  LEFT JOIN public.employees e ON e.department_id = d.id
  WHERE d.is_active = true
  GROUP BY d.id, d.name
  ORDER BY d.name
  WITH NO DATA;

  COMMENT ON MATERIALIZED VIEW public.mv_department_headcount IS
    'عدد الموظفين (نشط/غير نشط/إجمالي) لكل إدارة فعّالة. يُستخدم في لوحة المعلومات.';

  -- فهرس فريد على معرّف الإدارة — مطلوب لـ REFRESH CONCURRENTLY
  CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_dept_headcount_dept_id
    ON public.mv_department_headcount (department_id);

  REFRESH MATERIALIZED VIEW public.mv_department_headcount;

  RAISE NOTICE 'تم إنشاء mv_department_headcount بنجاح.';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'خطأ أثناء إنشاء mv_department_headcount: % — %', SQLSTATE, SQLERRM;
END;
$mv_headcount$;


-- =====================================================================
-- 3. mv_monthly_request_stats — إحصائيات الطلبات الشهرية
--    المصدر: requests
-- =====================================================================

DO $mv_requests$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'requests'
  ) THEN
    RAISE NOTICE 'جدول requests غير موجود؛ تُخطّى إنشاء mv_monthly_request_stats.';
    RETURN;
  END IF;

  DROP MATERIALIZED VIEW IF EXISTS public.mv_monthly_request_stats CASCADE;

  CREATE MATERIALIZED VIEW public.mv_monthly_request_stats AS
  SELECT
    date_trunc('month', r.created_at)::date               AS month,
    r.request_type,
    count(*)                                               AS total,
    count(*) FILTER (WHERE r.status = 'approved')          AS approved,
    count(*) FILTER (WHERE r.status = 'rejected')          AS rejected,
    count(*) FILTER (WHERE r.status = 'pending')           AS pending,
    -- متوسط ساعات المعالجة (من الإنشاء حتى القرار)
    COALESCE(
      round(
        avg(
          EXTRACT(EPOCH FROM (r.decided_at - r.created_at)) / 3600.0
        ) FILTER (WHERE r.decided_at IS NOT NULL),
        1
      ),
      0
    )                                                      AS avg_processing_hours
  FROM public.requests r
  GROUP BY date_trunc('month', r.created_at)::date, r.request_type
  ORDER BY month DESC, r.request_type
  WITH NO DATA;

  COMMENT ON MATERIALIZED VIEW public.mv_monthly_request_stats IS
    'إحصائيات الطلبات الشهرية: عدد الطلبات ونسب القبول/الرفض/المعلّق ومتوسط ساعات المعالجة لكل نوع.';

  -- فهرس فريد مركّب — مطلوب لـ REFRESH CONCURRENTLY
  CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_monthly_req_stats_month_type
    ON public.mv_monthly_request_stats (month, request_type);

  REFRESH MATERIALIZED VIEW public.mv_monthly_request_stats;

  RAISE NOTICE 'تم إنشاء mv_monthly_request_stats بنجاح.';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'خطأ أثناء إنشاء mv_monthly_request_stats: % — %', SQLSTATE, SQLERRM;
END;
$mv_requests$;


-- =====================================================================
-- 4. دالة تحديث يدوي لجميع العروض المادية
-- =====================================================================

CREATE OR REPLACE FUNCTION public.refresh_all_materialized_views()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_results  jsonb := '[]'::jsonb;
  v_start    timestamptz;
  v_elapsed  numeric;
BEGIN
  -- التحقق من صلاحية المستخدم (full-access فقط)
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'تحديث العروض المادية يتطلب صلاحية full-access.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ─── mv_daily_attendance_summary ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_daily_attendance_summary;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_daily_attendance_summary',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_daily_attendance_summary',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  -- ─── mv_department_headcount ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_department_headcount;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_department_headcount',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_department_headcount',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  -- ─── mv_monthly_request_stats ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_request_stats;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_monthly_request_stats',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_monthly_request_stats',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  RETURN jsonb_build_object(
    'refreshed_at', now(),
    'results', v_results
  );
END;
$$;

COMMENT ON FUNCTION public.refresh_all_materialized_views() IS
  'تحديث يدوي لجميع العروض المادية في لوحة المعلومات. يتطلب صلاحية full-access. يُرجع JSON بنتائج كل عرض.';

-- منع الموظف العادي من استدعاء الدالة مباشرة
REVOKE ALL ON FUNCTION public.refresh_all_materialized_views() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_all_materialized_views() TO authenticated;


-- =====================================================================
-- 5. جدولة التحديث التلقائي عبر pg_cron (كل ساعتين)
--    حارس آمن: إن غاب pg_cron تُتجاوز الجدولة دون كسر الترحيل
-- =====================================================================

DO $cron_schedule$
BEGIN
  -- تحقق من توفر pg_cron
  IF NOT EXISTS (
    SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'
  ) THEN
    RAISE NOTICE 'pg_cron غير متاح في هذه البيئة؛ العروض المادية لن تُحدَّث تلقائياً. استخدم refresh_all_materialized_views() يدوياً أو مشغّل خارجي.';
    RETURN;
  END IF;

  -- تأكّد من تفعيل الامتداد
  CREATE EXTENSION IF NOT EXISTS pg_cron;

  -- ─── ملخص الحضور اليومي — كل ساعتين ───
  BEGIN
    PERFORM cron.schedule(
      'refresh-attendance-summary',
      '0 */2 * * *',
      $$REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_daily_attendance_summary$$
    );
    RAISE NOTICE 'تمت جدولة تحديث mv_daily_attendance_summary كل ساعتين.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'فشل جدولة refresh-attendance-summary: %', SQLERRM;
  END;

  -- ─── عدد الموظفين حسب الإدارة — كل ساعتين (بإزاحة 10 دقائق) ───
  BEGIN
    PERFORM cron.schedule(
      'refresh-department-headcount',
      '10 */2 * * *',
      $$REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_department_headcount$$
    );
    RAISE NOTICE 'تمت جدولة تحديث mv_department_headcount كل ساعتين.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'فشل جدولة refresh-department-headcount: %', SQLERRM;
  END;

  -- ─── إحصائيات الطلبات الشهرية — كل ساعتين (بإزاحة 20 دقيقة) ───
  BEGIN
    PERFORM cron.schedule(
      'refresh-monthly-request-stats',
      '20 */2 * * *',
      $$REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_request_stats$$
    );
    RAISE NOTICE 'تمت جدولة تحديث mv_monthly_request_stats كل ساعتين.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'فشل جدولة refresh-monthly-request-stats: %', SQLERRM;
  END;

  RAISE NOTICE 'اكتملت جدولة تحديث العروض المادية عبر pg_cron.';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'خطأ عام في جدولة pg_cron: % — %', SQLSTATE, SQLERRM;
END;
$cron_schedule$;


-- =====================================================================
-- 6. صلاحيات القراءة على العروض المادية
--    القراءة متاحة للمستخدمين المصادق عليهم (RLS غير متاح على Materialized Views)
-- =====================================================================

GRANT SELECT ON public.mv_daily_attendance_summary  TO authenticated;
GRANT SELECT ON public.mv_department_headcount      TO authenticated;
GRANT SELECT ON public.mv_monthly_request_stats     TO authenticated;

COMMIT;
