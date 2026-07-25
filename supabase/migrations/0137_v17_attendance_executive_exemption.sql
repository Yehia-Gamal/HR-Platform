-- 0137: V17 §7 — إكمال استثناء المدير التنفيذي من الحضور الإلزامي.
-- الدالة الرئيسية punch_attendance_local_biometric_v1 (0104) تمنع التنفيذي فعلاً.
-- هذا الإصلاح يسد ثغرتين:
--   1) punch_attendance_local (0095) — لا يحتوي على فحص تنفيذي.
--   2) generate_punch_reminders (0057) — يرسل تذكيرات لجميع الموظفين بما فيهم التنفيذي.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) punch_attendance_local: إضافة فحص الدور التنفيذي
--    هذه الدالة تُستدعى أيضاً من punch_attendance_local_v2 (0096)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.punch_attendance_local(
  p_event_type text,
  p_credential_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false,
  p_device_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_employee record;
  v_credential record;
  v_device record;
  v_event_id uuid;
  v_event record;
  v_result jsonb;
  v_error text;
  v_known_errors constant text[] := array[
    'attendance_outside_complex',
    'attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low',
    'attendance_geofence_not_configured',
    'attendance_location_required',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required'
  ];
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if nullif(trim(p_credential_id), '') is null then
    raise exception 'credential_required' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid_latitude_or_longitude' using errcode = '22023';
  end if;
  if p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_accuracy' using errcode = '22023';
  end if;

  -- V17 §7: المدير التنفيذي مستثنى من الحضور الإلزامي
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_user_id and r.slug in ('executive', 'executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode = '42501';
  end if;

  -- Lookup employee
  select id, status, user_id into v_employee
  from public.employees
  where user_id = v_user_id and status in ('active', 'onboarding');

  if not found then
    raise exception 'employee_not_found' using errcode = '42501';
  end if;

  -- Verify credential
  select * into v_credential
  from public.passkey_credentials
  where credential_id = p_credential_id
    and employee_id = v_employee.id
    and status = 'active';

  if not found then
    raise exception 'credential_not_found' using errcode = '42501';
  end if;

  -- Verify device (match credential to employee_devices)
  select * into v_device
  from public.employee_devices
  where employee_id = v_employee.id
    and user_id = v_user_id
    and status = 'active'
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'device_not_found' using errcode = '42501';
  end if;

  begin
    v_event_id := public.record_attendance_event(
      v_employee.id,
      p_event_type,
      p_latitude,
      p_longitude,
      p_accuracy_meters,
      'passkey',
      null,
      v_credential.id,
      true,
      p_is_mock
    );
  exception
    when others then
      get stacked diagnostics v_error = message_text;
      if v_error = any(v_known_errors) then
        return jsonb_build_object(
          'ok', false,
          'error', v_error,
          'employeeId', v_employee.id
        );
      end if;
      raise;
  end;

  select * into v_event
  from public.attendance_events
  where id = v_event_id;

  return jsonb_build_object(
    'ok', true,
    'eventId', v_event_id,
    'employeeId', v_employee.id,
    'eventType', v_event.event_type,
    'eventAt', v_event.event_at,
    'status', v_event.status,
    'latitude', v_event.latitude,
    'longitude', v_event.longitude,
    'notes', v_event.notes
  );
end;
$$;

comment on function public.punch_attendance_local(text,text,double precision,double precision,double precision,boolean,text) is
  'V10 passkey-based attendance punch (legacy). 0137: أُضيف فحص استثناء المدير التنفيذي.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) generate_punch_reminders: استثناء المدير التنفيذي من التذكيرات
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.generate_punch_reminders(p_lead_minutes integer default 15)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created integer := 0;
  v_now_cairo timestamptz := now();
  v_local timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_local::date;
  v_now_time time := v_local::time;
  v_dow integer := extract(isodow from v_local)::integer;  -- 1=إثنين .. 7=أحد
  v_lead integer := greatest(coalesce(p_lead_minutes, 15), 1);
  v_shift record;
  v_emp record;
  v_daily public.attendance_daily;
  v_kind text;
  v_title text;
  v_body text;
begin
  -- مسموح فقط لعملية خادمية (service_role) أو مالك صلاحية إرسال الإشعارات.
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة والسبت عطلة (يوم العمل: الأحد=7 والإثنين..الخميس=1..4).
  if v_dow in (5, 6) then
    return 0;
  end if;

  -- الوردية الرسمية الحالية: النشطة الأحدث تحديثًا (تبديل رمضان يدوي).
  select * into v_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  if v_shift.id is null then
    return 0;
  end if;

  for v_emp in
    select e.id as employee_id, e.user_id
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
      -- V17 §7: استثناء المدير التنفيذي من تذكيرات الحضور
      and not exists (
        select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive', 'executive-director')
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
  loop
    -- سجل اليوم (إن وُجد) للموظف: مصدر الحقيقة لبصمة الدخول/الخروج.
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id
      and work_date = v_today;

    -- تحديد نوع التذكير حسب التوقيت
    v_kind := null;
    if v_now_time >= (v_shift.start_time - make_interval(mins := v_lead))
       and v_now_time < v_shift.start_time
       and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'before_in';
      v_title := 'تذكير بالحضور';
      v_body := 'اقترب وقت الحضور (' || to_char(v_shift.start_time, 'HH24:MI') || '). لا تنسَ تسجيل البصمة.';
    elsif v_now_time >= v_shift.start_time + make_interval(mins := v_shift.grace_in_minutes)
          and v_now_time < v_shift.start_time + make_interval(mins := v_shift.grace_in_minutes + v_lead)
          and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'late_in';
      v_title := '⚠️ تأخير في الحضور';
      v_body := 'لم تُسجَّل بصمة حضورك حتى الآن. سجّل البصمة في أقرب وقت.';
    elsif v_now_time >= (v_shift.end_time - make_interval(mins := v_lead))
          and v_now_time < v_shift.end_time
          and v_daily.first_check_in is not null
          and v_daily.last_check_out is null then
      v_kind := 'before_out';
      v_title := 'تذكير بالانصراف';
      v_body := 'اقترب وقت الانصراف (' || to_char(v_shift.end_time, 'HH24:MI') || '). لا تنسَ تسجيل بصمة الانصراف.';
    end if;

    if v_kind is null then
      continue;
    end if;

    -- منع التكرار: نفس (المستخدم/اليوم/النوع) مرة واحدة.
    if exists (
      select 1 from public.notifications n
      where n.recipient_user_id = v_emp.user_id
        and n.entity_type = 'punch_reminder'
        and n.metadata->>'kind' = v_kind
        and (n.metadata->>'workDate') = v_today::text
    ) then
      continue;
    end if;

    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, metadata
    ) values (
      v_emp.user_id, v_emp.employee_id, v_title, v_body,
      'system',
      case when v_kind = 'late_in' then 'high' else 'normal' end,
      '/attendance', 'punch_reminder', v_shift.id,
      jsonb_build_object('kind', v_kind, 'workDate', v_today::text, 'shiftId', v_shift.id)
    );
    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

comment on function public.generate_punch_reminders(integer) is
  'V10 تذكيرات البصمة. 0137: أُضيف استثناء المدير التنفيذي والمدير التنفيذي المساعد.';
