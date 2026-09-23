-- 0544: دعم شاشة تفاصيل تصحيح البصمة وإدارة طلبات الحضور للفريق وتوجيه الإشعارات
-- ═══════════════════════════════════════════════════════════════════════════════════
-- 1) تفاصيل طلب تصحيح البصمة مع التحقق من الصلاحيات وتقرير إمكانية القرار للمستخدم الحالي.
-- 2) قائمة تصحيحات البصمة للفريق (طلبات الحضور والانصراف المعلقة والمراجعة).
-- 3) توجيه إشعارات تصحيح البصمة إلى attendance_correction_detail بدلاً من attendance_detail.

BEGIN;

-- 1) دالة جلب تفاصيل تصحيح البصمة
CREATE OR REPLACE FUNCTION public.get_attendance_correction_detail(p_correction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec record;
BEGIN
  SELECT
    c.id,
    c.employee_id AS "employeeId",
    e.full_name_ar AS "employeeName",
    e.employee_code AS "employeeCode",
    jt.name AS "jobTitle",
    e.branch_id AS "branchId",
    c.work_date AS "workDate",
    c.correction_type AS "type",
    c.requested_check_in AS "requestedCheckIn",
    c.requested_check_out AS "requestedCheckOut",
    c.requested_status AS "requestedStatus",
    c.reason,
    c.attachment_path AS "attachmentPath",
    c.status,
    c.reviewed_by AS "reviewedBy",
    rev.full_name_ar AS "reviewerName",
    c.reviewed_at AS "reviewedAt",
    c.review_note AS "reviewNote",
    c.created_at AS "createdAt",
    (
      c.status = 'pending'
      AND (
        public.current_is_full_access()
        OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
        OR EXISTS (
          SELECT 1 FROM public.manager_relations mr
          WHERE mr.employee_id = c.employee_id
            AND mr.manager_employee_id = public.current_employee_id()
            AND mr.relation_type = 'primary'
            AND mr.effective_from <= current_date
            AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
        )
      )
    ) AS "canDecide"
  INTO v_rec
  FROM public.attendance_corrections c
  JOIN public.employees e ON e.id = c.employee_id
  LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
  LEFT JOIN public.employees rev ON rev.id = c.reviewed_by
  WHERE c.id = p_correction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'طلب التصحيح غير موجود' USING errcode = 'P0002';
  END IF;

  -- فحص الصلاحية: صاحب الطلب أو المدير أو من يملك صلاحية المراجعة أو وصول كامل
  IF NOT (
    v_rec."employeeId" = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.can_access_employee(v_rec."employeeId", 'attendance.correction.review')
    OR EXISTS (
      SELECT 1 FROM public.manager_relations mr
      WHERE mr.employee_id = v_rec."employeeId"
        AND mr.manager_employee_id = public.current_employee_id()
        AND mr.relation_type = 'primary'
        AND mr.effective_from <= current_date
        AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
    )
    OR public.has_any_permission(ARRAY['attendance.read', 'attendance.review', 'attendance.manage', 'requests.read'])
  ) THEN
    RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode = '42501';
  END IF;

  RETURN to_jsonb(v_rec);
END;
$$;

REVOKE ALL ON FUNCTION public.get_attendance_correction_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_attendance_correction_detail(uuid) TO authenticated;

-- 2) دالة جلب تصحيحات البصمة للفريق
CREATE OR REPLACE FUNCTION public.get_team_attendance_corrections(
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', e.full_name_ar,
        'employeeCode', e.employee_code,
        'jobTitle', jt.name,
        'workDate', c.work_date,
        'type', c.correction_type,
        'requestedCheckIn', c.requested_check_in,
        'requestedCheckOut', c.requested_check_out,
        'requestedStatus', c.requested_status,
        'reason', c.reason,
        'attachmentPath', c.attachment_path,
        'status', c.status,
        'reviewedBy', c.reviewed_by,
        'reviewedAt', c.reviewed_at,
        'reviewNote', c.review_note,
        'createdAt', c.created_at,
        'canDecide', (
          c.status = 'pending'
          AND (
            public.current_is_full_access()
            OR public.current_has_active_role(ARRAY['admin', 'super-admin', 'general-manager', 'hr-manager'])
            OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
            OR EXISTS (
              SELECT 1 FROM public.manager_relations mr
              WHERE mr.employee_id = c.employee_id
                AND mr.manager_employee_id = public.current_employee_id()
                AND mr.relation_type = 'primary'
                AND mr.effective_from <= current_date
                AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
            )
          )
        )
      ) ORDER BY c.created_at DESC
    )
    FROM public.attendance_corrections c
    JOIN public.employees e ON e.id = c.employee_id
    LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
    WHERE (p_status IS NULL OR c.status = p_status)
      AND (
        public.current_is_full_access()
        OR public.current_has_active_role(ARRAY['admin', 'super-admin', 'executive', 'general-manager', 'hr-manager', 'operations-manager'])
        OR public.has_any_permission(ARRAY['attendance.read', 'attendance.review', 'attendance.manage', 'attendance.admin', 'attendance.correction.review', 'requests.request.approve'])
        OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
        OR EXISTS (
          SELECT 1 FROM public.manager_relations mr
          WHERE mr.employee_id = c.employee_id
            AND mr.manager_employee_id = public.current_employee_id()
            AND mr.relation_type = 'primary'
            AND mr.effective_from <= current_date
            AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
        )
      )
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_team_attendance_corrections(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_team_attendance_corrections(text, integer) TO authenticated;

-- 3) تحديث get_mobile_action_target لدعم توجيه تصحيحات البصمة إلى attendance_correction_detail
CREATE OR REPLACE FUNCTION public.get_mobile_action_target(p_action_id text, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
BEGIN
  IF p_action_id IS NULL OR p_kind IS NULL OR position(v_prefix in lower(p_action_id)) <> 1 THEN
    RAISE EXCEPTION 'معرّف إجراء غير صالح' USING errcode = '22023';
  END IF;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  BEGIN
    v_uuid := v_raw_id::uuid;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'معرّف إجراء غير صالح' USING errcode = '22023';
  END;

  CASE lower(p_kind)
    WHEN 'request' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.requests r
        WHERE r.id = v_uuid
          AND (
            r.employee_id = public.current_employee_id()
            OR public.current_is_full_access()
            OR public.can_access_employee(r.employee_id, 'requests.request.approve')
            OR public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    WHEN 'kpi' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.kpi_evaluations k
        WHERE k.id = v_uuid
          AND (
            k.employee_id = public.current_employee_id()
            OR public.current_is_full_access()
            OR public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            OR public.has_any_permission(ARRAY[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    WHEN 'decision' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.administrative_decisions d
        WHERE d.id = v_uuid and d.status = 'published'
          AND (
            public.current_is_full_access()
            OR public.has_any_permission(ARRAY['comms.decision.read','comms.decision.manage'])
            OR EXISTS (
              SELECT 1 FROM public.decision_recipients dr
              WHERE dr.decision_id=d.id AND dr.employee_id=public.current_employee_id()
            )
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    -- تصحيح البصمة مباشرة
    WHEN 'attendance_correction', 'attendance_corrections' THEN
      SELECT (
        EXISTS(SELECT 1 FROM public.attendance_corrections c WHERE c.id = v_uuid AND c.employee_id = public.current_employee_id())
        OR public.current_is_full_access()
        OR EXISTS(
          SELECT 1 FROM public.attendance_corrections c
          WHERE c.id = v_uuid
            AND (
              public.can_access_employee(c.employee_id, 'attendance.correction.review')
              OR EXISTS (
                SELECT 1 FROM public.manager_relations mr
                WHERE mr.employee_id = c.employee_id
                  AND mr.manager_employee_id = public.current_employee_id()
                  AND mr.relation_type = 'primary'
                  AND mr.effective_from <= current_date
                  AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
              )
            )
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','attendance_correction','recordId',v_uuid,'mobileRoute','attendance_correction_detail');

    -- حضور/بصمة: إذا كان تصحيح حضور نوجّهه إلى شاشة التصحيح، وإلا شاشة الحضور
    WHEN 'attendance' THEN
      IF EXISTS(SELECT 1 FROM public.attendance_corrections c WHERE c.id = v_uuid) THEN
        RETURN jsonb_build_object('kind','attendance_correction','recordId',v_uuid,'mobileRoute','attendance_correction_detail');
      END IF;

      SELECT (
        EXISTS(SELECT 1 FROM public.attendance_events e
               WHERE e.id = v_uuid AND e.employee_id = public.current_employee_id())
        OR EXISTS(SELECT 1 FROM public.attendance_punch_attempts pa
                  WHERE pa.attendance_event_id = v_uuid AND pa.employee_id = public.current_employee_id())
        OR public.current_is_full_access()
        OR public.has_any_permission(ARRAY[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) INTO v_allowed;
      IF NOT v_allowed THEN
        RETURN jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      END IF;
      RETURN jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    WHEN 'dispute' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.dispute_cases dc
        WHERE dc.id = v_uuid AND (
          dc.actor_employee_id = public.current_employee_id()
          OR dc.respondent_employee_id = public.current_employee_id()
          OR public.current_is_full_access()
          OR public.can_access_dispute(dc.id)
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    WHEN 'task' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.tasks t
        WHERE t.id = v_uuid AND (
          t.assignee_employee_id = public.current_employee_id()
          OR t.created_by = auth.uid()
          OR public.current_is_full_access()
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    WHEN 'announcement' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.announcements a
        WHERE a.id = v_uuid AND a.status = 'published'
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    WHEN 'recognition' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.recognitions r
        WHERE r.id = v_uuid AND (
          r.recipient_employee_id = public.current_employee_id()
          OR public.current_is_full_access()
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    ELSE
      RAISE EXCEPTION 'نوع الإجراء غير مدعوم' USING errcode = '22023';
  END CASE;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_mobile_action_target(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_mobile_action_target(text, text) TO authenticated;

-- 4) تحديث resolve_mobile_action_target
CREATE OR REPLACE FUNCTION public.resolve_mobile_action_target(p_action_id text, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
  v_resolved_kind text;
BEGIN
  v_resolved_kind := CASE v_kind
    WHEN 'location' THEN 'live_location_request'
    WHEN 'location_request' THEN 'live_location_request'
    WHEN 'live_location_request' THEN 'live_location_request'
    WHEN 'live_location' THEN 'live_location_request'
    WHEN 'live_location_requests' THEN 'live_location_request'
    WHEN 'attendance_alert' THEN 'attendance'
    WHEN 'punch_reminder' THEN 'attendance'
    WHEN 'attendance_daily' THEN 'attendance'
    WHEN 'attendance_event' THEN 'attendance'
    WHEN 'attendance_corrections' THEN 'attendance_correction'
    WHEN 'attendance_correction' THEN 'attendance_correction'
    WHEN 'attendance' THEN 'attendance'
    WHEN 'overtime_records' THEN 'attendance'
    WHEN 'work_rosters' THEN 'attendance'
    WHEN 'request' THEN 'request'
    WHEN 'requests' THEN 'request'
    WHEN 'request_decision' THEN 'request'
    WHEN 'kpi' THEN 'kpi'
    WHEN 'kpi_evaluation' THEN 'kpi'
    WHEN 'decision' THEN 'decision'
    WHEN 'dispute' THEN 'dispute'
    WHEN 'dispute_case' THEN 'dispute'
    WHEN 'task' THEN 'task'
    WHEN 'announcement' THEN 'announcement'
    WHEN 'recognition' THEN 'recognition'
    ELSE NULL
  END;

  IF v_resolved_kind IS NULL THEN
    RAISE EXCEPTION 'نوع الإجراء غير مدعوم' USING errcode = '22023';
  END IF;

  -- strip prefix إن وُجد (kind-uuid)
  IF position(v_resolved_kind || '-' in lower(v_raw)) = 1 THEN
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  END IF;

  BEGIN
    v_uuid := v_raw::uuid;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'معرّف إجراء غير صالح' USING errcode = '22023';
  END;

  IF v_resolved_kind = 'live_location_request' THEN
    SELECT * INTO v_req FROM public.live_location_requests WHERE id = v_uuid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'هدف الإجراء غير موجود' USING errcode = 'P0002';
    END IF;
    IF NOT (
      v_req.employee_id = public.current_employee_id()
      OR v_req.requested_by = public.current_employee_id()
      OR public.current_is_full_access()
      OR public.can_access_employee(v_req.employee_id, 'live_location.view_response')
    ) THEN
      RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode = '42501';
    END IF;

    RETURN jsonb_build_object(
      'kind', v_resolved_kind,
      'recordId', v_uuid,
      'mobileRoute', 'live_location_request'
    );
  END IF;

  RETURN public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
END;
$function$;

REVOKE ALL ON FUNCTION public.resolve_mobile_action_target(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_mobile_action_target(text, text) TO authenticated;

COMMIT;
