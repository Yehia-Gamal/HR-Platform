-- 0164: V23 — تقوية الحضور والنطاق الجغرافي (Agent 04)
--
-- يعالج الفجوات التالية حسب متطلبات V23 §04:
--   A) جدول attendance_settings — إعدادات افتراضية قابلة للتعديل (نطاق 300م، عمر موقع 15ث، دقة 100م)
--   B) إصلاح work_date للورديات الليلية (crosses_midnight) في الدوال الأساسية
--   C) تعقب تغييرات النطاق الجغرافي (audit trigger على geofences)
--   D) دالة finalize_missing_checkouts — معالجة ورديات انتهت بدون بصمة خروج
--   E) جدولة pg_cron لتشغيل finalize_missing_checkouts كل 30 دقيقة
--   F) إضافة حالة 'missing_checkout' إلى attendance_daily.status
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- القسم أ: جدول attendance_settings (إعدادات الحضور على مستوى المنظمة)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.attendance_settings (
  id uuid primary key default gen_random_uuid(),
  -- نصف قطر النطاق الجغرافي الافتراضي (متر) — يُستخدم عند عدم وجود قيمة خاصة بالموقع
  geofence_radius_default_meters numeric(10,2) not null default 300.00,
  -- أقصى عمر مقبول للموقع بالثواني (مدة بين الحصول على الموقع وإرساله)
  location_age_max_seconds integer not null default 15,
  -- أقصى دقة GPS مقبولة افتراضياً (متر) — إذا لم يحدد الجيوفنس قيمة خاصة
  accuracy_max_default_meters numeric(10,2) not null default 100.00,
  -- فترة السماح بعد انتهاء الوردية قبل تسجيل "خروج مفقود" (بالدقائق)
  missing_checkout_grace_minutes integer not null default 60,
  -- سرعة الانتقال المستحيل (م/ث) — V23: 42 م/ث ≈ 150 كم/س
  impossible_travel_speed_mps numeric(6,1) not null default 42.0,
  -- مُعرف الموظف الذي عدّل آخر مرة
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  -- جدول singleton: صف واحد فقط
  constraint attendance_settings_singleton check (id = '00000000-0000-0000-0000-000000000001'::uuid),
  constraint att_settings_radius_chk check (geofence_radius_default_meters > 0),
  constraint att_settings_age_chk check (location_age_max_seconds > 0),
  constraint att_settings_accuracy_chk check (accuracy_max_default_meters > 0),
  constraint att_settings_grace_chk check (missing_checkout_grace_minutes >= 0),
  constraint att_settings_speed_chk check (impossible_travel_speed_mps > 0)
);

comment on table public.attendance_settings is
  'V23: إعدادات الحضور على مستوى المنظمة (singleton). النطاق الجغرافي الافتراضي، عمر الموقع، الدقة، سماحية الخروج المفقود.';

-- إدراج الصف الوحيد بالقيم الافتراضية
insert into public.attendance_settings (id)
values ('00000000-0000-0000-0000-000000000001'::uuid)
on conflict (id) do nothing;

-- RLS: القراءة للمصادق عليهم، الكتابة لـfull_access فقط
alter table public.attendance_settings enable row level security;

drop policy if exists att_settings_read on public.attendance_settings;
create policy att_settings_read on public.attendance_settings
  for select using (true);

drop policy if exists att_settings_write on public.attendance_settings;
create policy att_settings_write on public.attendance_settings
  for update using (public.current_is_full_access());

-- Audit trigger on attendance_settings
drop trigger if exists trg_att_settings_updated_at on public.attendance_settings;
create trigger trg_att_settings_updated_at
  before update on public.attendance_settings
  for each row execute function public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- القسم ب: إصلاح work_date للورديات الليلية (crosses_midnight)
-- في record_attendance_event و record_attendance_local_biometric
--
-- المنطق: إذا كانت الوردية تعبر منتصف الليل والساعة الحالية أقل من نهاية
-- الوردية (أي الموظف لا يزال في الوردية الليلية) → يوم العمل = أمس.
-- ─────────────────────────────────────────────────────────────────────────────

-- ---- record_attendance_event (الإصدار الكامل مع إصلاح الوردية الليلية) ----
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
  v_local_time time;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- إعدادات الحضور المركزية
  v_settings public.attendance_settings%rowtype;
  -- حارس الانتقال المستحيل
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
begin
  -- 0) الاستدعاء محصور بـservice_role
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

  -- تحميل الإعدادات المركزية
  select * into v_settings
  from public.attendance_settings
  where id = '00000000-0000-0000-0000-000000000001'::uuid;

  -- ── تحديد يوم العمل (مبدئي — يُعاد حسابه بعد تحديد الوردية للورديات الليلية)
  v_work_date := (v_now at time zone 'Africa/Cairo')::date;
  v_local_time := (v_now at time zone 'Africa/Cairo')::time;

  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- -----------------------------------------------------------------------
  -- حارس الانتقال المستحيل
  -- -----------------------------------------------------------------------
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

  -- ── البحث عن الوردية أولاً (نحتاجها لتحديد يوم العمل الصحيح)
  -- الجدول المنشور (roster) هو المصدر الأولي
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

  -- ── تحديد الوردية (لحساب يوم العمل الصحيح)
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- ── V23: تصحيح يوم العمل للورديات الليلية ──
  -- إذا كانت الوردية تعبر منتصف الليل والوقت المحلي الحالي أقل من نهاية الوردية
  -- (أي الموظف في الجزء الصباحي من الوردية الليلية) → يوم العمل = أمس
  if v_shift.id is not null and v_shift.crosses_midnight
     and v_local_time < v_shift.end_time then
    v_work_date := v_work_date - interval '1 day';
    -- أعد البحث عن الجدول/التعيين ليوم العمل المعدّل
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
  end if;

  -- ── فحص تكرار الفترة المنتهية (بيوم العمل المعدَّل)
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- ── فحص تسلسل الأحداث (CHECK_IN قبل CHECK_OUT)
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and (ae.event_at at time zone 'Africa/Cairo')::date = v_work_date
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

  -- ── تحديد الجيوفنس
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

  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;
  -- V23: استخدام الإعداد المركزي كقيمة افتراضية لأقصى دقة
  if p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_settings.accuracy_max_default_meters, 100) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

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

  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and (event_at at time zone 'Africa/Cairo')::date = v_work_date
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

  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review
    )
  );

  return v_event_id;
end;
$$;

-- إعادة تطبيق الصلاحيات بعد CREATE OR REPLACE
revoke all on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) to service_role;


-- ---- record_attendance_local_biometric (إصلاح الوردية الليلية) ----
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
  v_local_time time;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- إعدادات الحضور المركزية
  v_settings public.attendance_settings%rowtype;
  -- حارس الانتقال المستحيل
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode='42501';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if p_employee_id is null then
    raise exception 'attendance_identity_not_verified' using errcode='28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode='22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode='22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
     or p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_attendance_location' using errcode='22023';
  end if;
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id=p_employee_id and ae.event_type=p_event_type
      and ae.event_at>v_now-interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode='23505';
  end if;

  -- تحميل الإعدادات المركزية
  select * into v_settings
  from public.attendance_settings
  where id = '00000000-0000-0000-0000-000000000001'::uuid;

  -- ── تحديد يوم العمل المبدئي
  v_work_date := (v_now at time zone 'Africa/Cairo')::date;
  v_local_time := (v_now at time zone 'Africa/Cairo')::time;

  -- ── حارس الانتقال المستحيل
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

  -- ── البحث عن الوردية/الجدول
  select rd.shift_id,rd.geofence_id into v_roster_shift_id,v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id=rd.roster_id and wr.status='published'
  where rd.employee_id=p_employee_id and rd.work_date=v_work_date
    and rd.day_status='scheduled'
  order by wr.published_at desc nulls last limit 1;

  select * into v_assignment from public.shift_assignments sa
  where sa.employee_id=p_employee_id and sa.is_active
    and sa.effective_from<=v_work_date
    and (sa.effective_to is null or sa.effective_to>=v_work_date)
  order by sa.effective_from desc limit 1;

  if coalesce(v_roster_shift_id,v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id=coalesce(v_roster_shift_id,v_assignment.shift_id);
  end if;

  -- ── V23: تصحيح يوم العمل للورديات الليلية ──
  if v_shift.id is not null and v_shift.crosses_midnight
     and v_local_time < v_shift.end_time then
    v_work_date := v_work_date - interval '1 day';
    -- أعد البحث عن الجدول/التعيين ليوم العمل المعدّل
    select rd.shift_id,rd.geofence_id into v_roster_shift_id,v_roster_geofence_id
    from public.roster_days rd
    join public.work_rosters wr on wr.id=rd.roster_id and wr.status='published'
    where rd.employee_id=p_employee_id and rd.work_date=v_work_date
      and rd.day_status='scheduled'
    order by wr.published_at desc nulls last limit 1;

    select * into v_assignment from public.shift_assignments sa
    where sa.employee_id=p_employee_id and sa.is_active
      and sa.effective_from<=v_work_date
      and (sa.effective_to is null or sa.effective_to>=v_work_date)
    order by sa.effective_from desc limit 1;
  end if;

  -- ── فحص الفترة المنتهية (بيوم العمل المعدَّل)
  if exists (
    select 1 from public.attendance_daily
    where employee_id=p_employee_id and work_date=v_work_date and is_finalized
  ) then
    raise exception 'attendance_period_finalized' using errcode='55000';
  end if;

  -- ── فحص تسلسل الأحداث
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id=p_employee_id
    and (ae.event_at at time zone 'Africa/Cairo')::date=v_work_date
    and ae.status in ('accepted','adjusted')
  order by ae.event_at desc limit 1;
  if p_event_type='CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode='22023';
  end if;
  if p_event_type='CHECK_IN' and v_last_event_type='CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode='22023';
  end if;

  -- ── تحديد الجيوفنس
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id=v_roster_geofence_id and is_active;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id=v_assignment.geofence_id and is_active;
  end if;
  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode='55000';
  end if;

  v_distance := public.geo_distance_meters(
    p_latitude,p_longitude,v_geofence.latitude,v_geofence.longitude
  )::numeric(12,2);
  if v_distance>v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode='22023';
  end if;
  -- V23: استخدام الإعداد المركزي كقيمة افتراضية لأقصى دقة
  if p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_settings.accuracy_max_default_meters, 100) then
    raise exception 'attendance_location_accuracy_too_low' using errcode='22023';
  end if;

  if p_event_type='CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now,v_shift.start_time,v_shift.grace_in_minutes,v_work_date
    );
  end if;

  insert into public.attendance_events(
    employee_id,shift_assignment_id,geofence_id,event_type,event_at,
    latitude,longitude,accuracy_meters,distance_meters,status,
    late_minutes,requires_review,verification_status,
    passkey_credential_id,biometric_method,selfie_path,server_verified,
    is_mock_location,notes,source,created_by
  ) values (
    p_employee_id,v_assignment.id,v_geofence.id,p_event_type,v_now,
    p_latitude,p_longitude,p_accuracy_meters,v_distance,
    case when v_requires_review then 'flagged' else 'accepted' end,
    v_late,v_requires_review,'biometric_verified',null,'fingerprint',null,true,false,
    v_notes,'mobile',null
  ) returning id into v_event_id;

  select min(event_at) filter(where event_type='CHECK_IN'),
         max(event_at) filter(where event_type='CHECK_OUT')
    into v_first_check_in,v_last_check_out
  from public.attendance_events
  where employee_id=p_employee_id
    and (event_at at time zone 'Africa/Cairo')::date=v_work_date
    and status in ('accepted','adjusted');

  insert into public.attendance_daily(
    employee_id,work_date,shift_id,first_check_in,last_check_out,
    work_minutes,late_minutes,status,is_finalized,created_by
  ) values (
    p_employee_id,v_work_date,coalesce(v_roster_shift_id,v_assignment.shift_id),
    v_first_check_in,v_last_check_out,
    case when v_first_check_in is not null and v_last_check_out is not null
      then greatest(0,floor(extract(epoch from (v_last_check_out-v_first_check_in))/60)::integer)
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

  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة بيومترية محلية داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', 'fingerprint',
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review
    )
  );

  return v_event_id;
end;
$$;

-- إعادة تطبيق الصلاحيات
revoke all on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- القسم ج: Audit trigger على جدول geofences
-- كل تغيير في النطاق الجغرافي يُسجَّل في audit_events
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.trg_geofence_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_action text;
  v_diff jsonb := '{}'::jsonb;
begin
  if TG_OP = 'DELETE' then
    perform public.log_audit_event(
      'geofence.deleted', 'security', 'warning',
      'geofences', OLD.id,
      'حُذف نطاق جغرافي: ' || OLD.name, null,
      jsonb_build_object(
        'code', OLD.code,
        'radius_meters', OLD.radius_meters,
        'latitude', OLD.latitude,
        'longitude', OLD.longitude
      )
    );
    return OLD;
  end if;

  if TG_OP = 'INSERT' then
    v_action := 'geofence.created';
  else
    v_action := 'geofence.updated';
    -- تتبع الحقول المتغيرة فقط
    if NEW.radius_meters is distinct from OLD.radius_meters then
      v_diff := v_diff || jsonb_build_object(
        'radius_meters_old', OLD.radius_meters,
        'radius_meters_new', NEW.radius_meters
      );
    end if;
    if NEW.latitude is distinct from OLD.latitude or NEW.longitude is distinct from OLD.longitude then
      v_diff := v_diff || jsonb_build_object(
        'latitude_old', OLD.latitude, 'longitude_old', OLD.longitude,
        'latitude_new', NEW.latitude, 'longitude_new', NEW.longitude
      );
    end if;
    if NEW.max_accuracy is distinct from OLD.max_accuracy then
      v_diff := v_diff || jsonb_build_object(
        'max_accuracy_old', OLD.max_accuracy,
        'max_accuracy_new', NEW.max_accuracy
      );
    end if;
    if NEW.is_active is distinct from OLD.is_active then
      v_diff := v_diff || jsonb_build_object(
        'is_active_old', OLD.is_active,
        'is_active_new', NEW.is_active
      );
    end if;
  end if;

  perform public.log_audit_event(
    v_action, 'security',
    case when TG_OP = 'INSERT' then 'info' else 'warning' end,
    'geofences', NEW.id,
    case when TG_OP = 'INSERT' then 'أُنشئ نطاق جغرافي: ' || NEW.name
         else 'تعديل نطاق جغرافي: ' || NEW.name end,
    null,
    jsonb_build_object(
      'code', NEW.code,
      'radius_meters', NEW.radius_meters,
      'latitude', NEW.latitude,
      'longitude', NEW.longitude,
      'max_accuracy', NEW.max_accuracy,
      'is_active', NEW.is_active
    ) || v_diff
  );
  return NEW;
end;
$$;

drop trigger if exists trg_geofence_audit_trail on public.geofences;
create trigger trg_geofence_audit_trail
  after insert or update or delete on public.geofences
  for each row execute function public.trg_geofence_audit();


-- ─────────────────────────────────────────────────────────────────────────────
-- القسم د: إضافة حالة 'missing_checkout' إلى attendance_daily.status
-- ─────────────────────────────────────────────────────────────────────────────

-- إسقاط القيد القديم وإنشاء قيد جديد يشمل الحالة الجديدة
alter table public.attendance_daily
  drop constraint if exists attendance_daily_status_check;
alter table public.attendance_daily
  add constraint attendance_daily_status_check
  check (status in ('present','absent','late','on_leave','holiday','weekend',
                    'partial','pending','missing_checkout'));


-- ─────────────────────────────────────────────────────────────────────────────
-- القسم هـ: finalize_missing_checkouts
-- دالة دورية تعالج ورديات انتهت بدون بصمة خروج
-- V23: "missing checkout بدون وقت وهمي + pg_cron دوري"
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.finalize_missing_checkouts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := now();
  v_count integer := 0;
  v_grace_minutes integer;
  v_rec record;
  v_shift_end_ts timestamptz;
begin
  -- مسموح فقط لعملية خادمية (pg_cron يعمل كـ postgres)
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- تحميل فترة السماح
  select coalesce(s.missing_checkout_grace_minutes, 60)
    into v_grace_minutes
  from public.attendance_settings s
  where s.id = '00000000-0000-0000-0000-000000000001'::uuid;
  v_grace_minutes := coalesce(v_grace_minutes, 60);

  -- البحث عن attendance_daily: لديه بصمة دخول بدون بصمة خروج، والوردية انتهت + grace
  for v_rec in
    select
      ad.id as daily_id,
      ad.employee_id,
      ad.work_date,
      ad.first_check_in,
      ad.shift_id,
      s.end_time as shift_end_time,
      s.crosses_midnight
    from public.attendance_daily ad
    join public.shifts s on s.id = ad.shift_id
    where ad.is_finalized = false
      and ad.first_check_in is not null
      and ad.last_check_out is null
      and ad.status not in ('on_leave', 'holiday', 'weekend', 'missing_checkout')
      -- حساب وقت انتهاء الوردية الفعلي
      and case
        when s.crosses_midnight then
          -- الوردية الليلية: تنتهي في اليوم التالي
          (ad.work_date + interval '1 day' + s.end_time + make_interval(mins := v_grace_minutes)) <= v_now
        else
          -- الوردية العادية: تنتهي في نفس اليوم
          (ad.work_date + s.end_time + make_interval(mins := v_grace_minutes)) <= v_now
      end
      -- فقط آخر 3 أيام — لا نعالج بيانات قديمة جداً
      and ad.work_date >= (v_now at time zone 'Africa/Cairo')::date - 3
  loop
    -- تحديث حالة attendance_daily إلى missing_checkout (بدون وقت خروج وهمي)
    update public.attendance_daily
    set status = 'missing_checkout',
        updated_at = v_now
    where id = v_rec.daily_id
      and is_finalized = false
      and last_check_out is null;

    -- إنشاء استثناء حضور (exception) للمراجعة البشرية
    insert into public.attendance_exceptions (
      employee_id, attendance_daily_id, work_date, kind,
      description, status, created_by
    ) values (
      v_rec.employee_id, v_rec.daily_id, v_rec.work_date,
      'missing_check_out',
      'خروج مفقود — انتهت الوردية بدون بصمة انصراف. يحتاج مراجعة بشرية.',
      'open', null
    )
    -- تجنب التكرار: إذا وُجد استثناء بنفس النوع واليوم لا ندرج مجدداً
    on conflict do nothing;

    -- إرسال إشعار للموظف (إذا كان لديه user_id)
    insert into public.notifications (
      recipient_user_id, recipient_employee_id,
      title, body, category, priority,
      action_url, entity_type, entity_id, metadata
    )
    select
      e.user_id, v_rec.employee_id,
      '⚠️ بصمة انصراف مفقودة',
      'لم تُسجَّل بصمة انصراف ليوم ' || to_char(v_rec.work_date, 'YYYY-MM-DD') || '. راجع الحضور أو قدّم طلب تسوية.',
      'system', 'high',
      '/attendance', 'missing_checkout', v_rec.daily_id,
      jsonb_build_object('workDate', v_rec.work_date::text, 'dailyId', v_rec.daily_id)
    from public.employees e
    where e.id = v_rec.employee_id
      and e.user_id is not null
      -- تجنب تكرار الإشعار
      and not exists (
        select 1 from public.notifications n
        where n.recipient_employee_id = v_rec.employee_id
          and n.entity_type = 'missing_checkout'
          and n.metadata->>'dailyId' = v_rec.daily_id::text
      );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

comment on function public.finalize_missing_checkouts() is
  'V23: معالجة دورية للورديات المنتهية بدون بصمة خروج — تُعلّم missing_checkout بدون وقت وهمي + تُنشئ استثناء + إشعار.';

revoke all on function public.finalize_missing_checkouts() from public, anon, authenticated;
grant execute on function public.finalize_missing_checkouts() to service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- القسم و: جدولة pg_cron (إذا كان الإضافة مُثبتة)
-- تشغيل finalize_missing_checkouts كل 30 دقيقة
-- ─────────────────────────────────────────────────────────────────────────────

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- إلغاء الجدولة القديمة إن وُجدت
    perform cron.unschedule('finalize_missing_checkouts');
    -- جدولة جديدة: كل 30 دقيقة
    perform cron.schedule(
      'finalize_missing_checkouts',
      '*/30 * * * *',
      $$select public.finalize_missing_checkouts()$$
    );
  end if;
exception when others then
  -- pg_cron غير مُثبت — لا مشكلة، التشغيل اليدوي ممكن
  raise notice 'pg_cron not available — finalize_missing_checkouts must be called manually or via external scheduler';
end;
$$;
