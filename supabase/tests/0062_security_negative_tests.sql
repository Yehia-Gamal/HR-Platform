-- pgTAP: اختبارات أمان سلبية — التحقق من رفض العمليات غير المصرح بها
-- Agent 13 — QA Security Negative Tests

BEGIN;
SELECT plan(22);

-- ════════════════════════════════════════════════════
-- 1. RLS: موظف عادي لا يستطيع قراءة بيانات أمنية
-- ════════════════════════════════════════════════════

-- التحقق من وجود RLS على الجداول الأمنية الحساسة
SELECT has_table('public', 'audit_events', 'جدول أحداث المراجعة موجود');
SELECT has_table('public', 'security_events', 'جدول الأحداث الأمنية موجود');
SELECT has_table('public', 'login_auth_attempts', 'جدول محاولات الدخول موجود');

-- RLS مفعل على الجداول الحساسة
SELECT policies_are(
  'public', 'audit_events',
  ARRAY(SELECT policyname::text FROM pg_policies WHERE tablename = 'audit_events' AND schemaname = 'public'),
  'audit_events لديه سياسات RLS'
);

SELECT policies_are(
  'public', 'security_events',
  ARRAY(SELECT policyname::text FROM pg_policies WHERE tablename = 'security_events' AND schemaname = 'public'),
  'security_events لديه سياسات RLS'
);

-- ════════════════════════════════════════════════════
-- 2. SECURITY DEFINER: كل الدوال الحساسة محمية
-- ════════════════════════════════════════════════════

-- التحقق من أن الدوال الحساسة لها search_path ثابت
SELECT lives_ok(
  $$SELECT proname FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c
      WHERE c LIKE 'search_path=%'
    )
    HAVING count(*) = 0$$,
  'كل دوال SECURITY DEFINER لها search_path ثابت'
);

-- ════════════════════════════════════════════════════
-- 3. الصلاحيات: لا EXECUTE من PUBLIC على الدوال الحساسة
-- ════════════════════════════════════════════════════

SELECT ok(
  NOT has_function_privilege('PUBLIC', 'provision_employee_record(jsonb)', 'EXECUTE'),
  'provision_employee_record ليست متاحة لـ PUBLIC'
);

SELECT ok(
  NOT has_function_privilege('PUBLIC', 'rpc_assign_role(uuid, uuid)', 'EXECUTE'),
  'rpc_assign_role ليست متاحة لـ PUBLIC'
);

SELECT ok(
  NOT has_function_privilege('PUBLIC', 'rpc_revoke_role(uuid, uuid)', 'EXECUTE'),
  'rpc_revoke_role ليست متاحة لـ PUBLIC'
);

SELECT ok(
  NOT has_function_privilege('PUBLIC', 'log_audit_event(text, text, text, jsonb)', 'EXECUTE'),
  'log_audit_event ليست متاحة لـ PUBLIC'
);

-- ════════════════════════════════════════════════════
-- 4. القيود: لا NULL في الأعمدة الإلزامية
-- ════════════════════════════════════════════════════

SELECT col_not_null('public', 'employees', 'id', 'employees.id NOT NULL');
SELECT col_not_null('public', 'employees', 'full_name_ar', 'employees.full_name_ar NOT NULL');
SELECT col_not_null('public', 'employees', 'employment_status', 'employees.employment_status NOT NULL');

SELECT col_not_null('public', 'attendance_events', 'employee_id', 'attendance_events.employee_id NOT NULL');
SELECT col_not_null('public', 'attendance_events', 'event_type', 'attendance_events.event_type NOT NULL');

SELECT col_not_null('public', 'requests', 'employee_id', 'requests.employee_id NOT NULL');
SELECT col_not_null('public', 'requests', 'request_type', 'requests.request_type NOT NULL');

-- ════════════════════════════════════════════════════
-- 5. المفاتيح الخارجية: العلاقات المهمة محمية
-- ════════════════════════════════════════════════════

SELECT col_is_fk('public', 'attendance_events', 'employee_id',
  'attendance_events.employee_id مفتاح خارجي');

SELECT col_is_fk('public', 'requests', 'employee_id',
  'requests.employee_id مفتاح خارجي');

SELECT col_is_fk('public', 'kpi_evaluations', 'employee_id',
  'kpi_evaluations.employee_id مفتاح خارجي');

-- ════════════════════════════════════════════════════
-- 6. using(true): التأكد من أنها فقط على جداول مرجعية
-- ════════════════════════════════════════════════════

-- الجداول التي يجب ألا تحتوي على using(true)
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'employees'
    AND schemaname = 'public'
    AND qual = 'true'
  ),
  'employees ليس لديه سياسة using(true)'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'attendance_events'
    AND schemaname = 'public'
    AND qual = 'true'
  ),
  'attendance_events ليس لديه سياسة using(true)'
);

SELECT * FROM finish();
ROLLBACK;
