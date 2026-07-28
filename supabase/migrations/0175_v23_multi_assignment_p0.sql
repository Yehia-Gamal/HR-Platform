-- =====================================================================
-- 0173: V23 §6 — توسيع employee_departments لدعم التعيينات المتعددة P0
--
-- المرجع: V22 §6 (الموظف متعدد الإدارات والوظائف)
-- الجدول employee_departments (0156) يدعم many-to-many مع is_primary.
-- هذه المهاجرة تضيف الحقول المتبقية لـ P0:
--   • allocation_percentage — نسبة التخصيص (افتراضي 100 للأساسي)
--   • start_date / end_date — فترة التعيين
--   • functional_manager_id — المدير الوظيفي الثانوي (اختياري)
--
-- التراجع: DROP COLUMN allocation_percentage, start_date, end_date,
--   functional_manager_id من employee_departments
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- 1) إضافة الأعمدة الجديدة
-- ═══════════════════════════════════════════════════════════════════════
alter table public.employee_departments
  add column if not exists allocation_percentage integer
    not null default 100
    constraint chk_allocation_range check (allocation_percentage between 1 and 100);

alter table public.employee_departments
  add column if not exists start_date date not null default current_date;

alter table public.employee_departments
  add column if not exists end_date date;

alter table public.employee_departments
  add column if not exists functional_manager_id uuid
    references public.employees(id) on delete set null;

comment on column public.employee_departments.allocation_percentage is
  'V23 §6: نسبة التخصيص (1–100%). الأساسي افتراضيًا 100%.';

comment on column public.employee_departments.start_date is
  'V23 §6: تاريخ بداية التعيين في هذه الإدارة.';

comment on column public.employee_departments.end_date is
  'V23 §6: تاريخ نهاية التعيين (NULL = مستمر).';

comment on column public.employee_departments.functional_manager_id is
  'V23 §6: المدير الوظيفي الثانوي في هذه الإدارة (اختياري).';

-- فهرس على المدير الوظيفي لاستعلامات "من يعمل تحتي وظيفياً"
create index if not exists idx_employee_departments_functional_mgr
  on public.employee_departments(functional_manager_id)
  where functional_manager_id is not null;

-- فهرس على التعيينات النشطة (end_date is null أو في المستقبل)
create index if not exists idx_employee_departments_active
  on public.employee_departments(employee_id)
  where end_date is null;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) تحديث assign_employee_department لدعم الحقول الجديدة
-- ═══════════════════════════════════════════════════════════════════════
-- حذف التحميل الزائد القديم (5 params من 0156) لمنع تضارب الدوال
drop function if exists public.assign_employee_department(uuid, uuid, text, boolean, text);

create or replace function public.assign_employee_department(
  p_employee_id uuid,
  p_department_id uuid,
  p_job_title text default null,
  p_is_primary boolean default false,
  p_note text default null,
  p_allocation_percentage integer default null,
  p_start_date date default null,
  p_end_date date default null,
  p_functional_manager_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_has_any boolean;
  v_alloc integer;
begin
  -- تحقق من الصلاحية
  if not (public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- تحقق من وجود الموظف والإدارة
  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'DEPARTMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- تحقق من المدير الوظيفي إذا حُدد
  if p_functional_manager_id is not null
     and not exists (select 1 from public.employees where id = p_functional_manager_id and is_active) then
    raise exception 'FUNCTIONAL_MANAGER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- هل لديه إدارات موجودة؟
  select exists(select 1 from public.employee_departments where employee_id = p_employee_id)
    into v_has_any;

  -- إذا لم تكن لديه إدارات سابقة، اجعلها أساسية تلقائياً
  if not v_has_any then
    p_is_primary := true;
  end if;

  -- نسبة التخصيص: الأساسي = 100 افتراضيًا
  v_alloc := coalesce(p_allocation_percentage,
    case when p_is_primary then 100 else 50 end);

  insert into public.employee_departments (
    employee_id, department_id, job_title, is_primary, assigned_by, note,
    allocation_percentage, start_date, end_date, functional_manager_id
  )
  values (
    p_employee_id, p_department_id, p_job_title, p_is_primary, auth.uid(), p_note,
    v_alloc, coalesce(p_start_date, current_date), p_end_date, p_functional_manager_id
  )
  on conflict (employee_id, department_id) do update set
    job_title = coalesce(excluded.job_title, public.employee_departments.job_title),
    is_primary = excluded.is_primary,
    allocation_percentage = excluded.allocation_percentage,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    functional_manager_id = excluded.functional_manager_id,
    note = excluded.note,
    assigned_by = excluded.assigned_by
  returning id into v_id;

  return v_id;
end $$;

comment on function public.assign_employee_department(uuid, uuid, text, boolean, text, integer, date, date, uuid) is
  'V23 §6: إضافة أو تحديث تعيين إدارة لموظف — مع نسبة تخصيص ومدير وظيفي وفترة.';

revoke execute on function public.assign_employee_department(uuid, uuid, text, boolean, text, integer, date, date, uuid) from public;
grant execute on function public.assign_employee_department(uuid, uuid, text, boolean, text, integer, date, date, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) تحديث get_employee_departments لإرجاع الحقول الجديدة
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_employee_departments(p_employee_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ed.id,
      'departmentId', ed.department_id,
      'departmentName', d.name,
      'jobTitle', ed.job_title,
      'isPrimary', ed.is_primary,
      'assignedAt', ed.assigned_at,
      'allocationPercentage', ed.allocation_percentage,
      'startDate', ed.start_date,
      'endDate', ed.end_date,
      'functionalManagerId', ed.functional_manager_id,
      'functionalManagerName', fm.full_name_ar
    ) order by ed.is_primary desc, ed.assigned_at
  ), '[]'::jsonb)
  from public.employee_departments ed
  join public.departments d on d.id = ed.department_id
  left join public.employees fm on fm.id = ed.functional_manager_id
  where ed.employee_id = p_employee_id
    and (ed.end_date is null or ed.end_date >= current_date);
$$;

comment on function public.get_employee_departments(uuid) is
  'V23 §6: جلب كل تعيينات الموظف النشطة مع بيان التخصيص والمدير الوظيفي.';

-- الصلاحية الأصلية محفوظة
grant execute on function public.get_employee_departments(uuid) to authenticated;
