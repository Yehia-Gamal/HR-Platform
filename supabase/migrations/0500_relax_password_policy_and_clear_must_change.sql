-- ═══════════════════════════════════════════════════════════════════════════
-- 0500: تبسيط سياسة التحقق من قوة كلمة المرور إلى 8 خانات وإلغاء إجبار التغيير
-- ═══════════════════════════════════════════════════════════════════════════
-- تيسير متطلبات كلمة المرور لتكون 8 خانات سهلة ومقبولة، وفتح الحسابات مباشرة.

create or replace function public.validate_password_strength(p_password text)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_issues text[] := '{}';
begin
  if p_password is null or length(p_password) < 8 then
    v_issues := array_append(v_issues, 'يجب أن تكون 8 أحرف على الأقل');
  end if;
  if length(p_password) > 72 then
    v_issues := array_append(v_issues, 'يجب ألا تتجاوز 72 حرفًا');
  end if;
  if p_password ~ '(.)\1{4,}' then
    v_issues := array_append(v_issues, 'تكرار مفرط لنفس الحرف (5+ متتالية)');
  end if;

  return jsonb_build_object(
    'valid', cardinality(v_issues) = 0,
    'issues', to_jsonb(v_issues)
  );
end $$;

comment on function public.validate_password_strength(text) is
  '0500: تحقق مبسط من قوة كلمة المرور (الحد الأدنى 8 خانات سهلة ومقبولة).';

revoke all on function public.validate_password_strength(text) from public, anon;
grant execute on function public.validate_password_strength(text) to authenticated;

-- إزالة علامة must_change_password من كافة الحسابات السابقة لتفتح مباشرة فور تسجيل الدخول
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'must_change_password'
where raw_app_meta_data ? 'must_change_password';
