-- 0388: get_mobile_employee_directory — دليل الموظفين (mig 0388)
begin;
select plan(5);

-- 1. الدالة موجودة بالمعاملات الصحيحة
select has_function(
  'public', 'get_mobile_employee_directory',
  array['text', 'integer'],
  'get_mobile_employee_directory(text, integer) موجودة'
);

-- 2. SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_mobile_employee_directory'),
  true,
  'get_mobile_employee_directory يجب أن تكون SECURITY DEFINER'
);

-- 3. STABLE (لا تُعدّل البيانات)
select is(
  (select provolatile from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_mobile_employee_directory'),
  's'::char,
  'get_mobile_employee_directory يجب أن تكون STABLE'
);

-- 4. تتحقق من auth.uid() (بلا مصادقة ترفع استثناء)
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_mobile_employee_directory'),
  '%auth.uid()%',
  'get_mobile_employee_directory تتحقق من auth.uid() قبل الاستجابة'
);

-- 5. authenticated يملك EXECUTE — الدليل متاح لجميع الموظفين
select ok(
  exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'get_mobile_employee_directory'
      and grantee        = 'authenticated'
  ),
  'authenticated يملك EXECUTE على get_mobile_employee_directory'
);

select finish();
rollback;
