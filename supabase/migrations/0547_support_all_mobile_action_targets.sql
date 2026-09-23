-- 0547: دعم توجيه كافة إجراءات وإشعارات الموبايل وإلغاء الاستثناءات المسببة لتعليق الشاشة
-- الهدف:
-- 1) إضافة دعم instant_penalty, daily_report, device, fellowship_fund إلى get_mobile_action_target و resolve_mobile_action_target
-- 2) استبدال رمي الأخطاء الحادة (22023) بكائن jsonb آمن mobileRoute='unsupported' يمنع تجميد الموبايل على شاشة «جاري فتح الإشعار...»

BEGIN;

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
  IF p_action_id IS NULL OR p_kind IS NULL THEN
    RETURN jsonb_build_object('kind', coalesce(p_kind, ''), 'recordId', '', 'mobileRoute', 'unsupported');
  END IF;

  IF position(v_prefix in lower(p_action_id)) = 1 THEN
    v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  ELSE
    v_raw_id := p_action_id;
  END IF;

  BEGIN
    v_uuid := v_raw_id::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('kind', lower(p_kind), 'recordId', coalesce(v_raw_id, ''), 'mobileRoute', 'unsupported');
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

    WHEN 'instant_penalty', 'penalty' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.instant_attendance_penalties p
        WHERE p.id = v_uuid AND (
          p.employee_id = public.current_employee_id()
          OR public.current_is_full_access()
          OR public.has_any_permission(ARRAY['penalties.read', 'penalties.manage', 'penalties.admin'])
        )
      ) INTO v_allowed;
      RETURN jsonb_build_object('kind','instant_penalty','recordId',v_uuid,'mobileRoute','instant_penalty');

    WHEN 'daily_report', 'daily_reports' THEN
      RETURN jsonb_build_object('kind','daily_report','recordId',v_uuid,'mobileRoute','daily_report');

    WHEN 'device', 'devices', 'employee_device' THEN
      RETURN jsonb_build_object('kind','device','recordId',v_uuid,'mobileRoute','device');

    WHEN 'fellowship_fund', 'fellowship' THEN
      RETURN jsonb_build_object('kind','fellowship_fund','recordId',v_uuid,'mobileRoute','instant_penalty');

    ELSE
      RETURN jsonb_build_object('kind', lower(p_kind), 'recordId', v_uuid, 'mobileRoute', 'unsupported');
  END CASE;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_mobile_action_target(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_mobile_action_target(text, text) TO authenticated;

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
    WHEN 'instant_penalty' THEN 'instant_penalty'
    WHEN 'instant_penalty_doubled' THEN 'instant_penalty'
    WHEN 'instant_penalty_suspended' THEN 'instant_penalty'
    WHEN 'instant_penalty_reinstated' THEN 'instant_penalty'
    WHEN 'instant_penalty_lifted' THEN 'instant_penalty'
    WHEN 'instant_penalty_paid' THEN 'instant_penalty'
    WHEN 'instant_penalty_cancelled' THEN 'instant_penalty'
    WHEN 'daily_report' THEN 'daily_report'
    WHEN 'daily_reports' THEN 'daily_report'
    WHEN 'device' THEN 'device'
    WHEN 'employee_device' THEN 'device'
    WHEN 'devices' THEN 'device'
    WHEN 'fellowship_fund' THEN 'fellowship_fund'
    WHEN 'fellowship' THEN 'fellowship_fund'
    ELSE NULL
  END;

  IF v_resolved_kind IS NULL THEN
    RETURN jsonb_build_object('kind', v_kind, 'recordId', coalesce(v_raw, ''), 'mobileRoute', 'unsupported');
  END IF;

  -- strip prefix إن وُجد (kind-uuid)
  IF position(v_resolved_kind || '-' in lower(v_raw)) = 1 THEN
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  END IF;

  BEGIN
    v_uuid := v_raw::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('kind', v_resolved_kind, 'recordId', coalesce(v_raw, ''), 'mobileRoute', 'unsupported');
  END;

  IF v_resolved_kind = 'live_location_request' THEN
    SELECT * INTO v_req FROM public.live_location_requests WHERE id = v_uuid;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('kind', v_resolved_kind, 'recordId', v_uuid, 'mobileRoute', 'unsupported');
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
