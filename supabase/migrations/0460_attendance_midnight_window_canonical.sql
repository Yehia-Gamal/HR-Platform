-- ============================================================================
-- 0460: تثبيت التعريفات القياسية لنافذة تجميع اليوم + ترميم إضافي محصّن
-- ============================================================================
-- سياق: 0458 أصلح المشكلة نفسها برقعة regex على pg_get_functiondef. هذا
-- الترحيل يثبّت الأجسام الكاملة صراحةً (بلا اعتماد على تطابق أنماط regex بين
-- البيئات)، ويعيد تطبيق نموذج الصلاحيات المعتمد (service_role فقط)، ويرمّم
-- صفوفًا متبقية بشروط محافظة (لا يمسّ إلا first_check_in الفارغ في صفوف غير
-- معتمدة).
--
-- البلاغ الأصلي: موظف سجّل البصمة الساعة 12 من منتصف الليل — ظهرت في سجل الأحداث
-- (attendance_events) لكنها لم تظهر في كشف اليوم (attendance_daily)، واستمر
-- وصول تذكيرات «لم تُسجَّل بصمتك» لأن first_check_in ظل فارغًا في الصف اليومي.
--
-- السبب الجذري (منذ 0169/0201): حساب حدود فترة اليوم العادي كان:
--     v_period_start := v_work_date::timestamptz at time zone v_tz;
-- التحويل المزدوج يفسد النتيجة عندما تكون TimeZone للجلسة UTC (افتراضي Supabase):
--     date::timestamptz              = منتصف الليل UTC
--     ... at time zone 'Africa/Cairo' = نص محلي بلا منطقة (03:00 صيفًا)
--     الإسناد لمتغير timestamptz     = يعيد تفسيره UTC → 06:00 صباحًا بالقاهرة!
-- فأصبحت نافذة اليوم [06:00، 06:00+1) بدل [00:00، 00:00+1) صيفًا (و[02:00، …)
-- شتاءً). أثر ذلك:
--   1) أي CHECK_IN بين 00:00 و06:00 (صيفًا) لا يدخل التجميع → صف يومي بحالة
--      partial بلا first_check_in رغم إدراج الحدث في attendance_events.
--   2) فحص التتابع (خطوة 9) يستخدم النافذة نفسها → انصراف الفجر يُرفض
--      بـ attendance_check_in_required.
--   3) generate_punch_reminders يقرأ الصف اليومي الناقص → تذكيرات مستمرة.
--
-- الصيغة الصحيحة: `date::timestamp at time zone tz` — تحويل صريح إلى timestamp
-- بلا منطقة أولًا ثم تفسيره كتوقيت المنطقة، فينتج منتصف ليل القاهرة الحقيقي
-- بغضّ النظر عن منطقة الجلسة (ملاحظة: `date at time zone` وحده لا يكفي — يرقّى
-- التاريخ إلى timestamptz عبر منطقة الجلسة فتعود الانزياحة نفسها).
-- ============================================================================

begin;

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
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
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
$$;
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
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
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
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) ترميم إضافي محصّن: صفوف آخر 60 يومًا غير المعتمدة ذات first_check_in فارغ
--    مع حدث check_in مقبول داخل نافذة القاهرة الصحيحة ليومها (فرع اليوم فقط —
--    ورديات الليل مستبعدة لأن حضورها يُحسب ضمن فترة الأمس).
--    لا يُكتب فوق أي قيمة قائمة ولا يمسّ الصفوف المعتمدة أو الإجازات/العيدين.
-- ═══════════════════════════════════════════════════════════════════════════
with targets as (
  select ad.id, ad.employee_id, ad.work_date
  from public.attendance_daily ad
  where ad.is_finalized = false
    and ad.first_check_in is null
    and ad.status not in ('on_leave', 'holiday', 'weekend')
    and (ad.shift_id is null or not exists (
          select 1 from public.shifts s
           where s.id = ad.shift_id and s.crosses_midnight))
    and not exists (
      select 1
      from public.attendance_daily yd
      join public.shifts ys on ys.id = yd.shift_id and ys.crosses_midnight
      where yd.employee_id = ad.employee_id
        and yd.work_date = ad.work_date - 1
        and yd.first_check_in is not null
        and yd.last_check_out is null)
    and ad.work_date >= (now() at time zone 'Africa/Cairo')::date - 60
),
heal as (
  select t.id,
         (select min(ae.event_at)
            from public.attendance_events ae
           where ae.employee_id = t.employee_id
             and ae.event_type = 'CHECK_IN'
             and ae.status in ('accepted', 'adjusted')
             and ae.event_at >= t.work_date::timestamp at time zone 'Africa/Cairo'
             and ae.event_at <  (t.work_date + 1)::timestamp at time zone 'Africa/Cairo') as ci
  from targets t
)
update public.attendance_daily ad
   set first_check_in = heal.ci,
       updated_at = now()
  from heal
 where ad.id = heal.id
   and heal.ci is not null;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) إعادة تطبيق نموذج الصلاحيات المعتمد (نمط 0201/0230): service_role فقط
-- ═══════════════════════════════════════════════════════════════════════════
revoke all on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) to service_role;

revoke all on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;

comment on function public.record_attendance_event(uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean) is 'تسجيل بصمة موثقة (0201) مع نافذة يوم مصححة 0460: date::timestamp at time zone';
comment on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) is 'بصمة البايومتري المحلي (0201) مع نافذة يوم مصححة 0460: date::timestamp at time zone';

commit;
