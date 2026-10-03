-- 0602_fix_mobile_action_targets_and_defaults.sql
-- إصلاح شامل لتحليل مسارات الإجراءات والإشعارات في الموبايل:
-- 1) دعم معرّف 'default' أو المعرّفات غير الـ UUID لجميع الشاشات العامة (instant_penalty, fellowship_fund, attendance, daily_report, device, request, notification)
-- 2) إضافة دعم association_project و notification إلى resolve_mobile_action_target و get_mobile_action_target
-- 3) دعم أسماء الكيانات الإضافية (mission, leave, permission, urgent_exec, projects)

CREATE OR REPLACE FUNCTION public.get_mobile_action_target(p_action_id text, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_uuid uuid;
  v_norm_kind text := lower(trim(coalesce(p_kind, '')));
  v_prefix text;
  v_raw_id text;
  v_allowed boolean := false;
BEGIN
  IF p_action_id IS NULL OR p_kind IS NULL THEN
    RETURN jsonb_build_object('kind', coalesce(p_kind, ''), 'recordId', '', 'mobileRoute', 'unsupported');
  END IF;

  -- تطبيع نوع الإجراء
  v_norm_kind := CASE v_norm_kind
    WHEN 'requests' THEN 'request'
    WHEN 'request_decision' THEN 'request'
    WHEN 'mission' THEN 'request'
    WHEN 'leave' THEN 'request'
    WHEN 'permission' THEN 'request'
    WHEN 'urgent_exec' THEN 'request'
    WHEN 'kpi_evaluation' THEN 'kpi'
    WHEN 'attendance_corrections' THEN 'attendance_correction'
    WHEN 'attendance_daily' THEN 'attendance'
    WHEN 'attendance_event' THEN 'attendance'
    WHEN 'attendance_alert' THEN 'attendance'
    WHEN 'punch_reminder' THEN 'attendance'
    WHEN 'instant_penalties' THEN 'instant_penalty'
    WHEN 'penalty' THEN 'instant_penalty'
    WHEN 'fellowship' THEN 'fellowship_fund'
    WHEN 'daily_reports' THEN 'daily_report'
    WHEN 'devices' THEN 'device'
    WHEN 'employee_device' THEN 'device'
    WHEN 'tasks' THEN 'task'
    WHEN 'announcements' THEN 'announcement'
    WHEN 'decisions' THEN 'decision'
    WHEN 'dispute_case' THEN 'dispute'
    WHEN 'association_projects' THEN 'association_project'
    WHEN 'projects' THEN 'association_project'
    WHEN 'project' THEN 'association_project'
    WHEN 'notifications' THEN 'notification'
    ELSE v_norm_kind
  END;

  v_prefix := v_norm_kind || '-';
  IF position(v_prefix in lower(p_action_id)) = 1 THEN
    v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  ELSE
    v_raw_id := p_action_id;
  END IF;

  v_raw_id := trim(coalesce(v_raw_id, ''));

  -- معالجة 'default' أو المعرّفات الفارغة/العامة
  IF v_raw_id = '' OR v_raw_id = 'default' THEN
    RETURN CASE v_norm_kind
      WHEN 'instant_penalty' THEN jsonb_build_object('kind', 'instant_penalty', 'recordId', 'default', 'mobileRoute', 'instant_penalty')
      WHEN 'fellowship_fund' THEN jsonb_build_object('kind', 'fellowship_fund', 'recordId', 'default', 'mobileRoute', 'instant_penalty')
      WHEN 'daily_report' THEN jsonb_build_object('kind', 'daily_report', 'recordId', 'default', 'mobileRoute', 'daily_report')
      WHEN 'device' THEN jsonb_build_object('kind', 'device', 'recordId', 'default', 'mobileRoute', 'device')
      WHEN 'attendance' THEN jsonb_build_object('kind', 'attendance', 'recordId', 'default', 'mobileRoute', 'attendance_detail')
      WHEN 'request' THEN jsonb_build_object('kind', 'request', 'recordId', 'default', 'mobileRoute', 'requests')
      WHEN 'task' THEN jsonb_build_object('kind', 'task', 'recordId', 'default', 'mobileRoute', 'task_detail')
      WHEN 'notification' THEN jsonb_build_object('kind', 'notification', 'recordId', 'default', 'mobileRoute', 'notifications')
      WHEN 'association_project' THEN jsonb_build_object('kind', 'association_project', 'recordId', 'default', 'mobileRoute', 'notifications')
      ELSE jsonb_build_object('kind', v_norm_kind, 'recordId', v_raw_id, 'mobileRoute', 'unsupported')
    END;
  END IF;

  BEGIN
    v_uuid := v_raw_id::uuid;
  EXCEPTION WHEN others THEN
    -- معرّف ليس UUID (مثل تاريخ الحضور 2026-10-03)
    IF v_norm_kind = 'attendance' THEN
      RETURN jsonb_build_object('kind', 'attendance', 'recordId', v_raw_id, 'mobileRoute', 'attendance_detail');
    END IF;
    IF v_norm_kind = 'instant_penalty' THEN
      RETURN jsonb_build_object('kind', 'instant_penalty', 'recordId', v_raw_id, 'mobileRoute', 'instant_penalty');
    END IF;
    IF v_norm_kind = 'notification' THEN
      RETURN jsonb_build_object('kind', 'notification', 'recordId', v_raw_id, 'mobileRoute', 'notifications');
    END IF;
    RETURN jsonb_build_object('kind', v_norm_kind, 'recordId', v_raw_id, 'mobileRoute', 'unsupported');
  END;

  CASE v_norm_kind
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

    WHEN 'attendance_correction' THEN
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

    WHEN 'instant_penalty' THEN
      RETURN jsonb_build_object('kind','instant_penalty','recordId',v_uuid,'mobileRoute','instant_penalty');

    WHEN 'daily_report' THEN
      RETURN jsonb_build_object('kind','daily_report','recordId',v_uuid,'mobileRoute','daily_report');

    WHEN 'device' THEN
      RETURN jsonb_build_object('kind','device','recordId',v_uuid,'mobileRoute','device');

    WHEN 'fellowship_fund' THEN
      RETURN jsonb_build_object('kind','fellowship_fund','recordId',v_uuid,'mobileRoute','instant_penalty');

    WHEN 'association_project' THEN
      RETURN jsonb_build_object('kind','association_project','recordId',v_uuid,'mobileRoute','association_project');

    WHEN 'notification' THEN
      RETURN jsonb_build_object('kind','notification','recordId',v_uuid,'mobileRoute','notifications');

    ELSE
      RETURN jsonb_build_object('kind', v_norm_kind, 'recordId', v_uuid, 'mobileRoute', 'unsupported');
  END CASE;
END;
$function$;

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
    WHEN 'mission' THEN 'request'
    WHEN 'leave' THEN 'request'
    WHEN 'permission' THEN 'request'
    WHEN 'urgent_exec' THEN 'request'
    WHEN 'kpi' THEN 'kpi'
    WHEN 'kpi_evaluation' THEN 'kpi'
    WHEN 'decision' THEN 'decision'
    WHEN 'decisions' THEN 'decision'
    WHEN 'dispute' THEN 'dispute'
    WHEN 'dispute_case' THEN 'dispute'
    WHEN 'disputes' THEN 'dispute'
    WHEN 'task' THEN 'task'
    WHEN 'tasks' THEN 'task'
    WHEN 'announcement' THEN 'announcement'
    WHEN 'announcements' THEN 'announcement'
    WHEN 'recognition' THEN 'recognition'
    WHEN 'instant_penalty' THEN 'instant_penalty'
    WHEN 'instant_penalty_doubled' THEN 'instant_penalty'
    WHEN 'instant_penalty_suspended' THEN 'instant_penalty'
    WHEN 'instant_penalty_reinstated' THEN 'instant_penalty'
    WHEN 'instant_penalty_lifted' THEN 'instant_penalty'
    WHEN 'instant_penalty_paid' THEN 'instant_penalty'
    WHEN 'instant_penalty_cancelled' THEN 'instant_penalty'
    WHEN 'instant_penalty_excuse_approved' THEN 'instant_penalty'
    WHEN 'penalty' THEN 'instant_penalty'
    WHEN 'instant_penalties' THEN 'instant_penalty'
    WHEN 'daily_report' THEN 'daily_report'
    WHEN 'daily_reports' THEN 'daily_report'
    WHEN 'daily_report_like' THEN 'daily_report'
    WHEN 'daily_report_comment' THEN 'daily_report'
    WHEN 'device' THEN 'device'
    WHEN 'employee_device' THEN 'device'
    WHEN 'devices' THEN 'device'
    WHEN 'fellowship_fund' THEN 'fellowship_fund'
    WHEN 'fellowship' THEN 'fellowship_fund'
    WHEN 'association_project' THEN 'association_project'
    WHEN 'association_projects' THEN 'association_project'
    WHEN 'project' THEN 'association_project'
    WHEN 'projects' THEN 'association_project'
    WHEN 'notification' THEN 'notification'
    WHEN 'notifications' THEN 'notification'
    ELSE NULL
  END;

  IF v_resolved_kind IS NULL THEN
    RETURN jsonb_build_object('kind', v_kind, 'recordId', coalesce(v_raw, ''), 'mobileRoute', 'unsupported');
  END IF;

  -- strip prefix إن وُجد (kind-uuid)
  IF position(v_resolved_kind || '-' in lower(v_raw)) = 1 THEN
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  END IF;

  -- معالجة الحالات الافتراضية
  IF v_raw = '' OR v_raw = 'default' THEN
    RETURN CASE v_resolved_kind
      WHEN 'instant_penalty' THEN jsonb_build_object('kind', 'instant_penalty', 'recordId', 'default', 'mobileRoute', 'instant_penalty')
      WHEN 'fellowship_fund' THEN jsonb_build_object('kind', 'fellowship_fund', 'recordId', 'default', 'mobileRoute', 'instant_penalty')
      WHEN 'daily_report' THEN jsonb_build_object('kind', 'daily_report', 'recordId', 'default', 'mobileRoute', 'daily_report')
      WHEN 'device' THEN jsonb_build_object('kind', 'device', 'recordId', 'default', 'mobileRoute', 'device')
      WHEN 'attendance' THEN jsonb_build_object('kind', 'attendance', 'recordId', 'default', 'mobileRoute', 'attendance_detail')
      WHEN 'request' THEN jsonb_build_object('kind', 'request', 'recordId', 'default', 'mobileRoute', 'requests')
      WHEN 'task' THEN jsonb_build_object('kind', 'task', 'recordId', 'default', 'mobileRoute', 'task_detail')
      WHEN 'notification' THEN jsonb_build_object('kind', 'notification', 'recordId', 'default', 'mobileRoute', 'notifications')
      WHEN 'association_project' THEN jsonb_build_object('kind', 'association_project', 'recordId', 'default', 'mobileRoute', 'notifications')
      ELSE jsonb_build_object('kind', v_resolved_kind, 'recordId', v_raw, 'mobileRoute', 'unsupported')
    END;
  END IF;

  BEGIN
    v_uuid := v_raw::uuid;
  EXCEPTION WHEN others THEN
    IF v_resolved_kind = 'attendance' THEN
      RETURN jsonb_build_object('kind', 'attendance', 'recordId', v_raw, 'mobileRoute', 'attendance_detail');
    END IF;
    IF v_resolved_kind = 'instant_penalty' THEN
      RETURN jsonb_build_object('kind', 'instant_penalty', 'recordId', v_raw, 'mobileRoute', 'instant_penalty');
    END IF;
    IF v_resolved_kind = 'notification' THEN
      RETURN jsonb_build_object('kind', 'notification', 'recordId', v_raw, 'mobileRoute', 'notifications');
    END IF;
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

  IF v_resolved_kind = 'association_project' THEN
    RETURN jsonb_build_object(
      'kind', 'association_project',
      'recordId', v_uuid,
      'mobileRoute', 'association_project'
    );
  END IF;

  IF v_resolved_kind = 'notification' THEN
    RETURN jsonb_build_object(
      'kind', 'notification',
      'recordId', v_uuid,
      'mobileRoute', 'notifications'
    );
  END IF;

  RETURN public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_mobile_action_target(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_mobile_action_target(text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_mobile_action_target(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_mobile_action_target(text, text) TO authenticated;
