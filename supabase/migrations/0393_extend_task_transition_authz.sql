-- ══════════════════════════════════════════════════════════════════════
-- 0393: توسيع صلاحية admin_transition_task لمديري العمليات
--
-- مشكلة: 0392 أضاف operations.mission.manage إلى admin_create_task
-- لكن admin_transition_task بقيت تتطلب tasks.write فقط.
-- النتيجة: مدير العمليات يمكنه إنشاء المهام لكن لا يمكنه تحديث حالتها
-- (pending → in_progress → done)، مما يجعل المهام عالقة.
--
-- الإصلاح: إضافة operations.mission.manage إلى شرط الصلاحية.
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_transition_task(
  p_id     uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('tasks.write')
    OR public.has_permission('operations.mission.manage')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: تغيير حالة المهام يتطلب tasks.write أو operations.mission.manage'
      USING ERRCODE = '42501';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('pending', 'in_progress', 'done', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_TASK_STATUS' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tasks
  SET status = p_status, updated_at = now()
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_transition_task(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_transition_task(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_transition_task(uuid, text) IS
  '0393: يسمح لـ full_access + tasks.write + operations.mission.manage بتحديث حالة المهام.';

NOTIFY pgrst, 'reload schema';

COMMIT;
