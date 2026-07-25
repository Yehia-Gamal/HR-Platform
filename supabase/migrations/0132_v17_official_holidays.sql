-- 0132_v17_official_holidays.sql
-- V17 §1.7: توسيع جدول العطل الرسمية — نطاق (الكل/جهة/إدارة) + استثناءات
-- يعيد استخدام public_holidays (mig 0003) بدلاً من إنشاء جدول جديد.
-- يطابق shared-contracts/holidays.ts: officialHolidaySchema

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. أعمدة V17 على public_holidays
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.public_holidays
  add column if not exists scope text not null default 'all'
    check(scope in ('all','legal_entity','department')),
  add column if not exists department_id uuid references public.departments(id) on delete set null,
  add column if not exists excluded_department_ids uuid[] not null default '{}',
  add column if not exists notes text;

-- تعيين النطاق للبيانات القائمة: إذا كانت legal_entity_id موجودة → legal_entity، وإلا → all
update public.public_holidays
  set scope = case
    when legal_entity_id is not null then 'legal_entity'
    else 'all'
  end
where scope = 'all' and legal_entity_id is not null;

-- قيد تناسق: النطاق legal_entity يتطلب legal_entity_id، والنطاق department يتطلب department_id
alter table public.public_holidays
  add constraint public_holidays_scope_entity_chk
    check(
      (scope = 'all')
      or (scope = 'legal_entity' and legal_entity_id is not null)
      or (scope = 'department' and department_id is not null)
    );

-- فهرس للبحث حسب النطاق والتاريخ
create index if not exists ix_public_holidays_scope_date
  on public.public_holidays(scope, holiday_date);
create index if not exists ix_public_holidays_dept
  on public.public_holidays(department_id) where department_id is not null;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. صلاحية إدارة العطل
-- ═══════════════════════════════════════════════════════════════════════════════

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
  ('holidays.manage','attendance','holidays','manage','إدارة العطل الرسمية: إضافة وتعديل وحذف','sensitive',false)
on conflict(code) do update set
  description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

-- منح لـ HR
insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id, p.id, 'organization', false
from public.roles r
join public.permissions p on p.code = 'holidays.manage'
where r.slug in ('hr-manager','hr-specialist','executive-secretary')
on conflict(role_id,permission_id,scope) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. تشديد RLS — الكتابة تتطلب holidays.manage (لا organization.public_holidays.manage القديمة)
-- ═══════════════════════════════════════════════════════════════════════════════

-- القراءة: كل مسجّل (بيانات مرجعية)
drop policy if exists public_holidays_select on public.public_holidays;
create policy public_holidays_select on public.public_holidays
  for select to authenticated using (true);

-- الكتابة: holidays.manage أو full-access
drop policy if exists public_holidays_insert on public.public_holidays;
create policy public_holidays_insert on public.public_holidays
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('holidays.manage'));

drop policy if exists public_holidays_update on public.public_holidays;
create policy public_holidays_update on public.public_holidays
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('holidays.manage'))
  with check (public.current_is_full_access() or public.has_permission('holidays.manage'));

drop policy if exists public_holidays_delete on public.public_holidays;
create policy public_holidays_delete on public.public_holidays
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('holidays.manage'));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. دالة مساعدة: هل اليوم عطلة رسمية لموظف؟
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.is_official_holiday(
  p_date          date,
  p_employee_id   uuid default null
) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_dept_id  uuid;
  v_entity_id uuid;
begin
  -- استخراج إدارة وجهة الموظف إن وُجد
  if p_employee_id is not null then
    select e.department_id, e.legal_entity_id
      into v_dept_id, v_entity_id
    from public.employees e
    where e.id = p_employee_id and e.is_active and not e.is_deleted;
  end if;

  return exists(
    select 1 from public.public_holidays h
    where h.is_active
      and p_date >= h.holiday_date
      and p_date <= coalesce(h.end_date, h.holiday_date)
      -- نطاق العطلة
      and (
        h.scope = 'all'
        or (h.scope = 'legal_entity' and h.legal_entity_id = v_entity_id)
        or (h.scope = 'department'   and h.department_id = v_dept_id)
      )
      -- استثناءات الإدارات
      and (
        h.excluded_department_ids = '{}'
        or v_dept_id is null
        or not (v_dept_id = any(h.excluded_department_ids))
      )
  );
end;
$$;

revoke execute on function public.is_official_holiday(date, uuid) from public, anon;
grant  execute on function public.is_official_holiday(date, uuid) to authenticated;

comment on function public.is_official_holiday(date, uuid) is
  'V17 §1.7: هل التاريخ المحدد عطلة رسمية للموظف (يراعي النطاق والاستثناءات)';
