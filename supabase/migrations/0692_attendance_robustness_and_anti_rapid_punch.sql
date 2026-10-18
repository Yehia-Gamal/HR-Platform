-- ═══════════════════════════════════════════════════════════════
-- 0692: تعزيز متانة البصمة وحماية الحضور والانصراف اللحظي
-- 
-- يعالج هذا الملف المشاكل الثلاث الحرجة للإنتاج:
-- 1. فشل بصمة الحضور في الهواتف إلا بعد محاولات عديدة:
--    - إضافة سماحية 25 متراً إضافية على نصف قطر النطاق الجغرافي لحساب التذبذب الطبيعي لمستقبلات GPS بالهواتف.
--    - رفع الحد الأقصى المقبول لدقة الموقع إلى 150 متراً (بدلاً من 100م) لتمكين التسجيل داخل المكاتب والمباني دون رفض متكرر.
-- 2. منع تسجيل الحضور والانصراف في نفس اللحظة (الضغط المزدوج أو التداخل):
--    - إضافة حارس anti-rapid-punch: منع أي بصمة (حضور أو انصراف) خلال 30 ثانية من أي بصمة سابقة للموظف.
--    - إضافة حارس anti-instant-checkout: منع تسجيل الانصراف خلال أقل من دقيقتين (120 ثانية) من تسجيل الحضور لمنع الانصراف غير المقصود.
-- 3. تحديث قائمة v_known_errors في punch_attendance_local_biometric_v1 لمعالجة الأخطاء الجديدة برفق.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ─── 1) تحديث دالة تسجيل الحضور البيومتري المحلي ──────────────────────────────
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
  v_max_accuracy constant double precision := 150.0;
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

  -- ★ 1. حارس مكافحة البصم المتكرر السريع (خلال 30 ثانية من أي حدث سابق للموظف) ★
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_at > v_now - interval '30 seconds'
  ) then
    raise exception 'attendance_rapid_punch_rejected' using errcode = '22023';
  end if;

  -- ★ 2. حارس منع الانصراف الفوري (يمنع الانصراف قبل مضي دقيقتين على الأقل من الحضور) ★
  if p_event_type = 'CHECK_OUT' and exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = 'CHECK_IN'
      and ae.event_at > v_now - interval '2 minutes'
  ) then
    raise exception 'attendance_checkout_too_early' using errcode = '22023';
  end if;

  select s.timezone into v_tz
  from public.attendance_settings s
  where s.singleton_key;
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date  := (v_now at time zone v_tz)::date;

  -- استعلام الروستر المعتمد لليوم الحالي من جدول roster_days المربوط بـ work_rosters
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

  -- التحقق من النطاق الجغرافي مع سماحية 25 متراً لتذبذب الهواتف واستثناء الانصراف الميداني للمأموريات
  if v_distance > (v_geofence.radius_meters + 25.0) then
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

  -- سماحية دقة الموقع: حتى 150 متراً للهواتف داخل المباني والمكاتب
  if p_accuracy_meters > greatest(coalesce(v_geofence.max_accuracy, 100.0), 150.0) then
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
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role, authenticated;
comment on function public.record_attendance_local_biometric is 'يسجل الحضور أو الانصراف مع حماية ضد التكرار السريع وحماية ضد الانصراف الفوري وسماحية نطاق 25م ودقة 150م';

-- ─── 2) تحديث دالة RPC المحلية لدعم أكواد الحماية الجديدة ───────────────────
create or replace function public.punch_attendance_local_biometric_v1(
  p_operation_id uuid,
  p_event_type text,
  p_installation_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_hash text;
  v_managed public.managed_devices;
  v_employee_device public.employee_devices;
  v_operation public.local_attendance_operations;
  v_event_id uuid;
  v_event public.attendance_events;
  v_result jsonb;
  v_error text;
  v_verification_method text;
  v_waive_status jsonb;
  v_work_date date;
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required','invalid_attendance_location',
    'attendance_rapid_punch_rejected','attendance_checkout_too_early'
  ];
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode='42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode='22023';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if length(trim(coalesce(p_installation_id,'')))<12 then
    raise exception 'invalid_installation_id' using errcode='22023';
  end if;
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode='42501';
  end if;

  v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'managed_device_not_active',
      'replayed', false
    );
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'employee_device_not_active',
      'replayed', false
    );
  end if;

  v_verification_method := case
    when v_managed.biometric_available then 'local_biometric'
    else 'device_lock'
  end;

  insert into public.local_attendance_operations(
    operation_id,user_id,employee_id,event_type,credential_id
  ) values (p_operation_id,auth.uid(),v_employee_id,p_event_type,v_hash)
  on conflict (operation_id) do nothing;
  select * into v_operation from public.local_attendance_operations
  where operation_id=p_operation_id for update;
  if v_operation.user_id<>auth.uid()
     or v_operation.employee_id<>v_employee_id
     or v_operation.event_type<>p_event_type
     or v_operation.credential_id<>v_hash then
    raise exception 'attendance_idempotency_conflict' using errcode='22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result,'{}'::jsonb)
      || jsonb_build_object('replayed',true);
  end if;

  begin
    v_event_id := public.record_attendance_local_biometric(
      v_employee_id,p_event_type,p_latitude,p_longitude,
      p_accuracy_meters,p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error=any(v_known_errors) then
      v_result := jsonb_build_object('ok',false,'error',v_error,'replayed',false);
      update public.local_attendance_operations
      set status='rejected',result=v_result,completed_at=now()
      where operation_id=p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  update public.employee_devices set last_used_at=now()
  where id=v_employee_device.id;
  update public.managed_devices set last_seen_at=now()
  where id=v_managed.id;
  select * into v_event from public.attendance_events where id=v_event_id;

  v_work_date := (v_event.event_at at time zone 'Africa/Cairo')::date;

  -- عند الانصراف: جلب حالة الإلغاء لاستيفاء 8 ساعات إن وُجدت
  if p_event_type = 'CHECK_OUT' then
    v_waive_status := public.get_checkout_penalty_status(v_employee_id, v_work_date);
  end if;

  v_result := jsonb_build_object(
    'ok',true,'verified',true,
    'verificationMethod',v_verification_method,
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );

  if p_event_type = 'CHECK_OUT' and v_waive_status is not null and (v_waive_status->>'waived')::boolean = true then
    v_result := v_result || jsonb_build_object(
      'penaltyWaived', true,
      'waivedAmount', (v_waive_status->>'waived_amount')::numeric,
      'workMinutes', (v_waive_status->>'work_minutes')::integer,
      'message', v_waive_status->>'message',
      'checkIn', v_waive_status->>'check_in',
      'checkOut', v_waive_status->>'check_out'
    );
  end if;

  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;

  return v_result;
end;
$$;

revoke all on function public.punch_attendance_local_biometric_v1(uuid, text, text, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.punch_attendance_local_biometric_v1(uuid, text, text, double precision, double precision, double precision, boolean) to authenticated;
comment on function public.punch_attendance_local_biometric_v1 is 'RPC لتسجيل الحضور/الانصراف مع دعم معالجة أخطاء التكرار السريع والانصراف المبكر برفق';

commit;
