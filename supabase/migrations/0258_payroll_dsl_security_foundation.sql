-- 0258: Secure payroll formula-template foundation.
--
-- This migration stores declarative JSON only. It deliberately does not
-- evaluate expressions or execute user-supplied SQL. A future interpreter
-- must consume the allow-listed node types exposed by migration 0255.

begin;

-- Migration 0255 revoked the named authenticated role, but PostgreSQL grants
-- EXECUTE on new functions to PUBLIC by default. Close that inherited path in
-- this later migration without rewriting the already-published 0255 file.
revoke execute on function public.payroll_dsl_get_allowed_types()
  from public, anon, authenticated;
grant execute on function public.payroll_dsl_get_allowed_types()
  to service_role;

create table if not exists public.payroll_formula_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^[a-z][a-z0-9_]{2,63}$'),
  name_ar text not null check (length(btrim(name_ar)) between 2 and 160),
  jurisdiction text not null default 'EG' check (jurisdiction ~ '^[A-Z]{2,8}$'),
  version integer not null default 1 check (version > 0),
  spec jsonb not null check (jsonb_typeof(spec) = 'object'),
  template_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(template_config) = 'object'),
  effective_from date not null,
  effective_to date,
  is_active boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_formula_templates_dates_ck
    check (effective_to is null or effective_to >= effective_from),
  constraint payroll_formula_templates_code_version_uq
    unique (code, jurisdiction, version)
);

create table if not exists public.payroll_formula_approvals (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.payroll_formula_templates(id) on delete cascade,
  review_scope text not null check (review_scope in ('finance', 'legal')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'deferred')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_formula_approvals_scope_uq unique (template_id, review_scope),
  constraint payroll_formula_approvals_review_ck check (
    (status = 'pending' and reviewed_at is null)
    or (status <> 'pending' and reviewed_at is not null)
  )
);

comment on table public.payroll_formula_templates is
  'Versioned declarative payroll formula templates. JSON only; no eval or dynamic SQL.';
comment on column public.payroll_formula_templates.spec is
  'Declarative JSON DSL. Node types must be validated against payroll_dsl_get_allowed_types().';
comment on table public.payroll_formula_approvals is
  'Independent finance and legal review decisions for each payroll formula template.';

create index if not exists ix_payroll_formula_templates_active
  on public.payroll_formula_templates (code, jurisdiction, effective_from)
  where is_active;
create index if not exists ix_payroll_formula_approvals_template
  on public.payroll_formula_approvals (template_id, review_scope, status);

drop trigger if exists trg_payroll_formula_templates_updated_at
  on public.payroll_formula_templates;
create trigger trg_payroll_formula_templates_updated_at
  before update on public.payroll_formula_templates
  for each row execute function public.tg_set_updated_at();

drop trigger if exists trg_payroll_formula_approvals_updated_at
  on public.payroll_formula_approvals;
create trigger trg_payroll_formula_approvals_updated_at
  before update on public.payroll_formula_approvals
  for each row execute function public.tg_set_updated_at();

alter table public.payroll_formula_templates enable row level security;
alter table public.payroll_formula_templates force row level security;
alter table public.payroll_formula_approvals enable row level security;
alter table public.payroll_formula_approvals force row level security;

drop policy if exists payroll_formula_templates_read on public.payroll_formula_templates;
create policy payroll_formula_templates_read
  on public.payroll_formula_templates for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.structure.manage', 'payroll.run.approve'])
  );

drop policy if exists payroll_formula_templates_manage on public.payroll_formula_templates;
create policy payroll_formula_templates_manage
  on public.payroll_formula_templates for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('payroll.structure.manage')
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('payroll.structure.manage')
  );

drop policy if exists payroll_formula_approvals_read on public.payroll_formula_approvals;
create policy payroll_formula_approvals_read
  on public.payroll_formula_approvals for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.structure.manage', 'payroll.run.approve'])
  );

drop policy if exists payroll_formula_approvals_manage on public.payroll_formula_approvals;
create policy payroll_formula_approvals_manage
  on public.payroll_formula_approvals for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.structure.manage', 'payroll.run.approve'])
  )
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.structure.manage', 'payroll.run.approve'])
  );

revoke all on table public.payroll_formula_templates from public, anon;
revoke all on table public.payroll_formula_approvals from public, anon;
grant select, insert, update, delete on table public.payroll_formula_templates to authenticated;
grant select, insert, update, delete on table public.payroll_formula_approvals to authenticated;
grant all on table public.payroll_formula_templates to service_role;
grant all on table public.payroll_formula_approvals to service_role;

commit;
