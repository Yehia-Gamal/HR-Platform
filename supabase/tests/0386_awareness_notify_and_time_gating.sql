-- 0386: تريغر الإشعار الفوري + تقييد الموافقة بالزمن (mig 0386)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(6);

-- 1. دالة التريغر موجودة
select has_function(
  'public', 'tg_notify_awareness_on_request_submit',
  array[]::text[],
  'tg_notify_awareness_on_request_submit() موجودة'
);

-- 2. التريغر مربوط بجدول requests
select ok(
  exists (
    select 1 from information_schema.triggers
    where trigger_schema = 'public'
      and event_object_table = 'requests'
      and trigger_name like '%notify_awareness%'
  ),
  'تريغر notify_awareness_on_request_submit موجود على requests'
);

-- 3. decide_request موجودة
select has_function(
  'public', 'decide_request',
  array['uuid','text','text'],
  'decide_request(uuid,text,text) موجودة'
);

-- 4. decide_request تفرض الصلاحية حسب خطوة workflow (step-gating)
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'decide_request'
   limit 1),
  '%v_current_step%',
  'decide_request يجب أن تتحقق من خطوة workflow النشطة (step-gating)'
);

-- 5. decide_request SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'decide_request'
   limit 1),
  true,
  'decide_request يجب أن تكون SECURITY DEFINER'
);

-- 6. anon لا يملك EXECUTE على decide_request
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'decide_request'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على decide_request'
);

select finish();
rollback;
