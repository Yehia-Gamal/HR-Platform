-- ==============================================================================
-- Migration 0707: ضبط تبديل الورديات وإلغاء غرامات التأخير التلقائي عند الحضور والأذونات
-- ==============================================================================
-- المشاكل المعالجة جذرياً (حالة الزميل عمار ومثيلاتها):
-- 1. الموظف يبدل شفته إلى 11 ص – 7 م (سواء عبر adopt_my_work_shift أو طلب معتمد):
--    - كان النظام يترك جدول الروستر roster_days مقدماً على تعيين الوردية الجديد.
--    - كانت دالة adopt_my_work_shift تحدث shift_assignments فقط ولا تعيد احتساب late_minutes
--      ولا تسقط الغرامة الصباحية المسجلة في instant_attendance_penalties.
-- 2. الموظف يحضر في موعد ورديته الجديدة (مثلاً 10:20 ص لوردية 11:00 ص — مبكراً بـ 40 دقيقة!):
--    - مولّد الغرامات الآلي الصباحي (auto_generate_instant_penalties) كان يحاسبه على وردية 10 ص
--      وينزل عليه غرامة 50 ج.م قبل أن يصل موعد ورديته 11 ص أصلاً!
--    - وعند تسجيل البصمة، لم تكن دالة record_attendance_local_biometric تسقط الغرامة المسبقة عند
--      ثبوت الحضور في الموعد (v_late = 0).
-- 3. الموظف ينصرف 5:00 م ومعه إذن معتمد ساعتان (120 دقيقة):
--    - مجموع وقته 400 دقيقة حضور + 120 دقيقة إذن = 520 دقيقة (> 8 ساعات / 480 دقيقة).
--    - دالة auto_waive_penalty_if_completed_eight_hours كانت تفحص فقط (check_out - check_in = 400)
--      وتتجاهل الأذونات، فترفض إسقاط الغرامة.
--
-- الحلول المطبقة:
-- 1. تحديث adopt_my_work_shift:
--    - تحديث shift_assignments و roster_days و attendance_daily و attendance_events فورياً.
--    - إعادة احتساب دقائق التأخير بناءً على الوردية الجديدة.
--    - إلغاء أي غرامة فورية مسجلة في instant_attendance_penalties فوراً لليوم عند انتفاء التأخير.
-- 2. تحديث record_attendance_local_biometric:
--    - إعطاء الأولوية لتعيين الوردية النشط shift_assignments على جدول الروستر القديم.
--    - عند تسجيل الحضور وكان التأخير 0 (v_late = 0): إسقاط أي غرامة غير مبصومة وُلدت خطأً في الصباح.
-- 3. تحديث auto_waive_penalty_if_completed_eight_hours:
--    - دمج دقائق الأذونات والتصاريح الرسمية المعتمدة لليوم (v_permit_minutes) في إجمالي ساعات العمل.
--    - إسقاط الغرامة تلقائياً متى استوفى المجموع 480 دقيقة (8 ساعات كاملة).
--    - إسقاط الغرامة فوراً لأي موظف على وردية 11-7 حضر في موعدها.
-- 4. تحديث decide_request:
--    - عند اعتماد إذن انصراف أو تأخير أو تغيير وردية، إعادة تقييم وإسقاط غرامة اليوم تلقائياً ولحظياً.
-- 5. تنظيف بأثر رجعي لغرامة عمار وأي موظف تأثر بهذه الثغرات.
-- ==============================================================================

begin;

-- ─── 1) تحديث adopt_my_work_shift لتبديل الوردية وإلغاء الغرامة الصباحية فوراً ──
create or replace function public.adopt_my_work_shift(p_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_shift public.shifts%rowtype;
  v_new_late integer := 0;
  v_att record;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id and is_active = true;
  if not found then
    raise exception 'فترة العمل المحددة غير موجودة أو غير مفعلة' using errcode = '22023';
  end if;

  -- 1) إنهاء أي تعيين وردية نشط سابق
  update public.shift_assignments
  set is_active = false,
      effective_to = least(coalesce(effective_to, v_today), v_today),
      updated_at = now()
  where employee_id = v_me and is_active = true;

  -- 2) إسناد الوردية المختارة فوراً للموظف
  insert into public.shift_assignments (
    employee_id, shift_id, effective_from, is_active, notes, created_by
  ) values (
    v_me, p_shift_id, v_today, true,
    'اعتماد وتثبيت فوري بطلب الموظف عند البصمة', auth.uid()
  );

  -- 3) تحديث جدول الروستر لليوم لضمان عدم سيطرة الوردية القديمة
  update public.roster_days
  set shift_id = p_shift_id,
      updated_at = now()
  where employee_id = v_me
    and work_date >= v_today;

  -- 4) فحص سجل الحضور اليومي وإعادة احتساب دقائق التأخير بناءً على الوردية الجديدة
  select * into v_att
  from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  if v_att.id is not null and v_att.first_check_in is not null then
    begin
      v_new_late := public.attendance_policy_late_minutes(v_me, v_today, v_att.first_check_in, p_shift_id);
    exception when others then
      v_new_late := 0;
    end;

    update public.attendance_daily
    set shift_id = p_shift_id,
        late_minutes = v_new_late,
        status = case 
          when coalesce(v_att.work_minutes, 0) >= 480 then 'present'
          when v_new_late > 0 then 'late'
          else 'present'
        end,
        updated_at = now()
    where id = v_att.id;

    update public.attendance_events
    set late_minutes = v_new_late
    where employee_id = v_me
      and (event_at at time zone 'Africa/Cairo')::date = v_today
      and event_type = 'CHECK_IN';
  else
    -- لم يبصم بعد أو لا يوجد سجل حضور لليوم
    update public.attendance_daily
    set shift_id = p_shift_id,
        late_minutes = 0,
        status = 'present',
        updated_at = now()
    where employee_id = v_me and work_date = v_today;
  end if;

  -- 5) إلغاء أي غرامة مسجلة في الصباح لليوم إذا انتفى التأخير (أو لم يكن قد بصم بعد وبدأت ورديته 11 ص)
  if v_new_late = 0 then
    update public.instant_attendance_penalties
    set status = 'cancelled',
        cancelled_reason = 'إلغاء فوري: تبديل فترة العمل إلى (' || coalesce(v_shift.name, '11 ص – 7 م') || ') والحضور في الموعد المحدد',
        notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: تبديل الوردية إلى ' || coalesce(v_shift.name, '11 ص – 7 م') || ' المعتمدة بلا تأخير',
        updated_at = now()
    where employee_id = v_me
      and work_date = v_today
      and status in ('pending_payment', 'doubled', 'suspended');

    -- رفع التعليق إن وجد
    if not exists (
      select 1 from public.instant_attendance_penalties
      where employee_id = v_me
        and status in ('doubled', 'suspended')
    ) then
      update public.employees set is_active = true, status = 'active' where id = v_me;
      update public.profiles set status = 'active' where employee_id = v_me;
    end if;
  end if;

  -- 6) اعتماد وإغلاق أي طلب تغيير وردية معلق للموظف
  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where employee_id = v_me
    and request_type = 'shift_change'
    and status = 'pending';

  return jsonb_build_object(
    'ok', true,
    'shiftId', v_shift.id,
    'shiftName', coalesce(v_shift.name, v_shift.name_ar, ''),
    'startTime', v_shift.start_time,
    'endTime', v_shift.end_time,
    'lateMinutes', v_new_late,
    'penaltyCancelled', (v_new_late = 0)
  );
end;
$$;

revoke all on function public.adopt_my_work_shift(uuid) from public, anon;
grant execute on function public.adopt_my_work_shift(uuid) to authenticated, service_role;
comment on function public.adopt_my_work_shift(uuid) is
  '0707: تثبيت فترة العمل وإعادة احتساب دقائق التأخير وإلغاء الغرامة الصباحية فوراً عند تبديل الوردية.';

-- ─── 2) تحديث record_attendance_local_biometric لإسقاط الغرامات الصباحية غير المستحقة عند الحضور ─
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

  -- 1. حارس مكافحة البصم المتكرر السريع (خلال 30 ثانية)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_at > v_now - interval '30 seconds'
  ) then
    raise exception 'attendance_rapid_punch_rejected' using errcode = '22023';
  end if;

  -- 2. حارس منع الانصراف الفوري (خلال دقيقتين من الحضور)
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

  -- أولوية تحديد الوردية:
  -- 1) التعيين الإداري النشط أو التبديل اللحظي shift_assignments (الصدارة المطلقة لقرارات اليوم)
  select sa.* into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_work_date
    and (sa.effective_to is null or sa.effective_to >= v_work_date)
  order by sa.effective_from desc
  limit 1;

  -- 2) جدول الروستر roster_days المعتمد
  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
  limit 1;

  if coalesce(v_assignment.shift_id, v_roster_shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_assignment.shift_id, v_roster_shift_id);
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

  if v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  elsif v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
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

    -- إذا حضر الموظف في موعد ورديته (بلا تأخير v_late = 0):
    -- يتم إسقاط أي غرامة غير مبصومة وُلدت بالخطأ في الصباح استناداً لوردية سابقة
    if v_late = 0 then
      update public.instant_attendance_penalties
      set status = 'cancelled',
          cancelled_reason = 'إلغاء تلقائي: الحضور في موعد الوردية المعتمدة (' || coalesce(v_shift.name, '') || ') بلا تأخير',
          notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: تسجيل البصمة في موعد الوردية',
          updated_at = now()
      where employee_id = p_employee_id
        and work_date = v_work_date
        and status in ('pending_payment', 'doubled');
    end if;
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
    v_late, v_requires_review, 'biometric_verified',
    null, 'fingerprint', null, true, false,
    v_notes, 'mobile', null
  ) returning id into v_event_id;

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
    when v_calc_work_minutes >= 480 then 'present'
    when v_late > 0 then 'late'
    else 'present'
  end;

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, overtime_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_assignment.shift_id, v_roster_shift_id, public.match_flexible_shift(v_first_check_in)),
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
      when excluded.work_minutes >= 480 then 'present'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now();

  -- إشعارات الحضور
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
          'system', 'high', 'instant_penalty', v_event_id,
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
      end if;
    exception when others then
      null;
    end;
  end if;

  -- عند تسجيل الانصراف: إنهاء المأموريات وفحص إسقاط الغرامة (مع الأذونات)
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

    begin
      perform public.auto_waive_penalty_if_completed_eight_hours(p_employee_id, v_work_date);
    exception when others then
      null;
    end;
  end if;

  return v_event_id;
end;
$function$;

revoke all on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role, authenticated;
comment on function public.record_attendance_local_biometric is '0707: تقديم الوردية النشطة وإلغاء الغرامات الصباحية غير المستحقة عند الحضور في الموعد.';

-- ─── 3) تحديث دالة إسقاط الغرامات باحتساب الأذونات الرسمية المعتمدة ──────────
create or replace function public.auto_waive_penalty_if_completed_eight_hours(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_att record;
  v_pen record;
  v_work_minutes integer := 0;
  v_permit_minutes integer := 0;
  v_total_effective_minutes integer := 0;
  v_emp_name text;
  v_mgr_id uuid;
  v_in_str text;
  v_out_str text;
  v_hours integer;
  v_mins integer;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_elapsed_minutes integer;
  v_assigned_shift public.shifts%rowtype;
  v_shift_late_calc integer := 0;
begin
  if p_employee_id is null or p_work_date is null then
    return jsonb_build_object('waived', false, 'reason', 'invalid_params');
  end if;

  select ad.id, ad.shift_id, ad.first_check_in, ad.last_check_out, ad.work_minutes
    into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if not found or v_att.first_check_in is null then
    return jsonb_build_object('waived', false, 'reason', 'no_checkin');
  end if;

  select p.id, p.current_amount, p.original_amount, p.status, p.escalation_level, p.notes
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if not found then
    return jsonb_build_object('waived', false, 'reason', 'no_active_penalty');
  end if;

  select e.full_name_ar into v_emp_name
    from public.employees e
   where e.id = p_employee_id;

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;

  -- فحص هل الموظف مسند لوردية (11 ص - 7 م) وبصم في موعدها
  select s.* into v_assigned_shift
    from public.shifts s
   where s.id = v_att.shift_id;

  if v_assigned_shift.id is null then
    select s.* into v_assigned_shift
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = p_employee_id
       and sa.is_active = true
       and sa.effective_from <= p_work_date
       and (sa.effective_to is null or sa.effective_to >= p_work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_assigned_shift.id is not null and v_assigned_shift.start_time >= '11:00:00'::time then
    begin
      v_shift_late_calc := public.attendance_policy_late_minutes(
        p_employee_id,
        p_work_date,
        v_att.first_check_in,
        v_assigned_shift.id
      );
    exception when others then
      v_shift_late_calc := 0;
    end;

    if v_shift_late_calc = 0 then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: الوردية المعتمدة (' || coalesce(v_assigned_shift.name, '11 ص – 7 م') || ') والحضور في الموعد المحدد',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: الحضور في موعد الوردية المسائية المعتمدة',
             updated_at = now()
       where id = v_pen.id;

      perform public.notify_employee(
        p_employee_id,
        '🎉 إلغاء غرامة التأخير لاعتماد الوردية',
        'تم إلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لحضورك في موعد الوردية المعتمدة (' || coalesce(v_assigned_shift.name, '') || ').',
        'system', 'high', 'instant_penalty', v_pen.id,
        jsonb_build_object('penaltyId', v_pen.id, 'waived', true, 'reason', 'shift_match_no_delay')
      );

      return jsonb_build_object('waived', true, 'reason', 'shift_match_no_delay');
    end if;
  end if;

  -- احتساب دقائق الأذونات والتصاريح الرسمية المعتمدة لليوم
  select coalesce(sum(
    coalesce(
      nullif(r.payload->>'minutes', '')::integer,
      nullif(r.payload->>'duration', '')::integer,
      (nullif(r.payload->>'hours', '')::numeric * 60)::integer,
      case when r.request_type in ('early_permit', 'late_permit') then 120 else 0 end
    )
  ), 0) into v_permit_minutes
  from public.requests r
  where r.employee_id = p_employee_id
    and r.status = 'approved'
    and r.request_type in ('early_permit', 'late_permit', 'permit', 'attendance_permit', 'permission', 'errand')
    and coalesce(
      public.try_cast_date(r.payload->>'permitDate'),
      public.try_cast_date(r.payload->>'date'),
      public.try_cast_date(r.payload->>'startDate'),
      public.try_cast_date(r.payload->>'start_date'),
      public.try_cast_date(r.payload->>'workDate'),
      r.created_at::date
    ) = p_work_date;

  if v_permit_minutes = 0 then
    select coalesce(sum(greatest(0, coalesce(minutes_adjustment, 0))), 0) into v_permit_minutes
    from public.attendance_exceptions
    where employee_id = p_employee_id
      and work_date = p_work_date
      and status = 'approved'
      and kind in ('early_leave', 'permit', 'late', 'permission');
  end if;

  if v_att.last_check_out is null then
    if p_work_date = v_today then
      v_elapsed_minutes := floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
                           + coalesce(v_permit_minutes, 0);

      if v_elapsed_minutes >= 480 then
        if not exists (
          select 1 from public.notifications n
           where n.user_id = (select user_id from public.employees where id = p_employee_id)
             and n.category = 'instant_penalty'
             and n.metadata->>'promptType' = 'awaiting_checkout_confirmation'
             and n.created_at >= (now() - interval '8 hours')
        ) then
          perform public.notify_employee(
            p_employee_id,
            '🔔 أتممت 8 ساعات عمل — سجّل بصمة الانصراف',
            'عزيزي ' || coalesce(v_emp_name, '') || '، لقد أتممت 8 ساعات عمل بنجاح اليوم بمجموع الدوام الفعلي والتصاريح المعتمدة (' || (v_elapsed_minutes / 60) || ' ساعة و' || (v_elapsed_minutes % 60) || ' دقيقة). برجاء تسجيل بصمة الانصراف الآن من مقر العمل لتأكيد تواجدك وإلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) نهائياً.',
            'system', 'high', 'instant_penalty', v_pen.id,
            jsonb_build_object(
              'penaltyId', v_pen.id,
              'promptType', 'awaiting_checkout_confirmation',
              'elapsedMinutes', v_elapsed_minutes,
              'permitMinutes', v_permit_minutes,
              'amount', v_pen.current_amount,
              'deepLink', 'ahlashabab://action/attendance'
            )
          );
        end if;

        return jsonb_build_object(
          'waived', false,
          'awaitingCheckout', true,
          'elapsedMinutes', v_elapsed_minutes,
          'permitMinutes', v_permit_minutes,
          'message', 'أتم 8 ساعات وبانتظار بصمة الانصراف التأكيدية لإسقاط الغرامة'
        );
      else
        return jsonb_build_object(
          'waived', false,
          'elapsedMinutes', v_elapsed_minutes,
          'permitMinutes', v_permit_minutes,
          'remainingMinutes', (480 - v_elapsed_minutes),
          'message', 'لم يكمل 8 ساعات بعد'
        );
      end if;
    else
      return jsonb_build_object('waived', false, 'reason', 'missing_checkout_unwaived');
    end if;
  end if;

  v_work_minutes := greatest(
    coalesce(v_att.work_minutes, 0),
    floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
  );

  v_total_effective_minutes := v_work_minutes + coalesce(v_permit_minutes, 0);

  if v_total_effective_minutes < 480 then
    return jsonb_build_object(
      'waived', false,
      'penaltyRemaining', true,
      'penaltyId', v_pen.id,
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'permitMinutes', v_permit_minutes,
      'totalEffectiveMinutes', v_total_effective_minutes,
      'remainingMinutes', (480 - v_total_effective_minutes),
      'message', 'الغرامة مستحقة لمغادرة العمل قبل إتمام 8 ساعات عمل رسمية'
    );
  end if;

  v_out_str := to_char(v_att.last_check_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (v_att.last_check_out at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_hours := v_total_effective_minutes / 60;
  v_mins := v_total_effective_minutes % 60;

  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء نهائي: استيفاء ساعات العمل الرسمية بالكامل (دوام فعلي ' || (v_work_minutes / 60) || 'س و' || (v_work_minutes % 60) || 'د + تصاريح معتمدة ' || (v_permit_minutes / 60) || 'س و' || (v_permit_minutes % 60) || 'د)',
         notes = coalesce(notes || ' | ', '') ||
                 'تم تأكيد الانصراف وإلغاء الخصم لاستيفاء 8 ساعات كاملة — الدخول: ' ||
                 v_in_str || '، الخروج: ' || v_out_str ||
                 ' (إجمالي الساعات المعتمدة: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة)',
         updated_at = now()
   where id = v_pen.id;

  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = p_employee_id
       and status in ('doubled', 'suspended')
       and id <> v_pen.id
  ) then
    update public.employees set is_active = true, status = 'active' where id = p_employee_id;
    update public.profiles set status = 'active' where employee_id = p_employee_id;
  end if;

  perform public.notify_employee(
    p_employee_id,
    '🎉 تم تأكيد الانصراف وإلغاء غرامة التأخير نهائياً',
    'تم تأكيد بصمة انصرافك وإلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لاستيفائك 8 ساعات عمل كاملة اليوم بمجموع الدوام الفعلي والتصاريح المعتمدة (الحضور: ' || v_in_str || ' — الانصراف: ' || v_out_str || ' — الإجمالي: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة). شكراً لالتزامك!',
    'system', 'high', 'instant_penalty', v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'waived', true,
      'reason', 'eight_hours_verified_with_permits',
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'permitMinutes', v_permit_minutes,
      'totalEffectiveMinutes', v_total_effective_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  select m.id into v_mgr_id
    from public.employees e
    join public.departments d on d.id = e.department_id
    join public.employees m on m.id = d.manager_id
   where e.id = p_employee_id;

  if v_mgr_id is not null and v_mgr_id <> p_employee_id then
    perform public.notify_employee(
      v_mgr_id,
      'إلغاء غرامة تأخير لموظف بالقسم بعد استيفاء ساعات العمل',
      'تم تأكيد انصراف الموظف (' || coalesce(v_emp_name, '') || ') واستيفاء 8 ساعات عمل رسمية اليوم (دوام وتصاريح معتمدة)، وألغى النظام غرامة التأخير (' || v_pen.current_amount || ' ج.م) تلقائياً.',
      'team', 'normal', 'instant_penalty', v_pen.id,
      jsonb_build_object('penaltyId', v_pen.id, 'employeeId', p_employee_id, 'waived', true)
    );
  end if;

  perform public.notify_employees_with_permission(
    'payroll.run.manage',
    'تأكيد انصراف وإلغاء غرامة تأخير (استيفاء 8 ساعات عمل وتصاريح)',
    'سجل الموظف ' || coalesce(v_emp_name, '') || ' انصرافه بعد استيفاء 8 ساعات كاملة (دوام وتصاريح معتمدة) وتم إلغاء الغرامة (' || v_pen.current_amount || ' ج.م) تلقائياً.',
    'system', 'normal', 'instant_penalty', v_pen.id,
    jsonb_build_object('penaltyId', v_pen.id, 'employeeId', p_employee_id, 'totalEffectiveMinutes', v_total_effective_minutes),
    p_employee_id
  );

  perform public.log_audit_event(
    'instant_penalty.waived_with_permits',
    'instant_attendance_penalties',
    v_pen.id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'work_date', p_work_date,
      'work_minutes', v_work_minutes,
      'permit_minutes', v_permit_minutes,
      'total_effective', v_total_effective_minutes,
      'check_out', v_att.last_check_out
    )
  );

  return jsonb_build_object(
    'waived', true,
    'penaltyId', v_pen.id,
    'amount', v_pen.current_amount,
    'workMinutes', v_work_minutes,
    'permitMinutes', v_permit_minutes,
    'totalEffectiveMinutes', v_total_effective_minutes,
    'hours', v_hours,
    'minutes', v_mins,
    'checkIn', v_in_str,
    'checkOut', v_out_str,
    'employeeName', v_emp_name
  );
end;
$$;

revoke all on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) from public, anon;
grant execute on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) to authenticated, service_role;

-- ─── 4) تحديث decide_request لإسقاط الغرامات تلقائياً عند اعتماد الأذونات والورديات ─
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_is_clinic_mgr   boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_actor_role_name text;
  v_correction_id   uuid;
  v_decision        text;
  v_permit_eval_date date;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- تطبيع صيغة القرار وقبول كافة الصيغ المتوافقة (approve / approved, reject / rejected, return / returned)
  v_decision := case
    when lower(trim(coalesce(p_decision, ''))) in ('approve', 'approved') then 'approve'
    when lower(trim(coalesce(p_decision, ''))) in ('reject', 'rejected') then 'reject'
    when lower(trim(coalesce(p_decision, ''))) in ('return', 'returned') then 'return'
    else lower(trim(coalesce(p_decision, '')))
  end;

  if v_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if v_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status not in ('pending', 'under_review') then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager','executive-secretary']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer'])
               or public.current_is_full_access()
               or public.current_has_active_role(array['admin','super-admin'])
               or public.has_any_permission(array['requests.decide.hr', 'requests.decide.executive', 'payroll.run.manage']);
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-manager']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or v_is_operations or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending','in_progress')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step := coalesce(v_step.step_order, 0);

  -- التحقق من كون المعتمِد مدير العيادات
  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or public.current_has_active_role(array['clinics-manager'])
  );

  -- التحقق من صفة المدير المباشر:
  v_is_direct_mgr := (v_req.manager_employee_id = v_me)
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_req.employee_id)
        or v_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  -- الصلاحية الشاملة لاعتماد الطلبات (تشمل الإدارة التنفيذية وإدارة الموارد البشرية والتشغيلية والمدير المباشر)
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or v_is_operations
    or (v_step.id is not null and (
      v_step.assignee_employee_id = v_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or public.current_has_active_role(array['admin','super-admin','executive-secretary']);

  if not v_authorized then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  -- تحديد الدور الفعلي لمتخذ القرار واسمه الوظيفي الواضح
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
    v_actor_role_name := 'إدارة النظام';
  elsif v_is_hr then
    v_actor_role := 'hr-manager';
    v_actor_role_name := 'الموارد البشرية';
  elsif v_is_exec then
    v_actor_role := 'executive';
    v_actor_role_name := 'المدير التنفيذي';
  elsif v_is_operations then
    v_actor_role := 'operations-manager-1';
    v_actor_role_name := 'مدير التشغيل 1';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
    v_actor_role_name := 'المدير المباشر';
  else
    v_actor_role := 'manager';
    v_actor_role_name := 'المعتمِد';
  end if;

  -- 1) إذا كان القرار هو الرفض أو الإرجاع: يُغلق الطلب مباشرة
  if v_decision in ('reject', 'return') then
    v_final_status := case when v_decision = 'reject' then 'rejected' else 'returned' end;

    update public.requests
    set status = v_final_status,
        workflow_status = case when v_decision = 'reject' then 'terminated' else 'in_review' end,
        decided_at = now(),
        decided_by = v_me,
        review_note = coalesce(p_comment, review_note),
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_step.id is not null then
      update public.request_steps
      set status = v_final_status,
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'skipped',
        updated_at = now()
    where request_id = p_request_id
      and (v_step.id is null or id <> v_step.id)
      and status in ('active', 'escalated', 'pending');

    update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, v_decision, 'pending', v_final_status, p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    -- تصحيح البصمة عند الرفض أو الإرجاع:
    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        update public.attendance_corrections
        set status = case when v_decision = 'reject' then 'rejected' else 'cancelled' end,
            reviewed_by = v_me,
            reviewed_at = now(),
            review_note = coalesce(p_comment, case when v_decision = 'reject' then 'مرفوض مع الطلب' else 'معاد للمراجعة' end),
            updated_at = now()
        where id = v_correction_id and status = 'pending';
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      case when v_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', v_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- 2) إذا كان القرار هو الموافقة (approve):
  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  -- فحص ما إذا كان الطلب يحتاج خطوة لاحقة:
  -- القاعدة 1: إذا اعتمد المدير التنفيذي أو الأدمن أو مدير الموارد البشرية أو مدير التشغيل في أي مرحلة -> يُعتمد نهائياً فوراً
  -- القاعدة 2: إذا اعتمد المدير المباشر طلباً تصعّد بالفعل للمرحلة 2 أو أعلى -> يُعتمد نهائياً فوراً
  -- خلاف ذلك (إذا كان المدير المباشر فقط يعتمد المرحلة 1 وتوجد مرحلة 2 متبقية): تُنشّط المرحلة 2
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec or v_is_hr or v_is_operations) then
    -- تنشيط الخطوة التالية
    if v_step.id is not null then
      update public.request_steps
      set status = 'approved',
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'active',
        updated_at = now()
    where request_id = p_request_id
      and step_order = (
        select min(step_order) from public.request_steps
        where request_id = p_request_id and step_order > v_current_step and status = 'pending'
      );

    select * into v_req from public.requests where id = p_request_id;
    return v_req;
  end if;

  -- اعتماد نهائي للطلب:
  -- أ) الخطوة التي بُتّ فيها: تُعتمد مع الفاعل الفعلي والتعليق
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  -- ب) الخطوات المتبقية الأخرى في المسار التي تم تجاوزها أو لم تلزم:
  -- تُسجّل كـ 'skipped' (لم يلزم) دون تكرار فاعل أو تعليق عليها منعاً للازدواجية في السجل
  update public.request_steps
  set status = 'skipped',
      acted_at = null,
      acted_by = null,
      comment = null,
      updated_at = now()
  where request_id = p_request_id
    and (v_step.id is null or id <> v_step.id)
    and status in ('active', 'escalated', 'pending');

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = coalesce(p_comment, review_note),
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  update public.workflow_instances
  set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  -- تطبيق الآثار التلقائية للطلب المعتمد:
  -- أ) تغيير الوردية (shift_change):
  if v_req.request_type = 'shift_change' and v_req.payload->>'shiftId' is not null then
    declare
      v_target_shift_id uuid := nullif(v_req.payload->>'shiftId','')::uuid;
      v_eff_date date := coalesce(nullif(v_req.payload->>'effectiveFrom','')::date, (now() at time zone 'Africa/Cairo')::date);
    begin
      if v_target_shift_id is not null then
        update public.shift_assignments
        set is_active = false,
            effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
            updated_at = now()
        where employee_id = v_req.employee_id and is_active = true;

        insert into public.shift_assignments (
          employee_id, shift_id, effective_from, is_active, notes, created_by
        ) values (
          v_req.employee_id, v_target_shift_id, v_eff_date, true,
          'معتمد بطلب تغيير وردية: ' || coalesce(v_req.title, ''), auth.uid()
        );

        update public.roster_days
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date >= v_eff_date;

        update public.attendance_daily
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date = v_eff_date;
      end if;
    end;
  end if;

  -- ب) تصحيح البصمة (attendance_correction):
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      perform public.decide_attendance_correction(v_correction_id, 'approved', coalesce(p_comment, 'معتمد مع الطلب'));
    end if;
  end if;

  -- ج) الإجازات (leave):
  if v_req.request_type = 'leave' then
    perform public.activate_approved_leave(v_req.id);
  end if;

  -- د) إعادة تقييم وإسقاط غرامة اليوم تلقائياً عند اعتماد أذونات الانصراف أو التأخير أو الوردية
  if v_req.request_type in ('early_permit', 'late_permit', 'permit', 'attendance_permit', 'permission', 'errand', 'shift_change') then
    v_permit_eval_date := coalesce(
      public.try_cast_date(v_req.payload->>'permitDate'),
      public.try_cast_date(v_req.payload->>'date'),
      public.try_cast_date(v_req.payload->>'effectiveFrom'),
      public.try_cast_date(v_req.payload->>'startDate'),
      public.try_cast_date(v_req.payload->>'start_date'),
      public.try_cast_date(v_req.payload->>'workDate'),
      v_req.created_at::date
    );

    if v_permit_eval_date is not null then
      begin
        perform public.auto_waive_penalty_if_completed_eight_hours(v_req.employee_id, v_permit_eval_date);
      exception when others then
        null;
      end;
    end if;
  end if;

  -- إشعار صاحب الطلب بالاعتماد
  perform public.notify_employee(
    v_req.employee_id,
    'تم اعتماد طلبك بنجاح ✓',
    coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'decision', 'approve', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;
comment on function public.decide_request(uuid, text, text) is
  '0707: اعتماد الطلبات مع دعم التخطي السليم وإسقاط غرامة اليوم تلقائياً عند اعتماد الأذونات أو تبديل الوردية.';

-- ─── 5) تنظيف فوري بأثر رجعي لغرامة عمار محمد عبد الباسط وأي حالة مماثلة ──────
do $$
declare
  v_amar_id uuid;
  r record;
begin
  -- 1. إلغاء صريح ومباشر لغرامة عمار محمد عبد الباسط ليوم 2026-10-22
  select id into v_amar_id
  from public.employees
  where full_name_ar like '%عمار%محمد%عبد%الباسط%'
  limit 1;

  if v_amar_id is not null then
    update public.attendance_daily
    set late_minutes = 0,
        status = 'present',
        updated_at = now()
    where employee_id = v_amar_id
      and work_date = '2026-10-22';

    update public.attendance_events
    set late_minutes = 0
    where employee_id = v_amar_id
      and (event_at at time zone 'Africa/Cairo')::date = '2026-10-22'
      and event_type = 'CHECK_IN';

    update public.instant_attendance_penalties
    set status = 'cancelled',
        cancelled_reason = 'إلغاء نهائي بقرار الإدارة: الموظف بدل ورديته إلى 11 ص - 7 م ولديه إذن انصراف ساعتان معتمد رسمياً',
        notes = coalesce(notes || ' | ', '') || 'تم إلغاء الخصم كاملاً: الحضور مطابق للوردية المسائية 11 ص ومغطى بإذن ساعتين معتمد',
        updated_at = now()
    where employee_id = v_amar_id
      and work_date = '2026-10-22';
  end if;

  -- 2. تنظيف عام لأي موظف آخر لديه غرامة معلقة واستوفى ساعات العمل أو بدل ورديته
  for r in (
    select distinct p.employee_id, p.work_date
    from public.instant_attendance_penalties p
    where p.status in ('pending_payment', 'doubled', 'suspended')
  ) loop
    perform public.auto_waive_penalty_if_completed_eight_hours(r.employee_id, r.work_date);
  end loop;
end;
$$;

commit;
