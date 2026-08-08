-- =====================================================================
-- 0319: F6 — مشاركة موقع استباقية للمدير التنفيذي
--        F7 — إشعار المدير المباشر بدخول/انصراف موظفيه
-- ---------------------------------------------------------------------
-- F6: يشارك الموظف موقعه الحيّ استباقياً (دون طلب من أحد) إلى المدير
--     التنفيذي (دور executive-director) مع إشعار عاجل له.
--     • يسجّل live_location_requests (requested_by = المدير التنفيذي،
--       employee_id = الموظف، status = active، expires_at حسب المدة).
--     • يسجّل نقطة location فورية في employee_locations.
--     • يُشعر المدير التنفيذي بإشعار عاجل + نبضة fcm.
--     • لا يُنشئ أي طلب موافقة — مشاركة مباشرة.
-- F7: تريجر بعد insert/update على attendance_daily يرسل للمدير المباشر
--     (من manager_relations relation_type='primary' الفعّال) إشعاراً عند
--     تسجيل دخول (first_check_in) أو خروج (last_check_out) لأي موظف يتبعه.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- F6: share_my_location_proactively
-- ---------------------------------------------------------------------
create or replace function public.share_my_location_proactively(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision default null,
  p_duration_minutes integer default 60,
  p_reason text default null,
  p_source text default 'mobile',
  p_battery_level integer default null
)
returns public.live_location_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_exec_role text;
  v_exec_emp uuid;
  v_exec_user uuid;
  v_row public.live_location_requests;
  v_duration integer;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'coordinates are required' using errcode = '22023';
  end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'coordinates out of range' using errcode = '22023';
  end if;

  v_duration := greatest(1, least(coalesce(p_duration_minutes, 60), 1440));

  -- المدير التنفيذي المستهدف (الإعداد leave_escalation_notify_role غير مناسب هنا —
  -- نستخدم executive_director_role مباشرة بدور executive-director)
  v_exec_role := public.get_system_setting_text('executive_director_role', 'executive-director');
  v_exec_emp  := public.first_active_employee_for_role(v_exec_role);

  -- منع تكرار طلب موقع نشط لنفس الموظف (مشاركة مفتوحة واحدة كافية)
  if exists (
    select 1 from public.live_location_requests
    where employee_id = v_me
      and status in ('pending', 'accepted', 'active')
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'you already have an active location share' using errcode = '23505';
  end if;

  insert into public.live_location_requests (
    employee_id, requested_by, reason, status, purpose,
    requested_at, starts_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_me, v_exec_emp, trim(coalesce(p_reason, 'مشاركة موقع استباقية')),
    'active', 'safety',
    now(), now(), now() + make_interval(mins => v_duration), v_duration,
    jsonb_build_object('proactive', true, 'source', p_source),
    auth.uid()
  ) returning * into v_row;

  -- نقطة موقع فورية
  insert into public.employee_locations (
    employee_id, live_request_id, latitude, longitude, accuracy,
    source, battery_level, is_mock, created_by
  ) values (
    v_me, v_row.id, p_latitude, p_longitude, p_accuracy,
    case when p_source in ('mobile','web','device','manual','geofence') then p_source else 'mobile' end,
    case when p_battery_level between 0 and 100 then p_battery_level else null end,
    false, auth.uid()
  );

  -- إشعار عاجل للمدير التنفيذي
  if v_exec_emp is not null then
    select p.id into v_exec_user from public.profiles p where p.employee_id = v_exec_emp;

    if v_exec_user is not null then
      insert into public.notifications (
        recipient_user_id, recipient_employee_id, title, body, category, priority,
        action_url, entity_type, entity_id, metadata, created_by
      ) values (
        v_exec_user, v_exec_emp,
        'مشاركة موقع حيّة من موظف',
        format(
          '%s يشاركك موقعه الآن%s',
          coalesce((select full_name_ar from public.employees where id = v_me), 'موظف'),
          case when p_reason is not null then ' — ' || trim(p_reason) else '' end
        ),
        'location', 'urgent',
        'ahlashabab://action/live_location/' || v_row.id::text,
        'live_location_requests', v_row.id,
        jsonb_build_object(
          'proactive', true,
          'employeeId', v_me,
          'requestId', v_row.id,
          'channel', 'urgent_location',
          'sound', 'urgent',
          'deepLink', 'ahlashabab://action/live_location/' || v_row.id::text
        ),
        auth.uid()
      );
    end if;
  end if;

  perform public.log_audit_event(
    'live_location.proactive_shared', 'security', 'notice',
    'live_location_requests', v_row.id,
    'مشاركة موقع استباقية', null,
    jsonb_build_object(
      'employeeId', v_me, 'executiveEmployeeId', v_exec_emp,
      'durationMinutes', v_duration, 'purpose', 'safety'
    )
  );

  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$$;
revoke execute on function public.share_my_location_proactively(double precision, double precision, double precision, integer, text, text, integer) from public;
grant execute on function public.share_my_location_proactively(double precision, double precision, double precision, integer, text, text, integer) to authenticated;

comment on function public.share_my_location_proactively(double precision, double precision, double precision, integer, text, text, integer) is
  'مشاركة موقع استباقية من الموظف إلى المدير التنفيذي مع إشعار عاجل.';

-- ---------------------------------------------------------------------
-- F7: تريجر إشعار المدير المباشر بدخول/انصراف موظفيه
-- ---------------------------------------------------------------------
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
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  -- المدير المباشر الحالي (primary فعّال)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is null then
    return new;
  end if;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'HH24:MI'
  );

  perform public.notify_employee(
    v_manager,
    case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
         else 'انصراف موظف — تسجيل خروج' end,
    format(
      '%s — %s (%s)',
      coalesce((select full_name_ar from public.employees where id = new.employee_id), 'موظف'),
      case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
      v_time
    ),
    'attendance', 'low', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'employeeId', new.employee_id,
      'workDate', new.work_date,
      'managerId', v_manager,
      'time', v_time
    )
  );

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  'يُشعر المدير المباشر بدخول/انصراف موظفيه عند تسجيل أول دخول أو آخر خروج.';

drop trigger if exists trg_attendance_daily_notify_manager on public.attendance_daily;
create trigger trg_attendance_daily_notify_manager
  after insert or update of first_check_in, last_check_out on public.attendance_daily
  for each row execute function public.tg_attendance_daily_notify_manager();

notify pgrst, 'reload schema';

commit;
