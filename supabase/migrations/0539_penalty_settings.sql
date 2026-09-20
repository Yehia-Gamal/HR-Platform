/* 0539_penalty_settings.sql — إعدادات الغرامات الإدارية
   - جدول penalty_settings (الشرائح، فترات السماح، الحد الأقصى)
   - RPCs: get_penalty_settings, update_penalty_settings
*/
begin;

create table if not exists public.penalty_settings (
  id                uuid primary key default gen_random_uuid(),
  setting_key       text unique not null,
  setting_value     jsonb not null,
  description       text,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.employees(id)
);

alter table public.penalty_settings enable row level security;

do $$ begin
  create policy "HR يقرأ الإعدادات" on public.penalty_settings
    for select using (public.current_is_full_access());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "HR يعدّل الإعدادات" on public.penalty_settings
    for all using (public.current_is_full_access());
exception when duplicate_object then null; end $$;

-- القيم الافتراضية
insert into public.penalty_settings (setting_key, setting_value, description) values
  ('grace_minutes', to_jsonb(15), 'فترة السماح بالدقائق بعد موعد الحضور'),
  ('shift_start', to_jsonb('10:00'::text), 'موعد بداية الدوام'),
  ('tiers', to_jsonb('[{"min_late":16,"max_late":30,"amount":20,"label":"شريحة 20 ج.م"},{"min_late":31,"max_late":60,"amount":50,"label":"شريحة 50 ج.م"},{"min_late":61,"max_late":120,"amount":150,"label":"شريحة 150 ج.م"},{"min_late":121,"max_late":9999,"amount":150,"label":"شريحة 150 ج.م (عدم بصمة)"}]'::jsonb), 'شرائح الغرامات حسب دقائق التأخير'),
  ('doubled_amount', to_jsonb(500), 'مبلغ الغرامة المضاعفة (عدم السداد)'),
  ('max_days_before_escalation', to_jsonb(2), 'عدد الأيام قبل التصعيد إلى مضاعفة'),
  ('auto_checkout_enabled', to_jsonb(true), 'تفعيل الإغلاق التلقائي عند انتهاء المأمورية'),
  ('auto_checkout_time', to_jsonb('18:00'::text), 'وقت الإغلاق التلقائي'),
  ('weekends', to_jsonb('["Friday","Saturday"]'::jsonb), 'أيام العطلة الأسبوعية')
on conflict (setting_key) do nothing;

create or replace function public.get_penalty_settings()
returns table (
  setting_key   text,
  setting_value jsonb,
  description   text,
  updated_at    timestamptz
)
language sql
security definer
set search_path = ''
stable
as $$
  select s.setting_key, s.setting_value, s.description, s.updated_at
  from public.penalty_settings s
  order by s.setting_key;
$$;

create or replace function public.update_penalty_settings(
  p_settings jsonb  -- [{"key":"grace_minutes","value":20}, ...]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp_id uuid;
  v_item jsonb;
begin
  v_emp_id := public.current_employee_id();
  if v_emp_id is null or not public.current_is_full_access() then
    raise exception 'غير مصرح — يتطلب صلاحيات كاملة';
  end if;

  for v_item in select jsonb_array_elements(p_settings)
  loop
    insert into public.penalty_settings (setting_key, setting_value, updated_at, updated_by)
    values (
      v_item->>'key',
      v_item->'value',
      now(),
      v_emp_id
    )
    on conflict (setting_key) do update
    set setting_value = excluded.setting_value,
        updated_at = now(),
        updated_by = excluded.updated_by;
  end loop;
end;
$$;

grant execute on function public.get_penalty_settings() to authenticated;
grant execute on function public.update_penalty_settings(jsonb) to authenticated;

commit;
