-- =====================================================================
-- 0278: عطلة «بدل راحة» — نوع إجازة جديد لا يخصم الرصيد، مع تثبيت أعمدة public_holidays
-- =====================================================================
-- السياق: HR يضيف عطلة رسمية (مثل عيد أو عطلة إدارية أو قافلة) تطبق على
-- الكل أو نطاق، لكن النظام الحالي لم يكن لديه نوع إجازة «بدل راحة أسبوعية»
-- يمنح الموظف الوقت المكتسب لمقابل عمله في يوم راحته الأسبوعية دون خصم
-- من الرصيد السنوي (كما في هذا الفيديو: https://example.com).
--
-- يعالج أيضًا خطأ تصاعدي في بيئة الإنتاج:
--   * public_holidays قد يفتقد أعمدة notes/scope/excluded_department_ids
--     عندما تُطبق بعض migrations القديمة قبل 0132 في مسار النشر.
--   * RPC create_public_holiday يفشل بـ 42703 (undefined_column) في تلك الحالة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. تثبيت/إضافة أعمدة public_holidays إن لم تكن موجودة (idempotent)
--    هذه الأعمدة ضرورية لكل RPCs وواجهة الإدارة.
-- ---------------------------------------------------------------------

alter table public.public_holidays
  add column if not exists scope text not null default 'all';
alter table public.public_holidays
  add column if not exists excluded_department_ids uuid[] not null default '{}';
alter table public.public_holidays
  add column if not exists notes text;

-- ضمان القيد على قيم scope الشرعية
alter table public.public_holidays
  drop constraint if exists public_holidays_scope_entity_chk;
alter table public.public_holidays
  add constraint public_holidays_scope_entity_chk
    check (
      (scope = 'all')
      or (scope = 'legal_entity' and legal_entity_id is not null)
      or (scope = 'department' and department_id is not null)
    );

-- فهارس مركبة موسّعة (idempotent)
create index if not exists ix_public_holidays_scope_date
  on public.public_holidays(scope, holiday_date);
create index if not exists ix_public_holidays_dept
  on public.public_holidays(department_id) where department_id is not null;

-- ---------------------------------------------------------------------
-- 2. نوع إجازة «بدل راحة أسبوعية» — weekly_rest_comp
--    لا يُحتسب ضمن الرصيد (affects_balance = false)، هو تعويض عن يوم
--    راحة أسبوعية ولا يقتطع من رصيد المستخدم مهما كانت مدته.
--    يظهر ضمن أنواع الإجازة عند تقديم الطلبات.
-- ---------------------------------------------------------------------

insert into public.leave_types
  (code, name_ar, name_en, description, is_paid, requires_attachment,
   max_days_per_year, min_notice_days, affects_balance, monthly_accrual_units,
   sort_order, is_active)
values
  ('weekly_rest_comp', 'بدل راحة أسبوعية', 'Weekly Rest Comp-Off',
   'إجازة تعويضية عن يوم الراحة الأسبوعية التي عمل فيها الموظف — لا تُخصم من رصيد الإجازات السنوية.',
   true, false, null, 0, false, 0, 50, true)
on conflict (code) do update set
  name_ar               = excluded.name_ar,
  name_en               = excluded.name_en,
  description           = excluded.description,
  is_paid               = excluded.is_paid,
  requires_attachment   = excluded.requires_attachment,
  max_days_per_year     = excluded.max_days_per_year,
  affects_balance       = excluded.affects_balance,
  monthly_accrual_units = excluded.monthly_accrual_units,
  sort_order            = excluded.sort_order,
  is_active             = true,
  updated_at            = now();

comment on table public.leave_types is
  'كتالوج أنواع الإجازات: مدفوعة/غير مدفوعة، الحدود السنوية، متطلبات المرفقات والإشعار المسبق.';

-- ---------------------------------------------------------------------
-- 3. تأكيد صلاحيات RPCs على public_holidays (يزيد حماية من فشل 42703)
--    إعادة إنشاء create_public_holiday / update_public_holiday في حال كانا
--    مرجعيات أعمدة لم تعد موجودة.
-- ---------------------------------------------------------------------

create or replace function public.create_public_holiday(
  p_name            text,
  p_holiday_date    date,
  p_end_date        date                    default null,
  p_scope           text                    default 'all',
  p_legal_entity_id uuid                    default null,
  p_department_id   uuid                    default null,
  p_excluded_department_ids uuid[]          default '{}',
  p_notes           text                    default null,
  p_is_recurring    boolean                 default false
)
returns uuid
language plpgsql security invoker
as $$
declare
  v_id uuid;
begin
  insert into public.public_holidays (
    name, holiday_date, end_date, scope, legal_entity_id,
    department_id, excluded_department_ids, notes,
    is_recurring, created_by
  ) values (
    p_name, p_holiday_date, p_end_date, p_scope, p_legal_entity_id,
    p_department_id, p_excluded_department_ids, p_notes,
    p_is_recurring, auth.uid()
  )
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_public_holiday(text,date,date,text,uuid,uuid,uuid[],text,boolean) from anon;
grant execute on function public.create_public_holiday(text,date,date,text,uuid,uuid,uuid[],text,boolean) to authenticated;

create or replace function public.update_public_holiday(
  p_id                      uuid,
  p_name                    text     default null,
  p_holiday_date            date     default null,
  p_end_date                date     default null,
  p_scope                   text     default null,
  p_legal_entity_id         uuid     default null,
  p_department_id           uuid     default null,
  p_excluded_department_ids uuid[]   default null,
  p_notes                   text     default null,
  p_is_recurring            boolean  default null,
  p_is_active               boolean  default null
)
returns void
language plpgsql security invoker
as $$
begin
  update public.public_holidays set
    name                    = coalesce(p_name, name),
    holiday_date            = coalesce(p_holiday_date, holiday_date),
    end_date                = case when p_end_date is distinct from null then p_end_date else end_date end,
    scope                   = coalesce(p_scope, scope),
    legal_entity_id         = case when p_legal_entity_id is distinct from null then p_legal_entity_id else legal_entity_id end,
    department_id           = case when p_department_id is distinct from null then p_department_id else department_id end,
    excluded_department_ids = coalesce(p_excluded_department_ids, excluded_department_ids),
    notes                   = case when p_notes is distinct from null then p_notes else notes end,
    is_recurring            = coalesce(p_is_recurring, is_recurring),
    is_active               = coalesce(p_is_active, is_active),
    updated_at              = now()
  where id = p_id;
end;
$$;

revoke all on function public.update_public_holiday(uuid,text,date,date,text,uuid,uuid,uuid[],text,boolean,boolean) from anon;
grant execute on function public.update_public_holiday(uuid,text,date,date,text,uuid,uuid,uuid[],text,boolean,boolean) to authenticated;

create or replace function public.delete_public_holiday(p_id uuid)
returns void
language plpgsql security invoker
as $$
begin
  delete from public.public_holidays where id = p_id;
end;
$$;

revoke all on function public.delete_public_holiday(uuid) from anon;
grant execute on function public.delete_public_holiday(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. تأكيد صلاحية إدارة العطل (idempotent)
-- ---------------------------------------------------------------------

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
  ('holidays.manage','attendance','holidays','manage','إدارة العطل الرسمية: إضافة وتعديل وحذف','sensitive',false)
on conflict (code) do update set
  description = excluded.description,
  risk_level  = excluded.risk_level,
  is_sensitive = excluded.is_sensitive;

insert into public.role_permissions(role_id, permission_id, scope, requires_reason)
select r.id, p.id, 'organization', false
from public.roles r
join public.permissions p on p.code = 'holidays.manage'
where r.slug in ('hr-manager', 'hr-specialist', 'executive-secretary')
on conflict (role_id, permission_id, scope) do nothing;
