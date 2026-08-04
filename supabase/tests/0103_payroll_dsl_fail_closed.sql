-- 0103: regression for SQL three-valued logic in the payroll DSL gate.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(3);

select throws_ok(
  $$select public.payroll_formula_interpreter('{"id":"bad","type":"fixed_amount"}'::jsonb)$$,
  '22023', 'INVALID_DSL_SPEC',
  'missing required amount fails closed even when the validator returns NULL'
);

select is(
  public.payroll_formula_interpreter(
    '{"id":"fixed","type":"fixed_amount","amount":125.55}'::jsonb
  ),
  125.55::numeric,
  'valid fixed amount still evaluates after fail-closed hardening'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.payroll_formula_interpreter(jsonb)',
    'EXECUTE'
  ),
  'authenticated still cannot execute the service-only interpreter'
);

select * from finish();
rollback;
