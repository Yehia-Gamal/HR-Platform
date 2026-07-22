-- Migration 0005: الحضور والورديات والهوية (Attendance, Shifts & Identity)
-- Ahla Shabab Management OS V2
-- تشغيل عبر: supabase db push  (immutable بعد التطبيق)
--
-- يعتمد على:
--   0001 extensions + tg_set_updated_at()/set_updated_at()
--   0002 دوال التخويل: current_is_full_access(), has_permission(text),
--        has_any_permission(text[]), can_access_employee(uuid), current_employee_id()
--   0003 geofences, shifts, work_sites
--   0004 employees, profiles
--
-- ملاحظات أمنية:
--   * الموظف لا يُدرج attendance_events مباشرة؛ الإدراج فقط عبر service_role أو
--     صلاحية attendance.record.manual_create (مشرف)، أو عبر RPC record_attendance_event
--     المُعرَّفة أدناه (SECURITY DEFINER).
--   * جداول الهوية/المخاطر server-authored: لا كتابة من authenticated.
--   * passkey_credentials: trigger يجبر trusted=false عند أي INSERT/UPDATE من العميل.
--   * webauthn_challenges: single-use عبر used_at + قيود.

-- =====================================================================
-- 0. دوال مساعدة (helpers)
-- =====================================================================

-- المسافة بالمتر بين نقطتين (Haversine) — immutable لاستعمالها في الفهارس/القيود
create or replace function public.geo_distance_meters(
  p_lat1 double precision,
  p_lon1 double precision,
  p_lat2 double precision,
  p_lon2 double precision
)
returns double precision
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_lat1 is null or p_lon1 is null or p_lat2 is null or p_lon2 is null
      then null
    else
      6371000.0 * 2.0 * asin( least(1.0, sqrt(
          power(sin(radians(p_lat2 - p_lat1) / 2.0), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lon2 - p_lon1) / 2.0), 2)
      )))
  end;
$$;
comment on function public.geo_distance_meters(double precision,double precision,double precision,double precision)
  is 'المسافة بالمتر بين نقطتين جغرافيتين بصيغة Haversine (نصف قطر الأرض 6371كم). immutable.';

-- حساب دقائق التأخير مقارنةً ببداية الوردية مع سماحية (grace)
create or replace function public.calculate_late_minutes(
  p_event_at   timestamptz,
  p_shift_start time,
  p_grace_minutes integer default 0,
  p_reference_date date default null
)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  -- نبني توقيت بداية الوردية بالـ UTC على أساس تاريخ الحدث (أو reference date)
  select greatest(
    0,
    (
      floor(
        extract(epoch from (
          (p_event_at at time zone 'utc')
          - ( (coalesce(p_reference_date, (p_event_at at time zone 'utc')::date))::timestamp + p_shift_start )
        )) / 60.0
      )::integer
    ) - coalesce(p_grace_minutes, 0)
  );
$$;
comment on function public.calculate_late_minutes(timestamptz,time,integer,date)
  is 'دقائق التأخير عن بداية الوردية (UTC) بعد خصم السماحية. صفر إن لم يتأخر. immutable.';

revoke execute on function public.geo_distance_meters(double precision,double precision,double precision,double precision) from public;
revoke execute on function public.calculate_late_minutes(timestamptz,time,integer,date) from public;
grant execute on function public.geo_distance_meters(double precision,double precision,double precision,double precision) to authenticated;
grant execute on function public.calculate_late_minutes(timestamptz,time,integer,date) to authenticated;

-- =====================================================================
-- 1. shift_assignments  (إسناد الورديات للموظفين)
-- =====================================================================
create table if not exists public.shift_assignments (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  shift_id          uuid not null references public.shifts(id) on delete restrict,
  work_site_id      uuid references public.work_sites(id) on delete set null,
  geofence_id       uuid references public.geofences(id) on delete set null,
  effective_from    date not null,
  effective_to      date,
  weekday_mask      integer,                         -- بت لكل يوم أسبوع (اختياري)
  is_active         boolean not null default true,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint shift_assignments_date_chk
    check (effective_to is null or effective_to >= effective_from),
  constraint shift_assignments_weekday_chk
    check (weekday_mask is null or weekday_mask between 0 and 127)
);
comment on table public.shift_assignments is
  'إسناد الورديات للموظفين مع نطاق سريان وموقع/نطاق جغرافي اختياري.';
create index if not exists idx_shift_assign_employee on public.shift_assignments(employee_id);
create index if not exists idx_shift_assign_shift    on public.shift_assignments(shift_id);
create index if not exists idx_shift_assign_active   on public.shift_assignments(is_active);
create index if not exists idx_shift_assign_effrange on public.shift_assignments(effective_from, effective_to);

drop trigger if exists trg_shift_assignments_updated_at on public.shift_assignments;
create trigger trg_shift_assignments_updated_at
  before update on public.shift_assignments
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 2. passkey_credentials  (اعتمادات WebAuthn / Passkeys)
-- =====================================================================
create table if not exists public.passkey_credentials (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  user_id           uuid references auth.users(id) on delete set null,
  credential_id     text not null,                   -- base64url من المتصفح
  public_key        text not null,                   -- COSE public key (base64url)
  sign_count        bigint not null default 0,
  transports        text[],                          -- usb/nfc/ble/internal/hybrid
  aaguid            text,
  device_label      text,
  status            text not null default 'active'
                      check (status in ('active','revoked','suspended')),
  trusted           boolean not null default false,  -- يُرفع من الخادم فقط
  last_used         timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint passkey_credentials_credid_key unique (credential_id)
);
comment on table public.passkey_credentials is
  'اعتمادات Passkey/WebAuthn للموظفين. trusted يُضبط من الخادم فقط عبر trigger.';
create index if not exists idx_passkey_cred_employee on public.passkey_credentials(employee_id);
create index if not exists idx_passkey_cred_user     on public.passkey_credentials(user_id);
create index if not exists idx_passkey_cred_status   on public.passkey_credentials(status);

drop trigger if exists trg_passkey_credentials_updated_at on public.passkey_credentials;
create trigger trg_passkey_credentials_updated_at
  before update on public.passkey_credentials
  for each row execute function public.tg_set_updated_at();

-- trigger: يجبر trusted=false ما لم يكن الفاعل service_role/postgres
create or replace function public.passkey_credentials_force_untrusted()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := current_setting('request.jwt.claims', true);
  v_is_service boolean := false;
begin
  -- service_role عبر PostgREST يحمل role=service_role ضمن JWT claims،
  -- أو الاتصال المباشر بأدوار postgres/service_role.
  if v_role is not null and position('"role":"service_role"' in v_role) > 0 then
    v_is_service := true;
  end if;
  if current_user in ('service_role','postgres','supabase_admin') then
    v_is_service := true;
  end if;

  if not v_is_service then
    new.trusted := false;
  end if;
  return new;
end;
$$;
comment on function public.passkey_credentials_force_untrusted()
  is 'يمنع رفع trusted من العميل؛ فقط الخادم/service_role يضبط trusted=true.';

drop trigger if exists trg_passkey_force_untrusted on public.passkey_credentials;
create trigger trg_passkey_force_untrusted
  before insert or update on public.passkey_credentials
  for each row execute function public.passkey_credentials_force_untrusted();

-- =====================================================================
-- 3. webauthn_challenges  (تحديات WebAuthn — single-use)
-- =====================================================================
create table if not exists public.webauthn_challenges (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid references public.employees(id) on delete cascade,
  user_id           uuid references auth.users(id) on delete set null,
  challenge         text not null,                   -- base64url random
  type              text not null check (type in ('register','auth')),
  expires_at        timestamptz not null,
  used_at           timestamptz,                     -- single-use: يُملأ مرة واحدة
  ip_address        inet,
  user_agent        text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint webauthn_challenges_challenge_key unique (challenge),
  constraint webauthn_challenges_expiry_chk check (expires_at > created_at)
);
comment on table public.webauthn_challenges is
  'تحديات WebAuthn للتسجيل/المصادقة. تُستهلك مرة واحدة عبر used_at ولها expires_at.';
create index if not exists idx_webauthn_ch_employee on public.webauthn_challenges(employee_id);
create index if not exists idx_webauthn_ch_type     on public.webauthn_challenges(type);
create index if not exists idx_webauthn_ch_expires  on public.webauthn_challenges(expires_at);
create index if not exists idx_webauthn_ch_unused   on public.webauthn_challenges(used_at) where used_at is null;

drop trigger if exists trg_webauthn_challenges_updated_at on public.webauthn_challenges;
create trigger trg_webauthn_challenges_updated_at
  before update on public.webauthn_challenges
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 4. attendance_events  (أحداث الحضور/الانصراف الخام)
-- =====================================================================
create table if not exists public.attendance_events (
  id                    uuid primary key default gen_random_uuid(),
  employee_id           uuid not null references public.employees(id) on delete cascade,
  shift_assignment_id   uuid references public.shift_assignments(id) on delete set null,
  geofence_id           uuid references public.geofences(id) on delete set null,
  event_type            text not null check (event_type in ('CHECK_IN','CHECK_OUT')),
  event_at              timestamptz not null default now(),
  latitude              double precision,
  longitude             double precision,
  accuracy_meters       numeric(10,2),
  distance_meters       numeric(12,2),               -- المسافة المحسوبة عن مركز النطاق
  status                text not null default 'pending'
                          check (status in ('pending','accepted','rejected','flagged','adjusted')),
  late_minutes          integer not null default 0,
  requires_review       boolean not null default false,
  verification_status   text not null default 'unverified'
                          check (verification_status in ('unverified','passkey_verified','biometric_verified','failed')),
  passkey_credential_id uuid references public.passkey_credentials(id) on delete set null,
  biometric_method      text check (biometric_method in ('face','fingerprint','passkey','none')),
  selfie_path           text,                        -- مسار داخل storage
  server_verified       boolean not null default false,
  source                text not null default 'mobile'
                          check (source in ('mobile','web','kiosk','service','import')),
  device_id             text,
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  constraint attendance_events_lat_chk check (latitude is null or latitude between -90 and 90),
  constraint attendance_events_lon_chk check (longitude is null or longitude between -180 and 180),
  constraint attendance_events_accuracy_chk check (accuracy_meters is null or accuracy_meters >= 0),
  constraint attendance_events_late_chk check (late_minutes >= 0)
);
comment on table public.attendance_events is
  'أحداث الحضور/الانصراف الخام. لا إدراج مباشر من الموظف؛ فقط service أو صلاحية attendance.record.manual_create أو RPC record_attendance_event.';
create index if not exists idx_att_events_employee   on public.attendance_events(employee_id);
create index if not exists idx_att_events_event_at   on public.attendance_events(event_at);
create index if not exists idx_att_events_status     on public.attendance_events(status);
create index if not exists idx_att_events_review     on public.attendance_events(requires_review) where requires_review = true;
create index if not exists idx_att_events_emp_day    on public.attendance_events(employee_id, event_at);

drop trigger if exists trg_attendance_events_updated_at on public.attendance_events;
create trigger trg_attendance_events_updated_at
  before update on public.attendance_events
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 5. attendance_daily  (تجميع يومي محسوب من الأحداث)
-- =====================================================================
create table if not exists public.attendance_daily (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  work_date         date not null,
  shift_id          uuid references public.shifts(id) on delete set null,
  first_check_in    timestamptz,
  last_check_out    timestamptz,
  work_minutes      integer not null default 0,
  late_minutes      integer not null default 0,
  early_leave_minutes integer not null default 0,
  overtime_minutes  integer not null default 0,
  status            text not null default 'absent'
                      check (status in ('present','absent','late','on_leave','holiday','weekend','partial','pending')),
  is_finalized      boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint attendance_daily_uq unique (employee_id, work_date),
  constraint attendance_daily_work_chk check (work_minutes >= 0),
  constraint attendance_daily_late_chk check (late_minutes >= 0),
  constraint attendance_daily_early_chk check (early_leave_minutes >= 0),
  constraint attendance_daily_ot_chk check (overtime_minutes >= 0)
);
comment on table public.attendance_daily is
  'التجميع اليومي لحضور الموظف (دقائق العمل/التأخير/الحالة) محسوب من الأحداث. server-authored.';
create index if not exists idx_att_daily_employee on public.attendance_daily(employee_id);
create index if not exists idx_att_daily_date     on public.attendance_daily(work_date);
create index if not exists idx_att_daily_status   on public.attendance_daily(status);

drop trigger if exists trg_attendance_daily_updated_at on public.attendance_daily;
create trigger trg_attendance_daily_updated_at
  before update on public.attendance_daily
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 6. attendance_identity_checks  (فحوص الهوية — server-authored)
-- =====================================================================
create table if not exists public.attendance_identity_checks (
  id                    uuid primary key default gen_random_uuid(),
  attendance_event_id   uuid references public.attendance_events(id) on delete cascade,
  employee_id           uuid not null references public.employees(id) on delete cascade,
  method                text not null default 'none'
                          check (method in ('face','fingerprint','passkey','liveness','manual','none')),
  passkey_credential_id uuid references public.passkey_credentials(id) on delete set null,
  risk_score            numeric(5,2) not null default 0,   -- 0..100
  risk_level            text not null default 'low'
                          check (risk_level in ('low','medium','high','critical')),
  flags                 jsonb not null default '[]'::jsonb, -- قائمة إشارات الخطر
  requires_review       boolean not null default false,
  passed                boolean not null default false,
  checked_at            timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id),
  constraint att_identity_score_chk check (risk_score >= 0 and risk_score <= 100)
);
comment on table public.attendance_identity_checks is
  'نتائج فحص هوية الحضور (درجة الخطر/المستوى/الإشارات). تُكتب من الخادم فقط (server-authored).';
create index if not exists idx_att_idcheck_event    on public.attendance_identity_checks(attendance_event_id);
create index if not exists idx_att_idcheck_employee on public.attendance_identity_checks(employee_id);
create index if not exists idx_att_idcheck_level    on public.attendance_identity_checks(risk_level);
create index if not exists idx_att_idcheck_review   on public.attendance_identity_checks(requires_review) where requires_review = true;
create index if not exists idx_att_idcheck_flags    on public.attendance_identity_checks using gin (flags);

drop trigger if exists trg_att_identity_checks_updated_at on public.attendance_identity_checks;
create trigger trg_att_identity_checks_updated_at
  before update on public.attendance_identity_checks
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 7. attendance_risk_events  (سجل أحداث المخاطر — server-authored)
-- =====================================================================
create table if not exists public.attendance_risk_events (
  id                    uuid primary key default gen_random_uuid(),
  attendance_event_id   uuid references public.attendance_events(id) on delete cascade,
  identity_check_id     uuid references public.attendance_identity_checks(id) on delete set null,
  employee_id           uuid references public.employees(id) on delete cascade,
  risk_type             text not null,               -- geo_mismatch/spoofed_gps/duplicate/impossible_travel...
  risk_level            text not null default 'low'
                          check (risk_level in ('low','medium','high','critical')),
  detail                jsonb not null default '{}'::jsonb,
  resolved              boolean not null default false,
  resolved_by           uuid references auth.users(id),
  resolved_at           timestamptz,
  detected_at           timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  created_by            uuid references auth.users(id)
);
comment on table public.attendance_risk_events is
  'سجل أحداث المخاطر المكتشفة أثناء الحضور (نوع/مستوى/تفاصيل). server-authored؛ التسوية بصلاحية.';
create index if not exists idx_att_risk_event    on public.attendance_risk_events(attendance_event_id);
create index if not exists idx_att_risk_employee on public.attendance_risk_events(employee_id);
create index if not exists idx_att_risk_level    on public.attendance_risk_events(risk_level);
create index if not exists idx_att_risk_open     on public.attendance_risk_events(resolved) where resolved = false;

drop trigger if exists trg_att_risk_events_updated_at on public.attendance_risk_events;
create trigger trg_att_risk_events_updated_at
  before update on public.attendance_risk_events
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 8. attendance_exceptions  (استثناءات/تسويات الحضور)
-- =====================================================================
create table if not exists public.attendance_exceptions (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  attendance_daily_id uuid references public.attendance_daily(id) on delete set null,
  attendance_event_id uuid references public.attendance_events(id) on delete set null,
  work_date         date,
  kind              text not null
                      check (kind in ('missing_check_in','missing_check_out','late','early_leave',
                                      'geo_violation','manual_adjustment','duplicate','other')),
  description       text,
  minutes_adjustment integer not null default 0,
  status            text not null default 'open'
                      check (status in ('open','approved','rejected','resolved')),
  reviewed_by       uuid references auth.users(id),
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id)
);
comment on table public.attendance_exceptions is
  'استثناءات وتسويات الحضور (نقص بصمة/تأخير/تعديل يدوي) وحالتها ومراجعتها.';
create index if not exists idx_att_exc_employee on public.attendance_exceptions(employee_id);
create index if not exists idx_att_exc_status   on public.attendance_exceptions(status);
create index if not exists idx_att_exc_date     on public.attendance_exceptions(work_date);
create index if not exists idx_att_exc_kind     on public.attendance_exceptions(kind);

drop trigger if exists trg_att_exceptions_updated_at on public.attendance_exceptions;
create trigger trg_att_exceptions_updated_at
  before update on public.attendance_exceptions
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 9. attendance_permits  (أذونات الحضور/الانصراف)
-- =====================================================================
create table if not exists public.attendance_permits (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  kind              text not null check (kind in ('arrival','departure')),
  permit_date       date not null,
  from_time         time,
  to_time           time,
  grace_minutes     integer not null default 0,
  reason            text,
  status            text not null default 'pending'
                      check (status in ('pending','approved','rejected','cancelled')),
  approved_by       uuid references auth.users(id),
  approved_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id),
  constraint att_permit_grace_chk check (grace_minutes >= 0),
  constraint att_permit_time_chk  check (from_time is null or to_time is null or to_time >= from_time)
);
comment on table public.attendance_permits is
  'أذونات التأخير في الوصول أو الانصراف المبكر مع سماحية دقائق وحالة اعتماد.';
create index if not exists idx_att_permit_employee on public.attendance_permits(employee_id);
create index if not exists idx_att_permit_date     on public.attendance_permits(permit_date);
create index if not exists idx_att_permit_status   on public.attendance_permits(status);
create index if not exists idx_att_permit_kind     on public.attendance_permits(kind);

drop trigger if exists trg_att_permits_updated_at on public.attendance_permits;
create trigger trg_att_permits_updated_at
  before update on public.attendance_permits
  for each row execute function public.tg_set_updated_at();

-- =====================================================================
-- 10. تفعيل RLS على كل الجداول
-- =====================================================================
alter table public.shift_assignments          enable row level security;
alter table public.passkey_credentials         enable row level security;
alter table public.webauthn_challenges          enable row level security;
alter table public.attendance_events            enable row level security;
alter table public.attendance_daily             enable row level security;
alter table public.attendance_identity_checks   enable row level security;
alter table public.attendance_risk_events        enable row level security;
alter table public.attendance_exceptions         enable row level security;
alter table public.attendance_permits            enable row level security;

-- =====================================================================
-- 11. سياسات RLS
-- =====================================================================

-- ---- shift_assignments ----
-- قراءة: full-access أو صلاحية عرض الحضور أو الموظف صاحب الإسناد
create policy shift_assign_read on public.shift_assignments
  for select to authenticated
  using (
    public.has_permission('attendance.shift.read')
    or public.can_access_employee(employee_id)
  );
-- كتابة: صلاحية إدارة الورديات فقط
create policy shift_assign_write on public.shift_assignments
  for all to authenticated
  using (public.has_any_permission(array['attendance.shift.manage','attendance.shift.assign']))
  with check (public.has_any_permission(array['attendance.shift.manage','attendance.shift.assign']));

-- ---- passkey_credentials ----
-- قراءة: صاحب الاعتماد (موظفه) أو صلاحية إدارة الهوية
create policy passkey_cred_read on public.passkey_credentials
  for select to authenticated
  using (
    public.has_permission('attendance.identity.manage')
    or public.can_access_employee(employee_id)
  );
-- إدراج: الموظف يسجّل passkey لنفسه، أو مخوّل الهوية (trusted يُجبَر false عبر trigger)
create policy passkey_cred_insert on public.passkey_credentials
  for insert to authenticated
  with check (
    public.has_permission('attendance.identity.manage')
    or employee_id = public.current_employee_id()
  );
-- تحديث: الموظف يحدّث اعتماداته (label/status محدود)، أو مخوّل الهوية
create policy passkey_cred_update on public.passkey_credentials
  for update to authenticated
  using (
    public.has_permission('attendance.identity.manage')
    or employee_id = public.current_employee_id()
  )
  with check (
    public.has_permission('attendance.identity.manage')
    or employee_id = public.current_employee_id()
  );
-- حذف: مخوّل الهوية فقط
create policy passkey_cred_delete on public.passkey_credentials
  for delete to authenticated
  using (public.has_permission('attendance.identity.manage'));

-- ---- webauthn_challenges ----
-- قراءة: صاحب التحدي أو مخوّل الهوية (التحقق الفعلي عبر RPC/service)
create policy webauthn_ch_read on public.webauthn_challenges
  for select to authenticated
  using (
    public.has_permission('attendance.identity.manage')
    or employee_id = public.current_employee_id()
  );
-- إدراج: الموظف ينشئ تحدياً لنفسه أو مخوّل الهوية
create policy webauthn_ch_insert on public.webauthn_challenges
  for insert to authenticated
  with check (
    public.has_permission('attendance.identity.manage')
    or employee_id = public.current_employee_id()
  );
-- تحديث/حذف: مخوّل الهوية فقط (الاستهلاك single-use يتم من الخادم)
create policy webauthn_ch_manage on public.webauthn_challenges
  for update to authenticated
  using (public.has_permission('attendance.identity.manage'))
  with check (public.has_permission('attendance.identity.manage'));
create policy webauthn_ch_delete on public.webauthn_challenges
  for delete to authenticated
  using (public.has_permission('attendance.identity.manage'));

-- ---- attendance_events ----
-- قراءة: مخوّل قراءة الحضور أو الموظف نفسه
create policy att_events_read on public.attendance_events
  for select to authenticated
  using (
    public.has_permission('attendance.record.read')
    or public.can_access_employee(employee_id)
  );
-- إدراج: فقط بصلاحية manual_create (الموظف يدخل عبر RPC SECURITY DEFINER، وservice عبر service_role يتجاوز RLS)
create policy att_events_insert on public.attendance_events
  for insert to authenticated
  with check (public.has_permission('attendance.record.manual_create'));
-- تحديث: تصحيح/مراجعة بصلاحية
create policy att_events_update on public.attendance_events
  for update to authenticated
  using (public.has_any_permission(array['attendance.record.manual_create','attendance.record.review']))
  with check (public.has_any_permission(array['attendance.record.manual_create','attendance.record.review']));
-- حذف: مخوّل المراجعة فقط
create policy att_events_delete on public.attendance_events
  for delete to authenticated
  using (public.has_permission('attendance.record.review'));

-- ---- attendance_daily ----
-- قراءة: مخوّل أو الموظف نفسه
create policy att_daily_read on public.attendance_daily
  for select to authenticated
  using (
    public.has_permission('attendance.record.read')
    or public.can_access_employee(employee_id)
  );
-- كتابة: server-authored — بصلاحية معالجة الحضور فقط (service_role يتجاوز)
create policy att_daily_write on public.attendance_daily
  for all to authenticated
  using (public.has_any_permission(array['attendance.record.process','attendance.record.review']))
  with check (public.has_any_permission(array['attendance.record.process','attendance.record.review']));

-- ---- attendance_identity_checks (server-authored) ----
create policy att_idcheck_read on public.attendance_identity_checks
  for select to authenticated
  using (
    public.has_permission('attendance.identity.read')
    or public.can_access_employee(employee_id)
  );
-- كتابة: مخوّل إدارة الهوية فقط (لا كتابة من الموظف)
create policy att_idcheck_write on public.attendance_identity_checks
  for all to authenticated
  using (public.has_permission('attendance.identity.manage'))
  with check (public.has_permission('attendance.identity.manage'));

-- ---- attendance_risk_events (server-authored) ----
create policy att_risk_read on public.attendance_risk_events
  for select to authenticated
  using (
    public.has_permission('attendance.risk.read')
    or (employee_id is not null and public.can_access_employee(employee_id))
  );
-- كتابة/تسوية: مخوّل المخاطر فقط
create policy att_risk_write on public.attendance_risk_events
  for all to authenticated
  using (public.has_permission('attendance.risk.manage'))
  with check (public.has_permission('attendance.risk.manage'));

-- ---- attendance_exceptions ----
create policy att_exc_read on public.attendance_exceptions
  for select to authenticated
  using (
    public.has_permission('attendance.exception.read')
    or public.can_access_employee(employee_id)
  );
-- كتابة: مخوّل معالجة الاستثناءات
create policy att_exc_write on public.attendance_exceptions
  for all to authenticated
  using (public.has_any_permission(array['attendance.exception.manage','attendance.record.review']))
  with check (public.has_any_permission(array['attendance.exception.manage','attendance.record.review']));

-- ---- attendance_permits ----
-- قراءة: مخوّل أو الموظف نفسه
create policy att_permit_read on public.attendance_permits
  for select to authenticated
  using (
    public.has_permission('attendance.permit.read')
    or public.can_access_employee(employee_id)
  );
-- إدراج: الموظف يطلب لنفسه، أو مخوّل الأذونات
create policy att_permit_insert on public.attendance_permits
  for insert to authenticated
  with check (
    public.has_permission('attendance.permit.manage')
    or employee_id = public.current_employee_id()
  );
-- تحديث: اعتماد/رفض بصلاحية، أو الموظف يعدّل طلبه ما دام pending
create policy att_permit_update on public.attendance_permits
  for update to authenticated
  using (
    public.has_permission('attendance.permit.manage')
    or (employee_id = public.current_employee_id() and status = 'pending')
  )
  with check (
    public.has_permission('attendance.permit.manage')
    or (employee_id = public.current_employee_id() and status = 'pending')
  );
-- حذف: مخوّل الأذونات فقط
create policy att_permit_delete on public.attendance_permits
  for delete to authenticated
  using (public.has_permission('attendance.permit.manage'));

-- =====================================================================
-- 12. RPC: record_attendance_event  (المسار الوحيد لتسجيل الموظف حضوره)
-- =====================================================================
-- الموظف لا يُدرج في attendance_events مباشرة؛ يستدعي هذه الدالة التي تُدرج
-- نيابةً عنه بعد التحقق من هويته وحساب المسافة والتأخير مبدئياً (server-side).
-- ⚠️ إعادة تصميم أمني (P0): هذه الدالة server-authored بالكامل و**غير متاحة لـauthenticated**.
-- تُستدعى فقط من Edge Function موثوقة (verify-attendance-punch) عبر service_role،
-- بعد أن تتحقق الـEdge Function من WebAuthn assertion + challenge بالكامل.
-- ضمانات:
--   * وقت الحدث من الخادم فقط (now()) — لا يُقبل وقت من العميل.
--   * p_employee_id يُمرَّر من الخادم بعد استخراجه من الـJWT المُتحقَّق منه (لا من العميل).
--   * الـgeofence يُشتق من إسناد الموظف — لا يختار العميل أي geofence.
--   * p_verified يأتي من الـEdge Function بعد نجاح التحقق؛ server_verified يُضبط تبعاً له فقط.
--   * منع التكرار/Replay عبر نافذة زمنية + فحص آخر حدث.
--   * التاريخ التشغيلي بتوقيت Africa/Cairo لتحديد يوم الوردية.
create or replace function public.record_attendance_event(
  p_employee_id       uuid,                 -- من الخادم بعد التحقق من الهوية
  p_event_type        text,
  p_latitude          double precision,
  p_longitude         double precision,
  p_accuracy_meters   numeric,
  p_biometric_method  text,
  p_selfie_path       text,
  p_passkey_credential_id uuid,
  p_verified          boolean               -- نتيجة تحقق الـEdge Function (WebAuthn)
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id    uuid;
  v_geofence    public.geofences%rowtype;
  v_assignment  public.shift_assignments%rowtype;
  v_shift       public.shifts%rowtype;
  v_distance    numeric(12,2);
  v_requires_review boolean := false;
  v_late        integer := 0;
  v_now         timestamptz := now();                       -- وقت الخادم فقط
  v_op_date     date := (v_now at time zone 'Africa/Cairo')::date;  -- يوم الوردية بتوقيت القاهرة
  v_verif       text;
begin
  -- 0) الاستدعاء محصور بـservice_role (الـEdge الموثوقة). يمنع الاستدعاء المباشر من العميل.
  if coalesce(current_setting('request.jwt.claim.role', true),
              current_setting('role', true), current_user) not in ('service_role','postgres','supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'record_attendance_event may only be called by the trusted server (service_role)'
      using errcode = '42501';
  end if;

  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid event_type: %', p_event_type using errcode = '22023';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id required' using errcode = '22023';
  end if;

  -- 1) التحقق من ملكية الـpasskey (إن مُرّر): يخص الموظف وفعّال وموثوق
  if p_passkey_credential_id is not null then
    if not exists (
      select 1 from public.passkey_credentials pc
      where pc.id = p_passkey_credential_id
        and pc.employee_id = p_employee_id
        and pc.status = 'active'
    ) then
      raise exception 'invalid passkey credential' using errcode = '28000';
    end if;
  end if;
  v_verif := case when p_verified then 'server_verified' else 'unverified' end;

  -- 2) منع التكرار/Replay: لا حدثان بنفس النوع خلال 60 ثانية
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate attendance event within window' using errcode = '23505';
  end if;

  -- 3) إسناد الوردية الفعّال لليوم (بتوقيت القاهرة)
  select * into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_op_date
    and (sa.effective_to is null or sa.effective_to >= v_op_date)
  order by sa.effective_from desc
  limit 1;

  -- 4) الـgeofence من إسناد الموظف فقط (لا اختيار من العميل)
  if v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences where id = v_assignment.geofence_id;
  end if;

  -- 5) المسافة والمراجعة الجغرافية
  if v_geofence.id is not null and p_latitude is not null and p_longitude is not null then
    v_distance := public.geo_distance_meters(
      p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
    )::numeric(12,2);
    if v_distance > v_geofence.radius_meters then v_requires_review := true; end if;
    if v_geofence.max_accuracy is not null and p_accuracy_meters is not null
       and p_accuracy_meters > v_geofence.max_accuracy then v_requires_review := true; end if;
  else
    v_requires_review := true;   -- بلا موقع مؤكد => مراجعة
  end if;

  -- أي عملية غير مُتحقَّق منها بالكامل => مراجعة إلزامية
  if not p_verified then v_requires_review := true; end if;

  -- 6) التأخير عند الدخول
  if p_event_type = 'CHECK_IN' and v_assignment.shift_id is not null then
    select * into v_shift from public.shifts where id = v_assignment.shift_id;
    if v_shift.id is not null then
      v_late := public.calculate_late_minutes(v_now, v_shift.start_time, v_shift.grace_in_minutes, v_op_date);
    end if;
  end if;

  insert into public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    source, created_by
  ) values (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance,
    case when v_requires_review then 'flagged' else 'pending' end,
    coalesce(v_late, 0), v_requires_review, v_verif,
    p_passkey_credential_id, coalesce(p_biometric_method,'none'), p_selfie_path,
    p_verified,                       -- server_verified = نتيجة التحقق الفعلي فقط
    'mobile', null
  )
  returning id into v_event_id;

  if p_passkey_credential_id is not null then
    update public.passkey_credentials set last_used = v_now where id = p_passkey_credential_id;
  end if;

  return v_event_id;
end;
$$;
comment on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean)
  is 'server-authored: تُستدعى فقط من Edge Function عبر service_role بعد تحقق WebAuthn. الوقت والgeofence من الخادم، ومنع Replay، وserver_verified=نتيجة التحقق الفعلي.';

-- ⚠️ لا grant لـauthenticated: الاستدعاء عبر service_role (Edge Function) فقط.
revoke execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean) from public;
revoke execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean) from authenticated;

-- =====================================================================
-- نهاية Migration 0005
-- =====================================================================
