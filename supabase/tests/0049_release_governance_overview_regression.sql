begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(4);

select has_function(
  'public', 'get_release_governance_overview', array[]::text[],
  'release governance overview function exists'
);

select ok(
  position('from public.managed_devices d' in pg_get_functiondef(
    'public.get_release_governance_overview()'::regprocedure
  )) > 0,
  'release governance devices use the managed_devices contract'
);

select ok(
  position('passkey_credentials' in pg_get_functiondef(
    'public.get_release_governance_overview()'::regprocedure
  )) = 0,
  'release governance no longer projects obsolete passkey columns'
);

select ok(
  position('access_review_items' in pg_get_functiondef(
    'public.get_release_governance_overview()'::regprocedure
  )) > 0
  and position('break_glass_requests' in pg_get_functiondef(
    'public.get_release_governance_overview()'::regprocedure
  )) > 0,
  'release governance keeps access-review and break-glass sections'
);

select * from finish();
rollback;
