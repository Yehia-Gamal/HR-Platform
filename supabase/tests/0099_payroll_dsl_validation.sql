-- 0099: payroll formula DSL foundation (migrations 0255 and 0258).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(13);

select has_table('public', 'payroll_formula_templates', 'formula templates table exists');
select has_table('public', 'payroll_formula_approvals', 'formula approvals table exists');
select col_type_is('public', 'payroll_formula_templates', 'spec', 'jsonb', 'formula spec is jsonb');
select col_type_is('public', 'payroll_formula_templates', 'template_config', 'jsonb', 'template config is jsonb');

select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class
    where oid = 'public.payroll_formula_templates'::regclass),
  'formula templates enforce RLS'
);

select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class
    where oid = 'public.payroll_formula_approvals'::regclass),
  'formula approvals enforce RLS'
);

select ok(
  not has_table_privilege('anon', 'public.payroll_formula_templates', 'SELECT'),
  'anon cannot read formula templates'
);

select ok(
  not has_table_privilege('anon', 'public.payroll_formula_approvals', 'SELECT'),
  'anon cannot read formula approvals'
);

select throws_ok(
  $$insert into public.payroll_formula_templates
      (code, name_ar, jurisdiction, spec, effective_from)
    values ('invalid-code!', 'صيغة غير صالحة', 'EG', '{}'::jsonb, current_date)$$,
  '23514',
  null,
  'template code constraint rejects executable-style identifiers'
);

select set_eq(
  $$select jsonb_array_elements_text(public.payroll_dsl_get_allowed_types())$$,
  $$values
      ('fixed_amount'::text),
      ('percentage_of_basic'::text),
      ('tiered_tax'::text),
      ('conditional'::text),
      ('attendance_deduction'::text)$$,
  'DSL node allow-list contains exactly the five supported node types'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.payroll_dsl_get_allowed_types()',
    'EXECUTE'
  ),
  'anon cannot read the service-only DSL allow-list'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.payroll_dsl_get_allowed_types()',
    'EXECUTE'
  ),
  'authenticated cannot read the service-only DSL allow-list'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.payroll_dsl_get_allowed_types()',
    'EXECUTE'
  ),
  'service role can read the DSL allow-list'
);

select * from finish();
rollback;
