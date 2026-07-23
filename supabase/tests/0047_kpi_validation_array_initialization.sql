begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(3);

select has_function(
  'public',
  'get_kpi_validation_errors',
  array['uuid'],
  'KPI validation function exists'
);

select is(
  pg_get_function_result('public.get_kpi_validation_errors(uuid)'::regprocedure),
  'text[]',
  'KPI validation function returns a text array'
);

select ok(
  position(
    'array[]::text[]' in
    lower(pg_get_functiondef('public.get_kpi_validation_errors(uuid)'::regprocedure))
  ) > 0,
  'KPI validation errors use an explicitly typed empty array'
);

select * from finish();
rollback;
