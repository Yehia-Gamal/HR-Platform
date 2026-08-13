-- 0383: resolve_request_approver — guaranteed fallback for missions (mig 0385)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(5);

-- 1. نسخة النظام الحقيقية (uuid,date) موجودة — التوقيع الأجنبي (integer,text) أُزيل في 0399
select has_function(
  'public', 'resolve_request_approver',
  array['uuid','date'],
  'resolve_request_approver(uuid,date) موجودة — نسخة النظام الحقيقية'
);

-- 2. SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'resolve_request_approver'
     and p.oid = 'public.resolve_request_approver(uuid,date)'::regprocedure),
  true,
  'resolve_request_approver(uuid,date) يجب أن تكون SECURITY DEFINER'
);

-- 3. تحتوي على fallback مضموناً إلى HR (بديل المدير المباشر)
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'resolve_request_approver'
     and p.oid = 'public.resolve_request_approver(uuid,date)'::regprocedure)::text,
  '%hr-manager%'::text,
  'الدالة يجب أن تتضمن fallback مضموناً إلى hr-manager/hr-specialist'::text
);

-- 4. تعيد معرّف المعتمِد (uuid) بدلاً من رفع استثناء
select is(
  (select pg_get_function_result(p.oid) from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'resolve_request_approver'
     and p.oid = 'public.resolve_request_approver(uuid,date)'::regprocedure),
  'uuid',
  'الدالة تعيد معرّف المعتمِد (uuid) ولا ترفع استثناء عند غياب المعتمدين'
);

-- 5. anon لا يملك EXECUTE
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'resolve_request_approver'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على resolve_request_approver'
);

select finish();
rollback;
