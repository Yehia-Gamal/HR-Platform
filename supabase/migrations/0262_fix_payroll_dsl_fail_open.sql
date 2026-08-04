-- ═══════════════════════════════════════════════════════════════
-- 0262: تصحيح Fail-Open في payroll_validate_dsl_spec (0259)
--
-- المشكلة: حين ينقص حقل مطلوب (مثل amount في fixed_amount) يعيد
--   jsonb_typeof(p_spec->'amount') القيمة NULL، وليس false:
--     return jsonb_typeof(p_spec->'amount') = 'number';   -- → NULL
--   وفي payroll_formula_interpreter:
--     if not public.payroll_validate_dsl_spec(p_spec) then raise ... end if;
--   يكون `not NULL` هو NULL أيضاً، و IF يتعامل مع NULL كـ false
--   فتُقبَل المواصفة الناقصة وتُحتسب القيمة (غالباً NULL) دون استثناء.
--   نفس الفخ في فحص المدخلات الأول (length(btrim(id)) → NULL).
--
-- الإصلاح: إعادة بناء المُلحِّق بحيث لا يعيد NULL أبداً —
--   كل تعبير قابل للـ NULL يُغلَّف بـ coalesce(..., false)،
--   ويُعالَج p_spec NULL صراحةً. تبقى بقية البنية/المنح كما هي.
-- ═══════════════════════════════════════════════════════════════

BEGIN;

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
  if p_spec is null
     or jsonb_typeof(p_spec) <> 'object'
     or jsonb_typeof(p_spec->'id') <> 'string'
     or length(btrim(coalesce(p_spec->>'id', ''))) = 0
     or jsonb_typeof(p_spec->'type') <> 'string' then
    return false;
  end if;

  v_type := p_spec->>'type';
  case v_type
    when 'fixed_amount' then
      return coalesce(jsonb_typeof(p_spec->'amount') = 'number', false);
    when 'percentage_of_basic' then
      return coalesce(
        jsonb_typeof(p_spec->'percentage') = 'number'
        and (p_spec->>'percentage')::numeric between 0 and 100
        and jsonb_typeof(p_spec->'base_amount') = 'number'
        and (p_spec->>'base_amount')::numeric >= 0
        and (
          not (p_spec ? 'cap_amount')
          or (
            jsonb_typeof(p_spec->'cap_amount') = 'number'
            and (p_spec->>'cap_amount')::numeric >= 0
          )
        ),
        false
      );
    when 'tiered_tax' then
      return coalesce(
        jsonb_typeof(p_spec->'taxable_amount') = 'number'
        and (p_spec->>'taxable_amount')::numeric >= 0
        and jsonb_typeof(p_spec->'brackets') = 'array'
        and jsonb_array_length(p_spec->'brackets') > 0,
        false
      );
    when 'attendance_deduction' then
      return coalesce(
        jsonb_typeof(p_spec->'absent_days') = 'number'
        and (p_spec->>'absent_days')::numeric >= 0
        and jsonb_typeof(p_spec->'amount_per_day') = 'number'
        and (p_spec->>'amount_per_day')::numeric >= 0,
        false
      );
    when 'conditional' then
      if jsonb_typeof(p_spec->'condition') <> 'object'
         or jsonb_typeof(p_spec->'then') <> 'object'
         or jsonb_typeof(p_spec->'else') <> 'object'
         or not coalesce(public.payroll_validate_dsl_spec(p_spec->'then'), false)
         or not coalesce(public.payroll_validate_dsl_spec(p_spec->'else'), false) then
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

COMMIT;
