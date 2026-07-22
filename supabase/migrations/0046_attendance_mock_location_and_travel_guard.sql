-- =====================================================================
-- 0046: كشف الموقع المزيف وحارس الانتقال المستحيل للحضور
-- =====================================================================
-- المشكلة (من الفحص العميق):
--   * التطبيق لا يرسل Position.isMocked عند بصمة الحضور، والخادم لا
--     يستقبلها أصلًا — تزوير الحضور بتطبيقات Fake GPS ممكن.
--   * لا فحص خادمي لسرعة الانتقال بين بصمتين متتاليتين.
-- الحل:
--   1. عمود is_mock_location على attendance_events.
--   2. توسيع record_attendance_event بمعامل p_is_mock: أي بصمة بموقع
--      مزيف تُعلَّم flagged وتتطلب مراجعة، مع سبب مسجل في notes.
--   3. حارس الانتقال المستحيل: مقارنة الإحداثيات مع آخر حدث خلال 6
--      ساعات؛ إذا تجاوزت السرعة الضمنية 42 م/ث (~150 كم/س) تُعلَّم
--      البصمة للمراجعة بسبب impossible_travel.
-- القرار متحفظ عمدًا: لا رفض تلقائي — بل flagged + requires_review،
-- ليحسم المشرف عبر مسار تصحيحات الحضور القائم (0028).
-- =====================================================================

-- 1) العمود الجديد
alter table public.attendance_events
  add column if not exists is_mock_location boolean not null default false;

comment on column public.attendance_events.is_mock_location is
  'أبلغ نظام تشغيل الجهاز أن الموقع صادر من مزود مواقع وهمية (Mock Provider). server-authored عبر Edge Function فقط.';

create index if not exists idx_att_events_mock
  on public.attendance_events(is_mock_location) where is_mock_location = true;

-- 2) استبدال الدالة الموثوقة بتوقيع موسّع
drop function if exists public.record_attendance_event(
  uuid, text, double precision, double precision, numeric, text, text, uuid, boolean
);

create or replace function public.record_attendance_event(
  p_employee_id       uuid,
  p_event_type        text,
  p_latitude          double precision,
  p_longitude         double precision,
  p_accuracy_meters   numeric,
  p_biometric_method  text,
  p_selfie_path       text,
  p_passkey_credential_id uuid,
  p_verified          boolean,
  p_is_mock           boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_id    uuid;
  v_geofence    public.geofences%rowtype;
  v_assignment  public.shift_assignments%rowtype;
  v_shift       public.shifts%rowtype;
  v_distance    numeric(12,2);
  v_requires_review boolean := false;
  v_late        integer := 0;
  v_now         timestamptz := now();
  v_op_date     date := (v_now at time zone 'Africa/Cairo')::date;
  v_verif       text;
  v_flags       text[] := array[]::text[];
  v_prev_at     timestamptz;
  v_prev_lat    double precision;
  v_prev_lon    double precision;
  v_gap_seconds numeric;
  v_travel      double precision;
begin
  -- 0) الاستدعاء محصور بـservice_role (الـEdge الموثوقة).
  if coalesce(current_setting('request.jwt.claim.role', true),
              current_setting('role', true), current_user) not in ('service_role','postgres','supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'record_attendance_event may only be called by the trusted server (service_role)'
      using errcode = '42501';
  end if;

  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid event_type: %', p_event_type using errcode = '22023';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id required' using errcode = '22023';
  end if;

  -- 1) التحقق من ملكية الـpasskey (إن مُرّر)
  if p_passkey_credential_id is not null then
    if not exists (
      select 1 from public.passkey_credentials pc
      where pc.id = p_passkey_credential_id
        and pc.employee_id = p_employee_id
        and pc.status = 'active'
    ) then
      raise exception 'invalid passkey credential' using errcode = '28000';
    end if;
  end if;
  v_verif := case when p_verified then 'server_verified' else 'unverified' end;

  -- 2) منع التكرار/Replay: لا حدثان بنفس النوع خلال 60 ثانية
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate attendance event within window' using errcode = '23505';
  end if;

  -- 3) إسناد الوردية الفعّال لليوم
  select * into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_op_date
    and (sa.effective_to is null or sa.effective_to >= v_op_date)
  order by sa.effective_from desc
  limit 1;

  -- 4) الـgeofence من إسناد الموظف فقط
  if v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences where id = v_assignment.geofence_id;
  end if;

  -- 5) المسافة والمراجعة الجغرافية
  if v_geofence.id is not null and p_latitude is not null and p_longitude is not null then
    v_distance := public.geo_distance_meters(
      p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
    )::numeric(12,2);
    if v_distance > v_geofence.radius_meters then
      v_requires_review := true;
      v_flags := array_append(v_flags, 'outside_geofence');
    end if;
    if v_geofence.max_accuracy is not null and p_accuracy_meters is not null
       and p_accuracy_meters > v_geofence.max_accuracy then
      v_requires_review := true;
      v_flags := array_append(v_flags, 'low_accuracy');
    end if;
  else
    v_requires_review := true;
    v_flags := array_append(v_flags, 'no_geofence_or_location');
  end if;

  -- 5-ب) الموقع المزيف: علامة إلزامية للمراجعة
  if coalesce(p_is_mock, false) then
    v_requires_review := true;
    v_flags := array_append(v_flags, 'mock_location');
  end if;

  -- 5-ج) حارس الانتقال المستحيل: مقارنة مع آخر حدث بإحداثيات خلال 6 ساعات
  if p_latitude is not null and p_longitude is not null then
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
      v_travel := public.geo_distance_meters(p_latitude, p_longitude, v_prev_lat, v_prev_lon);
      -- 42 م/ث ≈ 150 كم/س: أسرع من أي انتقال بري مشروع بين بصمتين
      if v_travel is not null and (v_travel / v_gap_seconds) > 42 then
        v_requires_review := true;
        v_flags := array_append(v_flags, 'impossible_travel');
      end if;
    end if;
  end if;

  -- أي عملية غير مُتحقَّق منها بالكامل => مراجعة إلزامية
  if not p_verified then
    v_requires_review := true;
    v_flags := array_append(v_flags, 'unverified_assertion');
  end if;

  -- 6) التأخير عند الدخول
  if p_event_type = 'CHECK_IN' and v_assignment.shift_id is not null then
    select * into v_shift from public.shifts where id = v_assignment.shift_id;
    if v_shift.id is not null then
      v_late := public.calculate_late_minutes(v_now, v_shift.start_time, v_shift.grace_in_minutes, v_op_date);
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
    case when v_requires_review then 'flagged' else 'pending' end,
    coalesce(v_late, 0), v_requires_review, v_verif,
    p_passkey_credential_id, coalesce(p_biometric_method,'none'), p_selfie_path,
    p_verified,
    coalesce(p_is_mock, false),
    case when array_length(v_flags, 1) > 0
         then 'flags:' || array_to_string(v_flags, ',')
         else null end,
    'mobile', null
  )
  returning id into v_event_id;

  if p_passkey_credential_id is not null then
    update public.passkey_credentials set last_used = v_now where id = p_passkey_credential_id;
  end if;

  return v_event_id;
end;
$$;

comment on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean)
  is 'server-authored: تُستدعى فقط من Edge Function عبر service_role بعد تحقق WebAuthn. تشمل كشف Mock Location وحارس الانتقال المستحيل (>150كم/س خلال 6 ساعات) مع أسباب العلامات في notes.';

-- ⚠️ لا grant لـauthenticated: الاستدعاء عبر service_role فقط.
revoke execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean) from public;
revoke execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean) from authenticated;
revoke execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean) from anon;
grant execute on function public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean) to service_role;

-- =====================================================================
-- نهاية Migration 0046
-- =====================================================================
