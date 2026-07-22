-- Migration 0007: KPI والأداء والأهداف
-- Domain: KPI cycles, evaluations, monthly evaluations, goals/OKRs, 360 feedback,
--         competencies, calibration, review cycles, improvement plans, one-on-ones.

begin;

-- ============================================================================
-- Shared trigger function for updated_at maintenance
-- ============================================================================
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================================
-- 1. kpi_cycles
-- ============================================================================
create table if not exists public.kpi_cycles (
  id           uuid primary key default gen_random_uuid(),
  period_month date not null,
  status       text not null default 'open' check (status in ('open', 'locked')),
  opened_by    uuid references public.employees(id),
  locked_at    timestamptz,
  lock_day     integer not null default 25 check (lock_day between 1 and 31),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id),
  constraint kpi_cycles_period_month_uniq unique (period_month)
);
comment on table public.kpi_cycles is 'دورات مؤشرات الأداء الشهرية (مفتوحة/مقفلة).';
create index if not exists idx_kpi_cycles_status on public.kpi_cycles (status);
create index if not exists idx_kpi_cycles_period_month on public.kpi_cycles (period_month);

drop trigger if exists trg_kpi_cycles_updated_at on public.kpi_cycles;
create trigger trg_kpi_cycles_updated_at
  before update on public.kpi_cycles
  for each row execute function public.tg_set_updated_at();

alter table public.kpi_cycles enable row level security;

drop policy if exists kpi_cycles_select on public.kpi_cycles;
create policy kpi_cycles_select on public.kpi_cycles
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.self_assess','performance.kpi.manager_assess','performance.kpi.hr_review','performance.kpi.executive_review']));

drop policy if exists kpi_cycles_insert on public.kpi_cycles;
create policy kpi_cycles_insert on public.kpi_cycles
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_cycles_update on public.kpi_cycles;
create policy kpi_cycles_update on public.kpi_cycles
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_cycles_delete on public.kpi_cycles;
create policy kpi_cycles_delete on public.kpi_cycles
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 2. kpi_templates  (non-sensitive catalog: read allowed to all authenticated)
-- ============================================================================
create table if not exists public.kpi_templates (
  id          uuid primary key default gen_random_uuid(),
  name_ar     text not null,
  is_active   boolean not null default true,
  version     integer not null default 1 check (version >= 1),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  created_by  uuid references auth.users(id)
);
comment on table public.kpi_templates is 'قوالب مؤشرات الأداء (كتالوج غير حساس).';
create index if not exists idx_kpi_templates_is_active on public.kpi_templates (is_active);

drop trigger if exists trg_kpi_templates_updated_at on public.kpi_templates;
create trigger trg_kpi_templates_updated_at
  before update on public.kpi_templates
  for each row execute function public.tg_set_updated_at();

alter table public.kpi_templates enable row level security;

drop policy if exists kpi_templates_select on public.kpi_templates;
create policy kpi_templates_select on public.kpi_templates
  for select to authenticated
  using (true);

drop policy if exists kpi_templates_insert on public.kpi_templates;
create policy kpi_templates_insert on public.kpi_templates
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_templates_update on public.kpi_templates;
create policy kpi_templates_update on public.kpi_templates
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_templates_delete on public.kpi_templates;
create policy kpi_templates_delete on public.kpi_templates
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 3. kpi_criteria  (non-sensitive catalog)
-- ============================================================================
create table if not exists public.kpi_criteria (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.kpi_templates(id) on delete cascade,
  name_ar     text not null,
  weight      numeric(6,2) not null default 0 check (weight >= 0),
  max_score   numeric(6,2) not null default 100 check (max_score > 0),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  created_by  uuid references auth.users(id)
);
comment on table public.kpi_criteria is 'معايير القوالب لمؤشرات الأداء (كتالوج غير حساس).';
create index if not exists idx_kpi_criteria_template_id on public.kpi_criteria (template_id);
create index if not exists idx_kpi_criteria_sort_order on public.kpi_criteria (template_id, sort_order);

drop trigger if exists trg_kpi_criteria_updated_at on public.kpi_criteria;
create trigger trg_kpi_criteria_updated_at
  before update on public.kpi_criteria
  for each row execute function public.tg_set_updated_at();

alter table public.kpi_criteria enable row level security;

drop policy if exists kpi_criteria_select on public.kpi_criteria;
create policy kpi_criteria_select on public.kpi_criteria
  for select to authenticated
  using (true);

drop policy if exists kpi_criteria_insert on public.kpi_criteria;
create policy kpi_criteria_insert on public.kpi_criteria
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_criteria_update on public.kpi_criteria;
create policy kpi_criteria_update on public.kpi_criteria
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists kpi_criteria_delete on public.kpi_criteria;
create policy kpi_criteria_delete on public.kpi_criteria
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 4. kpi_evaluations  (SENSITIVE: scoped by can_access_employee)
-- ============================================================================
create table if not exists public.kpi_evaluations (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  cycle_id       uuid not null references public.kpi_cycles(id) on delete cascade,
  template_id    uuid references public.kpi_templates(id),
  stage          text not null default 'self' check (stage in ('self','manager','hr','secretary','executive','finalized')),
  current_stage  text not null default 'self' check (current_stage in ('self','manager','hr','secretary','executive','finalized')),
  final_score    numeric(6,2),
  final_rating   text,
  locked         boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id),
  constraint kpi_evaluations_uniq unique (employee_id, cycle_id, template_id)
);
comment on table public.kpi_evaluations is 'تقييمات مؤشرات الأداء للموظفين عبر مراحل الاعتماد (حساس).';
create index if not exists idx_kpi_evaluations_employee_id on public.kpi_evaluations (employee_id);
create index if not exists idx_kpi_evaluations_cycle_id on public.kpi_evaluations (cycle_id);
create index if not exists idx_kpi_evaluations_stage on public.kpi_evaluations (stage);

drop trigger if exists trg_kpi_evaluations_updated_at on public.kpi_evaluations;
create trigger trg_kpi_evaluations_updated_at
  before update on public.kpi_evaluations
  for each row execute function public.tg_set_updated_at();

alter table public.kpi_evaluations enable row level security;

drop policy if exists kpi_evaluations_select on public.kpi_evaluations;
create policy kpi_evaluations_select on public.kpi_evaluations
  for select to authenticated
  using (public.current_is_full_access() or public.can_access_employee(employee_id));

-- self-assessment insert: employee inserts own evaluation with self permission
drop policy if exists kpi_evaluations_insert on public.kpi_evaluations;
create policy kpi_evaluations_insert on public.kpi_evaluations
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or (public.has_permission('performance.kpi.self_assess') and employee_id = public.current_employee_id())
    or public.has_any_permission(array['performance.kpi.manager_assess','performance.kpi.hr_review','performance.kpi.executive_review','performance.cycle.manage'])
  );

-- update: DIRECT updates restricted to full-access only (administrative correction).
-- All stage transitions (self->manager->hr->secretary->executive->finalized) MUST go
-- through public.advance_kpi_stage() below, which enforces stage ordering and per-stage
-- ownership. This prevents stage-skipping and cross-stage field tampering via raw UPDATE.
drop policy if exists kpi_evaluations_update on public.kpi_evaluations;
create policy kpi_evaluations_update on public.kpi_evaluations
  for update to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

drop policy if exists kpi_evaluations_delete on public.kpi_evaluations;
create policy kpi_evaluations_delete on public.kpi_evaluations
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 5. kpi_scores  (SENSITIVE: scoped via parent evaluation employee)
-- ============================================================================
create table if not exists public.kpi_scores (
  id             uuid primary key default gen_random_uuid(),
  evaluation_id  uuid not null references public.kpi_evaluations(id) on delete cascade,
  criterion_id   uuid not null references public.kpi_criteria(id),
  score          numeric(6,2) not null check (score >= 0),
  reviewer_stage text not null check (reviewer_stage in ('self','manager','hr','secretary','executive','finalized')),
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id),
  constraint kpi_scores_uniq unique (evaluation_id, criterion_id, reviewer_stage)
);
comment on table public.kpi_scores is 'درجات معايير التقييم لكل مرحلة مراجعة (حساس).';
create index if not exists idx_kpi_scores_evaluation_id on public.kpi_scores (evaluation_id);
create index if not exists idx_kpi_scores_criterion_id on public.kpi_scores (criterion_id);

drop trigger if exists trg_kpi_scores_updated_at on public.kpi_scores;
create trigger trg_kpi_scores_updated_at
  before update on public.kpi_scores
  for each row execute function public.tg_set_updated_at();

alter table public.kpi_scores enable row level security;

drop policy if exists kpi_scores_select on public.kpi_scores;
create policy kpi_scores_select on public.kpi_scores
  for select to authenticated
  using (
    public.current_is_full_access()
    or exists (
      select 1 from public.kpi_evaluations e
      where e.id = evaluation_id and public.can_access_employee(e.employee_id)
    )
  );

drop policy if exists kpi_scores_insert on public.kpi_scores;
create policy kpi_scores_insert on public.kpi_scores
  for insert to authenticated
  with check (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager')
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary'))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive')
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized')
    )
  );

drop policy if exists kpi_scores_update on public.kpi_scores;
create policy kpi_scores_update on public.kpi_scores
  for update to authenticated
  using (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager')
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary'))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive')
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized')
    )
  )
  with check (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager')
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary'))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive')
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized')
    )
  );

drop policy if exists kpi_scores_delete on public.kpi_scores;
create policy kpi_scores_delete on public.kpi_scores
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 6. monthly_evaluations  (SENSITIVE: scoped by can_access_employee)
-- ============================================================================
create table if not exists public.monthly_evaluations (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.employees(id) on delete cascade,
  period_month     date not null,
  attendance_score numeric(6,2) check (attendance_score >= 0),
  efficiency_score numeric(6,2) check (efficiency_score >= 0),
  conduct_score    numeric(6,2) check (conduct_score >= 0),
  total            numeric(6,2) check (total >= 0),
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id),
  constraint monthly_evaluations_uniq unique (employee_id, period_month)
);
comment on table public.monthly_evaluations is 'التقييمات الشهرية المختصرة للموظفين (حساس).';
create index if not exists idx_monthly_evaluations_employee_id on public.monthly_evaluations (employee_id);
create index if not exists idx_monthly_evaluations_period_month on public.monthly_evaluations (period_month);

drop trigger if exists trg_monthly_evaluations_updated_at on public.monthly_evaluations;
create trigger trg_monthly_evaluations_updated_at
  before update on public.monthly_evaluations
  for each row execute function public.tg_set_updated_at();

alter table public.monthly_evaluations enable row level security;

drop policy if exists monthly_evaluations_select on public.monthly_evaluations;
create policy monthly_evaluations_select on public.monthly_evaluations
  for select to authenticated
  using (public.current_is_full_access() or public.can_access_employee(employee_id));

drop policy if exists monthly_evaluations_insert on public.monthly_evaluations;
create policy monthly_evaluations_insert on public.monthly_evaluations
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.manager_assess','performance.kpi.hr_review']));

drop policy if exists monthly_evaluations_update on public.monthly_evaluations;
create policy monthly_evaluations_update on public.monthly_evaluations
  for update to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.manager_assess','performance.kpi.hr_review']))
  with check (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.manager_assess','performance.kpi.hr_review']));

drop policy if exists monthly_evaluations_delete on public.monthly_evaluations;
create policy monthly_evaluations_delete on public.monthly_evaluations
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.kpi.hr_review'));

-- ============================================================================
-- 7. goal_objectives  (SENSITIVE when owner is employee: scoped)
-- ============================================================================
create table if not exists public.goal_objectives (
  id                  uuid primary key default gen_random_uuid(),
  owner_type          text not null check (owner_type in ('org','dept','team','employee')),
  owner_id            uuid,
  cycle_id            uuid references public.kpi_cycles(id) on delete set null,
  title               text not null,
  weight              numeric(6,2) not null default 0 check (weight >= 0),
  status              text not null default 'active' check (status in ('draft','active','on_track','at_risk','behind','completed','cancelled')),
  parent_objective_id uuid references public.goal_objectives(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id)
);
comment on table public.goal_objectives is 'الأهداف (OKR) على مستوى المنظمة/الإدارة/الفريق/الموظف.';
create index if not exists idx_goal_objectives_owner on public.goal_objectives (owner_type, owner_id);
create index if not exists idx_goal_objectives_cycle_id on public.goal_objectives (cycle_id);
create index if not exists idx_goal_objectives_parent on public.goal_objectives (parent_objective_id);

drop trigger if exists trg_goal_objectives_updated_at on public.goal_objectives;
create trigger trg_goal_objectives_updated_at
  before update on public.goal_objectives
  for each row execute function public.tg_set_updated_at();

alter table public.goal_objectives enable row level security;

drop policy if exists goal_objectives_select on public.goal_objectives;
create policy goal_objectives_select on public.goal_objectives
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.view')
    or (owner_type = 'employee' and owner_id is not null and public.can_access_employee(owner_id))
    or (owner_type <> 'employee')
  );

drop policy if exists goal_objectives_insert on public.goal_objectives;
create policy goal_objectives_insert on public.goal_objectives
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (owner_type = 'employee' and owner_id = public.current_employee_id() and public.has_permission('performance.goals.own'))
  );

drop policy if exists goal_objectives_update on public.goal_objectives;
create policy goal_objectives_update on public.goal_objectives
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (owner_type = 'employee' and owner_id = public.current_employee_id() and public.has_permission('performance.goals.own'))
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (owner_type = 'employee' and owner_id = public.current_employee_id() and public.has_permission('performance.goals.own'))
  );

drop policy if exists goal_objectives_delete on public.goal_objectives;
create policy goal_objectives_delete on public.goal_objectives
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.goals.manage'));

-- ============================================================================
-- 8. goal_key_results  (scoped via parent objective)
-- ============================================================================
create table if not exists public.goal_key_results (
  id            uuid primary key default gen_random_uuid(),
  objective_id  uuid not null references public.goal_objectives(id) on delete cascade,
  title         text not null,
  metric_type   text not null default 'number' check (metric_type in ('number','percent','currency','boolean')),
  start_value   numeric(18,4) not null default 0,
  target_value  numeric(18,4) not null default 0,
  current_value numeric(18,4) not null default 0,
  progress_pct  numeric(6,2) not null default 0 check (progress_pct >= 0 and progress_pct <= 100),
  due_date      date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  created_by    uuid references auth.users(id)
);
comment on table public.goal_key_results is 'النتائج الرئيسية المرتبطة بالأهداف (Key Results).';
create index if not exists idx_goal_key_results_objective_id on public.goal_key_results (objective_id);
create index if not exists idx_goal_key_results_due_date on public.goal_key_results (due_date);

drop trigger if exists trg_goal_key_results_updated_at on public.goal_key_results;
create trigger trg_goal_key_results_updated_at
  before update on public.goal_key_results
  for each row execute function public.tg_set_updated_at();

alter table public.goal_key_results enable row level security;

drop policy if exists goal_key_results_select on public.goal_key_results;
create policy goal_key_results_select on public.goal_key_results
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.view')
    or exists (
      select 1 from public.goal_objectives o
      where o.id = objective_id
        and (o.owner_type <> 'employee' or (o.owner_id is not null and public.can_access_employee(o.owner_id)))
    )
  );

drop policy if exists goal_key_results_insert on public.goal_key_results;
create policy goal_key_results_insert on public.goal_key_results
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or exists (
      select 1 from public.goal_objectives o
      where o.id = objective_id
        and o.owner_type = 'employee' and o.owner_id = public.current_employee_id()
        and public.has_permission('performance.goals.own')
    )
  );

drop policy if exists goal_key_results_update on public.goal_key_results;
create policy goal_key_results_update on public.goal_key_results
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or exists (
      select 1 from public.goal_objectives o
      where o.id = objective_id
        and o.owner_type = 'employee' and o.owner_id = public.current_employee_id()
        and public.has_permission('performance.goals.own')
    )
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or exists (
      select 1 from public.goal_objectives o
      where o.id = objective_id
        and o.owner_type = 'employee' and o.owner_id = public.current_employee_id()
        and public.has_permission('performance.goals.own')
    )
  );

drop policy if exists goal_key_results_delete on public.goal_key_results;
create policy goal_key_results_delete on public.goal_key_results
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.goals.manage'));

-- ============================================================================
-- 9. goal_checkins  (scoped via key result -> objective)
-- ============================================================================
create table if not exists public.goal_checkins (
  id            uuid primary key default gen_random_uuid(),
  key_result_id uuid not null references public.goal_key_results(id) on delete cascade,
  author_id     uuid references public.employees(id),
  new_value     numeric(18,4) not null,
  confidence    text check (confidence in ('low','medium','high')),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  created_by    uuid references auth.users(id)
);
comment on table public.goal_checkins is 'تحديثات دورية على النتائج الرئيسية (Check-ins).';
create index if not exists idx_goal_checkins_key_result_id on public.goal_checkins (key_result_id);
create index if not exists idx_goal_checkins_author_id on public.goal_checkins (author_id);

drop trigger if exists trg_goal_checkins_updated_at on public.goal_checkins;
create trigger trg_goal_checkins_updated_at
  before update on public.goal_checkins
  for each row execute function public.tg_set_updated_at();

alter table public.goal_checkins enable row level security;

drop policy if exists goal_checkins_select on public.goal_checkins;
create policy goal_checkins_select on public.goal_checkins
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.view')
    or exists (
      select 1 from public.goal_key_results kr
      join public.goal_objectives o on o.id = kr.objective_id
      where kr.id = key_result_id
        and (o.owner_type <> 'employee' or (o.owner_id is not null and public.can_access_employee(o.owner_id)))
    )
  );

drop policy if exists goal_checkins_insert on public.goal_checkins;
create policy goal_checkins_insert on public.goal_checkins
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (public.has_permission('performance.goals.own') and author_id = public.current_employee_id())
  );

drop policy if exists goal_checkins_update on public.goal_checkins;
create policy goal_checkins_update on public.goal_checkins
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (public.has_permission('performance.goals.own') and author_id = public.current_employee_id())
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.goals.manage')
    or (public.has_permission('performance.goals.own') and author_id = public.current_employee_id())
  );

drop policy if exists goal_checkins_delete on public.goal_checkins;
create policy goal_checkins_delete on public.goal_checkins
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.goals.manage'));

-- ============================================================================
-- 10. feedback_rounds  (SENSITIVE: scoped by subject employee)
-- ============================================================================
create table if not exists public.feedback_rounds (
  id                     uuid primary key default gen_random_uuid(),
  subject_employee_id    uuid not null references public.employees(id) on delete cascade,
  cycle_id               uuid references public.kpi_cycles(id) on delete set null,
  purpose                text not null default 'development' check (purpose in ('development','evaluation','probation','other')),
  status                 text not null default 'draft' check (status in ('draft','open','closed','revealed','cancelled')),
  min_responses_to_reveal integer not null default 3 check (min_responses_to_reveal >= 1),
  opens_at               timestamptz,
  closes_at              timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz,
  created_by             uuid references auth.users(id)
);
comment on table public.feedback_rounds is 'جولات تغذية راجعة 360 درجة لموظف (حساس).';
create index if not exists idx_feedback_rounds_subject on public.feedback_rounds (subject_employee_id);
create index if not exists idx_feedback_rounds_cycle_id on public.feedback_rounds (cycle_id);
create index if not exists idx_feedback_rounds_status on public.feedback_rounds (status);

drop trigger if exists trg_feedback_rounds_updated_at on public.feedback_rounds;
create trigger trg_feedback_rounds_updated_at
  before update on public.feedback_rounds
  for each row execute function public.tg_set_updated_at();

alter table public.feedback_rounds enable row level security;

drop policy if exists feedback_rounds_select on public.feedback_rounds;
create policy feedback_rounds_select on public.feedback_rounds
  for select to authenticated
  using (public.current_is_full_access() or public.can_access_employee(subject_employee_id) or public.has_permission('performance.feedback.manage'));

drop policy if exists feedback_rounds_insert on public.feedback_rounds;
create policy feedback_rounds_insert on public.feedback_rounds
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.feedback.manage'));

drop policy if exists feedback_rounds_update on public.feedback_rounds;
create policy feedback_rounds_update on public.feedback_rounds
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.feedback.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.feedback.manage'));

drop policy if exists feedback_rounds_delete on public.feedback_rounds;
create policy feedback_rounds_delete on public.feedback_rounds
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.feedback.manage'));

-- ============================================================================
-- 11. feedback_raters  (SENSITIVE: scoped via round)
-- ============================================================================
create table if not exists public.feedback_raters (
  id           uuid primary key default gen_random_uuid(),
  round_id     uuid not null references public.feedback_rounds(id) on delete cascade,
  rater_id     uuid references public.employees(id),
  relationship text not null check (relationship in ('self','manager','peer','report','stakeholder')),
  status       text not null default 'invited' check (status in ('invited','in_progress','submitted','declined')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id),
  constraint feedback_raters_uniq unique (round_id, rater_id)
);
comment on table public.feedback_raters is 'المقيّمون المدعوون ضمن جولة التغذية الراجعة (حساس).';
create index if not exists idx_feedback_raters_round_id on public.feedback_raters (round_id);
create index if not exists idx_feedback_raters_rater_id on public.feedback_raters (rater_id);

drop trigger if exists trg_feedback_raters_updated_at on public.feedback_raters;
create trigger trg_feedback_raters_updated_at
  before update on public.feedback_raters
  for each row execute function public.tg_set_updated_at();

alter table public.feedback_raters enable row level security;

drop policy if exists feedback_raters_select on public.feedback_raters;
create policy feedback_raters_select on public.feedback_raters
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.feedback.manage')
    or rater_id = public.current_employee_id()
    or exists (
      select 1 from public.feedback_rounds r
      where r.id = round_id and public.can_access_employee(r.subject_employee_id)
    )
  );

drop policy if exists feedback_raters_insert on public.feedback_raters;
create policy feedback_raters_insert on public.feedback_raters
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.feedback.manage'));

drop policy if exists feedback_raters_update on public.feedback_raters;
create policy feedback_raters_update on public.feedback_raters
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.feedback.manage')
    or rater_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.feedback.manage')
    or rater_id = public.current_employee_id()
  );

drop policy if exists feedback_raters_delete on public.feedback_raters;
create policy feedback_raters_delete on public.feedback_raters
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.feedback.manage'));

-- ============================================================================
-- 12. competencies  (non-sensitive catalog)
-- ============================================================================
create table if not exists public.competencies (
  id         uuid primary key default gen_random_uuid(),
  name_ar    text not null,
  name_en    text,
  category   text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);
comment on table public.competencies is 'الجدارات (كتالوج غير حساس).';
create index if not exists idx_competencies_is_active on public.competencies (is_active);
create index if not exists idx_competencies_category on public.competencies (category);

drop trigger if exists trg_competencies_updated_at on public.competencies;
create trigger trg_competencies_updated_at
  before update on public.competencies
  for each row execute function public.tg_set_updated_at();

alter table public.competencies enable row level security;

drop policy if exists competencies_select on public.competencies;
create policy competencies_select on public.competencies
  for select to authenticated
  using (true);

drop policy if exists competencies_insert on public.competencies;
create policy competencies_insert on public.competencies
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists competencies_update on public.competencies;
create policy competencies_update on public.competencies
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists competencies_delete on public.competencies;
create policy competencies_delete on public.competencies
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

-- ============================================================================
-- 13. competency_levels  (non-sensitive catalog)
-- ============================================================================
create table if not exists public.competency_levels (
  id                    uuid primary key default gen_random_uuid(),
  competency_id         uuid not null references public.competencies(id) on delete cascade,
  level_order           integer not null check (level_order >= 1),
  label                 text not null,
  behavioral_indicators text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  constraint competency_levels_uniq unique (competency_id, level_order)
);
comment on table public.competency_levels is 'مستويات الجدارة ومؤشراتها السلوكية (كتالوج غير حساس).';
create index if not exists idx_competency_levels_competency_id on public.competency_levels (competency_id);

drop trigger if exists trg_competency_levels_updated_at on public.competency_levels;
create trigger trg_competency_levels_updated_at
  before update on public.competency_levels
  for each row execute function public.tg_set_updated_at();

alter table public.competency_levels enable row level security;

drop policy if exists competency_levels_select on public.competency_levels;
create policy competency_levels_select on public.competency_levels
  for select to authenticated
  using (true);

drop policy if exists competency_levels_insert on public.competency_levels;
create policy competency_levels_insert on public.competency_levels
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists competency_levels_update on public.competency_levels;
create policy competency_levels_update on public.competency_levels
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists competency_levels_delete on public.competency_levels;
create policy competency_levels_delete on public.competency_levels
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

-- ============================================================================
-- 14. role_competency_profiles  (non-sensitive catalog: role -> expected level)
-- ============================================================================
create table if not exists public.role_competency_profiles (
  id                uuid primary key default gen_random_uuid(),
  role_or_title_id  uuid not null references public.roles(id) on delete cascade,
  competency_id     uuid not null references public.competencies(id) on delete cascade,
  expected_level    integer not null check (expected_level >= 1),
  is_critical       boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint role_competency_profiles_uniq unique (role_or_title_id, competency_id)
);
comment on table public.role_competency_profiles is 'المستويات المتوقعة من الجدارات لكل دور/مسمى (كتالوج غير حساس).';
create index if not exists idx_role_comp_profiles_role on public.role_competency_profiles (role_or_title_id);
create index if not exists idx_role_comp_profiles_competency on public.role_competency_profiles (competency_id);

drop trigger if exists trg_role_competency_profiles_updated_at on public.role_competency_profiles;
create trigger trg_role_competency_profiles_updated_at
  before update on public.role_competency_profiles
  for each row execute function public.tg_set_updated_at();

alter table public.role_competency_profiles enable row level security;

drop policy if exists role_competency_profiles_select on public.role_competency_profiles;
create policy role_competency_profiles_select on public.role_competency_profiles
  for select to authenticated
  using (true);

drop policy if exists role_competency_profiles_insert on public.role_competency_profiles;
create policy role_competency_profiles_insert on public.role_competency_profiles
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists role_competency_profiles_update on public.role_competency_profiles;
create policy role_competency_profiles_update on public.role_competency_profiles
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

drop policy if exists role_competency_profiles_delete on public.role_competency_profiles;
create policy role_competency_profiles_delete on public.role_competency_profiles
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.manage'));

-- ============================================================================
-- 15. employee_competency_assessments  (SENSITIVE: scoped by employee)
-- ============================================================================
create table if not exists public.employee_competency_assessments (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  competency_id  uuid not null references public.competencies(id) on delete cascade,
  assessed_level integer not null check (assessed_level >= 1),
  source         text not null default 'manager' check (source in ('self','manager','peer','hr','system')),
  cycle_id       uuid references public.kpi_cycles(id) on delete set null,
  assessor_id    uuid references public.employees(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id)
);
comment on table public.employee_competency_assessments is 'تقييمات جدارات الموظفين (حساس).';
create index if not exists idx_emp_comp_assess_employee on public.employee_competency_assessments (employee_id);
create index if not exists idx_emp_comp_assess_competency on public.employee_competency_assessments (competency_id);
create index if not exists idx_emp_comp_assess_cycle on public.employee_competency_assessments (cycle_id);

drop trigger if exists trg_emp_comp_assess_updated_at on public.employee_competency_assessments;
create trigger trg_emp_comp_assess_updated_at
  before update on public.employee_competency_assessments
  for each row execute function public.tg_set_updated_at();

alter table public.employee_competency_assessments enable row level security;

drop policy if exists emp_comp_assess_select on public.employee_competency_assessments;
create policy emp_comp_assess_select on public.employee_competency_assessments
  for select to authenticated
  using (public.current_is_full_access() or public.can_access_employee(employee_id));

drop policy if exists emp_comp_assess_insert on public.employee_competency_assessments;
create policy emp_comp_assess_insert on public.employee_competency_assessments
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.competency.assess')
    or (source = 'self' and employee_id = public.current_employee_id() and public.has_permission('performance.competency.self_assess'))
  );

drop policy if exists emp_comp_assess_update on public.employee_competency_assessments;
create policy emp_comp_assess_update on public.employee_competency_assessments
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.competency.assess')
    or (source = 'self' and employee_id = public.current_employee_id() and public.has_permission('performance.competency.self_assess'))
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.competency.assess')
    or (source = 'self' and employee_id = public.current_employee_id() and public.has_permission('performance.competency.self_assess'))
  );

drop policy if exists emp_comp_assess_delete on public.employee_competency_assessments;
create policy emp_comp_assess_delete on public.employee_competency_assessments
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.competency.assess'));

-- ============================================================================
-- 16. calibration_sessions  (SENSITIVE)
-- ============================================================================
create table if not exists public.calibration_sessions (
  id                  uuid primary key default gen_random_uuid(),
  cycle_id            uuid references public.kpi_cycles(id) on delete set null,
  scope_dept_id       uuid,
  facilitator_id      uuid references public.employees(id),
  status              text not null default 'draft' check (status in ('draft','scheduled','in_progress','completed','cancelled')),
  target_distribution jsonb not null default '{}'::jsonb,
  held_at             timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id)
);
comment on table public.calibration_sessions is 'جلسات معايرة التقييمات (حساس).';
create index if not exists idx_calibration_sessions_cycle on public.calibration_sessions (cycle_id);
create index if not exists idx_calibration_sessions_status on public.calibration_sessions (status);

drop trigger if exists trg_calibration_sessions_updated_at on public.calibration_sessions;
create trigger trg_calibration_sessions_updated_at
  before update on public.calibration_sessions
  for each row execute function public.tg_set_updated_at();

alter table public.calibration_sessions enable row level security;

drop policy if exists calibration_sessions_select on public.calibration_sessions;
create policy calibration_sessions_select on public.calibration_sessions
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['performance.calibration.manage','performance.calibration.view']));

drop policy if exists calibration_sessions_insert on public.calibration_sessions;
create policy calibration_sessions_insert on public.calibration_sessions
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.calibration.manage'));

drop policy if exists calibration_sessions_update on public.calibration_sessions;
create policy calibration_sessions_update on public.calibration_sessions
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.calibration.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.calibration.manage'));

drop policy if exists calibration_sessions_delete on public.calibration_sessions;
create policy calibration_sessions_delete on public.calibration_sessions
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.calibration.manage'));

-- ============================================================================
-- 17. review_cycle_templates  (non-sensitive catalog)
-- ============================================================================
create table if not exists public.review_cycle_templates (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  type              text not null default 'annual' check (type in ('annual','semiannual','probation','project')),
  components_weight jsonb not null default '{}'::jsonb,
  stage_flow        jsonb not null default '[]'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id)
);
comment on table public.review_cycle_templates is 'قوالب دورات المراجعة (سنوية/نصف سنوية/فترة تجربة/مشروع) - كتالوج غير حساس.';
create index if not exists idx_review_cycle_templates_type on public.review_cycle_templates (type);

drop trigger if exists trg_review_cycle_templates_updated_at on public.review_cycle_templates;
create trigger trg_review_cycle_templates_updated_at
  before update on public.review_cycle_templates
  for each row execute function public.tg_set_updated_at();

alter table public.review_cycle_templates enable row level security;

drop policy if exists review_cycle_templates_select on public.review_cycle_templates;
create policy review_cycle_templates_select on public.review_cycle_templates
  for select to authenticated
  using (true);

drop policy if exists review_cycle_templates_insert on public.review_cycle_templates;
create policy review_cycle_templates_insert on public.review_cycle_templates
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists review_cycle_templates_update on public.review_cycle_templates;
create policy review_cycle_templates_update on public.review_cycle_templates
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists review_cycle_templates_delete on public.review_cycle_templates;
create policy review_cycle_templates_delete on public.review_cycle_templates
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 18. review_cycle_instances  (SENSITIVE-ish: gated by cycle.manage/view)
-- ============================================================================
create table if not exists public.review_cycle_instances (
  id                  uuid primary key default gen_random_uuid(),
  template_id         uuid not null references public.review_cycle_templates(id),
  period_start        date not null,
  period_end          date not null,
  status              text not null default 'draft' check (status in ('draft','active','in_review','locked','closed','cancelled')),
  linked_kpi_cycle_id uuid references public.kpi_cycles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id),
  constraint review_cycle_instances_period_chk check (period_end >= period_start)
);
comment on table public.review_cycle_instances is 'نُسخ دورات المراجعة الفعلية المرتبطة بالقوالب ودورات KPI.';
create index if not exists idx_review_cycle_instances_template on public.review_cycle_instances (template_id);
create index if not exists idx_review_cycle_instances_status on public.review_cycle_instances (status);
create index if not exists idx_review_cycle_instances_kpi on public.review_cycle_instances (linked_kpi_cycle_id);

drop trigger if exists trg_review_cycle_instances_updated_at on public.review_cycle_instances;
create trigger trg_review_cycle_instances_updated_at
  before update on public.review_cycle_instances
  for each row execute function public.tg_set_updated_at();

alter table public.review_cycle_instances enable row level security;

drop policy if exists review_cycle_instances_select on public.review_cycle_instances;
create policy review_cycle_instances_select on public.review_cycle_instances
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.self_assess','performance.kpi.manager_assess','performance.kpi.hr_review','performance.kpi.executive_review']));

drop policy if exists review_cycle_instances_insert on public.review_cycle_instances;
create policy review_cycle_instances_insert on public.review_cycle_instances
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists review_cycle_instances_update on public.review_cycle_instances;
create policy review_cycle_instances_update on public.review_cycle_instances
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

drop policy if exists review_cycle_instances_delete on public.review_cycle_instances;
create policy review_cycle_instances_delete on public.review_cycle_instances
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.cycle.manage'));

-- ============================================================================
-- 19. improvement_plans  (SENSITIVE: scoped by employee)
-- ============================================================================
create table if not exists public.improvement_plans (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  type           text not null default 'pip' check (type in ('pip','idp')),
  trigger_source text,
  start_date     date,
  end_date       date,
  status         text not null default 'draft' check (status in ('draft','active','on_hold','completed','failed','cancelled')),
  manager_id     uuid references public.employees(id),
  hr_owner_id    uuid references public.employees(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id),
  constraint improvement_plans_dates_chk check (end_date is null or start_date is null or end_date >= start_date)
);
comment on table public.improvement_plans is 'خطط التحسين (PIP) والتطوير الفردي (IDP) - حساس.';
create index if not exists idx_improvement_plans_employee on public.improvement_plans (employee_id);
create index if not exists idx_improvement_plans_status on public.improvement_plans (status);
create index if not exists idx_improvement_plans_type on public.improvement_plans (type);

drop trigger if exists trg_improvement_plans_updated_at on public.improvement_plans;
create trigger trg_improvement_plans_updated_at
  before update on public.improvement_plans
  for each row execute function public.tg_set_updated_at();

alter table public.improvement_plans enable row level security;

drop policy if exists improvement_plans_select on public.improvement_plans;
create policy improvement_plans_select on public.improvement_plans
  for select to authenticated
  using (public.current_is_full_access() or public.can_access_employee(employee_id) or public.has_permission('performance.improvement.manage'));

drop policy if exists improvement_plans_insert on public.improvement_plans;
create policy improvement_plans_insert on public.improvement_plans
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('performance.improvement.manage'));

drop policy if exists improvement_plans_update on public.improvement_plans;
create policy improvement_plans_update on public.improvement_plans
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.improvement.manage'))
  with check (public.current_is_full_access() or public.has_permission('performance.improvement.manage'));

drop policy if exists improvement_plans_delete on public.improvement_plans;
create policy improvement_plans_delete on public.improvement_plans
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.improvement.manage'));

-- ============================================================================
-- 20. one_on_ones  (SENSITIVE: scoped by employee/manager)
-- ============================================================================
create table if not exists public.one_on_ones (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references public.employees(id) on delete cascade,
  manager_id   uuid references public.employees(id),
  scheduled_at timestamptz,
  agenda       text,
  notes        text,
  status       text not null default 'scheduled' check (status in ('scheduled','completed','cancelled','no_show')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id)
);
comment on table public.one_on_ones is 'اجتماعات واحد لواحد بين الموظف والمدير (حساس).';
create index if not exists idx_one_on_ones_employee on public.one_on_ones (employee_id);
create index if not exists idx_one_on_ones_manager on public.one_on_ones (manager_id);
create index if not exists idx_one_on_ones_scheduled_at on public.one_on_ones (scheduled_at);

drop trigger if exists trg_one_on_ones_updated_at on public.one_on_ones;
create trigger trg_one_on_ones_updated_at
  before update on public.one_on_ones
  for each row execute function public.tg_set_updated_at();

alter table public.one_on_ones enable row level security;

drop policy if exists one_on_ones_select on public.one_on_ones;
create policy one_on_ones_select on public.one_on_ones
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
    or manager_id = public.current_employee_id()
    or public.has_permission('performance.oneonone.manage')
  );

drop policy if exists one_on_ones_insert on public.one_on_ones;
create policy one_on_ones_insert on public.one_on_ones
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.oneonone.manage')
    or manager_id = public.current_employee_id()
    or employee_id = public.current_employee_id()
  );

drop policy if exists one_on_ones_update on public.one_on_ones;
create policy one_on_ones_update on public.one_on_ones
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('performance.oneonone.manage')
    or manager_id = public.current_employee_id()
    or employee_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('performance.oneonone.manage')
    or manager_id = public.current_employee_id()
    or employee_id = public.current_employee_id()
  );

drop policy if exists one_on_ones_delete on public.one_on_ones;
create policy one_on_ones_delete on public.one_on_ones
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('performance.oneonone.manage') or manager_id = public.current_employee_id());

-- ============================================================================
-- RPC: close_kpi_cycle — locks a cycle and freezes its evaluations
-- ============================================================================
create or replace function public.close_kpi_cycle(p_cycle_id uuid)
returns public.kpi_cycles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cycle public.kpi_cycles;
begin
  if not (public.current_is_full_access() or public.has_permission('performance.cycle.manage')) then
    raise exception 'insufficient_privilege: performance.cycle.manage required'
      using errcode = '42501';
  end if;

  select * into v_cycle from public.kpi_cycles where id = p_cycle_id for update;
  if not found then
    raise exception 'kpi_cycle % not found', p_cycle_id using errcode = 'P0002';
  end if;

  if v_cycle.status = 'locked' then
    return v_cycle;
  end if;

  update public.kpi_cycles
     set status = 'locked',
         locked_at = now(),
         updated_at = now()
   where id = p_cycle_id
   returning * into v_cycle;

  -- freeze all evaluations belonging to this cycle so no further edits are allowed
  update public.kpi_evaluations
     set locked = true,
         stage = 'finalized',
         current_stage = 'finalized',
         updated_at = now()
   where cycle_id = p_cycle_id
     and locked = false;

  return v_cycle;
end;
$$;

revoke execute on function public.close_kpi_cycle(uuid) from public;
grant execute on function public.close_kpi_cycle(uuid) to authenticated;

-- ============================================================================
-- RPC: advance_kpi_stage — the ONLY sanctioned way to move a KPI evaluation
--       through its approval stages. Enforces strict stage ordering, per-stage
--       ownership by permission, cycle/evaluation lock guards, and writes the
--       submitted scores into kpi_scores for the CURRENT stage only.
--
--   Stage order:  self -> manager -> hr -> secretary -> executive -> finalized
--   Actions map 1:1 to the stage that the caller is completing:
--     p_action = 'self'      requires performance.kpi.self_assess (own evaluation)
--     p_action = 'manager'   requires performance.kpi.manager_assess
--     p_action = 'hr'        requires performance.kpi.hr_review
--     p_action = 'secretary' requires performance.kpi.secretary_review
--     p_action = 'executive' requires performance.kpi.executive_review
--     p_action = 'finalize'  requires performance.kpi.finalize
--
--   p_scores (optional) shape:
--     [ { "criterion_id": "<uuid>", "score": <number>, "note": "<text?>" }, ... ]
--   Scores are written with reviewer_stage = the current stage being completed.
-- ============================================================================
create or replace function public.advance_kpi_stage(
  p_evaluation_id uuid,
  p_action        text,
  p_scores        jsonb default null,
  p_note          text  default null
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval        public.kpi_evaluations;
  v_cycle       public.kpi_cycles;
  v_expected    text;   -- stage the action is allowed to act on
  v_next        text;   -- stage the evaluation moves to on success
  v_perm        text;   -- permission the action requires
  v_score_stage text;   -- reviewer_stage written into kpi_scores
  v_row         jsonb;
begin
  -- Map the requested action to (expected current stage, next stage, permission).
  case p_action
    when 'self'      then v_expected := 'self';      v_next := 'manager';   v_perm := 'performance.kpi.self_assess';      v_score_stage := 'self';
    when 'manager'   then v_expected := 'manager';   v_next := 'hr';        v_perm := 'performance.kpi.manager_assess';   v_score_stage := 'manager';
    when 'hr'        then v_expected := 'hr';        v_next := 'secretary'; v_perm := 'performance.kpi.hr_review';        v_score_stage := 'hr';
    when 'secretary' then v_expected := 'secretary'; v_next := 'executive'; v_perm := 'performance.kpi.secretary_review'; v_score_stage := 'secretary';
    when 'executive' then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.executive_review'; v_score_stage := 'executive';
    when 'finalize'  then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.finalize';          v_score_stage := 'finalized';
    else
      raise exception 'invalid action %; expected one of self, manager, hr, secretary, executive, finalize', p_action
        using errcode = '22023';
  end case;

  -- Lock the evaluation row for the duration of the transition.
  select * into v_eval from public.kpi_evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'kpi_evaluation % not found', p_evaluation_id using errcode = 'P0002';
  end if;

  -- Reject any edit when the evaluation itself is locked.
  if v_eval.locked then
    raise exception 'kpi_evaluation % is locked', p_evaluation_id using errcode = '55000';
  end if;

  -- Reject when the parent cycle is locked.
  select * into v_cycle from public.kpi_cycles where id = v_eval.cycle_id;
  if not found then
    raise exception 'kpi_cycle % not found', v_eval.cycle_id using errcode = 'P0002';
  end if;
  if v_cycle.status = 'locked' then
    raise exception 'kpi_cycle % is locked', v_eval.cycle_id using errcode = '55000';
  end if;

  -- Permission gate: only the owner of this stage may move it (full-access bypasses).
  if not (public.current_is_full_access() or public.has_permission(v_perm)) then
    raise exception 'insufficient_privilege: % required', v_perm using errcode = '42501';
  end if;

  -- self stage may only be advanced by the evaluated employee.
  if p_action = 'self'
     and not public.current_is_full_access()
     and v_eval.employee_id is distinct from public.current_employee_id() then
    raise exception 'insufficient_privilege: self assessment restricted to the evaluated employee'
      using errcode = '42501';
  end if;

  -- Strict ordering: the evaluation must currently sit at the expected stage.
  -- This forbids skipping a stage or re-running a completed one.
  if v_eval.current_stage is distinct from v_expected then
    raise exception 'stage_out_of_order: action % requires current stage % but evaluation is at %',
      p_action, v_expected, v_eval.current_stage
      using errcode = '55000';
  end if;

  -- Persist scores for the CURRENT stage only (never for other stages).
  if p_scores is not null then
    for v_row in select * from jsonb_array_elements(p_scores)
    loop
      insert into public.kpi_scores (evaluation_id, criterion_id, score, reviewer_stage, note, created_by)
      values (
        p_evaluation_id,
        (v_row->>'criterion_id')::uuid,
        (v_row->>'score')::numeric,
        v_score_stage,
        coalesce(v_row->>'note', p_note),
        auth.uid()
      )
      on conflict (evaluation_id, criterion_id, reviewer_stage)
      do update set score = excluded.score,
                    note  = excluded.note,
                    updated_at = now();
    end loop;
  end if;

  -- Advance the stage. Finalizing also freezes the evaluation.
  update public.kpi_evaluations
     set stage         = v_next,
         current_stage = v_next,
         locked        = (v_next = 'finalized'),
         updated_at    = now()
   where id = p_evaluation_id
   returning * into v_eval;

  return v_eval;
end;
$$;

revoke execute on function public.advance_kpi_stage(uuid, text, jsonb, text) from public;
grant execute on function public.advance_kpi_stage(uuid, text, jsonb, text) to authenticated;

-- ============================================================================
-- RPC: close_kpi_cycle_due — cron entry point. Locks every open kpi_cycle whose
--       configured lock_day has arrived in Africa/Cairo local time, delegating to
--       close_kpi_cycle() so evaluations are frozen consistently.
--
--   Suggested schedule (documentation only; wire up via pg_cron / Supabase
--   scheduled functions — NOT created here):
--     select cron.schedule('close-kpi-cycles-due', '5 0 * * *',
--       $cron$ select public.close_kpi_cycle_due(); $cron$);
--   (Runs daily just after local midnight; each run locks cycles whose lock_day
--    is today or already past for their period.)
-- ============================================================================
create or replace function public.close_kpi_cycle_due()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_cycle  record;
  v_count  integer := 0;
begin
  for v_cycle in
    select c.id, c.period_month, c.lock_day
      from public.kpi_cycles c
     where c.status = 'open'
  loop
    -- The lock date for a cycle = its period month + (lock_day - 1) days, clamped
    -- to the last valid day of that month. When today (Cairo) reaches that date, lock.
    if v_today >= least(
         date_trunc('month', v_cycle.period_month)::date + (v_cycle.lock_day - 1),
         (date_trunc('month', v_cycle.period_month)::date + interval '1 month - 1 day')::date
       ) then
      -- Inline the lock (do NOT call close_kpi_cycle, which enforces a caller
      -- permission check meaningless under cron where there is no auth user).
      update public.kpi_cycles
         set status = 'locked',
             locked_at = now(),
             updated_at = now()
       where id = v_cycle.id
         and status <> 'locked';

      -- Freeze all still-open evaluations of this cycle.
      update public.kpi_evaluations
         set locked = true,
             stage = 'finalized',
             current_stage = 'finalized',
             updated_at = now()
       where cycle_id = v_cycle.id
         and locked = false;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- Cron-only entry point: not exposed to end users. Kept off PUBLIC; granted to
-- the service/postgres role that the scheduler runs as.
revoke execute on function public.close_kpi_cycle_due() from public;
grant execute on function public.close_kpi_cycle_due() to postgres, service_role;

commit;
