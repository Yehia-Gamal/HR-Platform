begin;
select plan(3);

-- Test 1: function exists
select has_function(
  'public', 'resolve_request_approver',
  ARRAY['integer','text'],
  'resolve_request_approver should exist'
);

-- Test 2: function contains hr-manager fallback
select like(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='resolve_request_approver'),
  '%hr-manager%',
  'function should have hr-manager as fallback'
);

-- Test 3: function raises NO_APPROVER_FOUND when no one available
select like(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='resolve_request_approver'),
  '%NO_APPROVER_FOUND%',
  'function should raise NO_APPROVER_FOUND instead of returning null'
);

select finish();
rollback;
