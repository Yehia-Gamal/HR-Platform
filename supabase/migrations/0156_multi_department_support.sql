-- =====================================================================
-- 0156: دعم تعدد الإدارات لكل موظف (Multi-Department)
-- =====================================================================
-- الهدف: موظف واحد يمكن أن يعمل في أكثر من إدارة في نفس الوقت.
-- مثال: سكرتير تنفيذي + IT، أو مسؤول مشتريات + محاسب.
--
-- التصميم:
--   1) جدول وسيط employee_departments (many-to-many)
--   2) عمود is_primary لتحديد الإدارة الرئيسية (تزامن مع employees.department_id)
--   3) RLS: القراءة لكل authenticated، الكتابة لمن يملك people.employee.update_sensitive
--   4) RPCs: إضافة/إزالة/جلب إدارات الموظف
--   5) Trigger لمزامنة employees.department_id مع الإدارة الأساسية
--   6) ترحيل البيانات: نقل department_id الحالي للجدول الجديد
-- =====================================================================

-- 1) الجدول الوسيط
create table if not exists public.employee_departments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  job_title text, -- المسمى الوظيفي في هذه الإدارة (اختياري)
  is_primary boolean not null default false,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references auth.users(id),
  note text,
  unique (employee_id, department_id)
);

comment on table public.employee_departments is
  'V17: ربط many-to-many بين الموظفين والإدارات — يسمح لموظف واحد بالعمل في عدة إدارات.';

-- فهارس
create index if not exists idx_employee_departments_employee on public.employee_departments(employee_id);
create index if not exists idx_employee_departments_department on public.employee_departments(department_id);
create index if not exists idx_employee_departments_primary on public.employee_departments(employee_id) where is_primary;

-- 2) RLS
alter table public.employee_departments enable row level security;

-- القراءة: أي مستخدم authenticated
create policy "employee_departments_select" on public.employee_departments
  for select to authenticated using (true);

-- الإدراج: من يملك صلاحية update_sensitive أو full-access
create policy "employee_departments_insert" on public.employee_departments
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive')
  );

-- التعديل: نفس صلاحية الإدراج
create policy "employee_departments_update" on public.employee_departments
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive')
  );

-- الحذف: نفس الصلاحية
create policy "employee_departments_delete" on public.employee_departments
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive')
  );

-- 3) Trigger: عند تغيير is_primary، مزامنة employees.department_id
create or replace function public._sync_primary_department()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- عند وضع إدارة كأساسية، أزل العلامة من الإدارات الأخرى لنفس الموظف
  if new.is_primary then
    update public.employee_departments
      set is_primary = false
    where employee_id = new.employee_id
      and id <> new.id
      and is_primary;

    -- مزامنة employees.department_id
    update public.employees
      set department_id = new.department_id
    where id = new.employee_id;
  end if;

  return new;
end $$;

create trigger trg_sync_primary_department
  after insert or update of is_primary on public.employee_departments
  for each row
  when (new.is_primary)
  execute function public._sync_primary_department();

-- عند حذف الإدارة الأساسية، رقّي أقدم إدارة متبقية أو أفرغ department_id
create or replace function public._on_primary_department_removed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_next uuid;
begin
  if not old.is_primary then return old; end if;

  -- ابحث عن أقدم إدارة متبقية
  select id into v_next
  from public.employee_departments
  where employee_id = old.employee_id and id <> old.id
  order by assigned_at
  limit 1;

  if v_next is not null then
    update public.employee_departments set is_primary = true where id = v_next;
  else
    update public.employees set department_id = null where id = old.employee_id;
  end if;

  return old;
end $$;

create trigger trg_on_primary_department_removed
  after delete on public.employee_departments
  for each row
  when (old.is_primary)
  execute function public._on_primary_department_removed();

-- 4) ترحيل البيانات: نقل department_id الحالي لكل موظف
insert into public.employee_departments (employee_id, department_id, is_primary, note)
select e.id, e.department_id, true, 'ترحيل تلقائي من department_id الأصلي (مهاجرة 0156)'
from public.employees e
where e.department_id is not null
on conflict (employee_id, department_id) do nothing;

-- 5) RPCs

-- جلب إدارات الموظف
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
      'assignedAt', ed.assigned_at
    ) order by ed.is_primary desc, ed.assigned_at
  ), '[]'::jsonb)
  from public.employee_departments ed
  join public.departments d on d.id = ed.department_id
  where ed.employee_id = p_employee_id;
$$;

comment on function public.get_employee_departments(uuid) is
  'V17: جلب كل إدارات الموظف مع بيان الإدارة الأساسية.';

grant execute on function public.get_employee_departments(uuid) to authenticated;

-- إضافة إدارة لموظف
create or replace function public.assign_employee_department(
  p_employee_id uuid,
  p_department_id uuid,
  p_job_title text default null,
  p_is_primary boolean default false,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_has_any boolean;
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

  -- هل لديه إدارات موجودة؟
  select exists(select 1 from public.employee_departments where employee_id = p_employee_id)
    into v_has_any;

  -- إذا لم تكن لديه إدارات سابقة، اجعلها أساسية تلقائياً
  if not v_has_any then
    p_is_primary := true;
  end if;

  insert into public.employee_departments (employee_id, department_id, job_title, is_primary, assigned_by, note)
  values (p_employee_id, p_department_id, p_job_title, p_is_primary, auth.uid(), p_note)
  returning id into v_id;

  return v_id;
end $$;

comment on function public.assign_employee_department(uuid, uuid, text, boolean, text) is
  'V17: إضافة إدارة لموظف (مع اختيار أساسية أم لا).';

grant execute on function public.assign_employee_department(uuid, uuid, text, boolean, text) to authenticated;

-- إزالة إدارة من موظف
create or replace function public.remove_employee_department(
  p_employee_id uuid,
  p_department_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- تحقق من الصلاحية
  if not (public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  delete from public.employee_departments
  where employee_id = p_employee_id and department_id = p_department_id;

  return found;
end $$;

comment on function public.remove_employee_department(uuid, uuid) is
  'V17: إزالة إدارة من موظف. إذا كانت الأساسية تُرقّى التالية تلقائياً.';

grant execute on function public.remove_employee_department(uuid, uuid) to authenticated;

-- تعيين إدارة كأساسية
create or replace function public.set_primary_department(
  p_employee_id uuid,
  p_department_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.employee_departments
    set is_primary = true
  where employee_id = p_employee_id and department_id = p_department_id;

  return found;
end $$;

comment on function public.set_primary_department(uuid, uuid) is
  'V17: تعيين إدارة محددة كإدارة أساسية للموظف.';

grant execute on function public.set_primary_department(uuid, uuid) to authenticated;

-- =====================================================================
-- نهاية Migration 0156
-- =====================================================================
