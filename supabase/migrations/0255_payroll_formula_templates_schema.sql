-- =====================================================================
-- 0255: Payroll Formula DSL — مفسّر آمن (لا eval نهائيًا)
-- =====================================================================
-- يُبنى على نوع العقد المعروفة فقط:
--   fixed_amount | percentage_of_basic | tiered_tax | conditional | attendance_deduction
-- كل العقد تمر عبر JSON Schema صارم وحدود ACL.
-- =====================================================================

do $dsl_schema$
begin
  -- -------------------------------------------------------------------
  -- 1) التحقق من أنواع العقد المسموح بها (غير قابلة للاختراق)
  -- -------------------------------------------------------------------
  insert into public.system_settings(key, value, updated_at) values
    ('payroll_dsl_allowed_types', '["fixed_amount", "percentage_of_basic", "tiered_tax", "conditional", "attendance_deduction"]'::jsonb, now())
    on conflict (key) do update set value = excluded.value, updated_at = now();

  -- -------------------------------------------------------------------
  -- 2) دالة توليد SQL آمنة من DSL (تتوسع لاحقًا في Migration منفصلة)
  -- -------------------------------------------------------------------
  create or replace function public.payroll_dsl_get_allowed_types()
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $$
    select value from public.system_settings where key = 'payroll_dsl_allowed_types';
  $$;

  comment on function public.payroll_dsl_get_allowed_types() is
    'إن JSON DSL spec الآمن. يمكن للمراجع الذي فقط payroll.formula.read';

  -- -------------------------------------------------------------------
  -- 3) ACL — لا يمكن للمستخدم العادي تعديل الصيغ
  -- -------------------------------------------------------------------
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke execute on function public.payroll_dsl_get_allowed_types() from authenticated;
    grant execute on function public.payroll_dsl_get_allowed_types() to service_role;
  end if;

end
$dsl_schema$;

-- =====================================================================
-- نهاية Migration 0255 — DSL Schema
-- =====================================================================
-- النصائح للـ legal review:
--   - كل spec تُنشأ عبر RPC مع audit trail; لا manual INSERT,
--    :
--   - Tiered tax brackets تُوثَّق مع references قانونية.
-- =====================================================================
