-- Migration 0159: V23 Task-10 — Extended post types, author info in feed,
-- attendance today overview RPC, HR reports summary RPC
-- =================================================================

BEGIN;

-- ─── 1. Extended post types on announcements ───────────────────────
ALTER TABLE announcements
  ADD COLUMN IF NOT EXISTS post_type text NOT NULL DEFAULT 'announcement'
  CHECK (post_type IN ('announcement','alert','poll','meeting','holiday_notice','kpi_notice','attendance_notice'));

-- ─── 2. Recreate publish_official_announcement with 7 args ────────
DROP FUNCTION IF EXISTS publish_official_announcement(text, text, text, text, boolean, text);

CREATE OR REPLACE FUNCTION publish_official_announcement(
  p_title text,
  p_body text,
  p_category text,
  p_priority text,
  p_requires_acknowledgement boolean,
  p_banner_url text DEFAULT NULL,
  p_post_type text DEFAULT 'announcement'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT (
    has_permission(auth.uid(), 'comms.announcement.manage')
    OR current_is_full_access()
  ) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  INSERT INTO announcements (title, body, category, priority, requires_acknowledgement, image_url, post_type, status, created_by)
  VALUES (p_title, p_body, p_category, p_priority, p_requires_acknowledgement, p_banner_url, p_post_type, 'published', auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ─── 3. Update get_official_feed_admin to include author + postType ─
CREATE OR REPLACE FUNCTION get_official_feed_admin(p_limit int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    has_any_permission(auth.uid(), ARRAY['comms.announcement.read','comms.announcement.manage'])
    OR current_is_full_access()
  ) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(row_to_json(t) ORDER BY t."publishedAt" DESC NULLS LAST)
    FROM (
      -- announcements
      SELECT
        a.id,
        'announcement' AS kind,
        a.title,
        a.body,
        a.category,
        a.priority,
        a.status,
        a.requires_acknowledgement AS "requiresAcknowledgement",
        a.image_url AS "imageUrl",
        a.post_type AS "postType",
        a.created_at AS "publishedAt",
        COALESCE(
          (SELECT count(*)::int FROM announcement_acknowledgements aa WHERE aa.announcement_id = a.id),
          0
        ) AS "acknowledgedCount",
        CASE WHEN a.requires_acknowledgement THEN
          (SELECT count(*)::int FROM employees e2 WHERE e2.status = 'active')
        ELSE NULL END AS "targetCount",
        emp_a.full_name AS "authorName",
        emp_a.photo_url AS "authorPhotoUrl"
      FROM announcements a
      LEFT JOIN employees emp_a ON emp_a.user_id = a.created_by

      UNION ALL

      -- decisions
      SELECT
        d.id,
        'decision' AS kind,
        d.title,
        d.body,
        d.category,
        d.priority,
        d.status,
        d.requires_read_receipt AS "requiresAcknowledgement",
        NULL AS "imageUrl",
        'decision' AS "postType",
        d.published_at AS "publishedAt",
        COALESCE(
          (SELECT count(*)::int FROM decision_read_receipts rr WHERE rr.decision_id = d.id),
          0
        ) AS "acknowledgedCount",
        CASE WHEN d.requires_read_receipt THEN
          (SELECT count(*)::int FROM employees e3 WHERE e3.status = 'active')
        ELSE NULL END AS "targetCount",
        COALESCE(emp_d2.full_name, emp_d1.full_name) AS "authorName",
        COALESCE(emp_d2.photo_url, emp_d1.photo_url) AS "authorPhotoUrl"
      FROM administrative_decisions d
      LEFT JOIN employees emp_d1 ON emp_d1.user_id = d.created_by
      LEFT JOIN employees emp_d2 ON emp_d2.id = d.issued_by
    ) t
    LIMIT p_limit
  ), '[]'::jsonb);
END;
$$;

-- ─── 4. Attendance today overview RPC ──────────────────────────────
CREATE OR REPLACE FUNCTION get_attendance_today_overview(p_date date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
BEGIN
  IF NOT (
    has_any_permission(auth.uid(), ARRAY['attendance.record.read','people.employee.read'])
    OR current_is_full_access()
  ) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT count(*)::int INTO v_total_active
  FROM employees WHERE status = 'active';

  -- إجازات معتمدة تتقاطع مع اليوم
  SELECT count(*)::int INTO v_on_leave
  FROM leave_requests lr
  JOIN employees e ON e.id = lr.employee_id AND e.status = 'active'
  WHERE lr.status = 'approved'
    AND p_date BETWEEN lr.start_date AND lr.end_date;

  -- تكليفات تتقاطع مع اليوم
  SELECT count(*)::int INTO v_on_assignment
  FROM work_assignments wa
  JOIN employees e ON e.id = wa.employee_id AND e.status = 'active'
  WHERE wa.status = 'active'
    AND p_date BETWEEN wa.start_date AND COALESCE(wa.end_date, p_date);

  v_expected := v_total_active - v_on_leave - v_on_assignment;

  -- حاضرون اليوم (لديهم check_in)
  SELECT count(DISTINCT ar.employee_id)::int INTO v_present
  FROM attendance_records ar
  JOIN employees e ON e.id = ar.employee_id AND e.status = 'active'
  WHERE ar.date = p_date AND ar.check_in IS NOT NULL;

  -- متأخرون (check_in بعد الساعة المتوقعة — نقدّرها 08:30)
  SELECT count(DISTINCT ar.employee_id)::int INTO v_late
  FROM attendance_records ar
  JOIN employees e ON e.id = ar.employee_id AND e.status = 'active'
  WHERE ar.date = p_date
    AND ar.check_in IS NOT NULL
    AND ar.check_in::time > '08:30:00';

  v_not_checked_in := GREATEST(0, v_expected - v_present);
  v_absent := GREATEST(0, v_not_checked_in); -- الغياب = لم يسجّل (مبدئيًا)

  RETURN jsonb_build_object(
    'date', p_date,
    'totalActive', v_total_active,
    'expected', v_expected,
    'present', v_present,
    'late', v_late,
    'notCheckedIn', v_not_checked_in,
    'onLeave', v_on_leave,
    'onAssignment', v_on_assignment,
    'absent', v_absent,
    'lastUpdatedAt', now()
  );
END;
$$;

-- ─── 5. HR reports summary RPC ─────────────────────────────────────
CREATE OR REPLACE FUNCTION get_hr_reports_summary()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_att jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
BEGIN
  IF NOT (
    has_any_permission(auth.uid(), ARRAY['reports.people.read','attendance.record.read'])
    OR current_is_full_access()
  ) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  -- الحضور
  SELECT jsonb_build_object(
    'totalEvents', count(*)::int,
    'checkIns', count(*) FILTER (WHERE date = CURRENT_DATE AND check_in IS NOT NULL)::int,
    'checkOuts', count(*) FILTER (WHERE date = CURRENT_DATE AND check_out IS NOT NULL)::int,
    'pendingReview', count(*) FILTER (WHERE status = 'pending_review')::int,
    'thisMonth', count(*) FILTER (WHERE date >= date_trunc('month', CURRENT_DATE))::int
  ) INTO v_att FROM attendance_records;

  -- الإجازات
  SELECT jsonb_build_object(
    'totalRequests', count(*)::int,
    'approved', count(*) FILTER (WHERE status = 'approved')::int,
    'pending', count(*) FILTER (WHERE status = 'pending')::int,
    'rejected', count(*) FILTER (WHERE status = 'rejected')::int,
    'activeNow', count(*) FILTER (WHERE status = 'approved' AND CURRENT_DATE BETWEEN start_date AND end_date)::int
  ) INTO v_leaves FROM leave_requests;

  -- التكليفات
  SELECT jsonb_build_object(
    'total', count(*)::int,
    'active', count(*) FILTER (WHERE status = 'active')::int,
    'completed', count(*) FILTER (WHERE status = 'completed')::int,
    'pending', count(*) FILTER (WHERE status = 'pending')::int
  ) INTO v_assignments FROM work_assignments;

  -- الأداء
  SELECT jsonb_build_object(
    'activeCycles', (SELECT count(*)::int FROM kpi_cycles WHERE status = 'active'),
    'totalEvaluations', count(*)::int,
    'pendingEvaluations', count(*) FILTER (WHERE status IN ('pending','draft'))::int,
    'completedEvaluations', count(*) FILTER (WHERE status IN ('completed','approved'))::int
  ) INTO v_kpi FROM kpi_evaluations;

  -- النزاعات
  SELECT jsonb_build_object(
    'total', count(*)::int,
    'open', count(*) FILTER (WHERE status IN ('open','in_progress','under_review'))::int,
    'resolved', count(*) FILTER (WHERE status = 'resolved')::int,
    'escalated', count(*) FILTER (WHERE status = 'escalated')::int
  ) INTO v_disputes FROM disputes;

  -- الموقع
  SELECT jsonb_build_object(
    'totalRequests', count(*)::int,
    'pending', count(*) FILTER (WHERE status = 'pending')::int,
    'responded', count(*) FILTER (WHERE status IN ('responded','completed'))::int
  ) INTO v_location FROM location_requests;

  RETURN jsonb_build_object(
    'attendance', v_att,
    'leaves', v_leaves,
    'assignments', v_assignments,
    'kpi', v_kpi,
    'disputes', v_disputes,
    'location', v_location,
    'generatedAt', now()
  );
END;
$$;

COMMIT;
