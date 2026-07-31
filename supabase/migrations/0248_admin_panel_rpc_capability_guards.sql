-- ═══════════════════════════════════════════════════════════════
-- 0248: إغلاق ثغرة تسريب بيانات لوحة الإدارة (P0)
--
-- المشكلة: الدوال الثلاث لتغذية لوحات الإدارة في 0225
--   (get_audit_security_data / get_operations_center_data /
--    get_integration_center_data) هي SECURITY DEFINER وتتجاوز RLS،
--   لكن الحارس الوحيد بداخلها كان "IF auth.uid() IS NULL" فقط —
--   أي مجرد "هل المستخدم مسجّل الدخول؟" دون أي فحص صلاحية.
--
--   0227 (P0-4,5,6) سحب PUBLIC/anon فقط ولم يسحب authenticated
--   ولم يُضِف فحص الصلاحية للجسم — لذا ظلّت الثغرة مفتوحة لكل
--   موظف مسجّل: يمكنه استدعاء الدوال مباشرة عبر PostgREST والحصول
--   على سجلات الأمان والتدقيق وكامل قائمة الموظفين وإعدادات التكامل.
--
-- الإصلاح: إضافة فحص صلاحية داخل جسم كل دالة، مطابق تماماً
--   لسياسات RLS على الجداول الأساسية في 0011:
--     - security_events / audit_events → 'audit.view'
--     - integrations / integration_*   → 'system.integration.view'
--     - operations (employees/tasks…)  → 'tasks.read' (بوابة /admin/operations)
--   مع الإبقاء على current_is_full_access() للوصول الكامل.
-- ═══════════════════════════════════════════════════════════════

BEGIN;

--------------------------------------------------------------------------------
-- get_operations_center_data — يتطلب tasks.read
--------------------------------------------------------------------------------
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
  IF NOT (public.current_is_full_access() OR public.has_permission('tasks.read')) THEN
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

--------------------------------------------------------------------------------
-- get_audit_security_data — يتطلب audit.view
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_audit_security_data()
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
  IF NOT (public.current_is_full_access() OR public.has_permission('audit.view')) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'securityEvents', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id', id, 'event_type', event_type, 'severity', severity,
                        'outcome', outcome, 'handled', handled, 'occurred_at', occurred_at))
                      FROM (SELECT id, event_type, severity, outcome, handled, occurred_at
                            FROM security_events ORDER BY occurred_at DESC LIMIT 100) se), '[]'::jsonb),
    'auditEvents', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                      'id', id, 'event_type', event_type, 'category', category,
                      'severity', severity, 'summary_ar', summary_ar,
                      'target_table', target_table, 'occurred_at', occurred_at))
                    FROM (SELECT id, event_type, category, severity, summary_ar, target_table, occurred_at
                          FROM audit_events ORDER BY occurred_at DESC LIMIT 120) ae), '[]'::jsonb),
    'devices', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                  'id', d.id, 'device_name', d.device_name, 'device_model', d.device_model,
                  'platform', d.platform, 'os_version', d.os_version, 'app_version', d.app_version,
                  'environment', d.environment, 'trusted', d.trusted, 'status', d.status,
                  'last_seen_at', d.last_seen_at, 'first_seen_at', d.first_seen_at,
                  'employee_id', d.employee_id,
                  'employee_name', e.full_name_ar))
                FROM (SELECT * FROM managed_devices ORDER BY last_seen_at DESC LIMIT 200) d
                LEFT JOIN employees e ON e.id = d.employee_id), '[]'::jsonb)
  ) INTO _result;

  RETURN _result;
END;
$$;

--------------------------------------------------------------------------------
-- get_integration_center_data — يتطلب system.integration.view
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_integration_center_data()
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
  IF NOT (public.current_is_full_access() OR public.has_permission('system.integration.view')) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'integrations', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                      'id', id, 'name_ar', name_ar, 'provider', provider, 'category', category,
                      'status', status, 'is_enabled', is_enabled,
                      'last_sync_at', last_sync_at, 'last_error', last_error))
                    FROM (SELECT id, name_ar, provider, category, status, is_enabled, last_sync_at, last_error
                          FROM integrations ORDER BY created_at DESC LIMIT 100) i), '[]'::jsonb),
    'logs', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', id, 'integration_id', integration_id, 'operation', operation,
                'direction', direction, 'status', status, 'http_status', http_status,
                'duration_ms', duration_ms, 'occurred_at', occurred_at, 'error_message', error_message))
              FROM (SELECT id, integration_id, operation, direction, status, http_status, duration_ms, occurred_at, error_message
                    FROM integration_logs ORDER BY occurred_at DESC LIMIT 150) il), '[]'::jsonb),
    'outbox', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                  'id', id, 'event_type', event_type, 'status', status,
                  'attempts', attempts, 'max_attempts', max_attempts,
                  'next_attempt_at', next_attempt_at, 'created_at', created_at, 'last_error', last_error))
                FROM (SELECT id, event_type, status, attempts, max_attempts, next_attempt_at, created_at, last_error
                      FROM integration_outbox ORDER BY created_at DESC LIMIT 150) io), '[]'::jsonb),
    'automationRuns', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id', id, 'status', status, 'attempts', attempts,
                        'created_at', created_at, 'completed_at', completed_at, 'error_detail', error_detail))
                      FROM (SELECT id, status, attempts, created_at, completed_at, error_detail
                            FROM automation_runs ORDER BY created_at DESC LIMIT 100) ar), '[]'::jsonb)
  ) INTO _result;

  RETURN _result;
END;
$$;

--------------------------------------------------------------------------------
-- get_employee_photo_url — يتطلب صلاحية قراءة بيانات الموظفين
-- (الصورة PII؛ لا يجوز لأي موظف قراءة صورة أي موظف آخر عشوائياً)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_employee_photo_url(p_employee_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF NOT (
    public.has_permission('people.employee.read')
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN (SELECT photo_url FROM employees WHERE id = p_employee_id);
END;
$$;

COMMIT;
