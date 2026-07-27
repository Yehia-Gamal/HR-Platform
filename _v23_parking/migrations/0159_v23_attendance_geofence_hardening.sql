-- 0159: V23 §4 — تقوية الحضور والسياج الجغرافي
-- Night-shift work_date fix, period-based event lookups, attendance_settings
-- singleton, missing-checkout finalization, geofence audit trigger.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم أ: جدول attendance_settings (singleton) — إعدادات مركزية
-- Section A: attendance_settings singleton table — centralised settings
-- ═══════════════════════════════════════════════════════════════════════════════

create table if not exists public.attendance_settings (
  singleton_key  boolean primary key default true
                   check (singleton_key = true),          -- صف واحد فقط
  geofence_radius_default_meters  integer  not null default 300
                   check (geofence_radius_default_meters between 50 and 5000),
  location_age_max_seconds        integer  not null default 15
                   check (location_age_max_seconds between 5 and 120),
  accuracy_max_default_meters     integer  not null default 100
                   check (accuracy_max_default_meters between 10 and 1000),
  missing_checkout_grace_minutes  integer  not null default 60
                   check (missing_checkout_grace_minutes between 15 and 480),
  impossible_travel_speed_mps     integer  not null default 42
                   check (impossible_travel_speed_mps between 10 and 200),
  timezone                        text     not null default 'Africa/Cairo',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);

comment on table public.attendance_settings is
  'V23 §4: إعدادات الحضور المركزية (singleton). المصدر الوحيد للحقيقة لعتبات السياج والحضور.';

-- Seed the singleton row
insert into public.attendance_settings (singleton_key)
values (true)
on conflict (singleton_key) do nothing;

-- updated_at trigger
drop trigger if exists trg_attendance_settings_updated_at on public.attendance_settings;
create trigger trg_attendance_settings_updated_at
  before update on public.attendance_settings
  for each row execute function public.tg_set_updated_at();

-- RLS: authenticated reads, full-access writes
alter table public.attendance_settings enable row level security;

create policy att_settings_read on public.attendance_settings
  for select to authenticated using (true);

create policy att_settings_write on public.attendance_settings
  for all to authenticated using (public.current_is_full_access());


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ب: إضافة 'missing_checkout' إلى قيد attendance_daily.status
-- Section B: Add 'missing_checkout' to attendance_daily.status CHECK constraint
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_con text;
begin
  select conname into v_con
  from pg_constraint
  where conrelid = 'public.attendance_daily'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%status%'
    and pg_get_constraintdef(oid) not like '%work_minutes%'
    and pg_get_constraintdef(oid) not like '%late_minutes%';

  if v_con is not null then
    execute format('alter table public.attendance_daily drop constraint %I', v_con);
  end if;
end $$;

alter table public.attendance_daily
  add constraint attendance_daily_status_check
  check (status in (
    'present','absent','late','on_leave','holiday',
    'weekend','partial','pending','missing_checkout'
  ));


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ج: record_attendance_event — إصلاح الوردية الليلية + فترات زمنية
-- Section C: record_attendance_event — night shift fix + period-based lookups
--
-- التغييرات الجوهرية:
--   1) قراءة الإعدادات من attendance_settings
--   2) كشف الوردية الليلية: إذا التوقيت المحلي < 12:00 والأمس وردية ليلية
--      بها حضور مفتوح → v_work_date يُنقص يوماً
--   3) حدود الفترة (period boundaries) بدل المقارنة بالتاريخ
--   4) سلسلة احتياط الدقة: geofence.max_accuracy → settings → 100
--   5) عتبة السرعة المستحيلة من الإعدادات
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.record_attendance_event(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_biometric_method text default 'passkey',
  p_selfie_path text default null,
  p_passkey_credential_id uuid default null,
  p_verified boolean default false,
  p_is_mock boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- حارس الانتقال المستحيل
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
  -- V23: متغيرات جديدة
  v_settings public.attendance_settings%rowtype;
  v_tz text;
  v_local_time time;
  v_prev_crosses boolean;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_max_accuracy numeric(10,2);
  v_is_night_shift boolean := false;
begin
  -- ── 0) الإعدادات ─────────────────────────────────────────────────────────
  select * into v_settings from public.attendance_settings limit 1;
  v_tz := coalesce(v_settings.timezone, 'Africa/Cairo');
  v_work_date := (v_now at time zone v_tz)::date;
  v_local_time := (v_now at time zone v_tz)::time;

  -- ── 1) حراسة الصلاحيات ───────────────────────────────────────────────────
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- ── 2) التحقق من المدخلات ────────────────────────────────────────────────
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_employee_id is null or not p_verified then
    raise exception 'attendance_identity_not_verified' using errcode = '28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;

  -- ── 3) فحص الـ passkey ───────────────────────────────────────────────────
  if p_passkey_credential_id is null or not exists (
    select 1
    from public.passkey_credentials pc
    where pc.id = p_passkey_credential_id
      and pc.employee_id = p_employee_id
      and pc.status = 'active'
      and pc.trusted = true
  ) then
    raise exception 'attendance_passkey_not_trusted' using errcode = '28000';
  end if;

  -- ── 4) كشف الوردية الليلية (V23) ────────────────────────────────────────
  -- إذا الوقت المحلي < 12:00، قد نكون في صباح وردية ليلية بدأت أمس.
  -- نتحقق: هل أمس كان هناك وردية ليلية (crosses_midnight) مع حضور مفتوح؟
  if v_local_time < '12:00:00'::time then
    -- جرّب الجدول المنشور أولاً
    select true into v_prev_crosses
    from public.roster_days rd
    join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
    join public.shifts s on s.id = rd.shift_id
    where rd.employee_id = p_employee_id
      and rd.work_date = v_work_date - 1
      and rd.day_status = 'scheduled'
      and s.crosses_midnight = true
    limit 1;

    if v_prev_crosses is null then
      select true into v_prev_crosses
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
      where sa.employee_id = p_employee_id
        and sa.is_active = true
        and sa.effective_from <= v_work_date - 1
        and (sa.effective_to is null or sa.effective_to >= v_work_date - 1)
        and s.crosses_midnight = true
      limit 1;
    end if;

    -- إذا وُجدت وردية ليلية بالأمس وهناك حضور مفتوح ← ننقص v_work_date
    if v_prev_crosses and exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id
        and ad.work_date = v_work_date - 1
        and ad.first_check_in is not null
        and ad.last_check_out is null
        and ad.is_finalized = false
        and ad.status not in ('missing_checkout', 'on_leave', 'holiday', 'weekend')
    ) then
      v_work_date := v_work_date - 1;
      v_is_night_shift := true;
    end if;
  end if;

  -- ── 5) حراسة التكرار (60 ثانية) ─────────────────────────────────────────
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- ── 6) حراسة الإقفال ─────────────────────────────────────────────────────
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- ── 7) بحث الجدول/التعيين + السياج + الوردية ─────────────────────────────
  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
    and rd.day_status = 'scheduled'
  order by wr.published_at desc nulls last
  limit 1;

  select * into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_work_date
    and (sa.effective_to is null or sa.effective_to >= v_work_date)
  order by sa.effective_from desc
  limit 1;

  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode = '55000';
  end if;

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- ── 8) حدود الفترة الزمنية (V23) ────────────────────────────────────────
  if v_shift.id is not null and v_shift.crosses_midnight then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := ((v_work_date + 1)::date)::timestamp at time zone v_tz;
  end if;

  -- ── 9) حراسة التسلسل (CHECK_IN ↔ CHECK_OUT) ─────────────────────────────
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at <  v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;

  if p_event_type = 'CHECK_OUT'
     and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  -- ── 10) حارس الانتقال المستحيل ───────────────────────────────────────────
  select ae.event_at, ae.latitude, ae.longitude
    into v_prev_at, v_prev_lat, v_prev_lon
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.latitude is not null and ae.longitude is not null
    and ae.event_at > v_now - interval '6 hours'
  order by ae.event_at desc
  limit 1;

  if v_prev_at is not null then
    v_gap_seconds := greatest(extract(epoch from (v_now - v_prev_at)), 1);
    v_travel := public.geo_distance_meters(
      p_latitude, p_longitude, v_prev_lat, v_prev_lon
    );
    if v_travel is not null
       and (v_travel / v_gap_seconds) > coalesce(v_settings.impossible_travel_speed_mps, 42) then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- ── 11) فحص السياج الجغرافي ──────────────────────────────────────────────
  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;

  -- سلسلة احتياط الدقة: geofence → settings → 100
  v_max_accuracy := coalesce(
    v_geofence.max_accuracy,
    v_settings.accuracy_max_default_meters::numeric(10,2),
    100::numeric(10,2)
  );
  if p_accuracy_meters > v_max_accuracy then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- ── 12) حساب التأخير ─────────────────────────────────────────────────────
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- ── 13) إدراج حدث الحضور ─────────────────────────────────────────────────
  insert into public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    is_mock_location, notes, source, created_by
  ) values (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance,
    case when v_requires_review then 'flagged' else 'accepted' end,
    v_late, v_requires_review, 'passkey_verified',
    p_passkey_credential_id, coalesce(p_biometric_method, 'passkey'),
    p_selfie_path, true, false,
    v_notes, 'mobile', null
  ) returning id into v_event_id;

  -- ── 14) تحديث / إدراج السجل اليومي (period-based) ───────────────────────
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at <  v_period_end
    and status in ('accepted', 'adjusted');

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id),
    v_first_check_in, v_last_check_out,
    case when v_first_check_in is not null and v_last_check_out is not null
      then greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer)
      else 0 end,
    v_late,
    case
      when v_first_check_in is null then 'partial'
      when v_late > 0 then 'late'
      else 'present'
    end,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(excluded.shift_id, attendance_daily.shift_id),
    first_check_in = coalesce(excluded.first_check_in, attendance_daily.first_check_in),
    last_check_out = coalesce(excluded.last_check_out, attendance_daily.last_check_out),
    work_minutes = excluded.work_minutes,
    late_minutes = greatest(attendance_daily.late_minutes, excluded.late_minutes),
    status = case
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend') then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now()
  where attendance_daily.is_finalized = false;

  -- ── 15) تحديث آخر استخدام للـ passkey ────────────────────────────────────
  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  -- ── 16) سجل التدقيق ──────────────────────────────────────────────────────
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_is_night_shift,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;

comment on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) is 'V23 §4: بصمة الحضور الموثقة — إصلاح الوردية الليلية + فترات زمنية + إعدادات مركزية.';

revoke all on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) from public, anon, authenticated;

grant execute on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم د: record_attendance_local_biometric — نفس الإصلاحات
-- Section D: record_attendance_local_biometric — same night shift + period fixes
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.record_attendance_local_biometric(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- حارس الانتقال المستحيل
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
  -- V23: متغيرات جديدة
  v_settings public.attendance_settings%rowtype;
  v_tz text;
  v_local_time time;
  v_prev_crosses boolean;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_max_accuracy numeric(10,2);
  v_is_night_shift boolean := false;
begin
  -- ── 0) الإعدادات ─────────────────────────────────────────────────────────
  select * into v_settings from public.attendance_settings limit 1;
  v_tz := coalesce(v_settings.timezone, 'Africa/Cairo');
  v_work_date := (v_now at time zone v_tz)::date;
  v_local_time := (v_now at time zone v_tz)::time;

  -- ── 1) حراسة الصلاحيات ───────────────────────────────────────────────────
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- ── 2) التحقق من المدخلات ────────────────────────────────────────────────
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_employee_id is null then
    raise exception 'attendance_identity_not_verified' using errcode = '28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
     or p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_attendance_location' using errcode = '22023';
  end if;

  -- ── 3) كشف الوردية الليلية (V23) ────────────────────────────────────────
  if v_local_time < '12:00:00'::time then
    select true into v_prev_crosses
    from public.roster_days rd
    join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
    join public.shifts s on s.id = rd.shift_id
    where rd.employee_id = p_employee_id
      and rd.work_date = v_work_date - 1
      and rd.day_status = 'scheduled'
      and s.crosses_midnight = true
    limit 1;

    if v_prev_crosses is null then
      select true into v_prev_crosses
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
      where sa.employee_id = p_employee_id
        and sa.is_active = true
        and sa.effective_from <= v_work_date - 1
        and (sa.effective_to is null or sa.effective_to >= v_work_date - 1)
        and s.crosses_midnight = true
      limit 1;
    end if;

    if v_prev_crosses and exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id
        and ad.work_date = v_work_date - 1
        and ad.first_check_in is not null
        and ad.last_check_out is null
        and ad.is_finalized = false
        and ad.status not in ('missing_checkout', 'on_leave', 'holiday', 'weekend')
    ) then
      v_work_date := v_work_date - 1;
      v_is_night_shift := true;
    end if;
  end if;

  -- ── 4) حراسة التكرار (60 ثانية) ─────────────────────────────────────────
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- ── 5) حراسة الإقفال ─────────────────────────────────────────────────────
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- ── 6) حارس الانتقال المستحيل ────────────────────────────────────────────
  select ae.event_at, ae.latitude, ae.longitude
    into v_prev_at, v_prev_lat, v_prev_lon
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.latitude is not null and ae.longitude is not null
    and ae.event_at > v_now - interval '6 hours'
  order by ae.event_at desc
  limit 1;

  if v_prev_at is not null then
    v_gap_seconds := greatest(extract(epoch from (v_now - v_prev_at)), 1);
    v_travel := public.geo_distance_meters(
      p_latitude, p_longitude, v_prev_lat, v_prev_lon
    );
    if v_travel is not null
       and (v_travel / v_gap_seconds) > coalesce(v_settings.impossible_travel_speed_mps, 42) then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- ── 7) بحث الجدول/التعيين + السياج + الوردية ─────────────────────────────
  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
    and rd.day_status = 'scheduled'
  order by wr.published_at desc nulls last
  limit 1;

  select * into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_work_date
    and (sa.effective_to is null or sa.effective_to >= v_work_date)
  order by sa.effective_from desc
  limit 1;

  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode = '55000';
  end if;

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- ── 8) حدود الفترة الزمنية (V23) ────────────────────────────────────────
  if v_shift.id is not null and v_shift.crosses_midnight then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := ((v_work_date + 1)::date)::timestamp at time zone v_tz;
  end if;

  -- ── 9) حراسة التسلسل (CHECK_IN ↔ CHECK_OUT) ─────────────────────────────
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at <  v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;

  if p_event_type = 'CHECK_OUT'
     and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  -- ── 10) فحص السياج الجغرافي ──────────────────────────────────────────────
  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;

  v_max_accuracy := coalesce(
    v_geofence.max_accuracy,
    v_settings.accuracy_max_default_meters::numeric(10,2),
    100::numeric(10,2)
  );
  if p_accuracy_meters > v_max_accuracy then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- ── 11) حساب التأخير ─────────────────────────────────────────────────────
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- ── 12) إدراج حدث الحضور ─────────────────────────────────────────────────
  insert into public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    is_mock_location, notes, source, created_by
  ) values (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance,
    case when v_requires_review then 'flagged' else 'accepted' end,
    v_late, v_requires_review, 'biometric_verified',
    null, 'fingerprint', null, true, false,
    v_notes, 'mobile', null
  ) returning id into v_event_id;

  -- ── 13) تحديث / إدراج السجل اليومي (period-based) ───────────────────────
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at <  v_period_end
    and status in ('accepted', 'adjusted');

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id),
    v_first_check_in, v_last_check_out,
    case when v_first_check_in is not null and v_last_check_out is not null
      then greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer)
      else 0 end,
    v_late,
    case
      when v_first_check_in is null then 'partial'
      when v_late > 0 then 'late'
      else 'present'
    end,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(excluded.shift_id, attendance_daily.shift_id),
    first_check_in = coalesce(excluded.first_check_in, attendance_daily.first_check_in),
    last_check_out = coalesce(excluded.last_check_out, attendance_daily.last_check_out),
    work_minutes = excluded.work_minutes,
    late_minutes = greatest(attendance_daily.late_minutes, excluded.late_minutes),
    status = case
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now()
  where attendance_daily.is_finalized = false;

  -- ── 14) سجل التدقيق ──────────────────────────────────────────────────────
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة محلية موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', 'local_biometric',
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_is_night_shift,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;

comment on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) is 'V23 §4: بصمة محلية — إصلاح الوردية الليلية + فترات زمنية + إعدادات مركزية.';

revoke all on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;

grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم هـ: finalize_missing_checkouts — معالجة بصمات الخروج المفقودة
-- Section E: finalize_missing_checkouts — handle missing checkout detection
--
-- تعمل بشكل دوري (pg_cron) لكشف attendance_daily بها حضور بدون انصراف
-- بعد انتهاء الوردية + فترة السماح. تُعلّم الحالة كـ missing_checkout
-- وتُنشئ attendance_exception للمراجعة. لا تُنشئ حدث خروج وهمي.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.finalize_missing_checkouts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
  v_settings public.attendance_settings%rowtype;
  v_tz text;
  v_grace_minutes integer;
  v_now timestamptz := now();
  v_rec record;
  v_shift_end_at timestamptz;
begin
  -- محصور بـservice_role / pg_cron
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  select * into v_settings from public.attendance_settings limit 1;
  v_tz := coalesce(v_settings.timezone, 'Africa/Cairo');
  v_grace_minutes := coalesce(v_settings.missing_checkout_grace_minutes, 60);

  for v_rec in
    select ad.id, ad.employee_id, ad.work_date, ad.shift_id,
           s.end_time, coalesce(s.crosses_midnight, false) as crosses_midnight
    from public.attendance_daily ad
    left join public.shifts s on s.id = ad.shift_id
    where ad.first_check_in is not null
      and ad.last_check_out is null
      and ad.is_finalized = false
      and ad.status not in ('missing_checkout', 'on_leave', 'holiday', 'weekend')
  loop
    -- حساب وقت انتهاء الوردية بالـ UTC
    if v_rec.crosses_midnight and v_rec.end_time is not null then
      v_shift_end_at := ((v_rec.work_date + 1) + v_rec.end_time) at time zone v_tz;
    elsif v_rec.end_time is not null then
      v_shift_end_at := (v_rec.work_date + v_rec.end_time) at time zone v_tz;
    else
      -- لا وردية: نهاية اليوم
      v_shift_end_at := ((v_rec.work_date + 1)::date)::timestamp at time zone v_tz;
    end if;

    -- تخطّي إذا فترة السماح لم تنتهِ بعد
    if v_shift_end_at + make_interval(mins := v_grace_minutes) >= v_now then
      continue;
    end if;

    -- تحديث الحالة
    update public.attendance_daily
    set status = 'missing_checkout',
        updated_at = now()
    where id = v_rec.id
      and is_finalized = false;

    if found then
      -- إنشاء استثناء حضور
      insert into public.attendance_exceptions (
        employee_id, attendance_daily_id, work_date,
        kind, description, status
      ) values (
        v_rec.employee_id, v_rec.id, v_rec.work_date,
        'missing_check_out',
        'بصمة خروج مفقودة — تم الكشف تلقائياً بواسطة finalize_missing_checkouts',
        'open'
      );

      -- سجل تدقيق
      perform public.log_audit_event(
        'attendance.missing_checkout', 'security', 'warning',
        'attendance_daily', v_rec.id,
        'بصمة خروج مفقودة', null,
        jsonb_build_object(
          'employeeId', v_rec.employee_id,
          'workDate', v_rec.work_date,
          'shiftId', v_rec.shift_id
        )
      );

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

comment on function public.finalize_missing_checkouts() is
  'V23 §4: كشف دوري لبصمات الخروج المفقودة بعد انتهاء الوردية + فترة السماح.';

revoke all on function public.finalize_missing_checkouts()
  from public, anon, authenticated;
grant execute on function public.finalize_missing_checkouts()
  to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم و: مُحفِّز تدقيق تغيير إعدادات السياج الجغرافي
-- Section F: Geofence configuration change audit trigger
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_geofence_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.log_audit_event(
    'geofence.config_changed', 'security', 'warning',
    'geofences', NEW.id,
    'تم تعديل إعدادات السياج الجغرافي', null,
    jsonb_build_object(
      'geofenceCode', NEW.code,
      'geofenceName', NEW.name,
      'oldRadius', OLD.radius_meters,
      'newRadius', NEW.radius_meters,
      'oldMaxAccuracy', OLD.max_accuracy,
      'newMaxAccuracy', NEW.max_accuracy,
      'oldLatitude', OLD.latitude,
      'newLatitude', NEW.latitude,
      'oldLongitude', OLD.longitude,
      'newLongitude', NEW.longitude,
      'oldActive', OLD.is_active,
      'newActive', NEW.is_active
    )
  );
  return NEW;
end;
$$;

drop trigger if exists trg_geofence_audit on public.geofences;
create trigger trg_geofence_audit
  after update of radius_meters, max_accuracy, latitude, longitude, is_active
  on public.geofences
  for each row
  execute function public.tg_geofence_audit();


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ز: جدولة pg_cron لمعالجة بصمات الخروج المفقودة (كل 30 دقيقة)
-- Section G: pg_cron schedule for missing checkout finalization (every 30 min)
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
begin
  -- إزالة الجدولة القديمة إن وُجدت
  perform cron.unschedule('finalize-missing-checkouts');
exception when others then null;
end $$;

do $$
begin
  perform cron.schedule(
    'finalize-missing-checkouts',
    '*/30 * * * *',
    $$select public.finalize_missing_checkouts()$$
  );
exception when others then
  raise notice 'pg_cron غير متاح — تخطي جدولة finalize-missing-checkouts: %', sqlerrm;
end $$;
