-- Migration 0607: بدء المأمورية من وقت الطلب حتى لو كان معلقاً، وتوفير خيار إنهاء المأمورية بالبصمة أو بدونها
-- 1) submit_my_request: عند طلب مأمورية لليوم الحالي، تبدأ المأمورية فوراً (in_progress) من وقت الطلب ويسجل الحضور اليومي
-- 2) start_my_mission: السماح ببدء المأمورية حتى لو كان الطلب معلقاً (pending) أو معتمداً (approved)
-- 3) end_my_mission: قبول معامل p_with_checkout لتحديد ما إذا كان الإنهاء مصحوباً ببصمة انصراف أم إنهاء للمهمة فقط واستمرار الدوام
-- 4) get_my_attendance_state: تحديث الإجراء المقترح للمأموريات الجارية أو المعلقة أو المنتهية دون انصراف

begin;

-- ============================================================================
-- 1) تحديث submit_my_request: بدء المأمورية فور إنشائها لليوم الحالي
-- ============================================================================
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_idempotency_key uuid default null::uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_row               public.requests;
  v_payload           jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
  v_day_mark          boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date        date;
  v_end_date          date;
  v_permit_date       date;
  v_minutes           integer;
  v_leave_type        text;
  v_leave_type_id     uuid;
  v_affects           boolean;
  v_days              numeric;
  v_substitute        uuid;
  v_correction_date   date;
  v_correction_type   text;
  v_corrected_time    text;
  v_permit_kind       text;
  v_geofence_id       uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select * into v_row
    from public.requests
    where employee_id = v_me
      and payload ->> 'clientId' = p_idempotency_key::text
      and created_at > now() - interval '10 minutes';
    if found then
      return v_row;
    end if;
    v_payload := v_payload || jsonb_build_object('clientId', p_idempotency_key::text);
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'العنوان وسبب الطلب مطلوبان (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  -- ── فحص قواعد تعديل حالة اليوم (dayMark): متاح لأي يوم ماضٍ في نفس الشهر ──
  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'تعديل حالة اليوم يتطلب تاريخاً صالحاً' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'تعديل حالة اليوم يكون ليوم واحد فقط' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'تعديل حالة اليوم متاح فقط خلال أيام الشهر الحالي' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'لا يمكن تعديل حالة الأيام المستقبلية' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم: %', v_leave_type using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية الإجازة مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية الإجازة يجب ألا يسبق البداية' using errcode = '22023';
        end if;

        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم إجازة عن أشهر سابقة' using errcode = '22023';
        end if;

        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'نوع الإجازة غير نشط أو غير معروف: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual' and v_start_date >= v_today));

      -- ─── مأمورية ───────────────────────────────────────────────────────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم مأمورية عن أشهر سابقة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل خارجية'),
          'days', 1,
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', case when v_day_mark then false else true end);

      -- ─── قافلة / فاندي ───────────────────────────────────────────────────
      when 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم تكليف عن أشهر سابقة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(
            nullif(trim(coalesce(v_payload->>'location', '')), ''),
            case when p_request_type = 'convoy' then 'قافلة ميدانية' else 'فعالية فاندي' end
          ),
          'days', ((v_end_date - v_start_date) + 1));

      -- ─── إذن تأخير صباحي ──────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن التأخير بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر ──────────────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن الانصراف بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── إذن حضور موحد ─────────────────────────────────────────────────────
      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن الحضور بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'نوع إذن غير مدعوم' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes);

      -- ─── تصحيح حضور ─────────────────────────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'تاريخ التصحيح مطلوب' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
        end if;
        if v_corrected_time is null or v_corrected_time !~ '^\d{2}:\d{2}$' then
          raise exception 'الوقت المصحح يجب أن يكون بصيغة HH:MM' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime', v_corrected_time);

      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'تواريخ أو قيم رقمية غير صالحة' using errcode = '22023';
  end;

  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- مسار الإجازات
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' and v_start_date >= v_today then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());
    end if;
  end if;

  -- ── 0607: بدء المأمورية فور طلبها لليوم الحالي وتسجيل الحضور ──
  if p_request_type in ('mission', 'convoy', 'fundraising') and not v_day_mark and v_start_date = v_today then
    insert into public.mission_executions(
      request_id, employee_id, status, started_at
    ) values (
      v_row.id, v_me, 'in_progress', coalesce(v_row.created_at, now())
    ) on conflict (request_id) do update
      set status = 'in_progress',
          started_at = coalesce(public.mission_executions.started_at, v_row.created_at, now()),
          updated_at = now();

    insert into public.attendance_daily (
      employee_id, work_date, status, first_check_in, updated_at
    ) values (
      v_me, v_today, 'present', coalesce(v_row.created_at, now()), now()
    ) on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          status = case
                     when public.attendance_daily.status in ('absent', 'pending', 'missing_checkout') then 'present'
                     else public.attendance_daily.status
                   end,
          updated_at = now();

    if not exists (
      select 1 from public.attendance_events
       where employee_id = v_me
         and (event_at at time zone 'Africa/Cairo')::date = v_today
         and event_type = 'CHECK_IN'
         and status in ('accepted', 'adjusted')
    ) then
      select id into v_geofence_id
        from public.geofences where is_active = true
        order by created_at limit 1;

      insert into public.attendance_events (
        employee_id, geofence_id, event_type, event_at, status,
        requires_review, verification_status, server_verified,
        is_mock_location, source, notes
      ) values (
        v_me, v_geofence_id, 'CHECK_IN', coalesce(v_row.created_at, now()), 'adjusted',
        true, 'server_verified', true,
        false, 'mission_auto', 'auto_check_in_from_mission_creation'
      );
    end if;
  end if;

  return v_row;
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;
comment on function public.submit_my_request(text, text, text, jsonb, uuid) is
  '0607: تقديم طلب مع بدء المأمورية فورياً من وقت طلبها لليوم الحالي وتسجيل الحضور.';

-- ============================================================================
-- 2) تحديث start_my_mission: السماح ببدء المأمورية حتى لو كان الطلب معلقاً
-- ============================================================================
create or replace function public.start_my_mission(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me          uuid := public.current_employee_id();
  v_req         public.requests;
  v_today       date := (now() at time zone 'Africa/Cairo')::date;
  v_id          uuid;
  v_end         date;
  v_geofence_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'لم يتم العثور على طلب المأمورية' using errcode = 'P0002';
  end if;
  if v_req.employee_id <> v_me then
    raise exception 'هذه المأمورية ليست مسندة إليك' using errcode = '42501';
  end if;
  if v_req.request_type not in ('mission','convoy','fundraising') then
    raise exception 'هذا الطلب ليس مأمورية أو تكليفاً' using errcode = '22023';
  end if;

  -- 0607: السماح بالبدء طالما الطلب معلق أو معتمد (وليس ملغياً أو مرفوضاً)
  if v_req.status not in ('approved', 'pending') then
    raise exception 'لا يمكن بدء مأمورية ملغاة أو مرفوضة' using errcode = '22023';
  end if;

  -- إذا كانت مسجلة مسبقاً كـ in_progress أو completed، نعيد المعرف بسلاسة
  select id into v_id from public.mission_executions
   where request_id = p_request_id
     and status in ('in_progress','completed');
  if v_id is not null then
    return v_id;
  end if;

  if v_req.request_type <> 'mission' then
    begin
      v_end := (nullif(v_req.payload->>'endDate', ''))::date;
    exception when others then
      v_end := null;
    end;
    if v_end is not null and v_today > v_end then
      raise exception 'لا يمكن بدء التكليف بعد انتهاء مدته' using errcode = '22023';
    end if;
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', coalesce(v_req.created_at, now()))
  on conflict (request_id) do update
    set status = 'in_progress',
        started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
        updated_at = now()
  returning id into v_id;

  -- تسجيل الحضور اليومي
  insert into public.attendance_daily (
    employee_id, work_date, status, first_check_in, updated_at
  ) values (
    v_me, v_today, 'present', coalesce(v_req.created_at, now()), now()
  ) on conflict (employee_id, work_date) do update
    set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
        status = case
                   when public.attendance_daily.status in ('absent', 'pending', 'missing_checkout') then 'present'
                   else public.attendance_daily.status
                 end,
        updated_at = now();

  -- التأكد من وجود حدث CHECK_IN في attendance_events
  if not exists (
    select 1 from public.attendance_events
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today
       and event_type = 'CHECK_IN'
       and status in ('accepted', 'adjusted')
  ) then
    select id into v_geofence_id
      from public.geofences where is_active = true
      order by created_at limit 1;

    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at, status,
      requires_review, verification_status, server_verified,
      is_mock_location, source, notes
    ) values (
      v_me, v_geofence_id, 'CHECK_IN', coalesce(v_req.created_at, now()), 'adjusted',
      true, 'server_verified', true,
      false, 'mission_auto', 'auto_check_in_from_mission_start'
    );
  end if;

  return v_id;
end $$;

revoke all on function public.start_my_mission(uuid) from public, anon;
grant execute on function public.start_my_mission(uuid) to authenticated;
comment on function public.start_my_mission(uuid) is
  '0607: بدء المأمورية حتى لو كان الطلب معلقاً (pending) مع تسجيل الحضور.';

-- ============================================================================
-- 3) تحديث end_my_mission: دعم خيار إنهاء المأمورية بالبصمة أو بدونها
-- ============================================================================
drop function if exists public.end_my_mission(uuid, text, text);
drop function if exists public.end_my_mission(uuid, text, text, boolean);

create or replace function public.end_my_mission(
  p_request_id uuid,
  p_report text,
  p_outcome text default null,
  p_with_checkout boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me          uuid := public.current_employee_id();
  v_exec        public.mission_executions;
  v_minutes     integer;
  v_today       date := (now() at time zone 'Africa/Cairo')::date;
  v_geofence_id uuid;
  v_do_checkout boolean := coalesce(p_with_checkout, true);
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
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
  if not exists (
    select 1 from public.attendance_events
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today
       and event_type = 'CHECK_IN'
       and status in ('accepted', 'adjusted')
  ) then
    select id into v_geofence_id
      from public.geofences where is_active = true
      order by created_at limit 1;

    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at, status,
      requires_review, verification_status, server_verified,
      is_mock_location, source, notes
    ) values (
      v_me, v_geofence_id, 'CHECK_IN', v_exec.started_at, 'adjusted',
      true, 'server_verified', true,
      false, 'mission_auto', 'auto_check_in_from_mission_end'
    );
  end if;

  -- 3) معالجة الانصراف حسب رغبة الموظف
  if v_do_checkout then
    -- إنهاء المأمورية مع تسجيل بصمة انصراف
    select id into v_geofence_id
      from public.geofences where is_active = true
      order by created_at limit 1;

    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at, status,
      requires_review, verification_status, server_verified,
      is_mock_location, source, notes
    ) values (
      v_me, v_geofence_id, 'CHECK_OUT', now(), 'adjusted',
      true, 'server_verified', true,
      false, 'mission_auto', 'mission_end_with_checkout'
    );

    insert into public.attendance_daily
      (employee_id, work_date, status, first_check_in, last_check_out, work_minutes, updated_at)
    values
      (v_me, v_today, 'present', v_exec.started_at, now(), v_minutes, now())
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          last_check_out = now(),
          work_minutes   = greatest(coalesce(public.attendance_daily.work_minutes, 0), excluded.work_minutes),
          status         = case
                             when public.attendance_daily.status in ('absent','missing_checkout','pending')
                               then 'present'
                             else public.attendance_daily.status
                           end,
          updated_at     = now();
  else
    -- إنهاء المأمورية فقط دون بصمة انصراف (استمرار الدوام)
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
end $$;

revoke all on function public.end_my_mission(uuid, text, text, boolean) from public, anon;
grant execute on function public.end_my_mission(uuid, text, text, boolean) to authenticated;
comment on function public.end_my_mission(uuid, text, text, boolean) is
  '0607: إنهاء المأمورية مع خيار بصمة انصراف أو بدونها.';

-- ============================================================================
-- 4) تحديث get_my_attendance_state لمزامنة الإجراء المقترح للمأموريات
-- ============================================================================
create or replace function public.get_my_attendance_state(p_installation_id text default null::text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                    uuid := public.current_employee_id();
  v_exempt                boolean;
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_last                  public.attendance_events;
  v_today_status          text;
  v_suggested             text;
  v_passkeys              integer;
  v_local_devices         integer;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_local_device_status   text;
  v_hash                  text;
  v_today_check_in        timestamptz;
  v_today_check_out       timestamptz;
  v_shift_end             timestamptz;
  v_shift_work_days       jsonb;
  v_shift_code            text;
  v_is_split              boolean := false;
  v_check_in_count        integer := 0;

  v_cutoff                time;
  v_m_id                  uuid;
  v_m_type                text;
  v_m_start_time          text;
  v_m_exec                text;
  v_m_started             timestamptz;
  v_m_ended               timestamptz;
  v_m_auto                boolean;
  v_mission               jsonb;
begin
  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'no_employee_linked'
    );
  end if;

  select is_exempt_from_attendance into v_exempt
  from public.employees where id = v_me;

  if coalesce(v_exempt, false) then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'executive_exempt'
    );
  end if;

  select s.is_split_shift, s.work_days, s.code
  into v_is_split, v_shift_work_days, v_shift_code
  from public.shift_assignments sa
  join public.shifts s on s.id = sa.shift_id
  where sa.employee_id = v_me and sa.is_active = true
    and v_today between sa.start_date and coalesce(sa.end_date, '9999-12-31'::date)
  order by sa.start_date desc limit 1;

  if v_is_split is null then
    select s.is_split_shift, s.work_days, s.code
    into v_is_split, v_shift_work_days, v_shift_code
    from public.shifts s
    where s.is_default = true and s.is_active = true
    limit 1;
  end if;

  v_is_split := coalesce(v_is_split, false);

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

  select status into v_today_status from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted');

  if v_last.id is not null and v_last.event_type = 'CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  elsif v_last.id is not null and v_last.event_type = 'CHECK_OUT' then
    if v_is_split and v_check_in_count < 2 then
      v_suggested := 'CHECK_IN';
    else
      v_suggested := 'DAY_COMPLETED';
    end if;
  else
    v_suggested := 'CHECK_IN';
  end if;

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

  -- ── فحص المأموريات اليوم ──
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
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
   order by case when r.status = 'approved' then 1 else 2 end,
            x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id = v_me and d.work_date = v_today;
    end if;

    -- 0607: توجيه الإجراء المقترح للمأمورية
    if v_m_exec = 'in_progress' then
      v_suggested := 'MISSION_IN_PROGRESS';
    elsif v_m_exec in ('approved', 'pending') and v_last.id is null then
      v_suggested := 'MISSION_START';
    elsif v_m_exec = 'completed' then
      if v_today_check_out is not null then
        v_suggested := 'DAY_COMPLETED';
      elsif v_today_check_in is not null then
        v_suggested := 'CHECK_OUT';
      else
        v_suggested := 'CHECK_IN';
      end if;
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

  select (v_today::text || ' ' || coalesce(s.shift_end_time, time '17:00')::text)::timestamptz
  into v_shift_end
  from public.attendance_settings s where s.singleton_key;

  return jsonb_build_object(
    'attendanceRequired', true,
    'selfPunchEnabled', true,
    'canPunch', true,
    'todayStatus', v_today_status,
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
    'missionToday', v_mission
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;
comment on function public.get_my_attendance_state is
  '0607: الحالة اللحظية للحضور مع دعم بدء المأموريات من وقت الطلب والإنهاء بالبصمة أو بدونها.';

commit;
