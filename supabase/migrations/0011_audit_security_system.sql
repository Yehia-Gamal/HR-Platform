-- Migration 0011: التدقيق والأمان والنظام (Audit, Security & System)
-- يعتمد على: 0001 (extensions, set_updated_at)، 0002 (دوال التخويل)، 0004 (employees, profiles).
-- لا يعيد تعريف أي جدول سابق — يشير إليها بـ FK فقط.
-- تشغيل عبر: supabase db push. الملف idempotent قدر الإمكان.
-- كل الطوابع الزمنية UTC. لا DROP لأي جدول.

-- =====================================================================
-- 0) trigger helpers (idempotent)
-- =====================================================================

-- set_updated_at: يحدّث updated_at = now() عند كل UPDATE (نفس تعريف 0001).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
comment on function public.set_updated_at() is
  'Trigger helper: sets updated_at = now() (UTC) on row update.';

-- audit_row_change: trigger عام يسجّل كل INSERT/UPDATE/DELETE في public.audit_logs.
-- يُربط بأي جدول حسّاس. يكتب صورة قبل/بعد بصيغة jsonb + الحقول المتغيّرة.
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old        jsonb;
  v_new        jsonb;
  v_changed    text[] := '{}';
  v_row_id     uuid;
  v_actor      uuid := auth.uid();
  v_key        text;
begin
  if (tg_op = 'DELETE') then
    v_old := to_jsonb(old);
    v_new := null;
    begin v_row_id := (old).id; exception when others then v_row_id := null; end;
  elsif (tg_op = 'UPDATE') then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    begin v_row_id := (new).id; exception when others then v_row_id := null; end;
    for v_key in select jsonb_object_keys(v_new) loop
      if (v_old -> v_key) is distinct from (v_new -> v_key) then
        v_changed := array_append(v_changed, v_key);
      end if;
    end loop;
  else -- INSERT
    v_old := null;
    v_new := to_jsonb(new);
    begin v_row_id := (new).id; exception when others then v_row_id := null; end;
  end if;

  insert into public.audit_logs
    (table_name, schema_name, record_id, action, actor_user_id,
     old_data, new_data, changed_columns, occurred_at)
  values
    (tg_table_name, tg_table_schema, v_row_id, lower(tg_op), v_actor,
     v_old, v_new, v_changed, now());

  if (tg_op = 'DELETE') then
    return old;
  end if;
  return new;
end;
$$;
comment on function public.audit_row_change() is
  'Trigger عام: يسجّل INSERT/UPDATE/DELETE في public.audit_logs مع صورة قبل/بعد والحقول المتغيّرة. SECURITY DEFINER.';

revoke execute on function public.audit_row_change() from public;

-- =====================================================================
-- Table: audit_logs  (سجل التدقيق العام — صورة الصفوف)
-- =====================================================================
create table if not exists public.audit_logs (
  id               uuid primary key default gen_random_uuid(),
  table_name       text not null,
  schema_name      text not null default 'public',
  record_id        uuid,
  action           text not null
                     check (action in ('insert','update','delete','truncate')),
  actor_user_id    uuid references auth.users(id) on delete set null,
  actor_employee_id uuid references public.employees(id) on delete set null,
  old_data         jsonb,
  new_data         jsonb,
  changed_columns  text[] not null default '{}',
  reason           text,
  ip_address       inet,
  user_agent       text,
  request_id       text,
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.audit_logs is
  'سجل التدقيق العام: صورة قبل/بعد لكل تغيير صفّي على الجداول الحسّاسة. تُكتب عبر audit_row_change فقط.';

create index if not exists ix_audit_logs_table on public.audit_logs (table_name);
create index if not exists ix_audit_logs_record on public.audit_logs (record_id);
create index if not exists ix_audit_logs_actor on public.audit_logs (actor_user_id);
create index if not exists ix_audit_logs_occurred on public.audit_logs (occurred_at desc);
create index if not exists ix_audit_logs_action on public.audit_logs (action);

alter table public.audit_logs enable row level security;

-- قراءة: full-access أو صلاحية audit.log.view. لا INSERT/UPDATE/DELETE من المستخدمين (تُكتب عبر trigger SECURITY DEFINER).
drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['audit.log.view','audit.view']));

-- لا سياسة INSERT/UPDATE/DELETE للمستخدمين: append-only عبر SECURITY DEFINER trigger فقط.

-- =====================================================================
-- Table: audit_events  (أحداث تدقيق دلالية — append-only, no direct INSERT)
-- =====================================================================
create table if not exists public.audit_events (
  id               uuid primary key default gen_random_uuid(),
  event_type       text not null,                 -- e.g. permission.granted, request.approved
  category         text not null default 'general'
                     check (category in ('general','access','data','workflow','security','system','integration')),
  severity         text not null default 'info'
                     check (severity in ('debug','info','notice','warning','error','critical')),
  actor_user_id    uuid references auth.users(id) on delete set null,
  actor_employee_id uuid references public.employees(id) on delete set null,
  target_table     text,
  target_id        uuid,
  summary_ar       text,
  description      text,
  metadata         jsonb not null default '{}'::jsonb,
  ip_address       inet,
  user_agent       text,
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.audit_events is
  'أحداث تدقيق دلالية عالية المستوى (append-only). تُكتب عبر RPC log_audit_event فقط — لا INSERT مباشر.';

create index if not exists ix_audit_events_type on public.audit_events (event_type);
create index if not exists ix_audit_events_category on public.audit_events (category);
create index if not exists ix_audit_events_severity on public.audit_events (severity);
create index if not exists ix_audit_events_actor on public.audit_events (actor_user_id);
create index if not exists ix_audit_events_occurred on public.audit_events (occurred_at desc);
create index if not exists ix_audit_events_target on public.audit_events (target_table, target_id);

alter table public.audit_events enable row level security;

-- قراءة: full-access أو audit.view. لا INSERT/UPDATE/DELETE مباشر (append-only عبر RPC).
drop policy if exists audit_events_select on public.audit_events;
create policy audit_events_select on public.audit_events
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['audit.event.view','audit.view']));

-- =====================================================================
-- Table: security_events  (أحداث أمنية)
-- =====================================================================
create table if not exists public.security_events (
  id               uuid primary key default gen_random_uuid(),
  event_type       text not null                  -- login_failed, mfa_challenge, privilege_escalation ...
                     ,
  severity         text not null default 'medium'
                     check (severity in ('low','medium','high','critical')),
  outcome          text not null default 'detected'
                     check (outcome in ('detected','blocked','allowed','resolved','ignored')),
  user_id          uuid references auth.users(id) on delete set null,
  employee_id      uuid references public.employees(id) on delete set null,
  identifier       text,                          -- بريد/هاتف/معرّف مُدخَل عند محاولة الدخول
  ip_address       inet,
  user_agent       text,
  geo              jsonb,
  details          jsonb not null default '{}'::jsonb,
  handled          boolean not null default false,
  handled_by       uuid references auth.users(id) on delete set null,
  handled_at       timestamptz,
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.security_events is
  'أحداث أمنية: فشل دخول، تحدي MFA، تصعيد صلاحيات، نشاط مريب — مع الخطورة والنتيجة والمعالجة.';

create index if not exists ix_security_events_type on public.security_events (event_type);
create index if not exists ix_security_events_severity on public.security_events (severity);
create index if not exists ix_security_events_user on public.security_events (user_id);
create index if not exists ix_security_events_ip on public.security_events (ip_address);
create index if not exists ix_security_events_occurred on public.security_events (occurred_at desc);
create index if not exists ix_security_events_unhandled on public.security_events (handled) where handled = false;

drop trigger if exists trg_security_events_updated_at on public.security_events;
create trigger trg_security_events_updated_at
  before update on public.security_events
  for each row execute function public.set_updated_at();

alter table public.security_events enable row level security;

-- قراءة: full-access أو security.event.view. كتابة/معالجة: full-access أو security.event.manage.
drop policy if exists security_events_select on public.security_events;
create policy security_events_select on public.security_events
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['security.event.view','audit.view']));

drop policy if exists security_events_write on public.security_events;
create policy security_events_write on public.security_events
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('security.event.manage'))
  with check (public.current_is_full_access() or public.has_permission('security.event.manage'));

-- =====================================================================
-- Table: login_identifier_attempts  (محاولات الدخول لكل معرّف — rate limiting)
-- =====================================================================
create table if not exists public.login_identifier_attempts (
  id               uuid primary key default gen_random_uuid(),
  identifier       text not null,                 -- البريد/الهاتف/اسم المستخدم المُدخَل
  identifier_kind  text not null default 'email'
                     check (identifier_kind in ('email','phone','username','national_id')),
  ip_address       inet,
  user_agent       text,
  success          boolean not null default false,
  failure_reason   text,
  attempted_at     timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.login_identifier_attempts is
  'محاولات تسجيل الدخول لكل معرّف (نجاح/فشل) لأغراض الحدّ من المعدّل وكشف الهجمات.';

create index if not exists ix_login_attempts_identifier on public.login_identifier_attempts (identifier);
create index if not exists ix_login_attempts_ip on public.login_identifier_attempts (ip_address);
create index if not exists ix_login_attempts_attempted on public.login_identifier_attempts (attempted_at desc);
create index if not exists ix_login_attempts_ident_time on public.login_identifier_attempts (identifier, attempted_at desc);

alter table public.login_identifier_attempts enable row level security;

-- قراءة: full-access أو security.event.view فقط (بيانات حسّاسة). الكتابة عبر service_role/RPC.
drop policy if exists login_attempts_select on public.login_identifier_attempts;
create policy login_attempts_select on public.login_identifier_attempts
  for select to authenticated
  using (public.current_is_full_access() or public.has_permission('security.event.view'));

-- =====================================================================
-- Table: credential_vault  (خزنة أسرار — service_role only)
-- =====================================================================
create table if not exists public.credential_vault (
  id               uuid primary key default gen_random_uuid(),
  key_name         text not null unique,          -- معرّف منطقي للسرّ
  category         text not null default 'general'
                     check (category in ('general','integration','smtp','sms','payment','signing','api_key','oauth')),
  secret_ciphertext bytea,                         -- قيمة مشفّرة (تُدار عبر service_role)
  secret_hint      text,                           -- تلميح غير حسّاس (آخر 4 خانات مثلاً)
  metadata         jsonb not null default '{}'::jsonb,
  rotated_at       timestamptz,
  expires_at       timestamptz,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.credential_vault is
  'خزنة الأسرار والاعتمادات (مشفّرة). الوصول لدور service_role حصراً — لا سياسات للمستخدمين المصادَقين.';

create index if not exists ix_credential_vault_category on public.credential_vault (category);
create index if not exists ix_credential_vault_active on public.credential_vault (is_active) where is_active = true;

drop trigger if exists trg_credential_vault_updated_at on public.credential_vault;
create trigger trg_credential_vault_updated_at
  before update on public.credential_vault
  for each row execute function public.set_updated_at();

alter table public.credential_vault enable row level security;
-- إلزام تطبيق RLS حتى لمالك الجدول (باستثناء service_role الذي يتجاوز RLS).
alter table public.credential_vault force row level security;

-- لا توجد سياسات لدور authenticated: بذلك يُرفض كل وصول من المستخدمين المصادَقين.
-- service_role يتجاوز RLS تلقائياً في Supabase، فهو الوحيد القادر على القراءة/الكتابة.

-- =====================================================================
-- Table: password_reset_requests  (طلبات إعادة تعيين كلمة المرور — token hash)
-- =====================================================================
create table if not exists public.password_reset_requests (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users(id) on delete cascade,
  identifier       text not null,                 -- المعرّف المستخدم في الطلب
  token_hash       text not null,                 -- تخزين hash فقط — لا التوكن الخام
  ip_address       inet,
  user_agent       text,
  requested_at     timestamptz not null default now(),
  expires_at       timestamptz not null,
  consumed_at      timestamptz,
  consumed         boolean not null default false,
  attempts         integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.password_reset_requests is
  'طلبات إعادة تعيين كلمة المرور: يُخزَّن hash التوكن فقط مع الصلاحية والاستهلاك. الوصول service_role/RPC.';

create index if not exists ix_pwd_reset_user on public.password_reset_requests (user_id);
create index if not exists ix_pwd_reset_token on public.password_reset_requests (token_hash);
create index if not exists ix_pwd_reset_expires on public.password_reset_requests (expires_at);
create unique index if not exists ux_pwd_reset_token_hash on public.password_reset_requests (token_hash);

drop trigger if exists trg_pwd_reset_updated_at on public.password_reset_requests;
create trigger trg_pwd_reset_updated_at
  before update on public.password_reset_requests
  for each row execute function public.set_updated_at();

alter table public.password_reset_requests enable row level security;
alter table public.password_reset_requests force row level security;

-- بيانات حسّاسة جداً: لا سياسات لدور authenticated (service_role فقط عبر تجاوز RLS).

-- =====================================================================
-- Table: settings  (إعدادات عامة قابلة للنطاق — user/org/module)
-- =====================================================================
create table if not exists public.settings (
  id               uuid primary key default gen_random_uuid(),
  scope            text not null default 'organization'
                     check (scope in ('organization','branch','department','role','user','module')),
  scope_id         uuid,                           -- المرجع حسب النطاق (branch_id, user_id ...)
  category         text not null default 'general',
  key              text not null,
  value            jsonb not null default '{}'::jsonb,
  value_type       text not null default 'json'
                     check (value_type in ('json','string','number','boolean','array')),
  description      text,
  is_public        boolean not null default false, -- هل يمكن قراءتها لأي مصادَق؟
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id),
  unique (scope, scope_id, category, key)
);
comment on table public.settings is
  'إعدادات عامة قابلة للنطاق (منظمة/فرع/قسم/دور/مستخدم/وحدة) بصيغة مفتاح/قيمة jsonb.';

create index if not exists ix_settings_scope on public.settings (scope, scope_id);
create index if not exists ix_settings_category on public.settings (category);
create index if not exists ix_settings_key on public.settings (key);

drop trigger if exists trg_settings_updated_at on public.settings;
create trigger trg_settings_updated_at
  before update on public.settings
  for each row execute function public.set_updated_at();

alter table public.settings enable row level security;

-- قراءة: العامة لأي مصادَق، أو إعدادات المستخدم نفسه، أو full-access/settings.read.
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to authenticated
  using (
    is_public
    or public.current_is_full_access()
    or public.has_any_permission(array['settings.read','settings.manage'])
    or (scope = 'user' and scope_id = auth.uid())
  );

-- كتابة إعدادات المستخدم نفسه: مسموح. باقي النطاقات: full-access/settings.manage.
drop policy if exists settings_write_own on public.settings;
create policy settings_write_own on public.settings
  for all to authenticated
  using (scope = 'user' and scope_id = auth.uid())
  with check (scope = 'user' and scope_id = auth.uid());

drop policy if exists settings_write_admin on public.settings;
create policy settings_write_admin on public.settings
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('settings.manage'))
  with check (public.current_is_full_access() or public.has_permission('settings.manage'));

-- =====================================================================
-- Table: system_settings  (إعدادات النظام العالمية — singleton-like keys)
-- =====================================================================
create table if not exists public.system_settings (
  id               uuid primary key default gen_random_uuid(),
  key              text not null unique,
  value            jsonb not null default '{}'::jsonb,
  value_type       text not null default 'json'
                     check (value_type in ('json','string','number','boolean','array')),
  group_name       text not null default 'general',
  label_ar         text,
  description      text,
  is_secret        boolean not null default false, -- إن true تُقيَّد القراءة على full-access
  is_editable      boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.system_settings is
  'إعدادات النظام العالمية (مفتاح فريد). الأسرار منها is_secret=true تُقرأ لـ full-access فقط.';

create index if not exists ix_system_settings_group on public.system_settings (group_name);

drop trigger if exists trg_system_settings_updated_at on public.system_settings;
create trigger trg_system_settings_updated_at
  before update on public.system_settings
  for each row execute function public.set_updated_at();

alter table public.system_settings enable row level security;

-- قراءة: غير السرّية لأي مصادَق؛ السرّية لـ full-access أو settings.read.
drop policy if exists system_settings_select on public.system_settings;
create policy system_settings_select on public.system_settings
  for select to authenticated
  using (
    (not is_secret)
    or public.current_is_full_access()
    or public.has_any_permission(array['settings.read','settings.manage'])
  );

-- كتابة: full-access أو settings.manage.
drop policy if exists system_settings_write on public.system_settings;
create policy system_settings_write on public.system_settings
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('settings.manage'))
  with check (public.current_is_full_access() or public.has_permission('settings.manage'));

-- =====================================================================
-- Table: system_backups  (سجل النسخ الاحتياطية)
-- =====================================================================
create table if not exists public.system_backups (
  id               uuid primary key default gen_random_uuid(),
  backup_type      text not null default 'full'
                     check (backup_type in ('full','incremental','snapshot','manual','scheduled')),
  status           text not null default 'pending'
                     check (status in ('pending','running','completed','failed','expired','deleted')),
  storage_provider text,                            -- s3, supabase-storage, gcs ...
  storage_path     text,
  size_bytes       bigint,
  checksum         text,
  started_at       timestamptz,
  finished_at      timestamptz,
  expires_at       timestamptz,
  error_message    text,
  metadata         jsonb not null default '{}'::jsonb,
  triggered_by     uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.system_backups is
  'سجل النسخ الاحتياطية: النوع، الحالة، مزود التخزين، الحجم، والصلاحية.';

create index if not exists ix_system_backups_status on public.system_backups (status);
create index if not exists ix_system_backups_type on public.system_backups (backup_type);
create index if not exists ix_system_backups_started on public.system_backups (started_at desc);

drop trigger if exists trg_system_backups_updated_at on public.system_backups;
create trigger trg_system_backups_updated_at
  before update on public.system_backups
  for each row execute function public.set_updated_at();

alter table public.system_backups enable row level security;

drop policy if exists system_backups_select on public.system_backups;
create policy system_backups_select on public.system_backups
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['system.backup.view','system.manage']));

drop policy if exists system_backups_write on public.system_backups;
create policy system_backups_write on public.system_backups
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('system.backup.manage'))
  with check (public.current_is_full_access() or public.has_permission('system.backup.manage'));

-- =====================================================================
-- Table: app_error_events  (سجل أخطاء التطبيق)
-- =====================================================================
create table if not exists public.app_error_events (
  id               uuid primary key default gen_random_uuid(),
  level            text not null default 'error'
                     check (level in ('debug','info','warning','error','fatal')),
  source           text not null default 'server'
                     check (source in ('client','server','edge','worker','job','integration')),
  error_code       text,
  message          text not null,
  stack_trace      text,
  route            text,
  http_method      text,
  http_status      integer,
  user_id          uuid references auth.users(id) on delete set null,
  employee_id      uuid references public.employees(id) on delete set null,
  request_id       text,
  environment      text not null default 'production',
  context          jsonb not null default '{}'::jsonb,
  resolved         boolean not null default false,
  resolved_by      uuid references auth.users(id) on delete set null,
  resolved_at      timestamptz,
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.app_error_events is
  'أحداث أخطاء التطبيق (client/server/edge) مع المستوى والمسار وحالة المعالجة.';

create index if not exists ix_app_errors_level on public.app_error_events (level);
create index if not exists ix_app_errors_source on public.app_error_events (source);
create index if not exists ix_app_errors_occurred on public.app_error_events (occurred_at desc);
create index if not exists ix_app_errors_unresolved on public.app_error_events (resolved) where resolved = false;
create index if not exists ix_app_errors_code on public.app_error_events (error_code);

drop trigger if exists trg_app_errors_updated_at on public.app_error_events;
create trigger trg_app_errors_updated_at
  before update on public.app_error_events
  for each row execute function public.set_updated_at();

alter table public.app_error_events enable row level security;

drop policy if exists app_errors_select on public.app_error_events;
create policy app_errors_select on public.app_error_events
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['system.error.view','system.manage']));

drop policy if exists app_errors_write on public.app_error_events;
create policy app_errors_write on public.app_error_events
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('system.error.manage'))
  with check (public.current_is_full_access() or public.has_permission('system.error.manage'));

-- =====================================================================
-- Table: feature_flags  (مفاتيح تفعيل الميزات)
-- =====================================================================
create table if not exists public.feature_flags (
  id               uuid primary key default gen_random_uuid(),
  flag_key         text not null unique,
  name_ar          text,
  description      text,
  is_enabled       boolean not null default false,
  rollout_percent  integer not null default 0 check (rollout_percent between 0 and 100),
  target_rules     jsonb not null default '{}'::jsonb, -- استهداف أدوار/فروع/مستخدمين
  environment      text not null default 'all'
                     check (environment in ('all','development','staging','production')),
  starts_at        timestamptz,
  ends_at          timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.feature_flags is
  'مفاتيح تفعيل الميزات مع نسبة الطرح التدريجي وقواعد الاستهداف والبيئة.';

create index if not exists ix_feature_flags_enabled on public.feature_flags (is_enabled);
create index if not exists ix_feature_flags_env on public.feature_flags (environment);

drop trigger if exists trg_feature_flags_updated_at on public.feature_flags;
create trigger trg_feature_flags_updated_at
  before update on public.feature_flags
  for each row execute function public.set_updated_at();

alter table public.feature_flags enable row level security;

-- قراءة: أي مصادَق (يحتاجها العميل لتقرير عرض الميزات).
drop policy if exists feature_flags_select on public.feature_flags;
create policy feature_flags_select on public.feature_flags
  for select to authenticated
  using (true);

-- كتابة: full-access أو system.feature.manage.
drop policy if exists feature_flags_write on public.feature_flags;
create policy feature_flags_write on public.feature_flags
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('system.feature.manage'))
  with check (public.current_is_full_access() or public.has_permission('system.feature.manage'));

-- =====================================================================
-- Table: integrations  (تكاملات خارجية)
-- =====================================================================
create table if not exists public.integrations (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique,
  name_ar          text not null,
  provider         text not null,                  -- twilio, sendgrid, whatsapp, sap ...
  category         text not null default 'general'
                     check (category in ('general','sms','email','whatsapp','payment','erp','storage','sso','webhook','analytics')),
  status           text not null default 'inactive'
                     check (status in ('inactive','active','error','suspended')),
  config           jsonb not null default '{}'::jsonb, -- إعداد غير حسّاس (السرّ في credential_vault)
  vault_key_name   text references public.credential_vault(key_name) on delete set null,
  webhook_url      text,
  is_enabled       boolean not null default false,
  last_sync_at     timestamptz,
  last_error       text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.integrations is
  'تعريفات التكاملات الخارجية: المزوّد، الفئة، الحالة، الإعداد غير الحسّاس، ومرجع سرّ الخزنة.';

create index if not exists ix_integrations_provider on public.integrations (provider);
create index if not exists ix_integrations_category on public.integrations (category);
create index if not exists ix_integrations_status on public.integrations (status);

drop trigger if exists trg_integrations_updated_at on public.integrations;
create trigger trg_integrations_updated_at
  before update on public.integrations
  for each row execute function public.set_updated_at();

alter table public.integrations enable row level security;

drop policy if exists integrations_select on public.integrations;
create policy integrations_select on public.integrations
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['system.integration.view','system.integration.manage']));

drop policy if exists integrations_write on public.integrations;
create policy integrations_write on public.integrations
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('system.integration.manage'))
  with check (public.current_is_full_access() or public.has_permission('system.integration.manage'));

-- =====================================================================
-- Table: integration_logs  (سجلات نداءات التكامل)
-- =====================================================================
create table if not exists public.integration_logs (
  id               uuid primary key default gen_random_uuid(),
  integration_id   uuid references public.integrations(id) on delete cascade,
  direction        text not null default 'outbound'
                     check (direction in ('inbound','outbound')),
  operation        text,                            -- send_sms, sync_users, webhook ...
  status           text not null default 'pending'
                     check (status in ('pending','success','failed','retrying','skipped')),
  http_status      integer,
  request_payload  jsonb,
  response_payload jsonb,
  error_message    text,
  duration_ms      integer,
  correlation_id   text,
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.integration_logs is
  'سجلات نداءات التكاملات (وارد/صادر) مع الحمولة والحالة والمدة لأغراض التتبّع والتشخيص.';

create index if not exists ix_integration_logs_integration on public.integration_logs (integration_id);
create index if not exists ix_integration_logs_status on public.integration_logs (status);
create index if not exists ix_integration_logs_occurred on public.integration_logs (occurred_at desc);
create index if not exists ix_integration_logs_correlation on public.integration_logs (correlation_id);

alter table public.integration_logs enable row level security;

drop policy if exists integration_logs_select on public.integration_logs;
create policy integration_logs_select on public.integration_logs
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['system.integration.view','system.integration.manage']));

drop policy if exists integration_logs_write on public.integration_logs;
create policy integration_logs_write on public.integration_logs
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('system.integration.manage'))
  with check (public.current_is_full_access() or public.has_permission('system.integration.manage'));

-- =====================================================================
-- Table: live_location_requests  (طلبات الموقع الحيّ)
-- =====================================================================
create table if not exists public.live_location_requests (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.employees(id) on delete cascade,
  requested_by     uuid references public.employees(id) on delete set null,
  reason           text,
  status           text not null default 'pending'
                     check (status in ('pending','accepted','rejected','active','expired','cancelled','completed')),
  purpose          text not null default 'verification'
                     check (purpose in ('verification','attendance','safety','field_visit','other')),
  requested_at     timestamptz not null default now(),
  responded_at     timestamptz,
  starts_at        timestamptz,
  expires_at       timestamptz,
  duration_minutes integer,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.live_location_requests is
  'طلبات مشاركة الموقع الحيّ لموظف مع السبب والحالة والغرض ومدة الصلاحية.';

create index if not exists ix_live_loc_req_employee on public.live_location_requests (employee_id);
create index if not exists ix_live_loc_req_requestedby on public.live_location_requests (requested_by);
create index if not exists ix_live_loc_req_status on public.live_location_requests (status);
create index if not exists ix_live_loc_req_requested on public.live_location_requests (requested_at desc);

drop trigger if exists trg_live_loc_req_updated_at on public.live_location_requests;
create trigger trg_live_loc_req_updated_at
  before update on public.live_location_requests
  for each row execute function public.set_updated_at();

alter table public.live_location_requests enable row level security;

-- قراءة: full-access، صاحب الصلاحية، الموظف المعني، أو من يستطيع الوصول لهذا الموظف.
drop policy if exists live_loc_req_select on public.live_location_requests;
create policy live_loc_req_select on public.live_location_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
    or requested_by = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

-- إنشاء/إدارة الطلبات: full-access أو صاحب صلاحية location.request.manage.
drop policy if exists live_loc_req_write on public.live_location_requests;
create policy live_loc_req_write on public.live_location_requests
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('location.request.manage'))
  with check (public.current_is_full_access() or public.has_permission('location.request.manage'));

-- تحديث حالة الطلب من الموظف المعني (قبول/رفض) — نطاق ذاتي.
drop policy if exists live_loc_req_respond on public.live_location_requests;
create policy live_loc_req_respond on public.live_location_requests
  for update to authenticated
  using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());

-- =====================================================================
-- Table: live_location_videos_meta  (بيانات وصفية لفيديوهات الموقع الحيّ)
-- =====================================================================
create table if not exists public.live_location_videos_meta (
  id               uuid primary key default gen_random_uuid(),
  live_request_id  uuid references public.live_location_requests(id) on delete cascade,
  employee_id      uuid not null references public.employees(id) on delete cascade,
  storage_path     text,                            -- مسار الملف في التخزين (بدون المحتوى الخام)
  storage_bucket   text,
  duration_seconds integer,
  size_bytes       bigint,
  mime_type        text,
  captured_lat     double precision,
  captured_lng     double precision,
  captured_accuracy double precision,
  captured_at      timestamptz,
  thumbnail_path   text,
  status           text not null default 'uploaded'
                     check (status in ('pending','uploading','uploaded','processing','ready','failed','deleted')),
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.live_location_videos_meta is
  'بيانات وصفية لفيديوهات إثبات الموقع الحيّ (مسار/حجم/إحداثيات) — المحتوى في التخزين الخارجي.';

create index if not exists ix_live_vid_meta_request on public.live_location_videos_meta (live_request_id);
create index if not exists ix_live_vid_meta_employee on public.live_location_videos_meta (employee_id);
create index if not exists ix_live_vid_meta_status on public.live_location_videos_meta (status);
create index if not exists ix_live_vid_meta_captured on public.live_location_videos_meta (captured_at desc);

drop trigger if exists trg_live_vid_meta_updated_at on public.live_location_videos_meta;
create trigger trg_live_vid_meta_updated_at
  before update on public.live_location_videos_meta
  for each row execute function public.set_updated_at();

alter table public.live_location_videos_meta enable row level security;

drop policy if exists live_vid_meta_select on public.live_location_videos_meta;
create policy live_vid_meta_select on public.live_location_videos_meta
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

drop policy if exists live_vid_meta_write on public.live_location_videos_meta;
create policy live_vid_meta_write on public.live_location_videos_meta
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
  );

-- =====================================================================
-- Table: employee_locations  (نقاط موقع الموظفين — تتبّع)
-- =====================================================================
create table if not exists public.employee_locations (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.employees(id) on delete cascade,
  live_request_id  uuid references public.live_location_requests(id) on delete set null,
  latitude         double precision not null,
  longitude        double precision not null,
  accuracy         double precision,
  altitude         double precision,
  speed            double precision,
  heading          double precision,
  source           text not null default 'mobile'
                     check (source in ('mobile','web','device','manual','geofence')),
  battery_level    integer check (battery_level between 0 and 100),
  is_mock          boolean not null default false,
  recorded_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.employee_locations is
  'نقاط موقع الموظفين (إحداثيات/دقة/سرعة) للتتبّع الميداني — بيانات موقع حسّاسة.';

create index if not exists ix_emp_locations_employee on public.employee_locations (employee_id);
create index if not exists ix_emp_locations_request on public.employee_locations (live_request_id);
create index if not exists ix_emp_locations_recorded on public.employee_locations (recorded_at desc);
create index if not exists ix_emp_locations_emp_time on public.employee_locations (employee_id, recorded_at desc);

alter table public.employee_locations enable row level security;

-- قراءة: full-access، صاحب صلاحية الإدارة، الموظف نفسه، أو من يستطيع الوصول لهذا الموظف.
drop policy if exists emp_locations_select on public.employee_locations;
create policy emp_locations_select on public.employee_locations
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

-- كتابة نقاط الموقع: الموظف نفسه (تطبيقه)، أو full-access.
drop policy if exists emp_locations_insert on public.employee_locations;
create policy emp_locations_insert on public.employee_locations
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or employee_id = public.current_employee_id()
  );

drop policy if exists emp_locations_manage on public.employee_locations;
create policy emp_locations_manage on public.employee_locations
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('location.request.manage'))
  with check (public.current_is_full_access() or public.has_permission('location.request.manage'));

-- =====================================================================
-- Table: location_requests  (طلبات موقع عامة — لقطة/تحقق لمرة واحدة)
-- =====================================================================
create table if not exists public.location_requests (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.employees(id) on delete cascade,
  requested_by     uuid references public.employees(id) on delete set null,
  request_type     text not null default 'snapshot'
                     check (request_type in ('snapshot','check_in','verification','address_confirm')),
  status           text not null default 'pending'
                     check (status in ('pending','fulfilled','rejected','expired','cancelled')),
  reason           text,
  fulfilled_lat    double precision,
  fulfilled_lng    double precision,
  fulfilled_accuracy double precision,
  requested_at     timestamptz not null default now(),
  fulfilled_at     timestamptz,
  expires_at       timestamptz,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  created_by       uuid references auth.users(id)
);
comment on table public.location_requests is
  'طلبات موقع لمرة واحدة (لقطة/تحقق) لموظف مع الحالة والإحداثيات المُلبّاة وصلاحية الطلب.';

create index if not exists ix_location_req_employee on public.location_requests (employee_id);
create index if not exists ix_location_req_requestedby on public.location_requests (requested_by);
create index if not exists ix_location_req_status on public.location_requests (status);
create index if not exists ix_location_req_requested on public.location_requests (requested_at desc);

drop trigger if exists trg_location_req_updated_at on public.location_requests;
create trigger trg_location_req_updated_at
  before update on public.location_requests
  for each row execute function public.set_updated_at();

alter table public.location_requests enable row level security;

drop policy if exists location_req_select on public.location_requests;
create policy location_req_select on public.location_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('location.request.manage')
    or employee_id = public.current_employee_id()
    or requested_by = public.current_employee_id()
    or public.can_access_employee(employee_id)
  );

drop policy if exists location_req_write on public.location_requests;
create policy location_req_write on public.location_requests
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('location.request.manage'))
  with check (public.current_is_full_access() or public.has_permission('location.request.manage'));

drop policy if exists location_req_fulfill on public.location_requests;
create policy location_req_fulfill on public.location_requests
  for update to authenticated
  using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());

-- =====================================================================
-- RPC: log_audit_event  (الكتابة الوحيدة المسموح بها لجدول audit_events)
-- =====================================================================
create or replace function public.log_audit_event(
  p_event_type    text,
  p_category      text    default 'general',
  p_severity      text    default 'info',
  p_target_table  text    default null,
  p_target_id     uuid    default null,
  p_summary_ar    text    default null,
  p_description   text    default null,
  p_metadata      jsonb   default '{}'::jsonb
)
returns public.audit_events
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.audit_events;
begin
  if p_event_type is null or length(trim(p_event_type)) = 0 then
    raise exception 'event_type is required' using errcode = '22023';
  end if;

  if p_category not in ('general','access','data','workflow','security','system','integration') then
    p_category := 'general';
  end if;

  if p_severity not in ('debug','info','notice','warning','error','critical') then
    p_severity := 'info';
  end if;

  insert into public.audit_events
    (event_type, category, severity, actor_user_id, actor_employee_id,
     target_table, target_id, summary_ar, description, metadata, occurred_at, created_by)
  values
    (p_event_type, p_category, p_severity, auth.uid(), public.current_employee_id(),
     p_target_table, p_target_id, p_summary_ar, p_description,
     coalesce(p_metadata, '{}'::jsonb), now(), auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;
comment on function public.log_audit_event(text, text, text, text, uuid, text, text, jsonb) is
  'RPC: يكتب حدث تدقيق دلالي في audit_events (المسار الوحيد للكتابة). SECURITY DEFINER.';

revoke execute on function public.log_audit_event(text, text, text, text, uuid, text, text, jsonb) from public;
grant  execute on function public.log_audit_event(text, text, text, text, uuid, text, text, jsonb) to authenticated;

-- =====================================================================
-- RPC: log_security_event  (تسجيل حدث أمني موحّد)
-- =====================================================================
create or replace function public.log_security_event(
  p_event_type   text,
  p_severity     text    default 'medium',
  p_outcome      text    default 'detected',
  p_identifier   text    default null,
  p_details      jsonb   default '{}'::jsonb
)
returns public.security_events
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.security_events;
begin
  if p_event_type is null or length(trim(p_event_type)) = 0 then
    raise exception 'event_type is required' using errcode = '22023';
  end if;

  if p_severity not in ('low','medium','high','critical') then
    p_severity := 'medium';
  end if;

  if p_outcome not in ('detected','blocked','allowed','resolved','ignored') then
    p_outcome := 'detected';
  end if;

  insert into public.security_events
    (event_type, severity, outcome, user_id, employee_id, identifier, details, occurred_at, created_by)
  values
    (p_event_type, p_severity, p_outcome, auth.uid(), public.current_employee_id(),
     p_identifier, coalesce(p_details, '{}'::jsonb), now(), auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;
comment on function public.log_security_event(text, text, text, text, jsonb) is
  'RPC: يسجّل حدثاً أمنياً في security_events مع الخطورة والنتيجة. SECURITY DEFINER.';

revoke execute on function public.log_security_event(text, text, text, text, jsonb) from public;
grant  execute on function public.log_security_event(text, text, text, text, jsonb) to authenticated;

-- =====================================================================
-- نهاية Migration 0011
-- =====================================================================
