begin;
select plan(4);

-- Test 1: function exists
select has_function(
  'public', 'set_employee_attendance_day_admin',
  ARRAY['integer','date','text','text'],
  'set_employee_attendance_day_admin should exist'
);

-- Test 2: function is security definer
select is(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='set_employee_attendance_day_admin'),
  true,
  'function should be SECURITY DEFINER'
);

-- Test 3: function body contains BACKDATING_LIMIT check
select like(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='set_employee_attendance_day_admin'),
  '%BACKDATING_LIMIT%',
  'function should contain BACKDATING_LIMIT guard'
);

-- Test 4: function body contains future date check
select like(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='set_employee_attendance_day_admin'),
  '%INVALID_DATE%',
  'function should contain future date guard'
);

select finish();
rollback;
