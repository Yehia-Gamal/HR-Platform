-- =====================================================================
-- 0586: تفعيل حساب التأخير عند البصمة حسب اللائحة (بقرار الإدارة 2026-09-30)
--
-- السبب الجذري: record_attendance_event لا يحسب التأخير إلا إن وُجدت وردية مسندة
-- (roster/shift_assignments)، ولا توجد إسنادات لأي موظف → كل 800 سجل حضور منذ
-- البداية late_minutes = 0 وحالة 'late' لم تُسجَّل قط. فكانت كل الشاشات والتقارير
-- تُظهر «0 تأخير» وانضباطاً 100%، ولم تعمل غرامة البصمة ولا تنبيه المدير.
--
-- التعريف — مصدر واحد للبصمة والغرامة وكشف الحضور (attendance_policy_late_minutes):
--  • وردية الموظف المسندة، وإلا الوردية الرسمية (OFFICIAL 10:00–18:00، سماح 15 د).
--  • التأخير = الدقائق من بداية الوردية إذا تجاوزت فترة السماح، بحد أقصى 120
--    (اللائحة 0576/0584: 10:16–10:30 = 20 ج.م ...).
--  • لأول بصمة حضور في اليوم فقط؛ كانت كل بصمة حضور تُحسب فبصمة ثانية الساعة 1
--    بعد انصراف كانت ستُسجَّل «تأخير ساعتين» وتُغرَّم.
--  • صفر للمعذور بقواعد إعفاء الغرامة نفسها (is_employee_exempt_from_instant_penalty):
--    الجمعة والعطلات، الإجازات والمأموريات والقوافل والفاندي والعمل عن بعد
--    والأذونات (مقدّمة أو معتمدة — غير المرفوضة/الملغاة)، والتعديل الإداري لليوم،
--    والمعفى من البصمة. المعفى من الغرامات فقط (طاقم العيادات) يُحسب تأخيره.
--
-- إصلاح حرج قبل التفعيل: generate_instant_penalty يرفض أي جلسة ليست مدير غرامات،
-- وتريجر البصمة يستدعيه داخل جلسة الموظف → كانت كل بصمة متأخرة ستفشل برسالة
-- «غير مسموح» (ثبت بمحاكاة). الآن: السماح من التريجر فقط، والغرامة لا تُفشل البصمة.
--
-- بأثر رجعي: late_minutes/الحالة لكل السجلات السابقة (مع وقت الحضور المعدّل
-- إدارياً) دون تشغيل أي تريجر (session_replication_role = replica داخل هذه
-- المعاملة فقط) → لا غرامات ولا إشعارات عن الأيام الماضية.
-- =====================================================================

begin;

-- ─── 1) أدوات مساعدة ────────────────────────────────────────────────────
create or replace function public.try_cast_date(p_text text)
returns date
language plpgsql
immutable
set search_path = public, pg_temp
as $fn$
begin
  if p_text is null or p_text !~ '^\d{4}-\d{2}-\d{2}' then
    return null;
  end if;
  return left(p_text, 10)::date;
exception when others then
  return null;
end
$fn$;

create or replace function public.default_shift_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select id from public.shifts
  where is_active
  order by (code = 'OFFICIAL') desc, created_at
  limit 1;
$fn$;

-- ─── 2) هل التأخير في هذا اليوم معذور؟ (قواعد إعفاء الغرامة ليومها) ──────
create or replace function public.is_lateness_excused(p_employee_id uuid, p_work_date date)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.is_employee_attendance_exempt(p_employee_id)
    or extract(isodow from p_work_date) = 5
    or exists (
      select 1 from public.public_holidays h
      where coalesce(h.is_active, true)
        and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
    or exists (
      select 1 from public.attendance_day_overrides o
      where o.employee_id = p_employee_id and o.work_date = p_work_date and o.is_active
        and o.day_type in ('leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest'))
    or exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id and ad.work_date = p_work_date and ad.status = 'on_leave')
    or exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and p_work_date between lr.start_date and lr.end_date)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
        and coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'),
                     public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                     public.try_cast_date(r.payload->>'workDate'), r.created_at::date) = p_work_date)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave',
                                'mission', 'external_mission', 'administrative_mission',
                                'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi',
                                'remote_work', 'compensation')
             or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission'))
        and p_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                            and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                         public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')));
$fn$;

-- ─── 3) دقائق التأخير بتعريف اللائحة ────────────────────────────────────
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
begin
  if p_check_in is null or public.is_lateness_excused(p_employee_id, p_work_date) then
    return 0;
  end if;
  select * into v_shift from public.shifts where id = coalesce(p_shift_id, public.default_shift_id());
  if v_shift.id is null or v_shift.start_time is null then
    return 0;
  end if;
  v_diff := floor(extract(epoch from (
    p_check_in - ((p_work_date + v_shift.start_time)::timestamp at time zone 'Africa/Cairo')
  )) / 60)::integer;
  return case when v_diff > coalesce(v_shift.grace_in_minutes, 0) then least(v_diff, 120) else 0 end;
end
$fn$;

do $revoke$
begin
  revoke execute on function public.default_shift_id() from public, anon;
  revoke execute on function public.is_lateness_excused(uuid, date) from public, anon, authenticated;
  revoke execute on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) from public, anon, authenticated;
  grant execute on function public.is_lateness_excused(uuid, date) to service_role;
  grant execute on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) to service_role;
end
$revoke$;

-- ─── 4) البصمة: حساب التأخير ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_attendance_event(p_employee_id uuid, p_event_type text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_biometric_method text DEFAULT 'passkey'::text, p_selfie_path text DEFAULT NULL::text, p_passkey_credential_id uuid DEFAULT NULL::uuid, p_verified boolean DEFAULT false, p_is_mock boolean DEFAULT false)
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
  -- Night shift / period boundaries
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
  -- Accuracy fallback
  v_max_accuracy numeric;
begin
  -- 0) Read centralized settings
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  -- 1) Service-role guard
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- 2) Basic validations
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

  -- 3) Passkey verification
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

  -- 4) Duplicate guard (60-second window)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- 5) Roster + shift assignment lookup (moved before sequencing for period computation)
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

  -- Load shift
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- 6) Night-shift detection: if local time < 12:00, check yesterday for crosses_midnight shift
  if v_local_time < '12:00:00'::time then
    declare
      v_yest_date date := v_work_date - 1;
      v_yest_shift public.shifts%rowtype;
      v_yest_shift_id uuid;
      v_has_open_yesterday boolean := false;
    begin
      -- Check yesterday's roster first
      select rd.shift_id into v_yest_shift_id
      from public.roster_days rd
      join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_yest_date
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last
      limit 1;

      -- Fallback to shift_assignments for yesterday
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
          -- Check if there's an open attendance_daily for yesterday (check-in but no check-out)
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
            -- Re-lookup roster/assignment for yesterday
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

  -- 7) Compute period boundaries

  -- 0460: ::timestamp صريح قبل at time zone؛ date وحدها تُرقّى
  -- إلى timestamptz عبر منطقة الجلسة فتنزلق النافذة (نفس علة 0169/0201).
  if v_crosses_midnight and v_shift.id is not null then
    -- Night shift: period = work_date+start_time → (work_date+1)+end_time
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    -- Day shift or no shift: full calendar day
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  -- 8) Finalized-period guard
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- 9) Sequencing check (period-based instead of date-based)
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

  -- 10) Impossible-travel guard (configurable speed from settings)
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

  -- 11) Geofence lookup + validation
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  -- *** FALLBACK (0201): إذا لم يُعثر على سياج عبر الجدول أو التعيين،
  -- يُؤخذ أول سياج نشط (مناسب لمنظمة ذات موقع واحد) ***
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

  -- Accuracy fallback chain: geofence.max_accuracy → settings → 100
  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- 12) Late calculation
  if p_event_type = 'CHECK_IN' and not exists (
    select 1 from public.attendance_events ae_prev
    where ae_prev.employee_id = p_employee_id
      and ae_prev.event_type = 'CHECK_IN'
      and ae_prev.status in ('accepted', 'adjusted')
      and ae_prev.event_at >= v_period_start
      and ae_prev.event_at < v_period_end
  ) then
    -- 0586: الوردية المسندة أو الرسمية الافتراضية (لم تُسند ورديات لأحد فلم يُحتسب
    -- تأخير قط)، بتعريف اللائحة، لأول بصمة حضور في اليوم فقط، وصفر للمعذور.
    -- حساب التأخير لا يُفشل البصمة أبداً.
    begin
      v_late := public.attendance_policy_late_minutes(p_employee_id, v_work_date, v_now, v_shift.id);
    exception when others then
      v_late := 0;
    end;
  end if;

  -- 13) Insert event
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

  -- 14) Aggregate attendance_daily (period-based)
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

  -- 15) Update passkey last_used
  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  -- 16) Audit log
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_crosses_midnight,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_attendance_local_biometric(p_employee_id uuid, p_event_type text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false)
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
  -- Night shift / period boundaries
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
  -- Accuracy fallback
  v_max_accuracy numeric;
begin
  -- 0) Read centralized settings
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  -- 1) Service-role guard (current_user check for biometric path)
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- 2) Basic validations
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

  -- 3) Duplicate guard (60-second window)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- 4) Roster + shift assignment lookup (moved before sequencing)
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

  -- Load shift
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- 5) Night-shift detection
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

  -- 6) Compute period boundaries

  -- 0460: ::timestamp صريح قبل at time zone؛ date وحدها تُرقّى
  -- إلى timestamptz عبر منطقة الجلسة فتنزلق النافذة (نفس علة 0169/0201).
  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  -- 7) Finalized-period guard
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- 8) Impossible-travel guard (configurable speed)
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

  -- 9) Sequencing check (period-based)
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;
  if p_event_type = 'CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  -- 10) Geofence lookup + validation
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  -- *** FALLBACK (0201): إذا لم يُعثر على سياج عبر الجدول أو التعيين،
  -- يُؤخذ أول سياج نشط (مناسب لمنظمة ذات موقع واحد) ***
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
  -- Accuracy fallback chain: geofence.max_accuracy → settings → 100
  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- 11) Late calculation
  if p_event_type = 'CHECK_IN' and not exists (
    select 1 from public.attendance_events ae_prev
    where ae_prev.employee_id = p_employee_id
      and ae_prev.event_type = 'CHECK_IN'
      and ae_prev.status in ('accepted', 'adjusted')
      and ae_prev.event_at >= v_period_start
      and ae_prev.event_at < v_period_end
  ) then
    -- 0586: الوردية المسندة أو الرسمية الافتراضية (لم تُسند ورديات لأحد فلم يُحتسب
    -- تأخير قط)، بتعريف اللائحة، لأول بصمة حضور في اليوم فقط، وصفر للمعذور.
    -- حساب التأخير لا يُفشل البصمة أبداً.
    begin
      v_late := public.attendance_policy_late_minutes(p_employee_id, v_work_date, v_now, v_shift.id);
    exception when others then
      v_late := 0;
    end;
  end if;

  -- 12) Insert event
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

  -- 13) Aggregate attendance_daily (period-based)
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

  -- 14) Audit log
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة محلية موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', 'local_biometric',
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_crosses_midnight,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$function$;

-- ─── 5) الغرامة عند البصمة: السماح من التريجر ولا تُفشل البصمة ─────────────
CREATE OR REPLACE FUNCTION public.generate_instant_penalty(p_employee_id uuid, p_work_date date, p_late_minutes integer, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_effective_late_minutes integer;
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
  v_exempt jsonb;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح). 0586: الاستدعاء من تريجر
  -- البصمة (pg_trigger_depth() > 0) يجري داخل جلسة الموظف فكان هذا الفحص يرفضه
  -- ويُفشل البصمة؛ الاستدعاء المباشر من الواجهات ما زال يتطلب الصلاحية.
  if auth.uid() is not null
     and pg_trigger_depth() = 0
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- 1. فحص الإعفاء الشامل المعتمد لذلك اليوم
  v_exempt := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى من غرامات الحضور والانصراف: ' || (v_exempt->>'reason')
    );
  end if;

  -- 2. التحقق من وجود الموظف (دون اشتراط is_active للسماح بتسجيل غرامة من حضر متأخراً في اليوم 2 أو 3)
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and coalesce(is_deleted, false) = false;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- 3. حصر دقائق التأخير عند 120 دقيقة كحد أقصى (ساعتان فقط)
  v_effective_late_minutes := least(120, greatest(1, p_late_minutes));
  v_amount := public.calc_instant_penalty_amount(v_effective_late_minutes);

  -- إذا كان التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15 = 0 ج.م)
  if v_amount <= 0.00 then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isGracePeriod', true,
      'amount', 0,
      'message', 'التأخير ضمن فترة السماح الرسمية (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة'
    );
  end if;

  v_default_notes := coalesce(p_notes, case
    when v_effective_late_minutes >= 120 then 'تأخير بلغ ساعتين (حُصر عند الحد الأقصى 120 دقيقة)'
    else 'تأخير عن موعد العمل الرسمي (10:00 ص)'
  end);

  -- محاولة الإدخال
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, notes, created_by
  ) values (
    p_employee_id, p_work_date, v_effective_late_minutes,
    v_amount, v_amount, 'EGP',
    'pending_payment', 'initial', v_default_notes, auth.uid()
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- إذا كانت الغرامة مسجلة مسبقاً لهذا اليوم:
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    -- إذا كانت لا تزال قيد السداد وكان التأخير/المبلغ الجديد أكبر:
    if v_row.status = 'pending_payment' and (v_amount > v_row.current_amount or v_effective_late_minutes > coalesce(v_row.late_minutes, 0)) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        v_emp_name || ': تزايد التأخير إلى ' || case when v_effective_late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_effective_late_minutes || ' دقيقة' end || ' — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'penaltyId', v_row.id::text,
          'lateMinutes', v_effective_late_minutes,
          'originalAmount', v_amount,
          'currentAmount', v_amount,
          'channel', 'instant_penalty',
          'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
        )
      );
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'amount', v_row.current_amount,
      'status', v_row.status,
      'lateMinutes', v_row.late_minutes,
      'message', 'توجد غرامة مسجلة مسبقاً لهذا اليوم'
    );
  end if;

  -- إشعار أصحاب الشأن
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ تسجيل غرامة تأخير حضور فورية',
    'تم تسجيل غرامة تأخير على ' || v_emp_name || ' بمبلغ ' || v_amount || ' ج.م (' || case when v_effective_late_minutes >= 120 then 'ساعتان — الحد الأقصى' else v_effective_late_minutes || ' دقيقة' end || ' تأخير). المهلة: نفس اليوم قبل المضاعفة إلى 500 ج.م غداً.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'penaltyId', v_row.id::text,
      'lateMinutes', v_effective_late_minutes,
      'originalAmount', v_amount,
      'currentAmount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'alreadyExists', false,
    'amount', v_amount,
    'status', 'pending_payment',
    'lateMinutes', v_effective_late_minutes,
    'message', 'تم تسجيل الغرامة الفورية بنجاح'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.trg_fn_instant_penalty_on_punch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_exempt jsonb;
begin
  if NEW.first_check_in is not null and coalesce(NEW.late_minutes, 0) > 15 then
    -- فحص الإعفاء أولاً
    v_exempt := public.is_employee_exempt_from_instant_penalty(NEW.employee_id, NEW.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      return NEW;
    end if;

    -- 0586: الغرامة لا تُفشل البصمة أبداً
    begin
      perform public.generate_instant_penalty(
        NEW.employee_id,
        NEW.work_date,
        NEW.late_minutes,
        'تأخير حضور فعلي: ' || NEW.late_minutes || ' دقيقة'
      );
    exception when others then
      raise warning 'instant penalty on punch skipped: %', sqlerrm;
    end;
  end if;
  return NEW;
end;
$function$;

-- ─── 6) كشف الحضور: التأخير من المصدر نفسه ──────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_late_grace constant integer := 15;   -- فترة السماح (0576)
  c_late_cap   constant integer := 120;  -- حد احتساب التأخير (0576)
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
  v_summary jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
  v_pending_permit boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
  v_is_exempt boolean;
  v_override_type text;
  v_scheduled boolean;
  v_on_leave boolean;
  v_offsite boolean;
  v_pending boolean;
  v_exempt_day boolean;
  v_waiting_today boolean;
  v_expected boolean;
  v_attended boolean;
  v_open_today boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_shift_start time;
  v_shift_end time;
  v_late integer;
  v_early integer;
  v_day_work integer;
  v_day_required integer;
  -- المجاميع
  v_pending_days integer := 0;
  v_expected_days integer := 0;
  v_attended_days integer := 0;
  v_offsite_days integer := 0;
  v_excl_leave integer := 0;
  v_excl_pending integer := 0;
  v_excl_exempt integer := 0;
  v_absent_days integer := 0;
  v_open_days integer := 0;
  v_missing_in_count integer := 0;
  v_missing_out_count integer := 0;
  v_hours_days integer := 0;
  v_required_minutes integer := 0;
  v_worked_minutes integer := 0;
  v_deficit_minutes integer := 0;
  v_late_total integer := 0;
  v_late_days integer := 0;
  v_early_total integer := 0;
  v_early_days integer := 0;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    continue when v_day_obj is null or v_day_obj = 'null'::jsonb;

    v_day := (v_day_obj->>'date')::date;
    v_ci := nullif(v_day_obj->>'checkIn', '');
    v_co := nullif(v_day_obj->>'checkOut', '');
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

    v_pending_leave := exists (
      select 1 from public.requests r
      join public.leave_requests lr on lr.request_id = r.id
      where lr.employee_id = p_employee_id
        and r.status = 'pending'
        and v_day between lr.start_date and lr.end_date
    );
    v_pending_mission := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy', 'fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_permit := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
        and r.status = 'pending'
        and coalesce(
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
          r.created_at::date
        ) = v_day
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه بصمة → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy or v_pending_permit)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        when v_pending_permit then 'بانتظار اعتماد إذن'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    if v_is_exempt and (v_status in ('غائب دون إذن', 'بانتظار حضور') or v_is_absent) then
      v_status := 'معفى من الحضور';
      v_is_absent := false;
    end if;

    -- adminOverride.leaveType
    if (v_day_obj->'adminOverride') is not null and (v_day_obj->'adminOverride') <> 'null'::jsonb then
      v_day_obj := jsonb_set(
        v_day_obj,
        '{adminOverride,leaveType}',
        coalesce(
          (v_day_obj->'adminOverride'->'leaveType'),
          to_jsonb((
            select o.leave_type
            from public.attendance_day_overrides o
            where o.employee_id = p_employee_id
              and o.work_date = v_day
              and o.is_active
            limit 1
          )),
          'null'::jsonb
        ),
        true
      );
    end if;

    -- ── تصنيف اليوم ──
    v_override_type := coalesce(v_day_obj->'adminOverride'->>'dayType', '');
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_override_type not in ('holiday', 'rest');
    v_on_leave := coalesce((v_day_obj->>'hasLeave')::boolean, false) and v_ci is null;
    v_offsite := coalesce((v_day_obj->>'hasMission')::boolean, false)
              or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_pending := v_status like 'بانتظار اعتماد%';
    v_exempt_day := v_status = 'معفى من الحضور';
    -- اليوم الجاري قبل نهاية الدوام بلا بصمة (v286: «بانتظار حضور») لا يُحتسب بعد
    v_waiting_today := v_day = v_today and v_ci is null and not v_is_absent and not v_offsite;
    v_expected := v_scheduled and v_day <= v_today and not v_on_leave and not v_pending
                  and not v_exempt_day and not v_waiting_today;
    v_attended := v_expected and (v_ci is not null or v_offsite);
    v_open_today := v_day = v_today and v_ci is not null and v_co is null;

    -- ── أعلام النقص من البيانات النهائية (بعد التعديلات الإدارية) ──
    v_missing_out := v_scheduled and v_day < v_today and v_ci is not null and v_co is null
                     and not v_offsite and not v_has_early_p and not v_pending_permit and not v_is_exempt;
    v_missing_in := v_scheduled and v_ci is null
                    and (v_co is not null or coalesce((v_day_obj->>'missingCheckIn')::boolean, false))
                    and not v_has_late_p and not v_pending_permit and not v_is_exempt;

    -- ── التأخير والخروج المبكر (أيام الدوام بالبصمة فقط) ──
    v_late := 0;
    v_early := 0;
    -- 0586: التأخير من الدالة نفسها التي تحسبه البصمة والغرامة (مصدر واحد)
    if v_ci is not null then
      begin
        v_late := public.attendance_policy_late_minutes(
          p_employee_id, v_day, ((v_day + v_ci::time)::timestamp at time zone 'Africa/Cairo'), null);
      exception when others then
        v_late := 0;
      end;
    end if;
    if v_scheduled and v_ci is not null and not v_offsite and not v_is_exempt and not v_pending_permit then
      v_shift_end := nullif(v_day_obj->>'shiftEnd', '')::time;
      if v_shift_end is not null and v_co is not null and not v_has_early_p
         and v_co::time > v_ci::time and v_co::time < v_shift_end then
        v_early := floor(extract(epoch from (v_shift_end - v_co::time)) / 60)::integer;
      end if;
    end if;

    -- ── الساعات: أيام الدوام المستحقة (والمأمورية إن اكتملت بصمتاها) ──
    v_day_work := greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer;
    v_day_required := greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60))::integer;
    if v_day_required = 0 then v_day_required := 480; end if;
    if v_expected and not v_open_today and (not v_offsite or (v_ci is not null and v_co is not null)) then
      v_hours_days := v_hours_days + 1;
      v_required_minutes := v_required_minutes + v_day_required;
      v_worked_minutes := v_worked_minutes + v_day_work;
      v_deficit_minutes := v_deficit_minutes + greatest(0, v_day_required - v_day_work);
    end if;

    -- ── المجاميع ──
    if v_scheduled and v_day <= v_today then
      if v_on_leave then v_excl_leave := v_excl_leave + 1;
      elsif v_pending then v_excl_pending := v_excl_pending + 1;
      elsif v_exempt_day then v_excl_exempt := v_excl_exempt + 1;
      end if;
    end if;
    if v_expected then
      v_expected_days := v_expected_days + 1;
      if v_attended then
        v_attended_days := v_attended_days + 1;
        if v_ci is null then v_offsite_days := v_offsite_days + 1; end if;
      end if;
    end if;
    if v_open_today then v_open_days := v_open_days + 1; end if;
    if v_missing_in then v_missing_in_count := v_missing_in_count + 1; end if;
    if v_missing_out then v_missing_out_count := v_missing_out_count + 1; end if;
    if v_late > 0 then v_late_total := v_late_total + v_late; v_late_days := v_late_days + 1; end if;
    if v_early > 0 then v_early_total := v_early_total + v_early; v_early_days := v_early_days + 1; end if;

    -- يوم ماضٍ بلا انصراف: v287 يسمّيه «بانتظار الانصراف» لكل الأيام
    if v_day < v_today and v_status = 'حاضر — بانتظار الانصراف' then
      v_status := case
        when v_has_early_p then 'حاضر (إذن انصراف)'
        when v_missing_out then 'حضور ناقص — لم يسجل الانصراف'
        else 'حاضر'
      end;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(v_day_work),
      'status', v_status
    )) || jsonb_build_object(
      'isAbsent', v_is_absent,
      'isDue', v_expected,
      'isOpenShift', v_open_today,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy,
      'hasPendingPermit', v_pending_permit,
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out,
      'lateMinutes', v_late,
      'earlyLeaveMinutes', v_early
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int from jsonb_array_elements(v_days) d
                    where coalesce((d->>'isAbsent')::boolean, false));

  v_summary := coalesce(v_result->'summary', '{}'::jsonb);
  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', v_summary || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'dueScheduledDays', v_expected_days,
      'openShiftDays', v_open_days,
      'missingCheckInCount', v_missing_in_count,
      'missingCheckOutCount', v_missing_out_count,
      'isAttendanceExempt', v_is_exempt,
      'attendanceRate', case when v_expected_days > 0
        then round(least(v_attended_days, v_expected_days) * 100.0 / v_expected_days, 2)
        else 0 end,
      'attendanceRateAvailable', v_expected_days > 0 and not v_is_exempt,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', least(v_attended_days, v_expected_days),
        'dueDays', v_expected_days,
        'presentDays', coalesce((v_summary->>'presentDays')::integer, 0),
        'offsiteDays', v_offsite_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_days,
        'upcomingDays', coalesce((v_summary->>'upcomingDays')::integer, 0),
        'excludedLeaveDays', v_excl_leave,
        'excludedPendingDays', v_excl_pending,
        'excludedExemptDays', v_excl_exempt,
        'basis', 'elapsed_workdays_excluding_leave_pending_exempt'
      ),
      'hoursComplianceAvailable', v_required_minutes > 0 and not v_is_exempt,
      'hoursComplianceRate', case when v_required_minutes > 0
        then least(100, round(v_worked_minutes * 100.0 / v_required_minutes, 2))
        else 0 end,
      'totalRequiredHours', round(v_required_minutes / 60.0, 2),
      'requiredMinutes', v_required_minutes,
      'compliantWorkMinutes', v_worked_minutes,
      'totalDeficitMinutes', v_deficit_minutes,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_worked_minutes,
        'requiredMinutes', v_required_minutes,
        'scheduledDays', v_hours_days,
        'deficitMinutes', v_deficit_minutes,
        'overtimeMinutes', coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0),
        'monthRequiredMinutes', coalesce((v_summary->'hoursRateBasis'->>'requiredMinutes')::integer, 0),
        'basis', 'elapsed_office_days'
      ),
      'totalLateMinutes', v_late_total,
      'lateDays', v_late_days,
      'totalEarlyLeaveMinutes', v_early_total,
      'earlyLeaveDays', v_early_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_summary->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(v_required_minutes),
      'totalDeficitFormatted', public._fmt_minutes_ar(v_deficit_minutes),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(v_late_total),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(v_early_total)
    )
  );

  return v_result;
end;
$function$;

-- ─── 7) بأثر رجعي دون تشغيل أي تريجر (لا غرامات ولا إشعارات عن الماضي) ────
set local session_replication_role = replica;

with first_in as (
  select ae.id, ae.employee_id, ae.event_at,
         (ae.event_at at time zone 'Africa/Cairo')::date as work_date,
         row_number() over (
           partition by ae.employee_id, (ae.event_at at time zone 'Africa/Cairo')::date
           order by ae.event_at) as rn
  from public.attendance_events ae
  where ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted')
), calc as (
  select id, case when rn = 1
                  then public.attendance_policy_late_minutes(employee_id, work_date, event_at, null)
                  else 0 end as late
  from first_in
)
update public.attendance_events ae
   set late_minutes = c.late
  from calc c
 where c.id = ae.id and ae.late_minutes is distinct from c.late;

with calc as (
  select ad.id,
         public.attendance_policy_late_minutes(
           ad.employee_id, ad.work_date,
           case
             when o.id is not null and o.clear_check_in then null
             when o.id is not null and o.check_in_override is not null
               then ((ad.work_date + o.check_in_override)::timestamp at time zone 'Africa/Cairo')
             else ad.first_check_in
           end,
           ad.shift_id) as late
  from public.attendance_daily ad
  left join public.attendance_day_overrides o
    on o.employee_id = ad.employee_id and o.work_date = ad.work_date and o.is_active
  where ad.first_check_in is not null or o.check_in_override is not null
)
update public.attendance_daily ad
   set late_minutes = c.late,
       status = case
         when ad.status = 'present' and c.late > 0 then 'late'
         when ad.status = 'late' and c.late = 0 then 'present'
         else ad.status end
  from calc c
 where c.id = ad.id
   and (ad.late_minutes is distinct from c.late
        or (ad.status = 'present' and c.late > 0)
        or (ad.status = 'late' and c.late = 0));

set local session_replication_role = origin;

commit;
