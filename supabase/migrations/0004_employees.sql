-- Migration 0004: employees_profiles_accounts (الموظفون والملفات والحسابات)
--
-- Depends on:
--   0002: public.current_is_full_access(), public.has_permission(text),
--         public.has_any_permission(text[]), public.can_access_employee(uuid),
--         public.current_employee_id()
--   0003: organization tables (branches, departments, teams, work_sites,
--         job_titles, positions, grades, employment_types, roles)
--   auth.users
--
-- Conventions: every table has id uuid pk, created_at, updated_at, created_by.
-- RLS enabled on every table with explicit policies. UTC timestamps. Idempotent.

-- =====================================================================
-- Helper: generic updated_at trigger function (idempotent create)
-- =====================================================================
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.tg_set_updated_at() is
  'Trigger helper: sets updated_at = now() on UPDATE.';

-- =====================================================================
-- Table: employees
-- =====================================================================
create table if not exists public.employees (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users(id) on delete set null,
  employee_code      text not null,
  full_name_ar       text not null,
  full_name_en       text,
  phone_e164         text,
  gender             text check (gender in ('male','female')),
  birth_date         date,
  national_id_enc    bytea,
  nationality        text,
  job_title_id       uuid references public.job_titles(id) on delete set null,
  position_id        uuid references public.positions(id) on delete set null,
  grade_id           uuid references public.job_grades(id) on delete set null,
  department_id      uuid references public.departments(id) on delete set null,
  team_id            uuid references public.teams(id) on delete set null,
  branch_id          uuid references public.branches(id) on delete set null,
  work_site_id       uuid references public.work_sites(id) on delete set null,
  employment_type_id uuid references public.employment_types(id) on delete set null,
  hire_date          date,
  contract_end       date,
  probation_end      date,
  status             text not null default 'draft'
                       check (status in (
                         'draft','invited','onboarding','active','suspended',
                         'notice_period','terminated','archived','probation_failed'
                       )),
  is_active          boolean not null default true,
  is_deleted         boolean not null default false,
  photo_url          text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);

comment on table public.employees is
  'السجل الرئيسي للموظفين: البيانات الشخصية والوظيفية والتنظيمية وحالة التوظيف.';

-- employee_code unique
create unique index if not exists ux_employees_employee_code
  on public.employees (employee_code);

-- phone_e164 unique only among active (is_active = true) rows
create unique index if not exists ux_employees_phone_e164_active
  on public.employees (phone_e164)
  where phone_e164 is not null and is_active = true;

-- user_id unique among linked rows (حساب واحد ↔ موظف واحد) — يمنع ازدواج current_employee_id
create unique index if not exists ux_employees_user_id
  on public.employees (user_id)
  where user_id is not null;

-- Common lookup indexes
create index if not exists ix_employees_user_id       on public.employees (user_id);
create index if not exists ix_employees_department_id on public.employees (department_id);
create index if not exists ix_employees_team_id       on public.employees (team_id);
create index if not exists ix_employees_branch_id     on public.employees (branch_id);
create index if not exists ix_employees_status        on public.employees (status);
create index if not exists ix_employees_is_deleted    on public.employees (is_deleted);

drop trigger if exists trg_employees_updated_at on public.employees;
create trigger trg_employees_updated_at
  before update on public.employees
  for each row execute function public.tg_set_updated_at();

-- Trigger: protect job/organizational columns from tampering by self-service
-- users. can_access_employee (including the employee themselves) grants UPDATE
-- via RLS for personal fields only; changing sensitive job fields requires
-- full access or the people.employee.update_sensitive permission.
create or replace function public.tg_employees_protect_job_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.current_is_full_access()
     or public.has_permission('people.employee.update_sensitive') then
    return new;
  end if;

  -- Onboarding managers may perform only the two controlled lifecycle
  -- transitions used by the server-authoritative onboarding RPC. No other
  -- sensitive field may change in the same statement.
  if public.has_permission('onboarding.journey.manage')
     and new.status is distinct from old.status
     and ((old.status in ('draft','invited') and new.status = 'onboarding')
          or (old.status = 'onboarding' and new.status = 'active'))
     and new.employee_code is not distinct from old.employee_code
     and new.department_id is not distinct from old.department_id
     and new.team_id is not distinct from old.team_id
     and new.branch_id is not distinct from old.branch_id
     and new.work_site_id is not distinct from old.work_site_id
     and new.job_title_id is not distinct from old.job_title_id
     and new.position_id is not distinct from old.position_id
     and new.grade_id is not distinct from old.grade_id
     and new.employment_type_id is not distinct from old.employment_type_id
     and new.hire_date is not distinct from old.hire_date
     and new.contract_end is not distinct from old.contract_end
     and new.user_id is not distinct from old.user_id then
    return new;
  end if;

  -- The employee may become active only after their own onboarding journey is
  -- completed by the controlled task RPC. All other sensitive fields must remain unchanged.
  if old.id = public.current_employee_id()
     and old.status = 'onboarding' and new.status = 'active'
     and exists (
       select 1 from public.onboarding_journeys j
       where j.employee_id = old.id and j.status = 'completed'
     )
     and new.employee_code is not distinct from old.employee_code
     and new.department_id is not distinct from old.department_id
     and new.team_id is not distinct from old.team_id
     and new.branch_id is not distinct from old.branch_id
     and new.work_site_id is not distinct from old.work_site_id
     and new.job_title_id is not distinct from old.job_title_id
     and new.position_id is not distinct from old.position_id
     and new.grade_id is not distinct from old.grade_id
     and new.employment_type_id is not distinct from old.employment_type_id
     and new.hire_date is not distinct from old.hire_date
     and new.contract_end is not distinct from old.contract_end
     and new.user_id is not distinct from old.user_id then
    return new;
  end if;

  if new.employee_code is distinct from old.employee_code then
    raise exception 'not authorized to change employee_code' using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    raise exception 'not authorized to change status' using errcode = '42501';
  end if;
  if new.department_id is distinct from old.department_id then
    raise exception 'not authorized to change department_id' using errcode = '42501';
  end if;
  if new.team_id is distinct from old.team_id then
    raise exception 'not authorized to change team_id' using errcode = '42501';
  end if;
  if new.branch_id is distinct from old.branch_id then
    raise exception 'not authorized to change branch_id' using errcode = '42501';
  end if;
  if new.work_site_id is distinct from old.work_site_id then
    raise exception 'not authorized to change work_site_id' using errcode = '42501';
  end if;
  if new.job_title_id is distinct from old.job_title_id then
    raise exception 'not authorized to change job_title_id' using errcode = '42501';
  end if;
  if new.position_id is distinct from old.position_id then
    raise exception 'not authorized to change position_id' using errcode = '42501';
  end if;
  if new.grade_id is distinct from old.grade_id then
    raise exception 'not authorized to change grade_id' using errcode = '42501';
  end if;
  if new.employment_type_id is distinct from old.employment_type_id then
    raise exception 'not authorized to change employment_type_id' using errcode = '42501';
  end if;
  if new.hire_date is distinct from old.hire_date then
    raise exception 'not authorized to change hire_date' using errcode = '42501';
  end if;
  if new.contract_end is distinct from old.contract_end then
    raise exception 'not authorized to change contract_end' using errcode = '42501';
  end if;
  if new.user_id is distinct from old.user_id then
    raise exception 'not authorized to change user_id' using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.tg_employees_protect_job_fields() is
  'يمنع غير المصرّح لهم (بما فيهم الموظف نفسه) من تعديل الأعمدة الوظيفية/التنظيمية الحساسة في employees. يُسمح بالتعديل فقط لمن يملك full access أو people.employee.update_sensitive؛ غير ذلك يقتصر على الحقول الشخصية.';

drop trigger if exists trg_employees_protect_job_fields on public.employees;
create trigger trg_employees_protect_job_fields
  before update on public.employees
  for each row execute function public.tg_employees_protect_job_fields();

alter table public.employees enable row level security;

-- SELECT: full access, employees.read permission, or scoped via can_access_employee
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(id)
    or public.has_permission('employees.read')
  );

drop policy if exists employees_insert on public.employees;
create policy employees_insert on public.employees
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.create')
  );

-- UPDATE: row access granted to full access, people.employee.update_basic with
-- scope (can_access_employee), or the employee editing their own row. Sensitive
-- job/organizational columns are protected by trg_employees_protect_job_fields,
-- which requires full access or people.employee.update_sensitive to change them.
drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees
  for update to authenticated
  using (
    public.current_is_full_access()
    or (public.has_permission('people.employee.update_basic') and public.can_access_employee(id))
    or id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or (public.has_permission('people.employee.update_basic') and public.can_access_employee(id))
    or id = public.current_employee_id()
  );

-- DELETE: no self-delete. Only full access or explicit delete permission,
-- and never your own employee row.
drop policy if exists employees_delete on public.employees;
create policy employees_delete on public.employees
  for delete to authenticated
  using (
    (public.current_is_full_access() or public.has_permission('employees.delete'))
    and id is distinct from public.current_employee_id()
  );

-- =====================================================================
-- Table: profiles  (id = auth.uid())
-- =====================================================================
create table if not exists public.profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  employee_id        uuid references public.employees(id) on delete set null,
  -- primary_role_id: للعرض فقط (chip/theme). مصدر الحقيقة للصلاحيات هو user_roles حصراً.
  primary_role_id    uuid references public.roles(id) on delete set null,
  status             text not null default 'active'
                       check (status in ('active','suspended','disabled','pending')),
  temporary_password boolean not null default false,
  branch_id          uuid references public.branches(id) on delete set null,
  department_id      uuid references public.departments(id) on delete set null,
  team_id            uuid references public.teams(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);

comment on table public.profiles is
  'ملف حساب المستخدم المرتبط بـ auth.users. primary_role_id للعرض فقط — مصدر الصلاحيات هو user_roles. الأعمدة الحساسة (primary_role_id, status, employee_id, temporary_password) محمية بـtrigger.';

-- employee_id فريد: موظف واحد ↔ profile واحد (يمنع ازدواج current_employee_id)
create unique index if not exists ux_profiles_employee_id
  on public.profiles (employee_id)
  where employee_id is not null;
create index if not exists ix_profiles_role_id      on public.profiles (primary_role_id);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.tg_set_updated_at();

-- Trigger: protect sensitive columns from privilege escalation by non-admins.
-- A user without full access / profiles.manage cannot change their own or
-- anyone's role_id, status, employee_id, or temporary_password.
create or replace function public.tg_profiles_protect_sensitive()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.current_is_full_access() or public.has_permission('profiles.manage') then
    return new;
  end if;

  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'not authorized to change primary_role_id' using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    raise exception 'not authorized to change status' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'not authorized to change employee_id' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password then
    raise exception 'not authorized to change temporary_password' using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.tg_profiles_protect_sensitive() is
  'يمنع غير المصرّح لهم من تعديل الأعمدة الحساسة في profiles (role_id, status, employee_id, temporary_password).';

drop trigger if exists trg_profiles_protect_sensitive on public.profiles;
create trigger trg_profiles_protect_sensitive
  before update on public.profiles
  for each row execute function public.tg_profiles_protect_sensitive();

alter table public.profiles enable row level security;

-- SELECT: own profile, full access, or profiles.read
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.current_is_full_access()
    or public.has_permission('profiles.read')
  );

-- INSERT: only admins / managers (profiles are usually created via provisioning)
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('profiles.manage')
  );

-- UPDATE: own profile (sensitive columns blocked by trigger) or admins.
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (
    id = auth.uid()
    or public.current_is_full_access()
    or public.has_permission('profiles.manage')
  )
  with check (
    id = auth.uid()
    or public.current_is_full_access()
    or public.has_permission('profiles.manage')
  );

-- DELETE: no self-delete; admins only.
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete to authenticated
  using (
    (public.current_is_full_access() or public.has_permission('profiles.manage'))
    and id is distinct from auth.uid()
  );

-- =====================================================================
-- Table: manager_relations
-- =====================================================================
create table if not exists public.manager_relations (
  id                  uuid primary key default gen_random_uuid(),
  employee_id         uuid not null references public.employees(id) on delete cascade,
  manager_employee_id uuid not null references public.employees(id) on delete cascade,
  relation_type       text not null default 'primary'
                        check (relation_type in ('primary','functional','dotted')),
  effective_from      date not null default current_date,
  effective_to        date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id),
  constraint ck_manager_not_self check (employee_id <> manager_employee_id),
  constraint ck_manager_dates check (effective_to is null or effective_to >= effective_from)
);

comment on table public.manager_relations is
  'علاقات الإدارة بين الموظفين (مباشر/وظيفي/منقّط) مع صلاحية زمنية.';

create index if not exists ix_manager_relations_employee on public.manager_relations (employee_id);
create index if not exists ix_manager_relations_manager  on public.manager_relations (manager_employee_id);

-- Only one active primary manager per employee at a time
create unique index if not exists ux_manager_relations_primary_active
  on public.manager_relations (employee_id)
  where relation_type = 'primary' and effective_to is null;

drop trigger if exists trg_manager_relations_updated_at on public.manager_relations;
create trigger trg_manager_relations_updated_at
  before update on public.manager_relations
  for each row execute function public.tg_set_updated_at();

alter table public.manager_relations enable row level security;

drop policy if exists manager_relations_select on public.manager_relations;
create policy manager_relations_select on public.manager_relations
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or public.can_access_employee(manager_employee_id)
    or public.has_permission('employees.read')
  );

drop policy if exists manager_relations_insert on public.manager_relations;
create policy manager_relations_insert on public.manager_relations
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

drop policy if exists manager_relations_update on public.manager_relations;
create policy manager_relations_update on public.manager_relations
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

drop policy if exists manager_relations_delete on public.manager_relations;
create policy manager_relations_delete on public.manager_relations
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.delete')
  );

-- =====================================================================
-- Table: employee_assignments  (transfer / promote history)
-- =====================================================================
create table if not exists public.employee_assignments (
  id                    uuid primary key default gen_random_uuid(),
  employee_id           uuid not null references public.employees(id) on delete cascade,
  assignment_type       text not null
                          check (assignment_type in (
                            'transfer','promote','demote','reassign','onboarding'
                          )),
  effective_date        date not null default current_date,
  -- from/to snapshots of organizational placement
  from_department_id    uuid references public.departments(id) on delete set null,
  to_department_id      uuid references public.departments(id) on delete set null,
  from_team_id          uuid references public.teams(id) on delete set null,
  to_team_id            uuid references public.teams(id) on delete set null,
  from_branch_id        uuid references public.branches(id) on delete set null,
  to_branch_id          uuid references public.branches(id) on delete set null,
  from_position_id      uuid references public.positions(id) on delete set null,
  to_position_id        uuid references public.positions(id) on delete set null,
  from_job_title_id     uuid references public.job_titles(id) on delete set null,
  to_job_title_id       uuid references public.job_titles(id) on delete set null,
  from_grade_id         uuid references public.job_grades(id) on delete set null,
  to_grade_id           uuid references public.job_grades(id) on delete set null,
  reason                text,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id)
);

comment on table public.employee_assignments is
  'سجل حركات الموظف: النقل والترقية والتخفيض وإعادة التعيين مع لقطات قبل/بعد للموضع التنظيمي.';

create index if not exists ix_employee_assignments_employee on public.employee_assignments (employee_id);
create index if not exists ix_employee_assignments_type     on public.employee_assignments (assignment_type);
create index if not exists ix_employee_assignments_date     on public.employee_assignments (effective_date);

drop trigger if exists trg_employee_assignments_updated_at on public.employee_assignments;
create trigger trg_employee_assignments_updated_at
  before update on public.employee_assignments
  for each row execute function public.tg_set_updated_at();

alter table public.employee_assignments enable row level security;

drop policy if exists employee_assignments_select on public.employee_assignments;
create policy employee_assignments_select on public.employee_assignments
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or public.has_permission('employees.read')
  );

drop policy if exists employee_assignments_insert on public.employee_assignments;
create policy employee_assignments_insert on public.employee_assignments
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

drop policy if exists employee_assignments_update on public.employee_assignments;
create policy employee_assignments_update on public.employee_assignments
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

drop policy if exists employee_assignments_delete on public.employee_assignments;
create policy employee_assignments_delete on public.employee_assignments
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.delete')
  );

-- =====================================================================
-- Table: employee_documents
-- =====================================================================
create table if not exists public.employee_documents (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  doc_type       text not null,
  title          text,
  doc_number     text,
  issue_date     date,
  expiry         date,
  storage_path   text not null,
  is_verified    boolean not null default false,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id)
);

comment on table public.employee_documents is
  'وثائق الموظف (الهوية/العقود/الشهادات...) مع تاريخ الانتهاء ومسار التخزين في storage.';

create index if not exists ix_employee_documents_employee on public.employee_documents (employee_id);
create index if not exists ix_employee_documents_type     on public.employee_documents (doc_type);
create index if not exists ix_employee_documents_expiry   on public.employee_documents (expiry);

drop trigger if exists trg_employee_documents_updated_at on public.employee_documents;
create trigger trg_employee_documents_updated_at
  before update on public.employee_documents
  for each row execute function public.tg_set_updated_at();

alter table public.employee_documents enable row level security;

drop policy if exists employee_documents_select on public.employee_documents;
create policy employee_documents_select on public.employee_documents
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or public.has_permission('documents.read')
  );

drop policy if exists employee_documents_insert on public.employee_documents;
create policy employee_documents_insert on public.employee_documents
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('documents.manage')
    or public.can_access_employee(employee_id)
  );

drop policy if exists employee_documents_update on public.employee_documents;
create policy employee_documents_update on public.employee_documents
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('documents.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('documents.manage')
  );

drop policy if exists employee_documents_delete on public.employee_documents;
create policy employee_documents_delete on public.employee_documents
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('documents.manage')
  );

-- =====================================================================
-- Table: employee_skills
-- =====================================================================
create table if not exists public.employee_skills (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references public.employees(id) on delete cascade,
  skill_name         text not null,
  proficiency_level  text check (proficiency_level in (
                        'beginner','intermediate','advanced','expert'
                      )),
  years_experience   numeric(4,1),
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);

comment on table public.employee_skills is
  'مهارات الموظف ومستوى الإتقان وسنوات الخبرة.';

create index if not exists ix_employee_skills_employee on public.employee_skills (employee_id);
create unique index if not exists ux_employee_skills_employee_skill
  on public.employee_skills (employee_id, lower(skill_name));

drop trigger if exists trg_employee_skills_updated_at on public.employee_skills;
create trigger trg_employee_skills_updated_at
  before update on public.employee_skills
  for each row execute function public.tg_set_updated_at();

alter table public.employee_skills enable row level security;

drop policy if exists employee_skills_select on public.employee_skills;
create policy employee_skills_select on public.employee_skills
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or public.has_permission('employees.read')
  );

drop policy if exists employee_skills_insert on public.employee_skills;
create policy employee_skills_insert on public.employee_skills
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  );

drop policy if exists employee_skills_update on public.employee_skills;
create policy employee_skills_update on public.employee_skills
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  );

drop policy if exists employee_skills_delete on public.employee_skills;
create policy employee_skills_delete on public.employee_skills
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

-- =====================================================================
-- Table: employee_certifications
-- =====================================================================
create table if not exists public.employee_certifications (
  id                  uuid primary key default gen_random_uuid(),
  employee_id         uuid not null references public.employees(id) on delete cascade,
  certification_name  text not null,
  issuing_authority   text,
  certificate_number  text,
  issue_date          date,
  expiry              date,
  storage_path        text,
  is_verified         boolean not null default false,
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id)
);

comment on table public.employee_certifications is
  'شهادات الموظف المهنية مع جهة الإصدار وتاريخ الانتهاء ومسار الملف.';

create index if not exists ix_employee_certifications_employee on public.employee_certifications (employee_id);
create index if not exists ix_employee_certifications_expiry   on public.employee_certifications (expiry);

drop trigger if exists trg_employee_certifications_updated_at on public.employee_certifications;
create trigger trg_employee_certifications_updated_at
  before update on public.employee_certifications
  for each row execute function public.tg_set_updated_at();

alter table public.employee_certifications enable row level security;

drop policy if exists employee_certifications_select on public.employee_certifications;
create policy employee_certifications_select on public.employee_certifications
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or public.has_permission('employees.read')
  );

drop policy if exists employee_certifications_insert on public.employee_certifications;
create policy employee_certifications_insert on public.employee_certifications
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  );

drop policy if exists employee_certifications_update on public.employee_certifications;
create policy employee_certifications_update on public.employee_certifications
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(employee_id)
  );

drop policy if exists employee_certifications_delete on public.employee_certifications;
create policy employee_certifications_delete on public.employee_certifications
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('employees.update')
  );

-- =====================================================================
-- RPC: set employee status (audited transition)
-- =====================================================================
create or replace function public.set_employee_status(
  p_employee_id uuid,
  p_status      text
)
returns public.employees
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.employees;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'not authorized to change employee status' using errcode = '42501';
  end if;

  if p_status not in (
    'draft','invited','onboarding','active','suspended',
    'notice_period','terminated','archived','probation_failed'
  ) then
    raise exception 'invalid status value: %', p_status using errcode = '22023';
  end if;

  update public.employees
     set status     = p_status,
         is_active  = (p_status = 'active'),
         updated_at = now()
   where id = p_employee_id
  returning * into v_row;

  if not found then
    raise exception 'employee not found: %', p_employee_id using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;

comment on function public.set_employee_status(uuid, text) is
  'تغيير حالة الموظف مع فحص الصلاحيات وتحديث is_active تبعاً للحالة.';

revoke execute on function public.set_employee_status(uuid, text) from public;
grant execute on function public.set_employee_status(uuid, text) to authenticated;

-- =====================================================================
-- RPC: soft delete employee (no self-delete)
-- =====================================================================
create or replace function public.soft_delete_employee(
  p_employee_id uuid
)
returns public.employees
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.employees;
begin
  if not (public.current_is_full_access() or public.has_permission('employees.delete')) then
    raise exception 'not authorized to delete employee' using errcode = '42501';
  end if;

  if p_employee_id is not distinct from public.current_employee_id() then
    raise exception 'self-delete is not allowed' using errcode = '42501';
  end if;

  update public.employees
     set is_deleted = true,
         is_active  = false,
         status     = 'archived',
         updated_at = now()
   where id = p_employee_id
  returning * into v_row;

  if not found then
    raise exception 'employee not found: %', p_employee_id using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;

comment on function public.soft_delete_employee(uuid) is
  'حذف ناعم للموظف (is_deleted=true, archived) مع منع الحذف الذاتي وفحص الصلاحيات.';

revoke execute on function public.soft_delete_employee(uuid) from public;
grant execute on function public.soft_delete_employee(uuid) to authenticated;

-- =====================================================================
-- إعادة التعريف الحقيقي لدوال التخويل المعتمدة على employees/profiles
-- (كانت نسخاً مؤقتة آمنة في 0002 قبل وجود الجداول).
-- =====================================================================

-- current_employee_id: نسخة نهائية (profiles موجود الآن)
create or replace function public.current_employee_id()
returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$
  select p.employee_id from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.current_employee_id() from public;
grant execute on function public.current_employee_id() to authenticated;

-- =====================================================================
-- دوال النطاق (Scope) الحقيقية — تحترم scope في role_permissions + scope_override
-- تُستخدم في سياسات RLS للجداول الحساسة بدل has_permission وحدها.
-- =====================================================================

-- هل يستطيع المستخدم الوصول لموظف ضمن نطاق صلاحية معيّنة؟
-- يفحص أوسع نطاق ممنوح للمستخدم عبر أي دور يحمل الصلاحية p_code.
-- Keep this overload strictly two-argument. The compatibility overload from
-- 0002 accepts one UUID; a default here makes one-argument calls ambiguous.
create or replace function public.can_access_employee(p_employee_id uuid, p_code text)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_me    uuid;
  v_scope text;
  v_ovr   jsonb;
  v_target_dept uuid;
  v_target_branch uuid;
  v_target_team uuid;
begin
  -- full-access يرى الكل
  if public.current_is_full_access() then return true; end if;

  v_me := public.current_employee_id();

  -- الذات دائماً مسموحة
  if v_me is not null and v_me = p_employee_id then return true; end if;

  -- لو لم تُحدَّد صلاحية، نكتفي بـ self + مدير مباشر (سلوك آمن افتراضي)
  if p_code is null then
    return exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = p_employee_id and mr.manager_employee_id = v_me
        and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;

  -- بيانات الموظف الهدف
  select department_id, branch_id, team_id
    into v_target_dept, v_target_branch, v_target_team
    from public.employees where id = p_employee_id;

  -- افحص كل دور فعّال يحمل الصلاحية p_code، وطبّق أوسع نطاق
  for v_scope, v_ovr in
    select rp.scope, ur.scope_override
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = p_code
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
  loop
    if v_scope = 'organization' then
      return true;
    elsif v_scope = 'self' then
      if v_me = p_employee_id then return true; end if;
    elsif v_scope in ('direct_reports','management_descendants') then
      if exists (
        select 1 from public.manager_relations mr
        where mr.employee_id = p_employee_id and mr.manager_employee_id = v_me
          and (mr.effective_to is null or mr.effective_to > now())
      ) then return true; end if;
    elsif v_scope = 'department' then
      if v_target_dept is not null and v_target_dept = (
        select e.department_id from public.employees e where e.id = v_me
      ) then return true; end if;
    elsif v_scope = 'branch' then
      if v_target_branch is not null and v_target_branch = (
        select e.branch_id from public.employees e where e.id = v_me
      ) then return true; end if;
    elsif v_scope = 'team' then
      if v_target_team is not null and v_target_team = (
        select e.team_id from public.employees e where e.id = v_me
      ) then return true; end if;
    elsif v_scope = 'selected_departments' then
      if v_ovr ? 'department_ids' and (v_ovr->'department_ids') ? v_target_dept::text then return true; end if;
    elsif v_scope = 'selected_branches' then
      if v_ovr ? 'branch_ids' and (v_ovr->'branch_ids') ? v_target_branch::text then return true; end if;
    elsif v_scope = 'selected_employees' then
      if v_ovr ? 'employee_ids' and (v_ovr->'employee_ids') ? p_employee_id::text then return true; end if;
    end if;
  end loop;

  return false;
end;
$$;
revoke execute on function public.can_access_employee(uuid, text) from public;
grant execute on function public.can_access_employee(uuid, text) to authenticated;

comment on function public.can_access_employee(uuid, text) is
  'فحص وصول لموظف يحترم نطاق (scope) الصلاحية p_code وscope_override. النسخة ذات المعامل الواحد (0002) تبقى للتوافق (self + مدير مباشر فقط).';
