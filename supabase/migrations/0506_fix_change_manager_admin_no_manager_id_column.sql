-- 0506: Fix change_employee_manager_admin — employees table has no manager_id column
-- The function references employees.manager_id which doesn't exist.
-- All manager data lives in manager_relations table exclusively.

-- ═══════════════════════════════════════════════════════════════════
-- 1) Fix change_employee_manager_admin: remove employees.manager_id references
-- NOTE: DROP+CREATE is required because CREATE OR REPLACE sometimes fails
-- to replace the function body when deployed via Management API.
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.change_employee_manager_admin(uuid, uuid, text);

CREATE FUNCTION public.change_employee_manager_admin(
  p_employee_id UUID,
  p_manager_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_manager UUID;
  v_pending_count INTEGER := 0;
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_any_permission(ARRAY[
      'people.employee.update_sensitive',
      'people.employee.update_basic',
      'employees.manage',
      'admin.manage',
      'people.manage'
    ])
    OR public.current_has_active_role(ARRAY[
      'admin', 'super-admin', 'hr-manager',
      'operations-manager-1', 'executive', 'executive-director'
    ])
  ) THEN
    RAISE EXCEPTION 'employee_update_not_allowed' USING errcode = '42501';
  END IF;

  IF nullif(trim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'change_reason_required' USING errcode = '22023';
  END IF;

  IF p_manager_id = p_employee_id THEN
    RAISE EXCEPTION 'manager_cannot_be_self' USING errcode = '22023';
  END IF;

  PERFORM 1 FROM public.employees
  WHERE id = p_employee_id AND NOT is_deleted
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'employee_not_found' USING errcode = 'P0002';
  END IF;

  -- الحصول على المدير القديم (من manager_relations فقط — لا يوجد employees.manager_id)
  SELECT manager_employee_id INTO v_old_manager
  FROM public.manager_relations
  WHERE employee_id = p_employee_id
    AND relation_type = 'primary'
    AND effective_from <= current_date
    AND (effective_to IS NULL OR effective_to >= current_date)
  ORDER BY (effective_to IS NULL) DESC, created_at DESC
  LIMIT 1;

  -- fallback: أقدم علاقة primary نشطة أو غير منتهية
  IF v_old_manager IS NULL THEN
    SELECT manager_employee_id INTO v_old_manager
    FROM public.manager_relations
    WHERE employee_id = p_employee_id
      AND relation_type = 'primary'
    ORDER BY effective_from DESC
    LIMIT 1;
  END IF;

  IF p_manager_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.employees
      WHERE id = p_manager_id AND NOT is_deleted AND status = 'active' AND is_active
    ) THEN
      RAISE EXCEPTION 'manager_not_active' USING errcode = '22023';
    END IF;

    -- فحص الدورة الإدارية
    IF EXISTS (
      WITH RECURSIVE manager_chain(id, path) AS (
        SELECT p_manager_id, ARRAY[p_manager_id]::UUID[]
        UNION ALL
        SELECT mr.manager_employee_id, c.path || mr.manager_employee_id
        FROM public.manager_relations mr
        JOIN manager_chain c ON c.id = mr.employee_id
        WHERE mr.relation_type = 'primary'
          AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
          AND NOT mr.manager_employee_id = ANY(c.path)
      )
      SELECT 1 FROM manager_chain WHERE id = p_employee_id
    ) THEN
      RAISE EXCEPTION 'manager_cycle_not_allowed' USING errcode = '22023';
    END IF;
  END IF;

  -- 1) إنهاء العلاقات الإدارية السابقة بأمان
  UPDATE public.manager_relations
  SET effective_to = CASE
        WHEN effective_from < current_date THEN current_date - INTERVAL '1 day'
        ELSE current_date
      END,
      updated_at = now()
  WHERE employee_id = p_employee_id
    AND relation_type = 'primary'
    AND (effective_to IS NULL OR effective_to >= current_date);

  -- 2) إدراج العلاقة الإدارية الجديدة
  IF p_manager_id IS NOT NULL THEN
    INSERT INTO public.manager_relations (
      employee_id, manager_employee_id, relation_type,
      effective_from, effective_to, created_by
    ) VALUES (
      p_employee_id, p_manager_id, 'primary',
      current_date, NULL, auth.uid()
    );
  END IF;

  -- 3) نقل الطلبات المعلّقة إلى المدير الجديد
  UPDATE public.requests
  SET manager_employee_id = p_manager_id,
      updated_at = now()
  WHERE employee_id = p_employee_id
    AND status = 'pending';

  GET DIAGNOSTICS v_pending_count = ROW_COUNT;

  -- 4) نقل خطوات سير العمل النشطة
  UPDATE public.request_steps
  SET assignee_employee_id = p_manager_id,
      updated_at = now()
  WHERE request_id IN (
    SELECT id FROM public.requests WHERE employee_id = p_employee_id AND status = 'pending'
  )
  AND status IN ('active', 'pending')
  AND (assignee_employee_id IS NULL OR assignee_employee_id = v_old_manager);

  PERFORM public.log_audit_event(
    'employee_manager_changed', 'people', 'warning', 'employees', p_employee_id,
    'تغيير المدير المباشر', trim(p_reason),
    jsonb_build_object(
      'previousManagerId', v_old_manager,
      'managerId', p_manager_id,
      'pendingRequestsTransferred', v_pending_count,
      'reason', trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'employeeId', p_employee_id,
    'previousManagerId', v_old_manager,
    'managerId', p_manager_id,
    'pendingRequestsTransferred', v_pending_count,
    'updatedAt', now()
  );
END;
$$;

COMMENT ON FUNCTION public.change_employee_manager_admin(UUID, UUID, TEXT) IS
  '0506: تغيير المدير المباشر — إزالة مرجع employees.manager_id غير الموجود.';

REVOKE ALL ON FUNCTION public.change_employee_manager_admin(UUID, UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.change_employee_manager_admin(UUID, UUID, TEXT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 2) تنظيف العلاقات المكررة — إبقاء نشطة واحدة فقط لكل موظف
-- ═══════════════════════════════════════════════════════════════════

-- حذف العلاقات المكررة (التي لها نفس effective_from وeffective_to = null) —
-- نحتفظ فقط بأحدث واحدة حسب created_at
DELETE FROM public.manager_relations
WHERE id IN (
  SELECT id FROM (
    SELECT id,
      ROW_NUMBER() OVER (
        PARTITION BY employee_id, effective_from
        ORDER BY created_at DESC
      ) as rn
    FROM public.manager_relations
    WHERE relation_type = 'primary'
      AND effective_to IS NULL
  ) ranked
  WHERE rn > 1
);

-- إغلاق العلاقات المكررة التي بدأت قبل اليوم
UPDATE public.manager_relations m
SET effective_to = CASE
      WHEN m.effective_from < current_date THEN current_date - INTERVAL '1 day'
      ELSE current_date
    END,
    updated_at = now()
WHERE m.id IN (
  SELECT id FROM (
    SELECT id,
      ROW_NUMBER() OVER (
        PARTITION BY employee_id
        ORDER BY effective_from DESC, created_at DESC
      ) as rn
    FROM public.manager_relations
    WHERE relation_type = 'primary'
      AND (effective_to IS NULL OR effective_to >= current_date)
  ) ranked
  WHERE rn > 1
);
