-- pgTAP tests for migration 0393
-- يتحقق من أن admin_transition_task قبلت operations.mission.manage
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

SELECT plan(5);

SELECT has_function(
  'public', 'admin_transition_task', ARRAY['uuid','text'],
  '0393: دالة admin_transition_task موجودة'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.admin_transition_task(uuid,text)', 'EXECUTE'),
  '0393: anon لا تملك EXECUTE على admin_transition_task'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.admin_transition_task(uuid,text)', 'EXECUTE'),
  '0393: authenticated لديها EXECUTE على admin_transition_task'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'admin_transition_task'
   LIMIT 1)
  LIKE '%operations.mission.manage%',
  '0393: admin_transition_task تتحقق من operations.mission.manage'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND p.proname = 'admin_transition_task'
   LIMIT 1)
  LIKE '%tasks.write%',
  '0393: admin_transition_task لا تزال تتحقق من tasks.write'
);

SELECT * FROM finish();
ROLLBACK;
