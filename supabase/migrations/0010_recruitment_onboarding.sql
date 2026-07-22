-- Migration 0010: التوظيف والإلحاق (ATS)
-- Recruitment & Onboarding domain (Applicant Tracking System)
-- Depends on: 0003 (public.departments), 0004 (public.employees),
--             permission helper functions:
--               public.current_is_full_access()
--               public.has_permission(text)
--               public.has_any_permission(text[])
--               public.can_access_employee(uuid)
--               public.current_employee_id()

-- =====================================================================
-- Shared trigger function: keep updated_at fresh on every UPDATE.
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
  'Trigger helper: sets updated_at = now() on row UPDATE.';

-- =====================================================================
-- 1. job_requisitions
-- =====================================================================
create table if not exists public.job_requisitions (
  id            uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete restrict,
  title         text not null,
  headcount     integer not null default 1 check (headcount > 0),
  reason        text,
  budget_range  text,
  status        text not null default 'draft'
                  check (status in ('draft','pending','approved','posted','closed')),
  requested_by  uuid references public.employees(id) on delete set null,
  current_stage text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  created_by    uuid references auth.users(id) on delete set null
);

comment on table public.job_requisitions is 'طلبات فتح الوظائف (Job requisitions) وحالتها.';

create index if not exists idx_job_requisitions_department on public.job_requisitions(department_id);
create index if not exists idx_job_requisitions_status     on public.job_requisitions(status);

alter table public.job_requisitions enable row level security;

drop trigger if exists trg_job_requisitions_updated_at on public.job_requisitions;
create trigger trg_job_requisitions_updated_at
  before update on public.job_requisitions
  for each row execute function public.tg_set_updated_at();

create policy job_requisitions_select on public.job_requisitions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.requisition.read','recruitment.requisition.manage'])
  );

create policy job_requisitions_insert on public.job_requisitions
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

create policy job_requisitions_update on public.job_requisitions
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

create policy job_requisitions_delete on public.job_requisitions
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

-- =====================================================================
-- 2. job_requisition_approvals
-- =====================================================================
create table if not exists public.job_requisition_approvals (
  id             uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references public.job_requisitions(id) on delete cascade,
  stage          text not null,
  approver_id    uuid references public.employees(id) on delete set null,
  decision       text not null default 'pending'
                   check (decision in ('pending','approved','rejected')),
  decided_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.job_requisition_approvals is 'قرارات اعتماد طلبات فتح الوظائف على مراحلها.';

create index if not exists idx_req_approvals_requisition on public.job_requisition_approvals(requisition_id);
create index if not exists idx_req_approvals_approver    on public.job_requisition_approvals(approver_id);

alter table public.job_requisition_approvals enable row level security;

drop trigger if exists trg_req_approvals_updated_at on public.job_requisition_approvals;
create trigger trg_req_approvals_updated_at
  before update on public.job_requisition_approvals
  for each row execute function public.tg_set_updated_at();

create policy req_approvals_select on public.job_requisition_approvals
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.requisition.read','recruitment.requisition.manage'])
  );

create policy req_approvals_insert on public.job_requisition_approvals
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

create policy req_approvals_update on public.job_requisition_approvals
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

create policy req_approvals_delete on public.job_requisition_approvals
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.requisition.manage')
  );

-- =====================================================================
-- 3. job_postings
-- =====================================================================
create table if not exists public.job_postings (
  id             uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references public.job_requisitions(id) on delete restrict,
  public_slug    text not null unique,
  visibility     text not null default 'internal'
                   check (visibility in ('internal','external')),
  published_at   timestamptz,
  closes_at      timestamptz,
  status         text not null default 'draft'
                   check (status in ('draft','published','closed')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.job_postings is 'الإعلانات الوظيفية المنشورة (Job postings) المرتبطة بطلبات التوظيف.';

create index if not exists idx_job_postings_requisition on public.job_postings(requisition_id);
create index if not exists idx_job_postings_status      on public.job_postings(status);

alter table public.job_postings enable row level security;

drop trigger if exists trg_job_postings_updated_at on public.job_postings;
create trigger trg_job_postings_updated_at
  before update on public.job_postings
  for each row execute function public.tg_set_updated_at();

create policy job_postings_select on public.job_postings
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.posting.read','recruitment.posting.manage'])
  );

create policy job_postings_insert on public.job_postings
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.posting.manage')
  );

create policy job_postings_update on public.job_postings
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.posting.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.posting.manage')
  );

create policy job_postings_delete on public.job_postings
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.posting.manage')
  );

-- =====================================================================
-- 4. candidates
-- =====================================================================
create extension if not exists citext;

create table if not exists public.candidates (
  id                  uuid primary key default gen_random_uuid(),
  full_name           text not null,
  email_norm          citext,
  phone_norm          text,
  source              text,
  tags                text[] not null default '{}',
  consent_at          timestamptz,
  consent_expires_at  timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  created_by          uuid references auth.users(id) on delete set null
);

comment on table public.candidates is 'المرشحون (Candidates) مع بيانات التواصل والموافقة على حفظ البيانات.';

create unique index if not exists uq_candidates_email_norm on public.candidates(email_norm) where email_norm is not null;
create index if not exists idx_candidates_phone_norm on public.candidates(phone_norm);

alter table public.candidates enable row level security;

drop trigger if exists trg_candidates_updated_at on public.candidates;
create trigger trg_candidates_updated_at
  before update on public.candidates
  for each row execute function public.tg_set_updated_at();

create policy candidates_select on public.candidates
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.candidate.read','recruitment.candidate.manage'])
  );

create policy candidates_insert on public.candidates
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

create policy candidates_update on public.candidates
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

create policy candidates_delete on public.candidates
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

-- =====================================================================
-- 5. candidate_documents
-- =====================================================================
create table if not exists public.candidate_documents (
  id           uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  storage_path text not null,
  doc_type     text,
  uploaded_at  timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id) on delete set null
);

comment on table public.candidate_documents is 'مستندات المرشحين (السيرة الذاتية، الشهادات) في التخزين.';

create index if not exists idx_candidate_documents_candidate on public.candidate_documents(candidate_id);

alter table public.candidate_documents enable row level security;

drop trigger if exists trg_candidate_documents_updated_at on public.candidate_documents;
create trigger trg_candidate_documents_updated_at
  before update on public.candidate_documents
  for each row execute function public.tg_set_updated_at();

create policy candidate_documents_select on public.candidate_documents
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.candidate.read','recruitment.candidate.manage'])
  );

create policy candidate_documents_insert on public.candidate_documents
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

create policy candidate_documents_update on public.candidate_documents
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

create policy candidate_documents_delete on public.candidate_documents
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.candidate.manage')
  );

-- =====================================================================
-- 6. applications
-- =====================================================================
create table if not exists public.applications (
  id             uuid primary key default gen_random_uuid(),
  candidate_id   uuid not null references public.candidates(id) on delete cascade,
  posting_id     uuid not null references public.job_postings(id) on delete cascade,
  applied_at     timestamptz not null default now(),
  source_channel text,
  status         text not null default 'active'
                   check (status in ('active','hired','rejected','withdrawn')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null,
  unique (candidate_id, posting_id)
);

comment on table public.applications is 'طلبات التقديم على الإعلانات الوظيفية (Applications).';

create index if not exists idx_applications_candidate on public.applications(candidate_id);
create index if not exists idx_applications_posting   on public.applications(posting_id);
create index if not exists idx_applications_status    on public.applications(status);

alter table public.applications enable row level security;

drop trigger if exists trg_applications_updated_at on public.applications;
create trigger trg_applications_updated_at
  before update on public.applications
  for each row execute function public.tg_set_updated_at();

create policy applications_select on public.applications
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.read','recruitment.application.manage','recruitment.pipeline.manage'])
  );

create policy applications_insert on public.applications
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.application.manage')
  );

create policy applications_update on public.applications
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.manage','recruitment.pipeline.manage'])
  )
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.manage','recruitment.pipeline.manage'])
  );

create policy applications_delete on public.applications
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.application.manage')
  );

-- =====================================================================
-- 7. pipeline_stages
-- =====================================================================
create table if not exists public.pipeline_stages (
  id           uuid primary key default gen_random_uuid(),
  posting_id   uuid not null references public.job_postings(id) on delete cascade,
  name         text not null,
  order_index  integer not null default 0,
  is_mandatory boolean not null default false,
  sla_days     integer check (sla_days is null or sla_days >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id) on delete set null,
  unique (posting_id, order_index)
);

comment on table public.pipeline_stages is 'مراحل مسار التوظيف لكل إعلان وظيفي (Pipeline stages).';

create index if not exists idx_pipeline_stages_posting on public.pipeline_stages(posting_id);

alter table public.pipeline_stages enable row level security;

drop trigger if exists trg_pipeline_stages_updated_at on public.pipeline_stages;
create trigger trg_pipeline_stages_updated_at
  before update on public.pipeline_stages
  for each row execute function public.tg_set_updated_at();

create policy pipeline_stages_select on public.pipeline_stages
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.read','recruitment.pipeline.manage'])
  );

create policy pipeline_stages_insert on public.pipeline_stages
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy pipeline_stages_update on public.pipeline_stages
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy pipeline_stages_delete on public.pipeline_stages
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

-- =====================================================================
-- 8. application_stage_history
-- =====================================================================
create table if not exists public.application_stage_history (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  from_stage     uuid references public.pipeline_stages(id) on delete set null,
  to_stage       uuid references public.pipeline_stages(id) on delete set null,
  moved_by       uuid references public.employees(id) on delete set null,
  reason         text,
  moved_at       timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.application_stage_history is 'سجل انتقالات الطلب بين مراحل المسار (audit trail).';

create index if not exists idx_stage_history_application on public.application_stage_history(application_id);

alter table public.application_stage_history enable row level security;

drop trigger if exists trg_stage_history_updated_at on public.application_stage_history;
create trigger trg_stage_history_updated_at
  before update on public.application_stage_history
  for each row execute function public.tg_set_updated_at();

create policy stage_history_select on public.application_stage_history
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.read','recruitment.pipeline.manage'])
  );

create policy stage_history_insert on public.application_stage_history
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy stage_history_update on public.application_stage_history
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy stage_history_delete on public.application_stage_history
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

-- =====================================================================
-- 9. application_current_state
-- =====================================================================
create table if not exists public.application_current_state (
  id               uuid primary key default gen_random_uuid(),
  application_id   uuid not null unique references public.applications(id) on delete cascade,
  current_stage_id uuid references public.pipeline_stages(id) on delete set null,
  entered_stage_at timestamptz not null default now(),
  assignee_id      uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id) on delete set null
);

comment on table public.application_current_state is 'الحالة الحالية للطلب: المرحلة الراهنة والمسؤول عنها.';

create index if not exists idx_current_state_stage    on public.application_current_state(current_stage_id);
create index if not exists idx_current_state_assignee on public.application_current_state(assignee_id);

alter table public.application_current_state enable row level security;

drop trigger if exists trg_current_state_updated_at on public.application_current_state;
create trigger trg_current_state_updated_at
  before update on public.application_current_state
  for each row execute function public.tg_set_updated_at();

create policy current_state_select on public.application_current_state
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.application.read','recruitment.pipeline.manage'])
  );

create policy current_state_insert on public.application_current_state
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy current_state_update on public.application_current_state
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

create policy current_state_delete on public.application_current_state
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.pipeline.manage')
  );

-- =====================================================================
-- 10. interviews
-- =====================================================================
create table if not exists public.interviews (
  id               uuid primary key default gen_random_uuid(),
  application_id   uuid not null references public.applications(id) on delete cascade,
  mode             text not null default 'onsite'
                     check (mode in ('onsite','remote')),
  scheduled_at     timestamptz,
  location_or_link text,
  status           text not null default 'scheduled'
                     check (status in ('scheduled','completed','cancelled','no_show')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id) on delete set null
);

comment on table public.interviews is 'المقابلات المجدولة لكل طلب تقديم (Interviews).';

create index if not exists idx_interviews_application on public.interviews(application_id);
create index if not exists idx_interviews_status      on public.interviews(status);

alter table public.interviews enable row level security;

drop trigger if exists trg_interviews_updated_at on public.interviews;
create trigger trg_interviews_updated_at
  before update on public.interviews
  for each row execute function public.tg_set_updated_at();

create policy interviews_select on public.interviews
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.interview.read','recruitment.interview.manage'])
  );

create policy interviews_insert on public.interviews
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

create policy interviews_update on public.interviews
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

create policy interviews_delete on public.interviews
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

-- =====================================================================
-- 11. interview_panel
-- =====================================================================
create table if not exists public.interview_panel (
  id           uuid primary key default gen_random_uuid(),
  interview_id uuid not null references public.interviews(id) on delete cascade,
  panelist_id  uuid not null references public.employees(id) on delete cascade,
  invited_at   timestamptz not null default now(),
  responded    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id) on delete set null,
  unique (interview_id, panelist_id)
);

comment on table public.interview_panel is 'لجنة المقابلة: المُقيّمون المدعوون لكل مقابلة.';

create index if not exists idx_interview_panel_interview on public.interview_panel(interview_id);
create index if not exists idx_interview_panel_panelist  on public.interview_panel(panelist_id);

alter table public.interview_panel enable row level security;

drop trigger if exists trg_interview_panel_updated_at on public.interview_panel;
create trigger trg_interview_panel_updated_at
  before update on public.interview_panel
  for each row execute function public.tg_set_updated_at();

create policy interview_panel_select on public.interview_panel
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.interview.read','recruitment.interview.manage'])
    or panelist_id = public.current_employee_id()
  );

create policy interview_panel_insert on public.interview_panel
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

create policy interview_panel_update on public.interview_panel
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or panelist_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or panelist_id = public.current_employee_id()
  );

create policy interview_panel_delete on public.interview_panel
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

-- =====================================================================
-- 12. interview_scorecards
-- =====================================================================
create table if not exists public.interview_scorecards (
  id             uuid primary key default gen_random_uuid(),
  interview_id   uuid not null references public.interviews(id) on delete cascade,
  panelist_id    uuid not null references public.employees(id) on delete cascade,
  submitted_at   timestamptz,
  recommendation text
                   check (recommendation in ('hire','reject','hold')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null,
  unique (interview_id, panelist_id)
);

comment on table public.interview_scorecards is 'بطاقات تقييم المقابلة وتوصية كل مُقيّم.';

create index if not exists idx_scorecards_interview on public.interview_scorecards(interview_id);
create index if not exists idx_scorecards_panelist  on public.interview_scorecards(panelist_id);

alter table public.interview_scorecards enable row level security;

drop trigger if exists trg_scorecards_updated_at on public.interview_scorecards;
create trigger trg_scorecards_updated_at
  before update on public.interview_scorecards
  for each row execute function public.tg_set_updated_at();

create policy scorecards_select on public.interview_scorecards
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.interview.read','recruitment.interview.manage'])
    or panelist_id = public.current_employee_id()
  );

create policy scorecards_insert on public.interview_scorecards
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or panelist_id = public.current_employee_id()
  );

create policy scorecards_update on public.interview_scorecards
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or panelist_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or panelist_id = public.current_employee_id()
  );

create policy scorecards_delete on public.interview_scorecards
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

-- =====================================================================
-- 13. scorecard_criteria_scores
-- =====================================================================
create table if not exists public.scorecard_criteria_scores (
  id           uuid primary key default gen_random_uuid(),
  scorecard_id uuid not null references public.interview_scorecards(id) on delete cascade,
  criterion    text not null,
  weight       numeric(6,2) not null default 1 check (weight >= 0),
  score        numeric(6,2) check (score is null or score >= 0),
  comment      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id) on delete set null
);

comment on table public.scorecard_criteria_scores is 'درجات معايير بطاقة التقييم (لكل معيار وزن ودرجة).';

create index if not exists idx_criteria_scores_scorecard on public.scorecard_criteria_scores(scorecard_id);

alter table public.scorecard_criteria_scores enable row level security;

drop trigger if exists trg_criteria_scores_updated_at on public.scorecard_criteria_scores;
create trigger trg_criteria_scores_updated_at
  before update on public.scorecard_criteria_scores
  for each row execute function public.tg_set_updated_at();

create policy criteria_scores_select on public.scorecard_criteria_scores
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.interview.read','recruitment.interview.manage'])
    or exists (
      select 1 from public.interview_scorecards s
      where s.id = scorecard_criteria_scores.scorecard_id
        and s.panelist_id = public.current_employee_id()
    )
  );

create policy criteria_scores_insert on public.scorecard_criteria_scores
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or exists (
      select 1 from public.interview_scorecards s
      where s.id = scorecard_criteria_scores.scorecard_id
        and s.panelist_id = public.current_employee_id()
    )
  );

create policy criteria_scores_update on public.scorecard_criteria_scores
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or exists (
      select 1 from public.interview_scorecards s
      where s.id = scorecard_criteria_scores.scorecard_id
        and s.panelist_id = public.current_employee_id()
    )
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
    or exists (
      select 1 from public.interview_scorecards s
      where s.id = scorecard_criteria_scores.scorecard_id
        and s.panelist_id = public.current_employee_id()
    )
  );

create policy criteria_scores_delete on public.scorecard_criteria_scores
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.interview.manage')
  );

-- =====================================================================
-- 14. job_offers
-- =====================================================================
create table if not exists public.job_offers (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  salary         numeric(14,2) check (salary is null or salary >= 0),
  title          text,
  contract_type  text,
  start_date     date,
  expires_at     timestamptz,
  status         text not null default 'draft'
                   check (status in ('draft','pending','approved','sent','accepted','declined','expired','withdrawn')),
  version        integer not null default 1 check (version > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.job_offers is 'عروض التوظيف (Job offers) وحالتها ونسخها.';

create index if not exists idx_job_offers_application on public.job_offers(application_id);
create index if not exists idx_job_offers_status      on public.job_offers(status);

alter table public.job_offers enable row level security;

drop trigger if exists trg_job_offers_updated_at on public.job_offers;
create trigger trg_job_offers_updated_at
  before update on public.job_offers
  for each row execute function public.tg_set_updated_at();

create policy job_offers_select on public.job_offers
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.offer.read','recruitment.offer.manage'])
  );

create policy job_offers_insert on public.job_offers
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

create policy job_offers_update on public.job_offers
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

create policy job_offers_delete on public.job_offers
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

-- =====================================================================
-- 15. offer_approvals
-- =====================================================================
create table if not exists public.offer_approvals (
  id          uuid primary key default gen_random_uuid(),
  offer_id    uuid not null references public.job_offers(id) on delete cascade,
  approver_id uuid references public.employees(id) on delete set null,
  decision    text not null default 'pending'
                check (decision in ('pending','approved','rejected')),
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  created_by  uuid references auth.users(id) on delete set null
);

comment on table public.offer_approvals is 'قرارات اعتماد عروض التوظيف.';

create index if not exists idx_offer_approvals_offer    on public.offer_approvals(offer_id);
create index if not exists idx_offer_approvals_approver on public.offer_approvals(approver_id);

alter table public.offer_approvals enable row level security;

drop trigger if exists trg_offer_approvals_updated_at on public.offer_approvals;
create trigger trg_offer_approvals_updated_at
  before update on public.offer_approvals
  for each row execute function public.tg_set_updated_at();

create policy offer_approvals_select on public.offer_approvals
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.offer.read','recruitment.offer.manage'])
  );

create policy offer_approvals_insert on public.offer_approvals
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

create policy offer_approvals_update on public.offer_approvals
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

create policy offer_approvals_delete on public.offer_approvals
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.offer.manage')
  );

-- =====================================================================
-- 16. employment_contracts
-- =====================================================================
create table if not exists public.employment_contracts (
  id              uuid primary key default gen_random_uuid(),
  offer_id        uuid references public.job_offers(id) on delete set null,
  employee_id     uuid references public.employees(id) on delete set null,
  template_id     uuid,
  status          text not null default 'draft'
                    check (status in ('draft','pending_signature','active','terminated','expired')),
  signed_pdf_path text,
  effective_from  date,
  effective_to    date,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz,
  created_by      uuid references auth.users(id) on delete set null
);

comment on table public.employment_contracts is 'عقود العمل الناتجة عن العروض المقبولة (Employment contracts).';

create index if not exists idx_contracts_offer    on public.employment_contracts(offer_id);
create index if not exists idx_contracts_employee on public.employment_contracts(employee_id);
create index if not exists idx_contracts_status   on public.employment_contracts(status);

alter table public.employment_contracts enable row level security;

drop trigger if exists trg_contracts_updated_at on public.employment_contracts;
create trigger trg_contracts_updated_at
  before update on public.employment_contracts
  for each row execute function public.tg_set_updated_at();

create policy contracts_select on public.employment_contracts
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.contract.read','recruitment.contract.manage'])
    or (employee_id is not null and public.can_access_employee(employee_id))
  );

create policy contracts_insert on public.employment_contracts
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

create policy contracts_update on public.employment_contracts
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

create policy contracts_delete on public.employment_contracts
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

-- =====================================================================
-- 17. contract_signatures
-- =====================================================================
create table if not exists public.contract_signatures (
  id          uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.employment_contracts(id) on delete cascade,
  signer_id   uuid references public.employees(id) on delete set null,
  signer_role text,
  method      text,
  signed_at   timestamptz,
  ip          inet,
  proof_ref   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  created_by  uuid references auth.users(id) on delete set null
);

comment on table public.contract_signatures is 'توقيعات عقود العمل مع دليل التوقيع (audit).';

create index if not exists idx_signatures_contract on public.contract_signatures(contract_id);
create index if not exists idx_signatures_signer   on public.contract_signatures(signer_id);

alter table public.contract_signatures enable row level security;

drop trigger if exists trg_signatures_updated_at on public.contract_signatures;
create trigger trg_signatures_updated_at
  before update on public.contract_signatures
  for each row execute function public.tg_set_updated_at();

create policy signatures_select on public.contract_signatures
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['recruitment.contract.read','recruitment.contract.manage'])
    or signer_id = public.current_employee_id()
  );

create policy signatures_insert on public.contract_signatures
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

create policy signatures_update on public.contract_signatures
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

create policy signatures_delete on public.contract_signatures
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('recruitment.contract.manage')
  );

-- =====================================================================
-- 18. onboarding_journeys
-- =====================================================================
create table if not exists public.onboarding_journeys (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  template_id    uuid,
  started_at     timestamptz,
  probation_end  date,
  status         text not null default 'not_started'
                   check (status in ('not_started','in_progress','completed','cancelled')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.onboarding_journeys is 'رحلات إلحاق الموظفين الجدد (Onboarding journeys).';

create index if not exists idx_journeys_employee on public.onboarding_journeys(employee_id);
create index if not exists idx_journeys_status   on public.onboarding_journeys(status);

alter table public.onboarding_journeys enable row level security;

drop trigger if exists trg_journeys_updated_at on public.onboarding_journeys;
create trigger trg_journeys_updated_at
  before update on public.onboarding_journeys
  for each row execute function public.tg_set_updated_at();

create policy journeys_select on public.onboarding_journeys
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['onboarding.journey.read','onboarding.journey.manage'])
    or public.can_access_employee(employee_id)
  );

create policy journeys_insert on public.onboarding_journeys
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  );

create policy journeys_update on public.onboarding_journeys
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  );

create policy journeys_delete on public.onboarding_journeys
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  );

-- =====================================================================
-- 19. onboarding_tasks
-- =====================================================================
create table if not exists public.onboarding_tasks (
  id               uuid primary key default gen_random_uuid(),
  journey_id       uuid not null references public.onboarding_journeys(id) on delete cascade,
  title            text not null,
  owner_role       text,
  assignee_id      uuid references public.employees(id) on delete set null,
  due_offset_days  integer,
  status           text not null default 'pending'
                     check (status in ('pending','in_progress','completed','skipped')),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id) on delete set null
);

comment on table public.onboarding_tasks is 'مهام الإلحاق ضمن رحلة الموظف الجديد.';

create index if not exists idx_onboarding_tasks_journey  on public.onboarding_tasks(journey_id);
create index if not exists idx_onboarding_tasks_assignee on public.onboarding_tasks(assignee_id);

alter table public.onboarding_tasks enable row level security;

drop trigger if exists trg_onboarding_tasks_updated_at on public.onboarding_tasks;
create trigger trg_onboarding_tasks_updated_at
  before update on public.onboarding_tasks
  for each row execute function public.tg_set_updated_at();

create policy onboarding_tasks_select on public.onboarding_tasks
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['onboarding.journey.read','onboarding.journey.manage'])
    or assignee_id = public.current_employee_id()
  );

create policy onboarding_tasks_insert on public.onboarding_tasks
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  );

create policy onboarding_tasks_update on public.onboarding_tasks
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
    or assignee_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
    or assignee_id = public.current_employee_id()
  );

create policy onboarding_tasks_delete on public.onboarding_tasks
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.journey.manage')
  );

-- =====================================================================
-- 20. provisioning_requests
-- =====================================================================
create table if not exists public.provisioning_requests (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references public.employees(id) on delete cascade,
  journey_id     uuid references public.onboarding_journeys(id) on delete set null,
  account_status text not null default 'requested'
                   check (account_status in ('requested','provisioned','revoked','failed')),
  role_granted   text,
  created_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  updated_at     timestamptz,
  created_by     uuid references auth.users(id) on delete set null
);

comment on table public.provisioning_requests is 'طلبات تجهيز الحسابات والصلاحيات للموظفين الجدد.';

create index if not exists idx_provisioning_employee on public.provisioning_requests(employee_id);
create index if not exists idx_provisioning_journey  on public.provisioning_requests(journey_id);

alter table public.provisioning_requests enable row level security;

drop trigger if exists trg_provisioning_updated_at on public.provisioning_requests;
create trigger trg_provisioning_updated_at
  before update on public.provisioning_requests
  for each row execute function public.tg_set_updated_at();

create policy provisioning_select on public.provisioning_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['onboarding.provisioning.read','onboarding.provisioning.manage'])
    or public.can_access_employee(employee_id)
  );

create policy provisioning_insert on public.provisioning_requests
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.provisioning.manage')
  );

create policy provisioning_update on public.provisioning_requests
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.provisioning.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('onboarding.provisioning.manage')
  );

create policy provisioning_delete on public.provisioning_requests
  for delete to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('onboarding.provisioning.manage')
  );

-- =====================================================================
-- RPC: advance_application_stage
--   Moves an application to a new pipeline stage, recording history and
--   updating the current-state row. Requires recruitment.pipeline.manage.
-- =====================================================================
create or replace function public.advance_application_stage(
  p_application_id uuid,
  p_to_stage_id    uuid,
  p_reason         text
)
returns public.application_current_state
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_from_stage uuid;
  v_emp        uuid;
  v_state      public.application_current_state;
begin
  -- Permission gate (full-access bypasses via helper).
  if not (public.current_is_full_access() or public.has_permission('recruitment.pipeline.manage')) then
    raise exception 'insufficient privilege: recruitment.pipeline.manage required'
      using errcode = '42501';
  end if;

  -- Validate the application exists.
  if not exists (select 1 from public.applications a where a.id = p_application_id) then
    raise exception 'application % not found', p_application_id using errcode = 'P0002';
  end if;

  -- Validate the target stage exists and belongs to the same posting.
  if not exists (
    select 1
    from public.pipeline_stages ps
    join public.applications a on a.posting_id = ps.posting_id
    where ps.id = p_to_stage_id
      and a.id = p_application_id
  ) then
    raise exception 'target stage % does not belong to the application''s posting', p_to_stage_id
      using errcode = '22023';
  end if;

  v_emp := public.current_employee_id();

  -- Determine the current stage (if any).
  select current_stage_id
    into v_from_stage
  from public.application_current_state
  where application_id = p_application_id;

  -- Record the transition in history.
  insert into public.application_stage_history (
    application_id, from_stage, to_stage, moved_by, reason, moved_at, created_by
  ) values (
    p_application_id, v_from_stage, p_to_stage_id, v_emp, p_reason, now(), auth.uid()
  );

  -- Upsert the current-state row.
  insert into public.application_current_state (
    application_id, current_stage_id, entered_stage_at, created_by
  ) values (
    p_application_id, p_to_stage_id, now(), auth.uid()
  )
  on conflict (application_id) do update
    set current_stage_id = excluded.current_stage_id,
        entered_stage_at = now(),
        updated_at       = now()
  returning * into v_state;

  return v_state;
end;
$$;

comment on function public.advance_application_stage(uuid, uuid, text) is
  'ينقل طلب التقديم إلى مرحلة جديدة، يسجّل الانتقال في السجل ويحدّث الحالة الحالية. يتطلب صلاحية recruitment.pipeline.manage.';

revoke all on function public.advance_application_stage(uuid, uuid, text) from public;
grant execute on function public.advance_application_stage(uuid, uuid, text) to authenticated;
