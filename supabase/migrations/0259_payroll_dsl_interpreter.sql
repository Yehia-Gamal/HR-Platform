-- 0259: Pure JSON payroll DSL interpreter.
--
-- Security boundary:
--   * no dynamic SQL, eval, table lookup, or user-selected identifier;
--   * only the five node types allow-listed by migration 0255;
--   * all operands are embedded JSON numbers/booleans and are validated first.

begin;
create or replace function public.payroll_evaluate_condition(p_condition jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $$
declare
  v_op text;
  v_item jsonb;
  v_result boolean;
begin
  if jsonb_typeof(p_condition) <> 'object' then
    raise exception 'INVALID_DSL_CONDITION' using errcode = '22023';
  end if;

  v_op := p_condition->>'op';
  case v_op
    when 'boolean' then
      if jsonb_typeof(p_condition->'value') <> 'boolean' then
        raise exception 'INVALID_DSL_CONDITION' using errcode = '22023';
      end if;
      return (p_condition->>'value')::boolean;
    when 'equals' then
      if not (p_condition ? 'left' and p_condition ? 'right') then
        raise exception 'INVALID_DSL_CONDITION' using errcode = '22023';
      end if;
      return p_condition->'left' = p_condition->'right';
    when 'greater_than', 'less_than' then
      if jsonb_typeof(p_condition->'left') <> 'number'
         or jsonb_typeof(p_condition->'right') <> 'number' then
        raise exception 'INVALID_DSL_CONDITION' using errcode = '22023';
      end if;
      if v_op = 'greater_than' then
        return (p_condition->>'left')::numeric > (p_condition->>'right')::numeric;
      end if;
      return (p_condition->>'left')::numeric < (p_condition->>'right')::numeric;
    when 'not' then
      return not public.payroll_evaluate_condition(p_condition->'value');
    when 'and', 'or' then
      if jsonb_typeof(p_condition->'values') <> 'array'
         or jsonb_array_length(p_condition->'values') = 0 then
        raise exception 'INVALID_DSL_CONDITION' using errcode = '22023';
      end if;
      v_result := (v_op = 'and');
      for v_item in select value from jsonb_array_elements(p_condition->'values') loop
        if v_op = 'and' then
          v_result := v_result and public.payroll_evaluate_condition(v_item);
          if not v_result then return false; end if;
        else
          v_result := v_result or public.payroll_evaluate_condition(v_item);
          if v_result then return true; end if;
        end if;
      end loop;
      return v_result;
    else
      raise exception 'INVALID_DSL_CONDITION_OP' using errcode = '22023';
  end case;
end;
$$;
create or replace function public.payroll_tiered_tax_calculation(
  p_taxable_amount numeric,
  p_brackets jsonb
)
returns numeric
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $$
declare
  v_bracket jsonb;
  v_previous_limit numeric := 0;
  v_limit numeric;
  v_rate numeric;
  v_tax numeric := 0;
  v_slice numeric;
  v_seen_open_ended boolean := false;
begin
  if p_taxable_amount < 0
     or jsonb_typeof(p_brackets) <> 'array'
     or jsonb_array_length(p_brackets) = 0 then
    raise exception 'INVALID_TAX_BRACKETS' using errcode = '22023';
  end if;

  for v_bracket in select value from jsonb_array_elements(p_brackets) loop
    if v_seen_open_ended
       or jsonb_typeof(v_bracket) <> 'object'
       or jsonb_typeof(v_bracket->'rate') <> 'number' then
      raise exception 'INVALID_TAX_BRACKETS' using errcode = '22023';
    end if;

    v_rate := (v_bracket->>'rate')::numeric;
    if v_rate < 0 or v_rate > 100 then
      raise exception 'INVALID_TAX_BRACKETS' using errcode = '22023';
    end if;

    if not (v_bracket ? 'up_to') or jsonb_typeof(v_bracket->'up_to') = 'null' then
      v_limit := p_taxable_amount;
      v_seen_open_ended := true;
    elsif jsonb_typeof(v_bracket->'up_to') = 'number' then
      v_limit := (v_bracket->>'up_to')::numeric;
      if v_limit <= v_previous_limit then
        raise exception 'INVALID_TAX_BRACKETS' using errcode = '22023';
      end if;
    else
      raise exception 'INVALID_TAX_BRACKETS' using errcode = '22023';
    end if;

    v_slice := greatest(least(p_taxable_amount, v_limit) - v_previous_limit, 0);
    v_tax := v_tax + (v_slice * v_rate / 100);
    v_previous_limit := v_limit;
    exit when p_taxable_amount <= v_limit;
  end loop;

  if p_taxable_amount > v_previous_limit and not v_seen_open_ended then
    raise exception 'TAX_BRACKETS_DO_NOT_COVER_AMOUNT' using errcode = '22023';
  end if;

  return round(v_tax, 2);
end;
$$;
create or replace function public.payroll_validate_dsl_spec(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $$
declare
  v_type text;
begin
  if jsonb_typeof(p_spec) <> 'object'
     or jsonb_typeof(p_spec->'id') <> 'string'
     or length(btrim(p_spec->>'id')) = 0
     or jsonb_typeof(p_spec->'type') <> 'string' then
    return false;
  end if;

  v_type := p_spec->>'type';
  case v_type
    when 'fixed_amount' then
      return jsonb_typeof(p_spec->'amount') = 'number';
    when 'percentage_of_basic' then
      return jsonb_typeof(p_spec->'percentage') = 'number'
        and (p_spec->>'percentage')::numeric between 0 and 100
        and jsonb_typeof(p_spec->'base_amount') = 'number'
        and (p_spec->>'base_amount')::numeric >= 0
        and (
          not (p_spec ? 'cap_amount')
          or (
            jsonb_typeof(p_spec->'cap_amount') = 'number'
            and (p_spec->>'cap_amount')::numeric >= 0
          )
        );
    when 'tiered_tax' then
      return jsonb_typeof(p_spec->'taxable_amount') = 'number'
        and (p_spec->>'taxable_amount')::numeric >= 0
        and jsonb_typeof(p_spec->'brackets') = 'array'
        and jsonb_array_length(p_spec->'brackets') > 0;
    when 'attendance_deduction' then
      return jsonb_typeof(p_spec->'absent_days') = 'number'
        and (p_spec->>'absent_days')::numeric >= 0
        and jsonb_typeof(p_spec->'amount_per_day') = 'number'
        and (p_spec->>'amount_per_day')::numeric >= 0;
    when 'conditional' then
      if jsonb_typeof(p_spec->'condition') <> 'object'
         or jsonb_typeof(p_spec->'then') <> 'object'
         or jsonb_typeof(p_spec->'else') <> 'object'
         or not public.payroll_validate_dsl_spec(p_spec->'then')
         or not public.payroll_validate_dsl_spec(p_spec->'else') then
        return false;
      end if;
      perform public.payroll_evaluate_condition(p_spec->'condition');
      return true;
    else
      return false;
  end case;
exception
  when data_exception or numeric_value_out_of_range then
    return false;
end;
$$;
create or replace function public.payroll_formula_interpreter(p_spec jsonb)
returns numeric
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result numeric;
  v_type text;
begin
  if not public.payroll_validate_dsl_spec(p_spec) then
    raise exception 'INVALID_DSL_SPEC' using errcode = '22023';
  end if;

  v_type := p_spec->>'type';
  case v_type
    when 'fixed_amount' then
      v_result := (p_spec->>'amount')::numeric;
    when 'percentage_of_basic' then
      v_result := (p_spec->>'base_amount')::numeric
        * (p_spec->>'percentage')::numeric / 100;
      if p_spec ? 'cap_amount' then
        v_result := least(v_result, (p_spec->>'cap_amount')::numeric);
      end if;
    when 'tiered_tax' then
      v_result := public.payroll_tiered_tax_calculation(
        (p_spec->>'taxable_amount')::numeric,
        p_spec->'brackets'
      );
    when 'attendance_deduction' then
      v_result := (p_spec->>'absent_days')::numeric
        * (p_spec->>'amount_per_day')::numeric;
    when 'conditional' then
      v_result := public.payroll_formula_interpreter(
        case when public.payroll_evaluate_condition(p_spec->'condition')
          then p_spec->'then' else p_spec->'else' end
      );
    else
      raise exception 'UNSUPPORTED_DSL_TYPE' using errcode = '22023';
  end case;

  return round(v_result, 2);
end;
$$;
create table if not exists public.payroll_execution_log (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.payroll_runs(id) on delete cascade,
  template_id uuid references public.payroll_formula_templates(id) on delete restrict,
  template_version integer not null check (template_version > 0),
  spec_snapshot jsonb not null check (jsonb_typeof(spec_snapshot) = 'object'),
  calculated_amount numeric(14,2),
  validation_passed boolean not null default false,
  error_message text,
  created_at timestamptz not null default now()
);
alter table public.payroll_execution_log enable row level security;
alter table public.payroll_execution_log force row level security;
revoke all on table public.payroll_execution_log from public, anon, authenticated;
grant select, insert on table public.payroll_execution_log to service_role;
revoke execute on function public.payroll_evaluate_condition(jsonb)
  from public, anon, authenticated;
revoke execute on function public.payroll_tiered_tax_calculation(numeric, jsonb)
  from public, anon, authenticated;
revoke execute on function public.payroll_validate_dsl_spec(jsonb)
  from public, anon, authenticated;
revoke execute on function public.payroll_formula_interpreter(jsonb)
  from public, anon, authenticated;
grant execute on function public.payroll_evaluate_condition(jsonb) to service_role;
grant execute on function public.payroll_tiered_tax_calculation(numeric, jsonb) to service_role;
grant execute on function public.payroll_validate_dsl_spec(jsonb) to service_role;
grant execute on function public.payroll_formula_interpreter(jsonb) to service_role;
commit;
