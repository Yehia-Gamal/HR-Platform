-- 0100: pure payroll DSL interpreter (migration 0259).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(10);

select is(public.payroll_formula_interpreter(
  '{"id":"fixed","type":"fixed_amount","amount":125.55}'::jsonb
), 125.55::numeric, 'fixed amount is returned exactly');

select is(public.payroll_formula_interpreter(
  '{"id":"pct","type":"percentage_of_basic","percentage":10,"base_amount":8000}'::jsonb
), 800::numeric, 'percentage of basic is calculated');

select is(public.payroll_formula_interpreter(
  '{"id":"capped","type":"percentage_of_basic","percentage":20,"base_amount":8000,"cap_amount":1000}'::jsonb
), 1000::numeric, 'percentage cap is enforced');

select is(public.payroll_formula_interpreter(
  '{"id":"absence","type":"attendance_deduction","absent_days":2,"amount_per_day":300}'::jsonb
), 600::numeric, 'attendance deduction is deterministic');

select is(public.payroll_formula_interpreter(
  '{"id":"tax","type":"tiered_tax","taxable_amount":15000,"brackets":[{"up_to":10000,"rate":10},{"up_to":null,"rate":20}]}'::jsonb
), 2000::numeric, 'progressive tax uses taxable amount and ordered brackets');

select is(public.payroll_formula_interpreter(
  '{"id":"conditional","type":"conditional","condition":{"op":"greater_than","left":2,"right":1},"then":{"id":"yes","type":"fixed_amount","amount":10},"else":{"id":"no","type":"fixed_amount","amount":5}}'::jsonb
), 10::numeric, 'conditional selects the true branch');

select ok(not public.payroll_validate_dsl_spec(
  '{"id":"bad","type":"percentage_of_basic","percentage":101,"base_amount":10}'::jsonb
), 'percentage above 100 is rejected');

select ok(not public.payroll_validate_dsl_spec(
  '{"id":"bad","type":"loan_installment","amount":10}'::jsonb
), 'non-allow-listed node type is rejected');

select throws_ok(
  $$select public.payroll_formula_interpreter('{"id":"bad","type":"fixed_amount"}'::jsonb)$$,
  '22023', 'INVALID_DSL_SPEC', 'invalid spec fails closed'
);

select ok(
  not has_function_privilege('authenticated', 'public.payroll_formula_interpreter(jsonb)', 'EXECUTE'),
  'authenticated cannot invoke the service-only interpreter directly'
);

select * from finish();
rollback;
