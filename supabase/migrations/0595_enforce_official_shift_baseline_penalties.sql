-- =====================================================================
-- 0595: اعتماد الدوام الأساسي (10:00 ص – 6:00 م) كمعيار عام وتطبيق الغرامات فوراً بعد 10:15 ص
--
--  بناءً على توجيه الإدارة (2026-10-03):
--  1) الدوام الأساسي (OFFICIAL: 10:00 ص إلى 06:00 م) هو المعيار العام لجميع الموظفين.
--  2) فترة السماح 15 دقيقة (تنتهي 10:15 ص)، وتبدأ الغرامات فوراً بعد 10:15 ص لكل من لم يبصم.
--  3) قصر وردية (11 ص – 7 م) على من لديه إسناد إداري مسبق فقط (shift_assignments أو roster_days)؛
--     ولا تُمنح تلقائياً عند التأخر في الحضور.
--  4) الحضور حتى 09:15 ص يطابق الوردية الصباحية (9 ص – 5 م)، ومابعدها يتبع الدوام الأساسي (10 ص – 6 م).
-- =====================================================================

begin;

-- ─── 1) تحديث دالة مطابقة الوردية المرنة (match_flexible_shift) ──────────
create or replace function public.match_flexible_shift(p_check_in timestamptz)
returns uuid
language plpgsql
stable security definer
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
  
  -- 1) حضور حتى 09:15 ص -> الوردية الصباحية (9 ص – 5 م)
  -- 2) حضور بعد 09:15 ص -> الدوام الأساسي المعتمد (10 ص – 6 م)
  -- (ملاحظة: وردية 11 ص - 7 م مقتصرة على الإسناد المسبق فقط ولا تُمنح تلقائياً)
  if v_time <= '09:15:00'::time then
    v_shift_code := 'SHIFT_9_5';
  else
    v_shift_code := 'OFFICIAL';
  end if;

  select id into v_shift_id
  from public.shifts
  where code = v_shift_code and is_active
  limit 1;

  return coalesce(v_shift_id, public.default_shift_id());
end;
$fn$;

comment on function public.match_flexible_shift(timestamptz) is
  '0595: مطابقة الحضور حتى 9:15 للوردية الصباحية وما بعدها للدوام الأساسي (10 ص - 6 م) مع قصر وردية 11 ص على الإسناد المسبق.';

-- ─── 2) تحديث دالة توليد الغرامات التلقائية (auto_generate_instant_penalties) ───
create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_now_cairo::date;
  v_time_cairo time := v_now_cairo::time;
  v_isodow integer := extract(isodow from v_now_cairo)::integer;
  v_elapsed_mins integer;
  v_processed integer := 0;
  v_emp record;
  v_att record;
  v_penalty_minutes integer;
  v_notes text;
  v_exempt jsonb;
  v_pen record;
  v_flex_start time;
  v_flex_grace integer;
  v_start time;
  v_grace integer;
  v_start_label text;
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1. استثناء عطلة الجمعة
  if v_isodow = 5 then
    return 0;
  end if;

  -- 2. استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة لموظفين لديهم إذن أو مأمورية أو إجازة معتمدة لذلك اليوم
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
       and p.work_date >= v_today - 3
  loop
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_pen.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             updated_at = now()
       where id = v_pen.id;

      -- رفع التعليق إن لم تكن هناك غرامات مضاعفة أخرى غير معفى منها
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = v_pen.employee_id
           and status in ('doubled', 'suspended')
           and id != v_pen.id
      ) then
        update public.employees set is_active = true, status = 'active' where id = v_pen.employee_id;
        update public.profiles set status = 'active' where employee_id = v_pen.employee_id;
      end if;
    end if;
  end loop;

  -- 4. 0595: الدوام الأساسي المعتمد هو المعيار العام (10:00 ص مع 15 دقيقة سماح حتى 10:15 ص)
  select s.start_time, coalesce(s.grace_in_minutes, 15)
    into v_flex_start, v_flex_grace
    from public.shifts s
   where s.is_active and s.code = 'OFFICIAL'
   limit 1;
  if v_flex_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_flex_start, v_flex_grace
      from public.shifts s
     where s.id = public.default_shift_id();
  end if;
  v_flex_start := coalesce(v_flex_start, '10:00'::time);
  v_flex_grace := coalesce(v_flex_grace, 15);

  -- 5. فحص الموظفين: يشمل جميع الموظفين النشطين، وكذلك من حضر اليوم وسجل بصمة متأخرة
  for v_emp in
    select e.id as employee_id, e.full_name_ar, e.is_active, e.status as emp_status
      from public.employees e
     where coalesce(e.is_deleted, false) = false
       and (
         e.is_active = true
         or exists (
           select 1 from public.attendance_daily ad
            where ad.employee_id = e.id
              and ad.work_date = v_today
         )
       )
  loop
    -- فحص الإعفاء اليومي المعتمد (إذن حضور، إجازة، مأمورية، قافلة)
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    -- فحص سجل الحضور اليومي للموظف
    v_att := null;
    select ad.id, ad.status, ad.late_minutes, ad.first_check_in into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today
     limit 1;

    -- إذا كانت حالة السجل تشير إلى إجازة أو مأمورية أو عذر رسمي
    if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- الحالة أ: الموظف بصم حضوراً ولديه تأخير فعلي أكثر من فترة السماح
    if v_att.id is not null and v_att.first_check_in is not null then
      if coalesce(v_att.late_minutes, 0) > 15 then
        -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى)
        v_penalty_minutes := least(120, coalesce(v_att.late_minutes, 0));
        v_notes := case
          when coalesce(v_att.late_minutes, 0) >= 120 then
            'تأخير حضور فعلي تجاوز ساعتين (حُصر عند الحد الأقصى 120 دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
          else
            'تأخير حضور فعلي (' || v_penalty_minutes || ' دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
        end;

        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
      continue;
    end if;

    -- الحالة ب: لم يسجل بصمة حضور بعد.
    -- لا غرامة لحساب غير نشط (معلّق، أو مدعوّ لم يفعّل حسابه فلا يستطيع البصم)
    if v_emp.is_active = false or v_emp.emp_status is distinct from 'active' then
      continue;
    end if;

    -- بداية ورديته المسندة إن وُجدت (بما فيها وردية 11 ص أو 9 ص)، وإلا الدوام الأساسي (10 ص مع سماح 15 دقيقة)
    v_start := null;
    v_grace := null;
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_start, v_grace
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_emp.employee_id
       and sa.is_active
       and sa.effective_from <= v_today
       and (sa.effective_to is null or sa.effective_to >= v_today)
     order by sa.effective_from desc
     limit 1;

    if v_start is null then
      select s.start_time, coalesce(s.grace_in_minutes, 15)
        into v_start, v_grace
        from public.roster_days rd
        join public.shifts s on s.id = rd.shift_id
        join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
       where rd.employee_id = v_emp.employee_id
         and rd.work_date = v_today
         and rd.day_status = 'scheduled'
       order by wr.published_at desc nulls last
       limit 1;
    end if;

    v_start := coalesce(v_start, v_flex_start);
    v_grace := coalesce(v_grace, v_flex_grace);

    v_elapsed_mins := floor(extract(epoch from (v_time_cairo - v_start)) / 60)::integer;
    if v_elapsed_mins <= v_grace then
      continue;
    end if;

    v_start_label := to_char(v_start, 'FMHH12:MI') || case when v_start < '12:00'::time then ' ص' else ' م' end;
    -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى)
    v_penalty_minutes := least(120, v_elapsed_mins);
    v_notes := case
      when v_elapsed_mins >= 120 then
        'تأخير عن بداية الوردية (' || v_start_label || ') — حُصر عند الحد الأقصى ساعتان (120 دقيقة) لعدم تسجيل البصمة حتى الآن'
      else
        'تأخير عن بداية الوردية (' || v_start_label || ') — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')'
    end;

    perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

comment on function public.auto_generate_instant_penalties() is
  '0595: فرض غرامات التأخير التلقائية بعد 10:15 ص على كل من لم يبصم وفق الدوام الأساسي ما لم يكن مسنداً لوردية أخرى صراحة.';

-- ─── 3) تحديث تسجيل الحضور المحلي البيومتري لحفظ الوردية المطابقة ───────────
-- نضمن تحديث shift_id في attendance_daily عند البصمة
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
set search_path to 'public', 'pg_temp'
as $function$
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
  v_notes text := 'inside_complex_local_biometric';
  v_max_accuracy numeric;
begin
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

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

  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

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

  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

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

  -- 11) Late calculation
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

  -- 13) Aggregate attendance_daily
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
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id, public.match_flexible_shift(v_first_check_in)),
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

-- ─── 4) تشغيل توليد الغرامات التلقائية لليوم الحالي (2026-10-03) ──────────────
select public.auto_generate_instant_penalties();

commit;
