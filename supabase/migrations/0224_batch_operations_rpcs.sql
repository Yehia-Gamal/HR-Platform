-- 0224: عمليات دُفعية — قرار جماعي على الطلبات + قراءة إشعارات جماعية
-- يعتمد على: 0006 (requests)، 0008 (notifications)، 0011 (audit_events / log_audit_event)
-- =====================================================================

BEGIN;

-- =====================================================================
-- 1) batch_decide_requests — موافقة/رفض دُفعي على عدة طلبات
-- =====================================================================
-- يُحدّث فقط الطلبات بحالة 'pending'. يتخطّى المُنتهية أو المُقرَّرة سابقاً.
-- لا يمرّ عبر مسار الخطوات (workflow_steps) — مخصَّص للعمليات الإدارية السريعة.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.batch_decide_requests(
  p_request_ids  uuid[],
  p_decision     text,       -- 'approved' أو 'rejected'
  p_comment      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count       int := 0;
  v_skipped     int := 0;
  v_id          uuid;
  v_user_id     uuid := auth.uid();
  v_employee_id uuid := public.current_employee_id();
  v_total       int  := coalesce(array_length(p_request_ids, 1), 0);
BEGIN
  -- ── التحقق من الهوية ──
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
  END IF;
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NO_EMPLOYEE_LINKED';
  END IF;

  -- ── التحقق من الصلاحية: full-access أو صلاحية الموافقة على الطلبات ──
  IF NOT public.current_is_full_access()
     AND NOT public.has_any_permission(ARRAY[
       'requests.request.approve',
       'requests.request.override'
     ])
  THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN';
  END IF;

  -- ── التحقق من القرار ──
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'ERR_INVALID_DECISION: يجب أن يكون approved أو rejected';
  END IF;

  -- ── التحقق من وجود طلبات ──
  IF v_total = 0 THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 0, 'total', 0);
  END IF;

  -- ── التحقق من وجود جدول requests ──
  IF to_regclass('public.requests') IS NULL THEN
    RAISE EXCEPTION 'ERR_TABLE_NOT_FOUND: requests';
  END IF;

  -- ── معالجة كل طلب ──
  FOREACH v_id IN ARRAY p_request_ids LOOP
    -- تخطّي الموافقة الذاتية
    IF EXISTS (
      SELECT 1 FROM public.requests
      WHERE id = v_id AND employee_id = v_employee_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE public.requests SET
      status       = p_decision,
      decided_by   = v_employee_id,
      decided_at   = now(),
      updated_at   = now()
    WHERE id = v_id
      AND status = 'pending';

    IF FOUND THEN
      v_count := v_count + 1;

      -- تسجيل الإجراء في request_actions إن وُجد الجدول
      IF to_regclass('public.request_actions') IS NOT NULL THEN
        INSERT INTO public.request_actions (
          request_id, actor_employee_id, action,
          from_status, to_status, comment, created_by
        ) VALUES (
          v_id, v_employee_id,
          CASE p_decision WHEN 'approved' THEN 'approve' ELSE 'reject' END,
          'pending', p_decision, p_comment, v_user_id
        );
      END IF;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  -- ── تسجيل حدث التدقيق ──
  PERFORM public.log_audit_event(
    'batch_decide_requests',           -- event_type
    'workflow',                         -- category
    'notice',                           -- severity
    'requests',                         -- target_table
    NULL,                               -- target_id (عملية جماعية)
    'قرار جماعي على ' || v_count || ' طلب (' || p_decision || ')',  -- summary_ar
    'batch decision: ' || v_count || ' processed, ' || v_skipped || ' skipped',
    jsonb_build_object(
      'processed', v_count,
      'skipped', v_skipped,
      'total', v_total,
      'decision', p_decision,
      'request_ids', to_jsonb(p_request_ids)
    )
  );

  RETURN jsonb_build_object(
    'processed', v_count,
    'skipped',   v_skipped,
    'total',     v_total
  );
END;
$$;

COMMENT ON FUNCTION public.batch_decide_requests(uuid[], text, text) IS
  'قرار جماعي (موافقة/رفض) على عدة طلبات. يتخطى الطلبات غير المعلقة والموافقة الذاتية. SECURITY DEFINER.';


-- =====================================================================
-- 2) batch_mark_notifications_read — تعليم إشعارات متعددة كمقروءة
-- =====================================================================
-- يحدّث فقط إشعارات المستخدم الحالي التي لم تُقرأ بعد.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.batch_mark_notifications_read(
  p_notification_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count   int;
  v_user_id uuid := auth.uid();
BEGIN
  -- ── التحقق من الهوية ──
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
  END IF;

  -- ── التحقق من وجود إشعارات ──
  IF coalesce(array_length(p_notification_ids, 1), 0) = 0 THEN
    RETURN 0;
  END IF;

  -- ── التحقق من وجود جدول notifications ──
  IF to_regclass('public.notifications') IS NULL THEN
    RETURN 0;
  END IF;

  -- ── تحديث الإشعارات (owner-scoped: المستخدم يرى إشعاراته فقط) ──
  UPDATE public.notifications
  SET read_at    = now(),
      is_read    = true,
      updated_at = now()
  WHERE id = ANY(p_notification_ids)
    AND recipient_user_id = v_user_id
    AND read_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.batch_mark_notifications_read(uuid[]) IS
  'تعليم عدة إشعارات كمقروءة للمستخدم الحالي. owner-scoped — لا يمسّ إشعارات غيره. SECURITY DEFINER.';


-- =====================================================================
-- صلاحيات التنفيذ
-- =====================================================================
REVOKE EXECUTE ON FUNCTION public.batch_decide_requests(uuid[], text, text) FROM public;
GRANT  EXECUTE ON FUNCTION public.batch_decide_requests(uuid[], text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.batch_mark_notifications_read(uuid[]) FROM public;
GRANT  EXECUTE ON FUNCTION public.batch_mark_notifications_read(uuid[]) TO authenticated;

COMMIT;
