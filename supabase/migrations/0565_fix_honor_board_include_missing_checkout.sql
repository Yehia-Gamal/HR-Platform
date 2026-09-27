-- Migration 0565: Fix Honor Board Discipline Percentage - Include missing_checkout & on_leave
-- Problems found:
--   1. 'missing_checkout' (54 records) not counted as attendance - employee DID show up
--   2. 'on_leave' (approved leave) penalizes the employee - should subtract from expected days
--   3. Today not included in working days range but attendance for today IS counted
-- Fix: 
--   - Include 'missing_checkout' as valid attendance
--   - Subtract approved leave days from expected working days
--   - Include today in working days calculation

CREATE OR REPLACE FUNCTION public.get_honor_board(
  p_period text DEFAULT 'month',
  p_category text DEFAULT 'attendance'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_start_date date;
  v_end_date date;
  v_result jsonb;
BEGIN
  -- 1. Calculate evaluation window
  IF p_period = 'week' THEN
    v_start_date := (CURRENT_DATE - interval '7 days')::date;
    v_end_date := CURRENT_DATE;
  ELSE
    v_start_date := date_trunc('month', CURRENT_DATE)::date;
    v_end_date := LEAST(
      CURRENT_DATE,
      (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
    );
  END IF;

  -- 2. Category: Attendance & Punctuality
  IF p_category = 'attendance' THEN
    WITH working_days AS (
      -- Generate all dates in range INCLUDING today, exclude Fridays and official holidays
      SELECT d::date AS work_day
      FROM generate_series(v_start_date, v_end_date, interval '1 day') d
      WHERE extract(dow FROM d) != 5  -- Exclude Fridays (dow=5)
        AND NOT EXISTS (
          SELECT 1 FROM public.public_holidays h
          WHERE h.is_active 
            AND d::date BETWEEN h.holiday_date AND coalesce(h.end_date, h.holiday_date)
        )
    ),
    total_working AS (
      SELECT count(*) AS total_days FROM working_days
    ),
    att_stats AS (
      SELECT 
        e.id AS employee_id,
        e.full_name_ar,
        coalesce(d.name, 'الإدارة العامة') AS department,
        e.photo_url,
        -- Count days the employee actually showed up (present, attended, excused, mission, missing_checkout)
        count(ad.id) FILTER (WHERE ad.status IN ('present', 'attended', 'excused', 'mission', 'missing_checkout')) AS days_present,
        -- Count approved leave days (should not penalize attendance percentage)
        count(ad.id) FILTER (WHERE ad.status = 'on_leave') AS leave_days,
        coalesce(sum(ad.late_minutes) FILTER (WHERE ad.status IN ('present', 'attended', 'excused', 'mission', 'missing_checkout')), 0) AS late_minutes,
        coalesce(sum(ad.work_minutes) FILTER (WHERE ad.status IN ('present', 'attended', 'excused', 'mission', 'missing_checkout')), 0) AS work_minutes
      FROM public.employees e
      LEFT JOIN public.departments d ON e.department_id = d.id
      LEFT JOIN public.attendance_daily ad ON ad.employee_id = e.id 
        AND ad.work_date >= v_start_date 
        AND ad.work_date <= v_end_date
      WHERE e.is_active = true 
        AND e.is_deleted = false
        AND e.full_name_ar NOT LIKE '%تجريبي%'
        AND e.full_name_ar NOT LIKE '%اختبار%'
        AND NOT public.is_employee_executive(e.id)
      GROUP BY e.id, e.full_name_ar, d.name, e.photo_url
    ),
    ranked AS (
      SELECT 
        row_number() OVER (
          ORDER BY 
            -- Primary: attendance percentage = days_present / (total_days - leave_days)
            CASE 
              WHEN (tw.total_days - att.leave_days) > 0 
              THEN att.days_present::numeric / (tw.total_days - att.leave_days) 
              ELSE 0 
            END DESC,
            -- Secondary: more days present is better (tiebreaker)
            att.days_present DESC,
            -- Tertiary: less late minutes is better
            att.late_minutes ASC,
            -- Final: alphabetical
            att.full_name_ar ASC
        ) AS rank,
        att.full_name_ar AS name,
        att.department,
        att.photo_url,
        att.days_present,
        att.leave_days,
        att.late_minutes,
        tw.total_days,
        -- Expected days = total working days minus approved leave
        GREATEST(tw.total_days - att.leave_days, 1) AS expected_days,
        CASE 
          WHEN (tw.total_days - att.leave_days) > 0 
          THEN LEAST(round(att.days_present::numeric / (tw.total_days - att.leave_days) * 100), 100)
          ELSE 0
        END AS attendance_pct,
        CASE 
          WHEN att.days_present >= (tw.total_days - att.leave_days) AND att.late_minutes = 0 AND (tw.total_days - att.leave_days) > 0
            THEN 'حضور كامل ' || att.days_present || ' يوماً بدون أي تأخير'
          WHEN att.days_present >= (tw.total_days - att.leave_days) AND (tw.total_days - att.leave_days) > 0
            THEN 'حضور كامل ' || att.days_present || ' يوماً بالدوام الرسمي'
          WHEN att.days_present > 0 AND att.late_minutes = 0 
            THEN 'التزام تام ' || att.days_present || ' يوماً بالدوام الرسمي'
          WHEN att.days_present > 0 
            THEN 'حضور ' || att.days_present || ' يوماً من ' || (tw.total_days - att.leave_days) || ' يوم عمل'
          ELSE 'لم يسجل حضور بعد'
        END AS achievement
      FROM att_stats att
      CROSS JOIN total_working tw
      -- Only include employees who have at least 1 day of attendance
      WHERE att.days_present > 0
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', name,
        'department', department,
        'achievement', achievement,
        'metric', attendance_pct || '% انضباط',
        'photo_url', photo_url
      )
    )
    INTO v_result
    FROM (SELECT * FROM ranked ORDER BY rank ASC LIMIT 10) t;

  -- 3. Category: Field Missions
  ELSIF p_category = 'missions' THEN
    WITH mis_counts AS (
      SELECT employee_id, count(*) AS missions_count
      FROM public.missions
      WHERE start_at >= v_start_date 
        AND start_at <= (v_end_date + interval '1 day')
      GROUP BY employee_id
    ),
    att_counts AS (
      SELECT employee_id, count(*) AS days_count
      FROM public.attendance_daily
      WHERE work_date >= v_start_date 
        AND work_date <= v_end_date
        AND status IN ('present', 'attended', 'excused', 'mission', 'missing_checkout')
      GROUP BY employee_id
    ),
    ranked AS (
      SELECT 
        row_number() OVER (
          ORDER BY coalesce(mc.missions_count, 0) DESC, coalesce(ac.days_count, 0) DESC, e.full_name_ar ASC
        ) AS rank,
        e.full_name_ar AS name,
        coalesce(d.name, 'الإدارة العامة') AS department,
        e.photo_url,
        CASE 
          WHEN coalesce(mc.missions_count, 0) >= 5 THEN 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية'
          WHEN coalesce(mc.missions_count, 0) > 0 THEN 'إنجاز المأموريات الميدانية والمهام الخارجية بدقة'
          ELSE 'جاهزية واستعداد عالي للمهام والمأموريات'
        END AS achievement,
        CASE 
          WHEN coalesce(mc.missions_count, 0) > 0 THEN coalesce(mc.missions_count, 0) || ' مأموريات'
          ELSE coalesce(ac.days_count, 0) || ' يوم دوام'
        END AS metric
      FROM public.employees e
      LEFT JOIN public.departments d ON e.department_id = d.id
      LEFT JOIN mis_counts mc ON mc.employee_id = e.id
      LEFT JOIN att_counts ac ON ac.employee_id = e.id
      WHERE e.is_active = true 
        AND e.is_deleted = false
        AND e.full_name_ar NOT LIKE '%تجريبي%'
        AND e.full_name_ar NOT LIKE '%اختبار%'
        AND NOT public.is_employee_executive(e.id)
        AND (coalesce(mc.missions_count, 0) > 0 OR coalesce(ac.days_count, 0) > 0)
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', name,
        'department', department,
        'achievement', achievement,
        'metric', metric,
        'photo_url', photo_url
      )
    )
    INTO v_result
    FROM (SELECT * FROM ranked ORDER BY rank ASC LIMIT 10) t;

  -- 4. Category: Daily Reports
  ELSE
    WITH rep_period AS (
      SELECT employee_id, count(*) AS period_reports_count
      FROM public.daily_reports
      WHERE report_date >= v_start_date 
        AND report_date <= v_end_date
      GROUP BY employee_id
    ),
    rep_total AS (
      SELECT employee_id, count(*) AS total_reports_count
      FROM public.daily_reports
      GROUP BY employee_id
    ),
    att_counts AS (
      SELECT employee_id, count(*) AS days_count
      FROM public.attendance_daily
      WHERE work_date >= v_start_date 
        AND work_date <= v_end_date
        AND status IN ('present', 'attended', 'excused', 'mission', 'missing_checkout')
      GROUP BY employee_id
    ),
    ranked AS (
      SELECT 
        row_number() OVER (
          ORDER BY 
            coalesce(rp.period_reports_count, 0) DESC, 
            coalesce(rt.total_reports_count, 0) DESC, 
            coalesce(ac.days_count, 0) DESC, 
            e.full_name_ar ASC
        ) AS rank,
        e.full_name_ar AS name,
        coalesce(d.name, 'الإدارة العامة') AS department,
        e.photo_url,
        CASE 
          WHEN coalesce(rp.period_reports_count, 0) >= 4 THEN 'تسليم جميع التقارير اليومية في الموعد المحدد'
          WHEN coalesce(rp.period_reports_count, 0) > 0 THEN 'تسليم التقارير المعتمدة في الموعد بدقة'
          WHEN coalesce(rt.total_reports_count, 0) > 0 THEN 'توثيق شامل ومعتمد للأنشطة والمهام'
          ELSE 'متابعة دورية وتوثيق مستمر لمهام العمل'
        END AS achievement,
        CASE 
          WHEN coalesce(rp.period_reports_count, 0) > 0 THEN coalesce(rp.period_reports_count, 0) || ' تقارير'
          WHEN coalesce(rt.total_reports_count, 0) > 0 THEN coalesce(rt.total_reports_count, 0) || ' تقريراً'
          ELSE 'توثيق منتظم'
        END AS metric
      FROM public.employees e
      LEFT JOIN public.departments d ON e.department_id = d.id
      LEFT JOIN rep_period rp ON rp.employee_id = e.id
      LEFT JOIN rep_total rt ON rt.employee_id = e.id
      LEFT JOIN att_counts ac ON ac.employee_id = e.id
      WHERE e.is_active = true 
        AND e.is_deleted = false
        AND e.full_name_ar NOT LIKE '%تجريبي%'
        AND e.full_name_ar NOT LIKE '%اختبار%'
        AND NOT public.is_employee_executive(e.id)
        AND (coalesce(rp.period_reports_count, 0) > 0 OR coalesce(rt.total_reports_count, 0) > 0 OR coalesce(ac.days_count, 0) > 0)
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', name,
        'department', department,
        'achievement', achievement,
        'metric', metric,
        'photo_url', photo_url
      )
    )
    INTO v_result
    FROM (SELECT * FROM ranked ORDER BY rank ASC LIMIT 10) t;

  END IF;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_honor_board(text, text) TO authenticated, service_role, anon;
