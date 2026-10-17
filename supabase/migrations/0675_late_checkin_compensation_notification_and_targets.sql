-- Migration 0675: إشعار فوري ذكي واقتراح تعويض التأخير عند تسجيل الحضور
-- ==============================================================================
-- متطلبات الميزة:
-- 1) عند تسجيل الموظف حضوراً متأخراً (سواء بحضور محلي بيومتري أو تسجيل غرامة):
--    - يصله إشعار فوري يوضح:
--      • وقت حضوره الدقيق (مثلاً: 10:23 ص).
--      • دقائق التأخير والغرامة/الخصم المقدر (مثلاً: تأخير 23 دقيقة - خصم 20 ج.م).
--      • اقتراح ذكي بموعد الانصراف المستهدف (مثلاً: 06:23 م) لتكملة 8 ساعات عمل.
--      • توضيح أنه إذا استكمل الـ 8 ساعات وسجل انصرافه، تسقط الغرامة وتلغى تلقائياً!
-- 2) تحديث get_my_attendance_state لإرجاع:
--    • todayCheckInTime (نص 12 ساعة: "10:23 ص")
--    • targetCheckoutAt (تاريخ ووقت timestamptz)
--    • targetCheckoutTime (نص 12 ساعة: "06:23 م")
--    • compensationRemainingMinutes (دقائق العمل المتبقية لإتمام 8 ساعات)
--    • estimatedLatePenaltyAmount (مبلغ الغرامة المقدرة)
--    • isCompensationEligible (هل هو متأخر ولديه فرصة تعويض)
--    • isCompensationCompleted (هل أتم 8 ساعات وبانتظار بصمة الانصراف)
-- 3) تحديث generate_instant_penalty لتضمين وقت الحضور وموعد الانصراف المقترح في نص الإشعار.
-- ==============================================================================

begin;

-- ─── 1) تحديث record_attendance_local_biometric لإرسال إشعار الاقتراح الذكي فورياً عند الحضور المتأخر ──
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
  v_impossible_speed constant double precision := 55.5;
  v_max_accuracy constant double precision := 100.0;
  v_requires_review boolean := false;
  v_notes text := '';
  v_calc_work_minutes integer := 0;
  v_calc_overtime_minutes integer := 0;
  v_calc_status text := 'present';

  -- متغيرات الإشعار والاقتراح الذكي للتعويض
  v_check_in_time_str text;
  v_target_checkout timestamptz;
  v_target_checkout_str text;
  v_penalty_amount numeric(12,2) := 0;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'location_required' using errcode = '22023';
  end if;
  if p_is_mock then
    raise exception 'mock_location_forbidden' using errcode = '22023';
  end if;

  select s.timezone into v_tz
  from public.attendance_settings s
  where s.singleton_key;
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date  := (v_now at time zone v_tz)::date;

  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
  limit 1;

  select sa.* into v_assignment
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

  -- استعلام آخر حدث حضور مع الـ fallback لسجل attendance_daily
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;

  if v_last_event_type is null then
    select case
      when ad.last_check_out is not null then 'CHECK_OUT'
      when ad.first_check_in is not null then 'CHECK_IN'
      else null
    end into v_last_event_type
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_work_date;
  end if;

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

  -- التحقق من النطاق الجغرافي مع استثناء الانصراف الميداني للمأموريات
  if v_distance > v_geofence.radius_meters then
    if p_event_type = 'CHECK_OUT' and (
      exists (
        select 1 from public.mission_executions me
         where me.employee_id = p_employee_id
           and me.status in ('in_progress', 'completed')
           and (me.started_at at time zone 'Africa/Cairo')::date = v_work_date
      ) or exists (
        select 1 from public.requests r
         where r.employee_id = p_employee_id
           and r.status in ('approved', 'pending')
           and r.request_type in ('mission', 'convoy', 'fundraising')
           and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                               and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
      )
    ) then
      v_notes := 'mission_field_checkout';
    else
      raise exception 'attendance_outside_complex' using errcode = '22023';
    end if;
  end if;

  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- حساب التأخير عند تسجيل أول حضور
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

  -- إدراج حدث الحضور/الانصراف
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

  -- تجميع بيانات الحضور اليومي في attendance_daily
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
    and status in ('accepted', 'adjusted');

  v_calc_work_minutes := case
    when v_first_check_in is not null and v_last_check_out is not null
    then greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer)
    else 0 end;

  v_calc_overtime_minutes := case
    when v_calc_work_minutes > 480 then v_calc_work_minutes - 480
    else 0 end;

  v_calc_status := case
    when v_first_check_in is null then 'partial'
    -- إذا أتم 8 ساعات عمل تختفي كلمة متأخر فوراً ويصبح حاضر:
    when v_calc_work_minutes >= 480 then 'present'
    when v_late > 0 then 'late'
    else 'present'
  end;

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, overtime_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id, public.match_flexible_shift(v_first_check_in)),
    v_first_check_in, v_last_check_out,
    v_calc_work_minutes,
    v_late,
    v_calc_overtime_minutes,
    v_calc_status,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(excluded.shift_id, attendance_daily.shift_id),
    first_check_in = coalesce(excluded.first_check_in, attendance_daily.first_check_in),
    last_check_out = coalesce(excluded.last_check_out, attendance_daily.last_check_out),
    work_minutes = excluded.work_minutes,
    overtime_minutes = excluded.overtime_minutes,
    late_minutes = greatest(attendance_daily.late_minutes, excluded.late_minutes),
    status = case
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      -- إذا استوفى 8 ساعات عمل (480 دقيقة) تختفي صفة التأخير فوراً ويتحول إلى حاضر:
      when excluded.work_minutes >= 480 then 'present'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now();

  -- عند تسجيل أول حضور وكان هناك تأخير: إرسال إشعار فوري ذكي مع اقتراح التعويض الدقيق
  if p_event_type = 'CHECK_IN' and v_late > 0 then
    begin
      v_penalty_amount := public.calc_instant_penalty_amount(least(120, v_late));
      v_check_in_time_str := to_char(v_now at time zone v_tz, 'FMHH12:MI') ||
                             case when (v_now at time zone v_tz)::time < '12:00' then ' ص' else ' م' end;
      v_target_checkout := v_now + interval '8 hours';
      v_target_checkout_str := to_char(v_target_checkout at time zone v_tz, 'FMHH12:MI') ||
                               case when (v_target_checkout at time zone v_tz)::time < '12:00' then ' ص' else ' م' end;

      if v_penalty_amount > 0 then
        perform public.notify_employee(
          p_employee_id,
          '⏰ تسجيل حضور متأخر — فرصة تعويض الغرامة',
          'سُجّل حضورك اليوم في تمام الساعة ' || v_check_in_time_str || ' (تأخير ' || v_late || ' دقيقة — غرامة مقررة ' || v_penalty_amount || ' ج.م).' || chr(10) ||
          '💡 فرصة التعويض: إذا استكملت 8 ساعات عمل حتى الساعة ' || v_target_checkout_str || ' وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!',
          'system',
          'high',
          'instant_penalty',
          v_event_id,
          jsonb_build_object(
            'channel', 'attendance',
            'promptType', 'late_checkin_compensation_proposal',
            'checkInTime', v_check_in_time_str,
            'targetCheckoutTime', v_target_checkout_str,
            'lateMinutes', v_late,
            'penaltyAmount', v_penalty_amount,
            'deepLink', 'ahlashabab://action/attendance'
          )
        );
      else
        -- ضمن فترة السماح (أول 15 دقيقة)
        perform public.notify_employee(
          p_employee_id,
          '⏰ تسجيل حضور (فترة السماح الرسمية)',
          'سُجّل حضورك اليوم في تمام الساعة ' || v_check_in_time_str || ' (تأخير ' || v_late || ' دقيقة ضمن فترة السماح الرسمية — بدون أي غرامة).' || chr(10) ||
          '💡 موعد إتمام 8 ساعات عمل هو الساعة ' || v_target_checkout_str || '، وسجل بصمة انصرافك حينها.',
          'system',
          'normal',
          'attendance',
          v_event_id,
          jsonb_build_object(
            'channel', 'attendance',
            'checkInTime', v_check_in_time_str,
            'targetCheckoutTime', v_target_checkout_str,
            'lateMinutes', v_late,
            'penaltyAmount', 0,
            'deepLink', 'ahlashabab://action/attendance'
          )
        );
      end if;
    exception when others then
      raise warning 'Notification for late checkin proposal failed: %', sqlerrm;
    end;
  end if;

  -- عند تسجيل الانصراف: إغلاق أي مأمورية جارية لليوم تلقائياً وفحص إسقاط الغرامة
  if p_event_type = 'CHECK_OUT' then
    update public.mission_executions
       set status = 'completed',
           ended_at = coalesce(ended_at, v_now),
           actual_minutes = greatest(1, round(extract(epoch from (v_now - started_at)) / 60)::integer),
           report = coalesce(report, 'تم تسجيل الانصراف وتوثيق إنهاء المأمورية بنجاح'),
           updated_at = v_now
     where employee_id = p_employee_id
       and status = 'in_progress'
       and (started_at at time zone 'Africa/Cairo')::date = v_work_date;

    -- تشغيل فحص إسقاط الغرامة التلقائي عند استيفاء 8 ساعات عمل
    begin
      perform public.auto_waive_penalty_if_completed_eight_hours(p_employee_id, v_work_date);
    exception when others then
      raise warning 'auto waive check skipped on checkout: %', sqlerrm;
    end;
  end if;

  return v_event_id;
end;
$function$;

revoke all on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role;
comment on function public.record_attendance_local_biometric is
  '0675: تسجيل الحضور البيومتري مع إشعار فوري ذكي يوضح وقت الحضور الفعلي وموعد الانصراف المقترح لإسقاط الغرامة عند إتمام 8 ساعات.';


-- ─── 2) تحديث generate_instant_penalty لتضمين وقت الحضور الفعلي وموعد الانصراف المقترح في الإشعار ──
create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_effective_late_minutes integer;
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
  v_exempt jsonb;
  v_check_in timestamptz;
  v_check_in_str text;
  v_target_checkout timestamptz;
  v_target_checkout_str text;
  v_notice_body text;
begin
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

  -- 2. التحقق من وجود الموظف
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

  -- استعلام وقت الحضور الفعلي لاحتساب موعد الانصراف المقترح (8 ساعات)
  select ad.first_check_in into v_check_in
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id and ad.work_date = p_work_date;

  if v_check_in is null then
    select ae.event_at into v_check_in
      from public.attendance_events ae
     where ae.employee_id = p_employee_id
       and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
       and ae.event_type = 'CHECK_IN'
       and ae.status in ('accepted', 'adjusted')
     order by ae.event_at asc
     limit 1;
  end if;

  if v_check_in is not null then
    v_check_in_str := to_char(v_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                      case when (v_check_in at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;
    v_target_checkout := v_check_in + interval '8 hours';
    v_target_checkout_str := to_char(v_target_checkout at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                             case when (v_target_checkout at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;

    v_notice_body := 'سُجّل حضورك في تمام الساعة ' || v_check_in_str || ' بتأخير ' || v_effective_late_minutes || ' دقيقة (غرامة: ' || v_amount || ' ج.م).' || chr(10) ||
                     '💡 فرصة التعويض: إذا استكملت 8 ساعات عمل حتى الساعة ' || v_target_checkout_str || ' وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!';
  else
    v_notice_body := 'تم تسجيل غرامة تأخير على ' || v_emp_name || ' بمبلغ ' || v_amount || ' ج.م (' || case when v_effective_late_minutes >= 120 then 'ساعتان — الحد الأقصى' else v_effective_late_minutes || ' دقيقة' end || ' تأخير). يمكنك تعويضها باستكمال 8 ساعات عمل من وقت حضورك وتسجيل بصمة الانصراف.';
  end if;

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

    if v_row.status = 'pending_payment' and v_amount > v_row.current_amount then
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
        v_notice_body,
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'penaltyId', v_row.id::text,
          'lateMinutes', v_effective_late_minutes,
          'originalAmount', v_amount,
          'currentAmount', v_amount,
          'channel', 'instant_penalty',
          'checkInTime', v_check_in_str,
          'targetCheckoutTime', v_target_checkout_str,
          'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
        )
      );
    elsif v_row.status = 'pending_payment'
          and v_effective_late_minutes > coalesce(v_row.late_minutes, 0) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;
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
    '⚠️ تسجيل غرامة تأخير حضور فورية — فرصة تعويض',
    v_notice_body,
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'penaltyId', v_row.id::text,
      'lateMinutes', v_effective_late_minutes,
      'originalAmount', v_amount,
      'currentAmount', v_amount,
      'channel', 'instant_penalty',
      'checkInTime', v_check_in_str,
      'targetCheckoutTime', v_target_checkout_str,
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

revoke all on function public.generate_instant_penalty(uuid, date, integer, text) from public, anon;
grant execute on function public.generate_instant_penalty(uuid, date, integer, text) to authenticated, service_role;
comment on function public.generate_instant_penalty(uuid, date, integer, text) is
  '0675: تسجيل الغرامة مع إشعار تفصيلي يوضح وقت الحضور الفعلي وموعد الانصراف المقترح للتعويض.';


-- ─── 3) تحديث get_my_attendance_state لإرجاع بيانات وقت الانصراف المستهدف واقتراح التعويض ──
create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                    uuid;
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_is_split              boolean := false;
  v_hash                  text;
  v_last                  record;
  v_check_in_count        integer := 0;
  v_today_check_in        timestamptz;
  v_today_check_out       timestamptz;
  v_shift_end             timestamptz;
  v_local_device_status   text := 'not_registered';
  v_today_status          text;
  v_suggested             text;
  v_passkeys              integer;
  v_local_devices         integer;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_mission               jsonb := null;
  v_m_id                  uuid;
  v_m_type                text;
  v_m_start_time          text;
  v_m_exec                text;
  v_m_started             timestamptz;
  v_m_ended               timestamptz;
  v_cutoff                time;
  v_m_auto                boolean;
  v_work_minutes          integer := 0;
  v_overtime_minutes      integer := 0;

  -- بيانات اقتراح التعويض والغرامة
  v_late_minutes          integer := 0;
  v_penalty_amount        numeric(12,2) := 0;
  v_active_penalty_amt    numeric(12,2);
  v_check_in_str          text := null;
  v_target_checkout       timestamptz := null;
  v_target_checkout_str   text := null;
  v_comp_remaining        integer := 0;
begin
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'no_employee_linked'
    );
  end if;

  if public.is_employee_attendance_exempt(v_me) then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'executive_exempt'
    );
  end if;

  v_is_split := coalesce(public.is_employee_split_shift(v_me), false);

  select count(*) into v_local_devices
  from public.employee_devices ed
  where ed.employee_id = v_me
    and ed.user_id = auth.uid()
    and ed.status = 'active';

  if coalesce(v_local_devices, 0) = 0 then
    select count(*) into v_local_devices
    from public.managed_devices md
    where md.user_id = auth.uid()
      and md.employee_id = v_me
      and md.platform in ('android', 'ios')
      and md.status = 'active';
  end if;

  if p_installation_id is not null and trim(p_installation_id) <> '' then
    v_hash := encode(digest(trim(p_installation_id), 'sha256'), 'hex');

    if exists (
      select 1 from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
        and ed.status = 'active'
    ) or exists (
      select 1 from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'active'
    ) then
      select ed.status into v_current_device_status
      from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
      order by ed.created_at desc
      limit 1;

      if v_current_device_status = 'active' then
        v_current_device_active := true;
      end if;
    else
      select md.status into v_current_device_status
      from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
      limit 1;

      if v_current_device_status is null then
        v_current_device_status := 'not_registered';
      end if;
    end if;
  end if;

  if v_local_devices > 0 then
    v_local_device_status := 'active';
  elsif v_current_device_status is not null then
    v_local_device_status := v_current_device_status;
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id = v_me and p.user_id = auth.uid()
    and p.status = 'active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  select status, work_minutes, overtime_minutes, late_minutes
    into v_today_status, v_work_minutes, v_overtime_minutes, v_late_minutes
  from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted');

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted')
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_OUT'
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  if v_today_check_in is null then
    select d.first_check_in into v_today_check_in
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

  if v_today_check_out is null then
    select d.last_check_out into v_today_check_out
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

  -- حساب دقائق العمل الحية والوقت الإضافي
  if v_today_check_in is not null and v_today_check_out is not null then
    v_work_minutes := greatest(coalesce(v_work_minutes, 0), floor(extract(epoch from (v_today_check_out - v_today_check_in)) / 60)::integer);
  elsif v_today_check_in is not null and v_today_check_out is null then
    v_work_minutes := greatest(coalesce(v_work_minutes, 0), floor(extract(epoch from (now() - v_today_check_in)) / 60)::integer);
  end if;

  if v_work_minutes > 480 then
    v_overtime_minutes := v_work_minutes - 480;
  else
    v_overtime_minutes := coalesce(v_overtime_minutes, 0);
  end if;

  -- إذا استوفى الموظف 8 ساعات عمل تختفي كلمة متأخر فوراً ويصبح حاضراً
  if v_work_minutes >= 480 and v_today_status = 'late' then
    v_today_status := 'present';
  end if;

  -- حساب موعد الانصراف المستهدف وبيانات اقتراح التعويض
  if v_today_check_in is not null then
    v_check_in_str := to_char(v_today_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                      case when (v_today_check_in at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;
    v_target_checkout := v_today_check_in + interval '8 hours';
    v_target_checkout_str := to_char(v_target_checkout at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                             case when (v_target_checkout at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;
    v_comp_remaining := greatest(0, 480 - coalesce(v_work_minutes, 0));

    v_late_minutes := coalesce(v_late_minutes, v_last.late_minutes, 0);
    v_penalty_amount := public.calc_instant_penalty_amount(least(120, v_late_minutes));

    -- فحص إذا كانت هناك غرامة فعلية مسجلة لليوم
    select p.current_amount into v_active_penalty_amt
      from public.instant_attendance_penalties p
     where p.employee_id = v_me
       and p.work_date = v_today
       and p.status in ('pending_payment', 'doubled', 'suspended');

    if v_active_penalty_amt is not null and v_active_penalty_amt > 0 then
      v_penalty_amount := v_active_penalty_amt;
    end if;
  end if;

  -- فحص المأموريات والأنشطة اليوم
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         coalesce(x.exec_status, case when r.status = 'approved' then 'approved' else 'pending' end),
         x.started_at, x.ended_at
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
     and r.status in ('approved', 'pending')
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                     and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
   order by case when r.status = 'approved' then 1 else 2 end,
            x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null and v_m_ended is not null then
      v_today_check_out := v_m_ended;
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'startTime', v_m_start_time,
      'execStatus', v_m_exec,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', coalesce(v_m_auto, false)
    );
  end if;

  -- حسم الإجراء المقترح (suggestedAction)
  if v_today_check_out is not null and (not v_is_split or v_check_in_count >= 2) then
    v_suggested := 'DAY_COMPLETED';
  elsif v_today_check_out is not null and v_is_split and v_check_in_count < 2 then
    v_suggested := 'CHECK_IN';
  elsif v_today_check_in is not null or (v_last.id is not null and v_last.event_type = 'CHECK_IN') then
    v_suggested := 'CHECK_OUT';
  elsif v_m_id is not null and v_m_exec in ('approved', 'pending') and v_last.id is null and v_today_check_in is null then
    v_suggested := 'MISSION_START';
  else
    v_suggested := 'CHECK_IN';
  end if;

  if v_today_status is null or v_today_status = '' then
    if v_m_id is not null and v_m_exec in ('approved', 'in_progress', 'completed') then
      v_today_status := case v_m_type
        when 'convoy' then 'convoy'
        when 'fundraising' then 'fundraising'
        when 'mission' then 'mission'
        else 'mission'
      end;
    elsif exists (
      select 1 from public.requests r
      where r.employee_id = v_me
        and r.status = 'approved'
        and r.request_type = 'leave'
        and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                        and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
    ) then
      v_today_status := 'on_leave';
    elsif v_today_check_in is not null or v_last.id is not null then
      if v_work_minutes >= 480 then
        v_today_status := 'present';
      elsif coalesce(v_last.status, '') = 'late' or coalesce(v_last.late_minutes, 0) > 0 then
        v_today_status := 'late';
      else
        v_today_status := 'present';
      end if;
    elsif extract(dow from v_today) = 5 then
      v_today_status := 'weekend';
    elsif exists (select 1 from public.public_holidays where holiday_date = v_today) then
      v_today_status := 'holiday';
    elsif (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then
      v_today_status := 'absent';
    else
      v_today_status := 'not_recorded';
    end if;
  end if;

  select (v_today::text || ' ' || coalesce(s.shift_end_time, time '17:00')::text)::timestamptz
  into v_shift_end
  from public.attendance_settings s where s.singleton_key;

  return jsonb_build_object(
    'attendanceRequired', true,
    'selfPunchEnabled', true,
    'canPunch', true,
    'todayStatus', v_today_status,
    'workMinutes', coalesce(v_work_minutes, 0),
    'overtimeMinutes', coalesce(v_overtime_minutes, 0),
    'lastEventType', v_last.event_type,
    'lastEventAt', v_last.event_at,
    'lastEventStatus', v_last.status,
    'suggestedAction', v_suggested,
    'hasPasskeys', v_passkeys > 0,
    'passkeysCount', v_passkeys,
    'hasActiveLocalDevice', coalesce(v_local_devices, 0) > 0,
    'activeLocalDevicesCount', coalesce(v_local_devices, 0),
    'currentDeviceActive', v_current_device_active,
    'currentDeviceStatus', v_current_device_status,
    'localDeviceStatus', v_local_device_status,
    'todayCheckInAt', v_today_check_in,
    'todayCheckOutAt', v_today_check_out,
    'shiftEndTime', v_shift_end,
    'isSplitShift', v_is_split,
    'checkInCount', v_check_in_count,
    'missionToday', v_mission,
    -- حقول الاقتراح الذكي للتعويض وإسقاط الغرامة
    'lateMinutes', coalesce(v_late_minutes, 0),
    'estimatedLatePenaltyAmount', coalesce(v_penalty_amount, 0),
    'todayCheckInTime', v_check_in_str,
    'targetCheckoutAt', v_target_checkout,
    'targetCheckoutTime', v_target_checkout_str,
    'compensationRemainingMinutes', coalesce(v_comp_remaining, 0),
    'isCompensationEligible', (coalesce(v_late_minutes, 0) > 0 or coalesce(v_penalty_amount, 0) > 0),
    'isCompensationCompleted', (coalesce(v_work_minutes, 0) >= 480 and (coalesce(v_late_minutes, 0) > 0 or coalesce(v_penalty_amount, 0) > 0))
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;
comment on function public.get_my_attendance_state(text) is
  '0675: إرجاع الحالة مع بيانات الاقتراح الذكي للتعويض وموعد الانصراف المستهدف لإسقاط الغرامة.';


-- ─── 4) تحديث tg_attendance_daily_notify_manager لتضمين وقت الحضور وموعد الانصراف المقترح والغرامة ──
create or replace function public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
  v_first text;
  v_exec_emp uuid;
  v_title text;
  v_body text;

  -- متغيرات التعويض والغرامة
  v_target_out timestamptz;
  v_target_out_str text;
  v_penalty numeric(12,2) := 0;
  v_self_title text;
  v_self_body text;
  v_priority text := 'normal';
begin
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;
  v_first := coalesce(nullif(split_part(coalesce(v_emp_ar, ''), ' ', 1), ''), 'موظف');

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'FMHH12:MI'
  ) || case when extract(hour from (
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end;

  if v_event = 'attendance_check_in' then
    v_target_out := new.first_check_in + interval '8 hours';
    v_target_out_str := to_char(v_target_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                        case when (v_target_out at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;

    if coalesce(new.late_minutes, 0) > 15 then
      v_penalty := public.calc_instant_penalty_amount(least(120, new.late_minutes));
      v_self_title := '⏰ تسجيل حضور متأخر — فرصة تعويض الغرامة';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة — خصم مقرر ' || v_penalty || ' ج.م).' || chr(10) ||
                      '💡 اقتراح ذكي: إذا استكملت 8 ساعات عمل حتى الساعة ' || v_target_out_str || ' وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!';
      v_priority   := 'high';
    elsif coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '⏰ تسجيل حضور (فترة السماح الرسمية)';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة ضمن فترة السماح 15 دقيقة — بدون أي غرامة).' || chr(10) ||
                      '💡 موعد إتمام 8 ساعات عمل هو الساعة ' || v_target_out_str || ' وسجل انصرافك حينها.';
      v_priority   := 'normal';
    else
      v_self_title := '✅ تم تسجيل حضورك بنجاح';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' بموعدك المنضبط.' || chr(10) ||
                      '💡 موعد نهاية الـ 8 ساعات هو الساعة ' || v_target_out_str || '.';
      v_priority   := 'normal';
    end if;

    v_title := format('وصل %s للعمل بالمجمع', v_first);
    v_body  := format(
      'دخل الساعة %s%s',
      v_time,
      case when coalesce(new.late_minutes, 0) > 0 then format(' (تأخير %s دقيقة)', new.late_minutes) else '' end
    );
  else
    -- checkout
    if coalesce(new.work_minutes, 0) >= 480 and coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '🎉 تم تسجيل انصرافك وإسقاط غرامة التأخير';
      v_self_body  := 'سُجّل انصرافك في تمام الساعة ' || v_time || '. لقد استوفيت 8 ساعات عمل كاملة بنجاح، وتم إلغاء غرامة التأخير الصباحي وإسقاط الخصم بالكامل!';
      v_priority   := 'high';
    else
      v_self_title := 'تم تسجيل انصرافك';
      v_self_body  := format('تم تسجيل انصرافك الساعة %s', v_time);
      v_priority   := 'normal';
    end if;

    v_title := format('خرج %s من المجمع', v_first);
    v_body  := format(
      'انصرف الساعة %s (إجمالي العمل: %s دقيقة%s)',
      v_time,
      coalesce(new.work_minutes, 0),
      case when coalesce(new.overtime_minutes, 0) > 0 then format(' — إضافي: +%s د', new.overtime_minutes) else '' end
    );
  end if;

  -- إشعار الموظف نفسه بالصيغة الذكية المفصلة
  perform public.notify_employee(
    new.employee_id,
    v_self_title,
    v_self_body,
    'attendance', v_priority, 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time,
      'lateMinutes', new.late_minutes,
      'workMinutes', new.work_minutes,
      'overtimeMinutes', new.overtime_minutes,
      'targetCheckoutTime', v_target_out_str,
      'penaltyAmount', v_penalty,
      'deepLink', 'ahlashabab://action/attendance'
    )
  );

  -- إشعار المدير المباشر
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null and v_manager <> new.employee_id then
    perform public.notify_employee(
      v_manager,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- إشعار المدير التنفيذي
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null and v_exec_emp <> new.employee_id then
    perform public.notify_employee(
      v_exec_emp,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'normal', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'time', v_time
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  '0675: إشعار فوري ذكي عند الحضور يوضح موعد الانصراف المقترح والغرامة وإسقاطها عند إتمام 8 ساعات.';

commit;

