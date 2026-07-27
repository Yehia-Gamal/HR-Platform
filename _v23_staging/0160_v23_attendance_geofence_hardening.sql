-- 0160: V23 §4 — Attendance, Geofence & Night-Shift Hardening
-- ============================================================================
-- هذه الهجرة تُعالج ستة ثغرات رئيسية في نظام الحضور:
--   A) جدول attendance_settings — إعدادات مركزية (singleton) لنظام الحضور
--   B) توسيع قيد attendance_daily.status لدعم 'missing_checkout'
--   C) record_attendance_event — إصلاح حساب work_date للورديات الليلية
--      + حدود فترة زمنية بدلاً من مقارنة التاريخ
--   D) record_attendance_local_biometric — نفس إصلاح الوردية الليلية
--   E) finalize_missing_checkouts — دالة مُجدولة لإغلاق البصمات المفقودة
--   F) مُشغّل تدقيق تغييرات السياج الجغرافي
--   G) جدولة pg_cron لـ finalize_missing_checkouts
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم أ: attendance_settings — جدول مفرد (singleton) لإعدادات الحضور
-- Section A: attendance_settings singleton table
-- ═══════════════════════════════════════════════════════════════════════════════

create table if not exists public.attendance_settings (
  singleton_key    boolean primary key default true
                   check (singleton_key = true),
  -- V23 §4: نصف قطر السياج الافتراضي (متر)
  geofence_radius_default_meters  numeric(10,2) not null default 300,
  -- V23 §4: أقصى عمر للموقع (ثانية) — الخادم يرفض موقعاً أقدم من هذا
  location_age_max_seconds        integer not null default 15
                                  check (location_age_max_seconds between 5 and 120),
  -- V23 §4: أقصى دقة مقبولة (متر) — احتياطي إذا لم يُحدد في السياج
  accuracy_max_default_meters     numeric(10,2) not null default 100,
  -- V23 §4: فترة سماح بعد انتهاء الوردية لانتظار بصمة الخروج (دقيقة)
  missing_checkout_grace_minutes  integer not null default 60
                                  check (missing_checkout_grace_minutes between 15 and 480),
  -- V23 §4: عتبة سرعة الانتقال المستحيل (م/ث) — 42 ≈ 150 كم/س
  impossible_travel_speed_mps     numeric(6,2) not null default 42
                                  check (impossible_travel_speed_mps between 10 and 200),
  -- المنطقة الزمنية الرسمية
  timezone                        text not null default 'Africa/Cairo',
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now()
);

comment on table public.attendance_settings is
  'V23 §4: إعدادات نظام الحضور — جدول مفرد (singleton). صف واحد فقط.';

-- بذر الصف الوحيد
insert into public.attendance_settings (singleton_key)
values (true)
on conflict (singleton_key) do nothing;

-- مُشغّل التحديث
drop trigger if exists trg_attendance_settings_updated_at on public.attendance_settings;
create trigger trg_attendance_settings_updated_at
  before update on public.attendance_settings
  for each row execute function public.tg_set_updated_at();

-- أمان: RLS + صلاحيات
alter table public.attendance_settings enable row level security;

create policy att_settings_read on public.attendance_settings
  for select to authenticated using (true);

create policy att_settings_admin on public.attendance_settings
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

grant select on public.attendance_settings to authenticated;
grant all on public.attendance_settings to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ب: توسيع قيد attendance_daily.status
-- Section B: Expand attendance_daily.status CHECK constraint
-- ═══════════════════════════════════════════════════════════════════════════════
-- القيد الأصلي (0005) لا يتضمن 'missing_checkout'. نبحث عن اسم القيد
-- التلقائي ونُسقطه ثم نُعيد إنشاءه بالقيمة الجديدة.

do $$
declare
  v_con text;
begin
  select conname into v_con
  from pg_constraint
  where conrelid = 'public.attendance_daily'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%status%';
  if v_con is not null then
    execute format('alter table public.attendance_daily drop constraint %I', v_con);
  end if;
end;
$$;

alter table public.attendance_daily add constraint attendance_daily_status_check
  check (status in (
    'present','absent','late','on_leave','holiday',
    'weekend','partial','pending','missing_checkout'
  ));


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ج: record_attendance_event — إصلاح الوردية الليلية + حدود الفترة
-- Section C: record_attendance_event — night shift work_date fix + period bounds
-- ═══════════════════════════════════════════════════════════════════════════════
-- الأخطاء المُصلحة:
--   1) v_work_date لم تُراعِ crosses_midnight — بصمة الخروج بعد منتصف الليل
--      تُسجَّل في يوم خاطئ.
--   2) فحص التسلسل يقارن (event_at at time zone 'Africa/Cairo')::date = v_work_date
--      — يفشل لأحداث الوردية الليلية بعد منتصف الليل.
--   3) تجميع attendance_daily يعاني من نفس خطأ المقارنة.
-- ============================================================================

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
  v_tz text;
  v_work_date date;
  v_local_time time;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- Night shift resolution
  v_prev_shift_id uuid;
  v_prev_crosses_midnight boolean;
  v_prev_end_time time;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
  -- Settings
  v_settings public.attendance_settings%rowtype;
begin
  -- Read centralized settings (singleton row, default-seeded)
  select * into v_settings from public.attendance_settings limit 1;
  v_tz := coalesce(v_settings.timezone, 'Africa/Cairo');
  v_work_date := (v_now at time zone v_tz)::date;
  v_local_time := (v_now at time zone v_tz)::time;

  -- 0) Service role only
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

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

  -- 60s dedup (time-based, independent of work_date)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- ─── Night shift work_date resolution ─────────────────────────────────
  -- For crosses_midnight shifts, a punch after midnight but before shift end
  -- belongs to the PREVIOUS calendar day's work_date.
  if v_local_time < '12:00:00'::time then
    -- Check yesterday's roster for a night shift
    select rd.shift_id into v_prev_shift_id
    from public.roster_days rd
    join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
    where rd.employee_id = p_employee_id
      and rd.work_date = v_work_date - 1
      and rd.day_status = 'scheduled'
    order by wr.published_at desc nulls last
    limit 1;
    -- Fallback to shift_assignments
    if v_prev_shift_id is null then
      select sa.shift_id into v_prev_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active = true
        and sa.effective_from <= v_work_date - 1
        and (sa.effective_to is null or sa.effective_to >= v_work_date - 1)
      order by sa.effective_from desc
      limit 1;
    end if;
    if v_prev_shift_id is not null then
      select s.crosses_midnight, s.end_time
        into v_prev_crosses_midnight, v_prev_end_time
      from public.shifts s where s.id = v_prev_shift_id;
      -- If yesterday had a night shift whose end_time hasn't passed yet,
      -- AND there's an open (no checkout) attendance for yesterday → adjust
      if v_prev_crosses_midnight
         and v_local_time < v_prev_end_time
         and exists (
           select 1 from public.attendance_daily ad
           where ad.employee_id = p_employee_id
             and ad.work_date = v_work_date - 1
             and ad.first_check_in is not null
             and ad.last_check_out is null
             and not ad.is_finalized
         )
      then
        v_work_date := v_work_date - 1;
      end if;
    end if;
  end if;

  -- Period finalization check (uses corrected work_date)
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- ─── Impossible-travel guard ──────────────────────────────────────────
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

  -- ─── Roster / shift / geofence lookup (uses corrected work_date) ──────
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

  -- ─── Geofence + accuracy check ────────────────────────────────────────
  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;
  -- Accuracy fallback: geofence-specific → global default → 100m
  if p_accuracy_meters > coalesce(
    v_geofence.max_accuracy,
    v_settings.accuracy_max_default_meters,
    100
  ) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- ─── Resolve shift & period boundaries ────────────────────────────────
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- Calculate event period boundaries for night shift support
  if v_shift.id is not null and v_shift.crosses_midnight then
    -- Night shift: period spans from start_time on work_date to end_time on work_date+1
    v_period_start := ((v_work_date::timestamp) + v_shift.start_time) at time zone v_tz;
    v_period_end   := (((v_work_date + 1)::timestamp) + v_shift.end_time) at time zone v_tz;
  else
    -- Day shift: period = full calendar day in local timezone
    v_period_start := (v_work_date::timestamp) at time zone v_tz;
    v_period_end   := ((v_work_date + 1)::timestamp) at time zone v_tz;
  end if;

  -- ─── Sequencing check (period-based, not date-based) ──────────────────
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
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

  -- ─── Late minutes calculation ─────────────────────────────────────────
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- ─── Insert attendance event ──────────────────────────────────────────
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

  -- ─── attendance_daily upsert (period-based aggregation) ───────────────
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
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

  -- Passkey last_used update
  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  -- Audit trail
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', coalesce(v_shift.crosses_midnight, false),
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;

-- Re-apply revokes after CREATE OR REPLACE
revoke all on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم د: record_attendance_local_biometric — نفس إصلاح الوردية الليلية
-- Section D: record_attendance_local_biometric — same night shift fix
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
  v_tz text;
  v_work_date date;
  v_local_time time;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- Night shift resolution
  v_prev_shift_id uuid;
  v_prev_crosses_midnight boolean;
  v_prev_end_time time;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
  -- Settings
  v_settings public.attendance_settings%rowtype;
begin
  -- Read centralized settings
  select * into v_settings from public.attendance_settings limit 1;
  v_tz := coalesce(v_settings.timezone, 'Africa/Cairo');
  v_work_date := (v_now at time zone v_tz)::date;
  v_local_time := (v_now at time zone v_tz)::time;

  -- Service role only
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;
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

  -- 60s dedup
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- ─── Night shift work_date resolution ─────────────────────────────────
  if v_local_time < '12:00:00'::time then
    select rd.shift_id into v_prev_shift_id
    from public.roster_days rd
    join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
    where rd.employee_id = p_employee_id
      and rd.work_date = v_work_date - 1
      and rd.day_status = 'scheduled'
    order by wr.published_at desc nulls last
    limit 1;

    if v_prev_shift_id is null then
      select sa.shift_id into v_prev_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active = true
        and sa.effective_from <= v_work_date - 1
        and (sa.effective_to is null or sa.effective_to >= v_work_date - 1)
      order by sa.effective_from desc
      limit 1;
    end if;

    if v_prev_shift_id is not null then
      select s.crosses_midnight, s.end_time
        into v_prev_crosses_midnight, v_prev_end_time
      from public.shifts s where s.id = v_prev_shift_id;

      if v_prev_crosses_midnight
         and v_local_time < v_prev_end_time
         and exists (
           select 1 from public.attendance_daily ad
           where ad.employee_id = p_employee_id
             and ad.work_date = v_work_date - 1
             and ad.first_check_in is not null
             and ad.last_check_out is null
             and not ad.is_finalized
         )
      then
        v_work_date := v_work_date - 1;
      end if;
    end if;
  end if;

  -- Period finalization check
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- ─── Impossible-travel guard ──────────────────────────────────────────
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

  -- ─── Roster / shift / geofence lookup ─────────────────────────────────
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

  -- ─── Geofence + accuracy check ────────────────────────────────────────
  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;
  if p_accuracy_meters > coalesce(
    v_geofence.max_accuracy,
    v_settings.accuracy_max_default_meters,
    100
  ) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- ─── Resolve shift & period boundaries ────────────────────────────────
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  if v_shift.id is not null and v_shift.crosses_midnight then
    v_period_start := ((v_work_date::timestamp) + v_shift.start_time) at time zone v_tz;
    v_period_end   := (((v_work_date + 1)::timestamp) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := (v_work_date::timestamp) at time zone v_tz;
    v_period_end   := ((v_work_date + 1)::timestamp) at time zone v_tz;
  end if;

  -- ─── Sequencing check (period-based) ──────────────────────────────────
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
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

  -- ─── Late calculation ─────────────────────────────────────────────────
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- ─── Insert event ─────────────────────────────────────────────────────
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

  -- ─── attendance_daily upsert (period-based) ───────────────────────────
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
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

  -- Audit trail
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة محلية موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', 'local_biometric',
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', coalesce(v_shift.crosses_midnight, false),
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;

-- Re-apply revokes
revoke all on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم هـ: finalize_missing_checkouts — إغلاق بصمات الخروج المفقودة
-- Section E: finalize_missing_checkouts — close missing checkouts
-- ═══════════════════════════════════════════════════════════════════════════════
-- V23 §4: دالة مُجدولة (pg_cron) تعمل كل 30 دقيقة.
-- تبحث عن attendance_daily بدون بصمة خروج، بعد انتهاء الوردية + فترة السماح.
-- تُعلِّم كـ 'missing_checkout' وتُنشئ attendance_exception + audit.
-- لا تُزوِّر وقتاً — لا تُدرج بصمة خروج وهمية.
-- ============================================================================

create or replace function public.finalize_missing_checkouts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_tz text;
  v_grace_minutes integer;
  v_count integer := 0;
  v_rec record;
  v_shift public.shifts%rowtype;
  v_shift_end_ts timestamptz;
begin
  -- Service role only
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'finalize_requires_service_role' using errcode = '42501';
  end if;

  select coalesce(timezone, 'Africa/Cairo'),
         coalesce(missing_checkout_grace_minutes, 60)
    into v_tz, v_grace_minutes
  from public.attendance_settings
  limit 1;

  -- Defaults if settings table is empty
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_grace_minutes := coalesce(v_grace_minutes, 60);

  for v_rec in
    select ad.id as daily_id,
           ad.employee_id,
           ad.work_date,
           ad.shift_id,
           ad.first_check_in
    from public.attendance_daily ad
    where ad.first_check_in is not null
      and ad.last_check_out is null
      and ad.is_finalized = false
      and ad.status not in ('on_leave', 'holiday', 'weekend', 'missing_checkout')
      -- Only process records older than today (or yesterday for night shifts)
      and ad.work_date < (v_now at time zone v_tz)::date
  loop
    -- Resolve shift for grace period calculation
    if v_rec.shift_id is not null then
      select * into v_shift from public.shifts where id = v_rec.shift_id;
    else
      v_shift := null;
    end if;

    -- Calculate when the shift actually ended
    if v_shift.id is not null then
      if v_shift.crosses_midnight then
        v_shift_end_ts := (((v_rec.work_date + 1)::timestamp) + v_shift.end_time) at time zone v_tz;
      else
        v_shift_end_ts := ((v_rec.work_date::timestamp) + v_shift.end_time) at time zone v_tz;
      end if;
    else
      -- No shift → default end of day 18:00
      v_shift_end_ts := ((v_rec.work_date::timestamp) + '18:00:00'::time) at time zone v_tz;
    end if;

    -- Skip if grace period hasn't elapsed yet
    if v_now < v_shift_end_ts + make_interval(mins := v_grace_minutes) then
      continue;
    end if;

    -- Mark as missing_checkout
    update public.attendance_daily
    set status = 'missing_checkout',
        updated_at = now()
    where id = v_rec.daily_id
      and is_finalized = false;

    -- Create an attendance exception for HR review
    insert into public.attendance_exceptions (
      employee_id, attendance_daily_id, work_date, kind,
      description, minutes_adjustment, status
    ) values (
      v_rec.employee_id, v_rec.daily_id, v_rec.work_date, 'missing_check_out',
      'بصمة خروج مفقودة — تم التعليم تلقائياً بعد انتهاء الوردية + فترة السماح',
      0, 'open'
    )
    on conflict do nothing;

    -- Audit log
    perform public.log_audit_event(
      'attendance.missing_checkout', 'operations', 'warning',
      'attendance_daily', v_rec.daily_id,
      'بصمة خروج مفقودة — تعليم تلقائي', null,
      jsonb_build_object(
        'employeeId', v_rec.employee_id,
        'workDate', v_rec.work_date,
        'checkIn', v_rec.first_check_in,
        'shiftId', v_rec.shift_id,
        'graceMinutes', v_grace_minutes
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

comment on function public.finalize_missing_checkouts() is
  'V23 §4: إغلاق بصمات الخروج المفقودة تلقائياً بعد انتهاء الوردية + فترة السماح. تُجدول كل 30 دقيقة.';

-- Service role only
revoke all on function public.finalize_missing_checkouts()
  from public, anon, authenticated;
grant execute on function public.finalize_missing_checkouts()
  to service_role;


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم و: مُشغّل تدقيق تغييرات السياج الجغرافي
-- Section F: Geofence change audit trigger
-- ═══════════════════════════════════════════════════════════════════════════════
-- V23 §4: أي تغيير في radius_meters / max_accuracy / latitude / longitude
-- يُسجَّل في audit_events للمراجعة.
-- ============================================================================

create or replace function public.tg_geofence_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Only audit meaningful changes to geo parameters
  if OLD.radius_meters   is distinct from NEW.radius_meters
     or OLD.max_accuracy  is distinct from NEW.max_accuracy
     or OLD.latitude      is distinct from NEW.latitude
     or OLD.longitude     is distinct from NEW.longitude
     or OLD.is_active     is distinct from NEW.is_active
  then
    perform public.log_audit_event(
      'geofence.config_changed', 'security', 'warning',
      'geofences', NEW.id,
      'تعديل إعدادات السياج الجغرافي',
      null,
      jsonb_build_object(
        'geofenceCode', NEW.code,
        'geofenceName', NEW.name,
        'changes', jsonb_build_object(
          'radius_meters',  jsonb_build_object('old', OLD.radius_meters, 'new', NEW.radius_meters),
          'max_accuracy',   jsonb_build_object('old', OLD.max_accuracy, 'new', NEW.max_accuracy),
          'latitude',       jsonb_build_object('old', OLD.latitude, 'new', NEW.latitude),
          'longitude',      jsonb_build_object('old', OLD.longitude, 'new', NEW.longitude),
          'is_active',      jsonb_build_object('old', OLD.is_active, 'new', NEW.is_active)
        )
      )
    );
  end if;
  return NEW;
end;
$$;

comment on function public.tg_geofence_audit() is
  'V23 §4: يُسجّل تغييرات السياج الجغرافي (نصف القطر/الدقة/الإحداثيات) في سجل التدقيق.';

drop trigger if exists trg_geofence_audit on public.geofences;
create trigger trg_geofence_audit
  after update on public.geofences
  for each row execute function public.tg_geofence_audit();


-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ز: جدولة pg_cron
-- Section G: pg_cron schedule for finalize_missing_checkouts
-- ═══════════════════════════════════════════════════════════════════════════════
-- NOTE: pg_cron is only available in hosted Supabase. This block is idempotent
-- and will silently skip if the extension or permission is unavailable.

do $$
begin
  -- Try to schedule; catch if pg_cron is not available
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Remove any previous schedule for this function
    perform cron.unschedule(jobname)
    from cron.job
    where jobname = 'finalize_missing_checkouts';

    -- Schedule every 30 minutes
    perform cron.schedule(
      'finalize_missing_checkouts',
      '*/30 * * * *',
      $$select public.finalize_missing_checkouts()$$
    );
  end if;
exception
  when others then
    raise notice 'pg_cron not available — finalize_missing_checkouts must be called manually or via external scheduler';
end;
$$;
