-- Migration 0006: الطلبات ومحرك الموافقات (Requests & Approvals Engine)
-- يعتمد على: 0002 (دوال التخويل)، 0004 (employees). لا يعيد تعريف أي جدول سابق.
-- ملاحظة: 0005 (attendance_permits وغيرها) مرجعية فقط — لا تُعرّف هنا.
-- تشغيل عبر: supabase db push. الملف idempotent قدر الإمكان.

-- =====================================================================
-- 0) trigger helper (idempotent — نفس التعريف المستخدم في 0003/0004)
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
  'Trigger helper: sets updated_at = now() (UTC) on row update.';

-- =====================================================================
-- Table: leave_types  (كتالوج أنواع الإجازات)
-- =====================================================================
create table if not exists public.leave_types (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null,
  name_ar            text not null,
  name_en            text,
  description        text,
  is_paid            boolean not null default true,
  requires_attachment boolean not null default false,
  max_days_per_year  integer,
  min_notice_days    integer not null default 0,
  affects_balance    boolean not null default true,
  color              text,
  sort_order         integer not null default 0,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.leave_types is
  'كتالوج أنواع الإجازات: مدفوعة/غير مدفوعة، الحدود السنوية، متطلبات المرفقات والإشعار المسبق.';

create unique index if not exists ux_leave_types_code on public.leave_types (code);
create index if not exists ix_leave_types_is_active on public.leave_types (is_active);

drop trigger if exists trg_leave_types_updated_at on public.leave_types;
create trigger trg_leave_types_updated_at
  before update on public.leave_types
  for each row execute function public.tg_set_updated_at();

alter table public.leave_types enable row level security;

drop policy if exists leave_types_select on public.leave_types;
create policy leave_types_select on public.leave_types
  for select to authenticated
  using (true);

drop policy if exists leave_types_write on public.leave_types;
create policy leave_types_write on public.leave_types
  for all to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['requests.leave_type.manage','requests.settings.manage']))
  with check (public.current_is_full_access() or public.has_any_permission(array['requests.leave_type.manage','requests.settings.manage']));

-- =====================================================================
-- Table: workflow_definitions  (محرك سير عمل قابل للتهيئة)
-- =====================================================================
create table if not exists public.workflow_definitions (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null,
  name_ar            text not null,
  name_en            text,
  description        text,
  request_type       text not null
                       check (request_type in (
                         'leave','mission','convoy','attendance_permit','generic'
                       )),
  version            integer not null default 1,
  is_active          boolean not null default true,
  is_default         boolean not null default false,
  auto_escalate      boolean not null default true,
  default_due_hours  integer not null default 48,
  config             jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.workflow_definitions is
  'تعريفات سير العمل القابلة للتهيئة لكل نوع طلب (النسخة، التصعيد التلقائي، مهلة القرار).';

create unique index if not exists ux_workflow_definitions_code_version
  on public.workflow_definitions (code, version);
create unique index if not exists ux_workflow_definitions_default_type
  on public.workflow_definitions (request_type)
  where is_default = true and is_active = true;
create index if not exists ix_workflow_definitions_request_type
  on public.workflow_definitions (request_type);

drop trigger if exists trg_workflow_definitions_updated_at on public.workflow_definitions;
create trigger trg_workflow_definitions_updated_at
  before update on public.workflow_definitions
  for each row execute function public.tg_set_updated_at();

alter table public.workflow_definitions enable row level security;

drop policy if exists workflow_definitions_select on public.workflow_definitions;
create policy workflow_definitions_select on public.workflow_definitions
  for select to authenticated
  using (true);

drop policy if exists workflow_definitions_write on public.workflow_definitions;
create policy workflow_definitions_write on public.workflow_definitions
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('requests.workflow.manage'))
  with check (public.current_is_full_access() or public.has_permission('requests.workflow.manage'));

-- =====================================================================
-- Table: workflow_steps  (خطوات تعريف سير العمل — تهيئة)
-- =====================================================================
create table if not exists public.workflow_steps (
  id                 uuid primary key default gen_random_uuid(),
  definition_id      uuid not null references public.workflow_definitions(id) on delete cascade,
  step_order         integer not null,
  name_ar            text not null,
  name_en            text,
  step_type          text not null default 'approval'
                       check (step_type in ('approval','review','notify','auto')),
  approver_type      text not null default 'direct_manager'
                       check (approver_type in (
                         'direct_manager','department_manager','role','specific_employee',
                         'operator','committee','system'
                       )),
  approver_role_slug text,
  approver_employee_id uuid references public.employees(id) on delete set null,
  approver_permission text,
  is_optional        boolean not null default false,
  allow_delegate     boolean not null default true,
  sla_hours          integer not null default 48,
  escalate_after_hours integer,
  config             jsonb not null default '{}'::jsonb,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.workflow_steps is
  'خطوات تعريف سير العمل: الترتيب، نوع الخطوة والمعتمد، SLA والتصعيد — قابلة للتهيئة.';

create unique index if not exists ux_workflow_steps_def_order
  on public.workflow_steps (definition_id, step_order);
create index if not exists ix_workflow_steps_definition on public.workflow_steps (definition_id);

drop trigger if exists trg_workflow_steps_updated_at on public.workflow_steps;
create trigger trg_workflow_steps_updated_at
  before update on public.workflow_steps
  for each row execute function public.tg_set_updated_at();

alter table public.workflow_steps enable row level security;

drop policy if exists workflow_steps_select on public.workflow_steps;
create policy workflow_steps_select on public.workflow_steps
  for select to authenticated
  using (true);

drop policy if exists workflow_steps_write on public.workflow_steps;
create policy workflow_steps_write on public.workflow_steps
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('requests.workflow.manage'))
  with check (public.current_is_full_access() or public.has_permission('requests.workflow.manage'));

-- =====================================================================
-- Table: requests  (النمط الموحّد لكل الطلبات)
-- =====================================================================
create table if not exists public.requests (
  id                   uuid primary key default gen_random_uuid(),
  request_number       bigint generated always as identity,
  request_type         text not null
                         check (request_type in (
                           'leave','mission','convoy','attendance_permit','generic'
                         )),
  employee_id          uuid not null references public.employees(id) on delete cascade,
  manager_employee_id  uuid references public.employees(id) on delete set null,
  workflow_definition_id uuid references public.workflow_definitions(id) on delete set null,
  status               text not null default 'pending'
                         check (status in (
                           'pending','approved','rejected','cancelled','withdrawn','expired'
                         )),
  workflow_status      text not null default 'submitted'
                         check (workflow_status in (
                           'submitted','in_review','awaiting_manager','awaiting_operator',
                           'escalated','completed','terminated'
                         )),
  title                text,
  reason               text,
  reference_id         uuid,
  current_step_order   integer not null default 1,
  decision_due_at      timestamptz,
  escalation_deadline  timestamptz,
  escalated_at         timestamptz,
  decided_at           timestamptz,
  decided_by           uuid references public.employees(id) on delete set null,
  cancelled_at         timestamptz,
  cancelled_by         uuid references public.employees(id) on delete set null,
  cancel_reason        text,
  payload              jsonb not null default '{}'::jsonb,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz,
  created_by           uuid references auth.users(id)
);
comment on table public.requests is
  'النمط الموحّد لكل الطلبات: الحالة وحالة سير العمل، المدير، مهلة القرار والتصعيد والسبب.';

create index if not exists ix_requests_employee    on public.requests (employee_id);
create index if not exists ix_requests_manager      on public.requests (manager_employee_id);
create index if not exists ix_requests_type         on public.requests (request_type);
create index if not exists ix_requests_status       on public.requests (status);
create index if not exists ix_requests_wf_status    on public.requests (workflow_status);
create index if not exists ix_requests_due          on public.requests (decision_due_at);
create index if not exists ix_requests_escalation   on public.requests (escalation_deadline);

drop trigger if exists trg_requests_updated_at on public.requests;
create trigger trg_requests_updated_at
  before update on public.requests
  for each row execute function public.tg_set_updated_at();

alter table public.requests enable row level security;

-- SELECT: full access, صلاحية القراءة، صاحب الطلب، أو المدير المعيّن
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or employee_id = public.current_employee_id()
    or manager_employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

-- INSERT: صاحب الطلب لنفسه فقط، وبحالة pending/submitted حصراً
drop policy if exists requests_insert on public.requests;
create policy requests_insert on public.requests
  for insert to authenticated
  with check (
    employee_id = public.current_employee_id()
    and status = 'pending'
    and workflow_status = 'submitted'
    and manager_employee_id is distinct from employee_id
  );

-- UPDATE: المشغّل/المدير (لا موافقة ذاتية). صاحب الطلب لا يُحدّث حالة القرار عبر RLS
-- ⚠️ منع UPDATE المباشر (P0): التحديث عبر الـRPCs فقط (submit/decide/cancel/escalate)
-- التي تفرض ترتيب الحالات وتسجّل الإجراءات. يُسمح فقط لـfull-access كإجراء تصحيح إداري موثّق.
drop policy if exists requests_update on public.requests;
create policy requests_update on public.requests
  for update to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

-- =====================================================================
-- Table: leave_requests  (تفصيل طلبات الإجازة — يمتد من requests)
-- =====================================================================
create table if not exists public.leave_requests (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  leave_type_id      uuid not null references public.leave_types(id) on delete restrict,
  start_date         date not null,
  end_date           date not null,
  is_half_day        boolean not null default false,
  half_day_period    text check (half_day_period in ('morning','afternoon')),
  days_count         numeric(6,2) not null default 0,
  handover_notes     text,
  contact_during_leave text,
  attachment_url     text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  constraint ck_leave_requests_dates check (end_date >= start_date)
);
comment on table public.leave_requests is
  'تفاصيل طلبات الإجازة المرتبطة بجدول requests الموحّد (النوع، الفترة، عدد الأيام، التسليم).';

create unique index if not exists ux_leave_requests_request on public.leave_requests (request_id);
create index if not exists ix_leave_requests_employee on public.leave_requests (employee_id);
create index if not exists ix_leave_requests_type     on public.leave_requests (leave_type_id);
create index if not exists ix_leave_requests_dates    on public.leave_requests (start_date, end_date);

drop trigger if exists trg_leave_requests_updated_at on public.leave_requests;
create trigger trg_leave_requests_updated_at
  before update on public.leave_requests
  for each row execute function public.tg_set_updated_at();

alter table public.leave_requests enable row level security;

drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select on public.leave_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

drop policy if exists leave_requests_insert on public.leave_requests;
create policy leave_requests_insert on public.leave_requests
  for insert to authenticated
  with check (
    employee_id = public.current_employee_id()
    and exists (
      select 1 from public.requests r
      where r.id = request_id
        and r.employee_id = public.current_employee_id()
        and r.status = 'pending'
    )
  );

-- التعديل الذاتي لبيانات الطلب مسموح فقط قبل الإرسال (الطلب pending)؛ القرار عبر RPC على requests.
drop policy if exists leave_requests_update on public.leave_requests;
create policy leave_requests_update on public.leave_requests
  for update to authenticated
  using (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  )
  with check (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  );

-- =====================================================================
-- Table: missions  (طلبات المهام/الانتداب — يمتد من requests)
-- =====================================================================
create table if not exists public.missions (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  destination        text not null,
  purpose            text not null,
  start_at           timestamptz not null,
  end_at             timestamptz not null,
  transport_mode     text check (transport_mode in ('company_vehicle','personal','public','flight','other')),
  estimated_cost     numeric(12,2),
  needs_advance      boolean not null default false,
  advance_amount     numeric(12,2),
  attachment_url     text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  constraint ck_missions_period check (end_at >= start_at)
);
comment on table public.missions is
  'طلبات المهام/الانتداب المرتبطة بجدول requests الموحّد (الوجهة، الغرض، الفترة، وسيلة النقل والتكلفة).';

create unique index if not exists ux_missions_request on public.missions (request_id);
create index if not exists ix_missions_employee on public.missions (employee_id);
create index if not exists ix_missions_period   on public.missions (start_at, end_at);

drop trigger if exists trg_missions_updated_at on public.missions;
create trigger trg_missions_updated_at
  before update on public.missions
  for each row execute function public.tg_set_updated_at();

alter table public.missions enable row level security;

drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

drop policy if exists missions_insert on public.missions;
create policy missions_insert on public.missions
  for insert to authenticated
  with check (
    employee_id = public.current_employee_id()
    and exists (
      select 1 from public.requests r
      where r.id = request_id
        and r.employee_id = public.current_employee_id()
        and r.status = 'pending'
    )
  );

drop policy if exists missions_update on public.missions;
create policy missions_update on public.missions
  for update to authenticated
  using (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  )
  with check (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  );

-- =====================================================================
-- Table: convoy_requests  (طلبات القوافل/المواكب — يمتد من requests)
-- =====================================================================
create table if not exists public.convoy_requests (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  convoy_name        text not null,
  origin             text not null,
  destination        text not null,
  departure_at       timestamptz not null,
  return_at          timestamptz,
  passengers_count   integer not null default 1 check (passengers_count >= 1),
  vehicles_count     integer not null default 1 check (vehicles_count >= 1),
  route_details      text,
  notes              text,
  attachment_url     text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  constraint ck_convoy_period check (return_at is null or return_at >= departure_at)
);
comment on table public.convoy_requests is
  'طلبات القوافل/المواكب المرتبطة بجدول requests الموحّد (المسار، المواعيد، عدد الركاب والمركبات).';

create unique index if not exists ux_convoy_requests_request on public.convoy_requests (request_id);
create index if not exists ix_convoy_requests_employee on public.convoy_requests (employee_id);
create index if not exists ix_convoy_requests_departure on public.convoy_requests (departure_at);

drop trigger if exists trg_convoy_requests_updated_at on public.convoy_requests;
create trigger trg_convoy_requests_updated_at
  before update on public.convoy_requests
  for each row execute function public.tg_set_updated_at();

alter table public.convoy_requests enable row level security;

drop policy if exists convoy_requests_select on public.convoy_requests;
create policy convoy_requests_select on public.convoy_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

drop policy if exists convoy_requests_insert on public.convoy_requests;
create policy convoy_requests_insert on public.convoy_requests
  for insert to authenticated
  with check (
    employee_id = public.current_employee_id()
    and exists (
      select 1 from public.requests r
      where r.id = request_id
        and r.employee_id = public.current_employee_id()
        and r.status = 'pending'
    )
  );

drop policy if exists convoy_requests_update on public.convoy_requests;
create policy convoy_requests_update on public.convoy_requests
  for update to authenticated
  using (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  )
  with check (
    public.current_is_full_access()
    or (employee_id = public.current_employee_id()
        and exists (select 1 from public.requests r where r.id = request_id and r.status = 'pending'))
  );

-- =====================================================================
-- Table: request_steps  (نسخة خطوات سير العمل الجارية لكل طلب)
-- =====================================================================
create table if not exists public.request_steps (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests(id) on delete cascade,
  workflow_step_id   uuid references public.workflow_steps(id) on delete set null,
  step_order         integer not null,
  name_ar            text not null,
  step_type          text not null default 'approval'
                       check (step_type in ('approval','review','notify','auto')),
  assignee_employee_id uuid references public.employees(id) on delete set null,
  assignee_role_slug text,
  status             text not null default 'pending'
                       check (status in ('pending','active','approved','rejected','skipped','escalated','expired')),
  sla_hours          integer,
  due_at             timestamptz,
  escalation_deadline timestamptz,
  escalated_at       timestamptz,
  acted_at           timestamptz,
  acted_by           uuid references public.employees(id) on delete set null,
  comment            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.request_steps is
  'نسخة الخطوات الجارية (runtime) لكل طلب: المكلّف، الحالة، مهلة القرار والتصعيد ونتيجة الإجراء.';

create unique index if not exists ux_request_steps_req_order on public.request_steps (request_id, step_order);
create index if not exists ix_request_steps_request  on public.request_steps (request_id);
create index if not exists ix_request_steps_assignee on public.request_steps (assignee_employee_id);
create index if not exists ix_request_steps_status   on public.request_steps (status);
create index if not exists ix_request_steps_due      on public.request_steps (due_at);

drop trigger if exists trg_request_steps_updated_at on public.request_steps;
create trigger trg_request_steps_updated_at
  before update on public.request_steps
  for each row execute function public.tg_set_updated_at();

alter table public.request_steps enable row level security;

drop policy if exists request_steps_select on public.request_steps;
create policy request_steps_select on public.request_steps
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or assignee_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.requests r
      where r.id = request_id
        and (r.employee_id = public.current_employee_id()
             or r.manager_employee_id = public.current_employee_id()
             or public.can_access_employee(r.employee_id))
    )
  );

-- الكتابة على الخطوات عبر RPC فقط (المشغّل/المدير)؛ لا موافقة ذاتية
-- ⚠️ منع الكتابة المباشرة (P0): request_steps تُكتب حصراً عبر RPCs (submit/decide/cancel)
-- التي تفرض ترتيب الخطوات وتسجّل الإجراءات. full-access فقط للتصحيح الإداري الموثّق.
drop policy if exists request_steps_update on public.request_steps;
create policy request_steps_update on public.request_steps
  for update to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

drop policy if exists request_steps_insert on public.request_steps;
create policy request_steps_insert on public.request_steps
  for insert to authenticated
  with check (public.current_is_full_access());

-- =====================================================================
-- Table: request_actions  (سجل الإجراءات/التدقيق لكل طلب — append only)
-- =====================================================================
create table if not exists public.request_actions (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.requests(id) on delete cascade,
  request_step_id    uuid references public.request_steps(id) on delete set null,
  actor_employee_id  uuid references public.employees(id) on delete set null,
  action             text not null
                       check (action in (
                         'submit','approve','reject','request_changes','comment',
                         'escalate','reassign','cancel','withdraw','expire','system'
                       )),
  from_status        text,
  to_status          text,
  comment            text,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.request_actions is
  'سجل تدقيق الإجراءات على الطلبات (submit/approve/reject/escalate/cancel...) للقراءة فقط للمستخدم.';

create index if not exists ix_request_actions_request on public.request_actions (request_id);
create index if not exists ix_request_actions_step    on public.request_actions (request_step_id);
create index if not exists ix_request_actions_actor   on public.request_actions (actor_employee_id);
create index if not exists ix_request_actions_action  on public.request_actions (action);

drop trigger if exists trg_request_actions_updated_at on public.request_actions;
create trigger trg_request_actions_updated_at
  before update on public.request_actions
  for each row execute function public.tg_set_updated_at();

alter table public.request_actions enable row level security;

drop policy if exists request_actions_select on public.request_actions;
create policy request_actions_select on public.request_actions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or actor_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.requests r
      where r.id = request_id
        and (r.employee_id = public.current_employee_id()
             or r.manager_employee_id = public.current_employee_id()
             or public.can_access_employee(r.employee_id))
    )
  );

-- إدراج الإجراءات: صاحب الطلب (submit/comment/withdraw) أو المخوّل؛ الفاعل = المستخدم الحالي
drop policy if exists request_actions_insert on public.request_actions;
create policy request_actions_insert on public.request_actions
  for insert to authenticated
  with check (
    actor_employee_id = public.current_employee_id()
    and (
      public.current_is_full_access()
      or public.has_permission('requests.approve')
      or exists (
        select 1 from public.requests r
        where r.id = request_id
          and r.employee_id = public.current_employee_id()
      )
    )
  );

-- =====================================================================
-- Table: workflow_instances  (نسخة سير العمل الجارية المرتبطة بطلب)
-- =====================================================================
create table if not exists public.workflow_instances (
  id                 uuid primary key default gen_random_uuid(),
  definition_id      uuid not null references public.workflow_definitions(id) on delete restrict,
  request_id         uuid not null references public.requests(id) on delete cascade,
  definition_version integer not null default 1,
  status             text not null default 'running'
                       check (status in ('running','completed','terminated','cancelled')),
  current_step_order integer not null default 1,
  started_at         timestamptz not null default now(),
  completed_at       timestamptz,
  context            jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.workflow_instances is
  'نسخة سير العمل الجارية لكل طلب: التعريف والنسخة والحالة والخطوة الحالية وسياق التنفيذ.';

create unique index if not exists ux_workflow_instances_request on public.workflow_instances (request_id);
create index if not exists ix_workflow_instances_definition on public.workflow_instances (definition_id);
create index if not exists ix_workflow_instances_status     on public.workflow_instances (status);

drop trigger if exists trg_workflow_instances_updated_at on public.workflow_instances;
create trigger trg_workflow_instances_updated_at
  before update on public.workflow_instances
  for each row execute function public.tg_set_updated_at();

alter table public.workflow_instances enable row level security;

drop policy if exists workflow_instances_select on public.workflow_instances;
create policy workflow_instances_select on public.workflow_instances
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('requests.read')
    or exists (
      select 1 from public.requests r
      where r.id = request_id
        and (r.employee_id = public.current_employee_id()
             or r.manager_employee_id = public.current_employee_id()
             or public.can_access_employee(r.employee_id))
    )
  );

-- ⚠️ منع الكتابة المباشرة (P0): workflow_instances تُدار عبر RPCs فقط. full-access للتصحيح الإداري.
drop policy if exists workflow_instances_write on public.workflow_instances;
create policy workflow_instances_write on public.workflow_instances
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

-- =====================================================================
-- RPC: submit_request  (إنشاء طلب موحّد بحالة pending + خطوة أولى + إجراء submit)
-- =====================================================================
create or replace function public.submit_request(
  p_request_type          text,
  p_workflow_definition_id uuid    default null,
  p_manager_employee_id    uuid    default null,
  p_title                  text    default null,
  p_reason                 text    default null,
  p_payload                jsonb   default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me       uuid := public.current_employee_id();
  v_def      public.workflow_definitions;
  v_due      timestamptz;
  v_esc      timestamptz;
  v_row      public.requests;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','attendance_permit','generic') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = v_me then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- اختر التعريف الافتراضي إن لم يُمرَّر
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then
      v_esc := v_due;
    end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, v_me, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء الخطوات الجارية من تعريف سير العمل (إن وُجد)
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id,
      ws.id,
      ws.step_order,
      ws.name_ar,
      ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1 then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  -- سجل إجراء submit
  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (
    v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid()
  );

  return v_row;
end;
$$;
comment on function public.submit_request(text, uuid, uuid, text, text, jsonb) is
  'إنشاء طلب موحّد بحالة pending، توليد خطوات سير العمل الجارية والنسخة، وتسجيل إجراء submit.';
revoke execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) from public;
grant  execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) to authenticated;

-- =====================================================================
-- RPC: decide_request  (موافقة/رفض من المشغّل أو المدير — لا موافقة ذاتية)
-- =====================================================================
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision   text,        -- 'approve' | 'reject'
  p_comment    text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.requests;
  v_from text;
  v_to   text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  -- منع الموافقة الذاتية
  if v_req.employee_id = v_me then
    raise exception 'self-approval is not allowed' using errcode = '42501';
  end if;

  -- التخويل: full-access أو صلاحية approve أو المدير المعيّن على الطلب
  if not (
    public.current_is_full_access()
    or public.has_permission('requests.approve')
    or v_req.manager_employee_id = v_me
  ) then
    raise exception 'not authorized to decide this request' using errcode = '42501';
  end if;

  v_from := v_req.status;
  v_to   := case when p_decision = 'approve' then 'approved' else 'rejected' end;

  update public.requests
     set status          = v_to,
         workflow_status = 'completed',
         decided_at      = now(),
         decided_by      = v_me,
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  -- أغلق الخطوات الجارية
  update public.request_steps
     set status   = case when p_decision = 'approve' then 'approved' else 'rejected' end,
         acted_at = now(),
         acted_by = v_me,
         comment  = coalesce(p_comment, comment),
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  -- أغلق نسخة سير العمل
  update public.workflow_instances
     set status       = 'completed',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status = 'running';

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, p_decision, v_from, v_to, p_comment, auth.uid()
  );

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  'موافقة/رفض طلب من المشغّل أو المدير المعيّن مع منع الموافقة الذاتية وتحديث الخطوات والنسخة والسجل.';
revoke execute on function public.decide_request(uuid, text, text) from public;
grant  execute on function public.decide_request(uuid, text, text) to authenticated;

-- =====================================================================
-- RPC: cancel_request  (إلغاء من صاحب الطلب أو المخوّل — طلبات pending فقط)
-- =====================================================================
create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason     text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.requests;
  v_from text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be cancelled (current: %)', v_req.status using errcode = '22023';
  end if;

  -- التخويل: صاحب الطلب، أو full-access، أو صلاحية approve
  if not (
    v_req.employee_id = v_me
    or public.current_is_full_access()
    or public.has_permission('requests.approve')
  ) then
    raise exception 'not authorized to cancel this request' using errcode = '42501';
  end if;

  v_from := v_req.status;

  update public.requests
     set status          = 'cancelled',
         workflow_status = 'terminated',
         cancelled_at    = now(),
         cancelled_by    = v_me,
         cancel_reason   = p_reason,
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  update public.request_steps
     set status   = 'skipped',
         acted_at = now(),
         acted_by = v_me,
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  update public.workflow_instances
     set status       = 'cancelled',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status = 'running';

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'cancel', v_from, 'cancelled', p_reason, auth.uid()
  );

  return v_req;
end;
$$;
comment on function public.cancel_request(uuid, text) is
  'إلغاء طلب pending عبر RPC من صاحب الطلب أو المخوّل، مع إنهاء الخطوات والنسخة وتسجيل الإجراء.';
revoke execute on function public.cancel_request(uuid, text) from public;
grant  execute on function public.cancel_request(uuid, text) to authenticated;
