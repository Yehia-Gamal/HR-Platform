-- Migration 0003: organization (المؤسسة والهيكل)
-- Depends on: 0001 (extensions: pgcrypto/gen_random_uuid), 0002 (permissions/roles + permission functions)
-- Reuses only functions defined in 0002:
--   public.current_is_full_access(), public.has_permission(text), public.has_any_permission(text[]),
--   public.can_access_employee(uuid), public.current_employee_id()
-- All timestamps are UTC (timestamptz). Idempotent where practical.

begin;

-- =====================================================================
-- Shared trigger function: maintain updated_at (UTC now())
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

comment on function public.tg_set_updated_at() is 'Trigger helper: sets updated_at = now() (UTC) on row update.';

-- =====================================================================
-- 1. legal_entities  (الكيانات القانونية)
-- =====================================================================
create table if not exists public.legal_entities (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name             text not null,
  name_en          text,
  legal_form        text,                 -- الشكل القانوني (نص، وليس enum)
  registration_no   text,                 -- السجل التجاري
  tax_number        text,                 -- الرقم الضريبي
  country_code      text not null default 'SA',
  currency_code     text not null default 'SAR',
  timezone          text not null default 'Asia/Riyadh',
  address           text,
  phone             text,
  email             text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint legal_entities_code_key unique (code)
);

comment on table public.legal_entities is 'الكيانات القانونية للمؤسسة (الشركات المسجلة).';
create index if not exists idx_legal_entities_active on public.legal_entities(is_active);

-- =====================================================================
-- 2. branches  (الفروع)
-- =====================================================================
create table if not exists public.branches (
  id                uuid primary key default gen_random_uuid(),
  legal_entity_id   uuid not null references public.legal_entities(id) on delete restrict,
  code              text not null,
  name             text not null,
  name_en          text,
  city              text,
  region            text,
  address           text,
  phone             text,
  timezone          text not null default 'Asia/Riyadh',
  is_headquarters   boolean not null default false,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint branches_entity_code_key unique (legal_entity_id, code)
);

comment on table public.branches is 'فروع الكيانات القانونية.';
create index if not exists idx_branches_entity on public.branches(legal_entity_id);
create index if not exists idx_branches_active on public.branches(is_active);

-- =====================================================================
-- 3. work_sites  (مواقع العمل)
-- =====================================================================
create table if not exists public.work_sites (
  id                uuid primary key default gen_random_uuid(),
  branch_id         uuid not null references public.branches(id) on delete restrict,
  code              text not null,
  name             text not null,
  name_en          text,
  site_type         text,                 -- نوع الموقع (مكتب/مصنع/مستودع...) كنص
  address           text,
  latitude          double precision,
  longitude         double precision,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint work_sites_branch_code_key unique (branch_id, code),
  constraint work_sites_lat_chk check (latitude is null or (latitude between -90 and 90)),
  constraint work_sites_lon_chk check (longitude is null or (longitude between -180 and 180))
);

comment on table public.work_sites is 'مواقع العمل الفعلية التابعة للفروع.';
create index if not exists idx_work_sites_branch on public.work_sites(branch_id);
create index if not exists idx_work_sites_active on public.work_sites(is_active);

-- =====================================================================
-- 4. cost_centers  (مراكز التكلفة)
-- =====================================================================
create table if not exists public.cost_centers (
  id                uuid primary key default gen_random_uuid(),
  legal_entity_id   uuid not null references public.legal_entities(id) on delete restrict,
  parent_id         uuid references public.cost_centers(id) on delete set null,
  code              text not null,
  name             text not null,
  name_en          text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint cost_centers_entity_code_key unique (legal_entity_id, code),
  constraint cost_centers_no_self_parent check (parent_id is null or parent_id <> id)
);

comment on table public.cost_centers is 'مراكز التكلفة (هرمية عبر parent_id).';
create index if not exists idx_cost_centers_entity on public.cost_centers(legal_entity_id);
create index if not exists idx_cost_centers_parent on public.cost_centers(parent_id);

-- =====================================================================
-- 8. job_titles  (المسميات الوظيفية) -- defined before positions (FK)
-- =====================================================================
create table if not exists public.job_titles (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name             text not null,
  name_en          text,
  description       text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint job_titles_code_key unique (code)
);

comment on table public.job_titles is 'المسميات الوظيفية (lookup).';
create index if not exists idx_job_titles_active on public.job_titles(is_active);

-- =====================================================================
-- 9. job_grades  (الدرجات الوظيفية) -- defined before positions (FK)
-- =====================================================================
create table if not exists public.job_grades (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name             text not null,
  name_en          text,
  level             integer not null default 1,          -- ترتيب الدرجة
  min_salary        numeric(14,2),
  max_salary        numeric(14,2),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint job_grades_code_key unique (code),
  constraint job_grades_salary_chk check (
    min_salary is null or max_salary is null or max_salary >= min_salary
  )
);

comment on table public.job_grades is 'الدرجات الوظيفية ونطاقات الرواتب (lookup).';
create index if not exists idx_job_grades_active on public.job_grades(is_active);
create index if not exists idx_job_grades_level on public.job_grades(level);

-- =====================================================================
-- 5. departments  (الإدارات) -- self manager relation for org_chart
-- =====================================================================
create table if not exists public.departments (
  id                uuid primary key default gen_random_uuid(),
  legal_entity_id   uuid not null references public.legal_entities(id) on delete restrict,
  branch_id         uuid references public.branches(id) on delete set null,
  cost_center_id    uuid references public.cost_centers(id) on delete set null,
  parent_id         uuid references public.departments(id) on delete set null,   -- org_chart: hierarchy
  manager_id        uuid,                                                        -- org_chart: manager (employees table added in later migration)
  code              text not null,
  name             text not null,
  name_en           text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint departments_entity_code_key unique (legal_entity_id, code),
  constraint departments_no_self_parent check (parent_id is null or parent_id <> id)
);

comment on table public.departments is 'الإدارات/الأقسام. parent_id وmanager_id يشكلان org_chart. manager_id يربط بجدول الموظفين في migration لاحق.';
create index if not exists idx_departments_entity on public.departments(legal_entity_id);
create index if not exists idx_departments_parent on public.departments(parent_id);
create index if not exists idx_departments_branch on public.departments(branch_id);
create index if not exists idx_departments_manager on public.departments(manager_id);

-- =====================================================================
-- 6. teams  (الفِرق) -- lead relation for org_chart
-- =====================================================================
create table if not exists public.teams (
  id                uuid primary key default gen_random_uuid(),
  department_id     uuid not null references public.departments(id) on delete cascade,
  parent_id         uuid references public.teams(id) on delete set null,
  lead_id           uuid,                                                        -- org_chart: team lead (employees later)
  code              text not null,
  name             text not null,
  name_en           text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint teams_dept_code_key unique (department_id, code),
  constraint teams_no_self_parent check (parent_id is null or parent_id <> id)
);

comment on table public.teams is 'الفِرق داخل الإدارات. lead_id يربط بجدول الموظفين في migration لاحق (org_chart).';
create index if not exists idx_teams_department on public.teams(department_id);
create index if not exists idx_teams_parent on public.teams(parent_id);
create index if not exists idx_teams_lead on public.teams(lead_id);

-- =====================================================================
-- 7. positions  (الوظائف/الشواغر) -- reports_to for org_chart
-- =====================================================================
create table if not exists public.positions (
  id                    uuid primary key default gen_random_uuid(),
  department_id         uuid not null references public.departments(id) on delete restrict,
  team_id               uuid references public.teams(id) on delete set null,
  job_title_id          uuid references public.job_titles(id) on delete set null,
  job_grade_id          uuid references public.job_grades(id) on delete set null,
  cost_center_id        uuid references public.cost_centers(id) on delete set null,
  reports_to_position_id uuid references public.positions(id) on delete set null, -- org_chart
  code                  text not null,
  name                 text not null,
  name_en               text,
  headcount             integer not null default 1,
  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  constraint positions_code_key unique (code),
  constraint positions_no_self_report check (reports_to_position_id is null or reports_to_position_id <> id),
  constraint positions_headcount_chk check (headcount >= 0)
);

comment on table public.positions is 'الوظائف الهيكلية. reports_to_position_id يبني org_chart على مستوى الوظائف.';
create index if not exists idx_positions_department on public.positions(department_id);
create index if not exists idx_positions_team on public.positions(team_id);
create index if not exists idx_positions_reports_to on public.positions(reports_to_position_id);
create index if not exists idx_positions_job_title on public.positions(job_title_id);

-- =====================================================================
-- 10. employment_types  (أنواع التوظيف)
-- =====================================================================
create table if not exists public.employment_types (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name             text not null,        -- مثال: دوام كامل، دوام جزئي، عقد مؤقت
  name_en           text,
  is_full_time      boolean not null default true,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint employment_types_code_key unique (code)
);

comment on table public.employment_types is 'أنواع التوظيف (lookup): دوام كامل/جزئي/عقد ...';
create index if not exists idx_employment_types_active on public.employment_types(is_active);

-- =====================================================================
-- 11. geofences  (النطاقات الجغرافية) lat/lon/radius/max_accuracy
-- =====================================================================
create table if not exists public.geofences (
  id                uuid primary key default gen_random_uuid(),
  work_site_id      uuid references public.work_sites(id) on delete cascade,
  code              text not null,
  name             text not null,
  latitude          double precision not null,
  longitude         double precision not null,
  radius_meters     numeric(10,2) not null,               -- نصف قطر النطاق بالمتر
  max_accuracy      numeric(10,2),                         -- أقصى دقة GPS مقبولة (متر)
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint geofences_code_key unique (code),
  constraint geofences_lat_chk check (latitude between -90 and 90),
  constraint geofences_lon_chk check (longitude between -180 and 180),
  constraint geofences_radius_chk check (radius_meters > 0),
  constraint geofences_accuracy_chk check (max_accuracy is null or max_accuracy > 0)
);

comment on table public.geofences is 'النطاقات الجغرافية لتحديد مواقع الحضور (خط عرض/طول/نصف قطر/أقصى دقة).';
create index if not exists idx_geofences_work_site on public.geofences(work_site_id);
create index if not exists idx_geofences_active on public.geofences(is_active);

-- =====================================================================
-- 12. shifts  (الورديات)
-- =====================================================================
create table if not exists public.shifts (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null,
  name                 text not null,
  name_en               text,
  start_time            time not null,
  end_time              time not null,
  crosses_midnight      boolean not null default false,     -- وردية تعبر منتصف الليل
  break_minutes         integer not null default 0,
  grace_in_minutes      integer not null default 0,          -- سماحية التأخير
  grace_out_minutes     integer not null default 0,
  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  constraint shifts_code_key unique (code),
  constraint shifts_break_chk check (break_minutes >= 0),
  constraint shifts_grace_in_chk check (grace_in_minutes >= 0),
  constraint shifts_grace_out_chk check (grace_out_minutes >= 0)
);

comment on table public.shifts is 'تعريف الورديات وأوقاتها وسماحياتها.';
create index if not exists idx_shifts_active on public.shifts(is_active);

-- =====================================================================
-- 13. shift_patterns  (أنماط الورديات)
-- =====================================================================
create table if not exists public.shift_patterns (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  name             text not null,
  name_en           text,
  description       text,
  cycle_days        integer not null default 7,             -- طول دورة النمط بالأيام
  -- جدول أيام النمط: مصفوفة JSON [{day_index:int, shift_id:uuid|null, is_rest:bool}]
  pattern           jsonb not null default '[]'::jsonb,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint shift_patterns_code_key unique (code),
  constraint shift_patterns_cycle_chk check (cycle_days between 1 and 366)
);

comment on table public.shift_patterns is 'أنماط تكرار الورديات (دورات أسبوعية/مخصصة) مخزّنة في pattern (jsonb).';
create index if not exists idx_shift_patterns_active on public.shift_patterns(is_active);

-- =====================================================================
-- 14. public_holidays  (الإجازات الرسمية)
-- =====================================================================
create table if not exists public.public_holidays (
  id                uuid primary key default gen_random_uuid(),
  legal_entity_id   uuid references public.legal_entities(id) on delete cascade,
  name             text not null,
  name_en           text,
  holiday_date      date not null,
  end_date          date,                                    -- لإجازات متعددة الأيام
  is_recurring      boolean not null default false,          -- تتكرر سنوياً
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint public_holidays_date_chk check (end_date is null or end_date >= holiday_date),
  constraint public_holidays_entity_date_name_key unique (legal_entity_id, holiday_date, name)
);

comment on table public.public_holidays is 'الإجازات الرسمية (عامة أو لكل كيان قانوني).';
create index if not exists idx_public_holidays_entity on public.public_holidays(legal_entity_id);
create index if not exists idx_public_holidays_date on public.public_holidays(holiday_date);

-- =====================================================================
-- 15. working_calendars  (تقاويم العمل)
-- =====================================================================
create table if not exists public.working_calendars (
  id                uuid primary key default gen_random_uuid(),
  legal_entity_id   uuid references public.legal_entities(id) on delete cascade,
  branch_id         uuid references public.branches(id) on delete set null,
  code              text not null,
  name             text not null,
  name_en           text,
  -- أيام العمل الأسبوعية (0=الأحد ... 6=السبت) كمصفوفة أعداد
  working_weekdays  integer[] not null default '{0,1,2,3,4}'::integer[],
  weekly_off_days   integer[] not null default '{5,6}'::integer[],
  default_shift_id  uuid references public.shifts(id) on delete set null,
  shift_pattern_id  uuid references public.shift_patterns(id) on delete set null,
  timezone          text not null default 'Asia/Riyadh',
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint working_calendars_code_key unique (code)
);

comment on table public.working_calendars is 'تقاويم العمل: أيام العمل الأسبوعية والعطلات والوردية الافتراضية لكل كيان/فرع.';
create index if not exists idx_working_calendars_entity on public.working_calendars(legal_entity_id);
create index if not exists idx_working_calendars_branch on public.working_calendars(branch_id);

-- =====================================================================
-- updated_at triggers (idempotent via drop-if-exists)
-- =====================================================================
do $$
declare
  t text;
  tables text[] := array[
    'legal_entities','branches','work_sites','cost_centers','departments',
    'teams','positions','job_titles','job_grades','employment_types',
    'geofences','shifts','shift_patterns','public_holidays','working_calendars'
  ];
begin
  foreach t in array tables loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s;', t);
    execute format(
      'create trigger trg_%1$s_updated_at before update on public.%1$s
         for each row execute function public.tg_set_updated_at();', t);
  end loop;
end;
$$;

-- =====================================================================
-- Row Level Security + Policies
-- Read: any authenticated user (lookups readable).
-- Write (insert/update/delete): full access OR organization.<table>.manage.
-- =====================================================================
do $$
declare
  t text;
  tables text[] := array[
    'legal_entities','branches','work_sites','cost_centers','departments',
    'teams','positions','job_titles','job_grades','employment_types',
    'geofences','shifts','shift_patterns','public_holidays','working_calendars'
  ];
  manage_perm text;
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('alter table public.%I force row level security;', t);

    manage_perm := 'organization.' || t || '.manage';

    -- drop existing (idempotent)
    execute format('drop policy if exists %I on public.%I;', t || '_select_authenticated', t);
    execute format('drop policy if exists %I on public.%I;', t || '_insert_manage', t);
    execute format('drop policy if exists %I on public.%I;', t || '_update_manage', t);
    execute format('drop policy if exists %I on public.%I;', t || '_delete_manage', t);

    -- SELECT: authenticated read
    execute format($p$
      create policy %I on public.%I
      for select to authenticated
      using (true);
    $p$, t || '_select_authenticated', t);

    -- INSERT: manage permission (no WITH CHECK(true) — explicit permission gate)
    execute format($p$
      create policy %I on public.%I
      for insert to authenticated
      with check (public.current_is_full_access() or public.has_permission(%L));
    $p$, t || '_insert_manage', t, manage_perm);

    -- UPDATE: manage permission
    execute format($p$
      create policy %I on public.%I
      for update to authenticated
      using (public.current_is_full_access() or public.has_permission(%L))
      with check (public.current_is_full_access() or public.has_permission(%L));
    $p$, t || '_update_manage', t, manage_perm, manage_perm);

    -- DELETE: manage permission
    execute format($p$
      create policy %I on public.%I
      for delete to authenticated
      using (public.current_is_full_access() or public.has_permission(%L));
    $p$, t || '_delete_manage', t, manage_perm);
  end loop;
end;
$$;

-- =====================================================================
-- RPC: public.get_org_chart(root uuid) — org_chart عبر manager relations
-- Returns department hierarchy (parent/manager) as recursive tree rows.
-- SECURITY DEFINER, locked to authenticated.
-- =====================================================================
create or replace function public.get_org_chart(p_root uuid default null)
returns table (
  id            uuid,
  parent_id     uuid,
  manager_id    uuid,
  name          text,
  legal_entity_id uuid,
  depth         integer,
  path          uuid[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with recursive tree as (
    select d.id, d.parent_id, d.manager_id, d.name, d.legal_entity_id,
           0 as depth, array[d.id] as path
    from public.departments d
    where (p_root is null and d.parent_id is null)
       or (p_root is not null and d.id = p_root)
    union all
    select c.id, c.parent_id, c.manager_id, c.name, c.legal_entity_id,
           t.depth + 1, t.path || c.id
    from public.departments c
    join tree t on c.parent_id = t.id
    where not c.id = any(t.path)   -- guard against cycles
  )
  select id, parent_id, manager_id, name, legal_entity_id, depth, path
  from tree
  order by path;
$$;

comment on function public.get_org_chart(uuid) is 'يبني org_chart لشجرة الإدارات (parent/manager) بدءاً من جذر اختياري.';

revoke execute on function public.get_org_chart(uuid) from public;
grant execute on function public.get_org_chart(uuid) to authenticated;

-- =====================================================================
-- geofences SELECT policy override (تقييد القراءة)
-- الافتراضي في اللوب أعلاه أنشأ سياسة select using(true) لكل الجداول.
-- geofences يكشف إحداثيات مواقع الحضور، لذا نقيّد القراءة: full-access
-- أو من يملك إحدى صلاحيات إدارة/قراءة الحضور فقط (وليس كل authenticated).
-- =====================================================================
drop policy if exists geofences_select_authenticated on public.geofences;
create policy geofences_select_restricted on public.geofences
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['attendance.geofence.manage','attendance.record.read'])
  );

comment on policy geofences_select_restricted on public.geofences is
  'قراءة geofences مقيّدة: full-access أو attendance.geofence.manage / attendance.record.read (ليست متاحة لكل authenticated).';

-- =====================================================================
-- Deferred foreign keys → employees (org_chart)
-- departments.manager_id و teams.lead_id يشيران إلى public.employees(id)،
-- لكن جدول employees يُنشأ في migration 0004. لذلك تُضاف هذه القيود هنا
-- بعد تعريف الأعمدة، وتُطبَّق فعلياً فقط بعد وجود employees.
-- نستخدم DO block يتحقق من وجود جدول employees ومن عدم وجود القيد قبل إضافته
-- (idempotent — لن يفشل عند إعادة التشغيل أو لو أُضيف القيد مسبقاً).
-- ملاحظة: إن طُبّق 0003 قبل 0004 لن يوجد employees بعد، وسيتم تخطّي الإضافة؛
-- تُعاد إضافة القيود عند إعادة تطبيق هذا الملف بعد إنشاء employees، أو تُضاف
-- صراحةً في 0004. الشرط أدناه يجعل التشغيل آمناً في كلا الحالتين.
-- =====================================================================
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'employees'
  ) then
    -- departments.manager_id → employees(id)
    if not exists (
      select 1 from pg_constraint where conname = 'departments_manager_id_fkey'
    ) then
      alter table public.departments
        add constraint departments_manager_id_fkey
        foreign key (manager_id) references public.employees(id) on delete set null;
    end if;

    -- teams.lead_id → employees(id)
    if not exists (
      select 1 from pg_constraint where conname = 'teams_lead_id_fkey'
    ) then
      alter table public.teams
        add constraint teams_lead_id_fkey
        foreign key (lead_id) references public.employees(id) on delete set null;
    end if;
  end if;
end;
$$;

commit;
