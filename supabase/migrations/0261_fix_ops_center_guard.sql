-- ═══════════════════════════════════════════════════════════════
-- 0261: تصحيح حارس get_operations_center_data (P0 — تسريب بعد 0256)
--
-- المشكلة: 0256 حارس get_operations_center_data على has_permission('tasks.read')
--   بحجة أن tasks.read بوابة /admin/operations، لكن 'tasks.read' مُنحَت للدور
--   الأساسي 'employee' (نطاق self) في seed 0002 — فكل موظف عادي يمر عبر الحارس
--   ويحصل على كشف كامل: كل الموظفين + المهام + المهمام الرسمية + قوافل + طلبات.
--
-- الإصلاح: الاستبدال بـحارس إداري فعلي — أيّ من:
--   • reports.read                 (hr-manager / department-manager /
--                                  executive-director / executive-secretary)
--   • operations.mission.manage    (operations-manager)
--   • operations.convoy.manage     (operations-manager)
--   ولا يملك أيّاً منها دور 'employee' أو 'operations-officer'،
--   مع الإبقاء على current_is_full_access() للوصول الكامل.
--
-- التوافق: CREATE OR REPLACE يحافظ على المنح القائمة (authenticated ينفّذ،
--   anon/PUBLIC مسحوبة منذ 0227)، ولا يُلمس أي كائن آخر.
-- ═══════════════════════════════════════════════════════════════

BEGIN;
CREATE OR REPLACE FUNCTION public.get_operations_center_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  _result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF NOT (
    public.current_is_full_access()
    OR public.has_any_permission(array[
      'reports.read',
      'operations.mission.manage',
      'operations.convoy.manage'
    ])
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'employees', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'full_name_ar', full_name_ar))
                  FROM (SELECT id, full_name_ar FROM employees ORDER BY full_name_ar LIMIT 500) e), '[]'::jsonb),
    'tasks', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', id, 'title', title, 'description', description,
                'assignee_employee_id', assignee_employee_id,
                'priority', priority, 'due_date', due_date, 'status', status))
              FROM (SELECT id, title, description, assignee_employee_id, priority, due_date, status
                    FROM tasks ORDER BY created_at DESC LIMIT 200) t), '[]'::jsonb),
    'missions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                  'id', id, 'request_id', request_id, 'employee_id', employee_id,
                  'destination', destination, 'purpose', purpose,
                  'start_at', start_at, 'end_at', end_at, 'transport_mode', transport_mode))
                FROM (SELECT id, request_id, employee_id, destination, purpose, start_at, end_at, transport_mode
                      FROM missions ORDER BY start_at DESC LIMIT 100) m), '[]'::jsonb),
    'convoy_requests', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id', id, 'request_id', request_id, 'employee_id', employee_id,
                        'convoy_name', convoy_name, 'origin', origin, 'destination', destination,
                        'departure_at', departure_at, 'return_at', return_at,
                        'passengers_count', passengers_count, 'vehicles_count', vehicles_count))
                      FROM (SELECT id, request_id, employee_id, convoy_name, origin, destination,
                                   departure_at, return_at, passengers_count, vehicles_count
                            FROM convoy_requests ORDER BY departure_at DESC LIMIT 100) c), '[]'::jsonb),
    'requests', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'status', status))
                FROM (SELECT id, status FROM requests ORDER BY created_at DESC LIMIT 300) r), '[]'::jsonb)
  ) INTO _result;

  RETURN _result;
END;
$$;
COMMIT;
