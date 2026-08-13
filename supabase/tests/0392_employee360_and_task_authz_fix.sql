-- pgTAP tests for migration 0392
-- يتحقق من:
-- 1) get_employee_360 تعيد الحقول الكاملة (لا stub 3-حقول)
-- 2) admin_create_task لا تُرفض لـ operations.mission.manage
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

SELECT plan(8);

-- ─── 1) get_employee_360 موجودة وتعيد jsonb ──────────────────────────────────
SELECT has_function(
  'public', 'get_employee_360', ARRAY['uuid'],
  '0392: دالة get_employee_360 موجودة'
);

-- التحقق من أن الدالة SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'get_employee_360'),
  true,
  '0392: get_employee_360 هي SECURITY DEFINER'
);

-- التحقق من أن authenticated لديها EXECUTE (لا PUBLIC)
SELECT ok(
  has_function_privilege('authenticated', 'public.get_employee_360(uuid)', 'EXECUTE'),
  '0392: authenticated لديها EXECUTE على get_employee_360'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.get_employee_360(uuid)', 'EXECUTE'),
  '0392: anon لا تملك EXECUTE على get_employee_360'
);

-- التحقق من أن جسم الدالة يحتوي على الحقول الكاملة (ليس stub)
SELECT ok(
  (SELECT prosrc FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'get_employee_360')
  LIKE '%fullNameAr%',
  '0392: get_employee_360 تحتوي على fullNameAr (ليست stub)'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'get_employee_360')
  LIKE '%recentTasks%',
  '0392: get_employee_360 تحتوي على recentTasks (ليست stub)'
);

-- ─── 2) admin_create_task صلاحيات وجسم صحيح ──────────────────────────────────
SELECT has_function(
  'public', 'admin_create_task', ARRAY['text','text','uuid','text','date'],
  '0392: admin_create_task موجودة'
);

-- جسم الدالة يتحقق من operations.mission.manage
SELECT ok(
  (SELECT prosrc FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'admin_create_task'
   LIMIT 1)
  LIKE '%operations.mission.manage%',
  '0392: admin_create_task تقبل operations.mission.manage'
);

SELECT * FROM finish();
ROLLBACK;
