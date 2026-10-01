-- =====================================================================
-- 0588: تفعيل فترات العمل المرنة الثلاث ودعم الوردية المجزأة (Split Shift)
--
--  1) فترات العمل المرنة الثلاث (بطلب الإدارة 2026-10-01):
--     • الوردية الصباحية: 09:00 ص إلى 05:00 م (سماح 15 د حتى 09:15 ص).
--     • الدوام الأساسي:   10:00 ص إلى 06:00 م (سماح 15 د حتى 10:15 ص).
--     • الوردية المسائية: 11:00 ص إلى 07:00 م (سماح 15 د حتى 11:15 ص).
--     • مطابقة تلقائية مرنة حسب وقت وصول الموظف:
--       - وصول حتى 09:30 ص → وردية (9 ص – 5 م).
--       - وصول بين 09:31 ص و 10:30 ص → وردية (10 ص – 6 م).
--       - وصول بعد 10:30 ص → وردية (11 ص – 7 م).
--       مع احتساب التأخير لكل وردية من بداية موعدها بعد انتهاء الربع ساعة سماح،
--       وتطبيق شرائح الغرامات المعتمدة (20 ج، 50 ج، 150 ج بسقف ساعتين).
--
--  2) دعم الوردية المجزأة (Split Shift) ليوسف رسمي وعبدالله أيوب:
--     • حضور وانصراف (فترة أولى) ثم راحة ثم حضور وانصراف (فترة ثانية) في نفس اليوم.
--     • تجميع ساعات العمل الفعلي للفترتين معاً تلقائياً (حضور 1 + حضور 2).
--     • خصم فترة الراحة بين الانصراف الأول والحضور الثاني من إجمالي الساعات.
--     • عدم تقييد التأخير أو فرض غرامة على الحضور الثاني (العودة من الراحة).
-- =====================================================================

begin;

-- ─── 1) تحديث وإدراج الفترات الثلاث في جدول الورديات (shifts) ─────────────
insert into public.shifts (code, name, name_en, start_time, end_time, crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
values
  ('SHIFT_9_5', 'الوردية الصباحية (9 ص – 5 م)', 'Morning (09:00–17:00)', '09:00:00', '17:00:00', false, 0, 15, 0, true),
  ('OFFICIAL', 'الدوام الأساسي (10 ص – 6 م)', 'Official (10:00–18:00)', '10:00:00', '18:00:00', false, 0, 15, 0, true),
  ('SHIFT_11_7', 'الوردية المسائية (11 ص – 7 م)', 'Evening (11:00–19:00)', '11:00:00', '19:00:00', false, 0, 15, 0, true)
on conflict (code) do update set
  name = excluded.name,
  name_en = excluded.name_en,
  start_time = excluded.start_time,
  end_time = excluded.end_time,
  grace_in_minutes = excluded.grace_in_minutes,
  is_active = true;

-- ─── 2) دالة المطابقة التلقائية للوردية المرنة بحسب وقت الحضور ───────────
create or replace function public.match_flexible_shift(p_check_in timestamptz)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_time time;
  v_shift_code text;
  v_shift_id uuid;
begin
  if p_check_in is null then
    return public.default_shift_id();
  end if;

  v_time := (p_check_in at time zone 'Africa/Cairo')::time;
  
  -- مطابقة نافذة الوصول
  if v_time <= '09:30:00'::time then
    v_shift_code := 'SHIFT_9_5';
  elsif v_time <= '10:30:00'::time then
    v_shift_code := 'OFFICIAL';
  else
    v_shift_code := 'SHIFT_11_7';
  end if;

  select id into v_shift_id
  from public.shifts
  where code = v_shift_code and is_active
  limit 1;

  return coalesce(v_shift_id, public.default_shift_id());
end;
$fn$;

-- ─── 3) حساب دقائق التأخير بحسب الوردية المرنة المطابقة ─────────────────
create or replace function public.attendance_policy_late_minutes(
  p_employee_id uuid,
  p_work_date date,
  p_check_in timestamptz,
  p_shift_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_shift public.shifts%rowtype;
  v_diff integer;
  v_target_shift_id uuid;
begin
  if p_check_in is null or public.is_lateness_excused(p_employee_id, p_work_date) then
    return 0;
  end if;

  -- إذا لم تُسند وردية معينة للموظف، يتم تحديد الوردية تلقائياً بحسب وقت الحضور
  v_target_shift_id := coalesce(p_shift_id, public.match_flexible_shift(p_check_in));

  select * into v_shift from public.shifts where id = v_target_shift_id;
  if v_shift.id is null or v_shift.start_time is null then
    return 0;
  end if;

  v_diff := floor(extract(epoch from (
    p_check_in - ((p_work_date + v_shift.start_time)::timestamp at time zone 'Africa/Cairo')
  )) / 60)::integer;

  return case when v_diff > coalesce(v_shift.grace_in_minutes, 0) then least(greatest(0, v_diff), 120) else 0 end;
end;
$fn$;

-- ─── 4) تمييز موظفي الوردية المجزأة (يوسف رسمي وعبدالله أيوب) ─────────────
alter table public.employees add column if not exists is_split_shift boolean default false;

update public.employees 
set is_split_shift = true 
where id in (
  'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', -- يوسف رسمي شعبان
  '7d879f2d-b4d4-4da0-93d6-14e542e7fef3'  -- عبدالله رمضان عبدالله أحمد أيوب
);

create or replace function public.is_employee_split_shift(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1 from public.employees 
    where id = p_employee_id and is_split_shift = true
  ) or coalesce(p_employee_id in (
    'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6',
    '7d879f2d-b4d4-4da0-93d6-14e542e7fef3'
  ), false);
$fn$;

-- ─── 5) دالة تجميع دقائق العمل الفعلي للفترات (خصم فترات الراحة) ───────────
create or replace function public.calculate_paired_work_minutes(
  p_employee_id uuid,
  p_start timestamptz,
  p_end timestamptz
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  with ordered_events as (
    select 
      event_type,
      event_at,
      lead(event_type) over (order by event_at) as next_type,
      lead(event_at) over (order by event_at) as next_at
    from public.attendance_events
    where employee_id = p_employee_id
      and event_at >= p_start
      and event_at < p_end
      and status in ('accepted', 'adjusted')
  )
  select coalesce(sum(
    greatest(0, floor(extract(epoch from (next_at - event_at)) / 60)::integer)
  ), 0)
  from ordered_events
  where event_type = 'CHECK_IN' and next_type = 'CHECK_OUT';
$fn$;

-- ─── 6) تحديث record_attendance_event لدعم الفترات المرنة وحساب الفترتين ──
CREATE OR REPLACE FUNCTION public.record_attendance_event(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_biometric_method text DEFAULT 'passkey'::text,
  p_selfie_path text DEFAULT NULL::text,
  p_passkey_credential_id uuid DEFAULT NULL::uuid,
  p_verified boolean DEFAULT false,
  p_is_mock boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_tz text;
  v_local_time time;
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
  v_max_accuracy numeric;
  v_actual_work_minutes integer := 0;
begin
  -- 0) الإعدادات المركزية
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  -- 1) التحقق من صلاحية الخادم الموثوق
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- 2) التحققات الأساسية
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

  -- 3) التحقق من الجهاز
  if p_passkey_credential_id is null or not exists (
    select 1
    from public.passkey_credentials
    where id = p_passkey_credential_id
      and employee_id = p_employee_id
      and status = 'active'
      and trusted = true
  ) then
    raise exception 'attendance_device_not_trusted' using errcode = '28000';
  end if;

  -- 4) حارس البصمة المكررة
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- 5) استعلام الوردية من الجدول أو التعيين
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

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- إذا لم تُسند وردية معينة، تُطابق الوردية المرنة تلقائياً من الفترات الثلاث
  if v_shift.id is null then
    select * into v_shift from public.shifts
    where id = public.match_flexible_shift(v_now);
  end if;

  -- 6) الوردية الليلية
  if v_local_time < '12:00:00'::time then
    declare
      v_yest_date date := v_work_date - 1;
      v_yest_shift public.shifts%rowtype;
      v_yest_shift_id uuid;
      v_has_open_yesterday boolean := false;
    begin
      select rd.shift_id into v_yest_shift_id
      from public.roster_days rd
      join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_yest_date
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last
      limit 1;

      if v_yest_shift_id is null then
        select sa.shift_id into v_yest_shift_id
        from public.shift_assignments sa
        where sa.employee_id = p_employee_id
          and sa.is_active = true
          and sa.effective_from <= v_yest_date
          and (sa.effective_to is null or sa.effective_to >= v_yest_date)
        order by sa.effective_from desc
        limit 1;
      end if;

      if v_yest_shift_id is not null then
        select * into v_yest_shift from public.shifts where id = v_yest_shift_id;
        if v_yest_shift.crosses_midnight then
          select true into v_has_open_yesterday
          from public.attendance_daily ad
          where ad.employee_id = p_employee_id
            and ad.work_date = v_yest_date
            and ad.first_check_in is not null
            and ad.last_check_out is null
            and ad.is_finalized = false;

          if v_has_open_yesterday then
            v_work_date := v_yest_date;
            v_crosses_midnight := true;
            v_shift := v_yest_shift;
            select rd.shift_id, rd.geofence_id
              into v_roster_shift_id, v_roster_geofence_id
            from public.roster_days rd
            join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
            where rd.employee_id = p_employee_id
              and rd.work_date = v_yest_date
              and rd.day_status = 'scheduled'
            order by wr.published_at desc nulls last
            limit 1;

            select * into v_assignment
            from public.shift_assignments sa
            where sa.employee_id = p_employee_id
              and sa.is_active = true
              and sa.effective_from <= v_yest_date
              and (sa.effective_to is null or sa.effective_to >= v_yest_date)
            order by sa.effective_from desc
            limit 1;
          end if;
        end if;
      end if;
    end;
  end if;

  -- 7) حدود اليوم
  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  -- 8) حارس الفترة المغلقة
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- 9) فحص التسلسل
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

  -- 10) حارس السفر المستحيل
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
    if v_travel is not null and (v_travel / v_gap_seconds) > v_impossible_speed then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- 11) النطاق الجغرافي
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  if v_geofence.id is null then
    select * into v_geofence from public.geofences
    where is_active = true
    order by created_at
    limit 1;
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

  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- 12) حساب التأخير لأول بصمة حضور في اليوم فقط
  if p_event_type = 'CHECK_IN' and not exists (
    select 1 from public.attendance_events ae_prev
    where ae_prev.employee_id = p_employee_id
      and ae_prev.event_type = 'CHECK_IN'
      and ae_prev.status in ('accepted', 'adjusted')
      and ae_prev.event_at >= v_period_start
      and ae_prev.event_at < v_period_end
  ) then
    begin
      v_late := public.attendance_policy_late_minutes(p_employee_id, v_work_date, v_now, v_shift.id);
    exception when others then
      v_late := 0;
    end;
  end if;

  -- 13) إدراج الحدث
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

  -- 14) تجميع السجل اليومي (attendance_daily) مع حساب ساعات العمل الفعلية للفترات
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
    and status in ('accepted', 'adjusted');

  -- حساب ساعات العمل الفعلي بتجميع الفترات وخصم الراحة
  v_actual_work_minutes := public.calculate_paired_work_minutes(p_employee_id, v_period_start, v_period_end);
  if v_actual_work_minutes = 0 and v_first_check_in is not null and v_last_check_out is not null then
    v_actual_work_minutes := greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer);
  end if;

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id, v_shift.id),
    v_first_check_in, v_last_check_out,
    v_actual_work_minutes,
    v_late,
    case
      when v_first_check_in is null then 'partial'
      when v_late > 0 then 'late'
      else 'present'
    end,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(attendance_daily.shift_id, excluded.shift_id),
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

  -- 15) تحديث آخر استخدام للجهاز
  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  -- 16) سجل التدقيق
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'shiftCode', v_shift.code,
      'lateMinutes', v_late,
      'pairedWorkMinutes', v_actual_work_minutes
    )
  );

  return v_event_id;
end;
$function$;

-- ─── 7) تحديث get_my_attendance_state لدعم حالة الوردية المجزأة ───────────
CREATE OR REPLACE FUNCTION public.get_my_attendance_state(p_installation_id text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_active boolean;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_local_devices integer := 0;
  v_local_device_status text := null;
  v_current_device_status text := null;
  v_current_device_active boolean := false;
  v_passkeys integer := 0;
  v_suggested text := 'CHECK_IN';
  v_last public.attendance_events%rowtype;
  v_today_status text;
  v_can_punch boolean := false;
  v_today_check_in timestamptz;
  v_today_check_out timestamptz;
  v_mission jsonb := null;
  v_m_id uuid;
  v_m_type text;
  v_m_start_time text;
  v_m_exec text;
  v_m_started timestamptz;
  v_m_ended timestamptz;
  v_m_auto boolean := false;
  v_cutoff time;
  v_is_executive boolean := false;
  v_is_split boolean := false;
  v_check_in_count integer := 0;
begin
  select e.id, (e.status='active' and not e.is_deleted)
    into v_me, v_active
  from public.employees e
  where e.user_id = auth.uid()
  limit 1;

  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired',false,
      'selfPunchEnabled',false,
      'canPunch',false,
      'suggestedAction','NONE',
      'error','employee_not_found'
    );
  end if;

  v_is_executive := public.is_employee_attendance_exempt(v_me);
  v_is_split := public.is_employee_split_shift(v_me);

  select count(*),
         coalesce(bool_or(p.status = 'active' and p.trusted), false)
    into v_local_devices, v_can_punch
  from public.passkey_credentials p
  where p.employee_id = v_me and p.user_id = auth.uid();

  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    select p.status, (p.status = 'active' and p.trusted)
      into v_current_device_status, v_current_device_active
    from public.passkey_credentials p
    where p.employee_id = v_me
      and p.user_id = auth.uid()
      and p.installation_id = trim(p_installation_id)
    order by p.created_at desc
    limit 1;
    v_local_device_status := v_current_device_status;
  else
    select p.status into v_local_device_status
    from public.passkey_credentials p
    where p.employee_id = v_me and p.user_id = auth.uid()
    order by p.created_at desc limit 1;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id=v_me and p.user_id=auth.uid()
    and p.status='active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_IN'
    and status in ('accepted', 'adjusted');

  if v_last.id is not null and v_last.event_type = 'CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  elsif v_last.id is not null and v_last.event_type = 'CHECK_OUT' then
    if v_is_split and v_check_in_count < 2 then
      v_suggested := 'CHECK_IN';
    else
      v_suggested := 'DAY_COMPLETED';
    end if;
  else
    v_suggested := 'CHECK_IN';
  end if;

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_IN'
    and status in ('accepted', 'adjusted')
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_OUT'
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  -- المأموريات
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         x.exec_status, x.started_at, x.ended_at
    into v_m_id, v_m_type, v_m_start_time, v_m_exec, v_m_started, v_m_ended
    from public.requests r
    left join lateral (
      select m.status as exec_status, m.started_at, m.ended_at
        from public.mission_executions m
       where m.request_id = r.id
       order by m.created_at desc
       limit 1
    ) x on true
   where r.employee_id = v_me
     and r.status = 'approved'
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
   order by x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id=v_me and d.work_date=v_today;
    end if;

    if v_last.id is null then
      if v_m_exec is null then
        v_suggested := 'MISSION_START';
      elsif v_m_exec = 'in_progress' then
        v_suggested := 'MISSION_IN_PROGRESS';
      elsif v_m_exec = 'completed' then
        if v_m_auto then
          v_suggested := 'DAY_COMPLETED';
        elsif v_today_check_in is not null then
          v_suggested := 'CHECK_OUT';
        else
          v_suggested := 'CHECK_IN';
        end if;
      end if;
    elsif v_m_exec = 'completed' and v_m_auto and v_today_check_out is not null then
      v_suggested := 'DAY_COMPLETED';
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'execStatus', coalesce(v_m_exec, 'approved'),
      'startTime', v_m_start_time,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', v_m_auto
    );
  end if;

  v_can_punch := v_active and not v_is_executive and (
    case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
         then v_current_device_active
         else v_local_devices > 0
    end
  );
  if v_suggested in ('MISSION_START','MISSION_IN_PROGRESS','DAY_COMPLETED') then
    v_can_punch := false;
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_can_punch,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'missionToday',v_mission,
    'isSplitShift',v_is_split,
    'checkInCount',v_check_in_count,
    'lastUpdatedAt',now()
  );
end;
$function$;

-- ─── 8) تحديث _build_attendance_statement_v287 لاحتساب فترات اليوم الفعلي ──
CREATE OR REPLACE FUNCTION public._build_attendance_statement_v287(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_type text;
  v_check_in time;
  v_check_out time;
  v_work_minutes integer;
  v_required_minutes integer;
  v_scheduled boolean;
  v_present boolean;
  v_covered boolean;
  v_is_future boolean;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_covered_days integer := 0;
  v_total_work_minutes integer := 0;
  v_month_required_minutes integer := 0;
  v_month_deficit_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_open_shift_days integer := 0;
  v_completed_days integer := 0;
  v_absent_days integer := 0;
  v_upcoming_days integer := 0;
  v_leave_days integer := 0;
  v_mission_days integer := 0;
  v_convoy_days integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  v_due_days integer := 0;
  v_is_due boolean;
  v_is_open boolean;
  v_shift_name text;
begin
  v_result := public._build_attendance_statement_v266(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_override := null;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    v_type := coalesce(v_override.day_type, '');
    v_check_in := nullif(v_day_obj->>'checkIn', '')::time;
    v_check_out := nullif(v_day_obj->>'checkOut', '')::time;
    v_shift_name := v_day_obj->>'shiftName';

    if v_override.id is not null then
      if v_override.clear_check_in then v_check_in := null;
      elsif v_override.check_in_override is not null then v_check_in := v_override.check_in_override;
      end if;
      if v_override.clear_check_out then v_check_out := null;
      elsif v_override.check_out_override is not null then v_check_out := v_override.check_out_override;
      end if;
    end if;

    -- الجمعة والعطل الرسمية ليست أيام عمل شهرية
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_type not in ('holiday','rest');
    v_is_future := v_scheduled and v_day > (now() at time zone 'Africa/Cairo')::date;

    if v_type in ('leave','mission','convoy','fundraising','holiday','rest','absent') then
      v_check_in := null;
      v_check_out := null;
    end if;

    -- حساب ساعات العمل الفعلي بتجميع الفترات واستبعاد الراحة
    v_work_minutes := public.calculate_paired_work_minutes(
      p_employee_id,
      (v_day::text || ' 00:00:00 Africa/Cairo')::timestamptz,
      (v_day::text || ' 23:59:59 Africa/Cairo')::timestamptz
    );

    -- احتياطي في حال عدم وجود أحداث مسجلة في attendance_events (مثل الإدخال اليدوي القديم)
    if v_work_minutes = 0 and v_check_in is not null and v_check_out is not null then
      v_work_minutes := greatest(0, (extract(epoch from (
        (v_day + v_check_out + case when v_check_out <= v_check_in then interval '1 day' else interval '0' end)
        - (v_day + v_check_in)
      )) / 60)::integer);
    end if;

    v_required_minutes := case when v_scheduled
      then greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60)::integer)
      else 0 end;
    if v_scheduled and v_required_minutes = 0 then v_required_minutes := 480; end if;

    v_present := v_scheduled and v_check_in is not null;
    v_covered := v_scheduled and (
      v_present
      or coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      or v_type in ('leave','mission','convoy','fundraising')
    );

    v_is_open := v_check_in is not null and v_check_out is null and not v_is_future;
    v_is_due := v_scheduled and not v_is_future and not v_is_open;

    if v_scheduled then
      v_scheduled_days := v_scheduled_days + 1;
      v_month_required_minutes := v_month_required_minutes + v_required_minutes;
      if v_is_due then
        v_due_days := v_due_days + 1;
        if v_work_minutes < v_required_minutes and not v_covered then
          v_month_deficit_minutes := v_month_deficit_minutes + (v_required_minutes - v_work_minutes);
        end if;
      end if;
      if v_present then
        v_present_days := v_present_days + 1;
        if v_check_out is not null then
          v_completed_days := v_completed_days + 1;
        end if;
      end if;
      if v_covered then v_covered_days := v_covered_days + 1; end if;
      if v_is_open then v_open_shift_days := v_open_shift_days + 1; end if;
      if not v_is_future and not v_covered and not v_is_open then
        v_absent_days := v_absent_days + 1;
      end if;
    end if;

    if v_is_future then v_upcoming_days := v_upcoming_days + 1; end if;
    if coalesce((v_day_obj->>'hasLeave')::boolean, false) or v_type = 'leave' then
      v_leave_days := v_leave_days + 1;
    end if;
    if coalesce((v_day_obj->>'hasMission')::boolean, false) or v_type = 'mission' then
      v_mission_days := v_mission_days + 1;
    end if;
    if coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or v_type in ('convoy','fundraising') then
      v_convoy_days := v_convoy_days + 1;
    end if;
    if not v_scheduled and (extract(isodow from v_day) = 5 or v_type = 'rest') then
      v_rest_days := v_rest_days + 1;
    elsif not v_scheduled then
      v_holiday_days := v_holiday_days + 1;
    end if;

    v_total_work_minutes := v_total_work_minutes + v_work_minutes;
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce((v_day_obj->>'overtimeMinutes')::integer, 0);
    v_total_late_minutes := v_total_late_minutes + coalesce((v_day_obj->>'lateMinutes')::integer, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce((v_day_obj->>'earlyLeaveMinutes')::integer, 0);

    -- مطابقة اسم الوردية إن كان فارغاً ووجد حضور
    if (v_shift_name is null or v_shift_name = '' or v_shift_name = '—') and v_check_in is not null then
      select s.name into v_shift_name
      from public.shifts s
      where s.id = public.match_flexible_shift((v_day + v_check_in)::timestamp at time zone 'Africa/Cairo');
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'checkIn', case when v_check_in is not null then to_char(v_check_in, 'HH24:MI') else null end,
      'checkOut', case when v_check_out is not null then to_char(v_check_out, 'HH24:MI') else null end,
      'workHours', round((v_work_minutes / 60.0)::numeric, 2),
      'shiftName', coalesce(v_shift_name, v_day_obj->>'shiftName')
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  return jsonb_set(v_result, '{days}', v_days);
end;
$function$;

commit;
