-- ==============================================================================
-- Migration 0681: فصل إنهاء المأمورية عن انصراف العمل ودعم الانصراف الميداني بالـ GPS
-- ==============================================================================
-- الأهداف والمتطلبات:
-- 1) إنهاء المأمورية ليس انصرافاً من العمل:
--    الموظف يمكنه إنشاء مأمورية، الخروج لإنجازها، ثم العودة للمقر وإنهاؤها
--    واستكمال يوم عمله العادي بالجمعية تماماً (دون إغلاق يوم الحضور أو تسجيل انصراف).
-- 2) إمكانية إنشاء مأموريات أخرى في نفس اليوم وإنهائها دون أي تعارض أو أخطاء.
-- 3) إمكانية إلغاء المأمورية (سواء كانت معتمدة أو جارية):
--    بحيث تلغى المأمورية وسجل تنفيذها فوراً، ويعود الموظف لوضع الحضور الطبيعي
--    مما يتيح له الضغط على زر الانصراف مباشرة في نهاية دوامه.
-- 4) خيار "إنهاء المأمورية مع الانصراف" عند امتداد المهمة لنهاية اليوم ("من برة برة"):
--    يأخذ إحداثيات GPS حية ومباشرة من جهاز الموظف، ويُقبل الانصراف دون رفض جغرافي.
--    يُسجل الحدث مع الإحداثيات الكاملة لتمكين الإدارة من مراجعته لاحقاً.
-- 5) تمكين الإدارة من فحص الانصراف الميداني ورفضه في أي وقت (حتى في اليوم التالي):
--    إتاحة دالة reject_attendance_event لرفض أي بصمة مشبوهة وإعادة احتساب حضور اليوم.
-- ==============================================================================

begin;

-- السماح بمصدر الانصراف الميداني للمأمورية في attendance_events
alter table public.attendance_events
  drop constraint if exists attendance_events_source_check;

alter table public.attendance_events
  add constraint attendance_events_source_check
  check (source in ('mobile','web','kiosk','service','import','mission_auto','mission_field_checkout'));

-- ─── 1) تحديث إلغاء الطلبات (cancel_request + cancel_my_mission) ─────────────
create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason text default null::text
)
returns public.requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.requests;
  v_from text;
  v_assignee uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  -- التخويل: صاحب الطلب، أو صلاحيات الإدارة العليا / الموارد البشرية
  if not (
    v_req.employee_id = v_me
    or public.current_is_full_access()
    or public.has_permission('requests.approve')
  ) then
    raise exception 'غير مصرح لك بإلغاء هذا الطلب' using errcode = '42501';
  end if;

  -- للمأموريات والقوافل والأنشطة: يُسمح بالإلغاء في حالتي pending و approved
  if v_req.request_type in ('mission', 'convoy', 'fundraising') then
    if v_req.status not in ('pending', 'approved') then
      raise exception 'لا يمكن إلغاء المأمورية في حالتها الحالية (%)', v_req.status using errcode = '22023';
    end if;

    -- إلغاء أي سجل تنفيذ غير مكتمل للمأمورية
    update public.mission_executions
       set status = 'cancelled',
           ended_at = now(),
           report = coalesce(p_reason, 'تم إلغاء المأمورية'),
           updated_at = now()
     where request_id = p_request_id
       and status in ('in_progress', 'not_started');
  else
    if v_req.status <> 'pending' then
      raise exception 'only pending requests can be cancelled (current: %)', v_req.status using errcode = '22023';
    end if;
  end if;

  v_from := v_req.status;

  update public.requests
     set status          = 'cancelled',
         workflow_status = 'terminated',
         cancelled_at    = now(),
         cancelled_by    = v_me,
         cancel_reason   = p_reason,
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  update public.request_steps
     set status   = 'skipped',
         acted_at = now(),
         acted_by = v_me,
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  update public.workflow_instances
     set status       = 'cancelled',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status = 'running';

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'cancel', v_from, 'cancelled', p_reason, auth.uid()
  );

  return v_req;
end;
$function$;

revoke all on function public.cancel_request(uuid, text) from public, anon;
grant execute on function public.cancel_request(uuid, text) to authenticated;

-- دالة مخصصة وسهلة لإلغاء المأمورية مباشرة
create or replace function public.cancel_my_mission(
  p_request_id uuid,
  p_reason text default null
)
returns public.requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  return public.cancel_request(p_request_id, p_reason);
end;
$$;

revoke all on function public.cancel_my_mission(uuid, text) from public, anon;
grant execute on function public.cancel_my_mission(uuid, text) to authenticated;


-- ─── 2) تحديث end_my_mission لدعم فك الارتباط بالانصراف والتقاط GPS الميداني ──
drop function if exists public.end_my_mission(uuid, text, text);
drop function if exists public.end_my_mission(uuid, text, text, boolean);
drop function if exists public.end_my_mission(uuid, text, text, boolean, double precision, double precision, double precision, boolean);

create or replace function public.end_my_mission(
  p_request_id uuid,
  p_report text,
  p_outcome text default null,
  p_with_checkout boolean default false,
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy double precision default null,
  p_is_mock boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me          uuid := public.current_employee_id();
  v_req         public.requests;
  v_exec        public.mission_executions;
  v_minutes     integer;
  v_today       date := (now() at time zone 'Africa/Cairo')::date;
  v_geofence    public.geofences%rowtype;
  v_distance    numeric(12,2) := null;
  v_do_checkout boolean := coalesce(p_with_checkout, false);
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;

  select * into v_exec from public.mission_executions where request_id = p_request_id;
  if not found then
    raise exception 'execution not started' using errcode = 'P0002';
  end if;
  if v_exec.employee_id <> v_me then
    raise exception 'mission ownership required' using errcode = '42501';
  end if;
  if v_exec.status <> 'in_progress' then
    raise exception 'execution already finished' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_report, ''))) < 3 then
    raise exception 'report is required (min 3 chars)' using errcode = '22023';
  end if;

  v_minutes := greatest(1, round(extract(epoch from (now() - v_exec.started_at)) / 60)::integer);

  -- 1) تحديث سجل التنفيذ
  update public.mission_executions
     set ended_at         = now(),
         actual_minutes   = v_minutes,
         report           = trim(p_report),
         outcome          = nullif(trim(coalesce(p_outcome, '')), ''),
         status           = 'completed',
         updated_at       = now()
   where id = v_exec.id;

  -- 2) التأكد من وجود حدث CHECK_IN في attendance_events لهذا اليوم
  select * into v_geofence from public.geofences where is_active = true order by created_at limit 1;

  if not exists (
    select 1 from public.attendance_events
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today
       and event_type = 'CHECK_IN'
       and status in ('accepted', 'adjusted')
  ) then
    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at, status,
      requires_review, verification_status, server_verified,
      is_mock_location, source, notes
    ) values (
      v_me, v_geofence.id, 'CHECK_IN', v_exec.started_at, 'adjusted',
      false, 'server_verified', true,
      false, 'mission_auto', 'auto_check_in_from_mission_end'
    );
  end if;

  if v_geofence.id is not null and p_lat is not null and p_lng is not null then
    v_distance := public.geo_distance_meters(p_lat, p_lng, v_geofence.latitude, v_geofence.longitude)::numeric(12,2);
  end if;

  -- 3) معالجة الانصراف حسب رغبة الموظف
  if v_do_checkout then
    -- أ) إنهاء المأمورية مع تسجيل بصمة انصراف ميداني ("من برة برة")
    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at,
      latitude, longitude, accuracy_meters, distance_meters,
      status, late_minutes, requires_review, verification_status,
      server_verified, is_mock_location, source, notes
    ) values (
      v_me, v_geofence.id, 'CHECK_OUT', now(),
      p_lat, p_lng, p_accuracy, v_distance,
      case when coalesce(p_is_mock, false) then 'flagged' else 'accepted' end,
      0,
      true, -- متاح للتدقيق والمراجعة الإدارية
      'server_verified',
      true,
      coalesce(p_is_mock, false),
      'mission_field_checkout',
      'mission_field_checkout: ' || coalesce(v_req.payload->>'location', 'ميداني') || ' | ' || trim(p_report) ||
      case when v_distance is not null then ' | بعد عن المقر: ' || v_distance::text || 'م' else '' end
    );

    insert into public.attendance_daily
      (employee_id, work_date, status, first_check_in, last_check_out, work_minutes, updated_at)
    values
      (v_me, v_today, 'present', v_exec.started_at, now(), v_minutes, now())
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          last_check_out = now(),
          work_minutes   = greatest(coalesce(public.attendance_daily.work_minutes, 0),
                                    floor(extract(epoch from (now() - coalesce(public.attendance_daily.first_check_in, v_exec.started_at))) / 60)::integer),
          status         = case
                             when public.attendance_daily.status in ('absent','missing_checkout','pending')
                               then 'present'
                             else public.attendance_daily.status
                           end,
          updated_at     = now();
  else
    -- ب) إنهاء المأمورية فقط واستمرار الدوام (الموظف عاد للمقر أو دوامه مستمر):
    -- لا نلمس last_check_out إطلاقاً حتى يتمكن الموظف من مواصلة العمل والبصم لاحقاً
    insert into public.attendance_daily
      (employee_id, work_date, status, first_check_in, work_minutes, updated_at)
    values
      (v_me, v_today, 'present', v_exec.started_at, v_minutes, now())
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          work_minutes   = greatest(coalesce(public.attendance_daily.work_minutes, 0), excluded.work_minutes),
          status         = case
                             when public.attendance_daily.status in ('absent','missing_checkout','pending')
                               then 'present'
                             else public.attendance_daily.status
                           end,
          updated_at     = now();
  end if;

  return v_exec.id;
end;
$$;

revoke all on function public.end_my_mission(uuid, text, text, boolean, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.end_my_mission(uuid, text, text, boolean, double precision, double precision, double precision, boolean) to authenticated;


-- ─── 3) تحديث get_my_attendance_state لتصحيح حالة استمرار الدوام وتعدد المأموريات ───
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
  v_late_minutes          integer := 0;
  v_penalty_amount        numeric := 0;
  v_check_in_str          text := null;
  v_target_checkout       timestamptz := null;
  v_target_checkout_str   text := null;
  v_comp_remaining        integer := 0;
  v_active_penalty_amt    numeric := null;
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

  -- آخر حدث حضور/انصراف مسجل اليوم
  select * into v_last from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  -- حالة اليوم وسجل الحضور اليومي
  select status, work_minutes, late_minutes
    into v_today_status, v_work_minutes, v_late_minutes
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

  if v_today_check_in is not null and v_today_check_out is null then
    v_work_minutes := greatest(coalesce(v_work_minutes, 0), floor(extract(epoch from (now() - v_today_check_in)) / 60)::integer);
  end if;

  if v_work_minutes > 480 then
    v_overtime_minutes := v_work_minutes - 480;
  else
    v_overtime_minutes := coalesce(v_overtime_minutes, 0);
  end if;

  if v_work_minutes >= 480 and v_today_status = 'late' then
    v_today_status := 'present';
  end if;

  if v_today_check_in is not null then
    v_check_in_str := to_char(v_today_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                      case when (v_today_check_in at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;
    v_target_checkout := v_today_check_in + interval '8 hours';
    v_target_checkout_str := to_char(v_target_checkout at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                             case when (v_target_checkout at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;
    v_comp_remaining := greatest(0, 480 - coalesce(v_work_minutes, 0));

    v_late_minutes := coalesce(v_late_minutes, v_last.late_minutes, 0);
    v_penalty_amount := public.calc_instant_penalty_amount(least(120, v_late_minutes));

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

  -- أولوية دقيقة لاختيار المأمورية المعروضة:
  -- 1) الجارية حالياً (in_progress) تأخذ الصدارة المطلقة حتى لو كان هناك غيرها
  -- 2) المعتمدة أو المعلقة التي تنتظر البدء ولم تنتهِ أو تُلغَ بعد
  -- 3) المكتملة
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
   order by
     case
       when x.exec_status = 'in_progress' then 0
       when x.exec_status is null or x.exec_status in ('not_started', 'approved', 'pending') then 1
       else 2
     end,
     x.started_at desc nulls last,
     r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;

    -- تنبيه جوهري: لا نضبط v_today_check_out إلى v_m_ended!
    -- لأن إنهاء المأمورية ليس انصرافاً من العمل، والانصراف يؤخذ حصراً من attendance_events/attendance_daily.

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

  -- ── حسم الإجراء المقترح (suggestedAction) ──
  -- 1) إذا كان اليوم مكتملاً بانصراف موثق:
  if v_today_check_out is not null and (not v_is_split or v_check_in_count >= 2) then
    v_suggested := 'DAY_COMPLETED';
  -- 2) إذا كانت وردية مجزأة وتم انصراف الفترة الأولى وبانتظار حضور الفترة الثانية:
  elsif v_today_check_out is not null and v_is_split and v_check_in_count < 2 then
    v_suggested := 'CHECK_IN';
  -- 3) إذا كان الموظف مسجل حضور بالفعل اليوم ولم ينصرف بعد:
  -- فالإجراء الطبيعي المتاح هو تسجيل الانصراف (أو استمرار العمل)
  elsif v_today_check_in is not null or (v_last.id is not null and v_last.event_type = 'CHECK_IN') then
    v_suggested := 'CHECK_OUT';
  -- 4) إذا لم يبصم حضوراً بعد ولديه مأمورية معتمدة/معلقة لليوم لم تبدأ:
  elsif v_m_id is not null and v_m_exec in ('approved', 'pending') and v_last.id is null and v_today_check_in is null then
    v_suggested := 'MISSION_START';
  else
    v_suggested := 'CHECK_IN';
  end if;

  if v_today_status is null or v_today_status = '' then
    if v_m_id is not null and v_m_exec in ('approved', 'in_progress') then
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


-- ─── 4) دالة رفض البصمة أو الانصراف الميداني بعد الفحص الإداري ─────────────
create or replace function public.reject_attendance_event(
  p_event_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me         uuid := public.current_employee_id();
  v_event      public.attendance_events;
  v_work_date  date;
  v_first_in   timestamptz;
  v_last_out   timestamptz;
  v_minutes    integer := 0;
  v_new_status text;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('attendance.audit')
    or public.has_permission('attendance.manage')
    or public.has_permission('attendance.correct')
  ) then
    raise exception 'غير مصرح لك برفض بصمات الحضور والانصراف' using errcode = '42501';
  end if;

  select * into v_event from public.attendance_events where id = p_event_id for update;
  if not found then
    raise exception 'attendance event not found' using errcode = 'P0002';
  end if;

  v_work_date := (v_event.event_at at time zone 'Africa/Cairo')::date;

  -- 1) تحديث حالة الحدث إلى مرفوض
  update public.attendance_events
     set status = 'rejected',
         requires_review = false,
         notes = coalesce(notes || ' | ', '') || 'مرفوض إدارياً: ' || trim(coalesce(p_reason, 'تلاعب في الموقع أو البصمة')),
         updated_at = now()
   where id = p_event_id;

  -- 2) إعادة احتساب اليوم في attendance_daily بناءً على البصمات الصالحة المتبقية
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_in, v_last_out
    from public.attendance_events
   where employee_id = v_event.employee_id
     and (event_at at time zone 'Africa/Cairo')::date = v_work_date
     and status in ('accepted', 'adjusted');

  if v_first_in is not null and v_last_out is not null then
    v_minutes := greatest(0, floor(extract(epoch from (v_last_out - v_first_in)) / 60)::integer);
    v_new_status := 'present';
  elsif v_first_in is not null and v_last_out is null then
    v_minutes := 0;
    v_new_status := 'missing_checkout';
  else
    v_minutes := 0;
    v_new_status := 'absent';
  end if;

  update public.attendance_daily
     set first_check_in = v_first_in,
         last_check_out = v_last_out,
         work_minutes   = v_minutes,
         status         = v_new_status,
         updated_at     = now()
   where employee_id = v_event.employee_id
     and work_date = v_work_date;

  -- 3) توثيق في سجل التدقيق
  perform public.log_audit_event(
    'attendance.event.rejected', 'attendance', 'warning', 'attendance_events', p_event_id,
    'رفض بصمة حضور/انصراف بعد الفحص الإداري',
    format('السبب: %s | الموظف: %s | التاريخ: %s', p_reason, v_event.employee_id, v_work_date),
    jsonb_build_object(
      'eventId', p_event_id,
      'eventType', v_event.event_type,
      'employeeId', v_event.employee_id,
      'workDate', v_work_date,
      'latitude', v_event.latitude,
      'longitude', v_event.longitude,
      'source', v_event.source,
      'reason', p_reason,
      'rejectedBy', v_me
    )
  );

  return jsonb_build_object(
    'success', true,
    'eventId', p_event_id,
    'newDailyStatus', v_new_status,
    'lastCheckOut', v_last_out
  );
end;
$$;

revoke all on function public.reject_attendance_event(uuid, text) from public, anon;
grant execute on function public.reject_attendance_event(uuid, text) to authenticated;

commit;
