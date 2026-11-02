-- ==============================================================================
-- Migration 0719: Retroactive Requests, Shift-Aware Reminders, and Correction Waivers
-- 1. submit_my_request: Allow retroactive requests (leaves, missions, convoys, fundraisings, permits, day marks) for past dates and prior months up to 365 days back.
-- 2. generate_punch_reminders: Respect each employee's assigned shift start/end times instead of assuming a single global 10:00 AM shift.
-- 3. decide_attendance_correction: When attendance correction is approved, automatically cancel associated instant penalties and lift suspensions.
-- 4. Reconcile existing approved corrections (waive penalties for Yousef Rasmy and others).
-- ==============================================================================

-- ─── 1) تحديث دالة submit_my_request للسماح بالطلبات بأثر رجعي وللأشهر السابقة ───
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
  v_me                    uuid := public.current_employee_id();
  v_manager               uuid;
  v_row                   public.requests;
  v_payload               jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_min_allowed_date      date := (v_today - interval '365 days')::date;
  v_day_mark              boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date            date;
  v_end_date              date;
  v_permit_date           date;
  v_minutes               integer;
  v_leave_type            text;
  v_leave_type_id         uuid;
  v_affects               boolean;
  v_days                  numeric;
  v_substitute            uuid;
  v_correction_date       date;
  v_correction_type       text;
  v_corrected_time        text;
  v_permit_kind           text;
  v_is_clinic             boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_is_clinic := public.is_clinic_team_member(v_me) and v_me <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';

  -- حظر المأموريات والقوافل والفاندي على طاقم العيادات
  if v_is_clinic and p_request_type in ('mission', 'convoy', 'fundraising') then
    raise exception 'طلبات المأموريات والقوافل والأنشطة الميدانية غير متاحة لطاقم العيادات' using errcode = '22023';
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
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'العنوان وسبب الطلب مطلوبان (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'تعديل حالة اليوم يتطلب تاريخاً صالحاً' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'تعديل حالة اليوم يكون ليوم واحد فقط' using errcode = '22023';
    end if;
    if v_start_date < v_min_allowed_date then
      raise exception 'تعديل حالة اليوم متاح للأيام خلال آخر 365 يوماً فقط' using errcode = '22023';
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
        if v_leave_type = 'unpaid' then
          raise exception 'لا يمكن للموظف طلب إجازة بدون راتب ذاتياً؛ تُمنح فقط بقرار من إدارة الموارد البشرية' using errcode = '22023';
        end if;
        if v_leave_type not in ('annual','casual','sick','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم: %', v_leave_type using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية الإجازة مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية الإجازة يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم إجازة تسبق أكثر من سنة' using errcode = '22023';
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
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم مأمورية تسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية المأمورية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل خارجية'),
          'days', ((v_end_date - v_start_date) + 1),
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
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم تكليف يسبق أكثر من سنة' using errcode = '22023';
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
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_correction_date < v_min_allowed_date then
          raise exception 'تاريخ التصحيح يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both','missing_check_in','missing_check_out') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
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

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  if p_request_type in ('mission', 'convoy', 'fundraising') and not v_day_mark and v_start_date = v_today then
    insert into public.mission_executions(
      request_id, employee_id, status, started_at, created_by)
    values(
      v_row.id, v_me, 'IN_PROGRESS', now(), auth.uid())
    on conflict (request_id) do nothing;
  end if;

  return v_row;
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;


-- ─── 2) تحديث دالة تذكيرات البصمة generate_punch_reminders لتلتزم بشفت كل موظف ───
create or replace function public.generate_punch_reminders(p_lead_minutes integer default 15)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_created integer := 0;
  v_now_cairo timestamptz := now();
  v_local timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_local::date;
  v_now_time time := v_local::time;
  v_dow integer := extract(isodow from v_local)::integer;  -- 1=إثنين .. 7=أحد
  v_lead integer := greatest(coalesce(p_lead_minutes, 15), 1);
  v_default_shift record;
  v_emp_shift record;
  v_emp record;
  v_daily public.attendance_daily;
  v_kind text;
  v_title text;
  v_body text;
begin
  -- قفل استشاري يمنع تشغيلَين متزامنين للوظيفة
  perform pg_advisory_xact_lock(hashtext('generate_punch_reminders'));
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة فقط عطلة أسبوعية
  if v_dow = 5 then
    return 0;
  end if;

  -- استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today and is_active = true) then
    return 0;
  end if;

  -- الوردية الافتراضية العامة
  select * into v_default_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  for v_emp in
    select e.id as employee_id, e.user_id, e.is_attendance_exempt, e.is_penalty_exempt
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
  loop
    -- 1. المعفى من البصمة وحده لا يُذكَّر
    if public.is_employee_attendance_exempt(v_emp.employee_id) then
      continue;
    end if;

    -- 2. استثناء الموظف المكلف بمهمة عمل أو قافلة رسمية اليوم
    if exists (
      select 1 from public.work_assignments wa
      where wa.responsible_employee_id = v_emp.employee_id
        and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
        and v_today between wa.start_at::date and wa.end_at::date
    ) then
      continue;
    end if;

    -- 3. استثناء الموظف إذا كان لديه طلب إجازة مسجل أو معتمد في leave_requests
    if exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and v_today between lr.start_date and lr.end_date
    ) then
      continue;
    end if;

    -- 4. استثناء الموظف إذا كان لديه طلب في requests يغطي اليوم
    if exists (
      select 1 from public.requests r
      where r.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
           and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                           and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          or (r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          or (r.request_type in ('remote_work', 'compensation')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
        )
    ) then
      continue;
    end if;

    -- 5. سجل اليوم للموظف
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id
      and work_date = v_today;

    if v_daily.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- تحديد وردية الموظف الخاصة بهذا اليوم بدقة
    v_emp_shift := null;
    select s.* into v_emp_shift
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
    where sa.employee_id = v_emp.employee_id
      and sa.is_active = true
      and sa.effective_from <= v_today
      and (sa.effective_to is null or sa.effective_to >= v_today)
    order by sa.effective_from desc
    limit 1;

    if v_emp_shift.id is null and v_daily.shift_id is not null then
      select * into v_emp_shift from public.shifts where id = v_daily.shift_id;
    end if;

    if v_emp_shift.id is null then
      v_emp_shift := v_default_shift;
    end if;

    if v_emp_shift.id is null then
      continue;
    end if;

    -- تحديد نوع التذكير حسب توقيت وردية الموظف الخاصة
    v_kind := null;
    if v_now_time >= (v_emp_shift.start_time - make_interval(mins := v_lead))
       and v_now_time < v_emp_shift.start_time
       and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'before_in';
      v_title := 'تذكير بالحضور';
      v_body := 'اقترب وقت بدء ورديتك (' || (to_char(v_emp_shift.start_time, 'hh12:mi') || case when extract(hour from v_emp_shift.start_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل البصمة.';
    elsif v_now_time >= v_emp_shift.start_time + make_interval(mins := coalesce(v_emp_shift.grace_in_minutes, 15))
          and v_now_time < v_emp_shift.start_time + make_interval(mins := coalesce(v_emp_shift.grace_in_minutes, 15) + v_lead)
          and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'late_in';
      v_title := '⚠️ تأخير في الحضور';
      v_body := 'لم تُسجَّل بصمة حضورك لوردية (' || (to_char(v_emp_shift.start_time, 'hh12:mi') || case when extract(hour from v_emp_shift.start_time) < 12 then ' ص' else ' م' end) || ') وتجاوزت فترة السماح. سجّل البصمة فوراً.';
    elsif v_now_time >= (v_emp_shift.end_time - make_interval(mins := v_lead))
          and v_now_time < v_emp_shift.end_time
          and v_daily.first_check_in is not null
          and v_daily.last_check_out is null then
      v_kind := 'before_out';
      v_title := 'تذكير بالانصراف';
      v_body := 'اقترب وقت انتهاء ورديتك (' || (to_char(v_emp_shift.end_time, 'hh12:mi') || case when extract(hour from v_emp_shift.end_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل بصمة الانصراف.';
    end if;

    if v_kind is null then
      continue;
    end if;

    -- 6. فحص أذونات الحضور والانصراف
    if v_kind in ('before_in', 'late_in') then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    if v_kind = 'before_out' then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('early_permit', 'permit')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    -- منع التكرار: نفس المستخدم/اليوم/النوع مرة واحدة
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
      'attendance',
      case when v_kind = 'late_in' then 'urgent' else 'high' end,
      '/attendance', 'punch_reminder', v_emp_shift.id,
      jsonb_build_object('kind', v_kind, 'workDate', v_today::text, 'shiftId', v_emp_shift.id)
    );
    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$function$;

revoke all on function public.generate_punch_reminders(integer) from public, anon;
grant execute on function public.generate_punch_reminders(integer) to authenticated, service_role;


-- ─── 3) تحديث دالة decide_attendance_correction لإلغاء الغرامات ورفع الإيقاف تلقائياً عند الاعتماد ───
create or replace function public.decide_attendance_correction(
  p_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.attendance_corrections;
  v_me  uuid := public.current_employee_id();
  v_effective_checkout timestamptz;
  v_cancelled_penalties integer := 0;
begin
  select * into strict v_row from public.attendance_corrections where id = p_id for update;

  if not (
    auth.role() = 'service_role'
    or public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','hr-manager','operations-manager-1'])
    or (
      v_row.employee_id is distinct from v_me
      and (
        public.can_access_employee(v_row.employee_id, 'attendance.correction.review')
        or public.is_manager_of(v_me, v_row.employee_id)
        or exists (
          select 1 from public.requests r
          where (r.payload->>'correctionId')::uuid = v_row.id
            and (r.manager_employee_id = v_me or r.created_by = auth.uid())
        )
      )
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_row.status = p_decision then
    return;
  end if;

  if v_row.status <> 'pending' or p_decision not in ('approved','rejected') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  if p_decision = 'rejected' and length(trim(coalesce(p_note, '')))<3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  v_effective_checkout := v_row.requested_check_out;
  if v_effective_checkout is not null then
    declare
      v_cur_checkin timestamptz;
    begin
      select first_check_in into v_cur_checkin from public.attendance_daily
       where employee_id = v_row.employee_id and work_date = v_row.work_date;
      if v_cur_checkin is not null and v_effective_checkout < v_cur_checkin then
        if v_effective_checkout + interval '1 day' > v_cur_checkin then
          v_effective_checkout := v_effective_checkout + interval '1 day';
        end if;
      end if;
    end;
  end if;

  update public.attendance_corrections
  set status = p_decision,
      reviewed_by = v_me,
      reviewed_at = now(),
      review_note = p_note,
      requested_check_out = v_effective_checkout,
      updated_at = now()
  where id = p_id;

  if p_decision = 'approved' then
    insert into public.attendance_daily(
      employee_id, work_date, first_check_in, last_check_out, status, late_minutes, is_finalized, created_by
    ) values (
      v_row.employee_id, v_row.work_date, v_row.requested_check_in, v_effective_checkout,
      coalesce(v_row.requested_status, 'present'), 0, false, auth.uid()
    )
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(v_row.requested_check_in, attendance_daily.first_check_in),
          last_check_out = coalesce(v_effective_checkout, attendance_daily.last_check_out),
          status = coalesce(v_row.requested_status, 'present'),
          late_minutes = 0,
          updated_at = now();

    -- إلغاء أي غرامة فورية متعلقة بهذا اليوم وتبريرها لاعتماد التصحيح
    with cancelled as (
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'اعتماد تصحيح البصمة إدارياً',
             notes = coalesce(notes || ' | ', '') || 'تم إلغاء الغرامة تلقائياً لاعتماد طلب تصحيح البصمة',
             updated_at = now()
       where employee_id = v_row.employee_id
         and work_date = v_row.work_date
         and status in ('pending_payment', 'doubled', 'suspended')
       returning id
    )
    select count(*) into v_cancelled_penalties from cancelled;

    -- رفع الإيقاف عن الموظف إن لم يعد لديه أي غرامات أخرى معلقة أو مضاعفة
    if not exists (
      select 1 from public.instant_attendance_penalties
      where employee_id = v_row.employee_id
        and status in ('doubled', 'suspended')
    ) then
      update public.employees
         set status = 'active',
             is_active = true,
             updated_at = now()
       where id = v_row.employee_id
         and status = 'suspended';

      update public.profiles
         set status = 'active',
             updated_at = now()
       where employee_id = v_row.employee_id
         and status = 'suspended';
    end if;

    if v_cancelled_penalties > 0 then
      perform public.log_audit_event(
        'penalty.cancelled_by_correction', 'finance', 'info',
        'instant_attendance_penalties', null,
        'إلغاء ' || v_cancelled_penalties || ' غرامة فورية لاعتماد تصحيح البصمة لتاريخ ' || v_row.work_date,
        p_note,
        jsonb_build_object('employeeId', v_row.employee_id, 'workDate', v_row.work_date, 'cancelledCount', v_cancelled_penalties)
      );
    end if;
  end if;

  -- مزامنة الطلب المرتبط إن وجد
  update public.requests
     set status = case when p_decision = 'approved' then 'approved' else 'rejected' end,
         workflow_status = case when p_decision = 'approved' then 'completed' else 'terminated' end,
         decided_at = now()
   where (payload->>'correctionId')::uuid = p_id
     and status = 'pending';

  perform public.notify_employee(
    v_row.employee_id,
    case when p_decision = 'approved' then 'تم قبول تصحيح الحضور وإلغاء أي غرامة مرتبطة' else 'تم رفض تصحيح الحضور' end,
    'تصحيح حضور بتاريخ ' || v_row.work_date || case when p_note is not null then ' — ' || p_note else '' end,
    'attendance', 'high', 'attendance_correction', p_id,
    jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date)
  );
end;
$$;

revoke all on function public.decide_attendance_correction(uuid, text, text) from public, anon;
grant execute on function public.decide_attendance_correction(uuid, text, text) to authenticated, service_role;


-- ─── 4) تسوية بيانات الحالات السابقة المعتمدة (مثل يوسف رسمي شعبان) ───
update public.instant_attendance_penalties p
   set status = 'cancelled',
       cancelled_reason = 'اعتماد تصحيح البصمة بأثر رجعي',
       notes = coalesce(p.notes || ' | ', '') || 'تسوية آلية: تم إلغاء الغرامة نظراً لاعتماد تصحيح البصمة لهذا اليوم',
       updated_at = now()
  from public.attendance_corrections c
 where c.employee_id = p.employee_id
   and c.work_date = p.work_date
   and c.status = 'approved'
   and p.status in ('pending_payment', 'doubled', 'suspended');

-- تسوية عبر جدول requests إن وجدت
update public.instant_attendance_penalties p
   set status = 'cancelled',
       cancelled_reason = 'اعتماد تصحيح البصمة بأثر رجعي',
       notes = coalesce(p.notes || ' | ', '') || 'تسوية آلية: تم إلغاء الغرامة نظراً لاعتماد طلب تصحيح البصمة لهذا اليوم',
       updated_at = now()
  from public.requests r
 where r.employee_id = p.employee_id
   and r.request_type = 'attendance_correction'
   and r.status = 'approved'
   and coalesce((r.payload->>'correctionDate')::date, (r.payload->>'date')::date, (r.payload->>'workDate')::date) = p.work_date
   and p.status in ('pending_payment', 'doubled', 'suspended');

-- تصفير late_minutes في attendance_daily لمن تم اعتماد تصحيح بصمتهم
update public.attendance_daily ad
   set late_minutes = 0,
       status = 'present',
       updated_at = now()
  from public.attendance_corrections c
 where c.employee_id = ad.employee_id
   and c.work_date = ad.work_date
   and c.status = 'approved'
   and coalesce(ad.late_minutes, 0) > 0;
