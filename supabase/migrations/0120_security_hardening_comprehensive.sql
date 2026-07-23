-- ============================================================================
-- 0120: تقوية أمنية شاملة — إلغاء صلاحيات مفقودة + استعادة حارس الانتقال
--       المستحيل + تحديد معدل إعادة الدعوة
-- ============================================================================
-- الأهداف:
--   أ) إلغاء EXECUTE من public/anon على دوال لم تُحصَّن بعد.
--   ب) استعادة حارس الانتقال المستحيل (42 م/ث ≈ 150 كم/س) الذي كان في 0046
--      وأُزيل في إعادة كتابة 0073/0082 — كعلامة مراجعة (لا رفض).
--   ج) تحديد معدل إعادة إرسال الدعوة على مستوى قاعدة البيانات.
-- ============================================================================
-- Objectives:
--   A) Revoke stray EXECUTE grants from public/anon on unprotected functions.
--   B) Restore the impossible-travel guard (42 m/s ~ 150 km/h) that existed in
--      0046 and was lost in the 0073/0082 rewrites — as a review flag (not
--      a hard rejection).
--   C) Add a DB-level rate-limit helper for admin resend-invite flow.
-- ============================================================================

begin;

-- ============================================================================
-- القسم أ: إلغاء صلاحيات التنفيذ المفقودة
-- Section A: Revoke missing EXECUTE grants from public/anon/authenticated
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) activate_verified_passkey_device — service_role only
--    Signature from 0083: (uuid, uuid, text, text, bigint, text[], text, text, text, boolean)
--    تفعيل مفتاح المرور المُتحقَّق — خادمية فقط
-- ---------------------------------------------------------------------------
revoke execute on function public.activate_verified_passkey_device(
  uuid, uuid, text, text, bigint, text[], text, text, text, boolean
) from public, anon, authenticated;

grant execute on function public.activate_verified_passkey_device(
  uuid, uuid, text, text, bigint, text[], text, text, text, boolean
) to service_role;

-- ---------------------------------------------------------------------------
-- 2) finalize_verified_attendance — service_role only
--    Signature from 0089: 13 params (uuid x6, text, double precision x3, bigint, text, boolean)
--    إنهاء بصمة الحضور المُتحقَّقة — خادمية فقط
-- ---------------------------------------------------------------------------
revoke execute on function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text, double precision,
  double precision, double precision, bigint, text, boolean
) from public, anon, authenticated;

grant execute on function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text, double precision,
  double precision, double precision, bigint, text, boolean
) to service_role;

-- ---------------------------------------------------------------------------
-- 3) sync_location_request_response_from_point — trigger helper (internal)
--    Signature from 0088: () returns trigger
--    Trigger functions are called by the trigger mechanism, not directly.
--    مزامنة استجابة طلب الموقع من النقطة — دالة مُشغِّل داخلية
-- ---------------------------------------------------------------------------
revoke execute on function public.sync_location_request_response_from_point()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) sync_location_response_video — trigger helper (internal)
--    Signature from 0088: () returns trigger
--    مزامنة فيديو استجابة الموقع — دالة مُشغِّل داخلية
-- ---------------------------------------------------------------------------
revoke execute on function public.sync_location_response_video()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) record_attendance_local_biometric — internal writer, called by
--    punch_attendance_local_biometric_v1 (SECURITY DEFINER)
--    Signature from 0104: (uuid, text, double precision x3, boolean)
--    تسجيل بصمة محلية — دالة داخلية تُستدعى من punch_attendance_local_biometric_v1
-- ---------------------------------------------------------------------------
revoke execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;

grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;

-- ---------------------------------------------------------------------------
-- 6) notify_dispute_admins — internal helper called via PERFORM from
--    SECURITY DEFINER functions in 0059
--    Signature from 0059: (uuid, text, text, text, text)
--    إشعار مدراء لجنة المخالفات — دالة مساعدة داخلية
-- ---------------------------------------------------------------------------
revoke execute on function public.notify_dispute_admins(
  uuid, text, text, text, text
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) nudge_notification_dispatcher — internal helper that fires Edge Function
--    via pg_net with cron_secret; called only from SECURITY DEFINER functions
--    Signature from 0067: () returns void
--    تنبيه مُرسِل الإشعارات — دالة مساعدة داخلية تستخدم أسرار خادمية
-- ---------------------------------------------------------------------------
revoke execute on function public.nudge_notification_dispatcher()
  from public, anon, authenticated;

grant execute on function public.nudge_notification_dispatcher()
  to service_role;

-- ---------------------------------------------------------------------------
-- 8) save_shift_admin (8-arg no-code overload from 0057)
--    Signature from 0057: (uuid, text, time, time, integer, integer, integer, boolean)
--    حفظ وردية بلا كود — النسخة المختصرة (8 معاملات)
--    Remains callable by authenticated (admin UI); revoke from public/anon.
-- ---------------------------------------------------------------------------
revoke execute on function public.save_shift_admin(
  uuid, text, time, time, integer, integer, integer, boolean
) from public, anon;

grant execute on function public.save_shift_admin(
  uuid, text, time, time, integer, integer, integer, boolean
) to authenticated;


-- ============================================================================
-- القسم ب: استعادة حارس الانتقال المستحيل في record_attendance_event
-- Section B: Restore impossible-travel detection in record_attendance_event
--            (was in 0046, lost in 0073/0082 rewrites)
--
-- التغيير: إضافة فحص السرعة الضمنية بين آخر بصمة بإحداثيات خلال 6 ساعات.
-- إذا تجاوزت 42 م/ث (~150 كم/س) تُعلَّم البصمة للمراجعة (لا تُرفَض).
-- Change: adds implied-speed check against last geolocated punch within 6h.
-- If speed > 42 m/s (~150 km/h) the punch is flagged for review (not rejected).
-- ============================================================================

-- The canonical double-precision overload (from 0082).
-- The numeric compatibility wrapper (from 0106) delegates to this and is unaffected.
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
  v_work_date date := (v_now at time zone 'Africa/Cairo')::date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- حارس الانتقال المستحيل / impossible-travel guard variables
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

  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

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

  -- -----------------------------------------------------------------------
  -- حارس الانتقال المستحيل (مُستعاد من 0046):
  -- مقارنة الإحداثيات مع آخر حدث بإحداثيات خلال 6 ساعات. إذا تجاوزت
  -- السرعة الضمنية 42 م/ث (~150 كم/س) تُعلَّم البصمة للمراجعة.
  -- Impossible-travel guard (restored from 0046):
  -- Compare coordinates with the most recent geolocated event within 6 hours.
  -- If implied speed exceeds 42 m/s (~150 km/h), flag for review.
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
    -- 42 م/ث ≈ 150 كم/س: أسرع من أي انتقال بري مشروع بين بصمتين
    -- 42 m/s ~ 150 km/h: faster than any legitimate ground transit
    if v_travel is not null and (v_travel / v_gap_seconds) > 42 then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- Published roster is the most specific assignment for the current day
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

  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;
  if v_geofence.max_accuracy is not null
     and p_accuracy_meters > v_geofence.max_accuracy then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
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

-- Re-apply revokes after CREATE OR REPLACE
revoke all on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_event(
  uuid, text, double precision, double precision, double precision,
  text, text, uuid, boolean, boolean
) to service_role;


-- ============================================================================
-- القسم ج: استعادة حارس الانتقال المستحيل في record_attendance_local_biometric
-- Section C: Restore impossible-travel detection in
--            record_attendance_local_biometric (from 0104)
--
-- نفس المنطق: علامة مراجعة (لا رفض) إذا تجاوزت السرعة 42 م/ث.
-- Same logic: flag for review (not rejection) if speed exceeds 42 m/s.
-- ============================================================================

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
  v_work_date date := (v_now at time zone 'Africa/Cairo')::date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- حارس الانتقال المستحيل / impossible-travel guard variables
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
  if exists (
    select 1 from public.attendance_daily
    where employee_id=p_employee_id and work_date=v_work_date and is_finalized
  ) then
    raise exception 'attendance_period_finalized' using errcode='55000';
  end if;

  -- -----------------------------------------------------------------------
  -- حارس الانتقال المستحيل (مُستعاد من 0046):
  -- مقارنة الإحداثيات مع آخر حدث بإحداثيات خلال 6 ساعات. إذا تجاوزت
  -- السرعة الضمنية 42 م/ث (~150 كم/س) تُعلَّم البصمة للمراجعة.
  -- Impossible-travel guard (restored from 0046):
  -- Compare coordinates with the most recent geolocated event within 6 hours.
  -- If implied speed exceeds 42 m/s (~150 km/h), flag for review.
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
    -- 42 م/ث ≈ 150 كم/س: أسرع من أي انتقال بري مشروع بين بصمتين
    -- 42 m/s ~ 150 km/h: faster than any legitimate ground transit
    if v_travel is not null and (v_travel / v_gap_seconds) > 42 then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

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
  if v_geofence.max_accuracy is not null
     and p_accuracy_meters>v_geofence.max_accuracy then
    raise exception 'attendance_location_accuracy_too_low' using errcode='22023';
  end if;

  if coalesce(v_roster_shift_id,v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id=coalesce(v_roster_shift_id,v_assignment.shift_id);
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
    case when v_first_check_in is null then 'partial'
      when v_late>0 then 'late' else 'present' end,
    false,null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id=coalesce(excluded.shift_id,attendance_daily.shift_id),
    first_check_in=coalesce(excluded.first_check_in,attendance_daily.first_check_in),
    last_check_out=coalesce(excluded.last_check_out,attendance_daily.last_check_out),
    work_minutes=excluded.work_minutes,
    late_minutes=greatest(attendance_daily.late_minutes,excluded.late_minutes),
    status=case
      when attendance_daily.status in ('on_leave','holiday','weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes,excluded.late_minutes)>0 then 'late'
      else 'present' end,
    updated_at=now()
  where attendance_daily.is_finalized=false;

  perform public.log_audit_event(
    'attendance.'||lower(p_event_type),'security','info','attendance_events',
    v_event_id,'بصمة محلية موثقة داخل نطاق المجمع',null,
    jsonb_build_object('method','local_biometric','insideComplex',true,
      'distanceMeters',v_distance,'geofenceId',v_geofence.id,
      'impossibleTravel',v_requires_review)
  );
  return v_event_id;
end;
$$;

-- Re-apply revokes after CREATE OR REPLACE
revoke all on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) from public, anon, authenticated;

grant execute on function public.record_attendance_local_biometric(
  uuid, text, double precision, double precision, double precision, boolean
) to service_role;


-- ============================================================================
-- القسم د: تحديد معدل إعادة إرسال دعوة الموظف
-- Section D: Rate-limit helper for admin resend-invite flow
-- ============================================================================
-- دالة مساعدة تُستدعى من Edge Function قبل إعادة إرسال الدعوة.
-- تفحص آخر وقت دعوة في audit_events وترفض إذا مرّ أقل من 60 ثانية.
-- Helper called by the Edge Function before resending an invite.
-- Checks the last invite timestamp in audit_events and rejects if < 60s ago.
-- ============================================================================

create or replace function public.check_invite_rate_limit(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_last_invite timestamptz;
begin
  select max(ae.created_at) into v_last_invite
  from public.audit_events ae
  where ae.entity_type = 'employees'
    and ae.entity_id = p_employee_id
    and ae.event_type in ('employee.invite.resent', 'employee.invite.sent');

  if v_last_invite is not null
     and v_last_invite > now() - interval '60 seconds' then
    raise exception 'invite_rate_limit_exceeded'
      using errcode = '42501',
            hint = 'يرجى الانتظار 60 ثانية قبل إعادة إرسال الدعوة.';
  end if;
end;
$$;

-- الدالة تُستدعى من Edge Function (service_role) أو من واجهة المدير (authenticated)
-- Callable from Edge Function (service_role) or admin UI (authenticated)
revoke execute on function public.check_invite_rate_limit(uuid)
  from public, anon;
grant execute on function public.check_invite_rate_limit(uuid)
  to authenticated, service_role;


-- ============================================================================
notify pgrst, 'reload schema';

commit;
