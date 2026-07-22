-- Migration 0039: privacy-preserving identifier login attempt ledger.
-- Raw identifiers and IP addresses are never stored. The Edge Function records peppered hashes only.
begin;

create table if not exists public.login_auth_attempts (
  id                uuid primary key default gen_random_uuid(),
  identifier_hash   text not null check (length(identifier_hash) = 64),
  ip_hash           text not null check (length(ip_hash) = 64),
  identifier_kind   text not null check (identifier_kind in ('email','phone','employee_code')),
  success           boolean not null default false,
  failure_code      text,
  user_agent_hash   text,
  attempted_at      timestamptz not null default now()
);
comment on table public.login_auth_attempts is
  'Rate-limit and security ledger for pre-auth identifier login. Stores only peppered hashes, never raw identifiers or IP addresses.';

create index if not exists ix_login_auth_attempts_ip_window
  on public.login_auth_attempts (ip_hash, attempted_at desc);
create index if not exists ix_login_auth_attempts_identifier_window
  on public.login_auth_attempts (identifier_hash, attempted_at desc);
create index if not exists ix_login_auth_attempts_retention
  on public.login_auth_attempts (attempted_at);

alter table public.login_auth_attempts enable row level security;
-- Deliberately no authenticated/anon policies. Only service-role Edge Functions access this table.

revoke all on public.login_auth_attempts from anon, authenticated;

commit;
