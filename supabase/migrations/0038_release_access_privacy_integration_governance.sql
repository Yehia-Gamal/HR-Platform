-- Migration 0038: release, device, access-review, break-glass, privacy and integration governance.
-- This migration is additive and keeps a single source of truth for post-release operations.
begin;

-- ---------------------------------------------------------------------
-- Permissions used by the governance workbench.
-- ---------------------------------------------------------------------
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values
  ('system.release.read', 'system', 'release', 'read', 'عرض سياسات الإصدارات والأجهزة', 'sensitive', true),
  ('system.release.manage', 'system', 'release', 'manage', 'إدارة التحديث الإجباري والصيانة والأجهزة', 'critical', true),
  ('access.review.read', 'access', 'review', 'read', 'عرض حملات مراجعة الصلاحيات', 'sensitive', true),
  ('access.review.manage', 'access', 'review', 'manage', 'إنشاء واعتماد مراجعات الصلاحيات', 'critical', true),
  ('access.break_glass.request', 'access', 'break_glass', 'request', 'طلب صلاحية طوارئ مؤقتة', 'critical', true),
  ('access.break_glass.approve', 'access', 'break_glass', 'approve', 'اعتماد صلاحية طوارئ مؤقتة', 'critical', true),
  ('privacy.request.manage', 'privacy', 'request', 'manage', 'إدارة طلبات الخصوصية', 'sensitive', true),
  ('system.integration.outbox.read', 'system', 'integration_outbox', 'read', 'عرض طابور التكاملات', 'sensitive', true),
  ('system.integration.outbox.manage', 'system', 'integration_outbox', 'manage', 'إدارة وإعادة طابور التكاملات', 'critical', true)
on conflict (code) do update set
  description = excluded.description,
  risk_level = excluded.risk_level,
  is_sensitive = excluded.is_sensitive,
  updated_at = now();

-- ---------------------------------------------------------------------
-- Release policies: one policy per platform/environment.
-- ---------------------------------------------------------------------
create table if not exists public.app_release_policies (
  id                    uuid primary key default gen_random_uuid(),
  platform              text not null check (platform in ('android','ios','web')),
  environment           text not null default 'production' check (environment in ('development','staging','production')),
  latest_version        text not null default '0.0.0',
  latest_build          integer not null default 0 check (latest_build >= 0),
  min_supported_version text not null default '0.0.0',
  min_supported_build   integer not null default 0 check (min_supported_build >= 0),
  force_update          boolean not null default false,
  maintenance_enabled   boolean not null default false,
  maintenance_message_ar text,
  maintenance_message_en text,
  update_message_ar     text,
  store_url             text,
  rollout_percent       integer not null default 100 check (rollout_percent between 0 and 100),
  effective_from        timestamptz not null default now(),
  effective_to          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  updated_by            uuid references auth.users(id),
  unique (platform, environment),
  check (effective_to is null or effective_to > effective_from),
  check (latest_build >= min_supported_build)
);
comment on table public.app_release_policies is 'سياسة الإصدار والصيانة والتحديث الإجباري لكل منصة وبيئة.';
create index if not exists ix_app_release_policies_active on public.app_release_policies(platform, environment, effective_from, effective_to);
drop trigger if exists trg_app_release_policies_updated_at on public.app_release_policies;
create trigger trg_app_release_policies_updated_at before update on public.app_release_policies
for each row execute function public.set_updated_at();
alter table public.app_release_policies enable row level security;
drop policy if exists app_release_policies_admin_read on public.app_release_policies;
create policy app_release_policies_admin_read on public.app_release_policies for select to authenticated
using (public.current_is_full_access() or public.has_any_permission(array['system.release.read','system.release.manage']));
-- No direct write policy. Updates go through an audited RPC.

insert into public.app_release_policies (
  platform, environment, latest_version, latest_build, min_supported_version, min_supported_build,
  update_message_ar, maintenance_message_ar, created_by, updated_by
)
values
  ('android','development','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من التطبيق.','التطبيق تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('android','staging','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من التطبيق.','بيئة الاختبار تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('android','production','0.9.0',9,'0.8.0',8,'يتوفر إصدار أحدث من التطبيق.','التطبيق تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('ios','development','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من التطبيق.','التطبيق تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('ios','staging','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من التطبيق.','بيئة الاختبار تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('ios','production','0.9.0',9,'0.8.0',8,'يتوفر إصدار أحدث من التطبيق.','التطبيق تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('web','development','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من الويب.','لوحة الويب تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('web','staging','0.9.0',9,'0.9.0',9,'يتوفر إصدار أحدث من الويب.','بيئة الاختبار تحت الصيانة مؤقتًا.',auth.uid(),auth.uid()),
  ('web','production','0.9.0',9,'0.8.0',8,'يتوفر إصدار أحدث من الويب.','لوحة الويب تحت الصيانة مؤقتًا.',auth.uid(),auth.uid())
on conflict (platform, environment) do nothing;

-- ---------------------------------------------------------------------
-- Managed installations and sessions.
-- ---------------------------------------------------------------------
create table if not exists public.managed_devices (
  id                 uuid primary key default gen_random_uuid(),
  installation_id    text not null unique,
  user_id             uuid references auth.users(id) on delete cascade,
  employee_id         uuid references public.employees(id) on delete set null,
  platform            text not null check (platform in ('android','ios','web')),
  device_name         text,
  device_model        text,
  os_version          text,
  app_version         text not null,
  app_build           integer not null default 0,
  environment         text not null default 'production' check (environment in ('development','staging','production')),
  push_enabled        boolean not null default false,
  biometric_available boolean not null default false,
  trusted             boolean not null default false,
  status              text not null default 'active' check (status in ('active','revoked','blocked','retired')),
  last_ip_hash        text,
  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  revoked_at          timestamptz,
  revoked_by          uuid references auth.users(id),
  revoke_reason       text,
  metadata            jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz
);
comment on table public.managed_devices is 'سجل تثبيتات التطبيق والأجهزة والجلسات القابلة للإبطال عن بعد.';
create index if not exists ix_managed_devices_user on public.managed_devices(user_id, status);
create index if not exists ix_managed_devices_employee on public.managed_devices(employee_id, status);
create index if not exists ix_managed_devices_last_seen on public.managed_devices(last_seen_at desc);
drop trigger if exists trg_managed_devices_updated_at on public.managed_devices;
create trigger trg_managed_devices_updated_at before update on public.managed_devices
for each row execute function public.set_updated_at();
alter table public.managed_devices enable row level security;
drop policy if exists managed_devices_read on public.managed_devices;
create policy managed_devices_read on public.managed_devices for select to authenticated
using (user_id = auth.uid() or public.current_is_full_access() or public.has_any_permission(array['system.release.read','system.release.manage','access.account.manage_devices']));
-- No direct write policy. Registration and revocation use RPCs.

-- ---------------------------------------------------------------------
-- Access review campaigns and decisions.
-- ---------------------------------------------------------------------
create table if not exists public.access_review_campaigns (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  description     text,
  scope           jsonb not null default '{}'::jsonb,
  status          text not null default 'draft' check (status in ('draft','active','completed','cancelled')),
  starts_at       timestamptz,
  due_at          timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz,
  created_by      uuid references auth.users(id)
);
create table if not exists public.access_review_items (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references public.access_review_campaigns(id) on delete cascade,
  user_role_id    uuid not null references public.user_roles(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  role_id         uuid not null references public.roles(id) on delete cascade,
  reviewer_user_id uuid references auth.users(id),
  decision        text not null default 'pending' check (decision in ('pending','keep','revoke','change_scope','expired')),
  decision_reason text,
  decided_at      timestamptz,
  snapshot        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz,
  unique (campaign_id, user_role_id)
);
create index if not exists ix_access_review_items_campaign on public.access_review_items(campaign_id, decision);
create index if not exists ix_access_review_items_reviewer on public.access_review_items(reviewer_user_id, decision);
drop trigger if exists trg_access_review_campaigns_updated_at on public.access_review_campaigns;
create trigger trg_access_review_campaigns_updated_at before update on public.access_review_campaigns
for each row execute function public.set_updated_at();
drop trigger if exists trg_access_review_items_updated_at on public.access_review_items;
create trigger trg_access_review_items_updated_at before update on public.access_review_items
for each row execute function public.set_updated_at();
alter table public.access_review_campaigns enable row level security;
alter table public.access_review_items enable row level security;
drop policy if exists access_review_campaigns_read on public.access_review_campaigns;
create policy access_review_campaigns_read on public.access_review_campaigns for select to authenticated
using (public.current_is_full_access() or public.has_any_permission(array['access.review.read','access.review.manage']));
drop policy if exists access_review_items_read on public.access_review_items;
create policy access_review_items_read on public.access_review_items for select to authenticated
using (reviewer_user_id = auth.uid() or public.current_is_full_access() or public.has_any_permission(array['access.review.read','access.review.manage']));

-- ---------------------------------------------------------------------
-- Two-person break-glass workflow. The approved role is always temporary.
-- ---------------------------------------------------------------------
create table if not exists public.break_glass_requests (
  id               uuid primary key default gen_random_uuid(),
  target_user_id   uuid not null references auth.users(id) on delete cascade,
  requested_role_id uuid not null references public.roles(id) on delete restrict,
  duration_minutes integer not null check (duration_minutes between 5 and 240),
  reason           text not null check (length(trim(reason)) >= 10),
  status           text not null default 'pending' check (status in ('pending','approved','rejected','expired','revoked')),
  requested_by     uuid not null references auth.users(id),
  requested_at     timestamptz not null default now(),
  approved_by      uuid references auth.users(id),
  approved_at      timestamptz,
  rejected_by      uuid references auth.users(id),
  rejected_at      timestamptz,
  rejection_reason text,
  active_from      timestamptz,
  active_until     timestamptz,
  user_role_id     uuid references public.user_roles(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  check (requested_by is distinct from approved_by)
);
create index if not exists ix_break_glass_status on public.break_glass_requests(status, requested_at desc);
create index if not exists ix_break_glass_target on public.break_glass_requests(target_user_id, status);
drop trigger if exists trg_break_glass_requests_updated_at on public.break_glass_requests;
create trigger trg_break_glass_requests_updated_at before update on public.break_glass_requests
for each row execute function public.set_updated_at();
alter table public.break_glass_requests enable row level security;
drop policy if exists break_glass_read on public.break_glass_requests;
create policy break_glass_read on public.break_glass_requests for select to authenticated
using (
  target_user_id = auth.uid() or requested_by = auth.uid() or approved_by = auth.uid()
  or public.current_is_full_access()
  or public.has_any_permission(array['access.break_glass.request','access.break_glass.approve'])
);

-- ---------------------------------------------------------------------
-- Privacy requests (DSAR-lite): self-service, server-managed decisions.
-- ---------------------------------------------------------------------
create table if not exists public.privacy_requests (
  id               uuid primary key default gen_random_uuid(),
  request_number   bigint generated always as identity unique,
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  requester_employee_id uuid references public.employees(id) on delete set null,
  request_type     text not null check (request_type in ('access','correction','export','restriction','deletion','objection')),
  details          text not null check (length(trim(details)) >= 10),
  status           text not null default 'submitted' check (status in ('submitted','in_review','waiting_requester','approved','rejected','completed','cancelled')),
  due_at           timestamptz,
  assigned_to      uuid references auth.users(id),
  decision_reason  text,
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz
);
create index if not exists ix_privacy_requests_status on public.privacy_requests(status, due_at);
create index if not exists ix_privacy_requests_requester on public.privacy_requests(requester_user_id, created_at desc);
drop trigger if exists trg_privacy_requests_updated_at on public.privacy_requests;
create trigger trg_privacy_requests_updated_at before update on public.privacy_requests
for each row execute function public.set_updated_at();
alter table public.privacy_requests enable row level security;
drop policy if exists privacy_requests_read on public.privacy_requests;
create policy privacy_requests_read on public.privacy_requests for select to authenticated
using (requester_user_id = auth.uid() or assigned_to = auth.uid() or public.current_is_full_access() or public.has_permission('privacy.request.manage'));

-- ---------------------------------------------------------------------
-- Transactional integration outbox. Only service-side code may enqueue.
-- ---------------------------------------------------------------------
create table if not exists public.integration_outbox (
  id               uuid primary key default gen_random_uuid(),
  integration_id   uuid references public.integrations(id) on delete set null,
  event_type       text not null,
  aggregate_type   text,
  aggregate_id     uuid,
  idempotency_key  text not null unique,
  payload          jsonb not null default '{}'::jsonb,
  headers          jsonb not null default '{}'::jsonb,
  status           text not null default 'pending' check (status in ('pending','processing','delivered','retrying','failed','dead_letter','cancelled')),
  attempts         integer not null default 0 check (attempts >= 0),
  max_attempts     integer not null default 8 check (max_attempts between 1 and 30),
  next_attempt_at  timestamptz not null default now(),
  locked_at        timestamptz,
  locked_by        text,
  delivered_at     timestamptz,
  last_error       text,
  correlation_id   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz
);
create index if not exists ix_integration_outbox_ready on public.integration_outbox(status, next_attempt_at) where status in ('pending','retrying');
create index if not exists ix_integration_outbox_created on public.integration_outbox(created_at desc);
drop trigger if exists trg_integration_outbox_updated_at on public.integration_outbox;
create trigger trg_integration_outbox_updated_at before update on public.integration_outbox
for each row execute function public.set_updated_at();
alter table public.integration_outbox enable row level security;
drop policy if exists integration_outbox_read on public.integration_outbox;
create policy integration_outbox_read on public.integration_outbox for select to authenticated
using (public.current_is_full_access() or public.has_any_permission(array['system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage']));

-- ---------------------------------------------------------------------
-- Public release-policy contract. No PII is returned.
-- ---------------------------------------------------------------------
create or replace function public.get_public_release_policy(
  p_platform text,
  p_environment text default 'production',
  p_current_version text default '0.0.0',
  p_current_build integer default 0,
  p_installation_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_policy public.app_release_policies;
  v_device_status text;
  v_action text := 'none';
  v_rollout_bucket integer := 1;
begin
  if p_platform not in ('android','ios','web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  if p_environment not in ('development','staging','production') then
    raise exception 'invalid environment' using errcode = '22023';
  end if;

  select * into v_policy
  from public.app_release_policies
  where platform = p_platform and environment = p_environment
    and effective_from <= now() and (effective_to is null or effective_to > now())
  limit 1;

  if not found then
    return jsonb_build_object(
      'action','none','platform',p_platform,'environment',p_environment,
      'currentVersion',coalesce(p_current_version,'0.0.0'),'currentBuild',greatest(coalesce(p_current_build,0),0),
      'latestVersion',coalesce(p_current_version,'0.0.0'),'latestBuild',greatest(coalesce(p_current_build,0),0),
      'minSupportedVersion','0.0.0','minSupportedBuild',0,'forceUpdate',false,
      'maintenance',false,'messageAr',null,'storeUrl',null,'checkedAt',now()
    );
  end if;

  if p_installation_id is not null then
    v_rollout_bucket := (abs(hashtext(p_installation_id)) % 100) + 1;
    select status into v_device_status from public.managed_devices where installation_id = p_installation_id;
    if v_device_status in ('revoked','blocked') then
      v_action := 'blocked';
    end if;
  end if;

  if v_action = 'none' and v_policy.maintenance_enabled then
    v_action := 'maintenance';
  elsif v_action = 'none' and greatest(coalesce(p_current_build,0),0) < v_policy.min_supported_build then
    v_action := 'update_required';
  elsif v_action = 'none' and greatest(coalesce(p_current_build,0),0) < v_policy.latest_build then
    if v_policy.force_update then
      v_action := 'update_required';
    elsif v_rollout_bucket <= v_policy.rollout_percent then
      v_action := 'update_available';
    end if;
  end if;

  return jsonb_build_object(
    'action',v_action,'platform',v_policy.platform,'environment',v_policy.environment,
    'currentVersion',coalesce(p_current_version,'0.0.0'),'currentBuild',greatest(coalesce(p_current_build,0),0),
    'latestVersion',v_policy.latest_version,'latestBuild',v_policy.latest_build,
    'minSupportedVersion',v_policy.min_supported_version,'minSupportedBuild',v_policy.min_supported_build,
    'forceUpdate',v_policy.force_update,'maintenance',v_policy.maintenance_enabled,
    'messageAr',case when v_action='maintenance' then v_policy.maintenance_message_ar else v_policy.update_message_ar end,
    'storeUrl',v_policy.store_url,'checkedAt',now()
  );
end;
$$;
revoke execute on function public.get_public_release_policy(text,text,text,integer,text) from public;
grant execute on function public.get_public_release_policy(text,text,text,integer,text) to anon, authenticated;

create or replace function public.register_my_device(
  p_installation_id text,
  p_platform text,
  p_device_name text,
  p_device_model text,
  p_os_version text,
  p_app_version text,
  p_app_build integer,
  p_environment text default 'production',
  p_push_enabled boolean default false,
  p_biometric_available boolean default false,
  p_metadata jsonb default '{}'::jsonb
)
returns public.managed_devices
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.managed_devices; v_existing_user uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(trim(coalesce(p_installation_id,''))) < 12 then raise exception 'invalid installation id' using errcode='22023'; end if;
  if p_platform not in ('android','ios','web') then raise exception 'invalid platform' using errcode='22023'; end if;
  if p_environment not in ('development','staging','production') then raise exception 'invalid environment' using errcode='22023'; end if;

  select user_id into v_existing_user from public.managed_devices where installation_id=p_installation_id;
  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'installation belongs to another account' using errcode='42501';
  end if;

  insert into public.managed_devices(
    installation_id,user_id,employee_id,platform,device_name,device_model,os_version,
    app_version,app_build,environment,push_enabled,biometric_available,last_seen_at,metadata
  ) values (
    p_installation_id,auth.uid(),public.current_employee_id(),p_platform,nullif(trim(p_device_name),''),
    nullif(trim(p_device_model),''),nullif(trim(p_os_version),''),coalesce(nullif(trim(p_app_version),''),'0.0.0'),
    greatest(coalesce(p_app_build,0),0),p_environment,coalesce(p_push_enabled,false),
    coalesce(p_biometric_available,false),now(),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id=excluded.user_id,employee_id=excluded.employee_id,device_name=excluded.device_name,
    device_model=excluded.device_model,os_version=excluded.os_version,app_version=excluded.app_version,
    app_build=excluded.app_build,environment=excluded.environment,push_enabled=excluded.push_enabled,
    biometric_available=excluded.biometric_available,last_seen_at=now(),metadata=excluded.metadata,
    status=case when public.managed_devices.status='retired' then 'active' else public.managed_devices.status end
  returning * into v_row;
  perform public.log_security_event('device.registered','low','allowed',p_installation_id,
    jsonb_build_object('platform',p_platform,'appVersion',p_app_version,'appBuild',p_app_build));
  return v_row;
end;
$$;
revoke execute on function public.register_my_device(text,text,text,text,text,text,integer,text,boolean,boolean,jsonb) from public;
grant execute on function public.register_my_device(text,text,text,text,text,text,integer,text,boolean,boolean,jsonb) to authenticated;

create or replace function public.update_release_policy(
  p_platform text,
  p_environment text,
  p_latest_version text,
  p_latest_build integer,
  p_min_supported_version text,
  p_min_supported_build integer,
  p_force_update boolean,
  p_maintenance_enabled boolean,
  p_maintenance_message_ar text,
  p_update_message_ar text,
  p_store_url text,
  p_rollout_percent integer default 100,
  p_reason text default null
)
returns public.app_release_policies
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.app_release_policies;
begin
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'release policy denied' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'reason required' using errcode='22023'; end if;
  if p_latest_build < p_min_supported_build then raise exception 'latest build must be >= minimum build' using errcode='22023'; end if;
  insert into public.app_release_policies(
    platform,environment,latest_version,latest_build,min_supported_version,min_supported_build,
    force_update,maintenance_enabled,maintenance_message_ar,update_message_ar,store_url,
    rollout_percent,created_by,updated_by
  ) values (
    p_platform,p_environment,p_latest_version,p_latest_build,p_min_supported_version,p_min_supported_build,
    coalesce(p_force_update,false),coalesce(p_maintenance_enabled,false),p_maintenance_message_ar,
    p_update_message_ar,p_store_url,greatest(0,least(coalesce(p_rollout_percent,100),100)),auth.uid(),auth.uid()
  )
  on conflict (platform,environment) do update set
    latest_version=excluded.latest_version,latest_build=excluded.latest_build,
    min_supported_version=excluded.min_supported_version,min_supported_build=excluded.min_supported_build,
    force_update=excluded.force_update,maintenance_enabled=excluded.maintenance_enabled,
    maintenance_message_ar=excluded.maintenance_message_ar,update_message_ar=excluded.update_message_ar,
    store_url=excluded.store_url,rollout_percent=excluded.rollout_percent,updated_by=auth.uid(),updated_at=now()
  returning * into v_row;
  perform public.log_audit_event('release.policy.updated','system','warning','app_release_policies',v_row.id,
    'تحديث سياسة إصدار',p_reason,jsonb_build_object('platform',p_platform,'environment',p_environment,'latestBuild',p_latest_build,'minimumBuild',p_min_supported_build,'maintenance',p_maintenance_enabled));
  return v_row;
end;
$$;
revoke execute on function public.update_release_policy(text,text,text,integer,text,integer,boolean,boolean,text,text,text,integer,text) from public;
grant execute on function public.update_release_policy(text,text,text,integer,text,integer,boolean,boolean,text,text,text,integer,text) to authenticated;

create or replace function public.revoke_managed_device(p_device_id uuid, p_reason text)
returns public.managed_devices
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.managed_devices;
begin
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'reason required' using errcode='22023'; end if;
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'device revoke denied' using errcode='42501';
  end if;
  update public.managed_devices set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revoke_reason=p_reason
  where id=p_device_id returning * into v_row;
  if not found then raise exception 'device not found' using errcode='P0002'; end if;
  perform public.log_security_event('device.revoked','high','blocked',v_row.installation_id,jsonb_build_object('reason',p_reason,'userId',v_row.user_id));
  return v_row;
end;
$$;
revoke execute on function public.revoke_managed_device(uuid,text) from public;
grant execute on function public.revoke_managed_device(uuid,text) to authenticated;

create or replace function public.create_access_review_campaign(p_name text, p_description text, p_due_at timestamptz)
returns public.access_review_campaigns
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_campaign public.access_review_campaigns;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then
    raise exception 'access review denied' using errcode='42501';
  end if;
  if p_due_at is null or p_due_at <= now() then raise exception 'future due date required' using errcode='22023'; end if;
  insert into public.access_review_campaigns(name,description,status,starts_at,due_at,created_by)
  values (trim(p_name),p_description,'active',now(),p_due_at,auth.uid()) returning * into v_campaign;
  insert into public.access_review_items(campaign_id,user_role_id,user_id,role_id,reviewer_user_id,snapshot)
  select v_campaign.id,ur.id,ur.user_id,ur.role_id,auth.uid(),jsonb_build_object(
    'roleSlug',r.slug,'roleName',r.name_ar,'effectiveFrom',ur.effective_from,'effectiveTo',ur.effective_to,'scopeOverride',ur.scope_override
  )
  from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());
  perform public.log_audit_event('access.review.started','access','notice','access_review_campaigns',v_campaign.id,'بدء مراجعة صلاحيات',p_description,jsonb_build_object('dueAt',p_due_at));
  return v_campaign;
end;
$$;
revoke execute on function public.create_access_review_campaign(text,text,timestamptz) from public;
grant execute on function public.create_access_review_campaign(text,text,timestamptz) to authenticated;

create or replace function public.decide_access_review_item(p_item_id uuid, p_decision text, p_reason text)
returns public.access_review_items
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_item public.access_review_items;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then raise exception 'access review denied' using errcode='42501'; end if;
  if p_decision not in ('keep','revoke') then raise exception 'invalid decision' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  select * into v_item from public.access_review_items where id=p_item_id for update;
  if not found then raise exception 'review item not found' using errcode='P0002'; end if;
  if v_item.decision <> 'pending' then raise exception 'review item already decided' using errcode='P0001'; end if;
  update public.access_review_items set decision=p_decision,decision_reason=p_reason,decided_at=now(),reviewer_user_id=auth.uid()
  where id=p_item_id returning * into v_item;
  if p_decision='revoke' then update public.user_roles set effective_to=now() where id=v_item.user_role_id; end if;
  perform public.log_audit_event('access.review.decided','access',case when p_decision='revoke' then 'warning' else 'info' end,
    'access_review_items',v_item.id,'قرار مراجعة صلاحية',p_reason,jsonb_build_object('decision',p_decision,'userRoleId',v_item.user_role_id));
  return v_item;
end;
$$;
revoke execute on function public.decide_access_review_item(uuid,text,text) from public;
grant execute on function public.decide_access_review_item(uuid,text,text) to authenticated;

create or replace function public.request_break_glass(p_target_user_id uuid, p_role_id uuid, p_duration_minutes integer, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.break_glass_requests; v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.request')) then raise exception 'break glass request denied' using errcode='42501'; end if;
  select * into v_role from public.roles where id=p_role_id;
  if not found then raise exception 'role not found' using errcode='P0002'; end if;
  if p_duration_minutes not between 5 and 240 then raise exception 'duration out of range' using errcode='22023'; end if;
  insert into public.break_glass_requests(target_user_id,requested_role_id,duration_minutes,reason,requested_by)
  values(p_target_user_id,p_role_id,p_duration_minutes,trim(p_reason),auth.uid()) returning * into v_row;
  perform public.log_security_event('break_glass.requested','critical','detected',p_target_user_id::text,
    jsonb_build_object('requestId',v_row.id,'role',v_role.slug,'durationMinutes',p_duration_minutes,'reason',p_reason));
  return v_row;
end;
$$;
revoke execute on function public.request_break_glass(uuid,uuid,integer,text) from public;
grant execute on function public.request_break_glass(uuid,uuid,integer,text) to authenticated;

create or replace function public.approve_break_glass(p_request_id uuid, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_req public.break_glass_requests; v_user_role public.user_roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'break glass approval denied' using errcode='42501'; end if;
  select * into v_req from public.break_glass_requests where id=p_request_id for update;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status <> 'pending' then raise exception 'request is not pending' using errcode='P0001'; end if;
  if v_req.requested_by=auth.uid() then raise exception 'four-eyes approval required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'approval reason required' using errcode='22023'; end if;
  if exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_req.target_user_id and ur.role_id=v_req.requested_role_id
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'target user already has the requested active role' using errcode='P0001';
  end if;
  insert into public.user_roles(user_id,role_id,scope_override,effective_from,effective_to,granted_by)
  values(v_req.target_user_id,v_req.requested_role_id,jsonb_build_object('breakGlassRequestId',v_req.id),now(),now()+make_interval(mins=>v_req.duration_minutes),auth.uid())
  on conflict (user_id,role_id) do update set
    scope_override=excluded.scope_override,effective_from=excluded.effective_from,effective_to=excluded.effective_to,granted_by=excluded.granted_by
  returning * into v_user_role;
  update public.break_glass_requests set status='approved',approved_by=auth.uid(),approved_at=now(),active_from=now(),
    active_until=v_user_role.effective_to,user_role_id=v_user_role.id where id=v_req.id returning * into v_req;
  perform public.log_security_event('break_glass.approved','critical','allowed',v_req.target_user_id::text,
    jsonb_build_object('requestId',v_req.id,'userRoleId',v_user_role.id,'activeUntil',v_req.active_until,'reason',p_reason));
  return v_req;
end;
$$;
revoke execute on function public.approve_break_glass(uuid,text) from public;
grant execute on function public.approve_break_glass(uuid,text) to authenticated;

create or replace function public.reject_break_glass(p_request_id uuid, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_req public.break_glass_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'break glass rejection denied' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  update public.break_glass_requests set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=p_reason
  where id=p_request_id and status='pending' returning * into v_req;
  if not found then raise exception 'pending request not found' using errcode='P0002'; end if;
  perform public.log_security_event('break_glass.rejected','high','blocked',v_req.target_user_id::text,jsonb_build_object('requestId',v_req.id,'reason',p_reason));
  return v_req;
end;
$$;
revoke execute on function public.reject_break_glass(uuid,text) from public;
grant execute on function public.reject_break_glass(uuid,text) to authenticated;

create or replace function public.submit_privacy_request(p_request_type text, p_details text)
returns public.privacy_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.privacy_requests;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_request_type not in ('access','correction','export','restriction','deletion','objection') then raise exception 'invalid privacy request type' using errcode='22023'; end if;
  insert into public.privacy_requests(requester_user_id,requester_employee_id,request_type,details,due_at)
  values(auth.uid(),public.current_employee_id(),p_request_type,trim(p_details),now()+interval '30 days') returning * into v_row;
  perform public.log_audit_event('privacy.request.submitted','data','notice','privacy_requests',v_row.id,'تقديم طلب خصوصية',null,jsonb_build_object('requestType',p_request_type));
  return v_row;
end;
$$;
revoke execute on function public.submit_privacy_request(text,text) from public;
grant execute on function public.submit_privacy_request(text,text) to authenticated;

create or replace function public.decide_privacy_request(p_request_id uuid, p_status text, p_reason text)
returns public.privacy_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.privacy_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('privacy.request.manage')) then raise exception 'privacy management denied' using errcode='42501'; end if;
  if p_status not in ('in_review','waiting_requester','approved','rejected','completed') then raise exception 'invalid status' using errcode='22023'; end if;
  if p_status in ('rejected','completed') and length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  update public.privacy_requests set status=p_status,decision_reason=p_reason,assigned_to=coalesce(assigned_to,auth.uid()),
    completed_at=case when p_status='completed' then now() else completed_at end where id=p_request_id returning * into v_row;
  if not found then raise exception 'privacy request not found' using errcode='P0002'; end if;
  perform public.log_audit_event('privacy.request.updated','data','notice','privacy_requests',v_row.id,'تحديث طلب خصوصية',p_reason,jsonb_build_object('status',p_status));
  return v_row;
end;
$$;
revoke execute on function public.decide_privacy_request(uuid,text,text) from public;
grant execute on function public.decide_privacy_request(uuid,text,text) to authenticated;

create or replace function public.enqueue_integration_event(
  p_integration_id uuid,
  p_event_type text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_idempotency_key text,
  p_payload jsonb,
  p_headers jsonb default '{}'::jsonb,
  p_correlation_id text default null
)
returns public.integration_outbox
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.integration_outbox;
begin
  if length(trim(coalesce(p_idempotency_key,''))) < 8 then raise exception 'idempotency key required' using errcode='22023'; end if;
  insert into public.integration_outbox(integration_id,event_type,aggregate_type,aggregate_id,idempotency_key,payload,headers,correlation_id)
  values(p_integration_id,p_event_type,p_aggregate_type,p_aggregate_id,p_idempotency_key,coalesce(p_payload,'{}'::jsonb),coalesce(p_headers,'{}'::jsonb),p_correlation_id)
  on conflict (idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.enqueue_integration_event(uuid,text,text,uuid,text,jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.enqueue_integration_event(uuid,text,text,uuid,text,jsonb,jsonb,text) to service_role;

create or replace function public.get_release_governance_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array[
    'system.release.read','system.release.manage','access.review.read','access.review.manage',
    'access.break_glass.request','access.break_glass.approve','privacy.request.manage',
    'system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage'
  ])) then raise exception 'governance overview denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'policies',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'platform',p.platform,'environment',p.environment,'latestVersion',p.latest_version,'latestBuild',p.latest_build,
      'minSupportedVersion',p.min_supported_version,'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
      'maintenance',p.maintenance_enabled,'maintenanceMessageAr',p.maintenance_message_ar,'updateMessageAr',p.update_message_ar,
      'storeUrl',p.store_url,'rolloutPercent',p.rollout_percent,'updatedAt',coalesce(p.updated_at,p.created_at)
    ) order by p.platform,p.environment) from public.app_release_policies p),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'installationId',d.installation_id,'userId',d.user_id,'employeeId',d.employee_id,
      'employeeName',e.full_name,'employeeCode',e.employee_code,'platform',d.platform,'deviceName',d.device_name,
      'deviceModel',d.device_model,'osVersion',d.os_version,'appVersion',d.app_version,'appBuild',d.app_build,
      'environment',d.environment,'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
    ) order by d.last_seen_at desc) from public.managed_devices d left join public.employees e on e.id=d.employee_id),'[]'::jsonb),
    'accessReviews',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,'dueAt',c.due_at,
      'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
      'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
      'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
    ) order by c.created_at desc) from public.access_review_campaigns c),'[]'::jsonb),
    'reviewItems',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,'userId',i.user_id,'roleId',i.role_id,
      'employeeName',e.full_name,'employeeCode',e.employee_code,'roleName',r.name_ar,'decision',i.decision,
      'decisionReason',i.decision_reason,'decidedAt',i.decided_at,'snapshot',i.snapshot
    ) order by i.created_at desc) from public.access_review_items i
      left join public.profiles pr on pr.id=i.user_id left join public.employees e on e.id=pr.employee_id join public.roles r on r.id=i.role_id
      where i.decision='pending'),'[]'::jsonb),
    'breakGlass',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'targetUserId',b.target_user_id,'targetName',e.full_name,'targetCode',e.employee_code,
      'roleId',b.requested_role_id,'roleName',r.name_ar,'durationMinutes',b.duration_minutes,'reason',b.reason,
      'status',b.status,'requestedBy',b.requested_by,'requestedAt',b.requested_at,'activeUntil',b.active_until
    ) order by b.requested_at desc) from public.break_glass_requests b
      left join public.profiles pr on pr.id=b.target_user_id left join public.employees e on e.id=pr.employee_id join public.roles r on r.id=b.requested_role_id),'[]'::jsonb),
    'privacyRequests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'requestNumber',p.request_number,'requesterUserId',p.requester_user_id,'employeeName',e.full_name,
      'employeeCode',e.employee_code,'requestType',p.request_type,'details',p.details,'status',p.status,'dueAt',p.due_at,
      'decisionReason',p.decision_reason,'createdAt',p.created_at
    ) order by p.created_at desc) from public.privacy_requests p left join public.employees e on e.id=p.requester_employee_id),'[]'::jsonb),
    'outbox',jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access) order by r.name_ar) from public.roles r),'[]'::jsonb),
    'users',coalesce((select jsonb_agg(jsonb_build_object('userId',p.id,'employeeId',p.employee_id,'name',e.full_name,'employeeCode',e.employee_code,'status',p.status) order by e.full_name) from public.profiles p left join public.employees e on e.id=p.employee_id),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end;
$$;
revoke execute on function public.get_release_governance_overview() from public;
grant execute on function public.get_release_governance_overview() to authenticated;

-- Expire stale break-glass access safely. Suitable for a scheduled worker.
create or replace function public.expire_break_glass_access()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  update public.break_glass_requests b set status='expired',updated_at=now()
  where status='approved' and active_until <= now();
  get diagnostics v_count = row_count;
  update public.user_roles ur set effective_to=least(coalesce(ur.effective_to,now()),now())
  where exists (select 1 from public.break_glass_requests b where b.user_role_id=ur.id and b.status='expired');
  return v_count;
end;
$$;
revoke execute on function public.expire_break_glass_access() from public, anon, authenticated;
grant execute on function public.expire_break_glass_access() to service_role;

-- Auditing for governance records. Outbox payloads are intentionally excluded to avoid duplicating sensitive data in audit logs.
do $$
declare t text;
begin
  foreach t in array array['app_release_policies','managed_devices','access_review_campaigns','access_review_items','break_glass_requests','privacy_requests'] loop
    execute format('drop trigger if exists %I on public.%I', 'trg_'||t||'_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row_change()', 'trg_'||t||'_audit', t);
  end loop;
end $$;

commit;
