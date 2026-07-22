-- Migration 0009: المستندات والمهام والسياسات والتشغيل

-- =====================================================================
-- Shared trigger function: set updated_at on every UPDATE
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

-- =====================================================================
-- Table: documents
-- =====================================================================
create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  owner_employee_id uuid not null references public.employees(id) on delete cascade,
  doc_type text not null check (doc_type in ('contract','id','passport','certificate','visa','iqama','medical','other')),
  title text not null,
  storage_path text not null,
  expiry_date date,
  status text not null default 'active' check (status in ('active','expired','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.documents is 'مستندات الموظفين مع مسار التخزين وتاريخ الانتهاء';

create index if not exists idx_documents_owner on public.documents(owner_employee_id);
create index if not exists idx_documents_status on public.documents(status);

alter table public.documents enable row level security;

drop trigger if exists trg_documents_updated_at on public.documents;
create trigger trg_documents_updated_at before update on public.documents
  for each row execute function public.tg_set_updated_at();

drop policy if exists documents_select on public.documents;
create policy documents_select on public.documents
  for select to authenticated
  using (public.can_access_employee(owner_employee_id) or public.has_permission('documents.read'));

drop policy if exists documents_insert on public.documents;
create policy documents_insert on public.documents
  for insert to authenticated
  with check (public.can_access_employee(owner_employee_id) or public.has_permission('documents.write'));

drop policy if exists documents_update on public.documents;
create policy documents_update on public.documents
  for update to authenticated
  using (public.can_access_employee(owner_employee_id) or public.has_permission('documents.write'))
  with check (public.can_access_employee(owner_employee_id) or public.has_permission('documents.write'));

drop policy if exists documents_delete on public.documents;
create policy documents_delete on public.documents
  for delete to authenticated
  using (public.has_permission('documents.write') or public.current_is_full_access());

-- =====================================================================
-- Table: attachments
-- =====================================================================
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  storage_path text not null,
  mime text,
  size_bytes bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.attachments is 'المرفقات العامة المرتبطة بكيانات أخرى عبر النوع والمعرف';

create index if not exists idx_attachments_entity on public.attachments(entity_type, entity_id);

alter table public.attachments enable row level security;

drop trigger if exists trg_attachments_updated_at on public.attachments;
create trigger trg_attachments_updated_at before update on public.attachments
  for each row execute function public.tg_set_updated_at();

drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
  for select to authenticated
  using (public.has_any_permission(array['attachments.read','documents.read']) or created_by = auth.uid());

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (public.has_permission('attachments.write') or created_by = auth.uid());

drop policy if exists attachments_update on public.attachments;
create policy attachments_update on public.attachments
  for update to authenticated
  using (public.has_permission('attachments.write') or created_by = auth.uid())
  with check (public.has_permission('attachments.write') or created_by = auth.uid());

drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete to authenticated
  using (public.has_permission('attachments.write') or created_by = auth.uid() or public.current_is_full_access());

-- =====================================================================
-- Table: tasks
-- =====================================================================
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  assignee_employee_id uuid references public.employees(id) on delete set null,
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  due_date date,
  status text not null default 'pending' check (status in ('pending','in_progress','done','cancelled')),
  created_by_employee_id uuid references public.employees(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.tasks is 'المهام المسندة للموظفين مع الأولوية والحالة';

create index if not exists idx_tasks_assignee on public.tasks(assignee_employee_id);
create index if not exists idx_tasks_status on public.tasks(status);

alter table public.tasks enable row level security;

drop trigger if exists trg_tasks_updated_at on public.tasks;
create trigger trg_tasks_updated_at before update on public.tasks
  for each row execute function public.tg_set_updated_at();

drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated
  using (
    assignee_employee_id = public.current_employee_id()
    or created_by_employee_id = public.current_employee_id()
    or public.has_permission('tasks.read')
  );

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (public.has_permission('tasks.write') or created_by_employee_id = public.current_employee_id());

drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks
  for update to authenticated
  using (
    assignee_employee_id = public.current_employee_id()
    or created_by_employee_id = public.current_employee_id()
    or public.has_permission('tasks.write')
  )
  with check (
    assignee_employee_id = public.current_employee_id()
    or created_by_employee_id = public.current_employee_id()
    or public.has_permission('tasks.write')
  );

drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks
  for delete to authenticated
  using (public.has_permission('tasks.write') or public.current_is_full_access());

-- =====================================================================
-- Table: task_templates
-- =====================================================================
create table if not exists public.task_templates (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  tasks jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.task_templates is 'قوالب المهام القابلة لإعادة الاستخدام';

alter table public.task_templates enable row level security;

drop trigger if exists trg_task_templates_updated_at on public.task_templates;
create trigger trg_task_templates_updated_at before update on public.task_templates
  for each row execute function public.tg_set_updated_at();

drop policy if exists task_templates_select on public.task_templates;
create policy task_templates_select on public.task_templates
  for select to authenticated
  using (true);

drop policy if exists task_templates_insert on public.task_templates;
create policy task_templates_insert on public.task_templates
  for insert to authenticated
  with check (public.has_permission('tasks.write'));

drop policy if exists task_templates_update on public.task_templates;
create policy task_templates_update on public.task_templates
  for update to authenticated
  using (public.has_permission('tasks.write'))
  with check (public.has_permission('tasks.write'));

drop policy if exists task_templates_delete on public.task_templates;
create policy task_templates_delete on public.task_templates
  for delete to authenticated
  using (public.has_permission('tasks.write') or public.current_is_full_access());

-- =====================================================================
-- Table: policies
-- =====================================================================
create table if not exists public.policies (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text,
  version text not null default '1.0',
  status text not null default 'draft' check (status in ('draft','published')),
  body text,
  requires_acknowledgement boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.policies is 'سياسات المنظمة مع الإصدار والحالة ومتطلب الإقرار';

create index if not exists idx_policies_status on public.policies(status);

alter table public.policies enable row level security;

drop trigger if exists trg_policies_updated_at on public.policies;
create trigger trg_policies_updated_at before update on public.policies
  for each row execute function public.tg_set_updated_at();

drop policy if exists policies_select_published on public.policies;
create policy policies_select_published on public.policies
  for select to authenticated
  using (status = 'published');

drop policy if exists policies_select_manage on public.policies;
create policy policies_select_manage on public.policies
  for select to authenticated
  using (public.has_permission('documents.policy.publish') or public.current_is_full_access());

drop policy if exists policies_insert on public.policies;
create policy policies_insert on public.policies
  for insert to authenticated
  with check (public.has_permission('documents.policy.publish'));

drop policy if exists policies_update on public.policies;
create policy policies_update on public.policies
  for update to authenticated
  using (public.has_permission('documents.policy.publish'))
  with check (public.has_permission('documents.policy.publish'));

drop policy if exists policies_delete on public.policies;
create policy policies_delete on public.policies
  for delete to authenticated
  using (public.has_permission('documents.policy.publish') or public.current_is_full_access());

-- =====================================================================
-- Table: policy_acknowledgements
-- =====================================================================
create table if not exists public.policy_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references public.policies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique (policy_id, employee_id)
);
comment on table public.policy_acknowledgements is 'إقرارات الموظفين على السياسات';

create index if not exists idx_policy_ack_employee on public.policy_acknowledgements(employee_id);

alter table public.policy_acknowledgements enable row level security;

drop trigger if exists trg_policy_ack_updated_at on public.policy_acknowledgements;
create trigger trg_policy_ack_updated_at before update on public.policy_acknowledgements
  for each row execute function public.tg_set_updated_at();

drop policy if exists policy_ack_select on public.policy_acknowledgements;
create policy policy_ack_select on public.policy_acknowledgements
  for select to authenticated
  using (public.can_access_employee(employee_id) or public.has_permission('documents.policy.publish'));

drop policy if exists policy_ack_insert on public.policy_acknowledgements;
create policy policy_ack_insert on public.policy_acknowledgements
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

drop policy if exists policy_ack_delete on public.policy_acknowledgements;
create policy policy_ack_delete on public.policy_acknowledgements
  for delete to authenticated
  using (public.has_permission('documents.policy.publish') or public.current_is_full_access());

-- =====================================================================
-- Table: daily_reports
-- =====================================================================
create table if not exists public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  report_date date not null default current_date,
  achievements text,
  blockers text,
  tomorrow_plan text,
  manager_comment text,
  reviewed_by uuid references public.employees(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.daily_reports is 'التقارير اليومية للموظفين مع مراجعة المدير';

create index if not exists idx_daily_reports_employee on public.daily_reports(employee_id);
create index if not exists idx_daily_reports_date on public.daily_reports(report_date);

alter table public.daily_reports enable row level security;

drop trigger if exists trg_daily_reports_updated_at on public.daily_reports;
create trigger trg_daily_reports_updated_at before update on public.daily_reports
  for each row execute function public.tg_set_updated_at();

drop policy if exists daily_reports_select on public.daily_reports;
create policy daily_reports_select on public.daily_reports
  for select to authenticated
  using (public.can_access_employee(employee_id) or public.has_permission('reports.read'));

drop policy if exists daily_reports_insert on public.daily_reports;
create policy daily_reports_insert on public.daily_reports
  for insert to authenticated
  with check (employee_id = public.current_employee_id() or public.has_permission('reports.write'));

drop policy if exists daily_reports_update on public.daily_reports;
create policy daily_reports_update on public.daily_reports
  for update to authenticated
  using (public.can_access_employee(employee_id) or public.has_permission('reports.write'))
  with check (public.can_access_employee(employee_id) or public.has_permission('reports.write'));

drop policy if exists daily_reports_delete on public.daily_reports;
create policy daily_reports_delete on public.daily_reports
  for delete to authenticated
  using (public.has_permission('reports.write') or public.current_is_full_access());

-- =====================================================================
-- Table: asset_inventory
-- =====================================================================
create table if not exists public.asset_inventory (
  id uuid primary key default gen_random_uuid(),
  asset_type text not null,
  serial text,
  name_ar text not null,
  status text not null default 'available' check (status in ('available','assigned','retired')),
  condition text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.asset_inventory is 'جرد الأصول والعهد';

create index if not exists idx_asset_inventory_status on public.asset_inventory(status);

alter table public.asset_inventory enable row level security;

drop trigger if exists trg_asset_inventory_updated_at on public.asset_inventory;
create trigger trg_asset_inventory_updated_at before update on public.asset_inventory
  for each row execute function public.tg_set_updated_at();

drop policy if exists asset_inventory_select on public.asset_inventory;
create policy asset_inventory_select on public.asset_inventory
  for select to authenticated
  using (true);

drop policy if exists asset_inventory_insert on public.asset_inventory;
create policy asset_inventory_insert on public.asset_inventory
  for insert to authenticated
  with check (public.has_permission('assets.write'));

drop policy if exists asset_inventory_update on public.asset_inventory;
create policy asset_inventory_update on public.asset_inventory
  for update to authenticated
  using (public.has_permission('assets.write'))
  with check (public.has_permission('assets.write'));

drop policy if exists asset_inventory_delete on public.asset_inventory;
create policy asset_inventory_delete on public.asset_inventory
  for delete to authenticated
  using (public.has_permission('assets.write') or public.current_is_full_access());

-- =====================================================================
-- Table: asset_assignments
-- =====================================================================
create table if not exists public.asset_assignments (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.asset_inventory(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  handed_over_at timestamptz,
  receipt_sig_path text,
  returned_at timestamptz,
  return_condition text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.asset_assignments is 'إسناد الأصول للموظفين مع الاستلام والإرجاع';

create index if not exists idx_asset_assignments_asset on public.asset_assignments(asset_id);
create index if not exists idx_asset_assignments_employee on public.asset_assignments(employee_id);

alter table public.asset_assignments enable row level security;

drop trigger if exists trg_asset_assignments_updated_at on public.asset_assignments;
create trigger trg_asset_assignments_updated_at before update on public.asset_assignments
  for each row execute function public.tg_set_updated_at();

drop policy if exists asset_assignments_select on public.asset_assignments;
create policy asset_assignments_select on public.asset_assignments
  for select to authenticated
  using (public.can_access_employee(employee_id) or public.has_permission('assets.read'));

drop policy if exists asset_assignments_insert on public.asset_assignments;
create policy asset_assignments_insert on public.asset_assignments
  for insert to authenticated
  with check (public.has_permission('assets.write'));

drop policy if exists asset_assignments_update on public.asset_assignments;
create policy asset_assignments_update on public.asset_assignments
  for update to authenticated
  using (public.has_permission('assets.write'))
  with check (public.has_permission('assets.write'));

drop policy if exists asset_assignments_delete on public.asset_assignments;
create policy asset_assignments_delete on public.asset_assignments
  for delete to authenticated
  using (public.has_permission('assets.write') or public.current_is_full_access());

-- =====================================================================
-- Table: projects
-- =====================================================================
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  description text,
  status text not null default 'active' check (status in ('planned','active','on_hold','completed','cancelled')),
  owner_employee_id uuid references public.employees(id) on delete set null,
  start_date date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.projects is 'المشاريع مع المالك والحالة والفترة';

-- Create the membership relation before any project policy references it.
create table if not exists public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  role_in_project text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique (project_id, employee_id)
);

create index if not exists idx_projects_status on public.projects(status);
create index if not exists idx_projects_owner on public.projects(owner_employee_id);

alter table public.projects enable row level security;

drop trigger if exists trg_projects_updated_at on public.projects;
create trigger trg_projects_updated_at before update on public.projects
  for each row execute function public.tg_set_updated_at();

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
  for select to authenticated
  using (
    owner_employee_id = public.current_employee_id()
    or public.has_permission('projects.read')
    or exists (
      select 1 from public.project_members pm
      where pm.project_id = projects.id
        and pm.employee_id = public.current_employee_id()
    )
  );

drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects
  for insert to authenticated
  with check (public.has_permission('projects.write') or owner_employee_id = public.current_employee_id());

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  for update to authenticated
  using (owner_employee_id = public.current_employee_id() or public.has_permission('projects.write'))
  with check (owner_employee_id = public.current_employee_id() or public.has_permission('projects.write'));

drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects
  for delete to authenticated
  using (public.has_permission('projects.write') or public.current_is_full_access());

-- =====================================================================
-- Table: project_members
-- =====================================================================
comment on table public.project_members is 'أعضاء المشاريع وأدوارهم';

create index if not exists idx_project_members_project on public.project_members(project_id);
create index if not exists idx_project_members_employee on public.project_members(employee_id);

alter table public.project_members enable row level security;

drop trigger if exists trg_project_members_updated_at on public.project_members;
create trigger trg_project_members_updated_at before update on public.project_members
  for each row execute function public.tg_set_updated_at();

drop policy if exists project_members_select on public.project_members;
create policy project_members_select on public.project_members
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.has_permission('projects.read')
    or exists (
      select 1 from public.projects p
      where p.id = project_members.project_id
        and p.owner_employee_id = public.current_employee_id()
    )
  );

drop policy if exists project_members_insert on public.project_members;
create policy project_members_insert on public.project_members
  for insert to authenticated
  with check (
    public.has_permission('projects.write')
    or exists (
      select 1 from public.projects p
      where p.id = project_members.project_id
        and p.owner_employee_id = public.current_employee_id()
    )
  );

drop policy if exists project_members_update on public.project_members;
create policy project_members_update on public.project_members
  for update to authenticated
  using (
    public.has_permission('projects.write')
    or exists (
      select 1 from public.projects p
      where p.id = project_members.project_id
        and p.owner_employee_id = public.current_employee_id()
    )
  )
  with check (
    public.has_permission('projects.write')
    or exists (
      select 1 from public.projects p
      where p.id = project_members.project_id
        and p.owner_employee_id = public.current_employee_id()
    )
  );

drop policy if exists project_members_delete on public.project_members;
create policy project_members_delete on public.project_members
  for delete to authenticated
  using (
    public.has_permission('projects.write')
    or public.current_is_full_access()
    or exists (
      select 1 from public.projects p
      where p.id = project_members.project_id
        and p.owner_employee_id = public.current_employee_id()
    )
  );

-- =====================================================================
-- Table: meetings
-- =====================================================================
create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  scheduled_at timestamptz,
  location_or_link text,
  organizer_employee_id uuid references public.employees(id) on delete set null,
  status text not null default 'scheduled' check (status in ('scheduled','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.meetings is 'الاجتماعات مع الموعد والمنظم والحالة';

create index if not exists idx_meetings_organizer on public.meetings(organizer_employee_id);
create index if not exists idx_meetings_status on public.meetings(status);

alter table public.meetings enable row level security;

drop trigger if exists trg_meetings_updated_at on public.meetings;
create trigger trg_meetings_updated_at before update on public.meetings
  for each row execute function public.tg_set_updated_at();

drop policy if exists meetings_select on public.meetings;
create policy meetings_select on public.meetings
  for select to authenticated
  using (organizer_employee_id = public.current_employee_id() or public.has_permission('meetings.read'));

drop policy if exists meetings_insert on public.meetings;
create policy meetings_insert on public.meetings
  for insert to authenticated
  with check (public.has_permission('meetings.write') or organizer_employee_id = public.current_employee_id());

drop policy if exists meetings_update on public.meetings;
create policy meetings_update on public.meetings
  for update to authenticated
  using (organizer_employee_id = public.current_employee_id() or public.has_permission('meetings.write'))
  with check (organizer_employee_id = public.current_employee_id() or public.has_permission('meetings.write'));

drop policy if exists meetings_delete on public.meetings;
create policy meetings_delete on public.meetings
  for delete to authenticated
  using (public.has_permission('meetings.write') or public.current_is_full_access());

-- =====================================================================
-- Table: meeting_minutes
-- =====================================================================
create table if not exists public.meeting_minutes (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  body text,
  decisions jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
comment on table public.meeting_minutes is 'محاضر الاجتماعات والقرارات';

create index if not exists idx_meeting_minutes_meeting on public.meeting_minutes(meeting_id);

alter table public.meeting_minutes enable row level security;

drop trigger if exists trg_meeting_minutes_updated_at on public.meeting_minutes;
create trigger trg_meeting_minutes_updated_at before update on public.meeting_minutes
  for each row execute function public.tg_set_updated_at();

drop policy if exists meeting_minutes_select on public.meeting_minutes;
create policy meeting_minutes_select on public.meeting_minutes
  for select to authenticated
  using (
    public.has_permission('meetings.read')
    or exists (
      select 1 from public.meetings m
      where m.id = meeting_minutes.meeting_id
        and m.organizer_employee_id = public.current_employee_id()
    )
  );

drop policy if exists meeting_minutes_insert on public.meeting_minutes;
create policy meeting_minutes_insert on public.meeting_minutes
  for insert to authenticated
  with check (
    public.has_permission('meetings.write')
    or exists (
      select 1 from public.meetings m
      where m.id = meeting_minutes.meeting_id
        and m.organizer_employee_id = public.current_employee_id()
    )
  );

drop policy if exists meeting_minutes_update on public.meeting_minutes;
create policy meeting_minutes_update on public.meeting_minutes
  for update to authenticated
  using (
    public.has_permission('meetings.write')
    or exists (
      select 1 from public.meetings m
      where m.id = meeting_minutes.meeting_id
        and m.organizer_employee_id = public.current_employee_id()
    )
  )
  with check (
    public.has_permission('meetings.write')
    or exists (
      select 1 from public.meetings m
      where m.id = meeting_minutes.meeting_id
        and m.organizer_employee_id = public.current_employee_id()
    )
  );

drop policy if exists meeting_minutes_delete on public.meeting_minutes;
create policy meeting_minutes_delete on public.meeting_minutes
  for delete to authenticated
  using (public.has_permission('meetings.write') or public.current_is_full_access());

-- =====================================================================
-- Table: decision_register
-- =====================================================================
create table if not exists public.decision_register (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text,
  body text,
  decided_by uuid references public.employees(id) on delete set null,
  decided_at timestamptz,
  status text not null default 'open' check (status in ('open','implemented','superseded','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.decision_register is 'سجل القرارات التنظيمية';

create index if not exists idx_decision_register_status on public.decision_register(status);

alter table public.decision_register enable row level security;

drop trigger if exists trg_decision_register_updated_at on public.decision_register;
create trigger trg_decision_register_updated_at before update on public.decision_register
  for each row execute function public.tg_set_updated_at();

drop policy if exists decision_register_select on public.decision_register;
create policy decision_register_select on public.decision_register
  for select to authenticated
  using (public.has_permission('decisions.read') or decided_by = public.current_employee_id());

drop policy if exists decision_register_insert on public.decision_register;
create policy decision_register_insert on public.decision_register
  for insert to authenticated
  with check (public.has_permission('decisions.write'));

drop policy if exists decision_register_update on public.decision_register;
create policy decision_register_update on public.decision_register
  for update to authenticated
  using (public.has_permission('decisions.write'))
  with check (public.has_permission('decisions.write'));

drop policy if exists decision_register_delete on public.decision_register;
create policy decision_register_delete on public.decision_register
  for delete to authenticated
  using (public.has_permission('decisions.write') or public.current_is_full_access());

-- =====================================================================
-- Table: risks
-- =====================================================================
create table if not exists public.risks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  likelihood text not null default 'medium' check (likelihood in ('low','medium','high')),
  impact text not null default 'medium' check (impact in ('low','medium','high')),
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  owner_employee_id uuid references public.employees(id) on delete set null,
  status text not null default 'open' check (status in ('open','mitigating','closed','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.risks is 'سجل المخاطر مع الاحتمالية والأثر والشدة';

create index if not exists idx_risks_status on public.risks(status);
create index if not exists idx_risks_owner on public.risks(owner_employee_id);

alter table public.risks enable row level security;

drop trigger if exists trg_risks_updated_at on public.risks;
create trigger trg_risks_updated_at before update on public.risks
  for each row execute function public.tg_set_updated_at();

drop policy if exists risks_select on public.risks;
create policy risks_select on public.risks
  for select to authenticated
  using (public.has_permission('risks.read') or owner_employee_id = public.current_employee_id());

drop policy if exists risks_insert on public.risks;
create policy risks_insert on public.risks
  for insert to authenticated
  with check (public.has_permission('risks.write') or owner_employee_id = public.current_employee_id());

drop policy if exists risks_update on public.risks;
create policy risks_update on public.risks
  for update to authenticated
  using (public.has_permission('risks.write') or owner_employee_id = public.current_employee_id())
  with check (public.has_permission('risks.write') or owner_employee_id = public.current_employee_id());

drop policy if exists risks_delete on public.risks;
create policy risks_delete on public.risks
  for delete to authenticated
  using (public.has_permission('risks.write') or public.current_is_full_access());

-- =====================================================================
-- Table: incidents
-- =====================================================================
create table if not exists public.incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  reported_by uuid references public.employees(id) on delete set null,
  status text not null default 'open' check (status in ('open','investigating','resolved','closed')),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.incidents is 'الحوادث مع الشدة والحالة والمُبلّغ';

create index if not exists idx_incidents_status on public.incidents(status);

alter table public.incidents enable row level security;

drop trigger if exists trg_incidents_updated_at on public.incidents;
create trigger trg_incidents_updated_at before update on public.incidents
  for each row execute function public.tg_set_updated_at();

drop policy if exists incidents_select on public.incidents;
create policy incidents_select on public.incidents
  for select to authenticated
  using (public.has_permission('incidents.read') or reported_by = public.current_employee_id());

drop policy if exists incidents_insert on public.incidents;
create policy incidents_insert on public.incidents
  for insert to authenticated
  with check (public.has_permission('incidents.write') or reported_by = public.current_employee_id());

drop policy if exists incidents_update on public.incidents;
create policy incidents_update on public.incidents
  for update to authenticated
  using (public.has_permission('incidents.write') or reported_by = public.current_employee_id())
  with check (public.has_permission('incidents.write') or reported_by = public.current_employee_id());

drop policy if exists incidents_delete on public.incidents;
create policy incidents_delete on public.incidents
  for delete to authenticated
  using (public.has_permission('incidents.write') or public.current_is_full_access());

-- =====================================================================
-- Table: knowledge_articles
-- =====================================================================
create table if not exists public.knowledge_articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text,
  body text,
  is_published boolean not null default false,
  author_employee_id uuid references public.employees(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.knowledge_articles is 'مقالات قاعدة المعرفة';

create index if not exists idx_knowledge_articles_published on public.knowledge_articles(is_published);

alter table public.knowledge_articles enable row level security;

drop trigger if exists trg_knowledge_articles_updated_at on public.knowledge_articles;
create trigger trg_knowledge_articles_updated_at before update on public.knowledge_articles
  for each row execute function public.tg_set_updated_at();

drop policy if exists knowledge_articles_select_published on public.knowledge_articles;
create policy knowledge_articles_select_published on public.knowledge_articles
  for select to authenticated
  using (is_published = true);

drop policy if exists knowledge_articles_select_manage on public.knowledge_articles;
create policy knowledge_articles_select_manage on public.knowledge_articles
  for select to authenticated
  using (
    author_employee_id = public.current_employee_id()
    or public.has_permission('knowledge.write')
    or public.current_is_full_access()
  );

drop policy if exists knowledge_articles_insert on public.knowledge_articles;
create policy knowledge_articles_insert on public.knowledge_articles
  for insert to authenticated
  with check (public.has_permission('knowledge.write') or author_employee_id = public.current_employee_id());

drop policy if exists knowledge_articles_update on public.knowledge_articles;
create policy knowledge_articles_update on public.knowledge_articles
  for update to authenticated
  using (author_employee_id = public.current_employee_id() or public.has_permission('knowledge.write'))
  with check (author_employee_id = public.current_employee_id() or public.has_permission('knowledge.write'));

drop policy if exists knowledge_articles_delete on public.knowledge_articles;
create policy knowledge_articles_delete on public.knowledge_articles
  for delete to authenticated
  using (public.has_permission('knowledge.write') or public.current_is_full_access());

-- =====================================================================
-- Table: hr_tickets
-- =====================================================================
create table if not exists public.hr_tickets (
  id uuid primary key default gen_random_uuid(),
  subject text not null,
  category text,
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed','cancelled')),
  requester_employee_id uuid not null references public.employees(id) on delete cascade,
  assignee_employee_id uuid references public.employees(id) on delete set null,
  sla_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.hr_tickets is 'تذاكر الموارد البشرية مع مقدم الطلب والمكلّف وسقف الخدمة';

create index if not exists idx_hr_tickets_requester on public.hr_tickets(requester_employee_id);
create index if not exists idx_hr_tickets_assignee on public.hr_tickets(assignee_employee_id);
create index if not exists idx_hr_tickets_status on public.hr_tickets(status);

alter table public.hr_tickets enable row level security;

drop trigger if exists trg_hr_tickets_updated_at on public.hr_tickets;
create trigger trg_hr_tickets_updated_at before update on public.hr_tickets
  for each row execute function public.tg_set_updated_at();

drop policy if exists hr_tickets_select on public.hr_tickets;
create policy hr_tickets_select on public.hr_tickets
  for select to authenticated
  using (
    requester_employee_id = public.current_employee_id()
    or assignee_employee_id = public.current_employee_id()
    or public.has_permission('tickets.read')
  );

drop policy if exists hr_tickets_insert on public.hr_tickets;
create policy hr_tickets_insert on public.hr_tickets
  for insert to authenticated
  with check (requester_employee_id = public.current_employee_id() or public.has_permission('tickets.write'));

drop policy if exists hr_tickets_update on public.hr_tickets;
create policy hr_tickets_update on public.hr_tickets
  for update to authenticated
  using (
    requester_employee_id = public.current_employee_id()
    or assignee_employee_id = public.current_employee_id()
    or public.has_permission('tickets.write')
  )
  with check (
    requester_employee_id = public.current_employee_id()
    or assignee_employee_id = public.current_employee_id()
    or public.has_permission('tickets.write')
  );

drop policy if exists hr_tickets_delete on public.hr_tickets;
create policy hr_tickets_delete on public.hr_tickets
  for delete to authenticated
  using (public.has_permission('tickets.write') or public.current_is_full_access());

-- =====================================================================
-- Table: ticket_messages
-- =====================================================================
create table if not exists public.ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.hr_tickets(id) on delete cascade,
  author_id uuid references auth.users(id),
  body text not null,
  is_internal boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.ticket_messages is 'رسائل تذاكر الموارد البشرية مع علامة الداخلية';

create index if not exists idx_ticket_messages_ticket on public.ticket_messages(ticket_id);

alter table public.ticket_messages enable row level security;

drop trigger if exists trg_ticket_messages_updated_at on public.ticket_messages;
create trigger trg_ticket_messages_updated_at before update on public.ticket_messages
  for each row execute function public.tg_set_updated_at();

drop policy if exists ticket_messages_select on public.ticket_messages;
create policy ticket_messages_select on public.ticket_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.hr_tickets t
      where t.id = ticket_messages.ticket_id
        and (
          (
            not ticket_messages.is_internal
            and (
              t.requester_employee_id = public.current_employee_id()
              or t.assignee_employee_id = public.current_employee_id()
            )
          )
          or t.assignee_employee_id = public.current_employee_id()
          or public.has_permission('tickets.read')
        )
    )
  );

drop policy if exists ticket_messages_insert on public.ticket_messages;
create policy ticket_messages_insert on public.ticket_messages
  for insert to authenticated
  with check (
    exists (
      select 1 from public.hr_tickets t
      where t.id = ticket_messages.ticket_id
        and (
          t.requester_employee_id = public.current_employee_id()
          or t.assignee_employee_id = public.current_employee_id()
          or public.has_permission('tickets.write')
        )
    )
  );

drop policy if exists ticket_messages_update on public.ticket_messages;
create policy ticket_messages_update on public.ticket_messages
  for update to authenticated
  using (author_id = auth.uid() or public.has_permission('tickets.write'))
  with check (author_id = auth.uid() or public.has_permission('tickets.write'));

drop policy if exists ticket_messages_delete on public.ticket_messages;
create policy ticket_messages_delete on public.ticket_messages
  for delete to authenticated
  using (author_id = auth.uid() or public.has_permission('tickets.write') or public.current_is_full_access());

-- =====================================================================
-- RPC: acknowledge_policy
-- =====================================================================
create or replace function public.acknowledge_policy(p_policy_id uuid)
returns public.policy_acknowledgements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_row public.policy_acknowledgements;
begin
  v_employee_id := public.current_employee_id();
  if v_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بالمستخدم الحالي';
  end if;

  if not exists (select 1 from public.policies p where p.id = p_policy_id and p.status = 'published') then
    raise exception 'السياسة غير موجودة أو غير منشورة';
  end if;

  insert into public.policy_acknowledgements (policy_id, employee_id, acknowledged_at, created_by)
  values (p_policy_id, v_employee_id, now(), auth.uid())
  on conflict (policy_id, employee_id)
  do update set acknowledged_at = now(), updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.acknowledge_policy(uuid) from public;
grant execute on function public.acknowledge_policy(uuid) to authenticated;
