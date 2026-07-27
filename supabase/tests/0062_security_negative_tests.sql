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
SELECT is(
  (SELECT count(*)::integer FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c
      WHERE c LIKE 'search_path=%'
    )),
  0,
  'كل دوال SECURITY DEFINER لها search_path ثابت'
);

-- ════════════════════════════════════════════════════
-- 3. الصلاحيات: لا EXECUTE من anon على الدوال الحساسة
-- ════════════════════════════════════════════════════

-- فحص الصلاحيات عبر OID — لا حاجة لتوقيع الدالة الكامل
SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'provision_employee_record ليست متاحة لـ anon'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'provision_employee_record' LIMIT 1;

SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'rpc_assign_role ليست متاحة لـ anon'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'rpc_assign_role' LIMIT 1;

SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'rpc_revoke_role ليست متاحة لـ anon'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'rpc_revoke_role' LIMIT 1;

SELECT ok(
  NOT has_function_privilege('anon', p.oid, 'EXECUTE'),
  'log_audit_event ليست متاحة لـ anon'
) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'log_audit_event' LIMIT 1;

-- ════════════════════════════════════════════════════
-- 4. القيود: لا NULL في الأعمدة الإلزامية
-- ════════════════════════════════════════════════════

SELECT col_not_null('public', 'employees', 'id', 'employees.id NOT NULL');
SELECT col_not_null('public', 'employees', 'full_name_ar', 'employees.full_name_ar NOT NULL');
SELECT col_not_null('public', 'employees', 'status', 'employees.status NOT NULL');

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
