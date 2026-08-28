create or replace function public._admin_approve_request_immediately(
  p_request_id uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.requests;
  v_me uuid := public.current_employee_id();
begin
  if p_request_id is null then
    raise exception 'REQUEST_REQUIRED' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'requests.approve',
      'attendance.correction.review',
      'attendance.record.manual_create'
    ])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_row from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'REQUEST_NOT_PENDING' using errcode = '22023';
  end if;

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
        comment = 'اعتماد إداري مباشر من تصحيح يوم الحضور', updated_at = now()
    where request_id = v_row.id and status in ('active','pending');

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = v_row.id and status = 'running';

  insert into public.request_actions(
    request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
  values(
    v_row.id, v_me, 'system', 'pending', 'approved',
    'اعتماد إداري مباشر من تصحيح يوم الحضور',
    jsonb_build_object('source', 'attendance_day_editor'), auth.uid());

  perform public.log_audit_event(
    'attendance.day.request.approved', 'workflow', 'warning', 'requests', v_row.id,
    'اعتماد إداري مباشر لطلب يوم حضور',
    v_row.title,
    jsonb_build_object('requestType', v_row.request_type, 'employeeId', v_row.employee_id));

  return v_row;
end;
$$;



create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_days integer := 0;
  v_absent_days integer;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
begin
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  -- طبقة 0354: أعلام الطلبات المعلّقة + إلغاء الغياب + «بانتظار الاعتماد» +
  -- حقول العرض المنسّقة (فوق days من v286).
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';

    v_pending_leave := exists (
      select 1 from public.requests r
      join public.leave_requests lr on lr.request_id = r.id
      where lr.employee_id = p_employee_id
        and r.status = 'pending'
        and v_day between lr.start_date and lr.end_date
    );
    v_pending_mission := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy','fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه قاعدة أخرى (حضور فعلي/طلب معتمد/عطلة) → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    -- 0362: adminOverride.leaveType — إن كان v286 أخرج override لليوم.
    if (v_day_obj->'adminOverride') is not null then
      v_day_obj := jsonb_set(v_day_obj, '{adminOverride,leaveType}',
        to_jsonb((select o.leave_type from public.attendance_day_overrides o
          where o.employee_id = p_employee_id and o.work_date = v_day and o.is_active)),
        true);
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null and v_ci <> '' then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null and v_co <> '' then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer
      ),
      'status', v_status,
      'isAbsent', v_is_absent,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int
    from jsonb_array_elements(v_days) d
    where coalesce((d->>'isAbsent')::boolean, false));

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalRequiredHours')::numeric, 0) * 60))::integer
      ),
      'totalDeficitFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalDeficitMinutes')::integer, 0))
      ),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalLateMinutes')::integer, 0))
      ),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalEarlyLeaveMinutes')::integer, 0))
      )
    )
  );

  return v_result;
end
$$;



CREATE OR REPLACE FUNCTION public._build_attendance_statement_v186(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_emp record;
  v_start date;
  v_end date;
  v_days jsonb := '[]'::jsonb;
  v_day date;
  v_row record;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_day_obj jsonb;
  v_status text;
  v_scheduled_minutes integer;
  v_required_hours numeric;
  v_work_hours numeric;
  -- V23: متغيرات يومية إضافية
  v_is_absent boolean;
  v_is_holiday boolean;
  v_has_late_permit boolean;
  v_has_early_permit boolean;
  -- ملخصات
  v_total_days integer := 0;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_leave_days integer := 0;
  v_permit_count integer := 0;
  v_mission_days integer := 0;
  v_convoy_fundi_days integer := 0;
  v_total_work_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
  v_correction_count integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  -- V23: إجمالي الدقائق المطلوبة
  v_total_required_minutes integer := 0;
begin
  -- بيانات الموظف
  select e.id, e.employee_code, e.full_name_ar, e.full_name_en,
    e.hire_date, e.birth_date,
    coalesce(d.name, '') as department_name,
    coalesce(jt.name, jt.name_en, '') as job_title,
    coalesce(b.name, '') as branch_name,
    coalesce(mgr.full_name_ar, '') as manager_name
  into v_emp
  from public.employees e
  left join public.departments d on d.id = e.department_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.branches b on b.id = e.branch_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and mr.relation_type = 'primary'
    and (mr.effective_to is null or mr.effective_to >= current_date)
  left join public.employees mgr on mgr.id = mr.manager_employee_id
  where e.id = p_employee_id;

  if v_emp.id is null then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month' - interval '1 day')::date;
  v_total_days := v_end - v_start + 1;

  -- بناء الجدول اليومي
  v_day := v_start;
  while v_day <= v_end loop
    -- تصفير المتغيرات اليومية
    v_is_absent := false;
    v_is_holiday := false;
    v_has_late_permit := false;
    v_has_early_permit := false;

    -- بيانات الحضور اليومي
    select * into v_row from public.attendance_daily a
    where a.employee_id = p_employee_id and a.work_date = v_day;

    -- الوردية
    v_scheduled_minutes := 0;
    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    if v_row.shift_id is not null then
      select s.name, s.start_time, s.end_time, s.crosses_midnight, coalesce(s.break_minutes,0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses, v_shift_break
      from public.shifts s where s.id = v_row.shift_id;
      if v_shift_start is not null then
        v_scheduled_minutes := greatest(0,
          case when v_shift_crosses
               then extract(epoch from ((v_shift_end + interval '24 hours') - v_shift_start))/60
               else extract(epoch from (v_shift_end - v_shift_start))/60
          end - v_shift_break)::integer;
      end if;
    end if;

    v_required_hours := round(v_scheduled_minutes / 60.0, 2);
    v_work_hours := round(coalesce(v_row.work_minutes, 0) / 60.0, 2);

    -- تحديد حالة اليوم المفصّلة
    v_status := coalesce(v_row.status, 'absent');

    -- هل هو يوم عطلة رسمية؟
    if exists (select 1 from public.public_holidays h
               where h.is_active and v_day between h.holiday_date and coalesce(h.end_date, h.holiday_date)) then
      v_status := 'عطلة رسمية';
      v_holiday_days := v_holiday_days + 1;
      v_is_holiday := true;
    -- هل هو يوم راحة (الجمعة فقط)؟
    elsif extract(isodow from v_day) = 5 then
      v_status := 'راحة أسبوعية';
      v_rest_days := v_rest_days + 1;
    -- هل هو روستر راحة/عطلة؟
    elsif exists (select 1 from public.roster_days rd
                  where rd.employee_id = p_employee_id and rd.work_date = v_day
                    and rd.day_status in ('rest','holiday')
                    and rd.day_status <> 'cancelled') then
      v_status := case (select rd.day_status from public.roster_days rd
                        where rd.employee_id = p_employee_id and rd.work_date = v_day
                          and rd.day_status <> 'cancelled' limit 1)
                   when 'rest' then 'راحة أسبوعية'
                   else 'عطلة رسمية' end;
      if v_status = 'راحة أسبوعية' then v_rest_days := v_rest_days + 1;
      else
        v_holiday_days := v_holiday_days + 1;
        v_is_holiday := true;
      end if;
    else
      -- يوم مجدول — نحسبه
      v_scheduled_days := v_scheduled_days + 1;
      -- V23: تراكم الدقائق المطلوبة
      v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;

      -- مأمورية عمل (work_assignments)?
      if exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id and wa.status = 'APPROVED'
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at at time zone 'Africa/Cairo')::date
      ) then
        -- نوع التكليف
        v_status := coalesce(
          (select case wa.assignment_type
                   when 'MISSION' then 'مأمورية عمل'
                   when 'CONVOY' then 'قافلة'
                   when 'FUNDRAISING' then 'فاندي'
                 end
           from public.work_assignment_participants wp
           join public.work_assignments wa on wa.id = wp.assignment_id
           where wp.employee_id = p_employee_id and wa.status = 'APPROVED'
             and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                           and (wa.end_at at time zone 'Africa/Cairo')::date
           limit 1),
          'مأمورية عمل');
        if v_status = 'مأمورية عمل' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;
      -- مأمورية قديمة (missions table)?-- إجازة معتمدة؟
      elsif v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id and r.status = 'approved'
          and v_day between lr.start_date and lr.end_date
      ) then
        v_status := 'إجازة معتمدة';
        v_leave_days := v_leave_days + 1;
      
      elsif exists (
        select 1 from public.missions m
        join public.requests r on r.id = m.request_id
        where m.employee_id = p_employee_id and r.status = 'approved'
          and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                        and (m.end_at at time zone 'Africa/Cairo')::date
      ) then
        v_status := 'مأمورية عمل';
        v_mission_days := v_mission_days + 1;
      -- حاضر/متأخر/جزئي/غائب
      elsif v_row.id is not null then
        v_status := case v_row.status
          when 'present' then 'حاضر'
          when 'late' then 'متأخر'
          when 'partial' then 'حضور ناقص'
          when 'pending' then 'يحتاج مراجعة'
          when 'absent' then 'غائب دون إذن'
          else coalesce(v_row.status, 'غائب دون إذن')
        end;
        if v_row.status = 'absent' then
          v_absent_days := v_absent_days + 1;
          v_is_absent := true;
        elsif v_row.status in ('present','late','partial') then
          v_present_days := v_present_days + 1;
        end if;
      else
        v_status := 'غائب دون إذن';
        v_absent_days := v_absent_days + 1;
        v_is_absent := true;
      end if;
    end if;

    -- V23: إذن تأخير/انصراف مبكر (مفصّل)
    select
      exists(select 1 from public.attendance_permits p
             where p.employee_id = p_employee_id and p.permit_date = v_day
               and p.status = 'approved' and p.kind = 'arrival'),
      exists(select 1 from public.attendance_permits p
             where p.employee_id = p_employee_id and p.permit_date = v_day
               and p.status = 'approved' and p.kind = 'departure')
    into v_has_late_permit, v_has_early_permit;

    -- إذن حضور؟ (عدّاد تجميعي — يشمل الاثنين)
    if v_has_late_permit or v_has_early_permit then
      v_permit_count := v_permit_count + 1;
    end if;

    -- تصحيح معتمد؟
    if exists (select 1 from public.attendance_corrections c
               where c.employee_id = p_employee_id and c.work_date = v_day
                 and c.status = 'approved') then
      v_correction_count := v_correction_count + 1;
      if v_status = 'غائب دون إذن' or v_status = 'يحتاج مراجعة' then
        v_status := 'تصحيح معتمد';
        -- التصحيح يُلغي الغياب
        if v_is_absent then
          v_is_absent := false;
          v_absent_days := greatest(0, v_absent_days - 1);
          v_present_days := v_present_days + 1;
        end if;
      end if;
    end if;

    -- نسيان ختم
    if v_row.id is not null and v_row.status not in ('on_leave','holiday','weekend')
       and v_status not like '%عطلة%' and v_status not like '%راحة%'
       and v_status <> 'إجازة معتمدة' and v_status not like '%مأمورية%'
       and v_status not like '%قافلة%' and v_status not like '%فاندي%' then
      if v_row.first_check_in is null and v_row.status <> 'absent' then
        v_missing_checkin := v_missing_checkin + 1;
      end if;
      if v_row.last_check_out is null and v_row.first_check_in is not null then
        v_missing_checkout := v_missing_checkout + 1;
      end if;
    end if;

    -- تراكمات
    v_total_work_minutes := v_total_work_minutes + coalesce(v_row.work_minutes, 0);
    v_total_late_minutes := v_total_late_minutes + coalesce(v_row.late_minutes, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce(v_row.early_leave_minutes, 0);
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_row.overtime_minutes, 0);

    -- بناء صف اليوم (مع حقول V23)
    v_day_obj := jsonb_build_object(
      'date', v_day,
      'dayName', to_char(v_day, 'Dy'),
      'dayNameAr', case extract(isodow from v_day)
        when 1 then 'الاثنين' when 2 then 'الثلاثاء' when 3 then 'الأربعاء'
        when 4 then 'الخميس' when 5 then 'الجمعة' when 6 then 'السبت' when 7 then 'الأحد' end,
      'checkIn', (v_row.first_check_in at time zone 'Africa/Cairo')::time(0),
      'checkOut', (v_row.last_check_out at time zone 'Africa/Cairo')::time(0),
      'shiftName', v_shift_name,
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'workHours', v_work_hours,
      'requiredHours', v_required_hours,
      'lateMinutes', coalesce(v_row.late_minutes, 0),
      'earlyLeaveMinutes', coalesce(v_row.early_leave_minutes, 0),
      'overtimeMinutes', coalesce(v_row.overtime_minutes, 0),
      'status', v_status,
      -- V23: حقول بوليانية مفصّلة
      'isAbsent', v_is_absent,
      'isOfficialHoliday', v_is_holiday,
      'hasLeave', (v_status = 'إجازة معتمدة'),
      'hasLatePermit', v_has_late_permit,
      'hasEarlyPermit', v_has_early_permit,
      'hasPermit', (v_has_late_permit or v_has_early_permit),
      'hasMission', (v_status like '%مأمورية%'),
      'hasConvoyFundi', (v_status like '%قافلة%' or v_status like '%فاندي%'),
      'missingCheckIn', (v_row.first_check_in is null and v_row.status not in ('absent','on_leave','holiday','weekend')
                         and v_status not like '%عطلة%' and v_status not like '%راحة%'
                         and v_status <> 'إجازة معتمدة' and v_status not like '%مأمورية%'
                         and v_status not like '%قافلة%' and v_status not like '%فاندي%'),
      'missingCheckOut', (v_row.last_check_out is null and v_row.first_check_in is not null),
      'hasCorrection', exists(select 1 from public.attendance_corrections c
                              where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved'),
      'correctionNote', (select c.reason from public.attendance_corrections c
                         where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved' limit 1),
      -- V23: ملاحظات وجزاءات
      'notes', null::text,
      'penalties', 0
    );

    v_days := v_days || v_day_obj;
    v_day := v_day + 1;
  end loop;

  return jsonb_build_object(
    'employee', jsonb_build_object(
      'id', v_emp.id,
      'employeeCode', v_emp.employee_code,
      'fullNameAr', v_emp.full_name_ar,
      'jobTitle', v_emp.job_title,
      'department', v_emp.department_name,
      'manager', v_emp.manager_name,
      'branch', v_emp.branch_name,
      'hireDate', v_emp.hire_date
    ),
    'period', jsonb_build_object(
      'year', p_year, 'month', p_month,
      'startDate', v_start, 'endDate', v_end,
      'generatedAt', (now() at time zone 'Africa/Cairo')
    ),
    'days', v_days,
    'summary', jsonb_build_object(
      'totalDays', v_total_days,
      'scheduledDays', v_scheduled_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'leaveDays', v_leave_days,
      'permitCount', v_permit_count,
      'missionDays', v_mission_days,
      'convoyFundiDays', v_convoy_fundi_days,
      'holidayDays', v_holiday_days,
      'restDays', v_rest_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      -- V23: إجمالي الساعات المطلوبة
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_present_days > 0
        then round(v_total_work_minutes / 60.0 / v_present_days, 2) else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'correctionCount', v_correction_count,
      -- V23: نسب الحضور والالتزام
      'attendanceRate', case when v_scheduled_days > 0
        then round(v_present_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_total_work_minutes * 100.0 / v_total_required_minutes, 2)) else 0 end
    )
  );
end $function$;



create or replace function public._build_attendance_statement_v287(p_employee_id uuid, p_year integer, p_month integer)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_type text;
  v_check_in time;
  v_check_out time;
  v_work_minutes integer;
  v_required_minutes integer;
  v_scheduled boolean;
  v_present boolean;
  v_covered boolean;
  v_is_future boolean;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_covered_days integer := 0;
  v_total_work_minutes integer := 0;
  v_month_required_minutes integer := 0;
  v_month_deficit_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_open_shift_days integer := 0;
  v_completed_days integer := 0;
  v_absent_days integer := 0;
  v_upcoming_days integer := 0;
  v_leave_days integer := 0;
  v_mission_days integer := 0;
  v_convoy_days integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  v_due_days integer := 0;
  v_is_due boolean;
  v_is_open boolean;
begin
  v_result := public._build_attendance_statement_v266(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_override := null;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    v_type := coalesce(v_override.day_type, '');
    v_check_in := nullif(v_day_obj->>'checkIn', '')::time;
    v_check_out := nullif(v_day_obj->>'checkOut', '')::time;

    if v_override.id is not null then
      if v_override.clear_check_in then v_check_in := null;
      elsif v_override.check_in_override is not null then v_check_in := v_override.check_in_override;
      end if;
      if v_override.clear_check_out then v_check_out := null;
      elsif v_override.check_out_override is not null then v_check_out := v_override.check_out_override;
      end if;
    end if;

    -- Friday and official holidays are not monthly work days.
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_type not in ('holiday','rest');
    v_is_future := v_scheduled and v_day > (now() at time zone 'Africa/Cairo')::date;

    if v_type in ('leave','mission','convoy','fundraising','holiday','rest','absent') then
      v_check_in := null;
      v_check_out := null;
    end if;

    v_work_minutes := 0;
    if v_check_in is not null and v_check_out is not null then
      v_work_minutes := greatest(0, (extract(epoch from (
        (v_day + v_check_out + case when v_check_out <= v_check_in then interval '1 day' else interval '0' end)
        - (v_day + v_check_in)
      )) / 60)::integer);
    end if;

    v_required_minutes := case when v_scheduled
      then greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60)::integer)
      else 0 end;
    if v_scheduled and v_required_minutes = 0 then v_required_minutes := 480; end if;

    v_present := v_scheduled and v_check_in is not null;
    v_covered := v_scheduled and (
      v_present
      or v_type in ('leave','mission','convoy','fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    v_is_open := v_check_in is not null and v_check_out is null and not v_is_future;
    v_is_due := v_scheduled and not v_is_future and not v_is_open and not (
      v_type in ('leave', 'mission', 'convoy', 'fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    if v_scheduled then
      v_scheduled_days := v_scheduled_days + 1;
      v_month_required_minutes := v_month_required_minutes + v_required_minutes;
      if v_present then v_present_days := v_present_days + 1; end if;
      if v_is_due then v_due_days := v_due_days + 1; end if;
      if v_covered then v_covered_days := v_covered_days + 1; end if;
      if v_is_future then v_upcoming_days := v_upcoming_days + 1; end if;
      if not v_is_future and not v_covered and v_type <> 'leave' then
        v_absent_days := v_absent_days + 1;
      end if;
    end if;

    if v_check_in is not null and v_check_out is null and not v_is_future then
      v_open_shift_days := v_open_shift_days + 1;
    end if;
    if v_check_in is not null and v_check_out is not null then
      v_completed_days := v_completed_days + 1;
      v_total_work_minutes := v_total_work_minutes + v_work_minutes;
      v_month_deficit_minutes := v_month_deficit_minutes + greatest(0, v_required_minutes - v_work_minutes);
      v_total_overtime_minutes := v_total_overtime_minutes + greatest(0, v_work_minutes - v_required_minutes);
    end if;

    if v_type = 'leave' or (v_override.id is null and coalesce((v_day_obj->>'hasLeave')::boolean, false)) then
      v_leave_days := v_leave_days + 1;
    end if;
    if v_type = 'mission' or (v_override.id is null and coalesce((v_day_obj->>'hasMission')::boolean, false)) then
      v_mission_days := v_mission_days + 1;
    end if;
    if v_type in ('convoy','fundraising') or (v_override.id is null and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then
      v_convoy_days := v_convoy_days + 1;
    end if;
    if not v_scheduled then
      if extract(isodow from v_day) = 5 or v_type = 'rest' then v_rest_days := v_rest_days + 1;
      else v_holiday_days := v_holiday_days + 1;
      end if;
    end if;

    -- Flexible duration policy: no late/early penalty when duration is what matters.
    if v_scheduled then
      v_total_late_minutes := v_total_late_minutes + 0;
      v_total_early_minutes := v_total_early_minutes + 0;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn', case when v_check_in is null then null else to_char(v_check_in, 'HH24:MI') end,
      'checkOut', case when v_check_out is null then null else to_char(v_check_out, 'HH24:MI') end,
      'workHours', round(v_work_minutes / 60.0, 2),
      'requiredHours', round(v_required_minutes / 60.0, 2),
      'lateMinutes', 0,
      'earlyLeaveMinutes', 0,
      'overtimeMinutes', greatest(0, v_work_minutes - v_required_minutes),
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', (v_check_in is not null and v_check_out is not null),
      'isAbsent', (v_scheduled and not v_is_future and not v_covered),
      'hasLeave', case when v_override.id is null then coalesce((v_day_obj->>'hasLeave')::boolean, false) else v_type = 'leave' end,
      'hasMission', case when v_override.id is null then coalesce((v_day_obj->>'hasMission')::boolean, false) else v_type = 'mission' end,
      'hasConvoyFundi', case when v_override.id is null then coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) else v_type in ('convoy','fundraising') end,
      'hasCorrection', (v_override.id is not null) or coalesce((v_day_obj->>'hasCorrection')::boolean, false),
      'correctionNote', coalesce(v_override.notes, v_override.reason, v_day_obj->>'correctionNote'),
      'adminOverride', case when v_override.id is null then null else jsonb_build_object(
        'id', v_override.id,
        'dayType', v_override.day_type,
        'reason', v_override.reason,
        'notes', v_override.notes,
        'updatedAt', v_override.updated_at
      ) end,
      'status', case
        when extract(isodow from v_day) = 5 then 'راحة أسبوعية'
        when v_type = 'holiday' then 'عطلة رسمية'
        when v_type = 'rest' then 'راحة أسبوعية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasMission')::boolean, false) then 'مأمورية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
             and v_day_obj->>'status' = 'فاندي' then 'فاندي'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) then 'قافلة'
        when v_type = 'leave' then 'إجازة معتمدة'
        when v_type = 'mission' then 'مأمورية'
        when v_type = 'convoy' then 'قافلة'
        when v_type = 'fundraising' then 'فاندي'
        when v_type = 'absent' then 'غائب دون إذن'
        when v_override.id is null
             and (coalesce((v_day_obj->>'hasLeave')::boolean, false)
                  or coalesce((v_day_obj->>'hasMission')::boolean, false)
                  or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then v_day_obj->>'status'
        when v_is_future then 'يوم قادم'
        when v_check_in is not null and v_check_out is null then 'حاضر — بانتظار الانصراف'
        when v_check_in is not null and v_check_out is not null and v_work_minutes < v_required_minutes then 'حاضر — ساعات غير مكتملة'
        when v_check_in is not null and v_check_out is not null then 'حاضر'
        when not v_scheduled then v_day_obj->>'status'
        else 'غائب دون إذن'
      end
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'capabilities', jsonb_build_object(
      'canEditDays', public.current_is_full_access()
        or public.can_access_employee(p_employee_id, 'attendance.correction.review')
        or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
    ),
    'summary', (v_result->'summary') || jsonb_build_object(
      'scheduledDays', v_scheduled_days,
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_days,
      'leaveDays', v_leave_days,
      'missionDays', v_mission_days,
      'convoyFundiDays', v_convoy_days,
      'holidayDays', v_holiday_days,
      'restDays', v_rest_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_month_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_days > 0 then round(v_total_work_minutes / 60.0 / v_completed_days, 2) else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'totalDeficitMinutes', v_month_deficit_minutes,
      'attendanceRate', case when v_due_days > 0
        then round((v_present_days - v_open_shift_days) * 100.0 / v_due_days, 2)
        else 0 end,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', (v_present_days - v_open_shift_days),
        'dueDays', v_due_days,
        'presentDays', v_present_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_shift_days,
        'upcomingDays', v_upcoming_days
      ),
      'coverageRate', case when v_scheduled_days > 0 then round(v_covered_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'coverageDays', v_covered_days,
      'hoursComplianceAvailable', (v_month_required_minutes > 0),
      'hoursComplianceRate', case when v_month_required_minutes > 0
        then least(100, round(v_total_work_minutes * 100.0 / v_month_required_minutes, 2)) else 0 end,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_total_work_minutes,
        'requiredMinutes', v_month_required_minutes,
        'scheduledDays', v_scheduled_days,
        'deficitMinutes', v_month_deficit_minutes,
        'overtimeMinutes', v_total_overtime_minutes
      ),
      'compliantWorkMinutes', v_total_work_minutes,
      'requiredMinutes', v_month_required_minutes
    )
  );

  return v_result;
end
$function$;



create or replace function public._cleanup_user_sessions_and_push(
  p_user_id uuid,
  p_reason text default 'device_revoked'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- حذف الجلسات النشطة
  delete from auth.sessions where user_id = p_user_id;
  -- حذف refresh tokens
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  -- تعطيل اشتراكات الدفع
  update public.push_subscriptions
  set is_active = false, updated_at = now()
  where user_id = p_user_id and is_active = true;
end;
$$;



create or replace function public._fmt_minutes_ar(p_minutes integer)
returns text
language sql immutable
as $$
  select case
    when p_minutes is null or p_minutes < 0 then '—'
    when p_minutes = 0 then '0 د'
    when p_minutes < 60 then p_minutes || ' د'
    when p_minutes % 60 = 0 then (p_minutes / 60) || ' س'
    else (p_minutes / 60) || ' س و ' || (p_minutes % 60) || ' د'
  end;
$$;



create or replace function public._fmt_time_12h(p_time time)
returns text
language sql immutable
as $$
  select case
    when p_time is null then null
    when extract(hour from p_time) = 0
      then lpad((12)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' ص'
    when extract(hour from p_time) < 12
      then lpad(extract(hour from p_time)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' ص'
    when extract(hour from p_time) = 12
      then '12:' || lpad(extract(minute from p_time)::text, 2, '0') || ' م'
    else lpad((extract(hour from p_time) - 12)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' م'
  end;
$$;



create or replace function public._on_primary_department_removed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_next uuid;
begin
  if not old.is_primary then return old; end if;

  -- ابحث عن أقدم إدارة متبقية
  select id into v_next
  from public.employee_departments
  where employee_id = old.employee_id and id <> old.id
  order by assigned_at
  limit 1;

  if v_next is not null then
    update public.employee_departments set is_primary = true where id = v_next;
  else
    update public.employees set department_id = null where id = old.employee_id;
  end if;

  return old;
end $$;



CREATE OR REPLACE FUNCTION public._submit_request_for(p_employee_id uuid, p_request_type text, p_workflow_definition_id uuid DEFAULT NULL::uuid, p_manager_employee_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_exec_emp       uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- التعريف الافتراضي لسير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء خطوات الجارية
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- إشعار المدير المباشر (أول خطوة نشطة)
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'workflowStatus', 'submitted',
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  -- إشعار المدير التنفيذي — إنباه كامل الشاشة على كل طلب جديد
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'طلب جديد — للمراجعة',
      v_label,
      'request',
      'request', v_row.id,
      '/requests/' || v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', false
      )
    );
  end if;

  return v_row;
end;
$function$;



create or replace function public._sync_primary_department()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- عند وضع إدارة كأساسية، أزل العلامة من الإدارات الأخرى لنفس الموظف
  if new.is_primary then
    update public.employee_departments
      set is_primary = false
    where employee_id = new.employee_id
      and id <> new.id
      and is_primary;

    -- مزامنة employees.department_id
    update public.employees
      set department_id = new.department_id
    where id = new.employee_id;
  end if;

  return new;
end $$;



CREATE OR REPLACE FUNCTION public.acknowledge_announcement(p_announcement_id uuid)
 RETURNS announcement_acknowledgements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.announcement_acknowledgements;
begin
  if v_me is null then raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode='42501'; end if;
  if not exists(select 1 from public.announcements a where a.id=p_announcement_id and a.status='published') then
    raise exception 'announcement not available' using errcode='P0002';
  end if;
  insert into public.announcement_acknowledgements(announcement_id,employee_id,created_by)
  values(p_announcement_id,v_me,auth.uid())
  on conflict(announcement_id,employee_id) do update set acknowledged_at=excluded.acknowledged_at,updated_at=now()
  returning * into v_row;
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.acknowledge_decision(p_decision_id uuid, p_acknowledge boolean DEFAULT true)
 RETURNS decision_reads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me   uuid := public.current_employee_id();
  v_row  public.decision_reads;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- يجب أن يكون الموظف مستهدفاً بالقرار (target-scoped)
  if not exists (
    select 1 from public.decision_recipients dr
    where dr.decision_id = p_decision_id and dr.employee_id = v_me
  ) then
    raise exception 'القرار ليس موجهاً لهذا الموظف' using errcode = '42501';
  end if;

  insert into public.decision_reads (
    decision_id, employee_id, read_at, acknowledged, acknowledged_at, created_by
  ) values (
    p_decision_id, v_me, now(), coalesce(p_acknowledge, false),
    case when p_acknowledge then now() else null end, auth.uid()
  )
  on conflict (decision_id, employee_id) do update
    set acknowledged    = greatest(public.decision_reads.acknowledged::int, excluded.acknowledged::int)::boolean,
        acknowledged_at = coalesce(public.decision_reads.acknowledged_at, excluded.acknowledged_at),
        updated_at      = now()
  returning * into v_row;

  return v_row;
end;
$function$;



create or replace function public.acknowledge_dispute_decision(p_decision_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_case uuid;
begin
 select case_id into strict v_case from public.dispute_decisions where id=p_decision_id and status in ('issued','implemented');
 if not public.can_access_dispute(v_case) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 insert into public.dispute_decision_receipts(decision_id,employee_id,created_by) values(p_decision_id,v_emp,auth.uid()) on conflict do nothing;
 perform public.log_audit_event('dispute.decision_acknowledged','workflow','info','dispute_decisions',p_decision_id,'تأكيد الاطلاع على القرار');
end $$;



create or replace function public.acknowledge_kpi_evaluation(
 p_evaluation_id uuid, p_note text default null, p_appeal_reason text default null
)
returns public.kpi_evaluations
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_eval public.kpi_evaluations;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.employee_id<>public.current_employee_id() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if not v_eval.locked or v_eval.current_stage<>'finalized' then raise exception 'KPI_NOT_FINALIZED'; end if;
 if length(coalesce(p_note,''))>2000 or length(coalesce(p_appeal_reason,''))>2000
  then raise exception 'NOTE_TOO_LONG'; end if;

 if coalesce(trim(p_appeal_reason),'')<>'' then
  -- الاعتراض لا يغيّر الحالة المقفلة؛ يوثَّق ويُبلَّغ للموافق لحسمه
  perform public.log_audit_event('kpi.result.disputed','workflow','warning','kpi_evaluations',v_eval.id,
   'اعتراض الموظف على نتيجة التقييم',trim(p_appeal_reason),
   jsonb_build_object('finalScore',v_eval.final_score,'approver',public.kpi_resolve_approver_for_employee(v_eval.employee_id)));
 else
  update public.kpi_evaluations set workflow_status='EMPLOYEE_ACKNOWLEDGED',updated_at=now()
   where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.result.acknowledged','workflow','notice','kpi_evaluations',v_eval.id,
   'إقرار الموظف بنتيجة تقييمه',nullif(trim(p_note),''),null);
 end if;
 return v_eval;
end $$;



create or replace function public.acknowledge_policy(p_policy_id uuid)
returns public.policy_acknowledgements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_row public.policy_acknowledgements;
begin
  v_employee_id := public.current_employee_id();
  if v_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بالمستخدم الحالي';
  end if;

  if not exists (select 1 from public.policies p where p.id = p_policy_id and p.status = 'published') then
    raise exception 'السياسة غير موجودة أو غير منشورة';
  end if;

  insert into public.policy_acknowledgements (policy_id, employee_id, acknowledged_at, created_by)
  values (p_policy_id, v_employee_id, now(), auth.uid())
  on conflict (policy_id, employee_id)
  do update set acknowledged_at = now(), updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;



create or replace function public.activate_employee_after_first_login()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_old_status text;
  v_profile_old_status text;
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Find the employee record for this user
  select id, status into v_employee_id, v_old_status
  from public.employees
  where user_id = v_user_id and is_active = true and is_deleted = false;

  if v_employee_id is null then
    -- No employee record — might be a web-only user or already active
    return jsonb_build_object('activated', false, 'reason', 'no_employee_record');
  end if;

  -- If already active, nothing to do
  if v_old_status = 'active' then
    return jsonb_build_object('activated', false, 'reason', 'already_active');
  end if;

  -- Activate employee
  update public.employees
  set status = 'active', updated_at = now()
  where id = v_employee_id;

  -- Activate profile
  update public.profiles
  set status = 'active', updated_at = now()
  where id = v_user_id;

  -- Log the activation
  perform public.log_audit_event(
    'employee.activated',
    'onboarding',
    'info',
    'employees',
    v_employee_id,
    'تفعيل الموظف بعد أول دخول وتغيير كلمة المرور',
    null,
    jsonb_build_object('old_status', v_old_status, 'new_status', 'active')
  );

  return jsonb_build_object(
    'activated', true,
    'employeeId', v_employee_id,
    'oldStatus', v_old_status
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.activate_verified_passkey_device(p_employee_id uuid, p_user_id uuid, p_credential_id text, p_public_key text, p_sign_count bigint, p_transports text[], p_device_label text, p_webauthn_user_id text, p_credential_device_type text, p_credential_backed_up boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_credential public.passkey_credentials;
  v_device public.employee_devices;
  v_hash text;
begin
  if p_employee_id is null or p_user_id is null or nullif(trim(p_credential_id), '') is null then
    raise exception 'هوية جهاز موثّق مطلوبة' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.employees
    where id = p_employee_id and user_id = p_user_id
  ) then
    raise exception 'employee/user link mismatch' using errcode = '42501';
  end if;

  -- passkey_credentials تبقى active (هي credential فنية، ليست سياسة موافقة)
  insert into public.passkey_credentials(
    employee_id, user_id, credential_id, public_key, sign_count,
    transports, device_label, status, trusted, webauthn_user_id,
    credential_device_type, credential_backed_up, created_by
  ) values (
    p_employee_id, p_user_id, p_credential_id, p_public_key, p_sign_count,
    p_transports, left(coalesce(p_device_label, 'هاتف الموظف'), 120),
    'active', true, nullif(p_webauthn_user_id, ''),
    p_credential_device_type, p_credential_backed_up, p_user_id
  ) returning * into v_credential;

  v_hash := encode(digest(convert_to(p_credential_id, 'UTF8'), 'sha256'), 'hex');
  -- V18 Â§5: الجهاز يُسجَّل بحالة pending وينتظر موافقة المسؤول
  insert into public.employee_devices(
    employee_id, user_id, device_identifier_hash, credential_id, public_key,
    device_name, platform, status, registered_at, metadata
  ) values (
    p_employee_id, p_user_id, v_hash, p_credential_id, p_public_key,
    left(coalesce(p_device_label, 'هاتف الموظف'), 120), 'android', 'pending', now(),
    jsonb_build_object(
      'serverVerified', true,
      'credentialDeviceType', p_credential_device_type,
      'credentialBackedUp', p_credential_backed_up,
      'passkeyCredentialId', v_credential.id
    )
  )
  on conflict (employee_id, device_identifier_hash) do update set
    user_id = excluded.user_id,
    credential_id = excluded.credential_id,
    public_key = excluded.public_key,
    device_name = excluded.device_name,
    status = 'pending',
    revoked_at = null,
    registered_at = now(),
    approved_by = null,
    approved_at = null,
    rejection_reason = null,
    metadata = excluded.metadata
  returning * into v_device;

  return jsonb_build_object(
    'id', v_credential.id,
    'credential_id', v_credential.credential_id,
    'device_label', v_credential.device_label,
    'status', 'pending',
    'created_at', v_credential.created_at,
    'device_id', v_device.id,
    'verified', true,
    'requiresApproval', true
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.add_daily_report_comment(p_report_id uuid, p_comment text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'التعليق مطلوب' using errcode = '22023';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  insert into public.daily_report_comments (report_id, employee_id, comment)
  values (p_report_id, v_me, trim(p_comment))
  returning id into v_id;

  if v_author is distinct from v_me then
    perform public.notify_employee(
      v_author,
      'تعليق جديد على تقريرك اليومي',
      trim(p_comment),
      'general', 'normal', 'daily_reports', p_report_id,
      jsonb_build_object('event', 'daily_report_comment', 'commentId', v_id)
    );
  end if;

  return v_id;
end;
$function$;



CREATE OR REPLACE FUNCTION public.add_employee_penalty(p_employee_id uuid, p_penalty_type text, p_amount numeric, p_reason text, p_evidence_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'لا يوجد ملف موظف لصاحب الطلب' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'مبلغ غير صالح' using errcode='22023'; end if;
  if nullif(trim(p_penalty_type), '') is null then raise exception 'نوع جزاء غير صالح' using errcode='22023'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists (select 1 from public.employees where id = p_employee_id and not is_deleted) then
    raise exception 'employee not found' using errcode='P0002';
  end if;

  insert into public.employee_penalties(
    employee_id, penalty_type, amount, currency, reason, evidence_ref,
    status, issued_by, issued_at, created_by)
  values (
    p_employee_id, p_penalty_type, p_amount, 'EGP', p_reason, p_evidence_ref,
    'issued', v_me, now(), auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'penalty.issued', 'financial', 'warning',
    'employee_penalties', v_row.id, 'إصدار مخالفة مالية', null,
    jsonb_build_object('employeeId', p_employee_id, 'amount', p_amount, 'type', p_penalty_type));

  return jsonb_build_object(
    'id', v_row.id, 'employeeId', v_row.employee_id, 'amount', v_row.amount,
    'penaltyType', v_row.penalty_type, 'status', v_row.status, 'issuedAt', v_row.issued_at);
end $function$;



create or replace function public.add_kpi_evidence(p_evaluation_id uuid,p_criterion_id uuid,p_type text,p_title text,p_description text default null,p_storage_path text default null,p_external_url text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_stage text; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.locked then raise exception 'EVALUATION_LOCKED'; end if;
 if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_stage:='self';
 elsif v_eval.current_stage in ('manager_review','parallel_review') and public.kpi_is_direct_manager(v_eval.employee_id) then v_stage:=v_eval.current_stage;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_type not in ('document','link','note','task','report','other') or length(trim(coalesce(p_title,'')))<3 then raise exception 'INVALID_EVIDENCE'; end if;
 if p_criterion_id is not null and not exists(select 1 from public.kpi_criteria where id=p_criterion_id and template_id=v_eval.template_id) then raise exception 'INVALID_CRITERION'; end if;
 insert into public.kpi_evidence(evaluation_id,criterion_id,evidence_type,title,description,storage_path,external_url,submitted_stage,submitted_by,created_by)
 values(p_evaluation_id,p_criterion_id,p_type,trim(p_title),p_description,p_storage_path,p_external_url,v_stage,public.current_employee_id(),auth.uid()) returning id into v_id;
 perform public.log_audit_event('kpi.evidence.added','workflow','info','kpi_evidence',v_id,'إضافة دليل إلى التقييم',null,jsonb_build_object('evaluationId',p_evaluation_id,'criterionId',p_criterion_id));
 return v_id;
end $$;



create or replace function public.adjust_leave_balance(
  p_employee_id uuid,p_leave_type_id uuid,p_year integer,p_units numeric,p_reason text
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_entry public.leave_ledger_entries;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then raise exception 'FORBIDDEN'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
  v_entry := public.apply_leave_ledger_entry(p_employee_id,p_leave_type_id,p_year,'adjustment',p_units,'leave:adjust:'||gen_random_uuid(),null,p_reason);
  perform public.log_audit_event('leave.balance.adjusted','hr','warning','leave_balance_accounts',v_entry.account_id,'تعديل رصيد إجازة',p_reason,jsonb_build_object('employeeId',p_employee_id,'leaveTypeId',p_leave_type_id,'units',p_units,'year',p_year));
  return v_entry.id;
end $$;



create or replace function public.admin_activate_employee_after_password_set(
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_employee_status_before text;
  v_profile_status_before text;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  -- نقرأ حالة الموظف قبل التعديل (لأغراض التدقيق) ونلتقط user_id المرتبط.
  select e.status, e.user_id
    into v_employee_status_before, v_user_id
  from public.employees e
  where e.id = p_employee_id and e.is_deleted = false
  limit 1;

  if v_user_id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  select p.status into v_profile_status_before
  from public.profiles p
  where p.id = v_user_id
  limit 1;

  -- إذا كان كلاهما نشطاً بالفعل، لا شيء لفعله — نُعيد مبكراً.
  if v_employee_status_before = 'active' and v_profile_status_before = 'active' then
    return jsonb_build_object('activated', false, 'reason', 'already_active');
  end if;

  -- نُفعّل الموظف فقط لو كان في حالة ما قبل التفعيل. لو كان في حالة
  -- متقدمة (مثل suspended / notice_period) لا نغيّرها — لكن نضمن is_active=true
  -- حتى لا تُقفل بوّابة identifier-sign-in الفرعية في is_active.
  if v_employee_status_before in ('invited', 'onboarding', 'draft') then
    update public.employees
    set    status     = 'active',
           is_active  = true,
           updated_at = now()
    where  id = p_employee_id
      and  is_deleted = false;
  else
    update public.employees
    set    is_active  = true,
           updated_at = now()
    where  id = p_employee_id
      and  is_deleted = false;
  end if;

  -- نُفعّل profile ونُزيل علم temporary_password.
  -- tg_profiles_protect_sensitive تسمح لـ service_role بتمرير أي تغيير
  -- لأن current_is_full_access()=true في هذا السياق.
  update public.profiles
  set    status             = 'active',
         temporary_password = false,
         updated_at         = now()
  where  id = v_user_id;

  -- نسجّل الحدث في سجل التدقيق لوضوح الرغبة الإدارية.
  perform public.log_audit_event(
    'employee.password_set_activated',
    'security',
    'info',
    'employees',
    p_employee_id,
    'تفعيل حساب بعد تعيين كلمة مرور يدوياً من الإدارة',
    null,
    jsonb_build_object(
      'employee_status_before', v_employee_status_before,
      'profile_status_before',  v_profile_status_before,
      'employee_id', p_employee_id
    )
  );

  return jsonb_build_object(
    'activated', true,
    'employee_status_before', v_employee_status_before,
    'profile_status_before', v_profile_status_before
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.admin_create_leave_request(p_employee_id uuid, p_leave_type text, p_start_date date, p_end_date date, p_reason text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_handover_notes text DEFAULT NULL::text, p_substitute_employee_id uuid DEFAULT NULL::uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_leave_type_id     uuid;
  v_days              numeric;
  v_payload           jsonb;
  v_row               public.requests;
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- البوابة: full access أو صلاحية ضبط أرصدة الإجازات (مطابقة 0429/0026).
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'EMPLOYEE_REQUIRED' using errcode = '22023';
  end if;
  if not exists(
    select 1 from public.employees
    where id = p_employee_id and is_active and not is_deleted
  ) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- توافق خلفي: emergency → casual (نفس submit_my_request 0401).
  if p_leave_type = 'emergency' then p_leave_type := 'casual'; end if;
  if p_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
    raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'leave start and end dates are required' using errcode = '22023';
  end if;
  if p_end_date < p_start_date then
    raise exception 'leave end date cannot precede start date' using errcode = '22023';
  end if;
  if p_start_date < v_today then
    raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'reason is required (min 3 chars)' using errcode = '22023';
  end if;

  select id into v_leave_type_id
  from public.leave_types
  where code = p_leave_type and is_active = true;
  if v_leave_type_id is null then
    raise exception 'leave type is inactive or unknown: %', p_leave_type using errcode = '22023';
  end if;

  v_days := (p_end_date - p_start_date) + 1;
  v_payload := jsonb_build_object(
    'leaveType', p_leave_type,
    'startDate', p_start_date,
    'endDate', p_end_date,
    'days', v_days,
    'immediate', (p_leave_type = 'casual'),
    'adminCreated', true,
    'handoverNotes', nullif(p_handover_notes,''),
    'substituteEmployeeId', p_substitute_employee_id);

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل).
  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  -- إنشاء الطلب في مسار الموافقة المعتاد (مدير مباشر ثم عمليات 1 أبو عمار).
  v_row := public._submit_request_for(
    p_employee_id,
    'leave',
    null,
    v_manager,
    coalesce(nullif(trim(p_title),''), 'إجازة ' || p_leave_type),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026).
  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date,
    days_count, duration_unit, handover_notes, substitute_employee_id, created_by)
  values(
    v_row.id, p_employee_id, v_leave_type_id, p_start_date, p_end_date,
    v_days, 'day',
    nullif(p_handover_notes,''),
    p_substitute_employee_id, auth.uid());

  -- العارضة: تُنفَّذ مباشرة دون موافقة (نفس submit_my_request 0401).
  if p_leave_type = 'casual' then
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
      'تنفيذ مباشر للإجازة العارضة (أنشأها HR بدل الموظف)',
      jsonb_build_object('immediate', true, 'leaveType', 'casual', 'adminCreated', true),
      auth.uid());

    perform public.log_audit_event(
      'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
      'تنفيذ فوري لإجازة عارضة (إنشاء إداري)',
      format('من %s إلى %s', p_start_date, p_end_date),
      jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
  end if;

  perform public.log_audit_event(
    'leave.request.admin_created', 'hr', 'info', 'requests', v_row.id,
    'إنشاء طلب إجازة بدل الموظف',
    coalesce(v_row.title, ''),
    jsonb_build_object(
      'employeeId', p_employee_id,
      'leaveType', p_leave_type,
      'days', v_days,
      'startDate', p_start_date,
      'endDate', p_end_date));

  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.admin_create_task(
  p_title       text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_priority    text DEFAULT 'medium',
  p_due_date    date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_id     uuid;
  v_emp_id uuid;
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('tasks.write')
    OR public.has_permission('operations.mission.manage')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: إنشاء المهام يتطلب صلاحية tasks.write أو operations.mission.manage'
      USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_title, '')), '') IS NULL THEN
    RAISE EXCEPTION 'TITLE_REQUIRED' USING ERRCODE = '22023';
  END IF;

  IF p_priority IS NOT NULL AND p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'INVALID_PRIORITY' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_emp_id
  FROM public.employees
  WHERE user_id = auth.uid() AND is_active
  LIMIT 1;

  INSERT INTO public.tasks (
    title, description, assignee_employee_id,
    priority, due_date, created_by_employee_id, created_by
  ) VALUES (
    btrim(p_title), p_description, p_assignee_id,
    p_priority, p_due_date, v_emp_id, auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;



CREATE OR REPLACE FUNCTION public.admin_delete_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  -- لا يُسمح بحذف جهاز نشط أو معلق أو محظور (قابل لإعادة التفعيل)
  if v_device.status not in ('revoked', 'replaced', 'auto_revoked') then
    raise exception 'only terminated devices (revoked/replaced/auto_revoked) can be deleted (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- تسجيل حدث أمني قبل الحذف
  perform public.log_security_event(
    'device.admin_deleted',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'deviceName', v_device.device_name,
      'platform', v_device.platform,
      'previousStatus', v_device.status,
      'reason', p_reason
    )
  );

  -- حذف بيانات اعتماد البصمة المرتبطة إن كانت منتهية ولا تربطها أجهزة أخرى
  delete from public.passkey_credentials
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked'
    and not exists (
      select 1 from public.employee_devices ed
      where ed.credential_id = v_device.credential_id
        and ed.employee_id = v_device.employee_id
        and ed.id <> p_device_id
        and ed.status in ('pending', 'active', 'blocked')
    );

  -- حذف الجهاز نهائياً
  delete from public.employee_devices
  where id = p_device_id;

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'deleted'
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.admin_reinstate_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('revoked', 'auto_revoked', 'blocked') then
    raise exception 'device is not in a reinstatable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  update public.employee_devices
  set status = 'pending',
      revoked_at = null,
      revocation_source = null,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'reinstated', true,
        'reinstatedAt', now(),
        'reinstatedBy', auth.uid(),
        'reinstateReason', p_reason,
        'previousStatus', v_device.status
      )
  where id = p_device_id;

  -- إعادة تنشيط بيانات اعتماد البصمة المرتبطة (بلا ثقة حتى تُعتمد من جديد).
  update public.passkey_credentials
  set status = 'active', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked';

  perform public.log_security_event(
    'device.reinstated', 'medium', 'allowed', v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'previousStatus', v_device.status,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'pending',
    'previousStatus', v_device.status
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.admin_revoke_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('active', 'pending') then
    raise exception 'device is not in a revocable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- إلغاء الجهاز
  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'admin'
  where id = p_device_id;

  -- إلغاء بيانات اعتماد البصمة المرتبطة
  update public.passkey_credentials
  set status = 'revoked', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'active';

  -- تنظيف الجلسات واشتراكات الدفع
  perform public._cleanup_user_sessions_and_push(v_device.user_id, 'admin_revoke');

  perform public.log_security_event(
    'device.admin_revoked',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'revoked',
    'sessionsCleared', true
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.admin_transition_task(
  p_id     uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('tasks.write')
    OR public.has_permission('operations.mission.manage')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: تغيير حالة المهام يتطلب tasks.write أو operations.mission.manage'
      USING ERRCODE = '42501';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('pending', 'in_progress', 'done', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_TASK_STATUS' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tasks
  SET status = p_status, updated_at = now()
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
END;
$$;



create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid, p_action text, p_scores jsonb default null, p_note text default null
)
returns public.kpi_evaluations
language plpgsql security definer set search_path = public, pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles;
 v_row jsonb; v_criterion public.kpi_criteria; v_score numeric;
 v_required int; v_received int; v_errors text[]; v_total numeric; v_rating text;
 v_att record;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle)
   then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 -- رفض صريح لأفعال المسارات القديمة
 if p_action not in ('self','manager_review') then
   raise exception 'KPI_FLOW_SIMPLIFIED: % لم يعد مساراً صالحاً منذ 0470 (self / manager_review فقط)', p_action
     using errcode='22023';
 end if;
 if v_eval.current_stage<>p_action then
   raise exception 'STAGE_OUT_OF_ORDER expected %, found %', p_action, v_eval.current_stage;
 end if;

 -- ══════════ ① التقييم الذاتي ══════════
 if p_action='self' then
  if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id()
     or not public.has_permission('performance.kpi.self_assess')
   then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
  select count(*) into v_required from public.kpi_criteria where template_id=v_eval.template_id;
  select count(*) into v_received from jsonb_array_elements(p_scores);
  if v_received<>v_required then raise exception 'ALL_SELF_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria
    where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id;
   if v_criterion.id is null then raise exception 'INVALID_SELF_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'self',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update
     set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;
  update public.kpi_evaluations set
   stage='manager_review',current_stage='manager_review',
   workflow_status='SUBMITTED_TO_DIRECT_MANAGER',
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
   'إرسال التقييم الذاتي إلى المدير (0470)',null,jsonb_build_object('to','manager_review'));
  return v_eval;
 end if;

 -- ══════════ ② تقييم المدير واعتماده النهائي في خطوة واحدة ══════════
 if not public.kpi_can_approve(v_eval) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
 if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'MANAGER_SCORES_REQUIRED'; end if;

 select count(*) into v_required from public.kpi_criteria
  where template_id=v_eval.template_id and evaluator_stage='manager';
 select count(*) into v_received from jsonb_array_elements(p_scores);
 if v_received<>v_required then raise exception 'ALL_MANAGER_CRITERIA_REQUIRED'; end if;
 for v_row in select * from jsonb_array_elements(p_scores) loop
  select * into v_criterion from public.kpi_criteria
   where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='manager';
  if v_criterion.id is null then raise exception 'INVALID_MANAGER_CRITERION'; end if;
  v_score:=(v_row->>'score')::numeric;
  if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_criterion.id,v_score,'manager',nullif(trim(v_row->>'note'),''),auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update
    set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 end loop;

 -- بنود HR: الحضور يُحتسب موضعياً لهذا التقييم، وما بقي بلا إدخال يأخذ الدرجة الكاملة افتراضياً (الاستثناء بالخصم)
 for v_att in
  select k.id criterion_id,k.attendance_metric,k.max_score,
   count(a.*) filter(where a.status not in ('holiday','weekend')) scheduled,
   count(a.*) filter(where a.status in ('present','late')) present,
   count(a.*) filter(where a.status='present') punctual,
   count(a.*) filter(where a.status in ('present','late','on_leave','holiday','weekend')) completed
  from public.kpi_criteria k
  left join public.attendance_daily a on a.employee_id=v_eval.employee_id
    and date_trunc('month',a.work_date)=v_cycle.period_month
  where k.template_id=v_eval.template_id and k.source_type='attendance'
  group by k.id,k.attendance_metric,k.max_score
 loop
  v_score:=case v_att.attendance_metric
    when 'punctuality_rate' then case when v_att.scheduled=0 then v_att.max_score else round(v_att.punctual::numeric/v_att.scheduled*v_att.max_score,2) end
    when 'completion_rate'  then case when v_att.scheduled=0 then v_att.max_score else round(v_att.completed::numeric/v_att.scheduled*v_att.max_score,2) end
    else case when v_att.scheduled=0 then v_att.max_score else round(v_att.present::numeric/v_att.scheduled*v_att.max_score,2) end end;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_att.criterion_id,greatest(0,least(v_score,v_att.max_score)),'hr','محسوب آلياً من الحضور (0470)',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
 end loop;
 update public.kpi_evaluations set manager_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 select v_eval.id, c.id, c.max_score, 'hr', 'قيمة افتراضية (0470): لا استثناء مسجلاً', auth.uid()
   from public.kpi_criteria c
  where c.template_id=v_eval.template_id and c.evaluator_stage='hr'
    and not exists(select 1 from public.kpi_scores s
                    where s.evaluation_id=v_eval.id and s.criterion_id=c.id and s.reviewer_stage='hr')
on conflict (evaluation_id,criterion_id,reviewer_stage) do nothing;

 v_errors:=public.get_kpi_validation_errors(v_eval.id);
 if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
 v_total:=public.kpi_total_score(v_eval.id);
 if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
 v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);

 update public.kpi_evaluations set
  stage='finalized',current_stage='finalized',
  workflow_status='EMPLOYEE_ACKNOWLEDGEMENT_PENDING',
  manager_approved_at=now(),manager_approved_by=public.current_employee_id(),
  final_score=v_total,final_rating=v_rating,
  final_breakdown=(select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id))
                     from public.kpi_criteria c where c.template_id=v_eval.template_id),
  rating_policy_snapshot=(select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id),
  locked=true,version=version+1,updated_at=now()
 where id=v_eval.id returning * into v_eval;

 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
  'اعتماد المدير الشامل (0470)',p_note,
  jsonb_build_object('finalScore',v_total,'finalRating',v_rating));
 perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,
  'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
 return v_eval;
end $$;



create or replace function public.apply_leave_ledger_entry(
  p_employee_id   uuid,
  p_leave_type_id uuid,
  p_year          integer,
  p_entry_type    text,   -- opening|accrual|carryover|adjustment|reserve|release|consume|refund|expire|credit
  p_units         numeric,
  p_source_key    text,
  p_request_id    uuid default null,
  p_reason        text default null,
  p_metadata      jsonb default '{}'::jsonb
) returns public.leave_ledger_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_account   public.leave_balance_accounts;
  v_entry     public.leave_ledger_entries;
  v_available numeric;
  v_lock_id   bigint;
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire','credit'
  ) then raise exception 'INVALID_LEAVE_ENTRY_TYPE'; end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'LEAVE_SOURCE_KEY_REQUIRED';
  end if;

  -- ── advisory lock: serialize per (employee, leave_type) ──────────────────
  -- يمنع سباقات reserve/consume المتزامنة (0382).
  v_lock_id := hashtextextended(p_employee_id::text || ':' || p_leave_type_id::text, 0);
  perform pg_advisory_xact_lock(v_lock_id);

  v_account := public.ensure_leave_account(p_employee_id, p_leave_type_id, p_year);

  -- ── idempotency: skip if source_key already processed ────────────────────
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key;
  if found then
    return v_entry; -- already applied — idempotent return
  end if;

  if p_entry_type = 'opening' and v_account.opening_units <> 0 then
    select * into v_entry
    from public.leave_ledger_entries
    where account_id = v_account.id and entry_type = 'opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

  -- ── insert audit entry (unique(source_key) يمنع التكرار عند التزامن) ─────
  insert into public.leave_ledger_entries(
    account_id, employee_id, leave_type_id, request_id, entry_type, units,
    effective_date, reason, source_key, metadata, created_by
  ) values (
    v_account.id, p_employee_id, p_leave_type_id, p_request_id, p_entry_type, p_units,
    current_date, p_reason, p_source_key, coalesce(p_metadata, '{}'::jsonb), auth.uid()
  ) on conflict(source_key) do nothing returning * into v_entry;
  if not found then
    select * into strict v_entry from public.leave_ledger_entries
    where source_key = p_source_key;
    return v_entry;
  end if;

  -- ── apply entry by type على الأعمدة الحقيقية للرصيد ──────────────────────
  if p_entry_type = 'opening' then
    update public.leave_balance_accounts set opening_units = opening_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'accrual' then
    update public.leave_balance_accounts set accrued_units = accrued_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'carryover' then
    update public.leave_balance_accounts set carryover_units = carryover_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'adjustment' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'credit' then
    -- رصيد بدل راحة أسبوعي (0428): يُضاف إلى adjusted_units فيظهر ضمن الرصيد المتاح.
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'reserve' then
    select opening_units + accrued_units + adjusted_units + carryover_units - consumed_units - reserved_units
      into v_available from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'INSUFFICIENT_LEAVE_BALANCE: available=% requested=%', v_available, p_units;
    end if;
    update public.leave_balance_accounts set reserved_units = reserved_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'release' then
    update public.leave_balance_accounts set reserved_units = greatest(0, reserved_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'consume' then
    -- حارس 0382: لا يستهلك أكثر مما حُجز فعلياً
    select reserved_units into v_available
    from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'CONSUME_EXCEEDS_RESERVE: reserved=% requested=% (concurrent modification?)', v_available, p_units;
    end if;
    update public.leave_balance_accounts
      set reserved_units = greatest(0, reserved_units - abs(p_units)),
          consumed_units = consumed_units + abs(p_units),
          updated_at = now()
      where id = v_account.id;
  elsif p_entry_type = 'refund' then
    update public.leave_balance_accounts set consumed_units = greatest(0, consumed_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'expire' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units - abs(p_units), updated_at = now() where id = v_account.id;
  end if;

  return v_entry;
end;
$$;



CREATE OR REPLACE FUNCTION public.approve_break_glass(p_request_id uuid, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.break_glass_requests; v_user_role public.user_roles; v_role_slug text;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'اعتماد الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  select * into v_req from public.break_glass_requests where id=p_request_id for update;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;
  if v_req.status <> 'pending' then raise exception 'الطلب ليس قيد الانتظار' using errcode='P0001'; end if;
  if v_req.requested_by=auth.uid() then raise exception 'يلزم اعتماد شخصين (أربع عيون)' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'سبب الاعتماد مطلوب' using errcode='22023'; end if;
  if exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_req.target_user_id and ur.role_id=v_req.requested_role_id
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'المستخدم يملك الدور المطلوب نشطاً بالفعل' using errcode='P0001';
  end if;
  insert into public.user_roles(user_id,role_id,scope_override,effective_from,effective_to,granted_by)
  values(v_req.target_user_id,v_req.requested_role_id,jsonb_build_object('breakGlassRequestId',v_req.id),now(),now()+make_interval(mins=>v_req.duration_minutes),auth.uid())
  on conflict (user_id,role_id) do update set
    scope_override=excluded.scope_override,effective_from=excluded.effective_from,effective_to=excluded.effective_to,granted_by=excluded.granted_by
  returning * into v_user_role;
  update public.break_glass_requests set status='approved',approved_by=auth.uid(),approved_at=now(),active_from=now(),
    active_until=v_user_role.effective_to,user_role_id=v_user_role.id where id=v_req.id returning * into v_req;
  select r.slug into v_role_slug from public.roles r where r.id=v_req.requested_role_id;
  perform public.log_security_event('break_glass.approved','critical','allowed',v_req.target_user_id::text,
    jsonb_build_object('requestId',v_req.id,'userRoleId',v_user_role.id,'activeUntil',v_req.active_until,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'تم قبول طلب Break Glass',
    format('مُنح وصول استثنائي لدور %s حتى %s.', coalesce(v_role_slug,''), v_req.active_until),
    'security', 'normal', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$function$;



CREATE OR REPLACE FUNCTION public.approve_device(p_device_id uuid, p_approved boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
  v_old_user_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('pending', 'blocked') then
    raise exception 'device is not in a reviewable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  if p_approved then
    -- حفظ user_id القديم للجهاز النشط السابق (لتنظيف الجلسات عند تغيير المستخدم)
    select user_id into v_old_user_id
    from public.employee_devices
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active'
    limit 1;

    -- تعطيل أي جهاز active آخر لنفس الموظف
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        revocation_source = 'replacement',
        metadata = metadata || jsonb_build_object('replacedByApproval', p_device_id)
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active';

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null,
        revocation_source = null
    where id = p_device_id;

    -- تنظيف الجلسات إن تغيّر المستخدم
    if v_old_user_id is not null and v_old_user_id <> v_device.user_id then
      perform public._cleanup_user_sessions_and_push(v_old_user_id, 'device_replaced');
    end if;
  else
    update public.employee_devices
    set status = 'blocked',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = coalesce(p_reason, 'رفض إداري')
    where id = p_device_id;
  end if;

  perform public.log_security_event(
    case when p_approved then 'device.approved' else 'device.rejected' end,
    'medium', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'approved', p_approved,
      'reason', p_reason
    )
  );

  return jsonb_build_object('ok', true, 'status', case when p_approved then 'active' else 'blocked' end);
end;
$function$;



create or replace function public.approve_offboarding_case(p_case_id uuid,p_final_settlement_reference text default null,p_exit_interview_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.offboarding_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.approve')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.offboarding_cases where id=p_case_id for update;
 if v.status<>'ready_for_approval' or exists(select 1 from public.asset_assignments where employee_id=v.employee_id and status in ('assigned','return_requested')) then raise exception 'CLEARANCE_OR_ASSETS_PENDING'; end if;
 update public.offboarding_cases set status='completed',approved_by=public.current_employee_id(),approved_at=now(),completed_at=now(),final_settlement_reference=p_final_settlement_reference,exit_interview_notes=p_exit_interview_notes,updated_at=now() where id=p_case_id;
 update public.employees set status='terminated',is_active=false,updated_at=now() where id=v.employee_id;
 update public.profiles set status='disabled',updated_at=now() where employee_id=v.employee_id;
 update public.user_roles set effective_to=coalesce(effective_to,now()) where user_id=(select user_id from public.employees where id=v.employee_id) and (effective_to is null or effective_to>now());
 insert into public.offboarding_actions(offboarding_case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id) values(p_case_id,'approve','ready_for_approval','completed',public.current_employee_id(),auth.uid());
 perform public.log_audit_event('offboarding.completed','workflow','warning','offboarding_cases',p_case_id,'اكتمال إنهاء خدمة موظف',null,jsonb_build_object('employeeId',v.employee_id));
 if v.handover_employee_id is not null and v.handover_employee_id <> public.current_employee_id() then
  perform public.notify_employee(
   v.handover_employee_id,
   'اكتمال إنهاء خدمة — تسلّم المهام',
   'اكتمل إنهاء خدمة أحد الزملاء المسلَّمة إليك، راجع مهام التسليم وأكمل إجراءاتك.',
   'offboarding', 'normal', 'offboarding_cases', p_case_id,
   jsonb_build_object('employeeId', v.employee_id));
 end if;
end $$;



create or replace function public.assign_employee_department(
  p_employee_id uuid,
  p_department_id uuid,
  p_job_title text default null,
  p_is_primary boolean default false,
  p_note text default null,
  p_allocation_percentage integer default null,
  p_start_date date default null,
  p_end_date date default null,
  p_functional_manager_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_has_any boolean;
  v_alloc integer;
begin
  -- تحقق من الصلاحية
  if not (public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- تحقق من وجود الموظف والإدارة
  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'DEPARTMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- تحقق من المدير الوظيفي إذا حُدد
  if p_functional_manager_id is not null
     and not exists (select 1 from public.employees where id = p_functional_manager_id and is_active) then
    raise exception 'FUNCTIONAL_MANAGER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- هل لديه إدارات موجودة؟
  select exists(select 1 from public.employee_departments where employee_id = p_employee_id)
    into v_has_any;

  -- إذا لم تكن لديه إدارات سابقة، اجعلها أساسية تلقائياً
  if not v_has_any then
    p_is_primary := true;
  end if;

  -- نسبة التخصيص: الأساسي = 100 افتراضيًا
  v_alloc := coalesce(p_allocation_percentage,
    case when p_is_primary then 100 else 50 end);

  insert into public.employee_departments (
    employee_id, department_id, job_title, is_primary, assigned_by, note,
    allocation_percentage, start_date, end_date, functional_manager_id
  )
  values (
    p_employee_id, p_department_id, p_job_title, p_is_primary, auth.uid(), p_note,
    v_alloc, coalesce(p_start_date, current_date), p_end_date, p_functional_manager_id
  )
  on conflict (employee_id, department_id) do update set
    job_title = coalesce(excluded.job_title, public.employee_departments.job_title),
    is_primary = excluded.is_primary,
    allocation_percentage = excluded.allocation_percentage,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    functional_manager_id = excluded.functional_manager_id,
    note = excluded.note,
    assigned_by = excluded.assigned_by
  returning id into v_id;

  return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.auto_notify_late_attendance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=إثنين..7=أحد
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  -- عطلة نهاية الأسبوع: الجمعة(5) والسبت(6). لا شيء لنفعله.
  if v_isodow in (5, 6) then
    return 0;
  end if;

  for v_rec in
    select
      ad.employee_id,
      ad.late_minutes,
      e.full_name_ar      as employee_name,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e   on e.id = ad.employee_id
    -- المدير المباشر الوحيد لكل موظف: نفضّل 'primary' ثم أي علاقة فعّالة.
    left join lateral (
      select m.user_id as manager_user_id, m.id as manager_employee_id
      from public.manager_relations mr
      join public.employees m on m.id = mr.manager_employee_id
      where mr.employee_id = ad.employee_id
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
        and m.is_active = true
        and m.user_id is not null
      order by case mr.relation_type
                 when 'primary'    then 1
                 when 'functional' then 2
                 when 'dotted'     then 3
                 else 4
               end
      limit 1
    ) mgr on true
    where ad.work_date = v_today
      and ad.status    = 'late'
      and coalesce(ad.late_minutes, 0) > 0
      and e.is_active  = true
      and e.is_deleted = false
      and mgr.manager_user_id is not null
      and not exists (
        -- منع التكرار: إشعار سابق لنفس (المدير/الموظف/اليوم)
        select 1
        from public.notifications n
        where n.recipient_user_id = mgr.manager_user_id
          and n.entity_type = 'late_attendance_alert'
          and (n.metadata->>'employeeId') = ad.employee_id::text
          and (n.metadata->>'workDate')   = v_today::text
      )
    order by e.full_name_ar
  loop
    -- الـ trigger trg_notifications_queue_jobs يُضيف notification_jobs تلقائياً.
    insert into public.notifications (
      recipient_user_id,
      recipient_employee_id,
      title,
      body,
      category,
      priority,
      action_url,
      entity_type,
      entity_id,
      metadata
    ) values (
      v_rec.manager_user_id,
      v_rec.manager_employee_id,
      'تنبيه تأخر موظف',
      coalesce(v_rec.employee_name, 'الموظف') || ' تأخر عن مواجهة الوردية بمقدار ' ||
        v_rec.late_minutes::text || ' دقيقة',
      'system',
      'urgent',
      '/attendance',
      'late_attendance_alert',
      v_rec.employee_id,
      jsonb_build_object(
        'workDate',     v_today::text,
        'lateMinutes',  v_rec.late_minutes,
        'employeeId',   v_rec.employee_id::text,
        'managerEmployeeId', v_rec.manager_employee_id::text,
        'channel', 'late_attendance',
        'deepLink', 'ahlashabab://action/attendance?date=' || to_char(v_today, 'YYYY-MM-DD')
      )
    ) returning id into v_notif_id;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
exception
  when others then
    -- لا نعطّل الكرون؛ نسجّل الحادث ونُرجع 0.
    perform public.log_audit_event(
      'attendance.late_alert_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل تنبيه التأخر التلقائي', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$function$;



CREATE OR REPLACE FUNCTION public.batch_decide_requests(
  p_request_ids  uuid[],
  p_decision     text,
  p_comment      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count       int := 0;
  v_skipped     int := 0;
  v_id          uuid;
  v_user_id     uuid := auth.uid();
  v_employee_id uuid := public.current_employee_id();
  v_total       int  := coalesce(array_length(p_request_ids, 1), 0);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
  END IF;
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NO_EMPLOYEE_LINKED';
  END IF;

  IF NOT public.current_is_full_access()
     AND NOT public.has_any_permission(ARRAY[
       'requests.request.approve',
       'requests.request.override'
     ])
  THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'ERR_INVALID_DECISION: يجب أن يكون approved أو rejected';
  END IF;

  IF v_total = 0 THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 0, 'total', 0);
  END IF;

  IF v_total > 500 THEN
    RAISE EXCEPTION 'ERR_BATCH_TOO_LARGE' USING ERRCODE = '22023';
  END IF;

  IF to_regclass('public.requests') IS NULL THEN
    RAISE EXCEPTION 'ERR_TABLE_NOT_FOUND: requests';
  END IF;

  FOREACH v_id IN ARRAY p_request_ids LOOP
    IF EXISTS (
      SELECT 1 FROM public.requests
      WHERE id = v_id AND employee_id = v_employee_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE public.requests SET
      status       = p_decision,
      decided_by   = v_employee_id,
      decided_at   = now(),
      updated_at   = now()
    WHERE id = v_id
      AND status = 'pending';

    IF FOUND THEN
      v_count := v_count + 1;

      IF to_regclass('public.request_actions') IS NOT NULL THEN
        INSERT INTO public.request_actions (
          request_id, actor_employee_id, action,
          from_status, to_status, comment, created_by
        ) VALUES (
          v_id, v_employee_id,
          CASE p_decision WHEN 'approved' THEN 'approve' ELSE 'reject' END,
          'pending', p_decision, p_comment, v_user_id
        );
      END IF;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  PERFORM public.log_audit_event(
    'batch_decide_requests',
    'workflow',
    'notice',
    'requests',
    NULL,
    'قرار جماعي على ' || v_count || ' طلب (' || p_decision || ')',
    'batch decision: ' || v_count || ' processed, ' || v_skipped || ' skipped',
    jsonb_build_object(
      'processed', v_count,
      'skipped', v_skipped,
      'total', v_total,
      'decision', p_decision,
      'request_ids', to_jsonb(p_request_ids)
    )
  );

  RETURN jsonb_build_object(
    'processed', v_count,
    'skipped',   v_skipped,
    'total',     v_total
  );
END;
$$;



create or replace function public.can_access_employee(p_employee_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_me uuid;
begin
  if public.current_is_full_access() then return true; end if;
  begin v_me := public.current_employee_id(); exception when others then v_me := null; end;
  if v_me is not null and v_me = p_employee_id then return true; end if;
  -- علاقة مدير مباشر (إن وُجد الجدول)
  begin
    if exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = p_employee_id
        and mr.manager_employee_id = v_me
        and (mr.effective_to is null or mr.effective_to > now())
    ) then return true; end if;
  exception when undefined_table then null;
  end;
  return false;
end;
$$;



create or replace function public.can_see_directory_entry(p_viewer uuid, p_target uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if p_target = p_viewer then return true; end if;
  if public.current_is_full_access() then return true; end if;
  if p_viewer is null or p_target is null then return false; end if;
  -- المعزول لا يظهر لمن خارج نطاقه
  if public.is_employee_isolated(p_target)
     and not public.can_view_isolated_employee(p_target) then
    return false;
  end if;
  -- مشاهد معزول لا يرى عام الفريق (يرى قسمه ومديره فقط)
  if public.is_employee_isolated(p_viewer)
     and not public.is_employee_isolated(p_target) then
    -- يُسمح برؤية مديره المباشر فقط
    return exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_viewer
         and mr.manager_employee_id = p_target
         and mr.effective_from <= now()
         and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;
  return true;
end $$;



create or replace function public.can_view_isolated_employee(p_target uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  if public.current_is_full_access() then return true; end if;
  if v_me is null then return false; end if;
  -- نفس القسم المعزول (زميل في الإدارة الطبية)
  if exists (
    select 1
      from public.employees t
     where t.id = p_target
       and t.department_id = (select e.department_id from public.employees e where e.id = v_me)
  ) then return true; end if;
  -- المدير المباشر (علاقة إشراف سارية)
  if exists (
    select 1 from public.manager_relations mr
     where mr.employee_id = p_target
       and mr.manager_employee_id = v_me
       and mr.effective_from <= now()
       and (mr.effective_to is null or mr.effective_to > now())
  ) then return true; end if;
  return false;
end $$;



create or replace function public.can_view_live_location_video(
  p_request_id uuid
)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  -- V12 §9: الفيديو ملغى نهائيًا — ترجع false دائمًا.
  return false;
end $$;



CREATE OR REPLACE FUNCTION public.cancel_location_request_as_requester(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me  uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  select * into v_req from public.live_location_requests where id = p_request_id;
  if not found then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  -- Only the original requester OR a full-access user can cancel.
  if v_req.requested_by is distinct from v_me and not public.current_is_full_access() then
    raise exception 'يمكنك إلغاء طلبات موقعك فقط' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'accepted') then
    raise exception 'لا يمكن إلغاء الطلب بحالته الحالية' using errcode = '22023';
  end if;

  update public.live_location_requests
    set status     = 'rejected',
        expires_at = now(),
        metadata   = jsonb_set(
          coalesce(metadata, '{}'::jsonb),
          '{cancelledByRequester}',
          'true'
        )
    where id = p_request_id;

  perform public.log_audit_event(
    'live_location.request_cancelled', 'security', 'info',
    'live_location_requests', p_request_id,
    'إلغاء طلب الموقع من قِبل المدير', null,
    jsonb_build_object('requestId', p_request_id, 'cancelledBy', v_me)
  );

  -- إشعار الموظف المستهدف بإلغاء الطلب (0316)
  if v_req.employee_id is not null and v_req.employee_id <> v_me then
    perform public.notify_employee(
      v_req.employee_id, 'أُلغي طلب مشاركة موقعك',
      format('أُلغي طلب مشاركة الموقع الحيّ (الحالة: %s)', coalesce(v_req.status, '')),
      'location', 'normal', 'live_location_requests', p_request_id,
      jsonb_build_object('cancelledBy', v_me));
  end if;
end;
$function$;



create or replace function public.cancel_my_dispute(p_case_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 if v.actor_employee_id<>public.current_employee_id() or v.status not in ('draft','submitted') or v.accepted_at is not null then raise exception 'CANNOT_CANCEL' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
 update public.dispute_cases set status='cancelled_by_employee',cancelled_at=now(),cancellation_reason=trim(p_reason),updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id)
 values(p_case_id,'cancel_by_employee',v.status,'cancelled_by_employee',trim(p_reason),public.current_employee_id(),auth.uid());
 perform public.log_audit_event('dispute.cancelled_by_employee','workflow','notice','dispute_cases',p_case_id,'إلغاء المشكلة قبل قبولها',trim(p_reason));
end $$;



CREATE OR REPLACE FUNCTION public.cancel_request(p_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be cancelled (current: %)', v_req.status using errcode = '22023';
  end if;

  -- التخويل: صاحب الطلب، أو full-access، أو صلاحية approve
  if not (
    v_req.employee_id = v_me
    or public.current_is_full_access()
    or public.has_permission('requests.approve')
  ) then
    raise exception 'غير مصرح لك بإلغاء هذا الطلب' using errcode = '42501';
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

  -- إشعار المعتمِدين على الخطوات (0316)
  for v_assignee in
    select distinct s.assignee_employee_id
    from public.request_steps s
    where s.request_id = p_request_id
      and s.assignee_employee_id is not null
      and s.assignee_employee_id <> v_me
  loop
    perform public.notify_employee(
      v_assignee,
      'أُلغيت طلب',
      format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
      'request', 'normal', 'request', p_request_id,
      jsonb_build_object('requestType', v_req.request_type));
  end loop;

  return v_req;
end;
$function$;



CREATE OR REPLACE FUNCTION public.cancel_work_assignment(p_assignment_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments;
begin
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'غير مصرح لك بإلغاء هذا التكليف' using errcode = '42501';
  end if;
  if v_row.status in ('COMPLETED','CANCELLED') then
    raise exception 'assignment already closed (%)', v_row.status using errcode = '22023';
  end if;
  update public.work_assignments
    set status = 'CANCELLED', decision_comment = p_reason, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.cancelled', 'workflow', 'warning', 'work_assignments', p_assignment_id,
    'إلغاء تكليف عمل', p_reason, jsonb_build_object('type', v_row.assignment_type));
  return v_row;
end $function$;



create or replace function public.change_employee_manager_admin(
  p_employee_id uuid,
  p_manager_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_old_manager uuid;
begin
  if not(public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'employee_update_not_allowed' using errcode='42501';
  end if;
  if not public.can_access_employee(p_employee_id,'people.employee.update_sensitive')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'change_reason_required' using errcode='22023'; end if;
  if p_manager_id=p_employee_id then raise exception 'manager_cannot_be_self' using errcode='22023'; end if;
  perform 1 from public.employees where id=p_employee_id and not is_deleted for update;
  if not found then raise exception 'employee_not_found' using errcode='P0002'; end if;
  select manager_employee_id into v_old_manager from public.manager_relations
  where employee_id=p_employee_id and relation_type='primary'
    and effective_from<=current_date and (effective_to is null or effective_to>=current_date)
  order by effective_from desc limit 1;
  if p_manager_id is not null then
    if not exists(select 1 from public.employees where id=p_manager_id and not is_deleted and status='active' and is_active) then
      raise exception 'manager_not_active' using errcode='22023';
    end if;
    if exists(
      with recursive manager_chain(id,path) as (
        select p_manager_id,array[p_manager_id]::uuid[]
        union all
        select mr.manager_employee_id,c.path||mr.manager_employee_id
        from public.manager_relations mr join manager_chain c on c.id=mr.employee_id
        where mr.relation_type='primary' and mr.effective_to is null
          and not mr.manager_employee_id=any(c.path)
      ) select 1 from manager_chain where id=p_employee_id
    ) then raise exception 'manager_cycle_not_allowed' using errcode='22023'; end if;
  end if;
  update public.manager_relations set effective_to=current_date,updated_at=now()
  where employee_id=p_employee_id and relation_type='primary' and effective_to is null;
  if p_manager_id is not null then
    insert into public.manager_relations(
      employee_id,manager_employee_id,relation_type,effective_from,created_by
    ) values(p_employee_id,p_manager_id,'primary',current_date,auth.uid());
  end if;
  perform public.log_audit_event(
    'employee_manager_changed','people','warning','employees',p_employee_id,
    'تغيير المدير المباشر',trim(p_reason),jsonb_build_object(
      'previousManagerId',v_old_manager,'managerId',p_manager_id,'reason',trim(p_reason))
  );
  return jsonb_build_object('employeeId',p_employee_id,
    'previousManagerId',v_old_manager,'managerId',p_manager_id,'updatedAt',now());
end;
$$;



CREATE OR REPLACE FUNCTION public.check_invite_rate_limit(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_last_invite timestamptz;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  -- current_user is the function owner inside SECURITY DEFINER and therefore
  -- cannot identify the caller. A JWT-backed caller must be full-access;
  -- trusted server invocations have no end-user auth.uid().
  if auth.uid() is not null
     and not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select max(ae.created_at)
    into v_last_invite
  from public.audit_events ae
  where ae.target_table = 'employees'
    and ae.target_id = p_employee_id
    and ae.event_type in ('employee.invite.resent', 'employee.invite.sent');

  if v_last_invite is not null
     and v_last_invite > now() - interval '60 seconds' then
    raise exception 'invite_rate_limit_exceeded'
      using errcode = '42501',
            hint = 'يرجى الانتظار 60 ثانية قبل إعادة إرسال الدعوة.';
  end if;
end;
$function$;



create or replace function public.check_rate_limit(
  p_domain text,
  p_max_count integer,
  p_window_minutes integer default 60
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_uid uuid := auth.uid();
begin
  -- full-access معفى من Rate Limit
  if public.current_is_full_access() then
    return;
  end if;

  select count(*) into v_count
  from public.rate_limit_log
  where user_id = v_uid
    and domain = p_domain
    and created_at > now() - make_interval(mins => p_window_minutes);

  if v_count >= p_max_count then
    raise exception 'rate_limit_exceeded: % (% في آخر % دقيقة، الحد %)',
      p_domain, v_count, p_window_minutes, p_max_count
      using errcode = '54000';
  end if;

  -- سجل العملية
  insert into public.rate_limit_log(user_id, domain)
  values (v_uid, p_domain);
end;
$$;



create or replace function public.close_kpi_cycle(p_cycle_id uuid)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return public.manage_kpi_cycle(p_cycle_id,'close','إغلاق من أمر التوافق المعتمد',null);
end $$;



create or replace function public.complete_dispute_action(p_action_id uuid,p_proof text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_actions; v_settlement uuid;
begin
 select * into strict v from public.dispute_actions where id=p_action_id for update;
 if v.execution_status not in ('pending','in_progress','failed') or not(public.current_is_full_access() or public.has_permission('disputes.action.manage') or v.assigned_to=public.current_employee_id()) then raise exception 'ACTION_COMPLETION_FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_proof,'')))<5 then raise exception 'PROOF_REQUIRED'; end if;
 update public.dispute_actions set execution_status='completed',completion_proof=trim(p_proof),completed_at=now() where id=p_action_id;
 v_settlement=nullif(v.metadata->>'settlementId','')::uuid;
 if v_settlement is not null then update public.dispute_settlements set status='completed',confirmed_by=public.current_employee_id(),completed_at=now(),updated_at=now() where id=v_settlement; end if;
 if nullif(v.metadata->>'decisionId','') is not null and not exists(select 1 from public.dispute_actions where case_id=v.case_id and execution_status in ('pending','in_progress','failed') and id<>p_action_id) then
  update public.dispute_decisions set status='implemented',implemented_at=now(),updated_at=now() where id=(v.metadata->>'decisionId')::uuid;
 end if;
 perform public.log_audit_event('dispute.action_completed','workflow','notice','dispute_actions',p_action_id,'تنفيذ إجراء قرار',trim(p_proof),jsonb_build_object('caseId',v.case_id));
 perform public.notify_dispute_admins(v.case_id,'action-completed:'||p_action_id::text,'تم تنفيذ إجراء في مشكلة','تم تسجيل إثبات التنفيذ، ويمكن مراجعة القضية للإغلاق.','normal');
end $$;



create or replace function public.complete_live_location_response(
  p_request_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy numeric,
  p_address text default null,
  p_captured_at timestamptz default now()
)
returns public.live_location_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  if v_me is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if p_request_id is null
     or p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180
     or p_accuracy is null or p_accuracy < 0 then
    raise exception 'INVALID_LOCATION_RESPONSE' using errcode = '22023';
  end if;

  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_req.employee_id is distinct from v_me then
    raise exception 'NOT_TARGET_EMPLOYEE' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'active') then
    raise exception 'REQUEST_NOT_ACTIVE: %', v_req.status using errcode = '22023';
  end if;
  if v_req.expires_at < now() then
    raise exception 'REQUEST_EXPIRED' using errcode = '22023';
  end if;

  insert into public.location_request_responses(
    request_id, employee_id, latitude, longitude, accuracy_meters,
    address, captured_at, upload_status, metadata
  ) values (
    p_request_id, v_me, p_latitude, p_longitude, p_accuracy::double precision,
    nullif(trim(coalesce(p_address, '')), ''), coalesce(p_captured_at, now()),
    'completed', jsonb_build_object('source', 'complete_live_location_response')
  )
  on conflict (request_id) do update set
    employee_id = excluded.employee_id,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_meters = excluded.accuracy_meters,
    address = excluded.address,
    captured_at = excluded.captured_at,
    upload_status = 'completed',
    metadata = public.location_request_responses.metadata || excluded.metadata,
    updated_at = now();

  update public.live_location_requests
  set status = 'completed',
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  if v_req.requested_by is not null then
    perform public.notify_employee(
      v_req.requested_by,
      'وصل الموقع',
      'تم استقبال موقع الموظف المطلوب.',
      'system', 'normal', 'live_location_requests', v_req.id,
      jsonb_build_object(
        'latitude', p_latitude,
        'longitude', p_longitude,
        'accuracy', p_accuracy
      )
    );
  end if;

  perform public.log_audit_event(
    'location.completed', 'workflow', 'info',
    'live_location_requests', v_req.id,
    'اكتمال طلب الموقع (بدون فيديو)', null,
    jsonb_build_object(
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy', p_accuracy,
      'address', p_address
    )
  );

  return v_req;
end;
$$;



CREATE OR REPLACE FUNCTION public.complete_my_live_location_request(p_request_id uuid)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.live_location_requests;
  v_mode text;
begin
  select * into v_row
  from public.live_location_requests
  where id = p_request_id and employee_id = v_me
  for update;
  if not found then
    raise exception 'لا يوجد طلب نشط' using errcode = 'P0002';
  end if;
  if v_row.status not in ('accepted','active') or v_row.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  v_mode := coalesce(v_row.metadata->>'mode', 'snapshot');
  if v_mode in ('snapshot','location_video') and not exists (
    select 1 from public.employee_locations
    where live_request_id = p_request_id and employee_id = v_me
  ) then
    raise exception 'نقطة الموقع مطلوبة' using errcode = '22023';
  end if;
  if v_mode in ('video_5s','location_video') and not exists (
    select 1 from public.live_location_videos_meta
    where live_request_id = p_request_id
      and employee_id = v_me
      and status = 'ready'
      and duration_seconds between 4 and 7
      and size_bytes > 0
  ) then
    raise exception 'video_required' using errcode = '22023';
  end if;

  update public.live_location_requests
  set status = 'completed',
      expires_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'videoWaived', false,
        'completionMode', 'verified',
        'completedAt', now()
      )
  where id = p_request_id
  returning * into v_row;

  perform public.log_audit_event(
    'live_location_completed', 'security', 'info',
    'live_location_requests', p_request_id,
    'إكمال طلب الموقع بعد التحقق من المتطلبات', null,
    jsonb_build_object('mode', v_mode, 'completionMode', 'verified')
  );
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.create_access_review_campaign(p_name text, p_description text, p_due_at timestamp with time zone)
 RETURNS access_review_campaigns
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_campaign public.access_review_campaigns;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then
    raise exception 'access review denied' using errcode='42501';
  end if;
  if p_due_at is null or p_due_at <= now() then raise exception 'تاريخ استحقاق مستقبلي مطلوب' using errcode='22023'; end if;
  insert into public.access_review_campaigns(name,description,status,starts_at,due_at,created_by)
  values (trim(p_name),p_description,'active',now(),p_due_at,auth.uid()) returning * into v_campaign;
  insert into public.access_review_items(campaign_id,user_role_id,user_id,role_id,reviewer_user_id,snapshot)
  select v_campaign.id,ur.id,ur.user_id,ur.role_id,auth.uid(),jsonb_build_object(
    'roleSlug',r.slug,'roleName',r.name_ar,'effectiveFrom',ur.effective_from,'effectiveTo',ur.effective_to,'scopeOverride',ur.scope_override
  )
  from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());
  perform public.log_audit_event('access.review.started','access','notice','access_review_campaigns',v_campaign.id,'بدء مراجعة صلاحيات',p_description,jsonb_build_object('dueAt',p_due_at));
  return v_campaign;
end;
$function$;



create or replace function public.create_job_offer_admin(
  p_application_id uuid,
  p_title text default null,
  p_salary numeric default null,
  p_contract_type text default null,
  p_start_date date default null,
  p_expires_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_version integer;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.offer.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.applications where id = p_application_id and status = 'active') then raise exception 'APPLICATION_NOT_ACTIVE'; end if;
  select coalesce(max(version),0) + 1 into v_version from public.job_offers where application_id = p_application_id;

  insert into public.job_offers(application_id, salary, title, contract_type, start_date, expires_at, status, version, created_by)
  values (p_application_id, p_salary, nullif(trim(p_title),''), nullif(trim(p_contract_type),''), p_start_date, p_expires_at, 'draft', v_version, auth.uid())
  returning id into v_id;

  perform public.log_audit_event('recruitment.offer_created','workflow','info','job_offers',v_id,
    'إنشاء عرض توظيف', null, jsonb_build_object('applicationId',p_application_id,'version',v_version));
  return jsonb_build_object('offerId', v_id, 'version', v_version, 'status', 'draft');
end $$;



CREATE OR REPLACE FUNCTION public.create_job_requisition_admin(p_department_id uuid, p_title text, p_headcount integer, p_reason text DEFAULT NULL::text, p_budget_range text DEFAULT NULL::text, p_submit boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.requisition.manage')) then
    raise exception 'إدارة طلبات التعيين مرفوضة' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_title), '') is null or coalesce(p_headcount, 0) <= 0 then
    raise exception 'القسم والمنصب وعدد موجب مطلوبة' using errcode = '22023';
  end if;
  insert into public.job_requisitions(
    department_id, title, headcount, reason, budget_range,
    status, requested_by, current_stage, created_by
  ) values (
    p_department_id, trim(p_title), p_headcount, nullif(trim(p_reason), ''), nullif(trim(p_budget_range), ''),
    case when p_submit then 'pending' else 'draft' end,
    public.current_employee_id(), case when p_submit then 'approval' else 'draft' end, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$function$;



create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true,
 p_use_parallel_flow boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid;
 v_open timestamptz; v_deadline timestamptz; v_status text:='draft';
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 if coalesce(p_open_now,false) and now() between v_open and v_deadline then v_status:='open'; end if;
 -- 0470: p_use_parallel_flow مقبول توافقاً لكنه مُهمَل — المسار الوحيد هو V24
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,use_parallel_flow,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,false,auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),
  use_parallel_flow=false,updated_at=now()
 returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,locked,created_by)
 select e.id,v_id,v_template,'self','self',case when v_status='open' then 'OPEN_FOR_SELF_EVALUATION' else 'DRAFT' end,v_status<>'open',auth.uid()
 from public.employees e
 where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
   and not exists(
     select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
     where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
       and (ur.effective_from is null or ur.effective_from<=now())
       and (ur.effective_to is null or ur.effective_to>now())
   )
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI (مسار مبسّط 0470)',null,jsonb_build_object('month',v_month,'status',v_status));
 return v_id;
end $$;



create or replace function public.create_kpi_cycle_admin_safe(
  p_month date,
  p_template_id uuid,
  p_self_due timestamptz,
  p_manager_due timestamptz,
  p_secretary_due timestamptz,
  p_executive_due timestamptz,
  p_open_now boolean default true,
  p_use_parallel_flow boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_sqlstate text;
  v_sqlerrm  text;
  v_ctx      text;
  v_hint     text;
  v_ar_msg   text;
begin
  if not (public.current_is_full_access() or public.current_is_executive_secretary()) then
    return jsonb_build_object('ok', false, 'errorAr',
      'ليس لديك صلاحية إنشاء دورة KPI. تحتاج دور full-access أو سكرتير تنفيذي.',
      'code', 'FORBIDDEN');
  end if;

  if not exists (select 1 from public.kpi_templates where id = p_template_id and official_code = 'OFFICIAL_KPI_100' and is_active) then
    return jsonb_build_object('ok', false, 'errorAr',
      'القالب الرسمي OFFICIAL_KPI_100 غير موجود أو غير نشط.',
      'code', 'NO_TEMPLATE');
  end if;

  if not exists (select 1 from public.kpi_policy_versions where is_active) then
    return jsonb_build_object('ok', false, 'errorAr',
      'لا توجد سياسة KPI نشطة.',
      'code', 'NO_POLICY');
  end if;

  begin
    v_id := public.create_kpi_cycle_admin(
      p_month             := p_month,
      p_template_id       := p_template_id,
      p_self_due          := p_self_due,
      p_manager_due       := p_manager_due,
      p_secretary_due     := p_secretary_due,
      p_executive_due     := p_executive_due,
      p_open_now          := p_open_now,
      p_use_parallel_flow := p_use_parallel_flow
    );
    return jsonb_build_object('ok', true, 'cycleId', v_id);
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_sqlerrm  = message_text,
      v_ctx      = pg_exception_context,
      v_hint     = pg_exception_hint;

    v_ar_msg := case
      when v_sqlstate = '42501' then 'ليس لديك صلاحية. تأكد من دورك في جدول user_roles.'
      when v_sqlstate = '23505' then 'توجد دورة مسجلة لهذا الشهر بالفعل.'
      when v_sqlstate = '23503' then 'يوجد مرجع مكسور في البيانات (employee أو template غير صالح).'
      when v_sqlstate = '23502' then 'حقل مطلوب فارغ في قاعدة البيانات.'
      when v_sqlstate = '23514' then 'قيمة تنتهك قيد تحقق في قاعدة البيانات.'
      when v_sqlstate = '22023' then 'قيمة غير صالحة مرسلة للدالة. تأكد من التواريخ.'
      when v_sqlstate = '42883' then 'الدالة غير موجودة بالتوقيع المطلوب — أعد تحميل schema cache.'
      when v_sqlstate = '42P01' then 'جدول مفقود في قاعدة البيانات: ' || coalesce(v_sqlerrm, '')
      when v_sqlstate = '42703' then 'عمود مفقود في قاعدة البيانات: ' || coalesce(v_sqlerrm, '')
      when v_sqlstate = 'P0002' then 'لم يُعثر على سجل: ' || coalesce(v_sqlerrm, '')
      else 'خطأ غير متوقع: ' || coalesce(v_sqlstate, '?') || ' — ' || coalesce(left(v_sqlerrm, 200), '')
    end;

    return jsonb_build_object(
      'ok', false,
      'errorAr', v_ar_msg,
      'code', coalesce(v_sqlstate, 'UNKNOWN'),
      'detail', left(coalesce(v_sqlerrm, ''), 500),
      'hint', left(coalesce(v_hint, ''), 500),
      'context', left(coalesce(v_ctx, ''), 500)
    );
  end;
end $$;



create or replace function public.create_kpi_policy_version(
 p_name text,p_attendance_rules jsonb,p_rating_bands jsonb,p_allow_target_overachievement boolean default false,p_effective_from date default current_date
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_version integer; v_weights jsonb:='{"TARGET":40,"EFFICIENCY":20,"ATTENDANCE":20,"CONDUCT":5,"PRAYER":5,"HALAQA":5,"INITIATIVES":5}'::jsonb; v_key text;
begin
 if not(public.current_is_full_access() or public.has_permission('performance.kpi.policy.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_name,'')))<3 or jsonb_typeof(p_attendance_rules)<>'object' or jsonb_typeof(p_rating_bands)<>'array' or jsonb_array_length(p_rating_bands)<1 then raise exception 'INVALID_KPI_POLICY'; end if;
 foreach v_key in array array['late','earlyLeave','unexcusedAbsence','missingPunch','shortagePerHour','maxShortagePerDay'] loop
  if not(p_attendance_rules?v_key) or (p_attendance_rules->>v_key)::numeric<0 then raise exception 'INVALID_ATTENDANCE_RULE_%',v_key; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_rating_bands) b where (b->>'min')::numeric<0 or (b->>'max')::numeric>100 or (b->>'min')::numeric>(b->>'max')::numeric or nullif(trim(b->>'label'),'') is null) then raise exception 'INVALID_RATING_BANDS'; end if;
 select coalesce(max(version),0)+1 into v_version from public.kpi_policy_versions;
 update public.kpi_policy_versions set is_active=false where is_active;
 insert into public.kpi_policy_versions(version,name_ar,effective_from,criteria_weights,attendance_rules,rating_bands,allow_target_overachievement,is_active,created_by)
 values(v_version,trim(p_name),coalesce(p_effective_from,current_date),v_weights,p_attendance_rules,p_rating_bands,coalesce(p_allow_target_overachievement,false),true,auth.uid()) returning id into v_id;
 perform public.log_audit_event('kpi.policy.version_created','workflow','warning','kpi_policy_versions',v_id,'إنشاء إصدار جديد من سياسة KPI',null,jsonb_build_object('version',v_version,'attendanceRules',p_attendance_rules,'ratingBands',p_rating_bands,'allowTargetOverachievement',p_allow_target_overachievement));
 return v_id;
end $$;



create or replace function public.create_my_dispute(p_title text,p_description text,p_case_type text default 'other',p_respondent_employee_id uuid default null,p_severity text default 'normal',p_confidential boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return public.submit_my_dispute(p_title,p_description,
  case p_case_type when 'conflict' then 'employee_conflict' when 'harassment' then 'inappropriate_conduct' when 'misconduct' then 'administrative_violation' else 'other' end,
  case when p_severity in ('urgent','high') then 'urgent' else 'normal' end,
  null,null,case when p_respondent_employee_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('employeeId',p_respondent_employee_id,'type','respondent')) end,
  '[]'::jsonb,null,null,null,'متابعة المشكلة واتخاذ الإجراء المناسب',p_confidential,true,true);
end $$;



CREATE OR REPLACE FUNCTION public.create_team_task(p_employee_id uuid, p_title text, p_description text DEFAULT NULL::text, p_priority text DEFAULT 'medium'::text, p_due_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_task_id uuid;
begin
  if v_manager_id is null or p_employee_id is null then
    raise exception 'سياق الموظف مطلوب' using errcode = '42501';
  end if;
  if p_employee_id=v_manager_id then
    raise exception 'استخدم مسار المهام الشخصية لمهامك' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'عنوان المهمة مطلوب' using errcode = '22023';
  end if;
  if p_priority not in ('low','medium','high','urgent') then
    raise exception 'أولوية مهمة غير مدعومة' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'tasks.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=p_employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'نطاق إسناد المهام مرفوض' using errcode = '42501';
  end if;

  insert into public.tasks(
    title, description, assignee_employee_id, priority, due_date,
    status, created_by_employee_id, created_by
  ) values (
    trim(p_title), nullif(trim(coalesce(p_description,'')),''), p_employee_id,
    p_priority, p_due_date, 'pending', v_manager_id, auth.uid()
  ) returning id into v_task_id;

  return v_task_id;
end;
$function$;



CREATE OR REPLACE FUNCTION public.create_work_assignment(p_assignment_type text, p_title text, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_participant_ids uuid[], p_description text DEFAULT NULL::text, p_location text DEFAULT NULL::text, p_responsible_employee_id uuid DEFAULT NULL::uuid, p_needs_report boolean DEFAULT false, p_report_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.work_assignments;
  v_emp uuid;
  v_can_manage boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if v_me is null then raise exception 'لا يوجد موظف مرتبط' using errcode = '42501'; end if;
  if p_assignment_type not in ('MISSION','CONVOY','FUNDRAISING') then
    raise exception 'نوع تكليف غير صالح' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'العنوان مطلوب' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at < p_start_at then
    raise exception 'فترة تكليف غير صالحة' using errcode = '22023';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'مشارك واحد على الأقل مطلوب' using errcode = '22023';
  end if;
  if array_length(p_participant_ids,1) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;

  v_can_manage := public.can_manage_assignment_type_org_wide(p_assignment_type);

  foreach v_emp in array p_participant_ids loop
    if not (v_can_manage or public.can_access_employee(v_emp)) then
      raise exception 'cannot assign employee outside your team without permission: %', v_emp
        using errcode = '42501';
    end if;
  end loop;

  insert into public.work_assignments(
    assignment_type, subtype, title, description, status,
    created_by_employee_id, responsible_employee_id, start_at, end_at,
    is_full_day, location, transport_mode, instructions, project_id, campaign_name,
    target_amount, needs_report, report_due_at, metadata, created_by)
  values(
    p_assignment_type, nullif(v_payload->>'subtype',''), trim(p_title), p_description,
    'APPROVED',
    v_me, coalesce(p_responsible_employee_id, v_me), p_start_at, p_end_at,
    coalesce((v_payload->>'isFullDay')::boolean, true),
    p_location, nullif(v_payload->>'transportMode',''),
    nullif(v_payload->>'instructions',''),
    nullif(v_payload->>'projectId','')::uuid, nullif(v_payload->>'campaignName',''),
    nullif(v_payload->>'targetAmount','')::numeric,
    coalesce(p_needs_report,false), p_report_due_at, v_payload, auth.uid())
  returning * into v_row;

  foreach v_emp in array p_participant_ids loop
    insert into public.work_assignment_participants(
      assignment_id, employee_id, role_in_assignment, created_by)
    values(v_row.id, v_emp, nullif(v_payload->>'roleInAssignment',''), auth.uid())
    on conflict(assignment_id, employee_id) do nothing;

    perform public.notify_employee(
      v_emp, 'تكليف عمل جديد',
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', 'normal', 'work_assignments', v_row.id,
      jsonb_build_object('assignmentType', v_row.assignment_type,
                         'startAt', v_row.start_at, 'endAt', v_row.end_at));
  end loop;

  perform public.log_audit_event(
    'assignment.created', 'workflow', 'info', 'work_assignments', v_row.id,
    'إنشاء تكليف عمل', v_row.title,
    jsonb_build_object('type', v_row.assignment_type,
                       'participants', array_length(p_participant_ids,1)));
  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.decide_access_review_item(p_item_id uuid, p_decision text, p_reason text)
 RETURNS access_review_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_item public.access_review_items;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then raise exception 'access review denied' using errcode='42501'; end if;
  if p_decision not in ('keep','revoke') then raise exception 'قرار غير صالح' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  select * into v_item from public.access_review_items where id=p_item_id for update;
  if not found then raise exception 'عنصر المراجعة غير موجود' using errcode='P0002'; end if;
  if v_item.decision <> 'pending' then raise exception 'عنصر المراجعة مُقرر عليه بالفعل' using errcode='P0001'; end if;
  update public.access_review_items set decision=p_decision,decision_reason=p_reason,decided_at=now(),reviewer_user_id=auth.uid()
  where id=p_item_id returning * into v_item;
  if p_decision='revoke' then update public.user_roles set effective_to=now() where id=v_item.user_role_id; end if;
  perform public.log_audit_event('access.review.decided','access',case when p_decision='revoke' then 'warning' else 'info' end,
    'access_review_items',v_item.id,'قرار مراجعة صلاحية',p_reason,jsonb_build_object('decision',p_decision,'userRoleId',v_item.user_role_id));
  perform public.notify_user(
    v_item.user_id,
    case p_decision when 'revoke' then 'أُلغيت صلاحية من حسابك' else 'تأكيد صلاحية من حسابك' end,
    format('قرار مراجعة الصلاحيات: %s.%s', case p_decision when 'revoke' then 'أُلغي دور' else 'أُبقي على دور' end, E'\n'||p_reason),
    'security', case p_decision when 'revoke' then 'high' else 'normal' end,
    'access_review_items', v_item.id,
    jsonb_build_object('decision', p_decision));
  return v_item;
end;
$function$;



create or replace function public.decide_admin_action(
  p_case_id         uuid,
  p_decision        text,
  p_reason          text,
  p_modified_action text default null,
  p_modified_detail text default null
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v record;
  v_approved_action text;
  v_approved_detail text;
  v_new_status      text;
begin
  -- صلاحية: المدير التنفيذي أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.decide')
    or public.has_permission('disputes.executive.manage')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_decision not in ('approved','modified','rejected','deferred') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  if v.status <> 'action_proposed' then
    raise exception 'CASE_NOT_IN_ACTION_PROPOSED' using errcode = '22023';
  end if;

  -- تحديد الإجراء المعتمد
  if p_decision = 'approved' then
    v_approved_action := v.proposed_administrative_action;
    v_approved_detail := v.proposed_action_detail;
    v_new_status      := 'pending_execution';
  elsif p_decision = 'modified' then
    if p_modified_action is null then
      raise exception 'MODIFIED_ACTION_REQUIRED' using errcode = '22023';
    end if;
    if p_modified_action not in (
      'verbal_warning','written_warning','final_warning','salary_deduction',
      'suspension','demotion','termination','transfer','training_requirement','no_action'
    ) then
      raise exception 'INVALID_ACTION_TYPE' using errcode = '22023';
    end if;
    v_approved_action := p_modified_action;
    v_approved_detail := coalesce(nullif(trim(p_modified_detail), ''), v.proposed_action_detail);
    v_new_status      := 'pending_execution';
  else
    -- rejected / deferred → إعادة إلى decision_issued ليعيد المقرر الاقتراح
    v_new_status := 'decision_issued';
  end if;

  if p_decision in ('approved','modified') then
    update public.dispute_cases set
      executive_decision              = p_decision,
      executive_decision_reason       = trim(p_reason),
      executive_decision_at           = now(),
      executive_decision_by           = public.current_employee_id(),
      approved_administrative_action  = v_approved_action,
      approved_action_detail          = v_approved_detail,
      status                          = v_new_status,
      updated_at                      = now()
    where id = p_case_id;
  else
    update public.dispute_cases set
      executive_decision              = p_decision,
      executive_decision_reason       = trim(p_reason),
      executive_decision_at           = now(),
      executive_decision_by           = public.current_employee_id(),
      -- مسح الاقتراح ليعيد المقرر تقديمه
      proposed_administrative_action  = null,
      proposed_action_detail          = null,
      proposed_at                     = null,
      proposed_by                     = null,
      approved_administrative_action  = null,
      approved_action_detail          = null,
      status                          = v_new_status,
      updated_at                      = now()
    where id = p_case_id;
  end if;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'decide_admin_action', 'action_proposed', v_new_status,
    trim(p_reason), public.current_employee_id(), auth.uid(),
    jsonb_build_object(
      'decision', p_decision,
      'approved_action', v_approved_action,
      'proposed_action', v.proposed_administrative_action
    )
  );

  perform public.log_audit_event(
    'dispute.admin_action_decided', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'قرار تنفيذي: ' || p_decision,
    trim(p_reason),
    jsonb_build_object(
      'decision', p_decision,
      'approved_action', v_approved_action,
      'proposed_action', v.proposed_administrative_action
    )
  );
end;
$$;



create or replace function public.decide_attendance_correction(p_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.attendance_corrections; v_daily uuid;
begin
 select * into strict v_row from public.attendance_corrections where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.correction.review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 if p_decision='rejected' and length(trim(coalesce(p_note,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
 update public.attendance_corrections set status=p_decision,reviewed_by=public.current_employee_id(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=p_id;
 if p_decision='approved' then
  insert into public.attendance_daily(employee_id,work_date,first_check_in,last_check_out,status,is_finalized,created_by)
  values(v_row.employee_id,v_row.work_date,v_row.requested_check_in,v_row.requested_check_out,coalesce(v_row.requested_status,'present'),false,auth.uid())
  on conflict(employee_id,work_date) do update set first_check_in=coalesce(v_row.requested_check_in,attendance_daily.first_check_in),last_check_out=coalesce(v_row.requested_check_out,attendance_daily.last_check_out),status=coalesce(v_row.requested_status,attendance_daily.status),updated_at=now();
 end if;
 perform public.log_audit_event('attendance.correction.'||p_decision,'workflow',case when p_decision='approved' then 'notice' else 'warning' end,'attendance_corrections',p_id,'قرار تصحيح حضور',p_note,jsonb_build_object('employeeId',v_row.employee_id,'workDate',v_row.work_date));
 perform public.notify_employee(
   v_row.employee_id,
   case p_decision when 'approved' then 'تم قبول تصحيح الحضور' else 'تم رفض تصحيح الحضور' end,
   format('تصحيح حضور بتاريخ %s%s', v_row.work_date, case when p_note is not null then E'\n'||p_note else '' end),
   'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
   'attendance_corrections', p_id,
   jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date));
end $$;



CREATE OR REPLACE FUNCTION public.decide_discipline_action(p_action_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS employee_discipline_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.approve')) then
    raise exception 'FORBIDDEN: requires relations.discipline.approve' using errcode = '42501';
  end if;

  select * into v_row from public.employee_discipline_actions where id = p_action_id;
  if not found then
    raise exception 'discipline_action_not_found' using errcode = 'P0002';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'discipline_action_not_pending' using errcode = '22023';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'قرار غير صالح' using errcode = '22023';
  end if;

  update public.employee_discipline_actions
  set status = p_decision,
      decision_note = p_note,
      decided_by = v_me,
      decided_at = now(),
      updated_at = now()
  where id = p_action_id
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.' || p_decision, 'compliance',
    case when p_decision = 'approved' then 'high' else 'info' end,
    'employee_discipline_actions', v_row.id,
    case when p_decision = 'approved' then 'تم اعتماد الإجراء التأديبي' else 'تم رفض الإجراء التأديبي' end,
    null,
    jsonb_build_object('employeeId', v_row.employee_id, 'actionId', v_row.id, 'note', p_note));

  perform public.notify_employee(
    v_row.employee_id,
    case when p_decision = 'approved' then 'تم اعتماد إجراء تأديبي على ملفك' else 'تم رفض إجراء تأديبي مسجل على ملفك' end,
    coalesce(nullif(trim(p_note), ''), 'يرجى مراجعة سجلك من قسم الانضباط.'),
    'general', case when p_decision = 'approved' then 'normal' else 'low' end,
    null, null, '{}'::jsonb
  );

  return v_row;
end;
$function$;



create or replace function public.decide_dispute_appeal(p_appeal_id uuid,p_decision text,p_resolution text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_appeals; v_case public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.appeal.review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v from public.dispute_appeals where id=p_appeal_id for update;
 select * into strict v_case from public.dispute_cases where id=v.case_id for update;
 if v.status not in ('submitted','under_review') or p_decision not in ('accepted','rejected') or length(trim(coalesce(p_resolution,'')))<10 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 update public.dispute_appeals set status=p_decision,resolution=trim(p_resolution),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then update public.dispute_cases set status='reopened',reopened_at=now(),updated_at=now() where id=v.case_id; end if;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(v.case_id,'appeal_'||p_decision,v_case.status,case when p_decision='accepted' then 'reopened' else v_case.status end,trim(p_resolution),public.current_employee_id(),auth.uid(),jsonb_build_object('appealId',p_appeal_id));
 perform public.enqueue_dispute_notification(v.case_id,v.appellant_employee_id,'appeal-decision:'||p_appeal_id::text,case when p_decision='accepted' then 'تم قبول الاعتراض وإعادة فتح المشكلة' else 'تم رفض الاعتراض' end,trim(p_resolution),'high');
 perform public.log_audit_event('dispute.appeal_'||p_decision,'workflow','warning','dispute_appeals',p_appeal_id,'البت في اعتراض',trim(p_resolution));
end $$;



create or replace function public.decide_interview_admin(
  p_interview_id uuid,
  p_status text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_app uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.interview.manage')) then raise exception 'FORBIDDEN'; end if;
  if coalesce(p_status,'') not in ('completed','cancelled','no_show') then raise exception 'INVALID_STATUS'; end if;
  update public.interviews set status = p_status, updated_at = now()
    where id = p_interview_id and status = 'scheduled'
    returning application_id into v_app;
  if v_app is null then raise exception 'INTERVIEW_NOT_ACTIONABLE'; end if;
  perform public.log_audit_event('recruitment.interview_'||p_status,'workflow','info','interviews',p_interview_id,
    'تحديث حالة مقابلة', null, jsonb_build_object('applicationId',v_app,'status',p_status));
  return jsonb_build_object('interviewId', p_interview_id, 'status', p_status);
end $$;



create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then
  -- V17: route to manager_review (the finalization step), not manager_final
  update public.kpi_evaluations set stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now() where id=v.evaluation_id;
 end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض KPI',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
 perform public.notify_employee(
   v.employee_id,
   case p_decision when 'accepted' then 'تم قبول اعتراضك على تقييم KPI' else 'تم رفض اعتراضك على تقييم KPI' end,
   format('%s%s', case p_decision when 'accepted' then 'أُعيد التقييم للمراجعة النهائية.' else 'بقيت النتيجة كما هي.' end, E'\n'||trim(p_note)),
   'kpi', case p_decision when 'accepted' then 'normal' else 'high' end,
   'kpi_appeals', p_appeal_id,
   jsonb_build_object('decision', p_decision, 'evaluationId', v.evaluation_id));
end $$;



create or replace function public.decide_overtime_record(p_id uuid,p_decision text,p_approved_minutes integer default null,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.overtime_records; v_min integer;
begin
 select * into strict v_row from public.overtime_records where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.overtime.approve')) then raise exception 'FORBIDDEN'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 v_min := case when p_decision='approved' then least(coalesce(p_approved_minutes,v_row.requested_minutes),v_row.requested_minutes) else 0 end;
 update public.overtime_records set status=p_decision,approved_minutes=v_min,approved_by=public.current_employee_id(),approved_at=now(),reason=coalesce(p_note,reason),updated_at=now() where id=p_id;
 perform public.log_audit_event('attendance.overtime.'||p_decision,'workflow',case when p_decision='approved' then 'notice' else 'warning' end,'overtime_records',p_id,'قرار ساعات إضافية',p_note,jsonb_build_object('employeeId',v_row.employee_id,'workDate',v_row.work_date,'approvedMinutes',v_min));
 perform public.notify_employee(
   v_row.employee_id,
   case p_decision when 'approved' then 'تم اعتماد ساعاتك الإضافية' else 'تم رفض ساعاتك الإضافية' end,
   format('ساعات إضافية بتاريخ %s (%s دقيقة)%s', v_row.work_date, v_min, case when p_note is not null then E'\n'||p_note else '' end),
   'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
   'overtime_records', p_id,
   jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date, 'approvedMinutes', v_min));
end $$;



CREATE OR REPLACE FUNCTION public.decide_privacy_request(p_request_id uuid, p_status text, p_reason text)
 RETURNS privacy_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.privacy_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('privacy.request.manage')) then raise exception 'إدارة الخصوصية مرفوضة' using errcode='42501'; end if;
  if p_status not in ('in_review','waiting_requester','approved','rejected','completed') then raise exception 'حالة غير صالحة' using errcode='22023'; end if;
  if p_status in ('rejected','completed') and length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  update public.privacy_requests set status=p_status,decision_reason=p_reason,assigned_to=coalesce(assigned_to,auth.uid()),
    completed_at=case when p_status='completed' then now() else completed_at end where id=p_request_id returning * into v_row;
  if not found then raise exception 'طلب الخصوصية غير موجود' using errcode='P0002'; end if;
  perform public.log_audit_event('privacy.request.updated','data','notice','privacy_requests',v_row.id,'تحديث طلب خصوصية',p_reason,jsonb_build_object('status',p_status));
  perform public.notify_user(
    v_row.requester_user_id,
    'تحديث حالة طلب الخصوصية',
    format('أصبح طلبك بحالة %s.%s', p_status, case when p_reason is not null then E'\n'||p_reason else '' end),
    'privacy', case when p_status in ('approved','completed') then 'normal' else 'high' end,
    'privacy_requests', v_row.id,
    jsonb_build_object('status', p_status));
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.decide_request(p_request_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_exec_emp        uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;
  -- حظر الموافقة الذاتية للجميع إلا HR (إذن صريح من الإدارة — 0464)
  if v_req.employee_id = v_me
     and not public.current_has_active_role(array['hr-manager','hr-specialist']) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ
  -- أول escalated/pending (إصلاح 0403).
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);
  v_is_direct_mgr := (v_req.manager_employee_id = v_me);
  -- أبو عمار = مدير التشغيل 1 فقط (لا ضابط عمليات)
  v_is_operations := public.current_has_active_role(array['operations-manager-1']);
  -- 0441: HR غير مقيد — يعتمد أي طلب في أي وقت
  v_is_hr         := public.current_has_active_role(array['hr-manager','hr-specialist']);

  -- ── الصلاحية ──
  -- المدير المباشر + HR (0441) + full_access: دائماً (أي مرحلة، أي وقت)
  -- أبو عمار (operations-manager-1): من الخطوة 2 فما فوق، أو عندما تكون مهلة
  --   الخطوة/الطلب متجاوزة (طلبات قديمة عالقة — 0440).
  if not found then
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or v_is_hr
      or public.can_access_employee(v_req.employee_id, 'requests.approve');
  else
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or v_is_hr
      or (v_is_operations
          and (
            v_current_step >= 2
            or coalesce(v_step.escalation_deadline, v_req.escalation_deadline) < now()
            or v_req.workflow_status in ('escalated', 'awaiting_operator')
          )
          and public.can_access_employee(v_req.employee_id, 'requests.approve'));
  end if;

  if not v_authorized then
    raise exception 'not authorized for the active workflow step (step: %, role required)'
      , v_current_step using errcode = '42501';
  end if;

  -- تحديد دور الفاعل للسجل
  v_actor_role := case
    when public.current_is_full_access() and not v_is_direct_mgr then 'admin'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_hr then 'hr'
    when v_is_operations then 'operations'
    else 'authorized'
  end;

  v_final_status := case p_decision
    when 'approve' then 'approved'
    when 'return'  then 'returned'
    else 'rejected'
  end;

  -- تسجيل إجراء الخطوة الحالية
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  -- إغلاق باقي الخطوات (موافقة واحدة تُنهي الطلب — لا مرحلتين)
  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending','active','escalated')
    and id is distinct from v_step.id;

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status = v_final_status,
        workflow_status = 'completed',
        decided_at = now(), decided_by = v_me, updated_at = now()
  where id = p_request_id
  returning * into v_req;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف بالنتيجة
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request',
    case when v_req.status = 'approved' then 'normal' else 'high' end,
    'request', v_req.id,
    jsonb_build_object(
      'decision', p_decision,
      'request_type', v_req.request_type,
      'actorRole', v_actor_role,
      'deepLink', '/requests/' || v_req.id
    )
  );

  -- إشعار المدير التنفيذي (كامل الشاشة) عند كل قرار
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_me then
    perform public.notify_executive_fullscreen(
      'قرار طلب — ' || case v_req.status
        when 'approved' then 'موافقة'
        when 'rejected' then 'رفض'
        else 'إعادة طلب' end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'decision', p_decision,
        'request_type', v_req.request_type,
        'actorRole', v_actor_role
      )
    );
  end if;

  return v_req;
end;
$function$;



CREATE OR REPLACE FUNCTION public.decide_work_assignment(p_assignment_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments; v_to text; v_part uuid;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'قرار غير صالح' using errcode = '22023';
  end if;
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'غير مصرح لك بحسم هذا التكليف' using errcode = '42501';
  end if;
  if v_row.status not in ('SUBMITTED','PENDING_APPROVAL','DRAFT') then
    raise exception 'assignment not in a decidable state (%)', v_row.status using errcode = '22023';
  end if;
  v_to := case when p_decision = 'approve' then 'APPROVED' else 'REJECTED' end;

  update public.work_assignments
    set status = v_to, decided_by = v_me, decided_at = now(),
        decision_comment = p_comment, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.decided', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'قرار على تكليف عمل', p_decision,
    jsonb_build_object('decision', p_decision, 'type', v_row.assignment_type));

  -- إشعار المشاركين ومنشئ التكليف (0316)
  for v_part in
    select employee_id from public.work_assignment_participants
    where assignment_id = p_assignment_id
  loop
    perform public.notify_employee(
      v_part,
      case p_decision when 'approve' then 'تم اعتماد تكليفك' else 'تم رفض تكليفك' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end loop;
  if v_row.created_by_employee_id is not null and v_row.created_by_employee_id <> v_me then
    perform public.notify_employee(
      v_row.created_by_employee_id,
      case p_decision when 'approve' then 'تم اعتماد تكليف العمل' else 'تم رفض تكليف العمل' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end if;

  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.delete_daily_report_comment(p_comment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_owner uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select employee_id into v_owner
  from public.daily_report_comments
  where id = p_comment_id;
  if not found then
    raise exception 'التعليق غير موجود' using errcode = 'P0002';
  end if;

  if v_owner is distinct from v_me and not public.current_is_full_access() then
    raise exception 'غير مصرح لك بحذف هذا التعليق' using errcode = '42501';
  end if;

  delete from public.daily_report_comments where id = p_comment_id;
end;
$function$;



create or replace function public.detect_and_raise_alerts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_raised integer := 0;
  v_val    numeric;
  v_rec    record;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- 4.1 [P0] طابور تكامل Dead-letter > 0
  select dead_letter into v_val from public.v_monitor_integration_queue;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('queue_dead_letter', 'P0', 'queue',
            'رسائل تكامل في Dead-letter',
            format('%s رسالة في dead_letter تحتاج تدخلًا يدويًا', v_val),
            v_val, 0, jsonb_build_object('table','integration_outbox'))
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.2 [P1] طابور تكامل failed متأخر (overdue > 20)
  select overdue into v_val from public.v_monitor_integration_queue;
  if coalesce(v_val,0) > 20 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('queue_overdue', 'P1', 'queue',
            'طابور تكامل متأخر عن المعالجة',
            format('%s رسالة تجاوزت موعد إعادة المحاولة بـ15 دقيقة', v_val),
            v_val, 20, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.3 [P0] أخطاء fatal في آخر ساعة
  select fatal_1h into v_val from public.v_monitor_errors;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('errors_fatal', 'P0', 'error',
            'أخطاء fatal في التطبيق',
            format('%s خطأ fatal خلال الساعة الأخيرة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.4 [P1] ارتفاع الأخطاء (error+ > 50/ساعة)
  select errors_1h into v_val from public.v_monitor_errors;
  if coalesce(v_val,0) > 50 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('errors_spike', 'P1', 'error',
            'ارتفاع معدّل الأخطاء',
            format('%s خطأ خلال الساعة الأخيرة (الحد 50)', v_val),
            v_val, 50, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.5 [P0] أحداث أمنية حرجة في آخر ساعة
  select critical_1h into v_val from public.v_monitor_security;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('security_critical', 'P0', 'security',
            'أحداث أمنية حرجة',
            format('%s حدث أمني بخطورة critical خلال الساعة الأخيرة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.6 [P1] إشعارات عالقة (queued > 30 دقيقة)
  select stuck into v_val from public.v_monitor_notifications;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('notifications_stuck', 'P1', 'notification',
            'إشعارات عالقة في الطابور',
            format('%s إشعار في حالة queued لأكثر من 30 دقيقة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.7 [P1] فشل مهام cron (آخر تشغيل failed) — إن توفّر cron
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      for v_rec in
        select j.jobname, d.status
        from cron.job j
        join lateral (
          select status from cron.job_run_details r
          where r.jobid = j.jobid order by start_time desc limit 1
        ) d on true
        where d.status = 'failed'
      loop
        insert into public.system_alerts as a
          (alert_key, severity, source, title, detail, context)
        values ('cron_failed:'||v_rec.jobname, 'P1', 'cron',
                'فشل مهمة مجدولة: '||v_rec.jobname,
                'آخر تشغيل للمهمة انتهى بحالة failed', jsonb_build_object('job', v_rec.jobname))
        on conflict (alert_key) where status = 'open'
        do update set last_seen_at = now(), occurrences = a.occurrences + 1;
        v_raised := v_raised + 1;
      end loop;
    exception
      when insufficient_privilege or undefined_table then
        null;  -- لا صلاحية cron.* في هذا الدور — نتجاوز بأمان فقط لهذه الحالة
      -- أي خطأ آخر (فشل كتابة/قفل/timeout) يُترك ليُطرح: لا نُخفي فشل التنبيهات كنجاح
    end;
  end if;

  -- سجل تشغيل الكاشف نفسه (تدقيق)
  perform public.log_audit_event(
    'monitor.alerts.scan', 'system', 'info', 'system_alerts', null,
    'فحص التنبيهات الآلي', format('رُصدت/حُدِّثت %s حالة', v_raised),
    jsonb_build_object('raised', v_raised));

  return v_raised;
end $$;



create or replace function public.discipline_action_type_label(p_type text)
returns text
language sql immutable strict
as $$
  select case p_type
    when 'verbal_warning' then 'تنبيه شفهي'
    when 'written_warning' then 'إنذار كتابي'
    when 'salary_deduction' then 'خصم من الراتب'
    when 'suspension' then 'إيقاف مؤقت'
    when 'termination' then 'إنهاء خدمة'
    else coalesce(p_type, '')
  end;
$$;



create or replace function public.end_my_mission(
  p_request_id uuid,
  p_report text,
  p_outcome text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := public.current_employee_id();
  v_exec    public.mission_executions;
  v_minutes integer;
  v_today   date := (now() at time zone 'Africa/Cairo')::date;
  v_cutoff  time;
  v_end_now time := (now() at time zone 'Africa/Cairo')::time;
  v_auto    boolean;
  v_geofence_id uuid;
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

  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');
  v_auto := v_end_now >= v_cutoff;

  update public.mission_executions
     set ended_at         = now(),
         actual_minutes   = v_minutes,
         report           = trim(p_report),
         outcome          = nullif(trim(coalesce(p_outcome, '')), ''),
         status           = 'completed',
         updated_at       = now()
   where id = v_exec.id;

  --attendance_daily (نفس0450): تسجيل الحضور والانصراف اليومي
  insert into public.attendance_daily
    (employee_id, work_date, status, first_check_in, last_check_out, work_minutes, updated_at)
  values
    (v_me,
     v_today,
     'present',
     v_exec.started_at,
     case when v_auto then now() end,
     v_minutes,
     now())
  on conflict (employee_id, work_date) do update
    set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
        last_check_out = coalesce(public.attendance_daily.last_check_out, excluded.last_check_out),
        work_minutes   = greatest(public.attendance_daily.work_minutes, excluded.work_minutes),
        status         = case
                           when public.attendance_daily.status in ('absent','missing_checkout','pending')
                             then 'present'
                           else public.attendance_daily.status
                         end,
        updated_at     = now();

  -- 0481: عند الإنهاء قبل نهاية الدوام (انصراف يدوي)، يُنشئ حدث CHECK_IN
  -- في attendance_events حتى يتوافق التسلسل مع record_attendance_local_biometric.
  -- بدون هذا، يرفض التسجيل بـ 'attendance_check_in_required'.
  if not v_auto then
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

  return v_exec.id;
end $$;



CREATE OR REPLACE FUNCTION public.enqueue_integration_event(p_integration_id uuid, p_event_type text, p_aggregate_type text, p_aggregate_id uuid, p_idempotency_key text, p_payload jsonb, p_headers jsonb DEFAULT '{}'::jsonb, p_correlation_id text DEFAULT NULL::text)
 RETURNS integration_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.integration_outbox;
begin
  if length(trim(coalesce(p_idempotency_key,''))) < 8 then raise exception 'مفتاح منع التكرار مطلوب' using errcode='22023'; end if;
  insert into public.integration_outbox(integration_id,event_type,aggregate_type,aggregate_id,idempotency_key,payload,headers,correlation_id)
  values(p_integration_id,p_event_type,p_aggregate_type,p_aggregate_id,p_idempotency_key,coalesce(p_payload,'{}'::jsonb),coalesce(p_headers,'{}'::jsonb),p_correlation_id)
  on conflict (idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning * into v_row;
  return v_row;
end;
$function$;



create or replace function public.escape_ilike(p_input text)
returns text
language sql immutable parallel safe
as $$
  -- يهرب الأحرف الخاصة في ILIKE: % → \%  _ → \_  \ → \\
  select replace(replace(replace(p_input, '\', '\\'), '%', '\%'), '_', '\_');
$$;



create or replace function public.execute_admin_action(
  p_case_id uuid,
  p_notes   text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v record;
begin
  -- صلاحية: HR أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.execute')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if nullif(trim(p_notes), '') is null then
    raise exception 'NOTES_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  if v.status <> 'pending_execution' then
    raise exception 'CASE_NOT_PENDING_EXECUTION' using errcode = '22023';
  end if;

  if v.approved_administrative_action is null then
    raise exception 'NO_APPROVED_ACTION' using errcode = '22023';
  end if;

  update public.dispute_cases set
    executed_at      = now(),
    executed_by      = public.current_employee_id(),
    execution_notes  = trim(p_notes),
    status           = 'executed',
    updated_at       = now()
  where id = p_case_id;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'execute_admin_action', 'pending_execution', 'executed',
    trim(p_notes), public.current_employee_id(), auth.uid(),
    jsonb_build_object('action', v.approved_administrative_action)
  );

  perform public.log_audit_event(
    'dispute.admin_action_executed', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'تنفيذ إجراء: ' || v.approved_administrative_action,
    trim(p_notes),
    jsonb_build_object(
      'action', v.approved_administrative_action,
      'decision', v.executive_decision
    )
  );
end;
$$;



create or replace function public.extend_request_deadline(
  p_request_id uuid,
  p_hours integer,
  p_reason text
)
returns public.requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_req public.requests;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['requests.request.override','requests.request.escalate'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 720 then
    raise exception 'INVALID_HOURS' using errcode = '22023';
  end if;
  update public.requests
    set decision_due_at = coalesce(decision_due_at, now()) + make_interval(hours => p_hours),
        escalation_deadline = coalesce(decision_due_at, now()) + make_interval(hours => p_hours),
        updated_at = now()
    where id = p_request_id and status = 'pending'
    returning * into v_req;
  if not found then raise exception 'request not found or not pending' using errcode = 'P0002'; end if;

  insert into public.request_actions(request_id, actor_employee_id, action, comment, metadata)
  values(p_request_id, public.current_employee_id(), 'comment',
    coalesce(p_reason, 'تمديد مهلة القرار'),
    jsonb_build_object('extendedHours', p_hours));

  perform public.log_audit_event('request.deadline.extended', 'workflow', 'info',
    'requests', p_request_id, 'تمديد مهلة قرار الطلب', p_reason,
    jsonb_build_object('hours', p_hours));
  return v_req;
end $$;



create or replace function public.finalize_dispute_session_v2(p_session_id uuid,p_minutes text,p_attendance jsonb,p_outcome text default null,p_minutes_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.dispute_sessions; v_case public.dispute_cases; v_item jsonb; v_member uuid; v_present integer:=0;
begin
 select * into strict v_session from public.dispute_sessions where id=p_session_id for update;
 select * into strict v_case from public.dispute_cases where id=v_session.case_id for update;
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=v_case.id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_session.status<>'scheduled' or length(trim(coalesce(p_minutes,'')))<20 or jsonb_typeof(p_attendance)<>'array' then raise exception 'INVALID_MINUTES'; end if;
 if jsonb_array_length(p_attendance)>100 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 delete from public.dispute_session_attendance where session_id=p_session_id;
 for v_item in select * from jsonb_array_elements(p_attendance) loop
  v_member=(v_item->>'committeeMemberId')::uuid;
  if not exists(select 1 from public.committee_members cm where cm.id=v_member and cm.case_id=v_case.id and cm.is_active) then raise exception 'INVALID_COMMITTEE_MEMBER' using errcode='22023'; end if;
  insert into public.dispute_session_attendance(session_id,committee_member_id,attendance_status,signed_at,signature_method,created_by)
  values(p_session_id,v_member,coalesce(v_item->>'status','present'),case when coalesce(v_item->>'status','present') in ('present','remote') then now() end,case when coalesce(v_item->>'status','present') in ('present','remote') then 'manual_verified' end,auth.uid());
  if coalesce(v_item->>'status','present') in ('present','remote') then v_present=v_present+1; end if;
 end loop;
 if v_present<v_case.committee_quorum then raise exception 'QUORUM_NOT_MET'; end if;
 update public.dispute_sessions set status='held',held_at=now(),minutes=trim(p_minutes),outcome=nullif(trim(p_outcome),''),minutes_data=coalesce(p_minutes_data,'{}'::jsonb),recommendation=nullif(trim(p_minutes_data->>'recommendation'),''),follow_up_at=nullif(p_minutes_data->>'followUpAt','')::timestamptz,internal_notes=nullif(trim(p_minutes_data->>'internalNotes'),''),updated_at=now() where id=p_session_id;
 update public.dispute_cases set status='committee_deliberation',updated_at=now() where id=v_case.id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(v_case.id,'session_completed',v_case.status,'committee_deliberation',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',p_session_id,'present',v_present));
 perform public.log_audit_event('dispute.session_completed','workflow','notice','dispute_sessions',p_session_id,'حفظ محضر جلسة المشكلة',null,jsonb_build_object('caseId',v_case.id,'present',v_present));
end $$;



create or replace function public.finalize_missing_checkouts()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_count integer := 0;
  v_grace_minutes integer;
  v_tz text;
  v_now timestamptz := now();
  v_rec record;
  v_shift public.shifts%rowtype;
  v_deadline timestamptz;
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  select s.missing_checkout_grace_minutes, s.timezone
    into v_grace_minutes, v_tz
  from public.attendance_settings s
  limit 1;
  v_grace_minutes := coalesce(v_grace_minutes, 60);
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  for v_rec in
    select ad.id, ad.employee_id, ad.work_date, ad.shift_id
    from public.attendance_daily ad
    where ad.first_check_in is not null
      and ad.last_check_out is null
      and not ad.is_finalized
      and ad.status not in ('on_leave', 'holiday', 'weekend', 'missing_checkout')
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = عمل خارجي → لا يُصفّى كنقص
      and not exists (
        select 1 from public.requests r
        where r.employee_id = ad.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and ad.work_date between public._payload_date(r.payload, 'startDate')
                               and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      )
      and not exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = ad.employee_id and wa.status = 'APPROVED'
          and ad.work_date between (wa.start_at at time zone 'Africa/Cairo')::date
                               and (wa.end_at at time zone 'Africa/Cairo')::date
      )
    for update skip locked
  loop
    v_shift := null;
    if v_rec.shift_id is not null then
      select * into v_shift
      from public.shifts
      where id = v_rec.shift_id;
    end if;

    if v_shift.id is not null then
      v_deadline := (
        v_rec.work_date
        + case when v_shift.crosses_midnight then 1 else 0 end
        + v_shift.end_time
      ) at time zone v_tz
      + make_interval(mins => v_grace_minutes);
    else
      v_deadline := (v_rec.work_date + '18:00'::time) at time zone v_tz
                    + make_interval(mins => v_grace_minutes);
    end if;

    if v_now > v_deadline then
      update public.attendance_daily
      set status = 'missing_checkout', updated_at = now()
      where id = v_rec.id and not is_finalized;

      if found then
        insert into public.attendance_exceptions(
          employee_id, attendance_daily_id, work_date, kind, description
        )
        select
          v_rec.employee_id,
          v_rec.id,
          v_rec.work_date,
          'missing_check_out',
          'بصمة خروج مفقودة — أُنشئ تلقائياً بواسطة finalize_missing_checkouts'
        where not exists (
          select 1
          from public.attendance_exceptions ae
          where ae.attendance_daily_id = v_rec.id
            and ae.kind = 'missing_check_out'
            and ae.status in ('open', 'approved', 'resolved')
        );

        perform public.log_audit_event(
          'attendance.missing_checkout_finalized', 'operations', 'warning',
          'attendance_daily', v_rec.id,
          'بصمة خروج مفقودة — تصفية تلقائية', null,
          jsonb_build_object(
            'workDate', v_rec.work_date,
            'shiftId', v_rec.shift_id,
            'deadline', v_deadline
          )
        );
        v_count := v_count + 1;
      end if;
    end if;
  end loop;

  return v_count;
end $function$;



create or replace function public.finalize_verified_attendance(
  p_operation_id     uuid,
  p_correlation_id   uuid,
  p_challenge_id     uuid,
  p_credential_id    uuid,
  p_employee_id      uuid,
  p_user_id          uuid,
  p_event_type       text,
  p_latitude         double precision,
  p_longitude        double precision,
  p_accuracy_meters  double precision,
  p_new_sign_count   bigint,
  p_selfie_path      text default null,
  p_is_mock          boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempt    public.attendance_punch_attempts%rowtype;
  v_challenge  public.webauthn_challenges%rowtype;
  v_credential public.passkey_credentials%rowtype;
  v_device_exists boolean;
  v_event_id   uuid;
  v_event      public.attendance_events%rowtype;
  v_result     jsonb;
  v_error      text;
  -- 0208: v_known_errors synced with record_attendance_event (0201)
  v_known_errors text[] := array[
    'attendance_mock_location_rejected',
    'attendance_location_required',
    'attendance_location_accuracy_too_low',
    'attendance_outside_complex',
    'attendance_geofence_not_configured',
    'attendance_passkey_not_trusted',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required',
    'invalid_attendance_location'
  ];
begin
  -- ── Guard: caller must be service_role (0208 style) ──
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'rpc_service_role_only' using errcode = '42501';
  end if;

  -- ── Input validation (restored from 0089) ──
  if p_operation_id is null or p_correlation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;

  -- ── 0236: Selfie path validation (path-traversal / cross-employee hardening) ──
  -- p_selfie_path اختياري؛ عند وجوده يجب أن يكون مفتاح كائن داخل حاوية سيلفي
  -- الحضور، مقيَّداً بمجلّد الموظف صاحب البصمة:  <p_employee_id>/<yyyy>/<اسم_الملف>
  if p_selfie_path is not null then
    if length(p_selfie_path) = 0 then
      raise exception 'invalid_selfie_path_empty' using errcode = '22023';
    end if;
    if length(p_selfie_path) > 512 then
      raise exception 'invalid_selfie_path_too_long' using errcode = '22023';
    end if;
    if left(p_selfie_path, 1) = '/' then
      raise exception 'invalid_selfie_path_absolute' using errcode = '22023';
    end if;
    if position('\' in p_selfie_path) > 0 then
      raise exception 'invalid_selfie_path_backslash' using errcode = '22023';
    end if;
    if position('://' in p_selfie_path) > 0 then
      raise exception 'invalid_selfie_path_scheme' using errcode = '22023';
    end if;
    if p_selfie_path like '%..%' then
      raise exception 'invalid_selfie_path_traversal' using errcode = '22023';
    end if;
    -- الملكية: يجب أن يبدأ المسار بمجلّد الموظف نفسه  "<p_employee_id>/"
    -- (errcode 42501 مطابقةً لـ register_live_location_video). هوية uuid ثابتة
    -- الطول (36 محرفاً) ولا تحوي % أو _ فلا خطر من محارف LIKE.
    if p_selfie_path not like p_employee_id::text || '/%' then
      raise exception 'invalid_selfie_path_scope' using errcode = '42501';
    end if;
    -- تثبيت البِنية:  <employee>/<yyyy>/<filename>  بمقاطع غير فارغة وطقم محارف آمن.
    -- المرساة ^...$ تربط بداية/نهاية السلسلة (لا السطر) في POSIX regex الخاص بـ Postgres.
    if p_selfie_path !~ ('^' || p_employee_id::text || '/[0-9]{4}/[A-Za-z0-9._-]+$') then
      raise exception 'invalid_selfie_path_format' using errcode = '22023';
    end if;
  end if;

  -- ── ① FIX: Idempotency INSERT — include credential_id + event_type (NOT NULL) ──
  insert into public.attendance_punch_attempts(
    operation_id, correlation_id, challenge_id, credential_id,
    employee_id, user_id, event_type
  ) values (
    p_operation_id, p_correlation_id, p_challenge_id, p_credential_id,
    p_employee_id, p_user_id, p_event_type
  )
  on conflict (operation_id) do nothing;

  -- ── ⑤ FIX: Proper idempotency — FOR UPDATE lock + field comparison ──
  select * into v_attempt
  from public.attendance_punch_attempts
  where operation_id = p_operation_id
  for update;

  if v_attempt.operation_id is null then
    raise exception 'attendance_attempt_create_failed' using errcode = '55000';
  end if;
  if v_attempt.challenge_id <> p_challenge_id
     or v_attempt.credential_id <> p_credential_id
     or v_attempt.employee_id <> p_employee_id
     or v_attempt.user_id <> p_user_id
     or v_attempt.event_type <> p_event_type then
    raise exception 'attendance_idempotency_conflict' using errcode = '22023';
  end if;
  if v_attempt.status in ('completed', 'rejected') then
    return v_attempt.result || jsonb_build_object('replayed', true);
  end if;

  -- ── ② FIX: Validate WebAuthn challenge (restored from 0089) ──
  select * into v_challenge
  from public.webauthn_challenges
  where id = p_challenge_id
  for update;
  if v_challenge.id is null
     or v_challenge.type <> 'auth'
     or v_challenge.user_id <> p_user_id
     or v_challenge.employee_id <> p_employee_id
     or v_challenge.used_at is not null
     or v_challenge.expires_at <= now() then
    raise exception 'challenge_invalid_or_used' using errcode = '22023';
  end if;

  -- ── Verify credential is active + trusted ──
  select * into v_credential
  from public.passkey_credentials
  where id = p_credential_id
  for update;
  if v_credential.id is null
     or v_credential.user_id <> p_user_id
     or v_credential.employee_id <> p_employee_id
     or v_credential.status <> 'active'
     or not v_credential.trusted then
    raise exception 'attendance_passkey_not_trusted' using errcode = '28000';
  end if;

  -- ── Check active device exists — auto-provision if needed (0208 feature) ──
  select exists (
    select 1 from public.employee_devices d
    where d.employee_id = p_employee_id
      and d.user_id = p_user_id
      and d.credential_id = v_credential.credential_id
      and d.status = 'active'
  ) into v_device_exists;

  if not v_device_exists then
    -- إذا لم يكن هناك جهاز نشط، ننشئ جهاز بحالة pending
    -- ونرفض تسجيل الحضور حتى يُعتمد الجهاز من المسؤول.
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, public_key,
      device_name, platform, status, registered_at, metadata
    ) values (
      p_employee_id, p_user_id,
      encode(digest(convert_to(v_credential.credential_id, 'UTF8'), 'sha256'), 'hex'),
      v_credential.credential_id, v_credential.public_key,
      coalesce(v_credential.device_label, 'هاتف الموظف'), 'android', 'pending', now(),
      jsonb_build_object('serverVerified', true, 'autoProvisioned', 'finalize_attendance', 'passkeyCredentialId', v_credential.id)
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      credential_id = excluded.credential_id,
      public_key = excluded.public_key,
      status = public.employee_devices.status,
      metadata = public.employee_devices.metadata || excluded.metadata;

    -- إعادة فحص: هل أصبح الجهاز نشطاً بعد الـ upsert؟
    select exists (
      select 1 from public.employee_devices d
      where d.employee_id = p_employee_id
        and d.user_id = p_user_id
        and d.credential_id = v_credential.credential_id
        and d.status = 'active'
    ) into v_device_exists;

    if not v_device_exists then
      v_result := jsonb_build_object(
        'ok', false,
        'error', 'device_pending_approval',
        'correlationId', p_correlation_id,
        'operationId', p_operation_id,
        'replayed', false
      );
      update public.attendance_punch_attempts
      set status = 'rejected', rejection_code = 'device_pending_approval',
          result = v_result, completed_at = now()
      where operation_id = p_operation_id;
      return v_result;
    end if;
  end if;

  -- ── Counter replay check ──
  if p_new_sign_count < 0
     or (v_credential.sign_count > 0 and p_new_sign_count <= v_credential.sign_count) then
    raise exception 'authenticator_counter_replay' using errcode = '28000';
  end if;

  -- ── Consume challenge ──
  update public.webauthn_challenges
  set used_at = now()
  where id = p_challenge_id;

  -- ── Update credential counters ──
  update public.passkey_credentials
  set sign_count = p_new_sign_count, last_used = now()
  where id = p_credential_id;

  update public.employee_devices
  set last_used_at = now()
  where employee_id = p_employee_id
    and user_id = p_user_id
    and credential_id = v_credential.credential_id
    and status = 'active';

  -- ── Record attendance event ──
  begin
    v_event_id := public.record_attendance_event(
      p_employee_id,
      p_event_type,
      p_latitude,
      p_longitude,
      p_accuracy_meters,
      'passkey',
      p_selfie_path,
      p_credential_id,
      true,
      p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    if v_error = any(v_known_errors) then
      v_result := jsonb_build_object(
        'ok', false,
        'error', v_error,
        'correlationId', p_correlation_id,
        'operationId', p_operation_id,
        'replayed', false
      );
      update public.attendance_punch_attempts
      set status = 'rejected', rejection_code = v_error,
          result = v_result, completed_at = now()
      where operation_id = p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  select * into v_event from public.attendance_events where id = v_event_id;
  v_result := jsonb_build_object(
    'ok', true,
    'verified', true,
    'eventId', v_event_id,
    'eventType', p_event_type,
    'status', coalesce(v_event.status, 'accepted'),
    'insideComplex', v_event.status = 'accepted',
    'distanceMeters', v_event.distance_meters,
    'geofenceId', v_event.geofence_id,
    -- ③ FIX: event_at (not event_time — column does not exist)
    'recordedAt', v_event.event_at,
    'correlationId', p_correlation_id,
    'operationId', p_operation_id,
    'replayed', false,
    'credentialLabel', v_credential.device_label
  );

  -- ④ FIX: include attendance_event_id (required by CHECK constraint)
  update public.attendance_punch_attempts
  set status = 'completed', attendance_event_id = v_event_id,
      result = v_result, completed_at = now()
  where operation_id = p_operation_id;

  return v_result;
end;
$$;



CREATE OR REPLACE FUNCTION public.generate_instapay_batch(p_payroll_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_batch public.payroll_instapay_batches;
  v_count integer;
  v_total numeric;
  v_ref text;
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.payroll_runs
    where id = p_payroll_run_id and status in ('approved', 'posted')
  ) then
    raise exception 'يجب اعتماد أو ترحيل دورة الرواتب' using errcode='P0002';
  end if;

  select count(*), coalesce(sum(pl.net_amount), 0)
    into v_count, v_total
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  if v_count = 0 then raise exception 'لا قسائم قابلة للدفع بأرقام هواتف' using errcode='P0002'; end if;

  v_ref := 'IP-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(p_payroll_run_id::text, '-', ''), 1, 8));

  insert into public.payroll_instapay_batches(
    payroll_run_id, batch_reference, total_amount, item_count, status, created_by)
  values (p_payroll_run_id, v_ref, v_total, v_count, 'generated', auth.uid())
  returning * into v_batch;

  insert into public.payroll_instapay_items(batch_id, employee_id, payslip_id, mobile_e164, amount)
  select v_batch.id, pl.employee_id, pl.id, e.phone_e164, pl.net_amount
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  perform public.log_audit_event(
    'instapay.batch_generated', 'financial', 'info',
    'payroll_instapay_batches', v_batch.id, 'توليد دفعة InstaPay لصرف الرواتب', null,
    jsonb_build_object('payrollRunId', p_payroll_run_id, 'reference', v_ref, 'items', v_count, 'total', v_total));

  return jsonb_build_object(
    'id', v_batch.id, 'reference', v_batch.batch_reference,
    'totalAmount', v_batch.total_amount, 'itemCount', v_batch.item_count,
    'status', v_batch.status);
end $function$;



create or replace function public.generate_kpi_cycle_notifications(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_eval record; v_recipient uuid; v_day integer:=(p_at at time zone 'Africa/Cairo')::date-(date_trunc('month',p_at at time zone 'Africa/Cairo'))::date+1; v_count integer:=0; v_event text; v_title text; v_body text;
begin
 for v_cycle in select * from public.kpi_cycles where status in ('open','locked') and period_month=date_trunc('month',p_at at time zone 'Africa/Cairo')::date loop
  if v_day>=20 then
   for v_eval in select e.id,e.employee_id,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id loop
    if public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_EMPLOYEE',v_eval.employee_id,'بدأت دورة تقييم الأداء','أكمل تقييمك الذاتي للبنود السبعة قبل نهاية الدورة.','normal') is not null then v_count:=v_count+1; end if;
    if v_eval.manager_id is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,'OPENED_MANAGER',v_eval.manager_id,'بدأت دورة تقييم فريقك','ستصلك تقييمات أعضاء فريقك للمراجعة ثم الاعتماد النهائي.','normal') is not null then v_count:=v_count+1; end if;
   end loop;
  end if;
  if p_at>public.kpi_effective_deadline(v_cycle) then v_event:='OVERDUE';v_title:='تقييمات أداء متأخرة';v_body:='انتهى الموعد وما زالت تقييمات غير مكتملة.';
  elsif v_day>=25 then v_event:='REMINDER_25';v_title:='اليوم آخر موعد لتقييم الأداء';v_body:='أكمل الإجراء المطلوب قبل إغلاق الدورة.';
  elsif v_day>=24 then v_event:='REMINDER_24';v_title:='غدًا آخر موعد لتقييم الأداء';v_body:='يوجد تقييم لم يكتمل بعد.';
  elsif v_day>=22 then v_event:='REMINDER_22';v_title:='تذكير بتقييم الأداء';v_body:='أكمل المرحلة المسندة إليك قبل الموعد.';
  else continue; end if;
  if v_event='OVERDUE' then
   for v_recipient in select distinct p.employee_id from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.user_id where r.slug='executive-secretary' and p.employee_id is not null and ur.effective_from<=p_at and (ur.effective_to is null or ur.effective_to>p_at) loop
    if public.enqueue_kpi_notification(v_cycle.id,null,v_event,v_recipient,v_title,v_body,'urgent') is not null then v_count:=v_count+1; end if;
   end loop;
  else
   for v_eval in select e.id,e.employee_id,e.current_stage,(select mr.manager_employee_id from public.manager_relations mr where mr.employee_id=e.employee_id and mr.relation_type='primary' and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date) limit 1) manager_id from public.kpi_evaluations e where e.cycle_id=v_cycle.id and e.current_stage not in ('finalized','closed','archived') loop
    if v_eval.current_stage='hr_review' then
     for v_recipient in select distinct p.employee_id from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.user_id where r.slug in ('hr-manager','hr-specialist') and p.employee_id is not null and ur.effective_from<=p_at and (ur.effective_to is null or ur.effective_to>p_at) loop
      if public.enqueue_kpi_notification(v_cycle.id,v_eval.id,v_event,v_recipient,v_title,v_body,case when v_event='REMINDER_25' then 'urgent' else 'high' end) is not null then v_count:=v_count+1; end if;
     end loop;
    else
     v_recipient:=case when v_eval.current_stage='self' then v_eval.employee_id when v_eval.current_stage in ('manager_review','manager_final') then v_eval.manager_id else null end;
     if v_recipient is not null and public.enqueue_kpi_notification(v_cycle.id,v_eval.id,v_event,v_recipient,v_title,v_body,case when v_event='REMINDER_25' then 'urgent' else 'high' end) is not null then v_count:=v_count+1; end if;
    end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $$;



CREATE OR REPLACE FUNCTION public.generate_punch_reminders(p_lead_minutes integer DEFAULT 15)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- 0461: قفل استشاري يمنع تشغيلَين متزامنين للوظيفة — سباق الفحص-ثم-الإدراج
  -- بين تشغيلين متقاربين كان يكرر تنبيهات «نسيت البصمة» بنفس اللحظة.
  perform pg_advisory_xact_lock(hashtext('generate_punch_reminders'));  -- مسموح فقط لعملية خادمية (service_role) أو مالك صلاحية إرسال الإشعارات.
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة فقط عطلة (يوم العمل: السبت=6 والأحد=7 والإثنين..الخميس=1..4).
  if v_dow = 5 then
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
      v_body := 'اقترب وقت الحضور (' || (to_char(v_shift.start_time, 'hh12:mi') || case when extract(hour from v_shift.start_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل البصمة.';
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
      v_body := 'اقترب وقت الانصراف (' || (to_char(v_shift.end_time, 'hh12:mi') || case when extract(hour from v_shift.end_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل بصمة الانصراف.';
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
$function$;



CREATE OR REPLACE FUNCTION public.generate_weekly_executive_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_end        date      := (v_local::date) - 1;   -- أمس
  v_start      date      := v_end - 6;            -- آخر 7 أيام شاملة
  v_period_id  text      := to_char(v_start, 'YYYY-MM-DD') || '_' || to_char(v_end, 'YYYY-MM-DD');
  v_total_emp  integer;
  v_summary    jsonb;
  v_top_late   jsonb;
  v_absent_gt3 jsonb;
  v_body       text;
  v_notif_id   uuid;
  v_recipients bigint;
  v_sent       integer := 0;
  v_result     jsonb;
begin
  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('reports.attendance.read')) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  -- إجمالي الموظفين النشطين (قاعدة المقام للنسب).
  select count(*) into v_total_emp
  from public.employees e
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active';

  -- الملخص: إجمالي سجلات/أيام + عدد لكل حالة.
  select jsonb_build_object(
    'startDate',     v_start,
    'endDate',       v_end,
    'periodId',      v_period_id,
    'activeEmployees', v_total_emp,
    'totalDayRecords', count(*),
    'present',       count(*) filter (where ad.status = 'present'),
    'late',           count(*) filter (where ad.status = 'late'),
    'absent',         count(*) filter (where ad.status = 'absent'),
    'onLeave',        count(*) filter (where ad.status = 'on_leave'),
    'holiday',        count(*) filter (where ad.status = 'holiday'),
    'weekend',        count(*) filter (where ad.status = 'weekend'),
    'partial',        count(*) filter (where ad.status = 'partial'),
    'totalLateMinutes',  coalesce(sum(ad.late_minutes), 0),
    'totalEarlyLeaveMinutes', coalesce(sum(ad.early_leave_minutes), 0),
    'totalOvertimeMinutes',  coalesce(sum(ad.overtime_minutes), 0)
  ) into v_summary
  from public.attendance_daily ad
  join public.employees e on e.id = ad.employee_id
  where ad.work_date between v_start and v_end
    and e.is_active = true
    and e.is_deleted = false;

  -- نسب معدّلة على عدد أيام العمل الفعلية (present+late+absent+partial)
  v_summary := v_summary || jsonb_build_object(
    'workdayRecords',
      coalesce((v_summary->>'present')::int,0)
      + coalesce((v_summary->>'late')::int,0)
      + coalesce((v_summary->>'absent')::int,0)
      + coalesce((v_summary->>'partial')::int,0),
    'presentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'present')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'lateRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'late')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'absentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'absent')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'onLeaveRate',
      case when coalesce(v_total_emp,0) * 7 = 0 then 0
           else round(100.0 * coalesce((v_summary->>'onLeave')::int,0)
             / (coalesce(v_total_emp,0) * 7), 2) end
  );

  -- أعلى 5 موظفين تكراراً في التأخير.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'lateDays',     t.late_days,
    'totalLateMinutes', t.total_late_minutes
  ) order by t.late_days desc, t.total_late_minutes desc), '[]'::jsonb) into v_top_late
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'late') as late_days,
      coalesce(sum(ad.late_minutes) filter (where ad.status = 'late'), 0) as total_late_minutes
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'late') > 0
    order by late_days desc, total_late_minutes desc
    limit 5
  ) t;

  -- موظفون تجاوزوا 3 أيام غياب في الأسبوع.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'absentDays',   t.absent_days
  ) order by t.absent_days desc, t.full_name_ar), '[]'::jsonb) into v_absent_gt3
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'absent') as absent_days
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'absent') > 3
    order by absent_days desc, full_name_ar
  ) t;

  -- النتيجة النهائية.
  v_result := jsonb_build_object(
    'generatedAt', now(),
    'summary',     v_summary,
    'topLateEmployees',     v_top_late,
    'absentGt3Employees',   v_absent_gt3
  );

  -- صياغة جسم الإشعار (عربي، مختصر).
  v_body := 'الملخص الأسبوعي للحضور (' || to_char(v_start, 'DD/MM/YYYY') || ' - '
             || to_char(v_end, 'DD/MM/YYYY') || '): '
             || 'حضور ' || coalesce((v_summary->>'present')::text,'0')
             || '، تأخر ' || coalesce((v_summary->>'late')::text,'0')
             || '، غياب ' || coalesce((v_summary->>'absent')::text,'0')
             || '، إجازة ' || coalesce((v_summary->>'onLeave')::text,'0')
             || '. نسبة التأخر ' || coalesce((v_summary->>'lateRate')::text,'0') || '%'
             || '، نسبة الغياب ' || coalesce((v_summary->>'absentRate')::text,'0') || '%.'
             || ' أعلى المتأخرين: ' || coalesce(
                (select string_agg(x->>'employeeName', '، ')
                 from jsonb_array_elements(v_top_late) as x),
                'لا يوجد')
             || '.';

  -- إدراج إشعار لكل مستخدم يملك reports.attendance.read أو دور full-access.
  -- نُحدّد المستخدمين عبر user_roles المرتبطة بـ role_permissions/permissions
  -- أو بـ roles.is_full_access=true. ونحلّ employee_id عبر profiles.
  with recipients as (
    -- full-access
    select distinct ur.user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where r.is_full_access = true
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
    union
    -- مالكو reports.attendance.read
    select distinct ur.user_id
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p        on p.id = rp.permission_id
    where p.code = 'reports.attendance.read'
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
  ),
  enriched as (
    select
      r.user_id,
      p.employee_id
    from recipients r
    left join public.profiles p on p.id = r.user_id
  )
  insert into public.notifications (
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    action_url,
    entity_type,
    entity_id,
    metadata
  )
  select
    e.user_id,
    e.employee_id,
    'الملخص الأسبوعي للحضور',
    v_body,
    'system',
    'normal',
    '/reports/attendance',
    'weekly_executive_summary',
    null,
    jsonb_build_object(
      'periodId', v_period_id,
      'startDate', v_start,
      'endDate',   v_end,
      'summary',   v_summary,
      'topLateEmployees',   v_top_late,
      'absentGt3Employees', v_absent_gt3,
      'kind', 'weekly_executive_summary',
      'deepLink', 'ahlashabab://action/reports/attendance?start='
        || to_char(v_start,'YYYY-MM-DD') || '&end=' || to_char(v_end,'YYYY-MM-DD')
    )
  from enriched e
  where not exists (
    -- منع التكرار: إشعار سابق لنفس (المستخدم/الفترة)
    select 1
    from public.notifications n
    where n.recipient_user_id = e.user_id
      and n.entity_type = 'weekly_executive_summary'
      and (n.metadata->>'periodId') = v_period_id
  );

  get diagnostics v_recipients = row_count;
  v_sent := v_recipients::integer;

  perform public.log_audit_event(
    'reports.weekly_executive_summary_generated', 'operations', 'info',
    'attendance_daily', null, 'توليد الملخص التنفيذي الأسبوعي للحضور', null,
    jsonb_build_object(
      'periodId', v_period_id,
      'recipientsNotified', v_sent,
      'summary', v_summary
    )
  );

  return v_result || jsonb_build_object(
    'recipientsNotified', v_sent,
    'notificationBody', v_body
  );
exception
  when others then
    perform public.log_audit_event(
      'reports.weekly_executive_summary_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل توليد الملخص التنفيذي الأسبوعي', null,
      jsonb_build_object('error', sqlerrm, 'periodId', v_period_id)
    );
    return jsonb_build_object('error', sqlerrm, 'periodId', v_period_id);
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_access_admin_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.role.update','access.role.assign'])) then
    raise exception 'وصول كتالوج الصلاحيات مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', case
          -- ── أدوار الوصول الكامل: إرجاع كل الصلاحيات ──
          when r.is_full_access then
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', 'organization',
                'requiresMfa', false,
                'requiresReason', false
              ) order by p.module, p.code)
              from public.permissions p
            ), '[]'::jsonb)
          -- ── أدوار عادية: فقط ما في role_permissions ──
          else
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
                'requiresReason', rp.requires_reason
              ) order by p.module, p.code)
              from public.role_permissions rp
              join public.permissions p on p.id = rp.permission_id
              where rp.role_id = r.id
            ), '[]'::jsonb)
        end,
        'assignments', (
          select count(*)
          from public.user_roles ur
          where ur.role_id = r.id
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action, 'name', coalesce(p.description, p.code), 'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'allowedScopes', array[
          'self','direct_reports','management_descendants','selected_employees',
          'team','department','selected_departments','branch','selected_branches',
          'organization','assigned_cases','workflow_inbox',
          'records_created_by_user','archive_readonly'
        ]
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr
      left join public.employees e on e.id = pr.employee_id
      -- ── إخفاء المؤرشفين/المحذوفين ناعماً (مع إبقاء الملفات اليتيمة) ──
      where e.id is null
         or (e.is_active = true and e.is_deleted = false)
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_access_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.audit.read'])) then
    raise exception 'وصول النظرة العامة مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'roles', (select count(*) from public.roles),
    'permissions', (select count(*) from public.permissions),
    'activeAssignments', (select count(*) from public.user_roles where effective_from <= now() and (effective_to is null or effective_to > now())),
    'sensitivePermissions', (select count(*) from public.permissions where is_sensitive = true or risk_level in ('sensitive','critical')),
    'expiringAssignments', (select count(*) from public.user_roles where effective_to between now() and now() + interval '30 days'),
    'rolesList', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'isFullAccess', r.is_full_access,
        'permissionCount', (select count(*) from public.role_permissions rp where rp.role_id = r.id),
        'userCount', (select count(*) from public.user_roles ur where ur.role_id = r.id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now()))
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_admin_org_chart()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  WITH RECURSIVE
  -- جميع الموظفين غير المحذوفين وغير المنتهين (بما فيهم الموقوفون والمدعوون وفترة الإخطار)
  emp_base AS (
    SELECT
      e.id,
      e.full_name_ar,
      e.full_name_en,
      e.photo_url,
      coalesce(jt.name, jt.name_en, '') AS job_title,
      coalesce(d.name, '') AS department_name,
      e.employee_code,
      e.department_id,
      e.status,
      e.is_active,
      e.is_deleted
    FROM public.employees e
    LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
    LEFT JOIN public.departments d ON d.id = e.department_id
    WHERE e.is_deleted = false
      AND e.status NOT IN ('terminated', 'draft')
  ),
  -- العلاقات النشطة فقط (مدير رئيسي نشط)
  active_primary_managers AS (
    SELECT
      mr.employee_id,
      mr.manager_employee_id
    FROM public.manager_relations mr
    WHERE mr.relation_type = 'primary'
      AND mr.effective_to IS NULL
      AND mr.employee_id IN (SELECT id FROM emp_base)
      AND mr.manager_employee_id IN (SELECT id FROM emp_base)
  ),
  -- الشجرة الهرمية المتكررة بدءًا من الجذور (موظفون بلا مدير رئيسي)
  org_tree AS (
    -- الجذور: موظفون ليس لديهم مدير رئيسي نشط
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      NULL::uuid AS manager_employee_id,
      0 AS depth,
      ARRAY[eb.id]::uuid[] AS path
    FROM emp_base eb
    LEFT JOIN active_primary_managers apm ON apm.employee_id = eb.id
    WHERE apm.employee_id IS NULL

    UNION ALL

    -- الأبناء: موظفون مديرهم موجود بالفعل في الشجرة
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      apm.manager_employee_id,
      ot.depth + 1,
      ot.path || eb.id
    FROM emp_base eb
    JOIN active_primary_managers apm ON apm.employee_id = eb.id
    JOIN org_tree ot ON ot.id = apm.manager_employee_id
    WHERE NOT eb.id = ANY(ot.path)
  ),
  -- عدّ المرؤوسين المباشرين لكل موظف
  direct_counts AS (
    SELECT
      manager_employee_id AS emp_id,
      COUNT(*) AS direct_reports_count
    FROM active_primary_managers
    GROUP BY manager_employee_id
  )
  SELECT jsonb_build_object(
    'employees', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'fullNameAr', t.full_name_ar,
        'fullNameEn', t.full_name_en,
        'photoUrl', t.photo_url,
        'jobTitle', t.job_title,
        'departmentName', t.department_name,
        'employeeCode', t.employee_code,
        'departmentId', t.department_id,
        'status', t.status,
        'isActive', t.is_active,
        'managerEmployeeId', t.manager_employee_id,
        'directReportsCount', coalesce(dc.direct_reports_count, 0),
        'depth', t.depth,
        'path', t.path
      ) ORDER BY t.path, t.full_name_ar)
      FROM org_tree t
      LEFT JOIN direct_counts dc ON dc.emp_id = t.id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;



create or replace function public.get_analytics_dashboard(
  p_months_back integer default 6
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  v_from_month   date;
  v_today        date;
  v_week_start   date;
  v_requests     jsonb;
  v_departments  jsonb;
  v_attendance   jsonb;
  v_kpi          jsonb;
begin
  if auth.uid() is null then
    raise exception 'ERR_UNAUTHENTICATED' using errcode = '28000';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.people.read')
    or public.has_permission('reports.hr.read')
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  v_today      := (now() at time zone 'Africa/Cairo')::date;
  v_from_month := date_trunc('month', v_today - (p_months_back || ' months')::interval)::date;
  v_week_start := v_today - extract(dow from v_today)::integer;

  -- ── 1. حركة الطلبات الشهرية ──────────────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'month',        to_char(s.month, 'Mon YYYY'),
        'monthKey',     to_char(s.month, 'YYYY-MM'),
        'approved',     s.approved,
        'rejected',     s.rejected,
        'pending',      s.pending,
        'cancelled',    s.cancelled
      )
      order by s.month
    ),
    '[]'::jsonb
  )
  into v_requests
  from (
    select
      date_trunc('month', month)::date as month,
      sum(approved)   as approved,
      sum(rejected)   as rejected,
      sum(pending)    as pending,
      sum(cancelled)  as cancelled
    from public.mv_monthly_request_stats
    where month >= v_from_month
    group by date_trunc('month', month)
  ) s;

  -- ── 2. توزيع الموظفين حسب الأقسام ───────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',  h.department_name,
        'value', h.active_count
      )
      order by h.active_count desc
    ),
    '[]'::jsonb
  )
  into v_departments
  from public.mv_department_headcount h
  where h.active_count > 0;

  -- ── 3. اتجاه الحضور (7 أيام الماضية) ────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',    to_char(day_date, 'Dy'),
        'date',    day_date,
        'present', coalesce(present_count, 0),
        'late',    coalesce(late_count,    0),
        'absent',  coalesce(absent_count,  0)
      )
      order by day_date
    ),
    '[]'::jsonb
  )
  into v_attendance
  from (
    select
      d.day_date,
      count(*) filter (
        where ad.status in ('present', 'present_late')
          and ad.status not in ('weekend', 'holiday')
      ) as present_count,
      count(*) filter (
        where ad.status = 'present_late'
          and ad.status not in ('weekend', 'holiday')
      ) as late_count,
      count(*) filter (
        where ad.status in ('absent', 'absent_excused')
          and ad.status not in ('weekend', 'holiday')
      ) as absent_count
    from generate_series(v_week_start, v_today, '1 day'::interval) as d(day_date)
    left join public.attendance_daily ad on ad.work_date = d.day_date::date
    where extract(isodow from d.day_date) not in (5, 6)   -- الجمعة والسبت راحة
    group by d.day_date
  ) w;

  -- ── 4. متوسطات KPI (آخر 6 دورات منتهية) ─────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subject',    k.criterion_name,
        'actual',     round(k.avg_score::numeric, 1),
        'target',     k.max_score
      )
      order by k.criterion_name
    ),
    '[]'::jsonb
  )
  into v_kpi
  from (
    select
      kc.name_ar                                    as criterion_name,
      avg(ks.score / nullif(kc.max_score, 0) * 100) as avg_score,
      100                                           as max_score
    from public.kpi_cycles c
    join public.kpi_evaluations ke  on ke.cycle_id = c.id
    join public.kpi_scores ks       on ks.evaluation_id = ke.id
    join public.kpi_criteria kc     on kc.id = ks.criterion_id
    where c.status in ('closed', 'locked')
      and c.period_month >= (v_today - '6 months'::interval)::date
      and ke.final_score is not null
      and ks.reviewer_stage in ('executive', 'manager')
    group by kc.name_ar
    having count(*) >= 3
  ) k;

  return jsonb_build_object(
    'monthlyRequests',       coalesce(v_requests,    '[]'::jsonb),
    'departmentDistribution',coalesce(v_departments, '[]'::jsonb),
    'attendanceTrend',       coalesce(v_attendance,  '[]'::jsonb),
    'kpiScores',             coalesce(v_kpi,         '[]'::jsonb),
    'generatedAt',           now() at time zone 'Africa/Cairo'
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.get_announcement_acknowledgers(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_ann_exists boolean;
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- لا نكشف قائمة المُقرّين إلا لإعلان موجود فعلاً
  select exists(
    select 1 from public.announcements a
    where a.id = p_announcement_id and a.status = 'published'
  ) into v_ann_exists;

  if not v_ann_exists then
    raise exception 'announcement not available' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'employeeId',    e.id,
      'employeeCode',  e.employee_code,
      'fullName',      e.full_name_ar,
      'photoUrl',      e.photo_url,
      'acknowledgedAt',ack.acknowledged_at
    )
    order by ack.acknowledged_at asc
  ), '[]'::jsonb)
  into v_result
  from public.announcement_acknowledgements ack
  join public.employees e on e.id = ack.employee_id
  where ack.announcement_id = p_announcement_id
    and (public.current_is_full_access()
         or public.can_access_employee(e.id, 'people.employee.read'));

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_announcement_engagement(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if not exists (select 1 from public.announcements where id = p_announcement_id) then
    raise exception 'الإعلان غير موجود' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'announcementId', p_announcement_id,
    'targetCount', (
      select count(*)::integer
      from public.employees e
      join public.profiles p on p.employee_id = e.id and p.status = 'active'
      where e.is_active and e.status = 'active' and not e.is_deleted
    ),
    'viewerCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'acknowledgedCount', (select count(*)::integer from public.announcement_acknowledgements a where a.announcement_id = p_announcement_id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.announcement_views v
      join public.employees e on e.id = v.employee_id
      where v.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'reactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', r.updated_at,
        'reactionType', r.reaction_type
      ) order by r.updated_at desc)
      from public.announcement_reactions r
      join public.employees e on e.id = r.employee_id
      where r.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'acknowledgements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', a.created_at
      ) order by a.created_at desc)
      from public.announcement_acknowledgements a
      join public.employees e on e.id = a.employee_id
      where a.announcement_id = p_announcement_id
    ), '[]'::jsonb)
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_attendance_dashboard(p_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_executive(e.id)  -- 0444: ╪º╪│╪¬╪¿╪╣╪º╪» ╪º┘ä┘à╪»┘è╪▒ ╪º┘ä╪¬┘å┘ü┘è╪░┘è
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (
         p_manager_id is null or exists (
           select 1
             from public.manager_relations mr
            where mr.employee_id = e.id
              and mr.manager_employee_id = p_manager_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
         )
       )
  ), daily as (
    select d.*
      from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
      join params p on p.work_date between lr.start_date and lr.end_date
      join visible_employees ve on ve.id = lr.employee_id
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
      join params prm on prm.work_date between wa.start_at::date and wa.end_at::date
     where wa.status in ('APPROVED','IN_PROGRESS')
  ), derived as (
    select
      ve.id as employee_id,
      d.id as daily_id,
      d.status as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      d.is_finalized,
      (al.employee_id is not null) as has_approved_leave,
      (am.employee_id is not null) as has_mission,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when public.is_official_holiday((select work_date from params), ve.id) then 'holiday'
        when extract(isodow from (select work_date from params)) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
  ), excused_absent as (
    select dv.employee_id
      from derived dv
      join visible_events e on e.employee_id = dv.employee_id
     where dv.derived_status = 'absent'
     group by dv.employee_id
    having count(e.id) > 0
  ), location_requests_day as (
    select llr.employee_id, llr.status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
      join visible_employees ve on ve.id = llr.employee_id
  )
  select jsonb_build_object(
    'scheduled',
      case when extract(isodow from (select work_date from params)) = 5
           then (select count(distinct employee_id) from daily)
           else (select count(*) from visible_employees)
      end,
    'present', (select count(*) from derived where derived_status in ('present','late','partial','missing_checkout')),
    'late', (select count(*) from derived where derived_status = 'late' or late_minutes > 0),
    'absent', (select count(*) from derived where derived_status = 'absent'),
    'unexcusedAbsent', (select count(*) from derived where derived_status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'onLeave', (select count(*) from derived where derived_status = 'on_leave'),
    'onMission', (select count(*) from derived where derived_status = 'on_mission'),
    'missingCheckout', (select count(*) from derived where derived_status = 'missing_checkout'),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    -- ┘à┘ü╪º╪¬┘è╪¡ 0444 ╪¬╪¿┘é┘ë ┘ä┘ä╪¬┘ê╪º┘ü┘é ┘à╪╣ ╪º┘ä┘ê╪º╪¼┘ç╪⌐ ╪º┘ä╪ú╪¡╪»╪½:
    'locationRequestsResponded', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'date', (select work_date from params),
    'lastUpdatedAt', now()
  );
$function$;



CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(p_date date DEFAULT NULL::date, p_category text DEFAULT 'scheduled'::text, p_search text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid, p_sort text DEFAULT 'name'::text, p_direction text DEFAULT 'asc'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_search    text := nullif(trim(coalesce(p_search, '')), '');
  v_limit     int  := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset    int  := greatest(0, coalesce(p_offset, 0));
  v_result    jsonb;
begin
  if p_category not in (
    'scheduled','present','late','absent','unexcused_absent',
    'incomplete','pending_review','location_requests','location_responded',
    'on_leave','on_mission','missing_checkout'
  ) then
    raise exception 'invalid attendance roster category: %', p_category
      using errcode = '22023';
  end if;
  if p_limit is not null and p_limit <= 0 then
    raise exception 'invalid roster limit: %', p_limit using errcode = '22023';
  end if;
  if p_offset is not null and p_offset < 0 then
    raise exception 'invalid roster offset: %', p_offset using errcode = '22023';
  end if;
  if p_sort not in ('name','check_in','late','status') then
    raise exception 'invalid roster sort: %', p_sort using errcode = '22023';
  end if;
  if p_direction not in ('asc','desc') then
    raise exception 'invalid roster direction: %', p_direction using errcode = '22023';
  end if;

  with visible_employees as (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
             e.department_id, e.branch_id,
             d.name as department_name,
             b.name as branch_name,
             jt.name as job_title,
             mr.manager_employee_id,
             me.full_name_ar as manager_name
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select mr.manager_employee_id
          from public.manager_relations mr
         where mr.employee_id = e.id
           and mr.relation_type = 'primary'
           and mr.effective_to is null
         order by mr.effective_from desc
         limit 1
      ) mr on true
      left join public.employees me on me.id = mr.manager_employee_id
     where e.is_active = true and coalesce(e.is_deleted, false) = false
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (p_manager_id is null or mr.manager_employee_id = p_manager_id)
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       and (v_search is null
         or lower(e.full_name_ar) like '%' || v_search || '%'
         or lower(e.employee_code) like '%' || v_search || '%')
  ), daily as (
    select d.* from public.attendance_daily d where d.work_date = v_work_date
  ), events_day as (
    select e.* from public.attendance_events e
     where (e.event_at at time zone 'Africa/Cairo')::date = v_work_date
  ), approved_leaves as (
    select distinct on (lr.employee_id)
           lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
     order by lr.employee_id, lr.start_date desc
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
     where wa.status in ('APPROVED','IN_PROGRESS')
       and v_work_date between wa.start_at::date and wa.end_at::date
  ), excused_absent as (
    select dv.employee_id
      from (
        select ve.id as employee_id,
               d.status as daily_status,
               (al.employee_id is not null) as has_approved_leave,
               (am.employee_id is not null) as has_mission
          from visible_employees ve
          left join daily d on d.employee_id = ve.id
          left join approved_leaves al on al.employee_id = ve.id
          left join active_missions am on am.employee_id = ve.id
      ) dv
      left join approved_leaves al on al.employee_id = dv.employee_id
      left join events_day e on e.employee_id = dv.employee_id
     where dv.daily_status = 'absent'
     group by dv.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
      or count(e.id) > 0
  ), location_requests_day as (
    select distinct on (llr.employee_id)
           llr.employee_id, llr.status as llr_status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
     where (llr.requested_at at time zone 'Africa/Cairo')::date = v_work_date
        or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = v_work_date)
     order by llr.employee_id, llr.requested_at desc
  ), review_reasons as (
    select distinct on (e.employee_id) e.employee_id,
           case
             when e.verification_status = 'failed' then '┘ü╪┤┘ä ╪º┘ä╪¬╪¡┘é┘é ┘à┘å ╪º┘ä┘ç┘ê┘è╪⌐'
             when e.latitude is null or e.longitude is null then '┘ä╪º ┘è┘ê╪¼╪» ┘à┘ê┘é╪╣ ┘à╪ñ┘â╪»'
             when e.accuracy_meters is not null and e.accuracy_meters > 100 then '╪»┘é╪⌐ GPS ┘à┘å╪«┘ü╪╢╪⌐'
             when e.distance_meters is not null and e.distance_meters > 0 then '╪«╪º╪▒╪¼ ╪º┘ä┘å╪╖╪º┘é ╪º┘ä┘à╪╣╪¬┘à╪»'
             when e.status = 'flagged' then '╪ú┘Å╪┤╪╣┘É╪▒ ╪¬┘ä┘é╪º╪ª┘è┘ï╪º ┘ä┘ä┘à╪▒╪º╪¼╪╣╪⌐'
             else '┘è╪¡╪¬╪º╪¼ ┘à╪▒╪º╪¼╪╣╪⌐ ╪¿╪┤╪▒┘è╪⌐'
           end as reason
      from events_day e
     where e.requires_review = true
     order by e.employee_id, e.created_at desc
  ), base as (
    select
      ve.id            as employee_id,
      ve.employee_code,
      ve.full_name_ar,
      ve.photo_url,
      ve.department_id,
      ve.department_name,
      ve.branch_id,
      ve.branch_name,
      ve.job_title,
      ve.manager_employee_id,
      ve.manager_name,
      d.id             as daily_id,
      d.status         as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce(d.is_finalized, false) as is_finalized,
      s.name           as shift_name,
      s.start_time     as shift_start,
      s.end_time       as shift_end,
      coalesce((select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id), false) as requires_review,
      rr.reason        as review_reason,
      (al.employee_id is not null) as has_approved_leave,
      al.leave_code,
      al.is_paid       as leave_is_paid,
      (am.employee_id is not null) as has_mission,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.shifts s on s.id = d.shift_id
    left join review_reasons rr on rr.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  ), categorized as (
    select b.*,
           case p_sort
             when 'check_in' then coalesce(to_char(b.first_check_in, 'YYYY-MM-DD HH24:MI:SS'), '9999-99-99 99:99:99')
             when 'late'     then lpad(coalesce(b.late_minutes::text, '0'), 12, '0')
             when 'status'   then coalesce(b.derived_status, '')
             else coalesce(b.full_name_ar, '')
           end as sort_key
      from base b
     where case p_category
        when 'scheduled'          then true
        when 'present'            then b.derived_status in ('present','late','partial','missing_checkout')
        when 'late'               then b.derived_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.derived_status = 'absent'
        when 'unexcused_absent'   then b.derived_status = 'absent'
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then b.derived_status = 'on_leave'
        when 'on_mission'         then b.derived_status = 'on_mission'
        when 'missing_checkout'   then b.derived_status = 'missing_checkout'
        when 'pending_review'     then b.requires_review = true
        when 'location_requests'  then b.location_requested_at is not null
                                    or b.location_responded_at is not null
        when 'location_responded' then b.location_responded_today = true
        else false
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(item)
        from (
          select jsonb_build_object(
            'employeeId', c.employee_id,
            'employeeCode', c.employee_code,
            'employeeName', c.full_name_ar,
            'photoUrl', c.photo_url,
            'departmentId', c.department_id,
            'departmentName', c.department_name,
            'branchId', c.branch_id,
            'branchName', c.branch_name,
            'jobTitle', c.job_title,
            'managerId', c.manager_employee_id,
            'managerName', c.manager_name,
            'status', c.derived_status,
            'lateMinutes', c.late_minutes,
            'firstCheckIn', c.first_check_in,
            'lastCheckOut', c.last_check_out,
            'shiftName', c.shift_name,
            'shiftStartAt', c.shift_start,
            'shiftEndAt', c.shift_end,
            'requiresReview', c.requires_review,
            'reviewReason', c.review_reason,
            'hasApprovedLeave', c.has_approved_leave,
            'leaveCode', c.leave_code,
            'leaveIsPaid', c.leave_is_paid,
            'hasMission', c.has_mission,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at
          ) as item
          from categorized c
          order by
            case when p_direction = 'desc' then c.sort_key end desc,
            case when p_direction = 'asc'  then c.sort_key end asc,
            c.full_name_ar asc
          limit v_limit offset v_offset
        ) t
    ), '[]'::jsonb),
    'total', (select count(*) from categorized),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_attendance_today_overview(p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
  v_is_friday boolean := (extract(isodow from p_date) = 5);
begin
  if not (public.current_is_full_access()
          or public.has_permission('attendance.record.read')
          or public.has_permission('people.employee.read')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- إجمالي الموظفين النشطين (بدون التنفيذيين)
  select count(*) into v_total_active
  from public.employees e
  where e.status = 'active'
    and not exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and r.slug in ('executive','executive-director')
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    );

  -- الموظفون في إجازة معتمدة
  select count(distinct lr.employee_id) into v_on_leave
  from public.leave_requests lr
  join public.requests req on req.id = lr.request_id
  where req.status = 'approved'
    and p_date between lr.start_date and lr.end_date;

  -- الموظفون في تكليفات نشطة
  select count(distinct wa.responsible_employee_id) into v_on_assignment
  from public.work_assignments wa
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date;

  -- الحاضرون (سجّلوا حضور اليوم)
  select count(distinct employee_id) into v_present
  from public.attendance_events
  where event_at::date = p_date and event_type = 'CHECK_IN';

  -- المتأخرون
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_at::date = p_date
    and ae.event_type = 'CHECK_IN'
    and ae.late_minutes > 0;

  -- يوم الجمعة: المتوقع = من على مأمورية فقط (لا كل الموظفين)
  if v_is_friday then
    v_expected := v_on_assignment;
  else
    v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);
  end if;

  v_not_checked_in := greatest(0, v_expected - v_present);
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', v_total_active,
    'expected', v_expected,
    'present', v_present,
    'late', v_late,
    'notCheckedIn', v_not_checked_in,
    'onLeave', v_on_leave,
    'onAssignment', v_on_assignment,
    'absent', v_absent,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now()
  );
end;
$function$;



create or replace function public.get_committee_dispute_portal()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_emp uuid := public.current_employee_id();
begin
  -- Same access gate as get_dispute_operations_catalog
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all')
    or exists(select 1 from public.committee_members where employee_id = v_emp and is_active)
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'cases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'caseNumber', c.case_number,
        'title', c.title,
        'description', c.description,
        'caseType', c.case_type,
        'status', c.status,
        'severity', c.severity,
        'actorName', a.full_name_ar,
        'actorDepartment', ad.name,
        'respondentName', r.full_name_ar,
        'assignedName', ass.full_name_ar,
        'openedAt', c.opened_at,
        'updatedAt', c.updated_at,
        'overdue', (c.status in ('submitted','needs_more_information') and c.review_due_at < now()),
        'proposedAdminAction', c.proposed_administrative_action,
        'proposedActionDetail', c.proposed_action_detail,
        'proposedAt', c.proposed_at,
        'proposedByName', pb.full_name_ar,
        'executiveDecision', c.executive_decision,
        'executiveDecisionReason', c.executive_decision_reason,
        'executiveDecisionAt', c.executive_decision_at,
        'approvedAdminAction', c.approved_administrative_action,
        'approvedActionDetail', c.approved_action_detail,
        'executedAt', c.executed_at,
        'executedByName', exb.full_name_ar,
        'executionNotes', c.execution_notes,
        'partyCount', (select count(*) from public.dispute_parties dp where dp.case_id = c.id),
        'sessionCount', (select count(*) from public.dispute_sessions s where s.case_id = c.id),
        'hasDecision', exists(select 1 from public.dispute_decisions d where d.case_id = c.id)
      ) order by
        case
          when c.status in ('submitted','needs_more_information') then 0
          when c.status = 'action_proposed' then 1
          when c.status = 'pending_execution' then 2
          -- 0202: تصحيح hearing_scheduled → session_scheduled
          when c.status in ('under_review','waiting_for_respondent','waiting_for_witness','session_scheduled') then 3
          else 4
        end,
        c.review_due_at nulls last,
        c.opened_at desc
      )
      from public.dispute_cases c
      left join public.employees a   on a.id  = c.actor_employee_id
      left join public.departments ad on ad.id = a.department_id
      left join public.employees r   on r.id  = c.respondent_employee_id
      left join public.employees ass on ass.id = c.assigned_to
      left join public.employees pb  on pb.id  = c.proposed_by
      left join public.employees exb on exb.id = c.executed_by
      where public.can_access_dispute(c.id)
    ), '[]'::jsonb),
    'summary', (
      select jsonb_build_object(
        'total', count(*),
        'new', count(*) filter (where status = 'submitted'),
        -- 0202: تصحيح hearing_scheduled → session_scheduled
        'underReview', count(*) filter (where status in ('under_review','waiting_for_respondent','waiting_for_witness','session_scheduled')),
        'actionProposed', count(*) filter (where status = 'action_proposed'),
        'pendingExecution', count(*) filter (where status = 'pending_execution'),
        'executed', count(*) filter (where status = 'executed'),
        'resolvedFriendly', count(*) filter (where status = 'resolved_friendly'),
        'closed', count(*) filter (where status = 'closed'),
        'overdue', count(*) filter (where status in ('submitted','needs_more_information') and review_due_at < now()),
        'urgent', count(*) filter (where severity in ('urgent','critical') and status not in ('closed','rejected','cancelled_by_employee'))
      )
      from public.dispute_cases
      where public.can_access_dispute(id)
    ),
    'lastUpdatedAt', now()
  );
end $$;



CREATE OR REPLACE FUNCTION public.get_cron_health()
RETURNS TABLE(
  job_name     text,
  last_run     timestamptz,
  minutes_ago  numeric,
  last_status  text,
  is_healthy   boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- مسموح فقط لـ: full-access أو service_role
  IF auth.role() <> 'service_role' AND NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      l.job_name,
      max(l.ran_at)                                          AS last_run,
      round(extract(epoch FROM now() - max(l.ran_at)) / 60, 1) AS minutes_ago,
      (array_agg(l.status ORDER BY l.ran_at DESC))[1]       AS last_status,
      max(l.ran_at) > now() - INTERVAL '30 minutes'         AS is_healthy
    FROM public.cron_health_log l
    GROUP BY l.job_name;
END;
$$;



CREATE OR REPLACE FUNCTION public.get_daily_report_engagement(p_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if not exists (select 1 from public.daily_reports where id = p_report_id) then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'reportId', p_report_id,
    'viewersCount', (
      select count(*)::integer from public.daily_report_views v
      where v.report_id = p_report_id
    ),
    'likersCount', (
      select count(*)::integer from public.daily_report_likes l
      where l.report_id = p_report_id
    ),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.daily_report_views v
      join public.employees e on e.id = v.employee_id
      where v.report_id = p_report_id
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees e on e.id = l.employee_id
      where l.report_id = p_report_id
    ), '[]'::jsonb)
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_dashboard_overview(p_workspace text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_workspace not in ('hr','main_admin') then
    raise exception 'مساحة عمل غير صالحة' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'employees', (select count(*) from public.employees),
    'activeEmployees', (select count(*) from public.employees where status = 'active'),
    'pendingRequests', (select count(*) from public.requests where status = 'pending'),
    'attendancePendingReview', (select count(*) from public.attendance_events where requires_review = true),
    'pendingKpi', (select count(*) from public.kpi_evaluations where current_stage <> 'finalized'),
    'openRequisitions', (select count(*) from public.job_requisitions where status in ('pending','approved','posted')),
    'urgentActions', (
      select count(*) from public.requests
      where status = 'pending' and decision_due_at is not null and decision_due_at < now() + interval '4 hours'
    ),
    'publishedDecisions', (select count(*) from public.administrative_decisions where status = 'published'),
    'unresolvedErrors', case when p_workspace = 'main_admin'
      then (select count(*) from public.app_error_events where resolved = false)
      else 0 end,
    'lastUpdatedAt', now()
  );
end;
$function$;



create or replace function public.get_dispute_case_recommendations(p_case_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_emp uuid := public.current_employee_id();
begin
  -- نفس بوابة الصلاحية المستخدمة في get_committee_dispute_portal
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all')
    or exists(select 1 from public.committee_members
              where employee_id = v_emp and is_active)
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- التحقق من وجود القضية
  if not exists(select 1 from public.dispute_cases where id = p_case_id) then
    raise exception 'CASE_NOT_FOUND' using errcode = '42P01';
  end if;

  return jsonb_build_object(
    'recommendations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'submittedByName', e.full_name_ar,
        'submittedById', s.submitted_by,
        'statementType', s.statement_type,
        'statementText', s.statement_text,
        'submittedAt', s.submitted_at,
        'visibility', s.visibility,
        'isOwn', (s.submitted_by = v_emp)
      ) order by s.submitted_at desc)
      from public.dispute_statements s
      join public.employees e on e.id = s.submitted_by
      where s.case_id = p_case_id
        and s.statement_type in ('committee_note','recommendation')
    ), '[]'::jsonb),
    'myRecommendationExists', exists(
      select 1 from public.dispute_statements
      where case_id = p_case_id
        and submitted_by = v_emp
        and statement_type = 'recommendation'
    ),
    'totalCount', (
      select count(*) from public.dispute_statements
      where case_id = p_case_id
        and statement_type in ('committee_note','recommendation')
    )
  );
end $$;



create or replace function public.get_dispute_operations_catalog(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.portal.access') or public.has_permission('disputes.case.read_all') or exists(select 1 from public.committee_members where employee_id=public.current_employee_id() and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return jsonb_build_object(
  'cases',coalesce((select jsonb_agg(
   -- الجزء الأول: البيانات الأساسية (30 زوج = 60 وسيط)
   jsonb_build_object(
   'id',c.id,'caseNumber',c.case_number,'title',c.title,'description',c.description,'caseType',c.case_type,'status',c.status,'priority',c.severity,
   'actorId',c.actor_employee_id,'actorName',a.full_name_ar,'actorDepartment',ad.name,
   'respondentId',c.respondent_employee_id,'respondentName',r.full_name_ar,
   'assignedTo',c.assigned_to,'assignedName',ass.full_name_ar,'openedAt',c.opened_at,'updatedAt',c.updated_at,
   'acceptedAt',c.accepted_at,'reviewDueAt',c.review_due_at,'decisionDueAt',c.decision_due_at,'overdue',(c.status in ('submitted','needs_more_information') and c.review_due_at<now()),
   'incidentAt',c.incident_at,'incidentLocation',c.incident_location,'requestedAction',c.requested_action,
   'directManagerContacted',c.direct_manager_contacted,'amicableAttempted',c.amicable_resolution_attempted,'amicableResult',c.amicable_resolution_result,
   'confidential',c.is_confidential,'privacyLevel',c.privacy_level,'quorum',c.committee_quorum,'closureReason',c.closure_reason
   )
   ||
   -- الجزء الثاني: حقول الإجراء الإداري + العلاقات (22 زوج = 44 وسيط)
   jsonb_build_object(
   'proposedAdminAction',c.proposed_administrative_action,
   'proposedActionDetail',c.proposed_action_detail,
   'proposedAt',c.proposed_at,
   'proposedByName',pb.full_name_ar,
   'executiveDecision',c.executive_decision,
   'executiveDecisionReason',c.executive_decision_reason,
   'executiveDecisionAt',c.executive_decision_at,
   'executiveDecisionByName',edb.full_name_ar,
   'approvedAdminAction',c.approved_administrative_action,
   'approvedActionDetail',c.approved_action_detail,
   'executedAt',c.executed_at,
   'executedByName',exb.full_name_ar,
   'executionNotes',c.execution_notes,
   'parties',coalesce((select jsonb_agg(jsonb_build_object('id',dp.id,'employeeId',dp.employee_id,'name',pe.full_name_ar,'type',dp.party_type,'notificationStatus',dp.notification_status,'notifiedAt',dp.notified_at,'statementSubmittedAt',dp.statement_submitted_at) order by dp.party_type,pe.full_name_ar) from public.dispute_parties dp join public.employees pe on pe.id=dp.employee_id where dp.case_id=c.id),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'employeeId',m.employee_id,'name',me.full_name_ar,'role',m.role_in_committee,'active',m.is_active) order by m.role_in_committee) from public.committee_members m join public.employees me on me.id=m.employee_id where m.case_id=c.id),'[]'::jsonb),
   'statements',coalesce((select jsonb_agg(jsonb_build_object('id',st.id,'submittedBy',st.submitted_by,'submittedByName',se.full_name_ar,'type',st.statement_type,'text',st.statement_text,'visibility',st.visibility,'submittedAt',st.submitted_at) order by st.submitted_at desc) from public.dispute_statements st join public.employees se on se.id=st.submitted_by where st.case_id=c.id),'[]'::jsonb),
   'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',ev.id,'title',ev.title,'description',ev.description,'type',ev.evidence_type,'mimeType',ev.mime_type,'storagePath',ev.storage_path,'visibility',ev.visibility,'submittedAt',ev.submitted_at,'submittedByName',ee.full_name_ar) order by ev.submitted_at desc) from public.dispute_evidence ev left join public.employees ee on ee.id=ev.submitted_by where ev.case_id=c.id and ev.deleted_at is null),'[]'::jsonb)
   )
   ||
   -- الجزء الثالث: الجلسات + القرار + الإجراءات + التسويات + الطعون (5 أزواج = 10 وسائط)
   jsonb_build_object(
   'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'type',s.session_type,'scheduledAt',s.scheduled_at,'endsAt',s.ends_at,'heldAt',s.held_at,'status',s.status,'location',s.location,'modality',s.modality,'minutes',s.minutes,'minutesData',s.minutes_data,'outcome',s.outcome,'recommendation',s.recommendation,'followUpAt',s.follow_up_at,
    'attendance',coalesce((select jsonb_agg(jsonb_build_object('committeeMemberId',sa.committee_member_id,'employeeId',cm.employee_id,'name',ae.full_name_ar,'status',sa.attendance_status)) from public.dispute_session_attendance sa join public.committee_members cm on cm.id=sa.committee_member_id join public.employees ae on ae.id=cm.employee_id where sa.session_id=s.id),'[]'::jsonb)) order by s.scheduled_at desc) from public.dispute_sessions s where s.case_id=c.id),'[]'::jsonb),
   'decision',(select jsonb_build_object('id',d.id,'number',d.decision_number,'text',d.decision_text,'rationale',d.rationale,'outcome',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,'ownerId',d.implementation_owner_id,'ownerName',oe.full_name_ar,'dueAt',d.implementation_due_at,'implementedAt',d.implemented_at) from public.dispute_decisions d left join public.employees oe on oe.id=d.implementation_owner_id where d.case_id=c.id order by d.created_at desc limit 1),
   'actions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'type',x.action_type,'note',x.note,'assignedTo',x.assigned_to,'assignedName',xe.full_name_ar,'dueAt',x.due_at,'status',x.execution_status,'proof',x.completion_proof,'completedAt',x.completed_at,'createdAt',x.created_at) order by x.created_at desc) from public.dispute_actions x left join public.employees xe on xe.id=x.assigned_to where x.case_id=c.id and x.execution_status is not null),'[]'::jsonb),
   'settlements',coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'type',z.settlement_type,'fromName',zf.full_name_ar,'toName',zt.full_name_ar,'text',z.apology_text,'publicationPlace',z.publication_place,'dueAt',z.due_at,'status',z.status,'completedAt',z.completed_at) order by z.created_at desc) from public.dispute_settlements z left join public.employees zf on zf.id=z.apology_from left join public.employees zt on zt.id=z.apology_to where z.case_id=c.id),'[]'::jsonb),
   'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'decisionId',ap.decision_id,'appellantId',ap.appellant_employee_id,'appellantName',ape.full_name_ar,'reason',ap.reason,'status',ap.status,'submittedAt',ap.submitted_at,'resolution',ap.resolution) order by ap.submitted_at desc) from public.dispute_appeals ap join public.employees ape on ape.id=ap.appellant_employee_id where ap.case_id=c.id),'[]'::jsonb)
   )
  order by case when c.status in ('submitted','needs_more_information') then 0 when c.status='action_proposed' then 1 when c.status='pending_execution' then 2 else 3 end,c.review_due_at,c.opened_at desc)
  from public.dispute_cases c
  left join public.employees a on a.id=c.actor_employee_id left join public.departments ad on ad.id=a.department_id
  left join public.employees r on r.id=c.respondent_employee_id left join public.employees ass on ass.id=c.assigned_to
  left join public.employees pb on pb.id=c.proposed_by
  left join public.employees edb on edb.id=c.executive_decision_by
  left join public.employees exb on exb.id=c.executed_by
  where (p_status is null or c.status=p_status) and public.can_access_dispute(c.id)),'[]'::jsonb),
  'summary',jsonb_build_object(
   'new',count(*) filter(where status='submitted'),
   'overdue',count(*) filter(where status in ('submitted','needs_more_information') and review_due_at<now()),
   'urgent',count(*) filter(where severity='urgent' and status not in ('closed','rejected','cancelled_by_employee')),
   'critical',count(*) filter(where severity='critical' and status not in ('closed','rejected','cancelled_by_employee')),
   'waitingStatements',count(*) filter(where status in ('waiting_for_respondent','waiting_for_witness')),
   'escalated',count(*) filter(where status='escalated_to_executive'),
   'pendingExecution',(select count(*) from public.dispute_actions where execution_status in ('pending','in_progress','failed')),
   'actionProposed',count(*) filter(where status='action_proposed'),
   'awaitingExecution',count(*) filter(where status='pending_execution'),
   'executed',count(*) filter(where status='executed'),
   'closed',count(*) filter(where status='closed'),
   'averageResolutionHours',coalesce(round(avg(extract(epoch from (closed_at-opened_at))/3600) filter(where closed_at is not null)::numeric,1),0)
  ),
  'pendingAppeals',(select count(*) from public.dispute_appeals where status in ('submitted','under_review')),
  'lastUpdatedAt',now()
 ) from public.dispute_cases where public.can_access_dispute(id);
end $$;



CREATE OR REPLACE FUNCTION public.get_dispute_participant_directory(
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_search text := NULLIF(trim(p_search), '');
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 100), 200));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('relations.case.manage')
    OR public.has_permission('disputes.portal.access')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: صلاحية غير كافية للوصول لدليل المشاركين'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'name', q.full_name_ar,
          'employeeCode', q.employee_code,
          'department', q.department
        )
        ORDER BY q.full_name_ar
      ),
      '[]'::jsonb
    )
    FROM (
      SELECT e.id, e.full_name_ar, e.employee_code, d.name AS department
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      WHERE e.status = 'active'
        AND e.is_active
        AND NOT e.is_deleted
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND (
          v_search IS NULL
          OR e.full_name_ar ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT v_limit
    ) q
  );
END
$$;



CREATE OR REPLACE FUNCTION public.get_employee_360(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'نطاق الموظف مرفوض' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'email', au.email,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', manager_rel.id,
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'latestKpi', (
      select jsonb_build_object(
        'id', ke.id,
        'periodMonth', kc.period_month,
        'currentStage', ke.current_stage,
        'finalScore', ke.final_score,
        'finalRating', ke.final_rating
      )
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id=ke.cycle_id
      where ke.employee_id=e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select *
        from public.requests r
        where r.employee_id=e.id
        order by r.created_at desc
        limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select *
        from public.tasks t
        where t.assignee_employee_id=e.id
        order by t.created_at desc
        limit 10
      ) t
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id=ed.department_id
      where ed.employee_id=e.id
        and (ed.start_date is null or ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        and (ed.end_date is null or ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', e.updated_at
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.employees manager_rel on manager_rel.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    limit 1
  )
  left join public.profiles profile on profile.employee_id=e.id
  left join auth.users au on au.id=profile.id
  where e.id=p_employee_id;

  if v_result is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_employee_departments(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- الحارس: المستدعي إمّا صاحب السجل، أو كامل الوصول، أو HR، أو له وصول
  -- إداري للموظف المستهدف. غير ذلك يُرفض (تجنّب كشف بيانات موظف آخر).
  IF NOT (
    p_employee_id = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.current_is_hr_only()
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: لا صلاحية لعرض أقسام هذا الموظف'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'id', ed.id,
        'departmentId', ed.department_id,
        'departmentName', d.name,
        'jobTitle', ed.job_title,
        'isPrimary', ed.is_primary,
        'assignedAt', ed.assigned_at,
        'allocationPercentage', ed.allocation_percentage,
        'startDate', ed.start_date,
        'endDate', ed.end_date,
        'functionalManagerId', ed.functional_manager_id,
        'functionalManagerName', fm.full_name_ar
      ) order by ed.is_primary desc, ed.assigned_at
    ), '[]'::jsonb)
    FROM public.employee_departments ed
    JOIN public.departments d ON d.id = ed.department_id
    LEFT JOIN public.employees fm ON fm.id = ed.functional_manager_id
    WHERE ed.employee_id = p_employee_id
      AND (ed.end_date IS NULL OR ed.end_date >= current_date)
  );
END;
$$;



CREATE OR REPLACE FUNCTION public.get_employee_photo_url(p_employee_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_url text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF NOT (
    public.has_permission('people.employee.read')
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT e.photo_url INTO v_url FROM public.employees e WHERE e.id = p_employee_id;
  IF v_url IS NULL THEN
    RETURN NULL;
  END IF;

  -- توحيد: استبدل /object/public/ بـ /object/authenticated/ في كل رابط.
  v_url := replace(v_url, '/storage/v1/object/public/employee-avatars/',
                          '/storage/v1/object/authenticated/employee-avatars/');
  RETURN v_url;
END;
$$;



CREATE OR REPLACE FUNCTION public.get_employees_enriched(
  p_search text default null,
  p_status text default null,
  p_limit integer default 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_is_org_admin boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  v_is_org_admin := public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read');

  RETURN coalesce((
    SELECT jsonb_agg(row_data ORDER BY row_data->>'fullNameAr')
    FROM (
      SELECT jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', d.name,
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at
      ) AS row_data
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      LEFT JOIN public.teams t ON t.id = e.team_id
      LEFT JOIN public.branches b ON b.id = e.branch_id
      LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
      WHERE e.is_deleted = false
        AND NOT public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
        AND (p_status IS NULL OR e.status = p_status)
        AND (v_search IS NULL
          OR lower(e.full_name_ar) LIKE '%' || v_search || '%'
          OR lower(coalesce(e.full_name_en, '')) LIKE '%' || v_search || '%'
          OR lower(e.employee_code) LIKE '%' || v_search || '%'
          OR e.phone_e164 LIKE '%' || v_search || '%')
        AND (
          v_is_org_admin
          OR public.can_access_employee(e.id, 'people.employee.read')
        )
      ORDER BY e.created_at DESC
      LIMIT greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
END;
$$;



CREATE OR REPLACE FUNCTION public.get_executive_attendance_overview(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date   date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_rows   jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode = '42501';
  end if;

  -- ─── قراءة من الـ materialized view عند طلب اليوم الحالي ───
  if v_date = (now() at time zone 'Africa/Cairo')::date then
    select
      jsonb_agg(jsonb_build_object(
        'id', id, 'name', full_name_ar, 'employeeCode', employee_code, 'avatarUrl', photo_url,
        'jobTitle', job_title, 'department', department, 'managerName', manager_name,
        'status', derived_status, 'attStatus', att_status,
        'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
        'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
        'onLeave', on_leave, 'assignmentType', assignment_type,
        'lastLatitude', latitude, 'lastLongitude', longitude, 'lastAccuracy', accuracy,
        'lastLocationAt', recorded_at, 'lastAddressAr', address_ar, 'locationSource', loc_source,
        'statusUpdatedAt', greatest(coalesce(att_updated_at, recorded_at), coalesce(recorded_at, att_updated_at)),
        'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
      ) order by full_name_ar),
      jsonb_build_object(
        'total',          count(*),
        'present',        count(*) filter (where derived_status = 'present'),
        'late',           count(*) filter (where derived_status = 'late'),
        'notYet',         count(*) filter (where derived_status = 'not_yet'),
        'absent',         count(*) filter (where derived_status = 'absent'),
        'checkedOut',     count(*) filter (where derived_status = 'checked_out'),
        'leftEarly',      count(*) filter (where derived_status = 'left_early'),
        'onLeave',        count(*) filter (where derived_status = 'on_leave'),
        'onAssignment',   count(*) filter (where derived_status = 'assignment'),
        'onMission',      count(*) filter (where assignment_type = 'MISSION'),
        'onConvoy',       count(*) filter (where assignment_type = 'CONVOY'),
        'onFundraising',  count(*) filter (where assignment_type = 'FUNDRAISING'),
        'weekend',        count(*) filter (where derived_status = 'weekend'),
        'activeLocationRequests', count(*) filter (where active_request_id is not null)
      )
    into v_rows, v_summary
    from public.mv_executive_attendance_snapshot;

    return jsonb_build_object(
      'date', v_date,
      'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
      'employees', coalesce(v_rows, '[]'::jsonb),
      'generatedAt', now(),
      'source', 'cache'
    );
  end if;

  -- ─── استعلام حي للتواريخ الأخرى ───
  with base as (
    select
      e.id, e.full_name_ar, e.employee_code, e.department_id, e.photo_url,
      jt.name as job_title, d.name as department,
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id = mr.manager_employee_id
        where mr.employee_id = e.id and mr.effective_from <= now()
          and (mr.effective_to is null or mr.effective_to > now())
        order by mr.effective_from desc limit 1) as manager_name,
      ad.status as att_status, ad.first_check_in, ad.last_check_out,
      ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
      exists(
        select 1 from public.leave_requests lr join public.requests rq on rq.id = lr.request_id
        where lr.employee_id = e.id and rq.status = 'approved' and v_date between lr.start_date and lr.end_date
      ) as on_leave,
      (select wa.assignment_type from public.work_assignment_participants wp
         join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = e.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between wa.start_at::date and wa.end_at::date
        order by wa.start_at desc limit 1) as assignment_type,
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
      ar.id as active_request_id, ar.status as active_request_status
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_date
    left join lateral (
      select l.latitude, l.longitude, l.accuracy, l.recorded_at, l.address_ar, l.source
      from public.employee_locations l where l.employee_id = e.id order by l.recorded_at desc limit 1
    ) lp on true
    left join lateral (
      select r.id, r.status from public.live_location_requests r
      where r.employee_id = e.id and r.status in ('pending','accepted','active')
        and (r.expires_at is null or r.expires_at > now())
      order by r.requested_at desc limit 1
    ) ar on true
    where e.status = 'active' and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and (public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read'))
  ),
  classified as (
    select *,
      case
        when on_leave then 'on_leave'
        when assignment_type is not null then 'assignment'
        when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
        when att_status = 'present' then 'present'
        when att_status = 'late' then 'late'
        when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
        when last_check_out is not null then 'checked_out'
        when att_status = 'absent' then 'absent'
        when extract(isodow from v_date) = 5 then 'weekend'  -- 0447: fallback أخير (0333/0402)
        else 'not_yet'
      end as derived_status
    from base
  )
  select
    jsonb_agg(jsonb_build_object(
      'id', id, 'name', full_name_ar, 'employeeCode', employee_code, 'avatarUrl', photo_url,
      'jobTitle', job_title, 'department', department, 'managerName', manager_name,
      'status', derived_status, 'attStatus', att_status,
      'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave, 'assignmentType', assignment_type,
      'lastLatitude', latitude, 'lastLongitude', longitude, 'lastAccuracy', accuracy,
      'lastLocationAt', recorded_at, 'lastAddressAr', address_ar, 'locationSource', loc_source,
      'statusUpdatedAt', greatest(coalesce(att_updated_at, recorded_at), coalesce(recorded_at, att_updated_at)),
      'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',         count(*),
      'present',       count(*) filter (where derived_status = 'present'),
      'late',          count(*) filter (where derived_status = 'late'),
      'notYet',        count(*) filter (where derived_status = 'not_yet'),
      'absent',        count(*) filter (where derived_status = 'absent'),
      'checkedOut',    count(*) filter (where derived_status = 'checked_out'),
      'leftEarly',     count(*) filter (where derived_status = 'left_early'),
      'onLeave',       count(*) filter (where derived_status = 'on_leave'),
      'onAssignment',  count(*) filter (where derived_status = 'assignment'),
      'onMission',     count(*) filter (where assignment_type = 'MISSION'),
      'onConvoy',      count(*) filter (where assignment_type = 'CONVOY'),
      'onFundraising', count(*) filter (where assignment_type = 'FUNDRAISING'),
      'weekend',       count(*) filter (where derived_status = 'weekend'),
      'activeLocationRequests', count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from classified;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
    'employees', coalesce(v_rows, '[]'::jsonb),
    'generatedAt', now(),
    'source', 'live'
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_executive_attendance_overview_fast(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date    date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_rows    jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode = '42501';
  end if;

  -- الـ MV تخص اليوم الحالي فقط؛ للتواريخ الأخرى فوّض على الدالة الحية الأصلية.
  if v_date <> (now() at time zone 'Africa/Cairo')::date then
    return public.get_executive_attendance_overview(v_date);
  end if;

  select
    jsonb_agg(jsonb_build_object(
      'id', employee_id, 'name', full_name_ar, 'employeeCode', employee_code,
      'jobTitle', job_title, 'department', department, 'managerName', manager_name,
      'status', derived_status, 'attStatus', att_status,
      'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave, 'assignmentType', assignment_type,
      'lastLatitude', last_latitude, 'lastLongitude', last_longitude,
      'lastAccuracy', last_accuracy,
      'lastLocationAt', last_location_at, 'lastAddressAr', last_address_ar,
      'statusUpdatedAt', status_updated_at,
      'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',                count(*),
      'present',              count(*) filter (where derived_status = 'present'),
      'late',                 count(*) filter (where derived_status = 'late'),
      'notYet',               count(*) filter (where derived_status = 'not_yet'),
      'absent',               count(*) filter (where derived_status = 'absent'),
      'checkedOut',           count(*) filter (where derived_status = 'checked_out'),
      'leftEarly',            count(*) filter (where derived_status = 'left_early'),
      'onLeave',              count(*) filter (where derived_status = 'on_leave'),
      'onAssignment',         count(*) filter (where derived_status = 'assignment'),
      'onMission',            count(*) filter (where assignment_type = 'MISSION'),
      'onConvoy',             count(*) filter (where assignment_type = 'CONVOY'),
      'onFundraising',        count(*) filter (where assignment_type = 'FUNDRAISING'),
      'activeLocationRequests', count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from public.mv_executive_attendance_overview;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
    'employees', coalesce(v_rows, '[]'::jsonb),
    'generatedAt', now(),
    'source', 'cache'
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_executive_attendance_today(p_status text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_status_match text := nullif(trim(coalesce(p_status, '')), '');
begin
  select public.current_has_active_role(array['executive-director', 'executive']) into v_is_executive;

  select public.current_is_full_access()
    or public.has_any_permission(array[
      'attendance.record.read',
      'attendance.history.manage',
      'attendance.roster.manage'
    ])
    or public.has_any_permission(array[
      'people.employee.read'
    ])
  into v_has_attendance_access;

  if not (v_is_executive or v_has_attendance_access) then
    raise exception 'صلاحية تنفيذي أو حضور مطلوبة' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(item order by item->>'name')
    from (
      select jsonb_build_object(
        'id',               e.id,
        'name',             e.full_name_ar,
        'employeeCode',     e.employee_code,
        'jobTitle',         jt.name,
        'department',       d.name,
        'departmentId',     d.id,
        'photoUrl',         e.photo_url,
        'attendanceStatus', coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end),
        'firstCheckIn',     ad.first_check_in,
        'lastCheckOut',     ad.last_check_out,
        'lateMinutes',      coalesce(ad.late_minutes, 0),
        'isOnMission',      (mission.id is not null),
        'lastLatitude',     last_loc.latitude,
        'lastLongitude',    last_loc.longitude,
        'lastRecordedAt',   last_loc.recorded_at
      ) as item,
      -- عمود خفي للترتيب (لا يظهر في JSON النهائي)
      case
        when mission.id is not null                     then 1
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'present' then 2
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'late'    then 3
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'partial' then 4
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'absent'  then 8
        else 9
      end as sort_order
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d   on d.id  = e.department_id
    left join public.attendance_daily ad
           on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select wa.id
      from public.work_assignment_participants wap
      join public.work_assignments wa on wa.id = wap.assignment_id
      where wap.employee_id = e.id
        and wa.status in ('APPROVED', 'IN_PROGRESS')
        and wa.counts_as_work_day = true
        and wa.start_at::date <= v_today
        and wa.end_at::date   >= v_today
      limit 1
    ) mission on true
    left join lateral (
      select lr.employee_id
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      where lr.employee_id = e.id
        and v_today between lr.start_date and lr.end_date
      limit 1
    ) alv on true
    left join lateral (
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      -- فلتر القسم
      and (p_department_id is null or e.department_id = p_department_id)
      -- فلتر البحث
      and (v_search is null
        or e.full_name_ar ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%')
      -- فلتر الحالة (يطبّق بعد الـ LATERAL JOINs)
      and (v_status_match is null or
        coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end) = v_status_match)
      and (
        v_is_executive
        or public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
    order by sort_order, e.full_name_ar
    ) items
  ), '[]'::jsonb);
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_hr_reports_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_att jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
begin
  -- فحص الصلاحية
  if not (public.current_is_full_access()
          or public.has_permission('reports.people.read')
          or public.has_permission('attendance.record.read')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- ═══ الحضور ═══
  -- attendance_events: event_type = 'CHECK_IN'/'CHECK_OUT' (أحرف كبيرة)
  -- event_at (timestamptz) — لا يوجد عمود event_date
  -- requires_review (وليس needs_review)
  select jsonb_build_object(
    'totalEvents', count(*),
    'checkIns',    count(*) filter (where event_type = 'CHECK_IN'  and (event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date),
    'checkOuts',   count(*) filter (where event_type = 'CHECK_OUT' and (event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date),
    'pendingReview', count(*) filter (where requires_review = true),
    'thisMonth',   count(*) filter (where event_at at time zone 'Africa/Cairo' >= date_trunc('month', (now() at time zone 'Africa/Cairo')::date))
  ) into v_att from public.attendance_events;

  -- ═══ الإجازات ═══
  -- leave_requests لا يحتوي على عمود status — الحالة في جدول requests عبر request_id
  select jsonb_build_object(
    'totalRequests', count(*),
    'approved',  count(*) filter (where r.status = 'approved'),
    'pending',   count(*) filter (where r.status = 'pending'),
    'rejected',  count(*) filter (where r.status = 'rejected'),
    'activeNow', count(*) filter (where r.status = 'approved'
                                    and (now() at time zone 'Africa/Cairo')::date between lr.start_date and lr.end_date)
  ) into v_leaves
  from public.leave_requests lr
  join public.requests r on r.id = lr.request_id;

  -- ═══ التكليفات ═══
  -- work_assignments.status بأحرف كبيرة: APPROVED, IN_PROGRESS, COMPLETED, DRAFT, SUBMITTED, PENDING_APPROVAL ...
  select jsonb_build_object(
    'total',     count(*),
    'active',    count(*) filter (where status in ('APPROVED','IN_PROGRESS')),
    'completed', count(*) filter (where status = 'COMPLETED'),
    'pending',   count(*) filter (where status in ('DRAFT','SUBMITTED','PENDING_APPROVAL'))
  ) into v_assignments from public.work_assignments;

  -- ═══ مؤشرات الأداء ═══
  -- kpi_cycles.status: draft, open, in_review, suspended, finalized, locked (أحرف صغيرة)
  -- kpi_evaluations لا يحتوي على عمود status — يستخدم workflow_status (أحرف كبيرة)
  select jsonb_build_object(
    'activeCycles',         (select count(*) from public.kpi_cycles where status = 'open'),
    'totalEvaluations',     count(*),
    'pendingEvaluations',   count(*) filter (where workflow_status in (
      'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_HR','HR_REVIEW',
      'SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW','PARALLEL_REVIEW_IN_PROGRESS',
      'HR_EVALUATION_IN_PROGRESS','MANAGER_EVALUATION_IN_PROGRESS'
    )),
    'completedEvaluations', count(*) filter (where workflow_status in (
      'APPROVED','CLOSED','CYCLE_CLOSED','ARCHIVED','EXECUTIVE_ACKNOWLEDGED'
    ))
  ) into v_kpi from public.kpi_evaluations;

  -- ═══ النزاعات ═══
  -- الجدول: dispute_cases (وليس disputes)
  select jsonb_build_object(
    'total',     count(*),
    'open',      count(*) filter (where status in (
      'submitted','needs_more_information','accepted','under_review',
      'waiting_for_respondent','waiting_for_witness','session_scheduled',
      'session_completed','committee_deliberation','settlement_pending',
      'returned_to_committee','reopened','action_proposed','pending_execution'
    )),
    'resolved',  count(*) filter (where status in (
      'resolved_friendly','closed','decision_issued','executed',
      'cancelled_by_employee','rejected'
    )),
    'escalated', count(*) filter (where status = 'escalated_to_executive')
  ) into v_disputes from public.dispute_cases;

  -- ═══ طلبات الموقع ═══
  -- location_requests.status: pending, fulfilled, rejected, expired, cancelled
  select jsonb_build_object(
    'totalRequests', count(*),
    'pending',   count(*) filter (where status = 'pending'),
    'responded', count(*) filter (where status = 'fulfilled')
  ) into v_location from public.location_requests;

  return jsonb_build_object(
    'attendance',   v_att,
    'leaves',       v_leaves,
    'assignments',  v_assignments,
    'kpi',          v_kpi,
    'disputes',     v_disputes,
    'location',     v_location,
    'generatedAt',  now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_kpi_cycle_evaluations(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_permission('performance.kpi.read')
    or public.has_permission('performance.kpi.hr_review')
    or public.has_permission('performance.kpi.manager_assess')
  ) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'employeeId', e.employee_id,
        'employeeName', emp.full_name_ar,
        'employeeCode', emp.employee_code,
        'department', d.name,
        'stage', e.current_stage,
        'workflowStatus', e.workflow_status,
        'selfScore', scores.self_score,
        'managerScore', scores.manager_score,
        'finalScore', e.final_score,
        'finalRating', e.final_rating,
        'locked', e.locked,
        'updatedAt', e.updated_at
      ) order by emp.full_name_ar, e.id
    )
    from public.kpi_evaluations e
    join public.employees emp on emp.id = e.employee_id
    left join public.departments d on d.id = emp.department_id
    left join lateral (
      select
        round(avg(s.score) filter (where s.reviewer_stage = 'self'), 2) as self_score,
        round(avg(s.score) filter (where s.reviewer_stage = 'manager'), 2) as manager_score
      from public.kpi_scores s
      where s.evaluation_id = e.id
    ) scores on true
    where e.cycle_id = p_cycle_id
      and (
        public.current_is_full_access()
        or public.has_permission('performance.kpi.hr_review')
        or e.employee_id = public.current_employee_id()
        or public.kpi_is_direct_manager(e.employee_id)
      )
  ), '[]'::jsonb);
end;
$function$;



create or replace function public.get_kpi_cycle_report(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary() or public.current_is_hr_reviewer() or public.has_any_permission(array['performance.kpi.report.read','reports.performance.read'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 return jsonb_build_object(
  'cycleId',v_cycle.id,'periodMonth',v_cycle.period_month,'status',v_cycle.status,'deadlineAt',public.kpi_effective_deadline(v_cycle),
  'summary',(select jsonb_build_object('total',count(*),'approved',count(*) filter(where current_stage in ('finalized','closed','archived')),'overdue',count(*) filter(where workflow_status='OVERDUE'),'averageScore',round(avg(final_score),2)) from public.kpi_evaluations where cycle_id=p_cycle_id),
  'distribution',(select coalesce(jsonb_object_agg(coalesce(final_rating,'غير مكتمل'),count),'{}'::jsonb) from (select final_rating,count(*) count from public.kpi_evaluations where cycle_id=p_cycle_id group by final_rating)x),
  'evaluations',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,'stage',e.current_stage,'workflowStatus',e.workflow_status,'finalScore',e.final_score,'finalRating',e.final_rating,'breakdown',e.final_breakdown,'attendance',(select to_jsonb(a)-'id'-'evaluation_id' from public.kpi_attendance_snapshots a where a.evaluation_id=e.id)) order by emp.full_name_ar) from public.kpi_evaluations e join public.employees emp on emp.id=e.employee_id where e.cycle_id=p_cycle_id),'[]'::jsonb),
  'generatedAt',now()
 );
end $$;



create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles;
 v_editable text; v_compliance_editable boolean:=false; v_locked boolean; v_criteria jsonb;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);

 if not v_locked then
  if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id()
     and (public.current_is_full_access() or public.has_permission('performance.kpi.self_assess')) then
   v_editable:='self';
  elsif v_eval.current_stage='manager_review' and public.kpi_can_approve(v_eval) then
   v_editable:='manager_review';
  end if;
  -- استثناءات HR متاحة في أي مرحلة غير مقفلة (0470)
  if not v_eval.locked and public.current_is_hr_reviewer() then v_compliance_editable:=true; end if;
 end if;

 -- انتقالات حالة العرض
 if v_editable='manager_review' and v_eval.workflow_status='SUBMITTED_TO_DIRECT_MANAGER' then
  update public.kpi_evaluations set workflow_status='MANAGER_EVALUATION_IN_PROGRESS',updated_at=now() where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.manager.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء المدير المباشر مراجعة التقييم',null,null);
 end if;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',case when v_editable='self' then true
                  when v_editable='manager_review' then c.evaluator_stage='manager'
                  else false end,
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}')
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;

 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'complianceEditable',v_compliance_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'parallelFlow',false,'hrCompleted',v_eval.hr_completed,'managerCompleted',v_eval.manager_completed,'version',v_eval.version,
  'cycle',jsonb_build_object('id',v_cycle.id,'status',v_cycle.status,'scheduledOpenAt',v_cycle.scheduled_open_at,'deadlineAt',v_cycle.deadline_at,'extendedUntil',v_cycle.extended_until,'effectiveDeadline',public.kpi_effective_deadline(v_cycle)),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'description',g.description,'targetValue',g.target_value,'achievedValue',g.achieved_value,'unit',g.unit,'weight',g.weight,'dueDate',g.due_date,'evidenceSource',g.evidence_source,'employeeNote',g.employee_note,'managerNote',g.manager_note,'status',g.status,'calculatedScore',g.calculated_score) order by g.created_at) from public.kpi_goals g where g.evaluation_id=v_eval.id),'[]'::jsonb),
  'session',(select jsonb_build_object('id',s.id,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'mode',s.mode,'discussionSummary',s.discussion_summary,'strengths',s.strengths,'improvementPoints',s.improvement_points,'nextMonthGoals',s.next_month_goals,'employeeNotes',s.employee_notes,'managerNotes',s.manager_notes,'employeeAttended',s.employee_attended,'managerAttended',s.manager_attended,'employeeConfirmedAt',s.employee_confirmed_at) from public.kpi_review_sessions s where s.evaluation_id=v_eval.id),
  'compliance',coalesce((select jsonb_agg(jsonb_build_object('metric',r.metric,'requiredCount',r.required_count,'actualCount',r.actual_count,'exemptCount',r.exempt_count,'cancelledCount',r.cancelled_count,'score',r.calculated_score,'note',r.note)) from public.kpi_compliance_records r where r.evaluation_id=v_eval.id),'[]'::jsonb),
  'attendance',(select jsonb_build_object('periodStart',a.period_start,'periodEnd',a.period_end,'lateCount',a.late_count,'earlyLeaveCount',a.early_leave_count,'unexcusedAbsenceCount',a.unexcused_absence_count,'shortagePenalty',a.shortage_penalty,'missingPunchCount',a.missing_punch_count,'score',a.score,'hasPendingItems',a.has_pending_items,'calculatedAt',a.calculated_at) from public.kpi_attendance_snapshots a where a.evaluation_id=v_eval.id),
  'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'criterionId',x.criterion_id,'type',x.evidence_type,'title',x.title,'description',x.description,'storagePath',x.storage_path,'externalUrl',x.external_url,'submittedStage',x.submitted_stage,'createdAt',x.created_at) order by x.created_at) from public.kpi_evidence x where x.evaluation_id=v_eval.id),'[]'::jsonb),
  'validationErrors',to_jsonb(public.get_kpi_validation_errors(v_eval.id)),
  'lastUpdatedAt',coalesce(v_eval.updated_at,v_eval.created_at)
 );
end $$;



create or replace function public.get_kpi_validation_errors(p_evaluation_id uuid)
returns text[]
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_eval public.kpi_evaluations;
  v_errors text[] := array[]::text[];
  v_total numeric;
begin
  select * into strict v_eval from public.kpi_evaluations where id = p_evaluation_id;

  if exists(
    select 1 from public.kpi_criteria c
    where c.template_id = v_eval.template_id
      and public.kpi_effective_score(v_eval.id, c.id) is null
  ) then
    v_errors := array_append(v_errors, 'لم تكتمل درجات البنود السبعة.');
  end if;

  if not exists(
    select 1
    from public.kpi_scores s
    join public.kpi_criteria c on c.id = s.criterion_id
    where s.evaluation_id = v_eval.id
      and s.reviewer_stage = 'self'
    group by s.evaluation_id
    having count(distinct s.criterion_id) =
      (select count(*) from public.kpi_criteria where template_id = v_eval.template_id)
  ) then
    v_errors := array_append(v_errors, 'التقييم الذاتي للبنود غير مكتمل.');
  end if;

  if nullif(trim(coalesce(v_eval.manager_comment, '')), '') is null then
    v_errors := array_append(v_errors, 'ملاحظة المدير مطلوبة قبل الاعتماد النهائي.');
  end if;

  v_total := public.kpi_total_score(p_evaluation_id);
  if v_total < 0 or v_total > 100 then
    v_errors := array_append(v_errors, 'المجموع النهائي يجب أن يكون بين صفر و100.');
  end if;

  return v_errors;
end $$;



create or replace function public.get_leave_requests_admin(
  p_year         integer default null,
  p_status       text    default null,
  p_leave_type   text    default null,
  p_employee_id  uuid    default null,
  p_limit        integer default 50,
  p_offset       integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_year  integer;
  v_total bigint;
  v_rows  jsonb;
begin
  if not (
    current_is_full_access()
    or has_permission('requests.leave.balance.read')
    or has_permission('requests.request.read')
  ) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Africa/Cairo')::integer);

  -- العد الكلي قبل الـ pagination
  select count(*)
    into v_total
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    join public.employees e on e.id = lr.employee_id
     and coalesce(e.is_deleted, false) = false
    join public.leave_types lt on lt.id = lr.leave_type_id
   where extract(year from lr.start_date)::integer = v_year
     and (p_status      is null or r.status = p_status)
     and (p_leave_type  is null or lt.code  = p_leave_type)
     and (p_employee_id is null or e.id     = p_employee_id);

  -- جلب الصفحة المطلوبة
  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'requestId',     r.id,
        'requestNumber', r.request_number,
        'status',        r.status,
        'createdAt',     r.created_at,
        'employeeId',    e.id,
        'employeeCode',  e.employee_code,
        'employeeName',  coalesce(e.full_name_ar, e.full_name_en),
        'leaveTypeId',   lt.id,
        'leaveTypeCode', lt.code,
        'leaveTypeName', lt.name_ar,
        'isPaid',        lt.is_paid,
        'startDate',     lr.start_date,
        'endDate',       lr.end_date,
        'daysCount',     lr.days_count,
        'hoursCount',    lr.hours_count,
        'durationUnit',  coalesce(lr.duration_unit, 'day'),
        'isHalfDay',     coalesce(lr.is_half_day, false),
        'reason',        r.reason,
        'handoverNotes', lr.handover_notes,
        'attachmentUrl', lr.attachment_url
      ) as row_data,
      r.created_at
        from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        join public.employees e on e.id = lr.employee_id
         and coalesce(e.is_deleted, false) = false
        join public.leave_types lt on lt.id = lr.leave_type_id
       where extract(year from lr.start_date)::integer = v_year
         and (p_status      is null or r.status = p_status)
         and (p_leave_type  is null or lt.code  = p_leave_type)
         and (p_employee_id is null or e.id     = p_employee_id)
       order by r.created_at desc
       limit p_limit offset p_offset
    ) sub;

  return jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;



CREATE OR REPLACE FUNCTION public.get_live_location_request_by_id(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'id', q.id, 'requesterName', q.requester_name, 'reason', q.reason,
    'status', q.effective_status, 'mode', q.mode,
    'durationMinutes', q.duration_minutes, 'requestedAt', q.requested_at,
    'expiresAt', q.expires_at
  ) into v_result
  from (
    select r.id, req.full_name_ar requester_name, r.reason,
      case when r.status in ('pending','accepted','active') and r.expires_at<now() then 'expired' else r.status end effective_status,
      coalesce(r.metadata->>'mode','snapshot') mode, r.duration_minutes, r.requested_at, r.expires_at
    from public.live_location_requests r
    left join public.employees req on req.id = r.requested_by
    where r.id = p_request_id
      and (
        r.employee_id = public.current_employee_id()
        or r.requested_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.can_access_employee(r.employee_id, 'live_location.view_response')
      )
  ) q;

  if v_result is null then
    raise exception 'طلب الموقع غير موجود أو غير مرئي' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_live_location_response(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_req      public.live_location_requests;
  v_emp      public.employees;
  v_result   jsonb;
  v_has_video boolean;
begin
  select * into v_req from public.live_location_requests where id=p_request_id;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;

  -- الصلاحية: صاحب الطلب (الموظف) أو من يملك view_response عليه أو full-access.
  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.can_access_employee(v_req.employee_id,'live_location.view_response')
  ) then
    raise exception 'غير مسموح لك بعرض هذه الاستجابة' using errcode='42501';
  end if;

  select * into v_emp from public.employees where id=v_req.employee_id;

  select exists(select 1 from public.live_location_videos_meta m where m.live_request_id=p_request_id and m.status<>'deleted')
    into v_has_video;

  v_result := jsonb_build_object(
    'request', jsonb_build_object(
      'id',v_req.id,'status',
        case when v_req.status in ('pending','accepted','active') and v_req.expires_at<now() then 'expired' else v_req.status end,
      'mode',coalesce(v_req.metadata->>'mode','snapshot'),
      'reason',v_req.reason,'purpose',v_req.purpose,
      'requestedAt',v_req.requested_at,'respondedAt',v_req.responded_at,
      'startsAt',v_req.starts_at,'expiresAt',v_req.expires_at,
      'durationMinutes',v_req.duration_minutes,
      'needsVideo',coalesce((v_req.metadata->>'needsVideo')::boolean,false),
      'needsPoint',coalesce((v_req.metadata->>'needsPoint')::boolean,true)
    ),
    'employee', jsonb_build_object(
      'id',v_emp.id,'name',v_emp.full_name_ar,'employeeCode',v_emp.employee_code,
      'jobTitle',(select name from public.job_titles where id=v_emp.job_title_id),
      'department',(select name from public.departments where id=v_emp.department_id)
    ),
    'requesterName',(select full_name_ar from public.employees where id=v_req.requested_by),
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',l.id,'latitude',l.latitude,'longitude',l.longitude,'accuracy',l.accuracy,
        'altitude',l.altitude,'speed',l.speed,'heading',l.heading,'isMock',l.is_mock,
        'source',l.source,'addressAr',l.address_ar,'recordedAt',l.recorded_at,'createdAt',l.created_at
      ) order by l.recorded_at)
      from public.employee_locations l where l.live_request_id=p_request_id
    ),'[]'::jsonb),
    'video', (
      select jsonb_build_object(
        'id',m.id,'durationSeconds',m.duration_seconds,'sizeBytes',m.size_bytes,'mimeType',m.mime_type,
        'capturedLat',m.captured_lat,'capturedLng',m.captured_lng,'capturedAccuracy',m.captured_accuracy,
        'capturedAt',m.captured_at,'status',m.status,
        'retentionDeleteAfter',m.retention_delete_after,'legalHoldUntil',m.legal_hold_until
      )
      from public.live_location_videos_meta m
      where m.live_request_id=p_request_id and m.status<>'deleted'
      order by m.created_at desc limit 1
    )
  );

  perform public.log_audit_event('live_location.response_viewed','security','info','live_location_requests',p_request_id,'اطّلاع على نتيجة طلب الموقع',null,jsonb_build_object('hasVideo',v_has_video));
  if v_has_video then
    insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action)
    select m.id, auth.uid(), public.current_employee_id(), 'view'
    from public.live_location_videos_meta m
    where m.live_request_id=p_request_id and m.status<>'deleted'
    order by m.created_at desc limit 1;
  end if;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_location_directory(
  p_search text    default null,
  p_limit  integer default 100
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text;
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('live_location.request')) THEN
    RAISE EXCEPTION 'live location request permission required' USING errcode = '42501';
  END IF;

  v_search := nullif(trim(coalesce(p_search, '')), '');

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) ORDER BY q.full_name_ar)
    FROM (
      SELECT
        e.id, e.full_name_ar, e.employee_code,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status
      FROM public.employees e
      LEFT JOIN public.job_titles  jt  ON jt.id = e.job_title_id
      LEFT JOIN public.departments d   ON d.id  = e.department_id
      LEFT JOIN LATERAL (
        SELECT l.latitude, l.longitude, l.accuracy, l.recorded_at
        FROM public.employee_locations l
        WHERE l.employee_id = e.id
        ORDER BY l.recorded_at DESC LIMIT 1
      ) last_point ON TRUE
      LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM public.live_location_requests r
        WHERE r.employee_id = e.id
          AND r.status IN ('pending','accepted','active')
          AND (r.expires_at IS NULL OR r.expires_at > now())
        ORDER BY r.requested_at DESC LIMIT 1
      ) active_req ON TRUE
      WHERE e.status IN ('active', 'invited', 'onboarding')
        AND e.is_deleted = false
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND e.user_id IS NOT NULL
        AND NOT public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
        AND (
          public.current_is_full_access()
          OR public.can_access_employee(e.id, 'live_location.request')
        )
        AND (
          v_search IS NULL
          OR e.full_name_ar  ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
END;
$$;



CREATE OR REPLACE FUNCTION public.get_mobile_action_target(p_action_id text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
  v_emp uuid;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    -- حضور/بصمة: أي حدث/تصحيح/طلب يخصني أو أملك صلاحية مراجعته
    when 'attendance' then
      select (
        exists(select 1 from public.attendance_events e
               where e.id = v_uuid and e.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_corrections c
                  where c.id = v_uuid and c.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_punch_attempts pa
                  where pa.attendance_event_id = v_uuid and pa.employee_id = public.current_employee_id())
        or public.current_is_full_access()
        or public.has_any_permission(array[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) into v_allowed;
      if not v_allowed then
        -- fallback: إن لم يوجد سجل أصلاً، اسمح بالفتح لعرض صفحة الحضور العامة
        -- (الهوية مؤكدة عبر كونها UUID صالح — لا تسريب بيانات).
        return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      end if;
      return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    -- نزاع: أحد الأطراف أو عضو لجنة أو مدير نزاعات
    when 'dispute' then
      select exists(
        select 1 from public.dispute_cases dc
        where dc.id = v_uuid and (
          dc.actor_employee_id = public.current_employee_id()
          or dc.respondent_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_dispute(dc.id)
          or public.has_any_permission(array['disputes.case.read','disputes.case.manage'])
        )
      ) into v_allowed;
    if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    -- مهمة: المكلّف أو المُسنِد أو مدير المهام
    when 'task' then
      select exists(
        select 1 from public.tasks t
        where t.id = v_uuid and (
          t.assignee_employee_id = public.current_employee_id()
          or t.created_by_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.has_any_permission(array['tasks.task.read','tasks.task.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    -- إعلان: منشور أو موجّه إليّ
    when 'announcement' then
      select exists(
        select 1 from public.announcements a
        where a.id = v_uuid and (
          a.status = 'published'
          or public.current_is_full_access()
          or public.has_any_permission(array['comms.announcement.read','comms.announcement.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    -- تقدير: المستلم أو المُرسل أو الإدارة
    when 'recognition' then
      select (
        exists(select 1 from public.recognitions r
               where r.id = v_uuid and (
                 r.recipient_employee_id = public.current_employee_id()
                 or r.nominated_by = public.current_employee_id()
               ))
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      ) into v_allowed;
    if not v_allowed then
        -- التقدير العام يظهر في feed حتى لو لم أكن طرفاً مباشراً
        return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');
      end if;
      return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_daily_reports(p_employee_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_target uuid := coalesce(p_employee_id, public.current_employee_id());
  v_result jsonb;
begin
  if v_target is null or not public.can_access_employee(v_target, 'reports.read') then
    raise exception 'نطاق التقارير مرفوض' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', dr.employee_id,
    'employeeName', e.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewerName', reviewer.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where employee_id = v_target
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.employees reviewer on reviewer.id = dr.reviewed_by;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_employee_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name,
      'statusToday',  case
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
        when exists (
          select 1 from public.missions m join public.requests r on r.id = m.request_id
          where m.employee_id = e.id and r.status = 'approved'
            and v_today between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
          where c.employee_id = e.id and r.status = 'approved'
            and v_today between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
          where wp.employee_id = e.id and wa.status = 'APPROVED' and coalesce(wa.counts_as_work_day,true)
            and v_today between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id and r.status = 'approved'
            and v_today between lr.start_date and lr.end_date
        ) then 'on_leave'
        else 'absent'
      end
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    where e.is_active  = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and public.can_see_directory_entry(public.current_employee_id(), e.id)  -- 0474/0482: عزل الإدارة الطبية في الدليل
      and (
        v_search is null
        or e.full_name_ar  ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%'
        or jt.name         ilike '%' || v_search || '%'
        or d.name          ilike '%' || v_search || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$function$;



create or replace function public.get_mobile_executive_brief(p_period text default 'morning')
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_today date:=(now() at time zone 'Africa/Cairo')::date; v_daily jsonb; v_previous jsonb;
begin
 if p_period not in ('morning','evening') then raise exception 'INVALID_BRIEF_PERIOD' using errcode='22023'; end if;
 v_daily:=public.get_v10_executive_daily_report(v_today);
 v_previous:=public.get_v10_executive_daily_report(v_today-1);
 return jsonb_build_object(
  'period',p_period,'briefDate',v_today,
  'attendance',jsonb_build_object(
    'presentToday',coalesce((v_daily#>>'{attendance,present}')::integer,0),
    'presentYesterday',coalesce((v_previous#>>'{attendance,present}')::integer,0),
    'lateToday',coalesce((v_daily#>>'{attendance,late}')::integer,0),
    'lateYesterday',coalesce((v_previous#>>'{attendance,late}')::integer,0),
    'absentToday',coalesce((v_daily#>>'{attendance,absent}')::integer,0),
    'onLeaveToday',coalesce((v_daily#>>'{workStatus,approvedLeave}')::integer,0),
    'weekAverageLate',coalesce((select round(avg(x.n),1) from (select count(*)::numeric n from public.attendance_daily where work_date between v_today-7 and v_today-1 and (status='late' or late_minutes>0) group by work_date)x),0)
  ),
  'decisions',jsonb_build_object(
    'urgentActions',coalesce((v_daily#>>'{followUp,unansweredLocationRequests}')::integer,0)+coalesce((v_daily#>>'{kpi,overdue}')::integer,0),
    'pendingApprovals',coalesce((v_daily#>>'{requests,pendingLeave}')::integer,0)+coalesce((v_daily#>>'{requests,pendingMission}')::integer,0),
    'pendingFinalKpi',coalesce((v_daily#>>'{kpi,ready}')::integer,0),
    'decisionsInReview',coalesce((v_daily#>>'{followUp,decisions}')::integer,0),
    'publishedToday',(select count(*) from public.administrative_decisions where status='published' and published_at>=v_today::timestamptz),
    'reportsReadyToday',coalesce((v_daily#>>'{kpi,ready}')::integer,0)
  ),
  'risk',jsonb_build_object(
    'criticalRisks',(select count(*) from public.risks where status in ('open','mitigating') and severity='critical'),
    'highRisks',(select count(*) from public.risks where status in ('open','mitigating') and severity='high'),
    'activeIncidents',(select count(*) from public.incidents where status in ('open','investigating')),
    'criticalIncidents',(select count(*) from public.incidents where status in ('open','investigating') and severity='critical')
  ),
  'highlights',jsonb_build_array(
    jsonb_build_object('kind','attendance','title','لم يسجلوا بعد','value',coalesce((v_daily#>>'{attendance,notYet}')::integer,0),'severity','high','detail','من جميع الموظفين المطلوب حضورهم اليوم'),
    jsonb_build_object('kind','attendance','title','لم يسجلوا الانصراف','value',coalesce((v_daily#>>'{attendance,missingCheckout}')::integer,0),'severity','high','detail','حالات تحتاج متابعة اكتمال اليوم'),
    jsonb_build_object('kind','kpi','title','تقارير KPI جاهزة','value',coalesce((v_daily#>>'{kpi,ready}')::integer,0),'severity','normal','detail','تقارير اعتمدها المدير المباشر'),
    jsonb_build_object('kind','case','title','قضايا جديدة','value',coalesce((v_daily#>>'{cases,new}')::integer,0),'severity','high','detail','قضايا تنتظر بدء الإجراء'),
    jsonb_build_object('kind','location','title','طلبات موقع بلا استجابة','value',coalesce((v_daily#>>'{followUp,unansweredLocationRequests}')::integer,0),'severity','critical','detail','طلبات نشطة لم يفتحها المستلم بعد')
  ),
  'dailyReport',v_daily,'generatedAt',now(),'sourceLabel','مصادر V10 التشغيلية المباشرة'
 );
end $$;



CREATE OR REPLACE FUNCTION public.get_mobile_executive_command_center()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_allowed boolean;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'comms.decision.manage',
    'reports.executive.read',
    'reports.schedule.manage',
    'live_location.request',
    'risks.read',
    'incidents.read'
  ]);
  if not v_allowed then
    raise exception 'وصول مركز القيادة التنفيذي مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', coalesce(s.name_ar, r.report_type),
        'reportType', r.report_type,
        'scheduleKind', s.schedule_kind,
        'status', r.status,
        'periodStart', r.period_start,
        'periodEnd', r.period_end,
        'storagePath', r.result_storage_path,
        'summary', r.result_summary,
        'attempts', r.attempts,
        'createdAt', r.created_at,
        'completedAt', r.completed_at,
        'errorDetail', r.error_detail
      ) order by r.created_at desc)
      from (
        select * from public.report_runs order by created_at desc limit 60
      ) r
      left join public.scheduled_reports s on s.id = r.scheduled_report_id
    ), '[]'::jsonb),
    'reportSchedules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name_ar,
        'reportType', s.report_type,
        'scheduleKind', s.schedule_kind,
        'active', s.active,
        'nextRunAt', s.next_run_at,
        'lastRunAt', s.last_run_at
      ) order by s.active desc, s.next_run_at nulls last)
      from public.scheduled_reports s
    ), '[]'::jsonb),
    'executionItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'decisionId', x.decision_id,
        'decisionTitle', x.decision_title,
        'title', x.title,
        'ownerName', x.owner_name,
        'dueAt', x.due_at,
        'status', x.status,
        'progressPercent', x.progress_percent,
        'blocker', x.blocker,
        'updatedAt', x.updated_at
      ) order by x.is_overdue desc, x.due_at nulls last, x.updated_at desc nulls last)
      from (
        select i.*, d.title decision_title, e.full_name_ar owner_name,
          (i.due_at is not null and i.due_at < now() and i.status not in ('completed','cancelled')) is_overdue
        from public.decision_execution_items i
        join public.administrative_decisions d on d.id = i.decision_id
        left join public.employees e on e.id = i.owner_employee_id
        where i.status <> 'cancelled'
        order by is_overdue desc, i.due_at nulls last
        limit 80
      ) x
    ), '[]'::jsonb),
    'polls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'decisionId', p.decision_id,
        'decisionTitle', d.title,
        'question', p.question,
        'pollType', p.poll_type,
        'status', p.status,
        'isAnonymous', p.is_anonymous,
        'opensAt', p.opens_at,
        'closesAt', p.closes_at,
        'quorumPercent', p.quorum_percent,
        'approvalThresholdPercent', p.approval_threshold_percent,
        'eligibleCount', (select count(*) from public.decision_poll_eligibility pe where pe.poll_id = p.id),
        'voteCount', (select count(*) from public.decision_poll_votes pv where pv.poll_id = p.id),
        'canVote', exists(select 1 from public.decision_poll_eligibility pe where pe.poll_id = p.id and pe.employee_id = v_employee_id),
        'myOptionIds', coalesce((select to_jsonb(pv.option_ids) from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id), '[]'::jsonb),
        'myRating', (select pv.rating from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id),
        'options', coalesce((
          select jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label) order by o.sort_order, o.label)
          from public.decision_poll_options o where o.poll_id = p.id
        ), '[]'::jsonb)
      ) order by p.status = 'open' desc, p.closes_at)
      from public.decision_polls p
      left join public.administrative_decisions d on d.id = p.decision_id
      where p.status in ('open','closed','certified')
        and (
          public.current_is_full_access()
          or public.has_permission('comms.decision.manage')
          or exists (
            select 1 from public.decision_poll_eligibility pe
            where pe.poll_id = p.id and pe.employee_id = v_employee_id
          )
        )
    ), '[]'::jsonb),
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'likelihood', x.likelihood,
        'impact', x.impact,
        'severity', x.severity,
        'status', x.status,
        'ownerName', x.owner_name,
        'updatedAt', x.updated_at,
        'createdAt', x.created_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select r.*, e.full_name_ar owner_name
        from public.risks r
        left join public.employees e on e.id = r.owner_employee_id
        where r.status in ('open','mitigating','accepted')
        order by r.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'incidents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'severity', x.severity,
        'status', x.status,
        'reporterName', x.reporter_name,
        'createdAt', x.created_at,
        'updatedAt', x.updated_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select i.*, e.full_name_ar reporter_name
        from public.incidents i
        left join public.employees e on e.id = i.reported_by
        where i.status in ('open','investigating')
        order by i.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'scheduledAt', x.scheduled_at,
        'locationOrLink', x.location_or_link,
        'organizerName', x.organizer_name,
        'status', x.status
      ) order by x.scheduled_at)
      from (
        select m.*, e.full_name_ar organizer_name
        from public.meetings m
        left join public.employees e on e.id = m.organizer_employee_id
        where m.status = 'scheduled' and m.scheduled_at >= now() - interval '2 hours'
        order by m.scheduled_at
        limit 40
      ) x
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_executive_employee_summary(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_allowed boolean;
  v_result jsonb;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول ملخص الموظفين مرفوض' using errcode = '42501';
  end if;
  -- نطاق فعلي على الموظف المستهدف — المدير المباشر لا يقرأ خارج فريقه.
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'people.employee.read')) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية ملف هذا الموظف' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'status', e.status,
    'jobTitle', jt.name,
    'position', p.name,
    'department', d.name,
    'team', tm.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'hireDate', e.hire_date,
    'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
    'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
    'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
    'latestKpi', (
      select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'recentAttendance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'workDate', a.work_date,
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'workMinutes', a.work_minutes,
        'firstCheckIn', a.first_check_in,
        'lastCheckOut', a.last_check_out
      ) order by a.work_date desc)
      from (
        select * from public.attendance_daily
        where employee_id = e.id
        order by work_date desc
        limit 14
      ) a
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = p_employee_id;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_executive_people(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_allowed boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول الموظفين التنفيذي مرفوض' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id,
      'employeeCode', x.employee_code,
      'name', x.full_name_ar,
      'photoUrl', x.photo_url,
      'jobTitle', x.job_title,
      'department', x.department,
      'team', x.team,
      'attendanceStatus', x.attendance_status,
      'pendingRequests', x.pending_requests,
      'openTasks', x.open_tasks,
      'latestKpiScore', x.latest_kpi_score
    ) order by x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        ad.status attendance_status,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1) latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
        and public.can_access_employee(e.id,'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_feed_item(p_kind text, p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if lower(p_kind) = 'announcement' then
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'postType', coalesce(a.post_type, 'announcement'),
      'requiresAcknowledgement', a.requires_acknowledgement,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'myReaction', (select x.reaction_type from public.announcement_reactions x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'viewCount', (select count(*)::integer from public.announcement_views x where x.announcement_id=a.id),
      'reactionCount', (select count(*)::integer from public.announcement_reactions x where x.announcement_id=a.id),
      'reactionSummary', coalesce((
        select jsonb_object_agg(x.reaction_type, x.total)
        from (
          select ar.reaction_type, count(*)::integer total
          from public.announcement_reactions ar
          where ar.announcement_id = a.id
          group by ar.reaction_type
        ) x
      ), '{}'::jsonb),
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'authorName', ae.full_name_ar,
      'authorPhotoUrl', ae.photo_url,
      'attachments', case when a.banner_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',a.banner_url,'type','banner')) end
    ) into v_result
    from public.announcements a
    left join public.employees ae on ae.user_id = a.created_by
    where a.id=p_item_id and a.status='published';
  elsif lower(p_kind) = 'decision' then
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'postType', 'decision',
      'requiresAcknowledgement', d.requires_read_receipt,
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'myReaction', null,
      'viewCount', (select count(*)::integer from public.decision_reads x where x.decision_id=d.id),
      'reactionCount', 0,
      'reactionSummary', '{}'::jsonb,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'decisionNumber', d.decision_number,
      'effectiveDate', d.effective_date,
      'attachments', case when d.attachment_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',d.attachment_url,'type','attachment')) end
    ) into v_result
    from public.administrative_decisions d where d.id=p_item_id and d.status='published';
  elsif lower(p_kind) = 'recognition' then
    select jsonb_build_object(
      'id', r.id, 'kind', 'recognition', 'title', r.title, 'body', coalesce(r.message,''),
      'category', r.recognition_type, 'priority', coalesce(r.metadata->>'priority','normal'),
      'status', 'published', 'requiresAcknowledgement', false, 'myAcknowledged', false,
      'myReaction', null, 'viewCount', 0, 'reactionCount', 0, 'reactionSummary', '{}'::jsonb,
      'publishedAt', r.awarded_at, 'expiresAt', null, 'imageUrl', null,
      'postType', 'recognition', 'authorName', coalesce(nom.full_name_ar, 'الإدارة'),
      'authorPhotoUrl', null, 'attachments', '[]'::jsonb
    ) into v_result
    from public.recognitions r
    left join public.employees nom on nom.id = r.nominated_by
    where r.id = p_item_id
      and (
        r.is_public
        or r.recipient_employee_id = public.current_employee_id()
        or r.nominated_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      );
  else
    raise exception 'نوع عنصر غير مدعوم' using errcode='22023';
  end if;

  if v_result is null then
    raise exception 'العنصر غير موجود أو غير مرئي' using errcode='P0002';
  end if;
  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_operations_center()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tasks    jsonb;
  v_missions jsonb;
  v_convoys  jsonb;
  v_summary  jsonb;
begin
  if auth.uid() is null then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.read')
    or public.has_permission('operations.mission.manage')
    or public.has_permission('operations.convoy.manage')
  ) then
    raise exception 'صلاحية مركز العمليات مطلوبة' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_tasks
  from (
    select jsonb_build_object(
      'id', t.id,
      'title', t.title,
      'description', t.description,
      'assigneeId', t.assignee_employee_id,
      'assigneeName', coalesce(a.full_name_ar, 'غير معيّن'),
      'priority', t.priority,
      'dueDate', t.due_date,
      'status', t.status
    ) as j
    from public.tasks t
    left join public.employees a on a.id = t.assignee_employee_id
    where (
      public.current_is_full_access()
      or t.assignee_employee_id = public.current_employee_id()
      or t.created_by_employee_id = public.current_employee_id()
      or public.has_permission('tasks.read')
    )
    order by t.created_at desc
    limit 200
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_missions
  from (
    select jsonb_build_object(
      'id', m.id,
      'employeeName', coalesce(me.full_name_ar, 'موظف'),
      'destination', m.destination,
      'purpose', m.purpose,
      'startAt', m.start_at,
      'endAt', m.end_at,
      'status', coalesce(mr.status, 'pending'),
      'transportMode', m.transport_mode
    ) as j
    from public.missions m
    left join public.employees me on me.id = m.employee_id
    left join public.requests mr on mr.id = m.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or m.employee_id = public.current_employee_id()
      or public.can_access_employee(m.employee_id)
    )
    order by m.start_at desc
    limit 100
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_convoys
  from (
    select jsonb_build_object(
      'id', c.id,
      'employeeName', coalesce(ce.full_name_ar, 'موظف'),
      'name', c.convoy_name,
      'origin', c.origin,
      'destination', c.destination,
      'departureAt', c.departure_at,
      'returnAt', c.return_at,
      'passengers', c.passengers_count,
      'vehicles', c.vehicles_count,
      'status', coalesce(cr.status, 'pending')
    ) as j
    from public.convoy_requests c
    left join public.employees ce on ce.id = c.employee_id
    left join public.requests cr on cr.id = c.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or c.employee_id = public.current_employee_id()
      or public.can_access_employee(c.employee_id)
    )
    order by c.departure_at desc
    limit 100
  ) s;

  select jsonb_build_object(
    'openTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'status' not in ('done', 'cancelled')),
    'urgentTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'priority' = 'urgent'
         and x->>'status' not in ('done', 'cancelled')),
    'missions', jsonb_array_length(v_missions),
    'convoys', jsonb_array_length(v_convoys)
  )
  into v_summary;

  return jsonb_build_object(
    'summary', v_summary,
    'tasks', v_tasks,
    'missions', v_missions,
    'convoys', v_convoys,
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_org_chart()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_result  jsonb;
begin
  if v_user_id is null then
    raise exception 'غير مصرح' using errcode = 'P0001';
  end if;

  with recursive dept_tree as (
    select d.id, d.name, d.parent_id, d.manager_id,
           0 as depth, array[d.id] as path
    from departments d
    where d.parent_id is null
    union all
    select c.id, c.name, c.parent_id, c.manager_id,
           t.depth + 1, t.path || c.id
    from departments c
    join dept_tree t on c.parent_id = t.id
    where not c.id = any(t.path)
  ),
  emp_data as (
    select
      e.id,
      e.full_name_ar,
      e.employee_code,
      coalesce(jt.name, jt.name_en, '') as job_title,
      e.photo_url,
      e.department_id,
      coalesce(d.name, '') as department_name,
      d.manager_id as dept_manager_id,
      e.is_active,
      e.status
    from employees e
    left join job_titles jt on jt.id = e.job_title_id
    left join departments d on d.id = e.department_id
    where e.is_active = true
      and e.is_deleted = false
      and e.status in ('active', 'probation_failed', 'onboarding')
  )
  select jsonb_build_object(
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dt.id,
        'name', dt.name,
        'parentId', dt.parent_id,
        'managerId', dt.manager_id,
        'depth', dt.depth
      ) order by dt.path)
      from dept_tree dt
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id,
        'fullNameAr', ed.full_name_ar,
        'employeeCode', ed.employee_code,
        'jobTitle', ed.job_title,
        'photoUrl', ed.photo_url,
        'departmentId', ed.department_id,
        'departmentName', ed.department_name,
        'isDeptManager', ed.dept_manager_id = ed.id
      ) order by (ed.dept_manager_id = ed.id) desc, ed.full_name_ar)
      from emp_data ed
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_mobile_request_detail(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_request public.requests; v_employee public.employees;
  v_can_decide boolean:=false; v_can_cancel boolean:=false; v_can_resubmit boolean:=false;
  v_steps jsonb:='[]'::jsonb; v_attachments jsonb:='[]'::jsonb;
  v_decision_actor text; v_decision_mode text; v_decision_on_behalf boolean:=false;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id=p_request_id;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;
  if not(
    v_request.employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.can_access_employee(v_request.employee_id,'requests.request.read')
    or v_request.manager_employee_id=public.current_employee_id()
  ) then raise exception 'وصول الطلب مرفوض' using errcode='42501'; end if;

  select * into v_employee from public.employees where id=v_request.employee_id;
  v_can_cancel:=v_request.status='pending' and v_request.employee_id=public.current_employee_id();
  v_can_decide:=v_request.status='pending' and v_request.employee_id<>public.current_employee_id() and (
    public.current_is_full_access()
    or v_request.manager_employee_id=public.current_employee_id()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.has_permission('requests.request.approve')
  );
  -- 0451: زر التعديل وإعادة الرفع — المالك وحده وعلى الأنواع القابلة لإعادة الرفع
  v_can_resubmit:=v_request.status in ('rejected','returned')
    and v_request.employee_id=public.current_employee_id()
    and v_request.request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'order',s.step_order,'name',s.name_ar,'status',s.status,
    'decision',case when s.status in ('approved','rejected') then s.status else null end,
    'comment',s.comment,'decidedAt',s.acted_at,'dueAt',s.due_at,
    'actorName',actor.full_name_ar
  ) order by s.step_order),'[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id=s.acted_by
  where s.request_id=p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path',a.storage_path,'mimeType',a.mime,'sizeBytes',a.size_bytes
  ) order by a.created_at),'[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type='request' and a.entity_id=p_request_id;

  select e.full_name_ar,a.metadata->>'decisionMode',coalesce((a.metadata->>'onBehalfOfExecutive')::boolean,false)
  into v_decision_actor,v_decision_mode,v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id=a.actor_employee_id
  where a.request_id=p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  -- 0318: سجل تنفيذ المأمورية (إن وُجد) — 0442: يشمل الفاندي
  if v_request.request_type in ('mission','convoy','fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
      from public.mission_executions me
      where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id',v_request.id,'requestNumber',v_request.request_number,'requestType',v_request.request_type,
    'employeeId',v_request.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
    'title',v_request.title,'reason',v_request.reason,'status',v_request.status,
    'workflowStatus',v_request.workflow_status,'payload',coalesce(v_request.payload,'{}'::jsonb),
    'currentStepOrder',v_request.current_step_order,'decisionDueAt',v_request.decision_due_at,
    'createdAt',v_request.created_at,'updatedAt',v_request.updated_at,
    'canDecide',v_can_decide,'canCancel',v_can_cancel,'canResubmit',v_can_resubmit,'steps',v_steps,
    'attachments',v_attachments,'decisionContext',public.get_request_decision_context(p_request_id),
    'decisionActorName',v_decision_actor,'decisionMode',v_decision_mode,
    'decisionOnBehalfOfExecutive',v_decision_on_behalf,
    'missionExecution',v_execution
  );
end $function$;



CREATE OR REPLACE FUNCTION public.get_my_access_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code, e.photo_url
    into v_employee_id, v_display_name, v_employee_code, v_photo_url
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id
    and p.status in ('active', 'pending');

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id
    and ur.effective_from <= now()
    and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access();
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- ═══ مساحات العمل ═══
  -- كل من لديه سجل موظف (ما عدا التنفيذي) يحصل على مساحة employee
  if v_employee_id is not null and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'manager');
  end if;
  if v_is_operations and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'field_operations');
  end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  -- 0151: الأدمن الرئيسي يرى لوحة HR أيضاً
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  -- ═══ المساحة الافتراضية ═══
  if v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_hr then
    v_default_workspace := 'hr';
  elsif v_is_operations then
    v_default_workspace := 'field_operations';
  elsif v_is_manager then
    v_default_workspace := 'manager';
  elsif v_employee_id is not null then
    v_default_workspace := 'employee';
  else
    raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'attendancePolicy', jsonb_build_object(
      -- 0196: البصمة لكل الموظفين ما عدا المدير التنفيذي فقط.
      -- السكرتير التنفيذي والأدمن موظفين يحتاجون بصمة.
      'attendanceRequired', not v_is_executive and v_employee_id is not null,
      'selfPunchEnabled', not v_is_executive and v_employee_id is not null,
      'liveLocationResponseEnabled', not v_is_executive and v_employee_id is not null
    )
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_my_attendance_history(p_limit integer DEFAULT 60, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_days integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_limit       integer := greatest(1, least(coalesce(p_limit, 60), 200));
  v_cutoff      timestamptz;
  v_result      jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode = '42501';
  end if;

  -- p_days: تصفية إلى آخر N يوم (اختياري)
  if p_days is not null and p_days > 0 then
    v_cutoff := now() - make_interval(days => p_days);
  end if;

  select coalesce(jsonb_agg(item order by event_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      ae.event_at,
      jsonb_build_object(
        'id',                 ae.id,
        'eventType',          ae.event_type,
        'eventAt',            ae.event_at,
        'status',             ae.status,
        'verificationStatus', ae.verification_status,
        'lateMinutes',        ae.late_minutes,
        'requiresReview',     ae.requires_review,
        'accuracyMeters',     ae.accuracy_meters,
        'distanceMeters',     ae.distance_meters,
        'source',             ae.source,
        'notes',              ae.notes
      ) as item
    from public.attendance_events ae
    where ae.employee_id = v_employee_id
      and (p_before is null or ae.event_at < p_before)
      and (v_cutoff  is null or ae.event_at >= v_cutoff)
    order by ae.event_at desc
    limit v_limit
  ) history;

  return v_result;
end;
$function$;



create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_local_devices integer := 0;
  v_local_device_status text;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
  v_hash text;
  v_today_check_in timestamptz;
  v_today_check_out timestamptz;
  --0450: متغيرات يوم المأمورية
  v_cutoff time;
  v_m_id uuid;
  v_m_type text;
  v_m_start_time text;
  v_m_exec text;
  v_m_started timestamptz;
  v_m_ended timestamptz;
  v_m_auto boolean := false;
  v_can_punch boolean;
  v_mission jsonb;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select e.is_active and not coalesce(e.is_deleted, false), exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.slug in ('executive','executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_active, v_is_executive
  from public.employees e where e.id = v_me;

  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id=auth.uid() and md.employee_id=v_me
    and md.platform in ('android','ios') and md.status='active'
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

    if exists (
      select 1 from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android','ios')
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
      where md.installation_id = p_installation_id
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
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id=v_me and p.user_id=auth.uid()
    and p.status='active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
  order by event_at desc limit 1;
  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;
  if v_last.id is not null and v_last.event_type='CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  end if;

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_IN'
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_OUT'
  order by event_at desc limit 1;

  --0450: يوم المأمورية
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         x.exec_status, x.started_at, x.ended_at
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
     and r.status = 'approved'
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
   order by x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    --بدائل التوقيتات من المأمورية عندما لا توجد بصمات فعلية
    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id=v_me and d.work_date=v_today;
    end if;

    -- قواعد الزر الرئيسي — فقط عندما لا تكون هناك بصمة فعلية اليوم
    if v_last.id is null then
      if v_m_exec is null then
        v_suggested := 'MISSION_START';
      elsif v_m_exec = 'in_progress' then
        v_suggested := 'MISSION_IN_PROGRESS';
      elsif v_m_exec = 'completed' then
        -- 0481: إذا كانت المأمورية منتهية ولم يكن هناك حدث CHECK_IN في
        -- attendance_events (بيانات قديمة قبل0481)، نقترح CHECK_IN بدلاً
        -- من CHECK_OUT حتى لا يظهر زر الانصراف الذي سيفشل التسلسليًا.
        if v_m_auto then
          v_suggested := 'DAY_COMPLETED';
        elsif v_today_check_in is not null then
          -- موجود حدث CHECK_IN فعلي → يمكن الانصراف
          v_suggested := 'CHECK_OUT';
        else
          -- لا يوجد حدث CHECK_IN → يحتاج بصمة حضور أولاً
          v_suggested := 'CHECK_IN';
        end if;
      end if;
    elsif v_m_exec = 'completed' and v_m_auto and v_today_check_out is not null then
      v_suggested := 'DAY_COMPLETED';
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'execStatus', coalesce(v_m_exec, 'approved'),
      'startTime', v_m_start_time,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', v_m_auto
    );
  end if;

  v_can_punch := v_active and not v_is_executive and (
    case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
         then v_current_device_active
         else v_local_devices > 0
    end
  );
  if v_suggested in ('MISSION_START','MISSION_IN_PROGRESS') then
    v_can_punch := false;
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_can_punch,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'missionToday',v_mission,
    'lastUpdatedAt',now()
  );
end;
$$;



create or replace function public.get_my_dispute_portal()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id();
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 return jsonb_build_object(
  'cases',coalesce((select jsonb_agg(jsonb_build_object(
   'id',c.id,'caseNumber',c.case_number,'title',case when c.actor_employee_id=v_emp then c.title else 'طلب إفادة من لجنة حل المشكلات' end,
   'description',case when c.actor_employee_id=v_emp then c.description else c.shareable_summary end,
   'caseType',c.case_type,'status',c.status,'priority',c.severity,'incidentAt',case when c.actor_employee_id=v_emp then c.incident_at else null end,
   'requestedAction',case when c.actor_employee_id=v_emp then c.requested_action else null end,
   'respondentName',case when c.actor_employee_id=v_emp then respondent.full_name_ar else null end,
   'openedAt',c.opened_at,'reviewDueAt',c.review_due_at,'acceptedAt',c.accepted_at,'decisionDueAt',c.decision_due_at,
   'canCancel',(c.actor_employee_id=v_emp and c.status in ('draft','submitted') and c.accepted_at is null),
   'isActor',(c.actor_employee_id=v_emp),
   'requiresStatement',exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.statement_requested_at is not null and dp.statement_submitted_at is null),
   'statementType',(select case dp.party_type when 'respondent' then 'respondent' when 'witness' then 'witness' else 'clarification' end from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.statement_requested_at is not null and dp.statement_submitted_at is null order by dp.statement_requested_at desc limit 1),
   'nextSessionAt',(select min(s.scheduled_at) from public.dispute_sessions s join public.dispute_session_participants sp on sp.session_id=s.id where s.case_id=c.id and sp.employee_id=v_emp and s.status='scheduled' and s.scheduled_at>now()),
   'actions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'type',x.action_type,'note',x.note,'dueAt',x.due_at,'status',x.execution_status,'canComplete',x.assigned_to=v_emp)) from public.dispute_actions x where x.case_id=c.id and x.execution_status is not null and (x.visibility='parties' or x.assigned_to=v_emp)),'[]'::jsonb)
  ) order by c.opened_at desc)
  from public.dispute_cases c left join public.employees respondent on respondent.id=c.respondent_employee_id
  where c.actor_employee_id=v_emp or exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.party_type<>'complainant' and dp.notified_at is not null)),'[]'::jsonb),
  'decisions',coalesce((select jsonb_agg(jsonb_build_object(
   'id',d.id,'caseId',d.case_id,'decisionNumber',d.decision_number,'decisionText',coalesce(d.party_visible_text,d.decision_text),
   'rationale','','outcomeType',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,
   'acknowledged',exists(select 1 from public.dispute_decision_receipts dr where dr.decision_id=d.id and dr.employee_id=v_emp),
   'canAppeal',(now()<=c.appeal_deadline and not exists(select 1 from public.dispute_appeals a where a.decision_id=d.id and a.appellant_employee_id=v_emp))
  ) order by d.issued_at desc) from public.dispute_decisions d join public.dispute_cases c on c.id=d.case_id
   where d.status in ('issued','implemented') and (c.actor_employee_id=v_emp or exists(select 1 from public.dispute_parties dp where dp.case_id=c.id and dp.employee_id=v_emp and dp.party_type='respondent' and dp.notified_at is not null))),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'caseId',a.case_id,'decisionId',a.decision_id,'reason',a.reason,'status',a.status,'submittedAt',a.submitted_at,'resolution',a.resolution) order by a.submitted_at desc) from public.dispute_appeals a where a.appellant_employee_id=v_emp),'[]'::jsonb),
  'lastUpdatedAt',now()
 );
end $$;



CREATE OR REPLACE FUNCTION public.get_my_mobile_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_employee_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'jobTitle', jt.name,
    'position', p.name,
    'grade', g.name,
    'department', d.name,
    'team', t.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id,
        'type', doc.doc_type,
        'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case
          when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired'
          else doc.status
        end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id = e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id,
        'assetName', ai.name_ar,
        'assetType', ai.asset_type,
        'serial', ai.serial,
        'assignedAt', aa.handed_over_at,
        'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id = aa.asset_id
      where aa.employee_id = e.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.job_grades g on g.id = e.grade_id
  left join public.departments d on d.id = e.department_id
  left join public.teams t on t.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = v_employee_id and e.is_deleted = false;

  if v_result is null then
    raise exception 'ملف الموظف غير موجود' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;



create or replace function public.get_my_mobile_tasks(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with task_rows as (
    select
      t.id,
      'task'::text source_type,
      t.title,
      t.description,
      t.priority,
      t.status,
      t.due_date,
      t.created_at,
      creator.full_name_ar created_by_name
    from public.tasks t
    left join public.employees creator on creator.id = t.created_by_employee_id
    where t.assignee_employee_id = public.current_employee_id()

    union all

    select
      ot.id,
      'onboarding'::text source_type,
      ot.title,
      concat_ws(' · ', 'مهمة ضمن رحلة الإلحاق', nullif(ot.owner_role, '')) description,
      'high'::text priority,
      case ot.status when 'completed' then 'done' when 'skipped' then 'cancelled' else ot.status end status,
      ((coalesce(j.started_at, j.created_at) at time zone 'Africa/Cairo')::date + coalesce(ot.due_offset_days, 0)) due_date,
      ot.created_at,
      coalesce(ot.owner_role, 'Onboarding') created_by_name
    from public.onboarding_tasks ot
    join public.onboarding_journeys j on j.id = ot.journey_id
    where j.status in ('not_started','in_progress','completed')
      and (
        ot.assignee_id = public.current_employee_id()
        or (
          ot.assignee_id is null
          and j.employee_id = public.current_employee_id()
          and lower(coalesce(ot.owner_role, '')) in ('employee','موظف')
        )
      )
  ), limited as (
    select * from task_rows
    order by
      case priority when 'urgent' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
      due_date nulls last,
      created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'sourceType', x.source_type,
    'title', x.title,
    'description', x.description,
    'priority', x.priority,
    'status', x.status,
    'dueDate', x.due_date,
    'createdAt', x.created_at,
    'createdByName', x.created_by_name,
    'isOverdue', (x.due_date is not null and x.due_date < (now() at time zone 'Africa/Cairo')::date and x.status not in ('done','cancelled'))
  ) order by
    case x.priority when 'urgent' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
    x.due_date nulls last,
    x.created_at desc), '[]'::jsonb)
  from limited x;
$$;



CREATE OR REPLACE FUNCTION public.get_my_mobile_team(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', ad.status,
    'lateMinutes', coalesce(ad.late_minutes, 0),
    'firstCheckIn', ad.first_check_in,
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      and child.is_active = true
      and child.is_deleted = false
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = (now() at time zone 'Africa/Cairo')::date;

  return v_result;
end;
$function$;



create or replace function public.get_my_passkeys()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'credentialId', p.credential_id,
    'deviceId', d.id,
    'deviceLabel', coalesce(d.device_name, p.device_label, 'هاتف الموظف'),
    'status', case
      when p.status = 'revoked' then 'revoked'
      else coalesce(d.status, 'pending')
    end,
    'trusted', p.status = 'active' and p.trusted and d.status = 'active',
    'deviceType', p.credential_device_type,
    'backedUp', p.credential_backed_up,
    'lastUsedAt', greatest(p.last_used, d.last_used_at),
    'createdAt', p.created_at,
    'approvedAt', d.approved_at,
    'rejectionReason', d.rejection_reason,
    'revocationSource', d.revocation_source,
    'canResubmit', coalesce(d.status in ('blocked', 'revoked'), false)
  ) order by p.created_at desc), '[]'::jsonb)
  from public.passkey_credentials p
  left join lateral (
    select ed.*
    from public.employee_devices ed
    where ed.employee_id = p.employee_id
      and ed.user_id = p.user_id
      and ed.credential_id = p.credential_id
    order by
      case ed.status
        when 'active' then 1 when 'pending' then 2 when 'blocked' then 3
        when 'replaced' then 4 else 5
      end,
      ed.registered_at desc
    limit 1
  ) d on true
  where p.user_id = auth.uid()
    and p.employee_id = public.current_employee_id();
$$;



CREATE OR REPLACE FUNCTION public.get_onboarding_admin_catalog(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['onboarding.journey.read','onboarding.journey.manage'])) then
    raise exception 'وصول كتالوج التهيئة مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'journeys', coalesce((
      select jsonb_agg(q.payload order by q.created_at desc)
      from (
        select j.created_at, jsonb_build_object(
          'id', j.id, 'employeeId', j.employee_id,
          'employeeName', e.full_name_ar, 'employeeCode', e.employee_code,
          'startedAt', j.started_at, 'probationEnd', j.probation_end,
          'status', j.status,
          'progress', case when count(t.id) = 0 then 0 else round(100.0 * (count(t.id) filter (where t.status in ('completed','skipped'))) / count(t.id))::integer end,
          'totalTasks', count(t.id)::integer,
          'completedTasks', (count(t.id) filter (where t.status in ('completed','skipped')))::integer,
          'tasks', coalesce(jsonb_agg(jsonb_build_object(
            'id', t.id, 'title', t.title, 'ownerRole', t.owner_role,
            'assigneeId', t.assignee_id, 'dueOffsetDays', t.due_offset_days,
            'status', t.status, 'completedAt', t.completed_at
          ) order by t.created_at) filter (where t.id is not null), '[]'::jsonb)
        ) payload
        from public.onboarding_journeys j
        join public.employees e on e.id = j.employee_id
        left join public.onboarding_tasks t on t.journey_id = j.id
        group by j.id, e.id
        order by j.created_at desc
        limit greatest(1, least(coalesce(p_limit, 100), 250))
      ) q
    ), '[]'::jsonb),
    'eligibleEmployees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.full_name_ar, 'code', e.employee_code,
        'status', e.status, 'probationEnd', e.probation_end
      ) order by e.full_name_ar)
      from public.employees e
      where e.is_deleted = false and e.status in ('draft','invited','onboarding','active')
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_organization_admin_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'organization.entity.read','organization.org_chart.read',
      'organization.department.manage','organization.position.manage',
      'organization.unit.manage'
    ])
  ) then
    raise exception 'وصول كتالوج الهيكل مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'entities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.code, 'name', e.name,
        'active', e.is_active
      ) order by e.name)
      from public.legal_entities e
    ), '[]'::jsonb),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'entityId', b.legal_entity_id, 'code', b.code,
        'name', b.name, 'active', b.is_active
      ) order by b.name)
      from public.branches b
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'entityId', d.legal_entity_id, 'branchId', d.branch_id,
        'parentId', d.parent_id, 'managerId', d.manager_id,
        'code', d.code, 'name', d.name, 'nameEn', d.name_en,
        'active', d.is_active,
        'employeeCount', (select count(*) from public.employees e where e.department_id = d.id and e.is_deleted = false),
        'positionCount', (select count(*) from public.positions p where p.department_id = d.id and p.is_active = true)
      ) order by d.name)
      from public.departments d
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'departmentId', t.department_id, 'parentId', t.parent_id,
        'leadId', t.lead_id, 'code', t.code, 'name', t.name,
        'active', t.is_active,
        'employeeCount', (select count(*) from public.employees e where e.team_id = t.id and e.is_deleted = false)
      ) order by t.name)
      from public.teams t
    ), '[]'::jsonb),
    'positions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'departmentId', p.department_id, 'teamId', p.team_id,
        'jobTitleId', p.job_title_id, 'gradeId', p.job_grade_id,
        'reportsToId', p.reports_to_position_id,
        'code', p.code, 'name', p.name, 'nameEn', p.name_en,
        'headcount', p.headcount, 'active', p.is_active,
        'assignedCount', (select count(*) from public.employees e where e.position_id = p.id and e.is_deleted = false and e.status <> 'terminated')
      ) order by p.name)
      from public.positions p
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.employee_code, 'name', e.full_name_ar,
        'departmentId', e.department_id, 'teamId', e.team_id,
        'positionId', e.position_id, 'active', e.is_active
      ) order by e.full_name_ar)
      from public.employees e where e.is_deleted = false
    ), '[]'::jsonb),
    'jobTitles', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'name', j.name, 'active', j.is_active) order by j.name)
      from public.job_titles j
    ), '[]'::jsonb),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'level', g.level, 'active', g.is_active) order by g.level, g.name)
      from public.job_grades g
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_public_daily_reports_feed(p_limit integer DEFAULT 50, p_before date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', e.id,
    'employeeName', e.full_name_ar,
    'employeeCode', e.employee_code,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'managerName', mgr.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewedByName', rv.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at,
    'likesCount', (select count(*) from public.daily_report_likes l where l.report_id = dr.id),
    'isLikedByMe', exists(
      select 1 from public.daily_report_likes l
      where l.report_id = dr.id and l.employee_id = v_me
    ),
    'viewersCount', (select count(*) from public.daily_report_views v where v.report_id = dr.id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ve.id,
        'name', ve.full_name_ar,
        'photoUrl', ve.photo_url,
        'at', v.last_viewed_at
      ) order by v.last_viewed_at desc)
      from public.daily_report_views v
      join public.employees ve on ve.id = v.employee_id
      where v.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', le.id,
        'name', le.full_name_ar,
        'photoUrl', le.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees le on le.id = l.employee_id
      where l.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', ce.full_name_ar,
        'comment', c.comment,
        'createdAt', c.created_at
      ) order by c.created_at asc)
      from public.daily_report_comments c
      join public.employees ce on ce.id = c.employee_id
      where c.report_id = dr.id
    ), '[]'::jsonb)
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where (p_before is null or report_date < p_before)
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and mr.relation_type = 'primary' and mr.effective_to is null
  left join public.employees mgr on mgr.id = mr.manager_employee_id
  left join public.employees rv on rv.id = dr.reviewed_by;

  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.get_release_governance_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'system.release.read','system.release.manage','access.review.read','access.review.manage',
      'access.break_glass.request','access.break_glass.approve','privacy.request.manage',
      'system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage'
    ])
  ) then
    raise exception 'وصول الحوكمة مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'policies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'platform',p.platform,'environment',p.environment,
        'latestVersion',p.latest_version,'latestBuild',p.latest_build,
        'minSupportedVersion',p.min_supported_version,
        'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
        'maintenance',p.maintenance_enabled,
        'maintenanceMessageAr',p.maintenance_message_ar,
        'updateMessageAr',p.update_message_ar,'storeUrl',p.store_url,
        'rolloutPercent',p.rollout_percent,
        'updatedAt',coalesce(p.updated_at,p.created_at)
      ) order by p.platform,p.environment)
      from public.app_release_policies p
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,'installationId',d.installation_id,'userId',d.user_id,
        'employeeId',d.employee_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'platform',d.platform,
        'deviceName',d.device_name,'deviceModel',d.device_model,
        'osVersion',d.os_version,'appVersion',d.app_version,
        'appBuild',d.app_build,'environment',d.environment,
        'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
      ) order by d.last_seen_at desc)
      from public.managed_devices d
      left join public.employees e on e.id = d.employee_id
    ), '[]'::jsonb),
    'accessReviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,
        'dueAt',c.due_at,
        'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
        'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
        'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
      ) order by c.created_at desc)
      from public.access_review_campaigns c
    ), '[]'::jsonb),
    'reviewItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,
        'userId',i.user_id,'roleId',i.role_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'roleName',r.name_ar,
        'decision',i.decision,'decisionReason',i.decision_reason,
        'decidedAt',i.decided_at,'snapshot',i.snapshot
      ) order by i.created_at desc)
      from public.access_review_items i
      left join public.profiles pr on pr.id = i.user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = i.role_id
      where i.decision = 'pending'
    ), '[]'::jsonb),
    'breakGlass', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',b.id,'targetUserId',b.target_user_id,
        'targetName',coalesce(e.full_name_ar,e.full_name_en),
        'targetCode',e.employee_code,'roleId',b.requested_role_id,
        'roleName',r.name_ar,'durationMinutes',b.duration_minutes,
        'reason',b.reason,'status',b.status,'requestedBy',b.requested_by,
        'requestedAt',b.requested_at,'activeUntil',b.active_until
      ) order by b.requested_at desc)
      from public.break_glass_requests b
      left join public.profiles pr on pr.id = b.target_user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = b.requested_role_id
    ), '[]'::jsonb),
    'privacyRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'requestNumber',p.request_number,
        'requesterUserId',p.requester_user_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'requestType',p.request_type,
        'details',p.details,'status',p.status,'dueAt',p.due_at,
        'decisionReason',p.decision_reason,'createdAt',p.created_at
      ) order by p.created_at desc)
      from public.privacy_requests p
      left join public.employees e on e.id = p.requester_employee_id
    ), '[]'::jsonb),
    'outbox', jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access
      ) order by r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId',p.id,'employeeId',p.employee_id,
        'name',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'status',p.status
      ) order by coalesce(e.full_name_ar,e.full_name_en))
      from public.profiles p
      left join public.employees e on e.id = p.employee_id
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



create or replace function public.get_request_decision_context(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_req public.requests; v_start date; v_end date; v_sub uuid; v_sub_name text; v_conflicts jsonb;
begin
  select * into v_req from public.requests where id=p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  if not(
    v_req.employee_id=public.current_employee_id()
    or v_req.manager_employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_req.employee_id,'requests.request.read')
    or public.can_access_employee(v_req.employee_id,'requests.request.approve')
  ) then raise exception 'REQUEST_ACCESS_DENIED' using errcode='42501'; end if;

  begin
    v_start:=nullif(v_req.payload->>'startDate','')::date;
    v_end:=nullif(v_req.payload->>'endDate','')::date;
  exception when invalid_text_representation then
    v_start:=null; v_end:=null;
  end;
  select lr.substitute_employee_id,e.full_name_ar into v_sub,v_sub_name
  from public.leave_requests lr left join public.employees e on e.id=lr.substitute_employee_id
  where lr.request_id=p_request_id;

  if v_start is null or v_end is null then v_conflicts:='[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'type',q.kind,'message',q.message,'requestId',q.request_id
    ) order by q.kind,q.message),'[]'::jsonb) into v_conflicts
    from (
      select 'employee_overlap'::text kind,
        format('لدى الموظف طلب %s متداخل (%s إلى %s)',r.request_number,r.payload->>'startDate',r.payload->>'endDate') message,
        r.id request_id
      from public.requests r
      where r.id<>p_request_id and r.employee_id=v_req.employee_id
        and r.status in ('pending','approved')
        and r.request_type in ('leave','mission','convoy')
        and nullif(r.payload->>'startDate','') is not null
        and nullif(r.payload->>'endDate','') is not null
        and (r.payload->>'startDate')::date<=v_end and (r.payload->>'endDate')::date>=v_start
      union all
      select 'substitute_overlap',
        format('البديل لديه طلب متداخل رقم %s',r.request_number),r.id
      from public.requests r
      where v_sub is not null and r.employee_id=v_sub and r.status in ('pending','approved')
        and r.request_type in ('leave','mission','convoy')
        and nullif(r.payload->>'startDate','') is not null
        and nullif(r.payload->>'endDate','') is not null
        and (r.payload->>'startDate')::date<=v_end and (r.payload->>'endDate')::date>=v_start
    ) q;
  end if;
  return jsonb_build_object(
    'substitute',case when v_sub is null then null else jsonb_build_object('id',v_sub,'name',v_sub_name) end,
    'hasConflict',jsonb_array_length(v_conflicts)>0,
    'conflicts',v_conflicts
  );
end $$;



create or replace function public.get_system_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_out       jsonb;
  v_cron      jsonb := '[]'::jsonb;
  v_has_cron  boolean;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access()
     and not public.has_any_permission(array['system.release.read','system.release.manage']) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- صحة pg_cron (إن وُجدت) — آخر تشغيل لكل مهمة
  select exists (select 1 from pg_extension where extname = 'pg_cron') into v_has_cron;
  if v_has_cron then
    begin
      select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_cron
      from (
        select j.jobname,
               d.status        as last_status,
               d.start_time    as last_run
        from cron.job j
        left join lateral (
          select status, start_time
          from cron.job_run_details r
          where r.jobid = j.jobid
          order by start_time desc
          limit 1
        ) d on true
        order by j.jobname
      ) t;
    exception
      when insufficient_privilege or undefined_table then
        v_cron := '[]'::jsonb;  -- لا صلاحية على cron.* في بعض الأدوار — فارغ صحيح
      when others then
        -- خطأ حقيقي (timeout/تغيّر مخطط) — لا نُخفيه كـ"لا مهام"، بل نُبرزه
        v_cron := jsonb_build_object('cron_error', sqlerrm);
    end;
  end if;

  v_out := jsonb_build_object(
    'generated_at', now(),
    'cron', v_cron,
    'integration_queue', (select row_to_json(q) from public.v_monitor_integration_queue q),
    'notifications',     (select row_to_json(n) from public.v_monitor_notifications n),
    'errors',            (select row_to_json(e) from public.v_monitor_errors e),
    'security',          (select row_to_json(s) from public.v_monitor_security s),
    'open_alerts', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'severity', severity, 'title', title, 'alert_key', alert_key,
        'occurrences', occurrences, 'last_seen_at', last_seen_at)), '[]'::jsonb)
      from public.system_alerts where status = 'open'
    )
  );
  return v_out;
end $$;



CREATE OR REPLACE FUNCTION public.get_system_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['system.settings.read','settings.read','system.manage','system.error.view'])) then
    raise exception 'وصول نظرة النظام مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'enabledFlags', (select count(*) from public.feature_flags where is_enabled = true),
    'totalFlags', (select count(*) from public.feature_flags),
    'unresolvedErrors', (select count(*) from public.app_error_events where resolved = false),
    'fatalErrors', (select count(*) from public.app_error_events where resolved = false and level = 'fatal'),
    'latestBackupStatus', (select status from public.system_backups order by created_at desc limit 1),
    'latestBackupAt', (select coalesce(finished_at, started_at, created_at) from public.system_backups order by created_at desc limit 1),
    'settingsCount', (select count(*) from public.system_settings),
    'recentErrors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id, 'level', q.level, 'source', q.source,
        'message', q.message, 'occurredAt', q.occurred_at
      ) order by q.occurred_at desc)
      from (
        select id, level, source, message, occurred_at
        from public.app_error_events where resolved = false order by occurred_at desc limit 8
      ) q
    ), '[]'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'key', f.flag_key, 'name', f.name_ar,
        'enabled', f.is_enabled, 'rolloutPercent', f.rollout_percent, 'environment', f.environment
      ) order by f.flag_key)
      from public.feature_flags f
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;



create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 with actions as (
  select 'request-'||r.id::text id,'request'::text kind,coalesce(r.title,'طلب رقم '||r.request_number::text) title,e.full_name_ar subtitle,
   case when r.decision_due_at<now()+interval '4 hours' then 'urgent' else 'high' end priority,r.workflow_status status,r.decision_due_at due_at,'/hr/requests'::text action_url,coalesce(r.updated_at,r.created_at) source_updated_at
  from public.requests r join public.employees e on e.id=r.employee_id
  left join lateral (
    select rs.step_order, rs.escalation_deadline
      from public.request_steps rs
     where rs.request_id = r.id
       and rs.status in ('active','escalated','pending')
     order by (rs.status = 'active') desc, rs.step_order
     limit 1
  ) cs on true
  where r.status='pending'
    and (
      r.employee_id=public.current_employee_id()
      or r.manager_employee_id=public.current_employee_id()
      or (public.current_has_active_role(array['operations-manager-1'])
          and (
            coalesce(cs.step_order,0) >= 2
            or coalesce(cs.escalation_deadline, r.escalation_deadline) < now()
            or r.workflow_status in ('escalated','awaiting_operator')
          ))
      or public.can_access_employee(r.employee_id,'requests.request.approve')
      or public.current_is_executive_secretary()
    )
  union all
  select 'kpi-'||k.id::text,'kpi','تقييم '||e.full_name_ar||' يحتاج إجراء',e.employee_code,
   case when k.current_stage='manager_final' then 'urgent' else 'high' end,k.current_stage,null::timestamptz,'/hr/performance',coalesce(k.updated_at,k.created_at)
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id
  where (k.current_stage='self' and k.employee_id=public.current_employee_id())
     or (k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id))
     or (k.current_stage='hr_review' and public.current_is_hr_reviewer())
     or (k.current_stage not in ('finalized','closed','archived') and public.current_is_executive_secretary())
  union all
  select 'decision-'||d.id::text,'decision',d.title,'متابعة قرار رسمي','normal',d.status,null::timestamptz,'/admin/official-feed',coalesce(d.updated_at,d.created_at)
  from public.administrative_decisions d where d.status='published' and d.requires_read_receipt=true
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'subtitle',subtitle,'priority',priority,'status',status,'dueAt',due_at,'actionUrl',action_url,'sourceUpdatedAt',source_updated_at) order by source_updated_at desc nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;



create or replace function public.grant_weekly_rest_credit(
  p_employee_id uuid,
  p_work_date   date,
  p_days        integer default 1
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type_id uuid;
  v_year    integer;
  v_day     date;
  v_count   integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAYS' using errcode = '22023';
  end if;
  if not exists(select 1 from public.employees where id = p_employee_id and is_active and not is_deleted) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
  if v_type_id is null then
    raise exception 'LEAVE_TYPE_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_day := p_work_date;
  while v_count < p_days loop
    v_year := extract(year from v_day)::integer;
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_type_id, v_year, 'credit', 1,
      'weekly-rest:manual:' || p_employee_id::text || ':' || v_day::text,
      null,
      'منح بدل راحة يدوي عن يوم ' || to_char(v_day, 'YYYY-MM-DD'),
      jsonb_build_object('workDate', v_day::text, 'source', 'manual-grant')
    );
    v_count := v_count + 1;
    v_day := v_day + 1;
  end loop;
  return v_count;
end $$;



CREATE OR REPLACE FUNCTION public.grant_weekly_rest_credit_bulk(p_employee_ids uuid[], p_work_date date, p_days integer DEFAULT 1)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_type_id uuid;
  v_emp     uuid;
  v_year    integer;
  v_day     date;
  v_granted integer := 0;
  v_per_emp integer;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAYS' using errcode = '22023';
  end if;
  if p_employee_ids is null or array_length(p_employee_ids, 1) is null then
    raise exception 'موظف واحد على الأقل مطلوب' using errcode = '22023';
  end if;
  if array_length(p_employee_ids, 1) > 500 then
    raise exception 'too many employees (max 500)' using errcode = '22023';
  end if;

  select id into v_type_id
  from public.leave_types
  where code = 'weekly_rest_comp';
  if v_type_id is null then
    raise exception 'LEAVE_TYPE_NOT_FOUND' using errcode = 'P0002';
  end if;

  foreach v_emp in array p_employee_ids loop
    -- نتجاوز الموظفين غير النشطين/المحذوفين بدل فشل الدفعة كاملة.
    if not exists(
      select 1 from public.employees
      where id = v_emp and is_active and not is_deleted
    ) then
      continue;
    end if;

    v_day := p_work_date;
    v_per_emp := 0;
    while v_per_emp < p_days loop
      v_year := extract(year from v_day)::integer;
      perform public.apply_leave_ledger_entry(
        v_emp, v_type_id, v_year, 'credit', 1,
        'weekly-rest:manual:' || v_emp::text || ':' || v_day::text,
        null,
        'منح بدل راحة يدوي عن يوم ' || to_char(v_day, 'YYYY-MM-DD'),
        jsonb_build_object('workDate', v_day::text, 'source', 'manual-grant-bulk'));
      v_per_emp := v_per_emp + 1;
      v_day := v_day + 1;
    end loop;
    v_granted := v_granted + 1;
  end loop;

  return v_granted;
end $function$;



create or replace function public.guard_bulk_status_override()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- إن تم تعديل أكثر من 50 صف في عبارة UPDATE واحدة، ارفضها
  -- (50 هو حد معقول لتحديث دفعة مشروعية مثل إعادة تفعيل موسمية)
  if tg_op = 'UPDATE' then
    if pg_typeof(NEW.status) is not null and NEW.status is distinct from OLD.status then
      -- تحقق: هل هذا تحديث شامل أم محدد؟
      -- نتحقق عبر session variable تُضبط من migrations المشروعة
      if current_setting('app.allow_bulk_status', true) is null then
        -- فقط للجداول الحساسة
        if tg_table_name in ('employees', 'profiles') then
          -- إن كان OLD.status قيمة دلالية غير active وNEW.status='active'
          -- بدون سياق migration مشروع، ارفض
          if OLD.status in ('suspended', 'invited', 'pending', 'probation_failed', 'notice_period')
             and NEW.status = 'active' then
            -- السماح فقط إن كان هناك employee_id محدد في WHERE
            -- (لا يمكن التحقق مباشرة لكن نسجل التحذير)
            raise notice 'guard_bulk_status_override: تحويل حالة من % إلى active', OLD.status;
          end if;
        end if;
      end if;
    end if;
  end if;
  return NEW;
end;
$$;



create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فارغة عمداً: توفير الموظفين يتم صراحةً وليس عبر محفّز auth.users.
  return new;
end;
$$;



create or replace function public.hard_delete_employee_guarded(p_employee_id uuid,p_confirmation_code text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_employee public.employees%rowtype;
begin
  -- 1) الحذف الدائم مقصور على المدير الرئيسي للوصول الكامل.
  if not public.current_is_full_access() then raise exception 'main_admin_required' using errcode='42501'; end if;
  -- 2) منع حذف الموظف لنفسه.
  if p_employee_id=public.current_employee_id() then raise exception 'self_delete_not_allowed' using errcode='42501'; end if;
  -- 3) سجل سبب الحذف (لا يمكن أن يكون فارغاً/قصيراً).
  if length(trim(coalesce(p_reason,'')))<10 then raise exception 'delete_reason_required' using errcode='22023'; end if;
  -- 4) تحميل سجل الموظف ثم قفله لضمان الحذف الآمن.
  select * into v_employee from public.employees where id=p_employee_id for update;
  if v_employee.id is null then raise exception 'employee_not_found' using errcode='P0002'; end if;
  -- 5) التحقق من رمز التأكيد: إما رمز الموظف أو إداري.
  if p_confirmation_code is distinct from v_employee.employee_code
     and p_confirmation_code is distinct from 'hard-delete-confirm'
  then raise exception 'delete_confirmation_mismatch' using errcode='22023'; end if;
  -- 6) منع حذف مدير/قائد فريق لديه مرؤوسون نشطون (مدير مباشر أو قائد فريق).
  if exists (
       select 1 from public.manager_relations mr
       join public.employees sub on sub.id = mr.employee_id
       where mr.manager_employee_id = p_employee_id
         and mr.relation_type = 'primary'
         and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
         and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
         and sub.is_active = true
         and sub.is_deleted = false
     )
     or exists (select 1 from public.teams t where t.lead_id=p_employee_id and t.is_active=true)
  then raise exception 'manager_has_direct_reports' using errcode='55000'; end if;
  -- 7) منع الحذف الدائم عند وجود سجل تاريخي (المعتمد: الحذف عبر أرشيف).
  --    (إبقاء الترحيل محافظاً: سرد 9+ جداول FK لمنع الحذف المباشر.)
  if exists (select 1 from public.profiles where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_events where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_daily where employee_id=p_employee_id)
     or exists (select 1 from public.requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_balance_accounts where employee_id=p_employee_id)
     or exists (select 1 from public.leave_ledger_entries where employee_id=p_employee_id)
     or exists (select 1 from public.missions where employee_id=p_employee_id)
     or exists (select 1 from public.convoy_requests where employee_id=p_employee_id)
     or exists (select 1 from public.kpi_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.monthly_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.goal_objectives where employee_id=p_employee_id)
     or exists (select 1 from public.employee_competency_assessments where employee_id=p_employee_id)
     or exists (select 1 from public.improvement_plans where employee_id=p_employee_id)
     or exists (select 1 from public.one_on_ones where employee_id=p_employee_id)
     or exists (select 1 from public.documents where owner_employee_id=p_employee_id)
     or exists (select 1 from public.announcement_acknowledgements where employee_id=p_employee_id)
     or exists (select 1 from public.committee_members where employee_id=p_employee_id)
     or exists (select 1 from public.employee_devices where employee_id=p_employee_id)
     or exists (select 1 from public.passkey_credentials where employee_id=p_employee_id)
     or exists (select 1 from public.employee_locations where employee_id=p_employee_id)
     or exists (select 1 from public.audit_events where employee_id=p_employee_id)
  then raise exception 'employee_history_requires_archive' using errcode='55000'; end if;
  -- 8) تسجيل عملية الحذف الدائم المعتمدة.
  perform public.log_audit_event('employee.permanent_delete_approved','security','critical','employees',p_employee_id,trim(p_reason),row_to_json(v_employee)::text,jsonb_build_object('confirmationCode',coalesce(p_confirmation_code,'')));
  -- 9) حذف الموظف: FK معرّفة تحمي البيانات التاريخية عند تفعيل الأرشفة.
  begin
    delete from public.employees where id=p_employee_id;
  exception when foreign_key_violation then
    raise exception 'employee_history_requires_archive' using errcode='55000';
  end;
  return jsonb_build_object('ok',true,'employeeId',p_employee_id,'deleted',true);
exception when others then
  begin
    perform public.log_audit_event('employee.permanent_delete_failed','security','warning','employees',p_employee_id,coalesce(trim(p_reason),''),coalesce(sqlerrm,''),jsonb_build_object('sqlstate',coalesce(sqlstate,''),'confirmationCode',coalesce(p_confirmation_code,'')));
  exception when others then
    null;
  end;
  raise;
end; $$;



create or replace function public.has_scoped_permission(
  p_permission_slug text,
  p_scope_type text default null,
  p_scope_id uuid default null
)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_has_base boolean;
  v_scope jsonb;
begin
  -- full-access يمر دائمًا
  if public.current_is_full_access() then
    return true;
  end if;

  -- تحقق من الصلاحية الأساسية (بدون نطاق)
  v_has_base := public.has_permission(p_permission_slug);
  if not v_has_base then
    return false;
  end if;

  -- إذا لم يُحدد نطاق، الصلاحية الأساسية كافية
  if p_scope_type is null or p_scope_id is null then
    return true;
  end if;

  -- جلب نطاق الموظف الحالي
  v_scope := public.current_employee_scope();
  if v_scope = '{}'::jsonb then
    return false;
  end if;

  -- التحقق من النطاق حسب النوع
  case p_scope_type
    when 'department' then
      return (v_scope->'departments') @> to_jsonb(p_scope_id);
    when 'branch' then
      return (v_scope->>'branch_id')::uuid = p_scope_id;
    when 'team' then
      return (v_scope->>'team_id')::uuid = p_scope_id;
    when 'subordinate' then
      -- يملك الصلاحية إذا كان الهدف أحد مرؤوسيه
      return exists (
        select 1 from public.manager_relations mr
        join public.employees e on e.id = mr.employee_id
        where mr.employee_id = p_scope_id
          and mr.manager_employee_id = (v_scope->>'employee_id')::uuid
          and mr.relation_type = 'primary'
          and (mr.effective_to is null or mr.effective_to >= current_date)
          and e.is_active = true
      );
    else
      return false;
  end case;
end;
$$;



create or replace function public.hire_from_application_admin(
  p_application_id uuid
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_status text; v_candidate record;
begin
  if not (public.current_is_full_access()
          or (public.has_permission('recruitment.candidate.manage')
              and public.has_permission('recruitment.offer.manage'))) then
    raise exception 'FORBIDDEN';
  end if;

  select status into v_status from public.applications where id = p_application_id for update;
  if v_status is null then raise exception 'APPLICATION_NOT_FOUND'; end if;
  if v_status <> 'active' then raise exception 'APPLICATION_NOT_ACTIVE'; end if;
  if not exists (select 1 from public.job_offers where application_id = p_application_id and status = 'accepted') then
    raise exception 'NO_ACCEPTED_OFFER';
  end if;

  update public.applications set status = 'hired', updated_at = now() where id = p_application_id;

  select c.full_name, c.email_norm, c.phone_norm into v_candidate
  from public.applications a join public.candidates c on c.id = a.candidate_id
  where a.id = p_application_id;

  perform public.log_audit_event('recruitment.application_hired','workflow','notice','applications',p_application_id,
    'اعتماد تعيين مرشح', null, jsonb_build_object('candidateName',v_candidate.full_name));
  return jsonb_build_object(
    'applicationId', p_application_id,
    'status', 'hired',
    'candidateName', v_candidate.full_name,
    'candidateEmail', v_candidate.email_norm,
    'candidatePhone', v_candidate.phone_norm);
end $$;



create or replace function public.is_safe_external_link(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    when lower((select v from n)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط عدا http/https (على القيمة المُنظَّفة)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower((select v from n)) !~ '^https?://' then false
    -- رفض الروابط بلا-مخطط (// \\ /\ \/)
    when (select v from n) ~ '^[/\\]{2}' then false
    when (select v from n) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;



create or replace function public.is_safe_storage_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    -- أي مخطط (scheme:) مرفوض — على القيمة المُنظَّفة (يشمل الفراغ البادئ)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' then false
    -- رفض المسار المطلق والروابط بلا-مخطط (/ أو \ أو خلطهما في البداية)
    when (select v from n) ~ '^[/\\]' then false
    when (select v from n) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;



create or replace function public.is_safe_url_or_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    -- الفارغ/NULL يُسمح به (العمود اختياري)
    when $1 is null or length(trim($1)) = 0 then true
    -- رفض محارف التحكّم و newline/CR/tab (على القيمة الخام)
    when $1 ~ '[[:cntrl:]]' then false
    -- رفض المخططات الخطِرة صراحةً (على القيمة المُنظَّفة)
    when lower((select v from n)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط غير https (على القيمة المُنظَّفة — يشمل حالة الفراغ البادئ)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower((select v from n)) !~ '^https://' then false
    -- رفض الروابط بلا-مخطط: أي محرفَي / أو \ بادئين (يمسك // \\ /\ \/)
    when (select v from n) ~ '^[/\\]{2}' then false
    -- منع اجتياز المسار في المسارات النسبية (/ أو \ كفاصلين)
    when (select v from n) ~ '(^|[/\\])\.\.([/\\]|$)' then false
    else true
  end;
$$;



create or replace function public.issue_dispute_decision(p_case_id uuid,p_session_id uuid,p_text text,p_rationale text,p_outcome text,p_owner_id uuid default null,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_case public.dispute_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.decision.issue') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee='chair' and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_case from public.dispute_cases where id=p_case_id for update;
 if v_case.status not in ('committee_deliberation','session_completed','returned_to_committee','escalated_to_executive') or length(trim(coalesce(p_text,'')))<20 or length(trim(coalesce(p_rationale,'')))<20 then raise exception 'INVALID_DECISION'; end if;
 if not exists(select 1 from public.dispute_sessions s where s.id=p_session_id and s.case_id=p_case_id and s.status='held' and (select count(*) from public.dispute_session_attendance a join public.committee_members cm on cm.id=a.committee_member_id where a.session_id=s.id and a.attendance_status in ('present','remote') and cm.case_id=p_case_id and cm.is_active)>=v_case.committee_quorum) then raise exception 'HELD_SESSION_WITH_QUORUM_REQUIRED'; end if;
 v_number='DEC-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_decisions(case_id,session_id,decision_number,decision_text,party_visible_text,rationale,outcome_type,decision_type,implementation_owner_id,implementation_due_at,requires_implementation,status,approved_at,approved_by,issued_at,created_by)
 values(p_case_id,p_session_id,v_number,trim(p_text),trim(p_text),trim(p_rationale),p_outcome,p_outcome,p_owner_id,p_due_at,p_owner_id is not null or p_due_at is not null,'issued',now(),public.current_employee_id(),now(),auth.uid()) returning id into v_id;
 update public.dispute_cases set status='decision_issued',resolved_at=now(),resolution_summary=trim(p_text),appeal_deadline=now()+interval '7 days',updated_at=now() where id=p_case_id;
 if p_owner_id is not null then
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,assigned_to,due_at,execution_status,visibility,metadata)
  values(p_case_id,'decision_implementation',v_case.status,'decision_issued',trim(p_text),public.current_employee_id(),auth.uid(),p_owner_id,p_due_at,'pending','parties',jsonb_build_object('decisionId',v_id));
  perform public.enqueue_dispute_notification(p_case_id,p_owner_id,'implementation:'||v_id::text,'إجراء مطلوب لتنفيذ قرار','يرجى تنفيذ الإجراء المسند وتسجيل إثبات التنفيذ.',case when p_due_at is not null and p_due_at<now()+interval '48 hours' then 'urgent' else 'high' end);
 else
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
  values(p_case_id,'decision_issued',v_case.status,'decision_issued',trim(p_text),public.current_employee_id(),auth.uid(),jsonb_build_object('decisionId',v_id));
 end if;
 perform public.log_audit_event('dispute.decision_issued','workflow','warning','dispute_decisions',v_id,'إصدار قرار اللجنة',null,jsonb_build_object('caseId',p_case_id,'decisionNumber',v_number));
 perform public.enqueue_dispute_notification(p_case_id,v_case.actor_employee_id,'decision:actor:'||v_id::text,'صدر قرار في المشكلة','يمكنك الاطلاع على القرار وتأكيد استلامه من قسم الشكاوى.','high');
 perform public.enqueue_dispute_notification(p_case_id,dp.employee_id,'decision:party:'||v_id::text,'صدر قرار في المشكلة','يمكنك الاطلاع على الجزء المصرح به من القرار.','high') from public.dispute_parties dp where dp.case_id=p_case_id and dp.party_type in ('respondent','related') and dp.notified_at is not null;
 return v_id;
end $$;



create or replace function public.kpi_diag_run(p_month date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_month         date := coalesce(p_month, date_trunc('month', (now() at time zone 'Africa/Cairo'))::date);
  v_report        jsonb := '{}'::jsonb;
  v_template_id   uuid;
  v_policy_id     uuid;
  v_missing_funcs text[];
  v_missing_tbls  text[];
  v_missing_cols  jsonb;
  v_grants        jsonb;
  v_cycle_attempt text;
  v_catalog_attempt text;
  v_sqlstate      text;
  v_sqlerrm       text;
  v_ctx           text;
  v_dummy_cycle_id uuid;
begin
  -- أ) الدوال المساعدة + دوال KPI الحرجة
  select coalesce(array_agg(fname order by fname), '{}'::text[]) into v_missing_funcs
  from (
    values
      ('current_is_full_access'),
      ('current_is_executive_secretary'),
      ('current_is_hr_reviewer'),
      ('current_employee_id'),
      ('has_any_permission'),
      ('has_permission'),
      ('can_access_employee'),
      ('kpi_effective_deadline'),
      ('log_audit_event'),
      ('refresh_kpi_attendance_inputs'),
      ('generate_kpi_cycle_notifications'),
      ('get_kpi_admin_catalog'),
      ('create_kpi_cycle_admin'),
      ('manage_kpi_cycle'),
      ('reschedule_kpi_cycle'),
      ('decide_kpi_appeal'),
      ('get_kpi_cycle_report'),
      ('send_kpi_notifications_admin'),
      ('create_kpi_policy_version')
  ) as t(fname)
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = t.fname
  );
  v_report := jsonb_set(v_report, '{missingFunctions}', to_jsonb(v_missing_funcs), true);

  -- ب) الجداول
  select coalesce(array_agg(tname order by tname), '{}'::text[]) into v_missing_tbls
  from (
    values
      ('kpi_templates'),('kpi_criteria'),('kpi_cycles'),('kpi_evaluations'),
      ('kpi_scores'),('kpi_attendance_snapshots'),('kpi_policy_versions'),
      ('kpi_appeals'),('employees'),('attendance_daily'),('attendance_permits'),
      ('attendance_exceptions'),('attendance_corrections'),('attendance_events'),
      ('roster_days'),('leave_requests'),('requests'),('missions'),
      ('work_assignment_participants'),('work_assignments'),('shifts'),
      ('audit_events'),('user_roles'),('roles')
  ) as t(tname)
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = t.tname and c.relkind in ('r','p')
  );
  v_report := jsonb_set(v_report, '{missingTables}', to_jsonb(v_missing_tbls), true);

  -- ج) الأعمدة الحرجة
  with required(tbl, col) as (
    values
      ('kpi_templates','official_code'),('kpi_templates','is_active'),
      ('kpi_cycles','period_month'),('kpi_cycles','template_id'),('kpi_cycles','scheduled_open_at'),
      ('kpi_cycles','deadline_at'),('kpi_cycles','self_due_at'),('kpi_cycles','manager_due_at'),
      ('kpi_cycles','secretary_due_at'),('kpi_cycles','executive_due_at'),('kpi_cycles','opened_at'),
      ('kpi_cycles','opened_by'),('kpi_cycles','policy_version_id'),('kpi_cycles','use_parallel_flow'),
      ('kpi_cycles','locked_at'),('kpi_cycles','override_reason'),
      ('kpi_evaluations','employee_id'),('kpi_evaluations','cycle_id'),('kpi_evaluations','template_id'),
      ('kpi_evaluations','stage'),('kpi_evaluations','current_stage'),('kpi_evaluations','workflow_status'),
      ('kpi_evaluations','locked'),('kpi_evaluations','final_score'),('kpi_evaluations','final_rating'),
      ('kpi_policy_versions','is_active'),('kpi_policy_versions','attendance_rules'),('kpi_policy_versions','rating_bands'),
      ('kpi_scores','reviewer_stage'),('kpi_attendance_snapshots','evaluation_id'),
      ('employees','is_active'),('employees','is_deleted'),('employees','user_id'),('employees','status'),
      ('attendance_daily','employee_id'),('attendance_daily','work_date'),('attendance_daily','shift_id'),
      ('attendance_daily','late_minutes'),('attendance_daily','early_leave_minutes'),
      ('attendance_daily','work_minutes'),('attendance_daily','status'),
      ('attendance_daily','first_check_in'),('attendance_daily','last_check_out'),
      ('shifts','crosses_midnight'),('shifts','end_time'),('shifts','start_time'),('shifts','break_minutes'),
      ('work_assignment_participants','assignment_id'),
      ('work_assignments','counts_as_work_day'),('work_assignments','start_at'),
      ('work_assignments','end_at'),('work_assignments','status')
  )
  select coalesce(jsonb_agg(jsonb_build_object('table', tbl, 'column', col) order by tbl, col), '[]'::jsonb)
  into v_missing_cols
  from required
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = required.tbl and column_name = required.col
  );
  v_report := jsonb_set(v_report, '{missingColumns}', v_missing_cols, true);

  -- د) القالب والسياسة
  select id into v_template_id from public.kpi_templates where official_code = 'OFFICIAL_KPI_100' and is_active limit 1;
  select id into v_policy_id   from public.kpi_policy_versions where is_active limit 1;
  v_report := jsonb_set(v_report, '{officialTemplateId}', to_jsonb(v_template_id), true);
  v_report := jsonb_set(v_report, '{activePolicyId}',     to_jsonb(v_policy_id),    true);

  -- هـ) صلاحيات EXECUTE على كل التوقيعات المنشورة
  with fn(sig_label, args) as (
    values
      ('get_kpi_admin_catalog(date)',
        'public.get_kpi_admin_catalog(date)'),
      ('create_kpi_cycle_admin(8 args)',
        'public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean,boolean)'),
      ('manage_kpi_cycle(uuid,text,text,timestamptz)',
        'public.manage_kpi_cycle(uuid,text,text,timestamptz)'),
      ('reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)',
        'public.reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)'),
      ('decide_kpi_appeal(uuid,text,text)',
        'public.decide_kpi_appeal(uuid,text,text)'),
      ('refresh_kpi_attendance_inputs(uuid)',
        'public.refresh_kpi_attendance_inputs(uuid)'),
      ('get_kpi_cycle_report(uuid)',
        'public.get_kpi_cycle_report(uuid)'),
      ('send_kpi_notifications_admin(uuid)',
        'public.send_kpi_notifications_admin(uuid)'),
      ('kpi_diag_run(date)',
        'public.kpi_diag_run(date)')
  )
  select jsonb_object_agg(
    sig_label,
    jsonb_build_object(
      'authenticated', coalesce(has_function_privilege('authenticated', args, 'EXECUTE'), false),
      'service_role',  coalesce(has_function_privilege('service_role', args, 'EXECUTE'), false)
    )
  ) into v_grants from fn;
  v_report := jsonb_set(v_report, '{grants}', v_grants, true);

  -- و) نبضة بسيطة — استدعاء get_kpi_admin_catalog الحقيقي
  begin
    perform public.get_kpi_admin_catalog(v_month);
    v_catalog_attempt := 'OK';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
    v_catalog_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
  end;
  v_report := jsonb_set(v_report, '{catalogCall}', to_jsonb(v_catalog_attempt), true);

  -- ز) نبضة بسيطة — استدعاء create_kpi_cycle_admin الحقيقي مع فرض rollback
  if v_template_id is not null and v_policy_id is not null then
    begin
      v_dummy_cycle_id := public.create_kpi_cycle_admin(
        p_month             := v_month,
        p_template_id       := v_template_id,
        p_self_due          := now(),
        p_manager_due       := now(),
        p_secretary_due     := now(),
        p_executive_due     := now(),
        p_open_now          := false,
        p_use_parallel_flow := false
      );
      raise exception '__DIAG_FORCE_ROLLBACK__ cycle_id=%', v_dummy_cycle_id using errcode = 'P0001';
    exception when others then
      get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
      if v_sqlerrm like '__DIAG_FORCE_ROLLBACK__%' then
        v_cycle_attempt := 'OK — نجحت الدالة (لم تُحفظ الدورة بسبب التراجع التشخيصي)';
      else
        v_cycle_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
      end if;
    end;
  else
    v_cycle_attempt := 'SKIPPED — لا قالب رسمي نشط أو لا سياسة نشطة';
  end if;
  v_report := jsonb_set(v_report, '{createCycleCall}', to_jsonb(v_cycle_attempt), true);

  -- metadata
  v_report := jsonb_set(v_report, '{month}', to_jsonb(v_month), true);
  v_report := jsonb_set(v_report, '{diagAt}', to_jsonb(now()), true);
  v_report := jsonb_set(v_report, '{diagVersion}', to_jsonb('0301_v1'::text), true);
  return v_report;
end $$;



create or replace function public.kpi_resolve_approver_for_employee(p_employee_id uuid)
returns uuid
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_mgr uuid;
begin
  -- مدير مباشر نشط
  select mr.manager_employee_id into v_mgr
    from public.manager_relations mr
   where mr.employee_id = p_employee_id
     and mr.relation_type = 'primary'
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
   order by mr.effective_from desc limit 1;
  if v_mgr is not null then return v_mgr; end if;

  -- بديل 1: أول موظف فعّال بدور hr-manager
  select e.id into v_mgr
    from public.employees e
    join public.profiles pr on pr.employee_id = e.id and pr.status = 'active'
    join public.user_roles ur on ur.user_id = pr.id
    join public.roles r on r.id = ur.role_id and r.slug = 'hr-manager'
   where e.is_active and e.status = 'active'
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now())
   order by e.hire_date limit 1;
  if v_mgr is not null then return v_mgr; end if;

  -- بديل 2: أول موظف فعّال بدور executive-secretary
  select e.id into v_mgr
    from public.employees e
    join public.profiles pr on pr.employee_id = e.id and pr.status = 'active'
    join public.user_roles ur on ur.user_id = pr.id
    join public.roles r on r.id = ur.role_id and r.slug = 'executive-secretary'
   where e.is_active and e.status = 'active'
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now())
   order by e.hire_date limit 1;
  return v_mgr;
end $$;



CREATE OR REPLACE FUNCTION public.link_assignment_to_initiatives(p_assignment_id uuid, p_evaluation_id uuid, p_points numeric DEFAULT 5, p_note text DEFAULT NULL::text)
 RETURNS kpi_assignment_contributions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_asg public.work_assignments;
  v_emp uuid;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess','performance.kpi.hr_review'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_points is null or p_points < 0 or p_points > 5 then
    raise exception 'INITIATIVES_POINTS_OUT_OF_RANGE (0..5)' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode='P0002'; end if;
  if v_asg.assignment_type not in ('CONVOY','FUNDRAISING') then
    raise exception 'only convoy/fundraising contribute to initiatives' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, points, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'INITIATIVES', p_points, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (منع الاحتساب المزدوج)' using errcode='23505';
  end if;

  perform public.log_audit_event(
    'kpi.assignment.initiatives.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'ربط تكليف بمعيار المبادرات', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'points', p_points,
                       'assignmentType', v_asg.assignment_type));
  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.link_fundraising_to_target(p_assignment_id uuid, p_evaluation_id uuid, p_weight numeric DEFAULT 40, p_note text DEFAULT NULL::text)
 RETURNS kpi_assignment_contributions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_asg public.work_assignments;
  v_emp uuid;
  v_goal_id uuid;
  v_achieved numeric;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_weight is null or p_weight <= 0 or p_weight > 40 then
    raise exception 'TARGET_WEIGHT_OUT_OF_RANGE (0..40]' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode='P0002'; end if;
  if v_asg.assignment_type <> 'FUNDRAISING' then
    raise exception 'فقط جمع التبرعات يرتبط بهدف مالي' using errcode='22023';
  end if;
  if v_asg.target_amount is null or v_asg.target_amount <= 0 then
    raise exception 'التكليف بلا هدف مالي' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  -- المحقق: مجموع محقق المشاركين إن وُجد، وإلا achieved_amount على التكليف.
  select coalesce(sum(achieved_amount), 0) into v_achieved
  from public.work_assignment_participants
  where assignment_id = p_assignment_id and employee_id = v_emp;
  if v_achieved = 0 then v_achieved := coalesce(v_asg.achieved_amount, 0); end if;

  -- سجّل المساهمة أولًا لضمان منع التكرار.
  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, amount, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'TARGET', v_achieved, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (منع الاحتساب المزدوج)' using errcode='23505';
  end if;

  -- أنشئ/حدّث هدف TARGET المالي.
  insert into public.kpi_goals(
    evaluation_id, title, description, target_value, achieved_value, unit, weight,
    evidence_source, created_by)
  values(
    p_evaluation_id, format('مستهدف فاندي: %s', v_asg.title), p_note,
    v_asg.target_amount, v_achieved, 'EGP', p_weight,
    'work_assignments', auth.uid())
  returning id into v_goal_id;

  perform public.log_audit_event(
    'kpi.assignment.target.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'ربط فاندي بمستهدف مالي', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'goalId', v_goal_id,
                       'target', v_asg.target_amount, 'achieved', v_achieved));
  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.list_credentials(
  p_category text DEFAULT NULL,
  p_active_only boolean DEFAULT true
)
RETURNS TABLE (
  key_name      text,
  category      text,
  secret_hint   text,
  metadata      jsonb,
  is_active     boolean,
  rotated_at    timestamptz,
  expires_at    timestamptz,
  created_at    timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'list_credentials يتطلب صلاحية full-access';
  END IF;

  RETURN QUERY
    SELECT cv.key_name, cv.category, cv.secret_hint, cv.metadata,
           cv.is_active, cv.rotated_at, cv.expires_at, cv.created_at
      FROM public.credential_vault cv
     WHERE (p_category IS NULL OR cv.category = p_category)
       AND (NOT p_active_only OR cv.is_active = true)
     ORDER BY cv.key_name;
END;
$$;



create or replace function public.manage_kpi_cycle(p_cycle_id uuid,p_action text,p_reason text,p_extended_until timestamptz default null)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_old text;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'CONTROL_REASON_REQUIRED'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id for update;
 v_old:=v_cycle.status;
 case p_action
  when 'open' then
   if v_cycle.status not in ('draft','suspended','in_review') then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='open',opened_at=coalesce(opened_at,now()),opened_by=public.current_employee_id(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when current_stage='self' then 'OPEN_FOR_SELF_EVALUATION' when workflow_status in ('OVERDUE','CYCLE_CLOSED') then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'reopen' then
   if v_cycle.status not in ('locked','suspended','in_review') then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='open',locked_at=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when workflow_status in ('OVERDUE','CYCLE_CLOSED') then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'extend' then
   if p_extended_until is null or p_extended_until<=coalesce(v_cycle.extended_until,v_cycle.deadline_at,now()) then raise exception 'INVALID_EXTENSION_DEADLINE'; end if;
   update public.kpi_cycles set status='open',extended_until=p_extended_until,locked_at=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when workflow_status='OVERDUE' then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'suspend' then
   if v_cycle.status<>'open' then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='suspended',override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=true,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'cancel_open' then
   if v_cycle.status not in ('open','draft') then raise exception 'INVALID_CYCLE_STATE'; end if;
   if exists(select 1 from public.kpi_evaluations e where e.cycle_id=p_cycle_id and (e.current_stage<>'self' or exists(select 1 from public.kpi_scores s where s.evaluation_id=e.id and s.reviewer_stage='self'))) then raise exception 'CYCLE_ALREADY_STARTED'; end if;
   update public.kpi_cycles set status='draft',opened_at=null,opened_by=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=true,workflow_status='DRAFT',updated_at=now() where cycle_id=p_cycle_id;
  when 'close' then
   update public.kpi_cycles set status='locked',locked_at=now(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set
    workflow_status=case when current_stage='finalized' then 'CYCLE_CLOSED' else 'OVERDUE' end,
    current_stage=case when current_stage='finalized' then 'closed' else current_stage end,
    stage=case when stage='finalized' then 'closed' else stage end,
    locked=true,updated_at=now()
   where cycle_id=p_cycle_id;
  when 'archive' then
   if v_cycle.status<>'locked' then raise exception 'CYCLE_MUST_BE_CLOSED'; end if;
   update public.kpi_evaluations set stage='archived',current_stage='archived',workflow_status='ARCHIVED',locked=true,updated_at=now()
   where cycle_id=p_cycle_id and current_stage='closed';
   update public.kpi_cycles set override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
  else raise exception 'INVALID_CYCLE_ACTION';
 end case;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 perform public.log_audit_event('kpi.cycle.'||p_action,'workflow','warning','kpi_cycles',p_cycle_id,'تحكم السكرتير التنفيذي في دورة KPI',trim(p_reason),jsonb_build_object('oldStatus',v_old,'newStatus',v_cycle.status,'extendedUntil',p_extended_until));
 return v_cycle;
end $$;



CREATE OR REPLACE FUNCTION public.mark_my_notification_delivery(p_notification_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_log public.notification_delivery_log; v_subscription_id uuid;
begin
  if auth.uid() is null then raise exception 'يلزم مستخدم مسجل الدخول' using errcode='42501'; end if;
  if p_status not in ('delivered','opened') then raise exception 'حالة تسليم غير صالحة' using errcode='22023'; end if;
  if not exists(select 1 from public.notifications n where n.id=p_notification_id and n.recipient_user_id=auth.uid()) then
    raise exception 'الإشعار ليس لك' using errcode='42501';
  end if;
  select * into v_log from public.notification_delivery_log l
  where l.notification_id=p_notification_id and l.recipient_user_id=auth.uid()
    and l.channel='push' order by l.created_at desc limit 1 for update;
  if v_log.id is null then
    select id into v_subscription_id from public.push_subscriptions
    where user_id=auth.uid() and is_active
    order by last_used_at desc nulls last,created_at desc limit 1;
    insert into public.notification_delivery_log(
      notification_id,subscription_id,recipient_user_id,channel,status,
      attempts,sent_at,delivered_at
    ) values(p_notification_id,v_subscription_id,auth.uid(),'push',p_status,1,now(),now());
  elsif v_log.status<>'opened' or p_status='opened' then
    update public.notification_delivery_log set status=p_status,
      delivered_at=coalesce(delivered_at,now()),updated_at=now() where id=v_log.id;
  end if;
end;
$function$;



CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
 RETURNS notifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.notifications;
begin
  update public.notifications
     set is_read = true,
         read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_user_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'الإشعار غير موجود أو ليس لك' using errcode = '42501';
  end if;

  return v_row;
end;
$function$;



create or replace function public.notify_document_signature_request()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.notify_user(
    new.signer_user_id,
    'طلب توقيع مستند',
    format('يوجد مستند بانتظار توقيعك (%s).', coalesce(new.signer_role, '')),
    'documents', 'normal', 'document_signature_requests', new.id,
    jsonb_build_object('sequenceNo', new.sequence_no));
  return new;
end $$;



create or replace function public.notify_wellbeing_request()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.notify_employees_with_permission(
    'wellbeing.request.manage',
    'طلب دعم جديد',
    format('طلب دعم ورفاهية (تصنيف %s).', coalesce(new.category, '')),
    'wellbeing', 'high', 'wellbeing_requests', new.id,
    jsonb_build_object('category', new.category),
    new.employee_id);
  return new;
end $$;



create or replace function public.nudge_notification_dispatcher()
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_has_net boolean;
  v_base    text;
  v_secret  text;
begin
  select exists(select 1 from pg_extension where extname='pg_net') into v_has_net;
  if not v_has_net then return; end if;
  v_base   := current_setting('app.settings.functions_base_url', true);
  v_secret := current_setting('app.settings.cron_secret', true);
  if v_base is null or v_base='' or v_secret is null or v_secret='' then return; end if;
  perform net.http_post(
    url     => v_base||'/notification-dispatcher',
    headers => jsonb_build_object('Content-Type','application/json','x-cron-secret',v_secret),
    body    => jsonb_build_object('trigger','urgent_location','expedite',true)
  );
exception when others then
  -- لا تُفشل الطلب بسبب فشل النبضة؛ الكرون يبقى الاحتياط.
  return;
end;
$$;



create or replace function public.open_annual_leave_entitlement(
  p_employee_id uuid,
  p_year integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ent jsonb;
  v_annual_id uuid;
  v_casual_id uuid;
  v_sick_id uuid;
  v_count integer := 0;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  v_ent := public.effective_annual_entitlement(p_employee_id, make_date(p_year, 1, 1));
  select id into v_annual_id from public.leave_types where code = 'annual' and is_active;
  select id into v_casual_id from public.leave_types where code = 'casual' and is_active;
  select id into v_sick_id   from public.leave_types where code = 'sick'   and is_active;

  if v_annual_id is not null then
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_annual_id, p_year, 'opening',
      (v_ent->>'annual')::numeric,
      format('leave:opening:annual:%s:%s', p_employee_id, p_year),
      null, 'فتح رصيد الإجازة الاعتيادية السنوي',
      jsonb_build_object('entitlement', v_ent));
    v_count := v_count + 1;
  end if;

  if v_casual_id is not null then
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_casual_id, p_year, 'opening',
      (v_ent->>'casual')::numeric,
      format('leave:opening:casual:%s:%s', p_employee_id, p_year),
      null, 'فتح رصيد الإجازة العارضة السنوي',
      jsonb_build_object('entitlement', v_ent));
    v_count := v_count + 1;
  end if;

  -- المرضية: لا نفتح رصيداً ثابتاً — أصبحت بدون حد. تُسجّل عند الحاجة فقط.
  -- (يُترك مرجعياً فارغاً دون ledger entry، رصيدها غير محدود.)

  perform public.log_audit_event(
    'leave.entitlement.opened', 'workflow', 'info',
    'leave_balance_accounts', p_employee_id,
    'فتح الرصيد السنوي للإجازات (بدون مرضية ثابتة)',
    format('السنة %s', p_year),
    jsonb_build_object('year', p_year, 'entitlement', v_ent));
  return v_count;
end;
$$;



create or replace function public.override_kpi_score(p_evaluation_id uuid,p_criterion_id uuid,p_score numeric,p_reason text)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_max numeric; v_old numeric;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'OVERRIDE_REASON_REQUIRED'; end if;
 select c.max_score into strict v_max from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id where e.id=p_evaluation_id and c.id=p_criterion_id;
 if p_score<0 or p_score>v_max then raise exception 'SCORE_OUT_OF_RANGE'; end if;
 select public.kpi_effective_score(p_evaluation_id,p_criterion_id) into v_old;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,p_criterion_id,p_score,'secretary',trim(p_reason),auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 -- V17: route back to manager_review (the finalization step), not manager_final
 update public.kpi_evaluations set final_score=null,final_rating=null,final_breakdown=null,locked=false,
  stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',updated_at=now()
 where id=p_evaluation_id;
 perform public.log_audit_event('kpi.score.overridden','workflow','warning','kpi_evaluations',p_evaluation_id,'تعديل استثنائي موثق لدرجة KPI',trim(p_reason),jsonb_build_object('criterionId',p_criterion_id,'oldScore',v_old,'newScore',p_score));
 return p_score;
end $$;



create or replace function public.process_dispute_sla(p_limit integer default 500)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_case record; v_count integer:=0;
begin
 for v_case in select id,case_number,title,review_due_at,severity from public.dispute_cases where status in ('submitted','needs_more_information') and review_due_at<=now()+interval '2 hours' order by review_due_at limit greatest(1,least(coalesce(p_limit,500),2000)) loop
  perform public.notify_dispute_admins(v_case.id,case when v_case.review_due_at<=now() then 'sla-overdue' else 'sla-due-soon' end,
   case when v_case.review_due_at<=now() then 'تجاوزت مشكلة مهلة المراجعة' else 'اقترب انتهاء مهلة مراجعة مشكلة' end,
   coalesce(v_case.case_number,'')||' — '||v_case.title,case when v_case.review_due_at<=now() or v_case.severity='critical' then 'urgent' else 'high' end);
  v_count=v_count+1;
 end loop;
 return v_count;
end $$;



create or replace function public.process_kpi_cycle_schedule(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_count integer:=0;
begin
 for v_cycle in select * from public.kpi_cycles where status='draft' and scheduled_open_at<=p_at and p_at<=coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='open',opened_at=p_at,updated_at=p_at where id=v_cycle.id;
  update public.kpi_evaluations set locked=false,workflow_status='OPEN_FOR_SELF_EVALUATION',updated_at=p_at where cycle_id=v_cycle.id and current_stage='self';
  perform public.log_audit_event('kpi.cycle.auto_opened','workflow','notice','kpi_cycles',v_cycle.id,'فتح دورة KPI تلقائيًا',null,jsonb_build_object('at',p_at));
  v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at);
 for v_cycle in select * from public.kpi_cycles where status='open' and p_at>coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='locked',locked_at=p_at,updated_at=p_at where id=v_cycle.id;
  update public.kpi_evaluations set
   workflow_status=case when current_stage='finalized' then 'CYCLE_CLOSED' else 'OVERDUE' end,
   current_stage=case when current_stage='finalized' then 'closed' else current_stage end,
   stage=case when stage='finalized' then 'closed' else stage end,
   locked=true,updated_at=p_at where cycle_id=v_cycle.id;
  perform public.log_audit_event('kpi.cycle.auto_closed','workflow','warning','kpi_cycles',v_cycle.id,'إغلاق دورة KPI تلقائيًا بعد الموعد',null,jsonb_build_object('at',p_at));
  v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at+interval '1 second');
 return v_count;
end $$;



create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_target   uuid;
  v_role     text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    -- ── الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد ──
    --    فقط تذكير دوري لأبو عمار وإعادة ضبط المهلة (24 ساعة).
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير).
المدير المباشر لم يبتّ والطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;
      -- صفِّر deadline لمنع تكرار التذكير الفوري (24 ساعة من الآن)
      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (أبو عمار) ──
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    -- وسمّ الخطوة الحالية كـ escalated + خنّق مهلتها 24 ساعة.
    -- (0465: كان يُترك deadline في الماضي فيعيد الـcron اختيارها كل 5 دقائق!)
    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = now() + interval '24 hours',
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      -- فعّل الخطوة التالية (أبو عمار) — مهلة ساعتين
      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      -- إشعار أبو عمار (الخطوة 2)
      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير التنفيذي (كامل الشاشة) عند التصعيد الأول فقط
      if v_next.status is distinct from 'active' then
        perform public.notify_executive_fullscreen(
          'تصعيد طلب — للمتابعة',
          coalesce(v_row.title, ''),
          'request',
          'request', v_row.request_id,
          '/requests/' || v_row.request_id,
          jsonb_build_object(
            'escalation', 'executive_notify',
            'tier', v_next.step_order
          )
        );
      end if;
    else
      -- لا توجد خطوة تالية (طلب قديم بلا بنية): تصعيد عام
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  -- سجل صحة الـ cron
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('process_request_sla', 0, 'error', sqlerrm);
  raise;
end $$;



create or replace function public.propose_admin_action(
  p_case_id uuid,
  p_action  text,
  p_detail  text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v record;
begin
  -- صلاحية: مقرر اللجنة أو رئيسها أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.propose')
    or exists(
      select 1 from public.committee_members
      where case_id = p_case_id
        and employee_id = public.current_employee_id()
        and role_in_committee in ('secretary','chair')
        and is_active
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- تحقق من نوع الإجراء
  if p_action not in (
    'verbal_warning','written_warning','final_warning','salary_deduction',
    'suspension','demotion','termination','transfer','training_requirement','no_action'
  ) then
    raise exception 'INVALID_ACTION_TYPE' using errcode = '22023';
  end if;

  if nullif(trim(p_detail), '') is null then
    raise exception 'DETAIL_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  -- يجب أن تكون القضية في حالة "قرار صادر"
  if v.status <> 'decision_issued' then
    raise exception 'CASE_NOT_IN_DECISION_ISSUED' using errcode = '22023';
  end if;

  update public.dispute_cases set
    proposed_administrative_action = p_action,
    proposed_action_detail         = trim(p_detail),
    proposed_at                    = now(),
    proposed_by                    = public.current_employee_id(),
    status                         = 'action_proposed',
    updated_at                     = now()
  where id = p_case_id;

  -- سجلّ في dispute_actions
  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'propose_admin_action', 'decision_issued', 'action_proposed',
    trim(p_detail), public.current_employee_id(), auth.uid(),
    jsonb_build_object('proposed_action', p_action)
  );

  -- تدقيق
  perform public.log_audit_event(
    'dispute.admin_action_proposed', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'اقتراح إجراء إداري: ' || p_action,
    trim(p_detail),
    jsonb_build_object('action', p_action)
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.provision_employee_record(p_actor_user_id uuid, p_user_id uuid, p_full_name_ar text, p_full_name_en text, p_employee_code text, p_phone_e164 text, p_role_slug text, p_manager_employee_id uuid DEFAULT NULL::uuid, p_department_id uuid DEFAULT NULL::uuid, p_team_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_work_site_id uuid DEFAULT NULL::uuid, p_job_title_id uuid DEFAULT NULL::uuid, p_position_id uuid DEFAULT NULL::uuid, p_grade_id uuid DEFAULT NULL::uuid, p_employment_type_id uuid DEFAULT NULL::uuid, p_hire_date date DEFAULT NULL::date, p_invitation_pending boolean DEFAULT true, p_job_title_name text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_employee_id uuid;
  v_role_id uuid;
  v_profile_status text;
  v_employee_status text;
  v_employee_code text;
  v_job_title_id uuid;
  v_title_name text;
  v_title_code text;
begin
  if p_actor_user_id is null or p_user_id is null then
    raise exception 'المنفّذ والمستخدم مطلوبان';
  end if;

  select id into v_role_id
  from public.roles
  where slug = p_role_slug;

  if v_role_id is null then
    raise exception 'unknown role slug: %', p_role_slug using errcode = '22023';
  end if;

  -- كود الموظف: صريح إن وُجد، وإلا يُشتق من رقم الهاتف.
  v_employee_code := coalesce(nullif(trim(p_employee_code), ''), nullif(trim(p_phone_e164), ''));
  if v_employee_code is null then
    raise exception 'كود الموظف أو الهاتف مطلوب' using errcode = '22023';
  end if;

  -- فحص تكرار كود الموظف بين النشطين.
  if exists (
    select 1 from public.employees
    where employee_code = v_employee_code and is_active = true and is_deleted = false
  ) then
    raise exception 'كود الموظف موجود مسبقاً' using errcode = '23505';
  end if;

  -- فحص تكرار الهاتف صريح مع رسالة مفهومة (بدل الاعتماد على constraint خام).
  if p_phone_e164 is not null and exists (
    select 1 from public.employees
    where phone_e164 = p_phone_e164 and is_active = true and is_deleted = false
  ) then
    raise exception 'phone number already belongs to an active employee' using errcode = '23505';
  end if;

  if p_manager_employee_id is not null and not exists (
    select 1 from public.employees
    where id = p_manager_employee_id and is_active = true and is_deleted = false
  ) then
    raise exception 'المدير ليس موظفاً نشطاً' using errcode = '23503';
  end if;

  -- المسمى الوظيفي: أولوية للمعرّف الصريح، وإلا مطابقة/إنشاء من الاسم الحر.
  v_job_title_id := p_job_title_id;
  v_title_name := nullif(trim(p_job_title_name), '');
  if v_job_title_id is null and v_title_name is not null then
    -- محاولة الإدراج أولاً مع ON CONFLICT لمنع التكرار عند التزامن.
    v_title_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    insert into public.job_titles (code, name, is_active, created_by)
    values (v_title_code, v_title_name, true, p_actor_user_id)
    on conflict ((lower(name))) where is_active = true
    do update set updated_at = now()
    returning id into v_job_title_id;
  end if;

  v_profile_status := case when p_invitation_pending then 'pending' else 'active' end;
  v_employee_status := case when p_invitation_pending then 'invited' else 'active' end;

  insert into public.employees (
    user_id, employee_code, full_name_ar, full_name_en, phone_e164,
    job_title_id, position_id, grade_id, department_id, team_id,
    branch_id, work_site_id, employment_type_id, hire_date,
    status, is_active, is_deleted, photo_url, created_by
  ) values (
    p_user_id, trim(v_employee_code), trim(p_full_name_ar), nullif(trim(p_full_name_en), ''),
    p_phone_e164, v_job_title_id, p_position_id, p_grade_id,
    p_department_id, p_team_id, p_branch_id, p_work_site_id,
    p_employment_type_id, p_hire_date, v_employee_status, true, false,
    nullif(trim(p_photo_url), ''), p_actor_user_id
  ) returning id into v_employee_id;

  insert into public.profiles (
    id, employee_id, primary_role_id, status, temporary_password,
    branch_id, department_id, team_id, created_by
  ) values (
    p_user_id, v_employee_id, v_role_id, v_profile_status, true,
    p_branch_id, p_department_id, p_team_id, p_actor_user_id
  );

  insert into public.user_roles (
    user_id, role_id, effective_from, granted_by
  ) values (
    p_user_id, v_role_id, now(), p_actor_user_id
  );

  if p_manager_employee_id is not null then
    insert into public.manager_relations (
      employee_id, manager_employee_id, relation_type,
      effective_from, created_by
    ) values (
      v_employee_id, p_manager_employee_id, 'primary',
      coalesce(p_hire_date, current_date), p_actor_user_id
    );
  end if;

  return jsonb_build_object(
    'employeeId', v_employee_id,
    'userId', p_user_id
  );
end;
$function$;



create or replace function public.publish_announcement(
  p_announcement_id uuid,
  p_channel         text default null
)
returns public.announcements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.announcements;
  v_channel text := coalesce(p_channel, 'web');
begin
  -- التحقق من الصلاحية
  if not (
    public.current_is_full_access()
    or public.has_permission('comms.announcement.manage')
    or public.has_permission('posts.publish')
  ) then
    raise exception 'ليس لديك صلاحية نشر المنشورات' using errcode = '42501';
  end if;

  if v_channel not in ('web','mobile') then
    raise exception 'قناة نشر غير صالحة: %', v_channel using errcode = '22023';
  end if;

  update public.announcements
    set status            = 'published',
        published_at      = now(),
        publisher_channel = v_channel,
        updated_at        = now()
  where id = p_announcement_id
    and status = 'draft'
  returning * into v_row;

  if not found then
    raise exception 'المنشور غير موجود أو ليس في حالة مسودة' using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;



CREATE OR REPLACE FUNCTION public.publish_official_announcement(p_title text, p_body text, p_category text DEFAULT 'general'::text, p_priority text DEFAULT 'normal'::text, p_requires_acknowledgement boolean DEFAULT false, p_banner_url text DEFAULT NULL::text, p_post_type text DEFAULT 'standard'::text, p_poll_options jsonb DEFAULT NULL::jsonb, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS announcements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.announcements;
  v_metadata jsonb;
begin
  -- التحقق من الصلاحية
  if not (public.current_is_full_access()
          or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'غير مصرح لك بنشر الإعلانات' using errcode = '42501';
  end if;

  -- التحقق من طول العنوان والمحتوى
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'العنوان أو المحتوى قصير جداً' using errcode = '22023';
  end if;

  -- التحقق من نوع المنشور
  if p_post_type not in ('standard', 'poll', 'announcement') then
    raise exception 'invalid post type: %', p_post_type using errcode = '22023';
  end if;

  -- بناء metadata
  v_metadata := jsonb_build_object('postType', p_post_type);
  if p_post_type = 'poll' and p_poll_options is not null then
    v_metadata := v_metadata || jsonb_build_object('pollOptions', p_poll_options);
  end if;

  insert into public.announcements(
    title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, post_type, published_at, expires_at,
    metadata, created_by
  )
  values (
    trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement, false),
    nullif(trim(coalesce(p_banner_url, '')), ''),
    coalesce(p_post_type, 'standard'),
    now(),
    p_expires_at,
    v_metadata,
    auth.uid()
  )
  returning * into v_row;

  perform public.log_audit_event(
    'announcement.published', 'workflow', 'info', 'announcements', v_row.id,
    'نشر إعلان رسمي', null,
    jsonb_build_object(
      'title', v_row.title,
      'priority', v_row.priority,
      'postType', v_row.post_type,
      'hasBanner', v_row.banner_url is not null,
      'hasPoll', p_post_type = 'poll'
    )
  );

  return v_row;
end;
$function$;



create or replace function public.publish_roster_admin(p_name text,p_period_start date,p_period_end date,p_department_id uuid,p_team_id uuid,p_branch_id uuid,p_days jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_employee uuid; v_date date; v_shift uuid; v_status text; v_code text; v_employees uuid[] := '{}'::uuid[];
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_period_end<p_period_start or jsonb_typeof(p_days)<>'array' then raise exception 'INVALID_ROSTER'; end if;
 v_code:='RST-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into public.work_rosters(code,name,period_start,period_end,department_id,team_id,branch_id,status,published_at,published_by,notes,created_by)
 values(v_code,trim(p_name),p_period_start,p_period_end,p_department_id,p_team_id,p_branch_id,'published',now(),public.current_employee_id(),p_notes,auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(p_days) loop
  v_employee:=(v_item->>'employeeId')::uuid; v_date:=(v_item->>'workDate')::date; v_shift:=nullif(v_item->>'shiftId','')::uuid; v_status:=coalesce(v_item->>'dayStatus','scheduled');
  if v_date<p_period_start or v_date>p_period_end or not public.can_access_employee(v_employee,'attendance.roster.manage') then raise exception 'ROSTER_SCOPE_OR_DATE_INVALID'; end if;
  if not (v_employee = any(v_employees)) then v_employees := v_employees || v_employee; end if;
  insert into public.roster_days(roster_id,employee_id,work_date,shift_id,work_site_id,geofence_id,day_status,start_override,end_override,notes,created_by)
  values(v_id,v_employee,v_date,v_shift,nullif(v_item->>'workSiteId','')::uuid,nullif(v_item->>'geofenceId','')::uuid,v_status,nullif(v_item->>'startOverride','')::time,nullif(v_item->>'endOverride','')::time,v_item->>'notes',auth.uid());
 end loop;
 perform public.log_audit_event('attendance.roster.published','workflow','notice','work_rosters',v_id,'نشر جدول ورديات',null,jsonb_build_object('start',p_period_start,'end',p_period_end));
 foreach v_employee in array v_employees loop
  perform public.notify_employee(
   v_employee, 'جدول ورديات جديد',
   format('نُشر جدول الورديات «%s» للفترة من %s إلى %s', trim(p_name), p_period_start, p_period_end),
   'attendance', 'normal', 'work_rosters', v_id,
   jsonb_build_object('start',p_period_start,'end',p_period_end));
 end loop;
 return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.punch_attendance_local(p_event_type text, p_credential_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    raise exception 'غير مصرح' using errcode = '42501';
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

  -- V17 Â§7: المدير التنفيذي مستثنى من الحضور الإلزامي
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
$function$;



CREATE OR REPLACE FUNCTION public.punch_attendance_local_biometric_v1(p_operation_id uuid, p_event_type text, p_installation_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required','invalid_attendance_location'
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

  -- 0226: Return structured JSON instead of RAISE for device-not-active.
  -- This lets Flutter's result-check path show a clear device-specific message.
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
  v_result := jsonb_build_object(
    'ok',true,'verified',true,
    'verificationMethod',v_verification_method,
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );
  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;
  return v_result;
end;
$function$;



CREATE OR REPLACE FUNCTION public.punch_attendance_local_v2(p_operation_id uuid, p_event_type text, p_credential_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_operation public.local_attendance_operations;
  v_result jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode = '42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;

  insert into public.local_attendance_operations(
    operation_id, user_id, employee_id, event_type, credential_id
  ) values (
    p_operation_id, auth.uid(), v_employee_id, p_event_type, p_credential_id
  ) on conflict (operation_id) do nothing;

  select * into v_operation
  from public.local_attendance_operations
  where operation_id = p_operation_id
  for update;

  if v_operation.user_id <> auth.uid()
     or v_operation.employee_id <> v_employee_id
     or v_operation.event_type <> p_event_type
     or v_operation.credential_id <> p_credential_id then
    raise exception 'attendance_idempotency_conflict' using errcode = '22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result, '{}'::jsonb)
      || jsonb_build_object('replayed', true);
  end if;

  v_result := public.punch_attendance_local(
    p_event_type,
    p_credential_id,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_is_mock,
    null
  );

  update public.local_attendance_operations
  set status = case when coalesce((v_result->>'ok')::boolean, false)
                    then 'completed' else 'rejected' end,
      result = v_result,
      completed_at = now()
  where operation_id = p_operation_id;

  return v_result || jsonb_build_object('replayed', false);
end;
$function$;



CREATE OR REPLACE FUNCTION public.read_credential(p_key_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_ciphertext bytea;
  v_enc_key    text;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'read_credential يتطلب صلاحية full-access';
  END IF;

  -- جلب القيمة المشفّرة (فقط السجلات النشطة)
  SELECT secret_ciphertext
    INTO v_ciphertext
    FROM public.credential_vault
   WHERE key_name = p_key_name
     AND is_active = true;

  IF v_ciphertext IS NULL THEN
    RETURN NULL;
  END IF;

  -- التحقق من وجود مفتاح التشفير
  v_enc_key := current_setting('app.credential_key', true);
  IF v_enc_key IS NULL OR length(trim(v_enc_key)) = 0 THEN
    RAISE EXCEPTION 'ERR_MISSING_ENCRYPTION_KEY'
      USING HINT = 'app.credential_key غير مُعرَّف — اضبطه كـ Supabase secret';
  END IF;

  -- تسجيل تدقيقي (قبل فك التشفير — حتى لو فشل)
  PERFORM public.log_audit_event(
    p_event_type   := 'credential.read',
    p_category     := 'security',
    p_severity     := 'notice',
    p_target_table := 'credential_vault',
    p_summary_ar   := 'قراءة اعتماد مشفّر: ' || p_key_name,
    p_metadata     := jsonb_build_object('key_name', p_key_name)
  );

  RETURN pgp_sym_decrypt(v_ciphertext, v_enc_key);
END;
$$;



CREATE OR REPLACE FUNCTION public.reassign_request(p_request_id uuid, p_new_manager_id uuid, p_reason text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.requests; v_old uuid;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['requests.request.delegate','requests.request.override'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002'; end if;
  if v_req.status <> 'pending' then
    raise exception 'الطلبات قيد الانتظار فقط تُعاد إسنادها' using errcode = '22023';
  end if;
  if p_new_manager_id = v_req.employee_id then
    raise exception 'لا يمكن تعيين صاحب الطلب معتمداً له' using errcode = '42501';
  end if;
  v_old := v_req.manager_employee_id;

  update public.requests
    set manager_employee_id = p_new_manager_id, updated_at = now(),
        payload = payload || jsonb_build_object('reassignment',
          jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id, 'reason', p_reason))
    where id = p_request_id returning * into v_req;

  update public.request_steps
    set assignee_employee_id = p_new_manager_id, updated_at = now()
    where request_id = p_request_id and status in ('active','pending','escalated');

  insert into public.request_actions(
    request_id, actor_employee_id, action, comment, metadata)
  values(p_request_id, public.current_employee_id(), 'reassign', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));

  perform public.notify_employee(p_new_manager_id, 'أُسند إليك طلب للقرار',
    format('تم نقل الطلب #%s إليك.', p_request_id), 'request', 'high', 'requests', p_request_id);

  perform public.log_audit_event('request.reassigned', 'workflow', 'warning',
    'requests', p_request_id, 'نقل طلب من مدير إلى آخر', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));
  return v_req;
end $function$;



CREATE OR REPLACE FUNCTION public.record_announcement_view(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.announcements a
    where a.id = p_announcement_id
      and a.status = 'published'
      and (a.expires_at is null or a.expires_at > now())
  ) then
    raise exception 'announcement not found or not visible' using errcode = 'P0002';
  end if;

  insert into public.announcement_views(
    announcement_id, employee_id, first_viewed_at, last_viewed_at, view_count, created_by
  ) values (
    p_announcement_id, v_me, now(), now(), 1, auth.uid()
  )
  on conflict (announcement_id, employee_id) do update
    set last_viewed_at = now(),
        view_count = public.announcement_views.view_count + 1;

  select jsonb_build_object(
    'viewCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'reactionSummary', coalesce((
      select jsonb_object_agg(x.reaction_type, x.total)
      from (
        select r.reaction_type, count(*)::integer as total
        from public.announcement_reactions r
        where r.announcement_id = p_announcement_id
        group by r.reaction_type
      ) x
    ), '{}'::jsonb),
    'myReaction', (
      select r.reaction_type from public.announcement_reactions r
      where r.announcement_id = p_announcement_id and r.employee_id = v_me
    )
  ) into v_result;

  return v_result;
end;
$function$;



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
  v_tz text;
  v_local_time time;
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- Night shift / period boundaries
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex';
  -- Accuracy fallback
  v_max_accuracy numeric;
begin
  -- 0) Read centralized settings
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  -- 1) Service-role guard
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- 2) Basic validations
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

  -- 3) Passkey verification
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

  -- 4) Duplicate guard (60-second window)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- 5) Roster + shift assignment lookup (moved before sequencing for period computation)
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

  -- Load shift
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- 6) Night-shift detection: if local time < 12:00, check yesterday for crosses_midnight shift
  if v_local_time < '12:00:00'::time then
    declare
      v_yest_date date := v_work_date - 1;
      v_yest_shift public.shifts%rowtype;
      v_yest_shift_id uuid;
      v_has_open_yesterday boolean := false;
    begin
      -- Check yesterday's roster first
      select rd.shift_id into v_yest_shift_id
      from public.roster_days rd
      join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_yest_date
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last
      limit 1;

      -- Fallback to shift_assignments for yesterday
      if v_yest_shift_id is null then
        select sa.shift_id into v_yest_shift_id
        from public.shift_assignments sa
        where sa.employee_id = p_employee_id
          and sa.is_active = true
          and sa.effective_from <= v_yest_date
          and (sa.effective_to is null or sa.effective_to >= v_yest_date)
        order by sa.effective_from desc
        limit 1;
      end if;

      if v_yest_shift_id is not null then
        select * into v_yest_shift from public.shifts where id = v_yest_shift_id;
        if v_yest_shift.crosses_midnight then
          -- Check if there's an open attendance_daily for yesterday (check-in but no check-out)
          select true into v_has_open_yesterday
          from public.attendance_daily ad
          where ad.employee_id = p_employee_id
            and ad.work_date = v_yest_date
            and ad.first_check_in is not null
            and ad.last_check_out is null
            and ad.is_finalized = false;

          if v_has_open_yesterday then
            v_work_date := v_yest_date;
            v_crosses_midnight := true;
            v_shift := v_yest_shift;
            -- Re-lookup roster/assignment for yesterday
            select rd.shift_id, rd.geofence_id
              into v_roster_shift_id, v_roster_geofence_id
            from public.roster_days rd
            join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
            where rd.employee_id = p_employee_id
              and rd.work_date = v_yest_date
              and rd.day_status = 'scheduled'
            order by wr.published_at desc nulls last
            limit 1;

            select * into v_assignment
            from public.shift_assignments sa
            where sa.employee_id = p_employee_id
              and sa.is_active = true
              and sa.effective_from <= v_yest_date
              and (sa.effective_to is null or sa.effective_to >= v_yest_date)
            order by sa.effective_from desc
            limit 1;
          end if;
        end if;
      end if;
    end;
  end if;

  -- 7) Compute period boundaries

  -- 0460: ::timestamp صريح قبل at time zone؛ date وحدها تُرقّى
  -- إلى timestamptz عبر منطقة الجلسة فتنزلق النافذة (نفس علة 0169/0201).
  if v_crosses_midnight and v_shift.id is not null then
    -- Night shift: period = work_date+start_time → (work_date+1)+end_time
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    -- Day shift or no shift: full calendar day
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  -- 8) Finalized-period guard
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- 9) Sequencing check (period-based instead of date-based)
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
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

  -- 10) Impossible-travel guard (configurable speed from settings)
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

  -- 11) Geofence lookup + validation
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  -- *** FALLBACK (0201): إذا لم يُعثر على سياج عبر الجدول أو التعيين،
  -- يُؤخذ أول سياج نشط (مناسب لمنظمة ذات موقع واحد) ***
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

  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;

  -- Accuracy fallback chain: geofence.max_accuracy → settings → 100
  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- 12) Late calculation
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- 13) Insert event
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

  -- 14) Aggregate attendance_daily (period-based)
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
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

  -- 15) Update passkey last_used
  update public.passkey_credentials set last_used = v_now
  where id = p_passkey_credential_id;

  -- 16) Audit log
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_crosses_midnight,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;



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
  v_tz text;
  v_local_time time;
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  -- Night shift / period boundaries
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  -- Impossible-travel guard
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
  -- Accuracy fallback
  v_max_accuracy numeric;
begin
  -- 0) Read centralized settings
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  -- 1) Service-role guard (current_user check for biometric path)
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  -- 2) Basic validations
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_employee_id is null then
    raise exception 'attendance_identity_not_verified' using errcode = '28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
     or p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_attendance_location' using errcode = '22023';
  end if;

  -- 3) Duplicate guard (60-second window)
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  -- 4) Roster + shift assignment lookup (moved before sequencing)
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

  -- Load shift
  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  -- 5) Night-shift detection
  if v_local_time < '12:00:00'::time then
    declare
      v_yest_date date := v_work_date - 1;
      v_yest_shift public.shifts%rowtype;
      v_yest_shift_id uuid;
      v_has_open_yesterday boolean := false;
    begin
      select rd.shift_id into v_yest_shift_id
      from public.roster_days rd
      join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_yest_date
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last
      limit 1;

      if v_yest_shift_id is null then
        select sa.shift_id into v_yest_shift_id
        from public.shift_assignments sa
        where sa.employee_id = p_employee_id
          and sa.is_active = true
          and sa.effective_from <= v_yest_date
          and (sa.effective_to is null or sa.effective_to >= v_yest_date)
        order by sa.effective_from desc
        limit 1;
      end if;

      if v_yest_shift_id is not null then
        select * into v_yest_shift from public.shifts where id = v_yest_shift_id;
        if v_yest_shift.crosses_midnight then
          select true into v_has_open_yesterday
          from public.attendance_daily ad
          where ad.employee_id = p_employee_id
            and ad.work_date = v_yest_date
            and ad.first_check_in is not null
            and ad.last_check_out is null
            and ad.is_finalized = false;

          if v_has_open_yesterday then
            v_work_date := v_yest_date;
            v_crosses_midnight := true;
            v_shift := v_yest_shift;

            select rd.shift_id, rd.geofence_id
              into v_roster_shift_id, v_roster_geofence_id
            from public.roster_days rd
            join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
            where rd.employee_id = p_employee_id
              and rd.work_date = v_yest_date
              and rd.day_status = 'scheduled'
            order by wr.published_at desc nulls last
            limit 1;

            select * into v_assignment
            from public.shift_assignments sa
            where sa.employee_id = p_employee_id
              and sa.is_active = true
              and sa.effective_from <= v_yest_date
              and (sa.effective_to is null or sa.effective_to >= v_yest_date)
            order by sa.effective_from desc
            limit 1;
          end if;
        end if;
      end if;
    end;
  end if;

  -- 6) Compute period boundaries

  -- 0460: ::timestamp صريح قبل at time zone؛ date وحدها تُرقّى
  -- إلى timestamptz عبر منطقة الجلسة فتنزلق النافذة (نفس علة 0169/0201).
  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  -- 7) Finalized-period guard
  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  -- 8) Impossible-travel guard (configurable speed)
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

  -- 9) Sequencing check (period-based)
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;
  if p_event_type = 'CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  -- 10) Geofence lookup + validation
  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  -- *** FALLBACK (0201): إذا لم يُعثر على سياج عبر الجدول أو التعيين،
  -- يُؤخذ أول سياج نشط (مناسب لمنظمة ذات موقع واحد) ***
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
  if v_distance > v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode = '22023';
  end if;
  -- Accuracy fallback chain: geofence.max_accuracy → settings → 100
  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- 11) Late calculation
  if p_event_type = 'CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  end if;

  -- 12) Insert event
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

  -- 13) Aggregate attendance_daily (period-based)
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
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
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now()
  where attendance_daily.is_finalized = false;

  -- 14) Audit log
  perform public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة محلية موثقة داخل نطاق المجمع', null,
    jsonb_build_object(
      'method', 'local_biometric',
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id,
      'impossibleTravel', v_requires_review,
      'nightShift', v_crosses_midnight,
      'workDate', v_work_date
    )
  );

  return v_event_id;
end;
$$;



CREATE OR REPLACE FUNCTION public.record_daily_reports_views(p_report_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_recorded integer;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_report_ids is null or cardinality(p_report_ids) = 0 then
    return jsonb_build_object('recorded', 0);
  end if;

  with inserted as (
    insert into public.daily_report_views (report_id, employee_id, created_by, view_count)
    select t.id, v_me, auth.uid(), 1
    from unnest(p_report_ids) t(id)
    join public.daily_reports dr on dr.id = t.id
    on conflict (report_id, employee_id)
    do update set
      view_count = public.daily_report_views.view_count + 1,
      last_viewed_at = now()
    returning 1
  )
  select count(*) into v_recorded from inserted;

  return jsonb_build_object('recorded', v_recorded);
end;
$function$;



create or replace function public.record_dispute_settlement(p_case_id uuid,p_type text,p_from uuid,p_to uuid,p_text text default null,p_publication_place text default null,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.action.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN'; end if;
 if p_type not in ('verbal_apology','written_apology','group_apology','undertaking','mediation','follow_up','other') then raise exception 'INVALID_SETTLEMENT'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_settlements(case_id,apology_from,apology_to,settlement_type,apology_text,publication_place,due_at,created_by)
 values(p_case_id,p_from,p_to,p_type,nullif(trim(p_text),''),nullif(trim(p_publication_place),''),p_due_at,auth.uid()) returning id into v_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,assigned_to,due_at,execution_status,visibility,metadata)
 values(p_case_id,'settlement_implementation',v_status,'settlement_pending',coalesce(nullif(trim(p_text),''),p_type),public.current_employee_id(),auth.uid(),p_from,p_due_at,'pending','parties',jsonb_build_object('settlementId',v_id));
 update public.dispute_cases set status='settlement_pending',updated_at=now() where id=p_case_id;
 if p_from is not null then perform public.enqueue_dispute_notification(p_case_id,p_from,'settlement:'||v_id::text,'تسوية تنتظر التنفيذ','يرجى تنفيذ التسوية في الموعد المحدد وتسجيل التأكيد.','high'); end if;
 perform public.log_audit_event('dispute.settlement_recorded','workflow','notice','dispute_settlements',v_id,'تسجيل تسوية للمشكلة',null,jsonb_build_object('caseId',p_case_id,'type',p_type));
 return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.refresh_all_materialized_views()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_results  jsonb := '[]'::jsonb;
  v_start    timestamptz;
  v_elapsed  numeric;
BEGIN
  -- التحقق من صلاحية المستخدم (full-access فقط)
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'تحديث العروض المادية يتطلب صلاحية full-access.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ─── mv_daily_attendance_summary ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_daily_attendance_summary;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_daily_attendance_summary',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_daily_attendance_summary',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  -- ─── mv_department_headcount ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_department_headcount;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_department_headcount',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_department_headcount',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  -- ─── mv_monthly_request_stats ───
  BEGIN
    v_start := clock_timestamp();
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_monthly_request_stats;
    v_elapsed := round(EXTRACT(EPOCH FROM clock_timestamp() - v_start)::numeric, 2);
    v_results := v_results || jsonb_build_object(
      'view', 'mv_monthly_request_stats',
      'status', 'ok',
      'seconds', v_elapsed
    );
  EXCEPTION WHEN OTHERS THEN
    v_results := v_results || jsonb_build_object(
      'view', 'mv_monthly_request_stats',
      'status', 'error',
      'message', SQLERRM
    );
  END;

  RETURN jsonb_build_object(
    'refreshed_at', now(),
    'results', v_results
  );
END;
$$;



create or replace function public.refresh_kpi_attendance_inputs(p_cycle_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_cycle public.kpi_cycles; v_eval record; v_rules jsonb; v_count integer:=0;
 v_start date; v_end date; v_late integer; v_early integer; v_absent integer;
 v_missing integer; v_shortage numeric; v_pending boolean; v_score numeric; v_old numeric;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.attendance.refresh','performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 select attendance_rules into strict v_rules from public.kpi_policy_versions where id=v_cycle.policy_version_id;
 v_start:=date_trunc('month',v_cycle.period_month)::date;
 v_end:=least((v_start+interval '1 month'-interval '1 day')::date,(public.kpi_effective_deadline(v_cycle) at time zone 'Africa/Cairo')::date);

 for v_eval in
  select e.id,e.employee_id,c.id criterion_id from public.kpi_evaluations e
  join public.kpi_criteria c on c.template_id=e.template_id and c.code='ATTENDANCE'
  where e.cycle_id=p_cycle_id
 loop
  with daily as (
   select a.*,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='arrival' and p.status='approved') arrival_permit,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='departure' and p.status='approved') departure_permit,
    exists(select 1 from public.attendance_exceptions x where x.employee_id=a.employee_id and coalesce(x.work_date,a.work_date)=a.work_date and x.status in ('approved','resolved')) exception_settled,
    exists(select 1 from public.attendance_corrections x where x.employee_id=a.employee_id and x.work_date=a.work_date and x.status='approved') correction_settled,
    exists(select 1 from public.roster_days rd where rd.employee_id=a.employee_id and rd.work_date=a.work_date and rd.day_status in ('rest','holiday','leave','mission','cancelled')) roster_exempt,
    exists(select 1 from public.leave_requests lr join public.requests r on r.id=lr.request_id where lr.employee_id=a.employee_id and r.status in ('approved','pending') and a.work_date between lr.start_date and lr.end_date) leave_exempt,
    exists(select 1 from public.missions m join public.requests r on r.id=m.request_id where m.employee_id=a.employee_id and r.status='approved' and a.work_date between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date) mission_exempt,
    exists(select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id=wp.assignment_id where wp.employee_id=a.employee_id and wa.status='APPROVED' and coalesce(wa.counts_as_work_day,true) and a.work_date between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date) assignment_exempt,
    exists(select 1 from public.requests r where r.employee_id=a.employee_id and r.request_type in ('mission','convoy','fundraising') and r.status='pending' and a.work_date between (r.payload->>'startDate')::date and coalesce((r.payload->>'endDate')::date,(r.payload->>'startDate')::date)) request_pending_exempt,
    greatest(0,
      case when s.crosses_midnight then extract(epoch from ((s.end_time+interval '24 hours')-s.start_time))/60
           else extract(epoch from (s.end_time-s.start_time))/60 end-coalesce(s.break_minutes,0)
    )::integer scheduled_minutes
   from public.attendance_daily a left join public.shifts s on s.id=a.shift_id
   where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end
  ), scored as (
   select *, (status in ('on_leave','holiday','weekend') or roster_exempt or leave_exempt or mission_exempt or assignment_exempt or request_pending_exempt) exempt
   from daily
  )
  select
   count(*) filter(where not exempt and late_minutes>0 and not arrival_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and early_leave_minutes>0 and not departure_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status='absent' and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status<>'absent' and (status in ('partial','pending') or first_check_in is null or last_check_out is null) and not exception_settled and not correction_settled),
   coalesce(sum(case when not exempt and status<>'absent' and not exception_settled and not correction_settled and scheduled_minutes>work_minutes
     then least((v_rules->>'maxShortagePerDay')::numeric,ceil((scheduled_minutes-work_minutes)::numeric/60)*(v_rules->>'shortagePerHour')::numeric) else 0 end),0)
  into v_late,v_early,v_absent,v_missing,v_shortage from scored;

  select exists(
   select 1 from public.attendance_daily a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
   union all select 1 from public.attendance_events a where a.employee_id=v_eval.employee_id and (a.event_at at time zone 'Africa/Cairo')::date between v_start and v_end and a.requires_review
   union all select 1 from public.attendance_exceptions a where a.employee_id=v_eval.employee_id and coalesce(a.work_date,v_start) between v_start and v_end and a.status='open'
   union all select 1 from public.attendance_corrections a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
  ) into v_pending;

  v_score:=greatest(0,round(20-
   v_late*(v_rules->>'late')::numeric-v_early*(v_rules->>'earlyLeave')::numeric-
   v_absent*(v_rules->>'unexcusedAbsence')::numeric-v_missing*(v_rules->>'missingPunch')::numeric-v_shortage,2));
  select score into v_old from public.kpi_scores where evaluation_id=v_eval.id and criterion_id=v_eval.criterion_id and reviewer_stage='hr';
  insert into public.kpi_attendance_snapshots(evaluation_id,period_start,period_end,late_count,early_leave_count,unexcused_absence_count,shortage_penalty,missing_punch_count,score,has_pending_items,details,calculated_by)
  values(v_eval.id,v_start,v_end,v_late,v_early,v_absent,v_shortage,v_missing,v_score,v_pending,jsonb_build_object('rules',v_rules),auth.uid())
  on conflict(evaluation_id) do update set period_start=excluded.period_start,period_end=excluded.period_end,late_count=excluded.late_count,early_leave_count=excluded.early_leave_count,unexcused_absence_count=excluded.unexcused_absence_count,shortage_penalty=excluded.shortage_penalty,missing_punch_count=excluded.missing_punch_count,score=excluded.score,has_pending_items=excluded.has_pending_items,details=excluded.details,calculated_at=now(),calculated_by=auth.uid(),updated_at=now();
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_eval.criterion_id,v_score,'hr','محسوب آليًا من الحضور والانصراف والاستثناءات والتكليفات المعتمدة',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  if v_old is distinct from v_score then
   perform public.log_audit_event('kpi.attendance.recalculated','workflow','notice','kpi_evaluations',v_eval.id,'إعادة حساب درجة الحضور',null,jsonb_build_object('oldScore',v_old,'newScore',v_score,'late',v_late,'earlyLeave',v_early,'absence',v_absent,'missingPunch',v_missing,'shortagePenalty',v_shortage,'pending',v_pending));
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end $$;



create or replace function public.register_dispute_evidence(p_case_id uuid,p_title text,p_storage_path text,p_mime_type text,p_file_size_bytes bigint,p_visibility text default 'committee_only',p_description text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
 if not public.can_access_dispute(p_case_id) or length(trim(coalesce(p_title,'')))<2 or p_file_size_bytes<=0 or p_file_size_bytes>15728640 then raise exception 'INVALID_EVIDENCE'; end if;
 if split_part(p_storage_path,'/',1)<>p_case_id::text or p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','audio/mpeg','audio/mp4','video/mp4','text/plain') then raise exception 'INVALID_EVIDENCE_FILE'; end if;
 if p_visibility not in ('committee_only','submitter_and_committee','parties') then raise exception 'INVALID_VISIBILITY'; end if;
 insert into public.dispute_evidence(case_id,evidence_type,title,description,storage_path,mime_type,file_size_bytes,submitted_by,visibility,is_confidential,created_by)
 values(p_case_id,case when p_mime_type like 'image/%' then 'photo' when p_mime_type like 'audio/%' then 'audio' when p_mime_type like 'video/%' then 'video' else 'document' end,trim(p_title),nullif(trim(p_description),''),p_storage_path,p_mime_type,p_file_size_bytes,v_emp,p_visibility,p_visibility<>'parties',auth.uid()) returning id into v_id;
 perform public.log_audit_event('dispute.evidence_added','data','notice','dispute_evidence',v_id,'إضافة دليل للمشكلة',null,jsonb_build_object('caseId',p_case_id,'mimeType',p_mime_type));
 return v_id;
end $$;



create or replace function public.register_employee_document_admin(p_employee_id uuid,p_doc_type text,p_title text,p_storage_path text,p_doc_number text default null,p_issue_date date default null,p_expiry date default null,p_file_hash text default null,p_mime_type text default null,p_size_bytes bigint default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.can_access_employee(p_employee_id,'documents.employee.manage')) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_doc_type))<2 or length(trim(p_title))<2 or length(trim(p_storage_path))<3 then raise exception 'INVALID_DOCUMENT'; end if;
 insert into public.employee_documents(employee_id,doc_type,title,doc_number,issue_date,expiry,storage_path,file_hash,mime_type,size_bytes,is_verified,status,created_by)
 values(p_employee_id,trim(p_doc_type),trim(p_title),p_doc_number,p_issue_date,p_expiry,trim(p_storage_path),p_file_hash,p_mime_type,p_size_bytes,false,'active',auth.uid()) returning id into v_id;
 perform public.log_audit_event('documents.employee.registered','data','notice','employee_documents',v_id,'تسجيل مستند موظف',null,jsonb_build_object('employeeId',p_employee_id,'docType',p_doc_type)); return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.register_live_location_map_snapshot(p_request_id uuid, p_storage_path text)
 RETURNS location_request_responses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.location_request_responses;
begin
  select * into v_req from public.live_location_requests
  where id = p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  if p_storage_path not like v_me::text || '/' || p_request_id::text || '/%.png' then
    raise exception 'مسار لقطة الخريطة غير صالح' using errcode = '42501';
  end if;

  update public.location_request_responses
  set map_snapshot_storage_path = p_storage_path,
      metadata = metadata || jsonb_build_object(
        'mapSnapshotBucket', 'live-location-map-snapshots',
        'mapSnapshotRegisteredAt', now()
      )
  where request_id = p_request_id and employee_id = v_me
  returning * into v_row;
  if not found then
    raise exception 'نقطة الموقع مطلوبة قبل لقطة الخريطة' using errcode = '22023';
  end if;

  perform public.log_audit_event(
    'live_location_map_snapshot_registered', 'security', 'info',
    'location_request_responses', v_row.id, 'تسجيل لقطة خريطة خاصة', null,
    jsonb_build_object('requestId', p_request_id)
  );
  return v_row;
end;
$function$;



create or replace function public.register_live_location_video(p_request_id uuid,p_storage_path text,p_duration_seconds integer,p_size_bytes bigint,p_mime_type text,p_latitude double precision,p_longitude double precision,p_accuracy double precision)
returns public.live_location_videos_meta
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_me uuid:=public.current_employee_id(); v_req public.live_location_requests; v_row public.live_location_videos_meta;
begin
  select * into v_req from public.live_location_requests where id=p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status<>'active' or v_req.expires_at<=now() or v_req.metadata->>'mode'<>'video_5s' then raise exception 'video request is not active' using errcode='22023'; end if;
  if p_duration_seconds not between 4 and 7 then raise exception 'video must be approximately five seconds' using errcode='22023'; end if;
  if p_size_bytes<=0 or p_size_bytes>15728640 then raise exception 'invalid video size' using errcode='22023'; end if;
  if p_storage_path not like v_me::text||'/'||p_request_id::text||'/%' then raise exception 'invalid storage path' using errcode='42501'; end if;
  insert into public.live_location_videos_meta(live_request_id,employee_id,storage_path,storage_bucket,duration_seconds,size_bytes,mime_type,captured_lat,captured_lng,captured_accuracy,captured_at,status,created_by)
  values(p_request_id,v_me,p_storage_path,'live-location-videos',p_duration_seconds,p_size_bytes,p_mime_type,p_latitude,p_longitude,p_accuracy,now(),'ready',auth.uid()) returning * into v_row;
  update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id;
  perform public.log_audit_event('live_location.video_registered','security','warning','live_location_videos_meta',v_row.id,'تسجيل فيديو تحقق حي',null,jsonb_build_object('requestId',p_request_id,'durationSeconds',p_duration_seconds));
  return v_row;
end;
$$;



CREATE OR REPLACE FUNCTION public.register_my_device(p_installation_id text, p_platform text, p_device_name text, p_device_model text, p_os_version text, p_app_version text, p_app_build integer, p_environment text DEFAULT 'production'::text, p_push_enabled boolean DEFAULT false, p_biometric_available boolean DEFAULT false, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS managed_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_row public.managed_devices;
  v_existing_user uuid;
  v_employee_id uuid := public.current_employee_id();
  v_identifier_hash text;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_installation_id, ''))) < 12 then
    raise exception 'معرّف جهاز غير صالح' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  if p_environment not in ('development', 'staging', 'production') then
    raise exception 'invalid environment' using errcode = '22023';
  end if;

  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  select user_id into v_existing_user
  from public.managed_devices
  where installation_id = p_installation_id;

  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'الجهاز مسجل على حساب آخر' using errcode = '42501';
  end if;

  insert into public.managed_devices(
    installation_id, user_id, employee_id, platform, device_name, device_model,
    os_version, app_version, app_build, environment, push_enabled,
    biometric_available, last_seen_at, metadata
  ) values (
    p_installation_id, auth.uid(), v_employee_id, p_platform,
    nullif(trim(p_device_name), ''), nullif(trim(p_device_model), ''),
    nullif(trim(p_os_version), ''), coalesce(nullif(trim(p_app_version), ''), '0.0.0'),
    greatest(coalesce(p_app_build, 0), 0), p_environment,
    coalesce(p_push_enabled, false), coalesce(p_biometric_available, false),
    now(), coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id = excluded.user_id,
    employee_id = excluded.employee_id,
    platform = excluded.platform,
    device_name = excluded.device_name,
    device_model = excluded.device_model,
    os_version = excluded.os_version,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    environment = excluded.environment,
    push_enabled = excluded.push_enabled,
    biometric_available = excluded.biometric_available,
    last_seen_at = now(),
    metadata = excluded.metadata,
    status = case
      when public.managed_devices.status = 'retired' then 'active'
      else public.managed_devices.status
    end
  returning * into v_row;

  if v_employee_id is not null and p_platform in ('android', 'ios') then
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, device_name,
      platform, status, approved_at, last_used_at, metadata
    ) values (
      v_employee_id, auth.uid(), v_identifier_hash, null,
      coalesce(nullif(trim(p_device_name), ''), nullif(trim(p_device_model), '')),
      p_platform, 'active', now(), now(), jsonb_build_object(
        'kind', 'local_biometric',
        'managedDeviceId', v_row.id,
        'biometricAvailable', coalesce(p_biometric_available, false)
      )
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      device_name = excluded.device_name,
      platform = excluded.platform,
      last_used_at = now(),
      status = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then 'active'
        else public.employee_devices.status
      end,
      approved_at = now(),
      revoked_at = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revoked_at
      end,
      revocation_source = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revocation_source
      end,
      rejection_reason = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.rejection_reason
      end,
      metadata = coalesce(public.employee_devices.metadata, '{}'::jsonb)
        || excluded.metadata
        || case
          when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
            then jsonb_build_object(
              'reregistered', true,
              'reregisteredAt', now(),
              'previousStatus', public.employee_devices.status
            )
          else '{}'::jsonb
        end;
  end if;

  perform public.log_security_event(
    'device.registered', 'low', 'allowed', v_identifier_hash,
    jsonb_build_object(
      'platform', p_platform,
      'appVersion', p_app_version,
      'appBuild', p_app_build,
      'biometricAvailable', p_biometric_available,
      'autoAccepted', true
    )
  );

  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.reject_break_glass(p_request_id uuid, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.break_glass_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'رفض الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  update public.break_glass_requests set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=p_reason
  where id=p_request_id and status='pending' returning * into v_req;
  if not found then raise exception 'الطلب المعلق غير موجود' using errcode='P0002'; end if;
  perform public.log_security_event('break_glass.rejected','high','blocked',v_req.target_user_id::text,jsonb_build_object('requestId',v_req.id,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'تم رفض طلب Break Glass',
    format('رُفض طلب الوصول الاستثنائي.%s', E'\n'||p_reason),
    'security', 'high', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$function$;



create or replace function public.remove_employee_department(
  p_employee_id uuid,
  p_department_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- تحقق من الصلاحية
  if not (public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  delete from public.employee_departments
  where employee_id = p_employee_id and department_id = p_department_id;

  return found;
end $$;



CREATE OR REPLACE FUNCTION public.request_attendance_correction(p_work_date date, p_type text, p_reason text, p_check_in timestamp with time zone DEFAULT NULL::timestamp with time zone, p_check_out timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT NULL::text, p_attachment_path text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_daily uuid;
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 if p_work_date>(now() at time zone 'Africa/Cairo')::date or length(trim(p_reason))<5 then raise exception 'INVALID_CORRECTION'; end if;
 select id into v_daily from public.attendance_daily where employee_id=v_emp and work_date=p_work_date;
 insert into public.attendance_corrections(employee_id,attendance_daily_id,work_date,correction_type,requested_check_in,requested_check_out,requested_status,reason,attachment_path,created_by)
 values(v_emp,v_daily,p_work_date,p_type,p_check_in,p_check_out,p_status,trim(p_reason),p_attachment_path,auth.uid()) returning id into v_id;
 perform public.notify_employees_with_permission(
   'attendance.correction.review',
   'طلب تصحيح حضور جديد',
   format('طلب تصحيح حضور بتاريخ %s (%s)', p_work_date, coalesce(p_type, '')),
   'attendance', 'normal', 'attendance_corrections', v_id,
   '{}'::jsonb, v_emp);
 return v_id;
end $function$;



CREATE OR REPLACE FUNCTION public.request_break_glass(p_target_user_id uuid, p_role_id uuid, p_duration_minutes integer, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.break_glass_requests; v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.request')) then raise exception 'طلب الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  select * into v_role from public.roles where id=p_role_id;
  if not found then raise exception 'role not found' using errcode='P0002'; end if;
  if p_duration_minutes not between 5 and 240 then raise exception 'المدة خارج النطاق' using errcode='22023'; end if;
  insert into public.break_glass_requests(target_user_id,requested_role_id,duration_minutes,reason,requested_by)
  values(p_target_user_id,p_role_id,p_duration_minutes,trim(p_reason),auth.uid()) returning * into v_row;
  perform public.log_security_event('break_glass.requested','critical','detected',p_target_user_id::text,
    jsonb_build_object('requestId',v_row.id,'role',v_role.slug,'durationMinutes',p_duration_minutes,'reason',p_reason));
  perform public.notify_employees_with_permission(
    'access.break_glass.approve',
    'طلب Break Glass بانتظار اعتمادك',
    format('طلب وصول استثنائي لدور %s لمدة %s دقيقة.', v_role.slug, p_duration_minutes),
    'security', 'high', 'break_glass_requests', v_row.id,
    jsonb_build_object('role', v_role.slug, 'durationMinutes', p_duration_minutes));
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.request_device_replacement(p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_user_id uuid := auth.uid();
begin
  if v_employee_id is null or v_user_id is null then
    raise exception 'يلزم موظف مسجل الدخول' using errcode = '42501';
  end if;

  -- V24: Do NOT revoke active devices. The old device stays usable until
  -- admin approves the new one. approve_device() (0171) will handle
  -- replacement when it sets the new device to 'active'.

  -- Log the request for audit and admin notification
  perform public.log_security_event(
    'device.replacement_requested',
    'high', 'allowed',
    null,
    jsonb_build_object(
      'employeeId', v_employee_id,
      'reason', p_reason
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', 'جهازك الحالي سيبقى نشطاً حتى اعتماد الجهاز الجديد من قبل المسؤول.'
  );
end;
$function$;



create or replace function public.request_live_location(p_employee_id uuid, p_mode text default 'snapshot', p_reason text default '')
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_needs_point   boolean := true;
  v_needs_video   boolean := false;
  v_row           public.live_location_requests;
  v_target_user   uuid;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not public.can_access_employee(p_employee_id,'live_location.request') then raise exception 'target outside permitted scope' using errcode='42501'; end if;
  if p_employee_id=v_me then raise exception 'cannot request own location' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists(select 1 from public.employees where id=p_employee_id and status='active') then raise exception 'employee is not active' using errcode='P0002'; end if;

  -- خريطة الأوضاع → المدة بالدقائق + متطلبات النقطة/الفيديو
  v_duration := case p_mode
    when 'snapshot'       then 1
    when 'video_5s'       then 2
    when 'location_video' then 2      -- الوضع المدمج للمدير التنفيذي: نقطة + فيديو 5 ثوانٍ
    when 'track_5'        then 5
    when 'track_10'       then 10
    when 'track_15'       then 15
    when 'track_30'       then 30
    else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;

  if p_mode = 'video_5s' then
    v_video_seconds := 5; v_needs_point := false; v_needs_video := true;
  elsif p_mode = 'location_video' then
    v_video_seconds := 5; v_needs_point := true;  v_needs_video := true;
  end if;

  if exists(select 1 from public.live_location_requests where employee_id=p_employee_id and status in ('pending','accepted','active') and (expires_at is null or expires_at>now())) then
    raise exception 'employee already has an active location request' using errcode='23505';
  end if;

  insert into public.live_location_requests(employee_id,requested_by,reason,status,purpose,requested_at,expires_at,duration_minutes,metadata,created_by)
  values(
    p_employee_id,v_me,trim(p_reason),'pending','verification',now(),now()+interval '5 minutes',v_duration,
    jsonb_build_object(
      'mode',p_mode,
      'videoSeconds',v_video_seconds,
      'needsPoint',v_needs_point,
      'needsVideo',v_needs_video
    ),
    auth.uid()
  ) returning * into v_row;

  select user_id into v_target_user from public.employees where id=p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,metadata,created_by)
    values(
      v_target_user,p_employee_id,
      'طلب موقع عاجل',
      'طلب موقع من '||coalesce((select full_name_ar from public.employees where id=v_me),'الإدارة')||' — السبب: '||trim(p_reason),
      'system','urgent','ahlashabab://action/live_location_request/'||v_row.id::text,
      'live_location_request',v_row.id,
      -- بيانات الإشعار العاجل: شاشة كاملة + قناة عالية الأولوية + Deep Link
      jsonb_build_object(
        'fullScreen', true,
        'kind', 'live_location_request',
        'entityId', v_row.id,
        'channel', 'urgent_location',
        'sound', 'urgent',
        'requiresVideo', v_needs_video,
        'deepLink', 'ahlashabab://action/live_location_request/'||v_row.id::text
      ),
      auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested','security','warning','live_location_requests',v_row.id,
    'طلب موقع حي',null,
    jsonb_build_object('employeeId',p_employee_id,'mode',p_mode,'duration',v_duration,'needsVideo',v_needs_video,'reason',trim(p_reason))
  );

  -- نبضة فورية لإرسال الإشعار العاجل دون انتظار كرون الدقيقتين (اختيارية وآمنة).
  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$$;



create or replace function public.request_type_label(p_type text)
returns text
language sql immutable strict
as $$
  select case p_type
    when 'leave' then 'إجازة'
    when 'mission' then 'مأمورية'
    when 'convoy' then 'قافلة'
    when 'fundraising' then 'فاندي'
    when 'late_permit' then 'إذن تأخير'
    when 'early_permit' then 'إذن انصراف مبكر'
    when 'attendance_correction' then 'تصحيح حضور'
    else coalesce(p_type, '')
  end;
$$;



create or replace function public.reschedule_kpi_cycle(p_cycle_id uuid,p_open_at timestamptz,p_deadline_at timestamptz,p_reason text)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 or p_open_at is null or p_deadline_at is null or p_deadline_at<=p_open_at then raise exception 'INVALID_SCHEDULE'; end if;
 update public.kpi_cycles set scheduled_open_at=p_open_at,deadline_at=p_deadline_at,extended_until=null,
  self_due_at=p_deadline_at,manager_due_at=p_deadline_at,secretary_due_at=p_deadline_at,executive_due_at=p_deadline_at,
  override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now()
 where id=p_cycle_id returning * into v_cycle;
 if v_cycle.id is null then raise exception 'CYCLE_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.cycle.rescheduled','workflow','warning','kpi_cycles',p_cycle_id,'تعديل موعد دورة KPI',trim(p_reason),jsonb_build_object('openAt',p_open_at,'deadlineAt',p_deadline_at));
 return v_cycle;
end $$;



CREATE OR REPLACE FUNCTION public.resolve_mobile_action_target(p_action_id text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
  v_resolved_kind text;
begin
  -- تطبيع الأسماء المترادفة القادمة من الإشعارات ومن تطبيق الموبايل:
  -- location/location_request/live_location/live_location_request →
  --   live_location_request (بالإضافة إلى الصيغة الجمعية live_location_requests)
  -- attendance_alert/punch_reminder/attendance/attendance_daily/
  --   attendance_event/attendance_corrections/overtime_records/work_rosters → attendance
  -- kpi_evaluation → kpi, request_decision/requests → request, dispute_case → dispute
  v_resolved_kind := case v_kind
    when 'location' then 'live_location_request'
    when 'location_request' then 'live_location_request'
    when 'live_location_request' then 'live_location_request'
    when 'live_location' then 'live_location_request'
    when 'live_location_requests' then 'live_location_request'
    when 'attendance_alert' then 'attendance'
    when 'punch_reminder' then 'attendance'
    when 'attendance' then 'attendance'
    when 'attendance_daily' then 'attendance'
    when 'attendance_event' then 'attendance'
    when 'attendance_corrections' then 'attendance'
    when 'overtime_records' then 'attendance'
    when 'work_rosters' then 'attendance'
    when 'request' then 'request'
    when 'requests' then 'request'
    when 'request_decision' then 'request'
    when 'kpi' then 'kpi'
    when 'kpi_evaluation' then 'kpi'
    when 'decision' then 'decision'
    when 'dispute' then 'dispute'
    when 'dispute_case' then 'dispute'
    when 'task' then 'task'
    when 'announcement' then 'announcement'
    when 'recognition' then 'recognition'
    else null
  end;

  if v_resolved_kind is null then
    raise exception 'unsupported action kind' using errcode = '22023';
  end if;

  -- strip prefix إن وُجد (kind-uuid)
  if position(v_resolved_kind || '-' in lower(v_raw)) = 1 then
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  end if;

  begin
    v_uuid := v_raw::uuid;
  exception when others then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end;

  -- live_location_request: تخويل خاص (لا يمر عبر get_mobile_action_target)
  if v_resolved_kind = 'live_location_request' then
    select * into v_req from public.live_location_requests where id = v_uuid;
    if not found then
      raise exception 'هدف الإجراء غير موجود' using errcode = 'P0002';
    end if;
    if not (
      v_req.employee_id = public.current_employee_id()
      or v_req.requested_by = public.current_employee_id()
      or public.current_is_full_access()
      or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
    ) then
      raise exception 'لا تملك صلاحية على هذا الموظف' using errcode = '42501';
    end if;

    return jsonb_build_object(
      'kind', v_resolved_kind,
      'recordId', v_uuid,
      'mobileRoute', 'live_location_request'
    );
  end if;

  -- بقية الأنواع: المرور عبر الدالة الأم التي تحمل التخويل المناسب
  return public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
end;
$function$;



create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
  v_dept_id uuid;
  v_is_operations boolean := false;
  v_executive_employee_id uuid;
begin
  -- المدير المباشر (primary) من الهيكل الإداري
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= p_as_of
    and (effective_to is null or effective_to >= p_as_of)
  order by effective_from desc
  limit 1;

  -- منع الموافقة الذاتية: لو صار المدير هو المُقدِّم نفسه، اصعد لمديره
  if v_mgr is not null and v_mgr = p_employee_id then
    select manager_employee_id into v_mgr
    from public.manager_relations
    where employee_id = p_employee_id
      and relation_type = 'primary'
      and manager_employee_id <> p_employee_id
      and effective_from <= p_as_of
      and (effective_to is null or effective_to >= p_as_of)
    order by effective_from desc
    limit 1;
  end if;

  -- V17 §1.2: توجيه طلبات التشغيل للمدير التنفيذي
  select e.department_id into v_dept_id
  from public.employees e
  where e.id = p_employee_id and e.is_active and not e.is_deleted;

  if v_dept_id is not null then
    select exists(
      with recursive dept_tree as (
        select d.id, d.slug, d.parent_id
        from public.departments d where d.id = v_dept_id
        union all
        select p.id, p.slug, p.parent_id
        from public.departments p
        join dept_tree dt on dt.parent_id = p.id
      )
      select 1 from dept_tree where slug like 'operations%'
    ) into v_is_operations;
  end if;

  if v_is_operations then
    select e.id into v_executive_employee_id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'executive'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    limit 1;

    if v_executive_employee_id is not null then
      v_mgr := v_executive_employee_id;
    end if;
  end if;

  -- صلاحية requests.approve: أي موظف نشط يملك صلاحية الموافقة على الطلبات
  if v_mgr is null then
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where p.code = 'requests.approve'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    limit 1;
  end if;

  -- سقوط HR: يضمن ألا تُيتم المهمة بلا معتمد (0385)
  if v_mgr is null then
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'hr-manager'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    limit 1;
  end if;

  if v_mgr is null then
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'hr-specialist'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    limit 1;
  end if;

  return v_mgr;
end $$;



CREATE OR REPLACE FUNCTION public.respond_live_location_request(p_request_id uuid, p_accept boolean)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  declare
    v_me uuid := public.current_employee_id();
    v_row public.live_location_requests;
    v_window_minutes integer;
  begin
    select * into v_row
    from public.live_location_requests
    where id = p_request_id
    for update;

    if not found or v_row.employee_id is distinct from v_me then
      raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
    end if;
    if v_row.status <> 'pending' or v_row.expires_at <= now() then
      raise exception 'الطلب لم يعد قيد الانتظار' using errcode = '22023';
    end if;

    if p_accept then
      -- V25: لا تقل نافذة الجلسة عن 5 دقائق حتى لو كان duration_minutes=1
      -- (لقطة). كانت الدقيقة الواحدة تفشل الإرسال عند تأخر GPS وتبقي الطلب
      -- active، فتستمر إعادة إرسال الإشعار إلى الأبد.
      v_window_minutes := greatest(coalesce(v_row.duration_minutes, 5), 5);
      update public.live_location_requests
      set status = 'active',
          responded_at = now(),
          starts_at = now(),
          expires_at = now() + make_interval(mins => v_window_minutes)
      where id = p_request_id
      returning * into v_row;
    else
      update public.live_location_requests
      set status = 'rejected',
          responded_at = now()
      where id = p_request_id
      returning * into v_row;
    end if;

    perform public.log_audit_event(
      case when p_accept then 'live_location.accepted' else 'live_location.rejected' end,
      'security',
      'info',
      'live_location_requests',
      v_row.id,
      'رد على طلب موقع',
      null,
      jsonb_build_object('accepted', p_accept)
    );
    return v_row;
  end;
  $function$;



CREATE OR REPLACE FUNCTION public.resubmit_my_request(p_request_id uuid, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me      uuid := public.current_employee_id();
  v_req     public.requests;
  v_def     public.workflow_definitions;
  v_manager uuid;
  v_due     timestamptz;
  v_esc     timestamptz;
  v_first_approver uuid;
  v_exec_emp uuid;
  v_label   text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- المالك حصراً
  if v_req.employee_id <> v_me then
    raise exception 'FORBIDDEN: only the requester may resubmit' using errcode = '42501';
  end if;

  -- من المرفوض/المُرجَع فقط
  if v_req.status not in ('rejected', 'returned') then
    raise exception 'ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT' using errcode = '22023';
  end if;

  -- الأنواع القابلة لإعادة الرفع (نفس أنواع submit_my_request عدا التصحيح)
  if v_req.request_type not in
     ('leave','mission','convoy','fundraising','late_permit','early_permit') then
    raise exception 'TYPE_NOT_RESUBMITTABLE' using errcode = '22023';
  end if;

  -- تحقق الطول (مطابق لقيود الجدول)
  if p_title is null or length(trim(p_title)) < 3 or length(trim(p_title)) > 300 then
    raise exception 'INVALID_TITLE_LENGTH' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'INVALID_REASON_LENGTH' using errcode = '22023';
  end if;

  -- 0457: استخدام resolve_request_approver بدلاً من lookup مباشر.
  -- يضمن التوجيه الصحيح لطلبات التشغيل→تنفيذي + السقوط على HR + منع الموافقة الذاتية.
  v_manager := public.resolve_request_approver(v_req.employee_id);

  -- مهلات السير من التعريف النشط
  if v_req.workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = v_req.workflow_definition_id;
  end if;
  if v_def.id is null or not v_def.is_active then
    select * into v_def from public.workflow_definitions
      where request_type = v_req.request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;
  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  -- 1) تحديث الطلب وتصفير القرار
  update public.requests set
    title                = trim(p_title),
    reason               = trim(p_reason),
    payload              = coalesce(p_payload, '{}'::jsonb),
    status               = 'pending',
    workflow_status      = 'submitted',
    current_step_order   = 1,
    manager_employee_id  = coalesce(v_manager, manager_employee_id),
    decision_due_at      = v_due,
    escalation_deadline  = v_esc,
    escalated_at         = null,
    decided_at           = null,
    decided_by           = null,
    updated_at           = now()
  where id = v_req.id
  returning * into v_req;

  -- 2) خطوات جديدة من التعريف (الأولى نشطة بمهلتها)
  delete from public.request_steps where request_id = v_req.id;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_req.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then v_manager
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours := ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    -- 3) إعادة فتح نسخة السير نفسها (قيد فريد: نسخة واحدة لكل طلب)
    update public.workflow_instances
      set definition_id      = v_def.id,
          definition_version = coalesce(v_def.version, 1),
          status             = 'running',
          current_step_order = 1,
          updated_at         = now()
      where request_id = v_req.id;

    if not found then
      insert into public.workflow_instances (
        definition_id, request_id, definition_version, status, current_step_order, created_by
      ) values (
        v_def.id, v_req.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
      );
    end if;
  end if;

  -- 4) توثيق الإجراء
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    v_req.id, v_me, 'submit', 'rejected', 'pending', trim(p_reason), auth.uid()
  );

  -- 5) الإشعارات
  v_label := format('%s — %s (مُعادة بعد تعديل)',
    public.request_type_label(v_req.request_type), coalesce(v_req.title, ''));

  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_req.id and s.status = 'active'
  order by s.step_order limit 1;
  if v_first_approver is null then
    v_first_approver := v_req.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_req.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب مُعدّل بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'workflowStatus', 'submitted',
        'resubmitted', true,
        'deepLink', '/requests/' || v_req.id
      )
    );
  end if;

  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'طلب مُعدّل — للمراجعة',
      v_label,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'resubmitted', true,
        'infoOnly', false
      )
    );
  end if;

  return to_jsonb(v_req);
end;
$function$;



create or replace function public.return_kpi_stage(
  p_evaluation_id uuid,
  p_target_stage text,
  p_note text
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_allowed_target text;
  v_perm text;
begin
  if length(trim(coalesce(p_note,''))) < 5 then
    raise exception 'return note is required' using errcode = '22023';
  end if;
  select * into v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
  if not found then raise exception 'KPI evaluation not found' using errcode='P0002'; end if;
  if v_eval.locked then raise exception 'KPI evaluation is locked' using errcode='55000'; end if;

  case v_eval.current_stage
    when 'manager' then v_allowed_target := 'self'; v_perm := 'performance.kpi.manager_assess';
    when 'secretary' then v_allowed_target := 'manager'; v_perm := 'performance.kpi.secretary_review';
    when 'executive' then v_allowed_target := 'secretary'; v_perm := 'performance.kpi.executive_review';
    else raise exception 'current KPI stage cannot be returned' using errcode='55000';
  end case;
  if p_target_stage is distinct from v_allowed_target then
    raise exception 'invalid return target: expected %', v_allowed_target using errcode='22023';
  end if;
  if not (public.current_is_full_access() or public.has_permission(v_perm)) then
    raise exception 'insufficient privilege: % required', v_perm using errcode='42501';
  end if;
  if v_eval.current_stage='manager' and not public.current_is_full_access()
     and not public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess') then
    raise exception 'employee is outside manager scope' using errcode='42501';
  end if;

  update public.kpi_evaluations
  set stage=p_target_stage,current_stage=p_target_stage,updated_at=now()
  where id=p_evaluation_id returning * into v_eval;
  perform public.log_audit_event(
    'kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,
    'إعادة تقييم الأداء للمرحلة السابقة',null,
    jsonb_build_object('from',case p_target_stage when 'self' then 'manager' when 'manager' then 'secretary' else 'executive' end,'to',p_target_stage,'note',trim(p_note))
  );
  return v_eval;
end;
$$;



CREATE OR REPLACE FUNCTION public.review_daily_report(p_report_id uuid, p_manager_comment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_report public.daily_reports%rowtype;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_manager_comment, ''))) < 3 then
    raise exception 'تعليق المدير مطلوب' using errcode = '22023';
  end if;

  select * into v_report from public.daily_reports where id=p_report_id for update;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;
  if v_report.employee_id = v_manager_id then
    raise exception 'التقييم الذاتي غير مسموح هنا' using errcode = '42501';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(v_report.employee_id, 'reports.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=v_report.employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'نطاق مراجعة التقارير مرفوض' using errcode = '42501';
  end if;

  update public.daily_reports
  set manager_comment=trim(p_manager_comment), reviewed_by=v_manager_id, reviewed_at=now(), updated_at=now()
  where id=p_report_id;

  return jsonb_build_object('id', p_report_id, 'reviewedBy', v_manager_id, 'reviewedAt', now(), 'managerComment', trim(p_manager_comment));
end;
$function$;



CREATE OR REPLACE FUNCTION public.revoke_credential(p_key_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_found boolean;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'revoke_credential يتطلب صلاحية full-access';
  END IF;

  UPDATE public.credential_vault
     SET is_active   = false,
         updated_at  = now()
   WHERE key_name    = p_key_name
     AND is_active   = true;

  v_found := FOUND;

  IF v_found THEN
    PERFORM public.log_audit_event(
      p_event_type   := 'credential.revoked',
      p_category     := 'security',
      p_severity     := 'warning',
      p_target_table := 'credential_vault',
      p_summary_ar   := 'تعطيل اعتماد: ' || p_key_name,
      p_metadata     := jsonb_build_object('key_name', p_key_name)
    );
  END IF;

  RETURN v_found;
END;
$$;



CREATE OR REPLACE FUNCTION public.revoke_managed_device(p_device_id uuid, p_reason text)
 RETURNS managed_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.managed_devices;
begin
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'سحب الجهاز مرفوض' using errcode='42501';
  end if;
  update public.managed_devices set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revoke_reason=p_reason
  where id=p_device_id returning * into v_row;
  if not found then raise exception 'لم يتم العثور على الجهاز' using errcode='P0002'; end if;
  perform public.log_security_event('device.revoked','high','blocked',v_row.installation_id,jsonb_build_object('reason',p_reason,'userId',v_row.user_id));
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.revoke_my_passkey(p_credential_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_credential public.passkey_credentials;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode='42501';
  end if;

  select * into v_credential
  from public.passkey_credentials
  where id=p_credential_id
    and user_id=auth.uid()
    and employee_id=v_employee_id
  for update;

  if v_credential.id is null then
    raise exception 'مفتاح الجهاز غير موجود' using errcode='P0002';
  end if;

  if v_credential.status='revoked' then
    return jsonb_build_object(
      'id',v_credential.id,
      'status','revoked',
      'alreadyRevoked',true
    );
  end if;

  update public.passkey_credentials
  set status='revoked', trusted=false, updated_at=now()
  where id=v_credential.id;

  update public.employee_devices
  set status='revoked', revoked_at=now(), updated_at=now()
  where employee_id=v_employee_id
    and credential_id=v_credential.credential_id
    and status='active';

  perform public.log_audit_event(
    'passkey.revoked',
    'security',
    'warning',
    'passkey_credentials',
    v_credential.id,
    'إلغاء جهاز بصمة موثوق',
    nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'deviceLabel',v_credential.device_label,
      'credentialDeviceType',v_credential.credential_device_type,
      'lastUsedAt',v_credential.last_used
    )
  );

  return jsonb_build_object(
    'id',v_credential.id,
    'status','revoked',
    'alreadyRevoked',false
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.rpc_set_role_permissions(p_role_id uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_role public.roles; v_count int := 0; v_item jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.update')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb)) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  select * into v_role from public.roles where id = p_role_id;
  if v_role.is_system and not public.current_is_super_admin() then
    raise exception 'system roles are protected' using errcode = '42501';
  end if;
  delete from public.role_permissions where role_id = p_role_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.role_permissions (role_id, permission_id, scope, requires_mfa, requires_reason)
    values (p_role_id,
            (v_item->>'permission_id')::uuid,
            coalesce(v_item->>'scope','self'),
            coalesce((v_item->>'requires_mfa')::boolean,false),
            coalesce((v_item->>'requires_reason')::boolean,false));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;



CREATE OR REPLACE FUNCTION public.rpc_upsert_role(p_id uuid, p_slug text, p_name_ar text, p_name_en text, p_description text, p_color text, p_icon text, p_is_full_access boolean DEFAULT false)
 RETURNS roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.roles; v_existing public.roles;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['access.role.create','access.role.update'])) then
    raise exception 'غير مصرح لك بإدارة الأدوار' using errcode = '42501';
  end if;

  -- منح full-access محصور بـsuper-admin فقط
  if p_is_full_access and not public.current_is_super_admin() then
    raise exception 'المدير الأعلى فقط يمنح الوصول الكامل' using errcode = '42501';
  end if;

  if p_id is not null then
    select * into v_existing from public.roles where id = p_id;
    -- منع تعديل الأدوار النظامية من غير super-admin
    if v_existing.is_system and not public.current_is_super_admin() then
      raise exception 'system roles are protected' using errcode = '42501';
    end if;
    update public.roles set
      slug = coalesce(p_slug, slug),
      name_ar = coalesce(p_name_ar, name_ar),
      name_en = p_name_en,
      description = p_description,
      color = p_color, icon = p_icon,
      -- is_full_access يتغيّر فقط بواسطة super-admin؛ خلاف ذلك يبقى كما هو
      is_full_access = case when public.current_is_super_admin() then p_is_full_access else is_full_access end,
      updated_at = now()
    where id = p_id returning * into v_row;
  else
    insert into public.roles (slug, name_ar, name_en, description, color, icon, is_system, is_full_access, created_by)
    values (p_slug, p_name_ar, p_name_en, p_description, p_color, p_icon, false,
            case when public.current_is_super_admin() then p_is_full_access else false end, auth.uid())
    returning * into v_row;
  end if;
  return v_row;
end;
$function$;



create or replace function public.save_kpi_compliance_metric(
 p_evaluation_id uuid,p_metric text,p_required integer,p_actual integer,p_exempt integer default 0,p_cancelled integer default 0,p_note text default null
)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_eligible integer; v_score numeric; v_criterion uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 -- 0470: لا بوابة مراحل — يكفي أن يكون التقييم غير مقفل والمُدخل من مراجعي HR
 if v_eval.locked or not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_metric not in ('PRAYER','HALAQA') or least(p_required,p_actual,p_exempt,p_cancelled)<0 then raise exception 'INVALID_COMPLIANCE_INPUT'; end if;
 v_eligible:=greatest(p_required-p_exempt-p_cancelled,0);
 if p_actual>v_eligible then raise exception 'ACTUAL_EXCEEDS_REQUIRED'; end if;
 v_score:=case when v_eligible=0 then 5 else round(p_actual::numeric/v_eligible*5,2) end;
 insert into public.kpi_compliance_records(evaluation_id,metric,required_count,actual_count,exempt_count,cancelled_count,calculated_score,note,approved_at,approved_by,created_by)
 values(p_evaluation_id,p_metric,p_required,p_actual,p_exempt,p_cancelled,v_score,p_note,now(),public.current_employee_id(),auth.uid())
 on conflict(evaluation_id,metric) do update set required_count=excluded.required_count,actual_count=excluded.actual_count,exempt_count=excluded.exempt_count,cancelled_count=excluded.cancelled_count,calculated_score=excluded.calculated_score,note=excluded.note,approved_at=now(),approved_by=public.current_employee_id(),updated_at=now();
 select c.id into strict v_criterion from public.kpi_criteria c where c.template_id=v_eval.template_id and c.code=p_metric;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,v_criterion,v_score,'hr',p_note,auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 perform public.log_audit_event('kpi.compliance.calculated','workflow','info','kpi_evaluations',p_evaluation_id,'احتساب معيار HR',null,jsonb_build_object('metric',p_metric,'score',v_score));
 return v_score;
end $$;



create or replace function public.save_kpi_goal(
 p_evaluation_id uuid,p_goal_id uuid,p_title text,p_description text,p_target_value numeric,
 p_achieved_value numeric,p_unit text,p_weight numeric,p_due_date date,p_evidence_source text,
 p_employee_note text,p_manager_note text,p_status text
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_id uuid; v_owner boolean; v_manager boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_owner:=v_eval.employee_id=public.current_employee_id();
 v_manager:=public.kpi_is_direct_manager(v_eval.employee_id);
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if p_status not in ('NOT_STARTED','IN_PROGRESS','COMPLETED','PARTIALLY_COMPLETED','BLOCKED','CANCELLED_BY_MANAGEMENT','DEFERRED_WITH_MANAGER_APPROVAL') then raise exception 'INVALID_GOAL_STATUS'; end if;
 -- V23: allow during parallel_review for manager; V17: allow during manager_review
 if v_manager and v_eval.current_stage in ('manager_review','parallel_review') then
  if length(trim(coalesce(p_title,'')))<3 or p_target_value<=0 or p_achieved_value<0 or p_weight<=0 or p_weight>40 then raise exception 'INVALID_GOAL'; end if;
  if p_goal_id is null then
   insert into public.kpi_goals(evaluation_id,title,description,target_value,achieved_value,unit,weight,due_date,evidence_source,employee_note,manager_note,status,created_by)
   values(p_evaluation_id,trim(p_title),p_description,p_target_value,p_achieved_value,trim(p_unit),p_weight,p_due_date,p_evidence_source,p_employee_note,p_manager_note,p_status,auth.uid()) returning id into v_id;
  else
   update public.kpi_goals set title=trim(p_title),description=p_description,target_value=p_target_value,achieved_value=p_achieved_value,unit=trim(p_unit),weight=p_weight,due_date=p_due_date,evidence_source=p_evidence_source,employee_note=p_employee_note,manager_note=p_manager_note,status=p_status,updated_at=now()
   where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
  end if;
 elsif v_owner and v_eval.current_stage='self' and v_eval.workflow_status<>'DRAFT' and p_goal_id is not null then
  update public.kpi_goals set achieved_value=p_achieved_value,evidence_source=p_evidence_source,employee_note=p_employee_note,status=p_status,updated_at=now()
  where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_id is null then raise exception 'GOAL_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.goal.saved','workflow','info','kpi_goals',v_id,'حفظ هدف تقييم الأداء',null,jsonb_build_object('evaluationId',p_evaluation_id,'status',p_status));
 return v_id;
end $$;



create or replace function public.save_kpi_review_session(p_evaluation_id uuid,p_session jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_manager uuid; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 -- V23: allow during parallel_review; V17: allow during manager_review
 if v_eval.current_stage not in ('manager_review','parallel_review') or not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 v_manager:=public.current_employee_id();
 if coalesce(p_session->>'mode','') not in ('ONSITE','REMOTE') then raise exception 'INVALID_SESSION_MODE'; end if;
 insert into public.kpi_review_sessions(evaluation_id,employee_id,manager_employee_id,scheduled_at,held_at,mode,discussion_summary,strengths,improvement_points,next_month_goals,employee_notes,manager_notes,employee_attended,manager_attended,manager_approved_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,v_manager,nullif(p_session->>'scheduledAt','')::timestamptz,nullif(p_session->>'heldAt','')::timestamptz,p_session->>'mode',nullif(trim(p_session->>'discussionSummary'),''),nullif(trim(p_session->>'strengths'),''),nullif(trim(p_session->>'improvementPoints'),''),nullif(trim(p_session->>'nextMonthGoals'),''),nullif(trim(p_session->>'employeeNotes'),''),nullif(trim(p_session->>'managerNotes'),''),coalesce((p_session->>'employeeAttended')::boolean,false),coalesce((p_session->>'managerAttended')::boolean,false),case when nullif(p_session->>'heldAt','') is not null then now() end,auth.uid())
 on conflict(evaluation_id) do update set scheduled_at=excluded.scheduled_at,held_at=excluded.held_at,mode=excluded.mode,discussion_summary=excluded.discussion_summary,strengths=excluded.strengths,improvement_points=excluded.improvement_points,next_month_goals=excluded.next_month_goals,employee_notes=excluded.employee_notes,manager_notes=excluded.manager_notes,employee_attended=excluded.employee_attended,manager_attended=excluded.manager_attended,manager_approved_at=excluded.manager_approved_at,updated_at=now()
 returning id into v_id;
 perform public.log_audit_event('kpi.session.saved','workflow','notice','kpi_review_sessions',v_id,'تسجيل جلسة تقييم الموظف والمدير',null,jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;



create or replace function public.save_shift_admin(p_shift_id uuid,p_code text,p_name text,p_start time,p_end time,p_break_minutes integer default 0,p_grace_in integer default 0,p_grace_out integer default 0,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(p_code))<2 or length(trim(p_name))<2 then raise exception 'INVALID_SHIFT'; end if;
 if p_shift_id is null then
  insert into public.shifts(code,name,start_time,end_time,crosses_midnight,break_minutes,grace_in_minutes,grace_out_minutes,is_active,created_by)
  values(upper(trim(p_code)),trim(p_name),p_start,p_end,p_end<=p_start,greatest(p_break_minutes,0),greatest(p_grace_in,0),greatest(p_grace_out,0),p_active,auth.uid()) returning id into v_id;
 else
  update public.shifts set code=upper(trim(p_code)),name=trim(p_name),start_time=p_start,end_time=p_end,crosses_midnight=p_end<=p_start,break_minutes=greatest(p_break_minutes,0),grace_in_minutes=greatest(p_grace_in,0),grace_out_minutes=greatest(p_grace_out,0),is_active=p_active,updated_at=now() where id=p_shift_id returning id into v_id;
 end if;
 perform public.log_audit_event('attendance.shift.saved','data','notice','shifts',v_id,'حفظ إعداد وردية',null,jsonb_build_object('code',p_code)); return v_id;
end $$;



create or replace function public.save_shift_admin(
  p_shift_id uuid,
  p_name text,
  p_start time,
  p_end time,
  p_break_minutes integer default 0,
  p_grace_in integer default 15,
  p_grace_out integer default 0,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  if p_shift_id is null then
    -- كود مشتق فريد (لا يظهر في اللوحة، للتمييز الداخلي فقط).
    v_code := 'SH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  else
    select code into v_code from public.shifts where id = p_shift_id;
    v_code := coalesce(v_code, 'SH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
  end if;

  -- نعيد الاستخدام للـ overload الأصلي (يفحص الصلاحية ويكتب سجل التدقيق).
  return public.save_shift_admin(
    p_shift_id, v_code, p_name, p_start, p_end,
    greatest(coalesce(p_break_minutes, 0), 0),
    greatest(coalesce(p_grace_in, 0), 0),
    greatest(coalesce(p_grace_out, 0), 0),
    p_active
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.schedule_dispute_session_v2(p_case_id uuid, p_type text, p_scheduled_at timestamp with time zone, p_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_location text DEFAULT NULL::text, p_modality text DEFAULT 'in_person'::text, p_participants jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_item jsonb; v_emp uuid; v_role text; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_scheduled_at<=now() or (p_ends_at is not null and p_ends_at<=p_scheduled_at) or p_modality not in ('in_person','remote','hybrid') then raise exception 'INVALID_SESSION'; end if;
 if jsonb_array_length(coalesce(p_participants,'[]'::jsonb))>200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_sessions(case_id,session_type,scheduled_at,ends_at,location,modality,status,created_by)
 values(p_case_id,p_type,p_scheduled_at,p_ends_at,nullif(trim(p_location),''),p_modality,'scheduled',auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','guest');
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_SESSION_PARTICIPANT'; end if;
  insert into public.dispute_session_participants(session_id,employee_id,participant_role,created_by) values(v_id,v_emp,v_role,auth.uid()) on conflict do nothing;
  perform public.enqueue_dispute_notification(p_case_id,v_emp,'session:'||v_id::text,'تم تحديد جلسة للمشكلة','موعد الجلسة: '||(to_char(p_scheduled_at at time zone 'Africa/Cairo','YYYY-MM-DD hh12:mi') || case when extract(hour from (p_scheduled_at at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end),'high');
 end loop;
 update public.dispute_cases set status='session_scheduled',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'session_scheduled',v_status,'session_scheduled',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',v_id,'scheduledAt',p_scheduled_at));
 perform public.log_audit_event('dispute.session_scheduled','workflow','notice','dispute_sessions',v_id,'تحديد جلسة للمشكلة',null,jsonb_build_object('caseId',p_case_id));
 return v_id;
end $function$

;



create or replace function public.schedule_interview_admin(
  p_application_id uuid,
  p_mode text,
  p_scheduled_at timestamptz,
  p_location_or_link text default null,
  p_panelists uuid[] default null,
  p_interview_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_panelist uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.interview.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.applications where id = p_application_id) then raise exception 'APPLICATION_NOT_FOUND'; end if;
  if coalesce(p_mode,'') not in ('onsite','remote') then raise exception 'INVALID_MODE'; end if;
  if array_length(p_panelists, 1) > 100 then raise exception 'ERR_BATCH_TOO_LARGE'; end if;

  if p_interview_id is null then
    insert into public.interviews(application_id, mode, scheduled_at, location_or_link, status, created_by)
    values (p_application_id, p_mode, p_scheduled_at, nullif(trim(p_location_or_link),''), 'scheduled', auth.uid())
    returning id into v_id;
  else
    update public.interviews
      set mode = p_mode, scheduled_at = p_scheduled_at, location_or_link = nullif(trim(p_location_or_link),''), updated_at = now()
      where id = p_interview_id and application_id = p_application_id
      returning id into v_id;
    if v_id is null then raise exception 'INTERVIEW_NOT_FOUND'; end if;
  end if;

  if p_panelists is not null then
    foreach v_panelist in array p_panelists loop
      insert into public.interview_panel(interview_id, panelist_id, created_by)
      values (v_id, v_panelist, auth.uid())
      on conflict (interview_id, panelist_id) do nothing;
    end loop;
  end if;

  perform public.log_audit_event('recruitment.interview_scheduled','workflow','info','interviews',v_id,
    'جدولة/تحديث مقابلة توظيف', null, jsonb_build_object('applicationId',p_application_id,'mode',p_mode));
  return jsonb_build_object('interviewId', v_id, 'scheduledAt', p_scheduled_at);
end $$;



CREATE OR REPLACE FUNCTION public.send_broadcast_alert(p_message text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if not public.has_permission('alerts.broadcast.send') then
    raise exception 'صلاحية التنبيه الشامل مطلوبة' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_message, ''))) < 3
     or length(trim(p_message)) > 300 then
    raise exception 'الرسالة يجب أن تكون بين 3 و300 حرف' using errcode = '22023';
  end if;

  -- تنبيه نشط واحد فقط في المرة.
  update public.broadcast_alerts set is_active = false where is_active;

  insert into public.broadcast_alerts(message, created_by)
  values (trim(p_message), v_me)
  returning id into v_id;

  perform public.notify_employee(
    e.id,
    'تنبيه عاجل',
    trim(p_message),
    'general',
    'urgent',
    'broadcast_alert',
    v_id,
    jsonb_build_object('alertId', v_id)
  )
    from public.employees e
   where e.is_active = true
     and coalesce(e.is_deleted, false) = false;

  return v_id;
end $function$;



create or replace function public.send_kpi_notifications_admin(p_cycle_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  -- فقط full-access أو السكرتير التنفيذي
  if not (public.current_is_full_access() or public.current_is_executive_secretary()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- إرسال إشعارات الدورة الحالية
  v_count := public.generate_kpi_cycle_notifications(now());

  perform public.log_audit_event(
    'kpi.notifications.manual_send', 'workflow', 'info',
    'kpi_cycles', p_cycle_id,
    'إرسال إشعارات KPI يدوي من الواجهة',
    null,
    jsonb_build_object('sentCount', v_count, 'triggeredBy', auth.uid())
  );

  return v_count;
end $$;



create or replace function public.set_dispute_committee(p_case_id uuid,p_members jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item jsonb; v_emp uuid; v_role text; v_status text; v_voters integer;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.committee.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then raise exception 'COMMITTEE_TOO_SMALL'; end if;
 if jsonb_array_length(p_members)>100 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 if v_status not in ('accepted','under_review','returned_to_committee','reopened') then raise exception 'INVALID_STATE'; end if;
 delete from public.committee_members where case_id=p_case_id;
 for v_item in select * from jsonb_array_elements(p_members) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','member');
  if v_role not in ('chair','secretary','member','observer','advisor') then raise exception 'INVALID_COMMITTEE_ROLE'; end if;
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_COMMITTEE_MEMBER'; end if;
  if exists(select 1 from public.dispute_parties where case_id=p_case_id and employee_id=v_emp) then raise exception 'PARTY_CANNOT_JOIN_COMMITTEE'; end if;
  insert into public.committee_members(case_id,committee_name,employee_id,role_in_committee,created_by)
  values(p_case_id,'لجنة حل المشكلات والخلافات',v_emp,v_role,auth.uid());
 end loop;
 if not exists(select 1 from public.committee_members where case_id=p_case_id and role_in_committee='chair') then raise exception 'CHAIR_REQUIRED'; end if;
 select count(*) into v_voters from public.committee_members where case_id=p_case_id and role_in_committee in ('chair','secretary','member') and is_active;
 if (select committee_quorum from public.dispute_cases where id=p_case_id)>v_voters then raise exception 'QUORUM_EXCEEDS_VOTERS'; end if;
 update public.dispute_cases set status='under_review',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'committee_assigned',v_status,'under_review',public.current_employee_id(),auth.uid(),jsonb_build_object('members',jsonb_array_length(p_members)));
 perform public.log_audit_event('dispute.committee_assigned','workflow','notice','dispute_cases',p_case_id,'تشكيل لجنة المشكلة',null,jsonb_build_object('members',jsonb_array_length(p_members)));
end $$;



create or replace function public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time default null,
  p_check_out time default null,
  p_clear_check_in boolean default false,
  p_clear_check_out boolean default false,
  p_reason text default null,
  p_notes text default null,
  p_leave_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_manager uuid;
  v_req public.requests;
  v_leave_type_id uuid;
  v_affects boolean;
  v_leave_type text;
  v_payload jsonb;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_clear_check_in and p_check_in is not null then
    raise exception 'CHECK_IN_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if p_clear_check_out and p_check_out is not null then
    raise exception 'CHECK_OUT_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- ── حارس الـ backdating (0383) — يمنع تزوير سجلات قديمة ───────────────────
  -- service_role يتجاوز الحارس للتصحيحات الرسمية/الترحيلات.
  if auth.role() <> 'service_role' then
    if p_work_date > v_today then
      raise exception 'INVALID_DATE: cannot set attendance for a future date' using errcode = '22023';
    end if;
    if p_work_date < (v_today - interval '90 days')::date then
      raise exception 'BACKDATING_LIMIT: cannot modify attendance older than 90 days (date: %, limit: %)',
        p_work_date, (v_today - interval '90 days')::date;
    end if;
  end if;

  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- تطبيع نوع الإجازة قبل التخزين في attendance_day_overrides.leave_type.
  v_leave_type := nullif(trim(coalesce(p_leave_type, '')), '');
  if p_day_type in ('leave','absent') then
    v_leave_type := coalesce(v_leave_type, case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'unsupported leave type: %', v_leave_type using errcode = '22023';
    end if;
  else
    v_leave_type := null;
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type, leave_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type, v_leave_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    leave_type = excluded.leave_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning id into v_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- ترميز إداري مباشر → ينشئ طلباً معتمداً (خصم الرصيد للِإجازة/الغياب).
  -- نمنع إنشاء طلب مكرر ليومٍ به طلب معتمد مسبقاً يغطي نفس اليوم.
  -- ─────────────────────────────────────────────────────────────────────────
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    if p_day_type in ('leave','absent') then
      -- نوع الإجازة: سبق تطبيعه أعلاه (v_leave_type) وتحققنا من صلاحيته.
      select id, affects_balance into v_leave_type_id, v_affects
      from public.leave_types where code = v_leave_type and is_active = true;
      if v_leave_type_id is null then
        raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
      end if;

      if not exists (
        select 1
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
         where lr.employee_id = p_employee_id
           and p_work_date between lr.start_date and lr.end_date
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true);

        v_req := public._submit_request_for(
          p_employee_id,
          'leave',
          null,
          v_manager,
          'تحديد يوم إداري — ' || (case when p_day_type = 'absent' then 'غياب' else 'إجازة' end),
          btrim(p_reason),
          v_payload);

        insert into public.leave_requests(
          request_id, employee_id, leave_type_id, start_date, end_date,
          days_count, duration_unit, created_by)
        values(
          v_req.id, p_employee_id, v_leave_type_id, p_work_date, p_work_date,
          1, 'day', auth.uid());

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    else
      -- مأمورية/قافلة/فاندي: طلب تشغيلي معتمد → تريجر الإعفاء يكتب present + استثناء
      if not exists (
        select 1
          from public.requests r
         where r.employee_id = p_employee_id
           and r.request_type = p_day_type
           and r.status = 'approved'
           and p_work_date between (r.payload->>'startDate')::date
                               and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true,
          'location', coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'تحديد إداري'));

        v_req := public._submit_request_for(
          p_employee_id,
          p_day_type,
          null,
          v_manager,
          'تحديد يوم إداري — ' || public.request_type_label(p_day_type),
          btrim(p_reason),
          v_payload);

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    end if;
  end if;

  perform public.log_audit_event(
    'attendance.day.override.saved', 'workflow', 'warning',
    'attendance_day_overrides', v_id,
    'تعديل إداري ليوم حضور', p_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'previous', v_previous,
      'dayType', p_day_type,
      'leaveType', v_leave_type,
      'requestId', case when v_req.id is null then null else v_req.id end,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'clearCheckIn', coalesce(p_clear_check_in, false),
      'clearCheckOut', coalesce(p_clear_check_out, false)
    )
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'employeeId', p_employee_id,
    'workDate', p_work_date,
    'leaveType', v_leave_type
  );
end
$$;



CREATE OR REPLACE FUNCTION public.set_employee_attendance_device_status(p_device_id uuid, p_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('access.account.manage_devices')
  ) then
    raise exception 'صلاحية إدارة الأجهزة مطلوبة' using errcode = '42501';
  end if;
  if p_status not in ('pending','active','blocked','revoked','replaced') then
    raise exception 'حالة جهاز غير صالحة' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'سبب حالة الجهاز مطلوب' using errcode = '22023';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;
  if not found then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  update public.employee_devices
  set status = p_status,
      revoked_at = case
        when p_status in ('revoked','replaced') then coalesce(revoked_at, now())
        else null
      end,
      metadata = metadata || jsonb_build_object(
        'lastStatusReason', trim(p_reason),
        'lastStatusActor', auth.uid(),
        'lastStatusAt', now()
      )
  where id = p_device_id
  returning * into v_device;

  if p_status = 'active' then
    update public.passkey_credentials
    set status = 'active', trusted = true, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  elsif p_status in ('revoked','replaced') then
    update public.passkey_credentials
    set status = 'revoked', trusted = false, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  end if;

  perform public.log_audit_event(
    'attendance.device_status_changed', 'security', 'warning',
    'employee_devices', v_device.id,
    'تغيير حالة جهاز الحضور', trim(p_reason),
    jsonb_build_object(
      'employeeId', v_device.employee_id,
      'status', p_status,
      'credentialId', v_device.credential_id
    )
  );

  return jsonb_build_object(
    'id', v_device.id,
    'employeeId', v_device.employee_id,
    'status', v_device.status
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.set_employee_status(p_employee_id uuid, p_status text)
 RETURNS employees
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.employees;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'غير مصرح بتغيير حالة الموظف' using errcode = '42501';
  end if;

  if p_status not in (
    'draft','invited','onboarding','active','suspended',
    'notice_period','terminated','archived','probation_failed'
  ) then
    raise exception 'invalid status value: %', p_status using errcode = '22023';
  end if;

  update public.employees
     set status     = p_status,
         is_active  = (p_status = 'active'),
         updated_at = now()
   where id = p_employee_id
  returning * into v_row;

  if not found then
    raise exception 'employee not found: %', p_employee_id using errcode = 'P0002';
  end if;

  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.set_live_location_legal_hold(p_video_id uuid, p_hold_until timestamp with time zone, p_reason text)
 RETURNS live_location_videos_meta
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.live_location_videos_meta;
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.manage_retention')) then
    raise exception 'صلاحية إدارة الاستبقاء مطلوبة' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'سبب الحجز القانوني مطلوب' using errcode='22023'; end if;

  update public.live_location_videos_meta
    set legal_hold_until = p_hold_until,
        retention_delete_after = case when p_hold_until is not null then greatest(coalesce(retention_delete_after,now()), p_hold_until) else retention_delete_after end
    where id=p_video_id and status<>'deleted'
    returning * into v_row;
  if not found then raise exception 'الفيديو غير موجود' using errcode='P0002'; end if;

  insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action,reason)
  values(p_video_id, auth.uid(), public.current_employee_id(), case when p_hold_until is null then 'release_hold' else 'legal_hold' end, trim(p_reason));

  perform public.log_audit_event(
    case when p_hold_until is null then 'live_location.hold_released' else 'live_location.legal_hold' end,
    'security','warning','live_location_videos_meta',p_video_id,'حفظ إداري لفيديو التحقق',null,
    jsonb_build_object('holdUntil',p_hold_until,'reason',trim(p_reason))
  );
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.set_my_photo_url(p_photo_url text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_emp_id uuid;
  v_url text;
  v_normalized text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  v_emp_id := public.current_employee_id();
  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NO_EMPLOYEE_PROFILE' USING ERRCODE = '42501';
  END IF;

  v_url := nullif(trim(p_photo_url), '');
  IF v_url IS NULL THEN
    RAISE EXCEPTION 'ERR_INVALID_URL' USING ERRCODE = '23502';
  END IF;

  -- يجب أن يكون الـ URL داخل bucket employee-avatars (authenticated أو public).
  IF NOT (
    v_url LIKE '%/storage/v1/object/authenticated/employee-avatars/%'
    OR v_url LIKE '%/storage/v1/object/public/employee-avatars/%'
  ) THEN
    RAISE EXCEPTION 'ERR_INVALID_URL' USING ERRCODE = '23514';
  END IF;

  -- توحيد على صيغة authenticated.
  v_normalized := replace(v_url, '/storage/v1/object/public/employee-avatars/',
                                '/storage/v1/object/authenticated/employee-avatars/');

  -- التحديث عبر UPDATE على employees — RLS تسمح بالتحديث الذاتي.
  UPDATE public.employees
     SET photo_url = v_normalized
   WHERE id = v_emp_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ERR_UPDATE_FAILED' USING ERRCODE = '44000';
  END IF;

  RETURN v_normalized;
END;
$$;



CREATE OR REPLACE FUNCTION public.share_my_location_proactively(p_latitude double precision, p_longitude double precision, p_accuracy double precision DEFAULT NULL::double precision, p_duration_minutes integer DEFAULT 60, p_reason text DEFAULT NULL::text, p_source text DEFAULT 'mobile'::text, p_battery_level integer DEFAULT NULL::integer)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_exec_role text;
  v_exec_emp uuid;
  v_exec_user uuid;
  v_row public.live_location_requests;
  v_duration integer;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'الإحداثيات مطلوبة' using errcode = '22023';
  end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'الإحداثيات خارج النطاق' using errcode = '22023';
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
    raise exception 'لديك مشاركة موقع نشطة بالفعل' using errcode = '23505';
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
$function$;



create or replace function public.soft_delete_employee(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- يحيل إلى الدالة الآمنة التي تعالج كل التبعيات (auth, roles, manager_relations).
  perform public.archive_employee_secure(p_employee_id, 'deprecated soft_delete_employee redirect');
end;
$$;



CREATE OR REPLACE FUNCTION public.start_my_mission(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me    uuid := public.current_employee_id();
  v_req   public.requests;
  v_end   date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_id    uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
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
  if v_req.status <> 'approved' then
    raise exception 'يجب اعتماد المأمورية قبل بدئها — راجع الإدارة' using errcode = '22023';
  end if;

  -- 0453: منع تكرار التنفيذ لنفس الطلب (نقرة مزدوجة/سباق)
  if exists (
    select 1 from public.mission_executions
     where request_id = p_request_id
       and status in ('in_progress','completed')
  ) then
    raise exception 'تم بدء هذه المأمورية مسبقًا' using errcode = '22023';
  end if;

  begin
    v_end := (nullif(v_req.payload->>'endDate', ''))::date;
  exception when others then
    v_end := null;
  end;
  if v_end is not null and v_today > v_end then
    raise exception 'لا يمكن بدء المأمورية بعد انتهاء مدتها' using errcode = '22023';
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', now())
  returning id into v_id;

  return v_id;
end $function$;



create or replace function public.start_offboarding_case(p_employee_id uuid,p_reason_type text,p_reason text,p_notice_date date,p_last_working_date date,p_handover_employee_id uuid default null,p_clearance_items jsonb default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_item jsonb;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.manage')) then raise exception 'FORBIDDEN'; end if;
 if p_employee_id=public.current_employee_id() or p_last_working_date<coalesce(p_notice_date,p_last_working_date) then raise exception 'INVALID_OFFBOARDING'; end if;
 if exists(select 1 from public.offboarding_cases where employee_id=p_employee_id and status not in ('completed','cancelled')) then raise exception 'ACTIVE_OFFBOARDING_EXISTS'; end if;
 v_number:='OFF-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.offboarding_cases(employee_id,case_number,reason_type,reason,notice_date,last_working_date,status,handover_employee_id,created_by)
 values(p_employee_id,v_number,p_reason_type,p_reason,p_notice_date,p_last_working_date,'in_clearance',p_handover_employee_id,auth.uid()) returning id into v_id;
 update public.employees set status='notice_period',is_active=true,updated_at=now() where id=p_employee_id;
 if p_clearance_items is null then p_clearance_items:='[{"category":"manager","title":"تسليم المهام والمعرفة"},{"category":"assets","title":"إعادة جميع العهد"},{"category":"it","title":"إلغاء الوصول التقني"},{"category":"hr","title":"مراجعة الملف والمستندات"},{"category":"finance","title":"التسوية المالية النهائية"}]'::jsonb; end if;
 if jsonb_array_length(p_clearance_items) > 200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 for v_item in select * from jsonb_array_elements(p_clearance_items) loop
  insert into public.offboarding_clearance_items(offboarding_case_id,category,title,owner_role,due_at,created_by) values(v_id,v_item->>'category',v_item->>'title',v_item->>'ownerRole',p_last_working_date::timestamptz,auth.uid());
 end loop;
 insert into public.offboarding_actions(offboarding_case_id,action_type,to_status,note,actor_employee_id,actor_user_id) values(v_id,'start','in_clearance',p_reason,public.current_employee_id(),auth.uid()); return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.store_credential(
  p_key_name    text,
  p_value       text,
  p_category    text    DEFAULT 'general',
  p_hint        text    DEFAULT NULL,
  p_metadata    jsonb   DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_enc_key text;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'store_credential يتطلب صلاحية full-access';
  END IF;

  -- التحقق من وجود مفتاح التشفير
  v_enc_key := current_setting('app.credential_key', true);
  IF v_enc_key IS NULL OR length(trim(v_enc_key)) = 0 THEN
    RAISE EXCEPTION 'ERR_MISSING_ENCRYPTION_KEY'
      USING HINT = 'app.credential_key غير مُعرَّف — اضبطه كـ Supabase secret';
  END IF;

  -- إدراج أو تحديث
  INSERT INTO public.credential_vault
    (key_name, secret_ciphertext, category, secret_hint, metadata, rotated_at, created_by)
  VALUES (
    p_key_name,
    pgp_sym_encrypt(p_value, v_enc_key),
    p_category,
    p_hint,
    COALESCE(p_metadata, '{}'::jsonb),
    now(),                          -- rotated_at = وقت آخر تدوير
    auth.uid()
  )
  ON CONFLICT (key_name) DO UPDATE SET
    secret_ciphertext = pgp_sym_encrypt(p_value, v_enc_key),
    category          = COALESCE(NULLIF(p_category, ''), credential_vault.category),
    secret_hint       = COALESCE(p_hint, credential_vault.secret_hint),
    metadata          = credential_vault.metadata || COALESCE(p_metadata, '{}'::jsonb),
    rotated_at        = now(),
    updated_at        = now();

  -- تسجيل تدقيقي
  PERFORM public.log_audit_event(
    p_event_type   := 'credential.stored',
    p_category     := 'security',
    p_severity     := 'notice',
    p_target_table := 'credential_vault',
    p_summary_ar   := 'تخزين/تحديث اعتماد مشفّر: ' || p_key_name,
    p_metadata     := jsonb_build_object(
      'key_name', p_key_name,
      'category', p_category,
      'has_hint', (p_hint IS NOT NULL)
    )
  );
END;
$$;



CREATE OR REPLACE FUNCTION public.submit_assignment_report(p_assignment_id uuid, p_report text, p_outcome text DEFAULT NULL::text, p_achieved_amount numeric DEFAULT NULL::numeric)
 RETURNS work_assignment_participants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignment_participants;
begin
  if length(trim(coalesce(p_report,''))) < 3 then
    raise exception 'التقرير مطلوب' using errcode = '22023';
  end if;
  update public.work_assignment_participants
    set report = p_report, outcome = p_outcome, achieved_amount = p_achieved_amount,
        attendance_status = 'completed', updated_at = now()
    where assignment_id = p_assignment_id and employee_id = v_me
    returning * into v_row;
  if not found then raise exception 'not a participant' using errcode = '42501'; end if;

  update public.work_assignments
    set status = 'REPORT_SUBMITTED', updated_at = now()
    where id = p_assignment_id and needs_report = true and status in ('APPROVED','IN_PROGRESS','COMPLETED','REPORT_PENDING');

  perform public.log_audit_event(
    'assignment.report.submitted', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'إرسال تقرير تنفيذ تكليف', null,
    jsonb_build_object('employeeId', v_me, 'achievedAmount', p_achieved_amount));
  return v_row;
end $function$;



CREATE OR REPLACE FUNCTION public.submit_discipline_action(p_employee_id uuid, p_action_type text, p_title text, p_description text, p_severity text DEFAULT 'moderate'::text, p_amount numeric DEFAULT NULL::numeric, p_effective_from date DEFAULT NULL::date, p_effective_to date DEFAULT NULL::date)
 RETURNS employee_discipline_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.create')) then
    raise exception 'FORBIDDEN: requires relations.discipline.create' using errcode = '42501';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and is_deleted = false) then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if p_action_type not in ('verbal_warning','written_warning','salary_deduction','suspension','termination') then
    raise exception 'نوع إجراء غير صالح' using errcode = '22023';
  end if;

  if p_action_type = 'salary_deduction' and (p_amount is null or p_amount <= 0) then
    raise exception 'المبلغ مطلوب للخصم من الراتب' using errcode = '22023';
  end if;

  insert into public.employee_discipline_actions(
    employee_id, action_type, title, description, severity, amount,
    effective_from, effective_to, status, created_by)
  values (
    p_employee_id, p_action_type, trim(p_title), trim(p_description), p_severity, p_amount,
    p_effective_from, p_effective_to, 'pending', auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.submitted', 'compliance', 'warning',
    'employee_discipline_actions', v_row.id,
    'إجراء تأديبي جديد بانتظار الاعتماد', null,
    jsonb_build_object('employeeId', p_employee_id, 'actionType', p_action_type));

  perform public.notify_employee(
    p_employee_id,
    'إجراء تأديبي بانتظار المراجعة',
    'تم تسجيل إجراء (' || public.discipline_action_type_label(p_action_type) || ') على ملفك وهو بانتظار الاعتماد.',
    'general', 'normal', null, null, '{}'::jsonb
  );

  return v_row;
end;
$function$;



create or replace function public.submit_dispute_appeal(p_decision_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_dec public.dispute_decisions; v_case public.dispute_cases; v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
 select * into strict v_dec from public.dispute_decisions where id=p_decision_id;
 select * into strict v_case from public.dispute_cases where id=v_dec.case_id for update;
 if not exists(select 1 from public.dispute_parties where case_id=v_case.id and employee_id=v_emp and party_type in ('complainant','respondent') and (party_type='complainant' or notified_at is not null)) or now()>v_case.appeal_deadline or length(trim(coalesce(p_reason,'')))<20 then raise exception 'APPEAL_NOT_ALLOWED'; end if;
 insert into public.dispute_appeals(case_id,decision_id,appellant_employee_id,reason,created_by) values(v_case.id,p_decision_id,v_emp,trim(p_reason),auth.uid()) returning id into v_id;
 perform public.notify_dispute_admins(v_case.id,'appeal:'||v_id::text,'اعتراض جديد على قرار',coalesce(v_case.case_number,'')||' — يتطلب مراجعة','high');
 perform public.log_audit_event('dispute.appeal_submitted','workflow','warning','dispute_appeals',v_id,'تقديم اعتراض على القرار',null,jsonb_build_object('caseId',v_case.id));
 return v_id;
end $$;



create or replace function public.submit_dispute_statement(
  p_case_id uuid,
  p_statement_type text,
  p_statement_text text,
  p_visibility text default 'committee_only'
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_emp uuid := public.current_employee_id();
  v_case public.dispute_cases;
  v_party public.dispute_parties;
  v_id uuid;
  v_committee boolean;
  v_authorized boolean;
begin
  if v_emp is null or length(trim(coalesce(p_statement_text,''))) < 10 then
    raise exception 'INVALID_STATEMENT';
  end if;

  select * into strict v_case from public.dispute_cases where id = p_case_id for update;

  v_committee := exists(
    select 1 from public.committee_members
    where case_id = p_case_id and employee_id = v_emp and is_active
  );

  -- 0198: السماح لأصحاب صلاحيات اللجنة بتقديم توصيات حتى بدون عضوية لكل قضية
  v_authorized := v_committee
    or public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all');

  select * into v_party from public.dispute_parties
  where case_id = p_case_id and employee_id = v_emp
  order by case when party_type = 'complainant' then 0 else 1 end
  limit 1;

  -- إذا ليس عضو لجنة ولا صاحب صلاحية ولا طرف → ممنوع
  if not v_authorized and v_party.id is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not v_authorized and v_party.party_type <> 'complainant'
     and v_party.notified_at is null then
    raise exception 'NOT_NOTIFIED' using errcode = '42501';
  end if;

  if not v_authorized and v_party.party_type = 'complainant'
     and v_case.status <> 'needs_more_information'
     and p_statement_type = 'clarification' then
    raise exception 'CLARIFICATION_NOT_REQUESTED';
  end if;

  if p_statement_type not in (
    'complainant','respondent','witness','clarification',
    'committee_note','recommendation','executive_note'
  ) or p_visibility not in (
    'committee_only','submitter_and_committee','parties','complainant','respondent'
  ) then
    raise exception 'INVALID_STATEMENT_TYPE';
  end if;

  -- committee_note/recommendation/executive_note تتطلب عضوية أو صلاحية
  if not v_authorized and p_statement_type in (
    'committee_note','recommendation','executive_note'
  ) then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.dispute_statements(
    case_id, party_id, submitted_by, statement_type,
    statement_text, visibility, created_by
  ) values (
    p_case_id, v_party.id, v_emp, p_statement_type,
    trim(p_statement_text), p_visibility, auth.uid()
  ) returning id into v_id;

  if v_party.id is not null then
    update public.dispute_parties
    set statement_submitted_at = now(), updated_at = now()
    where id = v_party.id;
  end if;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'statement_added', v_case.status, v_case.status,
    'تمت إضافة إفادة', v_emp, auth.uid(),
    jsonb_build_object('statementId', v_id, 'type', p_statement_type)
  );

  perform public.log_audit_event(
    'dispute.statement_added','data','notice',
    'dispute_statements', v_id,
    'إضافة إفادة للمشكلة', null,
    jsonb_build_object('caseId', p_case_id, 'type', p_statement_type)
  );

  perform public.notify_dispute_admins(
    p_case_id, 'statement:' || v_id::text,
    'إفادة جديدة في مشكلة',
    coalesce(v_case.case_number,'') || ' — تمت إضافة إفادة جديدة',
    'normal'
  );

  return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.submit_employee_day_mark(p_employee_id uuid, p_request_type text, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_start_date date;
  v_end_date date;
  v_manager uuid;
  v_leave_type text;
  v_leave_type_id uuid;
  v_days numeric := 1;
  v_substitute uuid;
  v_row public.requests;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'الموظف مطلوب' using errcode = '22023';
  end if;

  -- الصلاحية: نفس صلاحية التعديل الإداري لليوم (0266)
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- منع التعديل على شهر مغلق
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month_start
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- النوع: إجازة أو توجيه تشغيلي فقط
  if p_request_type not in ('leave','mission','convoy','fundraising') then
    raise exception 'ترميز اليوم يدعم الإجازة والمأمورية والقافلة والفاندي فقط' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  v_start_date := nullif(v_payload->>'startDate', '')::date;
  v_end_date := nullif(v_payload->>'endDate', '')::date;
  if v_start_date is null or v_end_date is null then
    raise exception 'day mark requires a date' using errcode = '22023';
  end if;
  if v_end_date <> v_start_date then
    raise exception 'day marks are single-day only' using errcode = '22023';
  end if;
  if v_start_date < v_month_start then
    raise exception 'day marks are allowed within the current month only' using errcode = '22023';
  end if;
  if v_start_date > v_today then
    raise exception 'future days cannot be marked' using errcode = '22023';
  end if;

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  if p_request_type = 'leave' then
    v_leave_type := v_payload->>'leaveType';
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
    end if;
    select id into v_leave_type_id
    from public.leave_types where code = v_leave_type and is_active = true;
    if v_leave_type_id is null then
      raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
    end if;
    v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
    v_payload := v_payload || jsonb_build_object(
      'leaveType', v_leave_type,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'days', v_days,
      'immediate', (v_leave_type = 'casual'),
      'dayMark', true);
  else
    if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
      raise exception 'assignment location is required' using errcode = '22023';
    end if;
    v_payload := v_payload || jsonb_build_object(
      'startDate', v_start_date,
      'endDate', v_end_date,
      'location', trim(v_payload->>'location'),
      'days', v_days,
      'dayMark', true);
  end if;

  v_row := public._submit_request_for(
    p_employee_id,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- صف تفصيل الإجازة + تنفيذ فوري للعارضة (نفس مسار submit_my_request)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, p_employee_id, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' then
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
        jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
    end if;
  end if;

  return v_row;
end;
$function$;



create or replace function public.submit_kpi_appeal(p_evaluation_id uuid,p_reason text,p_requested_outcome text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if v_eval.employee_id<>public.current_employee_id() or v_eval.current_stage not in ('finalized','closed','archived') then raise exception 'FORBIDDEN_OR_NOT_AVAILABLE'; end if;
 if length(trim(p_reason))<10 then raise exception 'REASON_TOO_SHORT'; end if;
 insert into public.kpi_appeals(evaluation_id,employee_id,reason,requested_outcome,status,resolution_due_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,trim(p_reason),p_requested_outcome,'submitted',now()+interval '7 days',auth.uid())
 on conflict(evaluation_id,employee_id) do update set reason=excluded.reason,requested_outcome=excluded.requested_outcome,status='submitted',submitted_at=now(),review_note=null,reviewed_at=null,reviewed_by=null,updated_at=now()
 returning id into v_id;
 perform public.log_audit_event('kpi.appeal.submitted','workflow','warning','kpi_appeals',v_id,'تقديم اعتراض على KPI',trim(p_reason),jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.submit_live_location_point(p_request_id uuid, p_latitude double precision, p_longitude double precision, p_accuracy double precision, p_altitude double precision DEFAULT NULL::double precision, p_speed double precision DEFAULT NULL::double precision, p_heading double precision DEFAULT NULL::double precision, p_is_mock boolean DEFAULT false, p_address_ar text DEFAULT NULL::text)
 RETURNS employee_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.employee_locations;
  v_mode text;
  v_needs_video boolean;
  v_has_video boolean := false;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'إحداثيات غير صالحة' using errcode = '22023';
  end if;
  if p_accuracy is null or p_accuracy < 0 or p_accuracy > 10000 then
    raise exception 'دقة الموقع غير صالحة' using errcode = '22023';
  end if;

  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  if v_req.status <> 'active' or v_req.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  insert into public.employee_locations(
    employee_id,
    live_request_id,
    latitude,
    longitude,
    accuracy,
    altitude,
    speed,
    heading,
    source,
    is_mock,
    address_ar,
    geocode_source,
    recorded_at,
    created_by
  )
  values(
    v_me,
    p_request_id,
    p_latitude,
    p_longitude,
    p_accuracy,
    p_altitude,
    p_speed,
    p_heading,
    'mobile',
    coalesce(p_is_mock, false),
    nullif(trim(coalesce(p_address_ar, '')), ''),
    case when nullif(trim(coalesce(p_address_ar, '')), '') is not null then 'nominatim' else null end,
    now(),
    auth.uid()
  )
  returning * into v_row;

  v_mode := coalesce(v_req.metadata->>'mode', 'snapshot');
  v_needs_video := coalesce((v_req.metadata->>'needsVideo')::boolean, v_mode in ('video_5s', 'location_video'));

  if v_needs_video then
    select exists(
      select 1
      from public.live_location_videos_meta
      where live_request_id = p_request_id
        and status <> 'deleted'
    ) into v_has_video;
  end if;

  if not v_needs_video or v_has_video then
    update public.live_location_requests
    set status = 'completed',
        expires_at = now(),
        updated_at = now()
    where id = p_request_id;
  end if;

  return v_row;
end $function$;



create or replace function public.submit_my_dispute(
 p_title text,p_description text,p_case_type text,p_priority text default 'normal',
 p_incident_at timestamptz default null,p_incident_location text default null,
 p_parties jsonb default '[]'::jsonb,p_witnesses jsonb default '[]'::jsonb,
 p_direct_manager_contacted boolean default null,p_amicable_attempted boolean default null,
 p_amicable_result text default null,p_requested_action text default null,
 p_confidential boolean default true,p_truth_confirmed boolean default false,
 p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text; v_item jsonb; v_party uuid; v_first_respondent uuid;
begin
 if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode='42501'; end if;
 if length(trim(coalesce(p_title,'')))<5 or length(trim(coalesce(p_description,'')))<20 then raise exception 'INVALID_CASE' using errcode='22023'; end if;
 if not p_truth_confirmed or not p_confidentiality_accepted then raise exception 'REQUIRED_CONFIRMATIONS_MISSING' using errcode='22023'; end if;
 if p_case_type not in ('employee_conflict','inappropriate_conduct','verbal_abuse','management_chain','direct_manager','department_conflict','misunderstanding','work_environment','donor_beneficiary','administrative_violation','agreement_breach','other') then raise exception 'INVALID_CASE_TYPE' using errcode='22023'; end if;
 if p_priority not in ('normal','urgent') then raise exception 'EMPLOYEE_PRIORITY_NOT_ALLOWED' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_parties,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_witnesses,'[]'::jsonb))<>'array' then raise exception 'INVALID_PARTIES' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(p_parties,'[]'::jsonb))=0 then raise exception 'AT_LEAST_ONE_PARTY_REQUIRED' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(p_parties,'[]'::jsonb))>200 or jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb))>200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;

 v_number:='CASE-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_cases(case_number,title,description,case_type,status,severity,actor_employee_id,is_confidential,privacy_level,opened_at,
  incident_at,incident_location,requested_action,witnesses_present,direct_manager_contacted,amicable_resolution_attempted,amicable_resolution_result,
  truth_confirmed,confidentiality_accepted,review_due_at,created_by)
 values(v_number,trim(p_title),trim(p_description),p_case_type,'submitted',p_priority,v_emp,p_confidential,'restricted',now(),
  p_incident_at,nullif(trim(p_incident_location),''),nullif(trim(p_requested_action),''),jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb))>0,
  p_direct_manager_contacted,p_amicable_attempted,nullif(trim(p_amicable_result),''),true,true,now()+interval '24 hours',auth.uid()) returning id into v_id;

 insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,notified_at,created_by)
 values(v_id,v_emp,'complainant','read',now(),auth.uid());

 for v_item in select * from jsonb_array_elements(coalesce(p_parties,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_PARTY' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,case when coalesce(v_item->>'type','respondent') in ('respondent','related') then coalesce(v_item->>'type','respondent') else 'respondent' end,'withheld',auth.uid())
  on conflict(case_id,employee_id,party_type) do nothing;
  if v_first_respondent is null and coalesce(v_item->>'type','respondent')='respondent' then v_first_respondent=v_party; end if;
 end loop;
 for v_item in select * from jsonb_array_elements(coalesce(p_witnesses,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_WITNESS' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,'witness','withheld',auth.uid()) on conflict(case_id,employee_id,party_type) do nothing;
 end loop;
 update public.dispute_cases set respondent_employee_id=v_first_respondent where id=v_id;
 insert into public.dispute_actions(case_id,action_type,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(v_id,'submit','submitted','تم تقديم المشكلة',v_emp,auth.uid(),jsonb_build_object('priority',p_priority));
 perform public.log_audit_event('dispute.submitted','workflow','notice','dispute_cases',v_id,'تقديم مشكلة جديدة',null,jsonb_build_object('caseNumber',v_number,'priority',p_priority));
 perform public.notify_dispute_admins(v_id,'submitted','مشكلة جديدة تنتظر المراجعة',v_number||' — '||trim(p_title),case when p_priority='urgent' then 'urgent' else 'high' end);
 return v_id;
end $$;



CREATE OR REPLACE FUNCTION public.submit_my_request(p_request_type text, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb, p_idempotency_key uuid DEFAULT NULL::uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- ── idempotency (0379): same key within 10 minutes returns the same row ──
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
  -- ────────────────────────────────────────────────────────────────────────

  -- V17 Â§8 + 0333: request types (legacy + attendance_permit/generic from 0379)
  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction','attendance_permit','generic') then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  -- قواعد تحديد اليوم (dayMark): يوم ماضٍ من نفس الشهر أو اليوم الحالي فقط.
  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'day mark requires a date' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'day marks are single-day only' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'day marks are allowed within the current month only' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'future days cannot be marked' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- توافق خلفي: emergency → casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        -- أثر رجعي: مسموح فقط عبر dayMark (نفس الشهر) — وإلا منع كالمعتاد
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      -- ─── مأمورية / قافلة / فاندي ───────────────────────────────────────────
      when 'mission', 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية التكليف لا يسبق تاريخ البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_today then
          raise exception 'التكليفات بأثر رجعي غير مسموحة' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        -- وقت مخطط اختياري بصيغة HH:MM — يرفض "9:00"
        if nullif(trim(coalesce(v_payload->>'startTime','')),'') is not null
           and v_payload->>'startTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'startTime must be in HH:MM format' using errcode = '22023';
        end if;
        if nullif(trim(coalesce(v_payload->>'endTime','')),'') is not null
           and v_payload->>'endTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'endTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1,
          'startTime', nullif(trim(coalesce(v_payload->>'startTime','')),''),
          'endTime', nullif(trim(coalesce(v_payload->>'endTime','')),''));

      -- ─── إذن تأخير (V17 Â§8) ────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر (V17 Â§8) ──────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── إذن حضور موحد (0379) ─────────────────────────────────────────────
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

      -- ─── تصحيح حضور (V17 Â§8) ─────────────────────────────────────────────
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
          raise exception 'correctedTime must be in HH:MM format' using errcode = '22023';
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

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل)
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026)
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

    -- العارضة/الطارئة: تُنفَّذ مباشرة دون موافقة المدير المباشر
    if v_leave_type = 'casual' then
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

  return v_row;
end $function$;



create or replace function public.submit_my_service_request(p_catalog_item_id uuid,p_title text,p_description text,p_priority text default 'normal',p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$ declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_sla integer; begin if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if; select sla_hours into v_sla from public.service_catalog_items where id=p_catalog_item_id and active; if not found then raise exception 'SERVICE_NOT_AVAILABLE'; end if; insert into public.service_requests(catalog_item_id,requester_employee_id,title,description,payload,priority,due_at,created_by) values(p_catalog_item_id,v_emp,trim(p_title),nullif(trim(p_description),''),coalesce(p_payload,'{}'::jsonb),p_priority,now()+make_interval(hours=>v_sla),auth.uid()) returning id into v_id; perform public.notify_employees_with_permission('service.request.manage','طلب خدمة جديد',format('طلب خدمة: %s', trim(p_title)),'service','normal','service_requests',v_id,'{}'::jsonb,v_emp); return v_id; end $$;



CREATE OR REPLACE FUNCTION public.submit_privacy_request(p_request_type text, p_details text)
 RETURNS privacy_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.privacy_requests;
begin
  if auth.uid() is null then raise exception 'يلزم تسجيل الدخول أولاً' using errcode='42501'; end if;
  if p_request_type not in ('access','correction','export','restriction','deletion','objection') then raise exception 'نوع طلب خصوصية غير صالح' using errcode='22023'; end if;
  insert into public.privacy_requests(requester_user_id,requester_employee_id,request_type,details,due_at)
  values(auth.uid(),public.current_employee_id(),p_request_type,trim(p_details),now()+interval '30 days') returning * into v_row;
  perform public.log_audit_event('privacy.request.submitted','data','notice','privacy_requests',v_row.id,'تقديم طلب خصوصية',null,jsonb_build_object('requestType',p_request_type));
  perform public.notify_employees_with_permission(
    'privacy.request.manage',
    'طلب خصوصية جديد',
    format('طلب %s من موظف.', p_request_type),
    'privacy', 'normal', 'privacy_requests', v_row.id,
    jsonb_build_object('requestType', p_request_type), v_row.requester_employee_id);
  return v_row;
end;
$function$;



create or replace function public.tg_adjust_escalation_deadline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int;
  v_manager_id uuid;
begin
  -- فقط لطلبات الإجازة التي لها خطوة موافقة (step_order >= 1)
  if new.request_type = 'leave' and new.current_step_order >= 1 then
    -- جلب المدير المسؤول عن الخطوة الحالية
    select assignee_employee_id into v_manager_id
    from public.request_steps
    where request_id = new.id
      and step_order = new.current_step_order
    limit 1;

    if v_manager_id is not null then
      v_hours := public.get_escalation_hours(v_manager_id);
      new.decision_due_at := now() + (v_hours || ' hours')::interval;
    end if;
  end if;

  return new;
end;
$$;



CREATE OR REPLACE FUNCTION public.tg_attendance_daily_notify_manager()
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

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  -- الاسم الأول للعنوان الشخصي (وصل مصطفى…) مع احتياط عند غياب الاسم
  v_first := coalesce(nullif(split_part(coalesce(v_emp_ar, ''), ' ', 1), ''), 'موظف');

  -- 0449: الوقت بنظام 12 ساعة مع ص/م بدل HH24
  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'hh12:mi'
  ) || case when extract(hour from (
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end;

  -- 0446: عنوان شخصي باسم الموظف بدل الصيغة العامة
  v_title := case when v_event = 'attendance_check_in'
              then format('وصل %s للعمل بالمجمع', v_first)
              else format('خرج %s من المجمع', v_first) end;
  v_body := format(
    '%s الساعة %s',
    case when v_event = 'attendance_check_in' then 'دخل' else 'انصرف' end,
    v_time
  );

  -- إشعار الموظف نفسه (تأكيد تسجيل الحضور/الانصراف)
  perform public.notify_employee(
    new.employee_id,
    case when v_event = 'attendance_check_in' then 'تم تسجيل حضورك'
         else 'تم تسجيل انصرافك' end,
    format(
      'تم تسجيل %s الساعة %s',
      case when v_event = 'attendance_check_in' then 'حضورك' else 'انصرافك' end,
      v_time
    ),
    'attendance', 'normal', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time
    )
  );

  -- إشعار المدير المباشر (أولوية منخفضة — عنوان شخصي 0446)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
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

  -- 0446: إشعار المدير التنفيذي بإشعار «عادي» (لا عاجل ولا full-screen)
  -- حتى لا تغرق إشعارات الحضور الروتينية قسم «تنبيهات عاجلة»؛ تبقى في
  -- قائمة الإشعارات العامة. لا يُشعر التنفيذي عن حضور/انصراف نفسه.
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



create or replace function public.tg_block_disabled_leave_types()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_blocked constant text[] := array[
    'maternity','childcare','child_care','maternity_leave','وضع','رعاية_طفل'
  ];
begin
  -- نسمح فقط بإبقائها معطّلة (is_active=false)؛ نمنع تفعيلها أو إنشاءها نشطة.
  if new.code = any (v_blocked) and coalesce(new.is_active, true) = true then
    raise exception 'LEAVE_TYPE_DISABLED_BY_POLICY: % (إجازة الوضع/رعاية الطفل ملغاة بالسياسة)', new.code
      using errcode = '42501';
  end if;
  return new;
end $$;



create or replace function public.tg_device_approval_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- فقط عند تغيير الحالة من pending/blocked إلى active أو blocked
  if old.status in ('pending','blocked')
     and new.status in ('active','blocked')
     and old.status is distinct from new.status then

    perform public.notify_employee(
      new.employee_id,
      case new.status
        when 'active'  then 'تم اعتماد جهازك'
        else 'تم رفض جهازك'
      end,
      case new.status
        when 'active'  then 'تم اعتماد جهاز ' || coalesce(new.device_name, 'غير معروف')
        else 'تم رفض جهاز ' || coalesce(new.device_name, 'غير معروف') ||
             coalesce(': ' || new.rejection_reason, '')
      end,
      'device',
      case new.status when 'active' then 'normal' else 'high' end,
      'device',
      new.id,
      jsonb_build_object(
        'kind', case new.status when 'active' then 'device_approved' else 'device_rejected' end,
        'deviceId', new.id,
        'deviceName', new.device_name
      )
    );
  end if;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION tg_employees_protect_job_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- SECURITY DEFINER يجعل current_user = المالك (postgres) دائمًا، لذا لا يمكن
  -- التمييز عبر current_user. نستبدل بالتحقق من غياب JWT claims (وصول صيانة مباشر)
  -- أو service_role (Edge Functions) — الحالة الصحيحة للتجاوز.
  IF current_setting('request.jwt.claims', true) IS NULL
     OR current_setting('request.jwt.claim.role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF (
    NEW.employee_code    IS DISTINCT FROM OLD.employee_code OR
    NEW.status           IS DISTINCT FROM OLD.status OR
    NEW.is_active        IS DISTINCT FROM OLD.is_active OR
    NEW.is_deleted       IS DISTINCT FROM OLD.is_deleted OR
    NEW.national_id_enc  IS DISTINCT FROM OLD.national_id_enc OR
    NEW.department_id    IS DISTINCT FROM OLD.department_id OR
    NEW.team_id          IS DISTINCT FROM OLD.team_id OR
    NEW.branch_id        IS DISTINCT FROM OLD.branch_id OR
    NEW.work_site_id     IS DISTINCT FROM OLD.work_site_id OR
    NEW.job_title_id     IS DISTINCT FROM OLD.job_title_id OR
    NEW.position_id      IS DISTINCT FROM OLD.position_id OR
    NEW.grade_id         IS DISTINCT FROM OLD.grade_id OR
    NEW.employment_type_id IS DISTINCT FROM OLD.employment_type_id OR
    NEW.hire_date        IS DISTINCT FROM OLD.hire_date OR
    NEW.contract_end     IS DISTINCT FROM OLD.contract_end OR
    NEW.user_id          IS DISTINCT FROM OLD.user_id
  ) THEN
    IF NOT (
      public.current_is_full_access()
      OR public.has_permission('people.employee.update_sensitive')
    ) THEN
      RAISE EXCEPTION 'ERR_FORBIDDEN: تعديل الحقول الحساسة يتطلب صلاحية people.employee.update_sensitive'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END
$$;



create or replace function public.tg_fundraising_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
begin
  -- فقط عند الموافقة على طلب فاندي
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;
  if new.request_type <> 'fundraising' then
    return new;
  end if;

  v_employee_id := new.employee_id;
  v_start_date := (new.payload->>'startDate')::date;
  v_end_date := coalesce((new.payload->>'endDate')::date, v_start_date);
  if v_start_date is null then
    return new;
  end if;

  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  v_day := v_start_date;
  while v_day <= v_end_date loop
    insert into public.attendance_daily (employee_id, work_date, status)
    values (v_employee_id, v_day, 'present')
    on conflict on constraint attendance_daily_uq do update
      set status = 'present',
          updated_at = now()
      where public.attendance_daily.is_finalized = false
        and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

    insert into public.attendance_exceptions (
      employee_id, attendance_daily_id, work_date, kind, description, status, created_by
    )
    select v_employee_id, ad.id, v_day, 'manual_adjustment',
           'فاندي معتمد — إعفاء من التأخير/الغياب',
           'approved', auth.uid()
    from public.attendance_daily ad
    where ad.employee_id = v_employee_id and ad.work_date = v_day
    on conflict do nothing;

    v_day := v_day + 1;
  end loop;

  perform public.log_audit_event(
    'request.attendance_exempted', 'workflow', 'info',
    'attendance_daily', v_employee_id,
    'إعفاء حضور بعد اعتماد فاندي',
    format('من %s إلى %s', v_start_date, v_end_date),
    jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                       'startDate', v_start_date, 'endDate', v_end_date)
  );

  return new;
end;
$$;



create or replace function public.tg_geofence_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.log_audit_event(
    'geofence.config_changed', 'security', 'warning',
    'geofences', new.id,
    'تغيير إعدادات السياج الجغرافي', null,
    jsonb_build_object(
      'code', new.code,
      'changes', jsonb_build_object(
        'radius_meters', jsonb_build_object('old', old.radius_meters, 'new', new.radius_meters),
        'max_accuracy', jsonb_build_object('old', old.max_accuracy, 'new', new.max_accuracy),
        'latitude', jsonb_build_object('old', old.latitude, 'new', new.latitude),
        'longitude', jsonb_build_object('old', old.longitude, 'new', new.longitude),
        'is_active', jsonb_build_object('old', old.is_active, 'new', new.is_active)
      )
    )
  );
  return new;
end;
$$;



create or replace function public.tg_leave_attendance_on_approval()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lr public.leave_requests;
  v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
  v_punch timestamptz;
  v_covered boolean;
begin
  if old.status = new.status then return new; end if;

  -- ── إجازة معتمدة: on_leave (مع حماية أيام العمل المعتمدة الأخرى) ──
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = يوم عمل → لا يُعلَّم إجازة
      v_covered := exists (
        select 1 from public.requests r
        where r.employee_id = v_lr.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and v_day between public._payload_date(r.payload, 'startDate')
                       and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      ) or exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = v_lr.employee_id and wa.status = 'APPROVED'
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                       and (wa.end_at at time zone 'Africa/Cairo')::date
      );
      if not v_covered then
        insert into public.attendance_daily(employee_id, work_date, status)
        values(v_lr.employee_id, v_day, 'on_leave')
        on conflict on constraint attendance_daily_uq do update
          set status = 'on_leave', updated_at = now()
          where public.attendance_daily.is_finalized = false
            and public.attendance_daily.status <> 'on_leave';
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'تم تعليم أيام الإجازة المعتمدة كـ on_leave في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- ── مأمورية/قافلة/فاندي معتمدة: أيام عمل → present (بلا خصم من الرصيد) ──
  if new.request_type in ('mission','convoy','fundraising') and new.status = 'approved' then
    v_emp := new.employee_id;
    if v_emp is null then
      return new; -- لا بيانات مصدرية للطلب → لا تعليم
    end if;
    v_start := public._payload_date(new.payload, 'startDate');
    v_end := coalesce(public._payload_date(new.payload, 'endDate'), v_start);

    if v_start is null then
      -- بلا payload: قراءة التواريخ من الخانات الخاصة (طلبات قديمة / إنشاء مباشر)
      v_start_ts := null; v_end_ts := null;
      if new.request_type = 'mission' then
        select start_at, end_at into v_start_ts, v_end_ts
        from public.missions where request_id = new.id;
      elsif new.request_type = 'convoy' then
        select departure_at, coalesce(return_at, departure_at) into v_start_ts, v_end_ts
        from public.convoy_requests where request_id = new.id;
      end if;
      if v_start_ts is null then
        return new;
      end if;
      v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
      v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    else
      -- ضبط الخانات الخاصة بالطلب من payload (متوافقة مع قراءة الكشف والتراجع)
      if new.request_type = 'mission'
         and not exists (select 1 from public.missions where request_id = new.id) then
        insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at, created_by)
        values (
          new.id, v_emp, coalesce(new.payload->>'location', ''), coalesce(new.title, ''),
          (v_start::text || case when new.payload->>'startTime' is not null
                                 then 'T' || (new.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          (v_end::text   || case when new.payload->>'endTime'   is not null
                                 then 'T' || (new.payload->>'endTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          new.created_by
        );
      elsif new.request_type = 'convoy'
            and not exists (select 1 from public.convoy_requests where request_id = new.id) then
        insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, created_by)
        values (
          new.id, v_emp,
          coalesce(coalesce(new.payload->>'convoyName', new.title), ''),
          coalesce(new.payload->>'origin', ''), coalesce(new.payload->>'location', ''),
          (v_start::text || case when new.payload->>'startTime' is not null
                                 then 'T' || (new.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          (case when new.payload->>'endTime' is not null
                then (v_end::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo'
                when v_end > v_start then (v_end::text || 'T00:00:00')::timestamp at time zone 'Africa/Cairo'
                else null end), -- endDate وحده => منتصف ليل نهايته; نفس اليوم بلا endTime => NULL (لا يخرق ck_convoy_period)
          new.created_by
        );
      end if;
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      -- بصمة حضور في أول يوم (من وقت بدء المأمورية إن وُجد — بدون بصمة = حضور مُسجَّل)
      v_punch := null;
      if v_day = v_start and new.payload->>'startTime' is not null then
        v_punch := (v_day::text || 'T' || (new.payload->>'startTime') || ':00')::timestamp at time zone 'Africa/Cairo';
      end if;
      insert into public.attendance_daily(employee_id, work_date, status, first_check_in)
      values(v_emp, v_day, 'present', v_punch)
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');

      -- بصمة انصراف في آخر يوم (وقت نهاية المأمورية إن وُجد — يُسجَّل الانصراف عند الامتداد خارج العمل)
      if v_day = v_end and new.payload->>'endTime' is not null then
        update public.attendance_daily
        set last_check_out = (v_day::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo',
            updated_at = now()
        where employee_id = v_emp and work_date = v_day
          and last_check_out is null and is_finalized = false;
      end if;

      -- بدل الراحة الأسبوعي: الجمعة خلال مأمورية/قافلة/فاندي
      if extract(isodow from v_day) = 5 then
        select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
        if v_type_id is not null then
          v_year := extract(year from v_day)::integer;
          perform public.apply_leave_ledger_entry(
            v_emp, v_type_id, v_year, 'credit', 1,
            'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
            null,
            'بدل راحة أسبوعي عن يوم عمل في ' || new.request_type || ' بتاريخ ' || to_char(v_day, 'YYYY-MM-DD'),
            jsonb_build_object('workDate', v_day::text, 'source', new.request_type, 'requestId', new.id)
          );
        end if;
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_emp,
      'تم تعليم أيام ' || new.request_type || ' المعتمدة كحضور عمل (present) بلا خصم',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $function$;



create or replace function public.tg_leave_reserve_on_detail()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lt public.leave_types; v_units numeric; v_year integer;
begin
  select * into v_lt from public.leave_types where id = new.leave_type_id;
  if not found then return new; end if;

  v_units := case when new.duration_unit='hour' then coalesce(new.hours_count,0) else coalesce(new.days_count,0) end;
  if v_units <= 0 then raise exception 'INVALID_LEAVE_DURATION'; end if;
  v_year := extract(year from new.start_date)::integer;

  -- بدل الراحة الأسبوعية (0428): حجز من الرصيد المكتسب عن عمل الجمعة.
  if v_lt.code = 'weekly_rest_comp' then
    perform public.apply_leave_ledger_entry(
      new.employee_id, new.leave_type_id, v_year, 'reserve', v_units,
      'weekly-rest:reserve:' || new.request_id, new.request_id,
      'حجز يوم بدل راحة — يتطلب رصيداً مكتسباً من العمل يوم الجمعة',
      jsonb_build_object('durationUnit', new.duration_unit)
    );
    return new;
  end if;

  if not coalesce(v_lt.affects_balance,false) then return new; end if;
  perform public.apply_leave_ledger_entry(new.employee_id,new.leave_type_id,v_year,'reserve',v_units,'leave:reserve:'||new.request_id,new.request_id,'حجز رصيد عند تقديم الطلب',jsonb_build_object('durationUnit',new.duration_unit));
  return new;
end $$;



create or replace function public.tg_leave_settle_on_request_decision()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lr public.leave_requests; v_lt public.leave_types; v_units numeric; v_year integer; v_has_reserve boolean;
begin
  if new.request_type <> 'leave' or old.status = new.status then return new; end if;
  select * into v_lr from public.leave_requests where request_id=new.id;
  if not found then return new; end if;
  select * into v_lt from public.leave_types where id=v_lr.leave_type_id;
  if not found then return new; end if;

  v_units := case when v_lr.duration_unit='hour' then coalesce(v_lr.hours_count,0) else coalesce(v_lr.days_count,0) end;
  v_year := extract(year from v_lr.start_date)::integer;

  -- بدل الراحة الأسبوعية (0428): consume عند الاعتماد (إن وُجد حجز — توافق
  -- قديم للطلبات المقدمة قبل 0428)، refund عند إلغاء معتمد، release خلاف ذلك.
  if v_lt.code = 'weekly_rest_comp' then
    if new.status='approved' then
      select exists(
        select 1 from public.leave_ledger_entries
        where source_key = 'weekly-rest:reserve:' || new.id
      ) into v_has_reserve;
      if v_has_reserve then
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'consume', v_units,
          'weekly-rest:consume:' || new.id, new.id,
          'استهلاك رصيد بدل الراحة بعد الاعتماد'
        );
      end if;
    elsif new.status in ('rejected','cancelled','withdrawn','expired') then
      if old.status='approved' then
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'refund', v_units,
          'weekly-rest:refund:' || new.id || ':' || new.status, new.id,
          'استرداد رصيد بدل الراحة بعد إلغاء طلب معتمد (' || new.status || ')'
        );
      else
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'release', v_units,
          'weekly-rest:release:' || new.id || ':' || new.status, new.id,
          'تحرير حجز بدل الراحة بعد ' || new.status
        );
      end if;
    end if;
    return new;
  end if;

  if not coalesce(v_lt.affects_balance,false) then return new; end if;
  if new.status='approved' then
    perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'consume',v_units,'leave:consume:'||new.id,new.id,'خصم الرصيد بعد الاعتماد');
  elsif new.status in ('rejected','cancelled','withdrawn','expired') then
    -- LEDGER-02: إلغاء طلب معتمد → refund؛ إلغاء من حالة معلقة → release.
    if old.status='approved' then
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'refund',v_units,'leave:refund:'||new.id||':'||new.status,new.id,'استرداد الرصيد بعد إلغاء طلب معتمد ('||new.status||')');
    else
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'release',v_units,'leave:release:'||new.id||':'||new.status,new.id,'تحرير الحجز بعد '||new.status);
    end if;
  end if;
  return new;
end $$;



create or replace function public.tg_mission_execution_close_on_cancel()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status in ('rejected','cancelled','withdrawn','expired') then
    update public.mission_executions
       set status     = 'completed',
           ended_at   = coalesce(ended_at, now()),
           report     = coalesce(report, 'أُلغي الطلب قبل إتمام التنفيذ'),
           updated_at = now()
     where request_id = new.id and status = 'in_progress';
  end if;
  return new;
end $$;



create or replace function public.tg_notify_awareness_on_request_submit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_body   text;
  v_emp_id uuid;
begin
  v_body := format('%s: %s',
    public.request_type_label(new.request_type),
    coalesce(new.title, ''));

  -- المدير التنفيذي (للإطلاع فقط، بدون صلاحية قرار في هذه المرحلة)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('executive-director', 'executive')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      'طلب جديد — للإطلاع',
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  -- HR (للمتابعة فقط، بدون صلاحية قرار إلا بعد 6 ساعات)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('hr-manager', 'hr-specialist')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      'طلب جديد — للمتابعة',
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  return new;
end;
$$;



create or replace function public.tg_notify_manager_late_arrival()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee    record;
  v_manager     record;
  v_notif_id    uuid;
  v_late_text   text;
begin
  -- تنطبق فقط على CHECK_IN متأخر (late_minutes > 0)
  if new.event_type <> 'CHECK_IN' or coalesce(new.late_minutes, 0) <= 0 then
    return new;
  end if;

  -- جلب بيانات الموظف المتأخر
  select e.id, e.full_name_ar, e.user_id
    into v_employee
    from public.employees e
   where e.id = new.employee_id;

  if not found then return new; end if;

  -- جلب المدير المباشر (أول مدير في manager_relations)
  select e.id, e.user_id
    into v_manager
    from public.manager_relations mr
    join public.employees e on e.id = mr.manager_employee_id
   where mr.employee_id = new.employee_id
     and e.user_id is not null
     and e.is_active = true
   limit 1;

  if not found or v_manager.user_id is null then return new; end if;

  -- صياغة وقت التأخير
  v_late_text := case
    when new.late_minutes >= 60 then
      (new.late_minutes / 60)::text || ' ساعة ' || (new.late_minutes % 60)::text || ' دقيقة'
    else
      new.late_minutes::text || ' دقيقة'
  end;

  -- إدراج الإشعار — الـ trigger trg_notifications_queue_jobs يُضيف notification_jobs تلقائياً
  insert into public.notifications (
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    entity_type,
    entity_id,
    metadata
  ) values (
    v_manager.user_id,
    v_manager.id,
    'موظف متأخر: ' || coalesce(v_employee.full_name_ar, 'غير محدد'),
    'سجّل ' || coalesce(v_employee.full_name_ar, 'الموظف') || ' حضوره متأخراً بمقدار ' || v_late_text || '.',
    'system',
    'normal',
    'attendance_event',
    new.id,
    jsonb_build_object(
      'lateMinutes', new.late_minutes,
      'employeeId', new.employee_id::text
    )
  ) returning id into v_notif_id;

  return new;
exception
  when others then
    -- الإشعار اختياري — لا يعطّل تسجيل الحضور
    return new;
end;
$$;



CREATE OR REPLACE FUNCTION public.tg_profiles_protect_sensitive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_self_activation boolean;
begin
  -- السياقات الموثوقة تمر مباشرة. لا نستخدم current_user هنا لأنه داخل دالة
  -- security definer يعود باسم المالك (postgres) دائماً — بل نستخدم auth.role()
  -- المستخرجة من JWT الطلب (نمط مطبّق في 0026/0033).
  if auth.role() = 'service_role'
     or public.current_is_full_access()
     or public.has_permission('profiles.manage') then
    return new;
  end if;

  -- الحقول الأكثر حساسية محظورة على أي مستخدم غير مخوّل مهما كان.
  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'غير مصرح بتغيير الدور الأساسي' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'غير مصرح بتغيير معرّف الموظف' using errcode = '42501';
  end if;

  -- التفعيل الذاتي: الموظف يفعّل ملفه بنفسه بعد أول ضبط كلمة مرور
  -- (activate_employee_after_first_login من الويب/الموبايل) — المسار الوحيد
  -- المسموح لغير المخوّل لتغيير status/temporary_password.
  v_self_activation :=
       new.id = auth.uid()
       and old.status in ('pending', 'invited', 'onboarding', 'draft')
       and new.status = 'active'
       and new.temporary_password = false;

  if new.status is distinct from old.status and not v_self_activation then
    raise exception 'غير مصرح لك بتغيير الحالة' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password and not v_self_activation then
    raise exception 'غير مصرح بتغيير كلمة المرور المؤقتة' using errcode = '42501';
  end if;

  return new;
end;
$function$;



create or replace function public.tg_request_approved_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_work_date date;
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
begin
  -- فقط عند الموافقة على الطلب
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;

  v_employee_id := new.employee_id;

  -- تجاهل الإجازات — لها تريجر خاص (tg_leave_attendance_on_approval)
  if new.request_type = 'leave' then
    return new;
  end if;

  -- اسم الموظف للإشعار
  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  -- ─── المأمورية/القافلة/الفاندي: قراءة التواريخ من payload الطلب ──────────
  if new.request_type in ('mission', 'convoy', 'fundraising') then
    v_start_date := (new.payload->>'startDate')::date;
    v_end_date   := coalesce((new.payload->>'endDate')::date, v_start_date);
    if v_start_date is null then return new; end if;

    v_day := v_start_date;
    while v_day <= v_end_date loop
      insert into public.attendance_daily (employee_id, work_date, status)
      values (v_employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

      -- سجل استثناء: مأمورية معتمدة
      insert into public.attendance_exceptions (
        employee_id, attendance_daily_id, work_date, kind, description, status, created_by
      )
      select v_employee_id, ad.id, v_day, 'manual_adjustment',
             'مأمورية معتمدة — إعفاء من التأخير/الغياب',
             'approved', auth.uid()
      from public.attendance_daily ad
      where ad.employee_id = v_employee_id and ad.work_date = v_day
      on conflict do nothing;

      v_day := v_day + 1;
    end loop;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد مأمورية',
      format('من %s إلى %s', v_start_date, v_end_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                         'startDate', v_start_date, 'endDate', v_end_date)
    );
    return new;
  end if;

  -- ─── إذن تأخير/انصراف: قراءة permitDate من payload ──────────────────
  if new.request_type in ('late_permit', 'early_permit') then
    v_work_date := (new.payload->>'permitDate')::date;
    if v_work_date is null then
      v_work_date := (new.payload->>'date')::date;
    end if;
    if v_work_date is null then return new; end if;

    if new.request_type = 'late_permit' then
      insert into public.attendance_daily (employee_id, work_date, status, late_minutes)
      values (v_employee_id, v_work_date, 'present', 0)
      on conflict on constraint attendance_daily_uq do update
        set late_minutes = 0,
            status = case when public.attendance_daily.status in ('on_leave','holiday','weekend')
                         then public.attendance_daily.status else 'present' end,
            updated_at = now()
        where public.attendance_daily.is_finalized = false;

      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'late',
              'إذن تأخير معتمد — إعفاء من دقائق التأخير',
              0, 'approved', auth.uid())
      on conflict do nothing;
    else
      -- إذن انصراف مبكر: سجل استثناء
      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'early_leave',
              'إذن انصراف مبكر معتمد',
              0, 'approved', auth.uid())
      on conflict do nothing;
    end if;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد طلب',
      format('النوع: %s، التاريخ: %s', new.request_type, v_work_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type, 'workDate', v_work_date)
    );
    return new;
  end if;

  -- أنواع أخرى (attendance_correction) — لا نعالجها
  return new;
end;
$$;



create or replace function public.tg_weekly_rest_credit_on_attendance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type_id uuid;
  v_year    integer;
begin
  -- الجمعة فقط (isodow=5)
  if extract(isodow from new.work_date) <> 5 then
    return new;
  end if;

  -- عمل فعلي: بصمة دخول/خروج موجودة أو حالة تشير لحضور فعلي
  -- (المصمم أعلاه متطابق مع تعريف 0005+0169: present|late|partial|missing_checkout)
  if new.first_check_in is null
     and new.last_check_out is null
     and new.status not in ('present','late','partial','missing_checkout') then
    return new;
  end if;

  select id into v_type_id
  from public.leave_types
  where code = 'weekly_rest_comp';
  if v_type_id is null then
    return new; -- النوع غير معرّف (بيئة قديمة) — لا نقف ترقية.
  end if;

  v_year := extract(year from new.work_date)::integer;

  -- source_key معرفي لكل (موظف + يوم) → idempotent مهما تكررت التحديثات.
  perform public.apply_leave_ledger_entry(
    new.employee_id, v_type_id, v_year, 'credit', 1,
    'weekly-rest:credit:' || new.employee_id::text || ':' || new.work_date::text,
    null,
    'رصيد بدل راحة أسبوعي عن العمل يوم الجمعة ' || to_char(new.work_date, 'YYYY-MM-DD'),
    jsonb_build_object('workDate', new.work_date::text)
  );

  return new;
end;
$$;



create or replace function public.tg_work_assignment_attendance_link()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_p record; v_day date; v_end date; v_type_id uuid; v_year integer; v_emp uuid;
begin
  if old is not null and old.status = new.status then return new; end if;

  -- اعتماد (بما فيه الإنشاء بحالة APPROVED من create_work_assignment)
  if new.status = 'APPROVED' then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        if coalesce(new.counts_as_work_day, true) then
          insert into public.attendance_daily(employee_id, work_date, status)
          values(v_emp, v_day, 'present')
          on conflict on constraint attendance_daily_uq do update
            set status = 'present', updated_at = now()
            where public.attendance_daily.is_finalized = false
              and public.attendance_daily.status not in ('holiday','weekend');
        end if;
        -- بدل الراحة الأسبوعي عن الجمعة ضمن التكليف
        if extract(isodow from v_day) = 5 then
          select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
          if v_type_id is not null then
            v_year := extract(year from v_day)::integer;
            perform public.apply_leave_ledger_entry(
              v_emp, v_type_id, v_year, 'credit', 1,
              'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
              null,
              'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
              jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', new.id)
            );
          end if;
        end if;
        v_day := v_day + 1;
      end loop;
    end loop;
    return new;
  end if;

  -- إلغاء/رفض بعد اعتماد: تراجع عن الأيام غير المثبتة ما لم يغطّها اعتماد آخر
  if old.status = 'APPROVED' and new.status in ('REJECTED','CANCELLED') then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        update public.attendance_daily ad
        set status = 'absent', updated_at = now()
        where ad.employee_id = v_emp and ad.work_date = v_day
          and ad.is_finalized = false and ad.status = 'present'
          and ad.first_check_in is null and ad.last_check_out is null
          and not exists (
            select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
            where lr.employee_id = v_emp and r.status = 'approved'
              and v_day between lr.start_date and lr.end_date)
          and not exists (
            select 1 from public.missions m join public.requests r on r.id = m.request_id
            where m.employee_id = v_emp and r.status = 'approved'
              and v_day between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
            where c.employee_id = v_emp and r.status = 'approved'
              and v_day between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.work_assignment_participants wp2 join public.work_assignments wa2 on wa2.id = wp2.assignment_id
            where wp2.employee_id = v_emp and wa2.status = 'APPROVED' and wa2.id <> new.id
              and v_day between (wa2.start_at at time zone 'Africa/Cairo')::date and (wa2.end_at at time zone 'Africa/Cairo')::date);
        v_day := v_day + 1;
      end loop;
    end loop;
  end if;
  return new;
end $function$;



create or replace function public.tg_work_assignment_participant_link()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_wa public.work_assignments;
  v_day date; v_end date; v_type_id uuid; v_year integer;
begin
  select * into v_wa from public.work_assignments where id = new.assignment_id;
  if not found or v_wa.status <> 'APPROVED' then return new; end if;
  v_day := (v_wa.start_at at time zone 'Africa/Cairo')::date;
  v_end := (v_wa.end_at at time zone 'Africa/Cairo')::date;
  while v_day <= v_end loop
    if coalesce(v_wa.counts_as_work_day, true) then
      insert into public.attendance_daily(employee_id, work_date, status)
      values(new.employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');
    end if;
    if extract(isodow from v_day) = 5 then
      select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
      if v_type_id is not null then
        v_year := extract(year from v_day)::integer;
        perform public.apply_leave_ledger_entry(
          new.employee_id, v_type_id, v_year, 'credit', 1,
          'weekly-rest:credit:' || new.employee_id::text || ':' || v_day::text,
          null,
          'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
          jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', v_wa.id)
        );
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return new;
end $function$;



create or replace function public.toggle_announcement_reaction(p_announcement_id uuid,p_reaction_type text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_me uuid:=public.current_employee_id(); v_existing text; v_actor text;
  v_publisher_user uuid; v_publisher_employee uuid; v_title text; v_active boolean:=true;
begin
  if v_me is null then raise exception 'no employee linked to current user' using errcode='42501'; end if;
  if p_reaction_type not in ('like','celebrate','support','insightful') then
    raise exception 'invalid reaction type' using errcode='22023';
  end if;
  select a.title,a.created_by,p.employee_id into v_title,v_publisher_user,v_publisher_employee
  from public.announcements a left join public.profiles p on p.id=a.created_by and p.status='active'
  where a.id=p_announcement_id and a.status='published';
  if not found then raise exception 'announcement not found or not visible' using errcode='P0002'; end if;

  select reaction_type into v_existing from public.announcement_reactions
  where announcement_id=p_announcement_id and employee_id=v_me for update;
  if v_existing=p_reaction_type then
    delete from public.announcement_reactions where announcement_id=p_announcement_id and employee_id=v_me;
    v_active:=false;
  else
    insert into public.announcement_reactions(announcement_id,employee_id,reaction_type,created_by)
    values(p_announcement_id,v_me,p_reaction_type,auth.uid())
    on conflict(announcement_id,employee_id) do update set reaction_type=excluded.reaction_type,updated_at=now();
    if v_publisher_user is not null and v_publisher_employee is distinct from v_me then
      select full_name_ar into v_actor from public.employees where id=v_me;
      perform public.notify_user(
        v_publisher_user,'تفاعل جديد على إعلانك',
        coalesce(v_actor,'أحد الموظفين')||' تفاعل مع «'||left(v_title,120)||'».',
        'announcement','normal','announcement',p_announcement_id,
        jsonb_build_object('kind','announcement_reaction','reactionType',p_reaction_type,
          'actorEmployeeId',v_me,'announcementId',p_announcement_id));
    end if;
  end if;
  return jsonb_build_object(
    'active',v_active,'myReaction',case when v_active then p_reaction_type else null end,
    'viewCount',(select count(*)::integer from public.announcement_views where announcement_id=p_announcement_id),
    'reactionCount',(select count(*)::integer from public.announcement_reactions where announcement_id=p_announcement_id),
    'reactionSummary',coalesce((select jsonb_object_agg(reaction_type,total) from (
      select reaction_type,count(*)::integer total from public.announcement_reactions
      where announcement_id=p_announcement_id group by reaction_type) s),'{}'::jsonb));
end $$;



CREATE OR REPLACE FUNCTION public.toggle_daily_report_like(p_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_liked boolean;
  v_count integer;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me
  ) then
    delete from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me;
    v_liked := false;
  else
    insert into public.daily_report_likes (report_id, employee_id)
    values (p_report_id, v_me);
    v_liked := true;

    -- إشعار صاحب التقرير (لا يشعر نفسه)
    if v_author is distinct from v_me then
      perform public.notify_employee(
        v_author,
        'أُعجب شخص بتقريرك اليومي',
        'أُعجب أحد زملائك بتقريرك اليومي.',
        'general', 'low', 'daily_reports', p_report_id,
        jsonb_build_object('event', 'daily_report_like')
      );
    end if;
  end if;

  select count(*) into v_count
  from public.daily_report_likes
  where report_id = p_report_id;

  return jsonb_build_object('liked', v_liked, 'count', v_count);
end;
$function$;



create or replace function public.transition_decision(
  p_decision_id uuid,p_action text,p_reason text default null,p_scheduled_for timestamptz default null
) returns public.administrative_decisions language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.administrative_decisions; v_from text; v_to text; v_emp uuid:=public.current_employee_id();
begin
  select * into strict v_row from public.administrative_decisions where id=p_decision_id for update;
  v_from:=v_row.status;
  if p_action='submit_review' and v_from='draft' then v_to:='in_review';
  elsif p_action='approve' and v_from='in_review' then
    if not(public.current_is_full_access() or public.has_permission('comms.decision.approve')) then raise exception 'FORBIDDEN'; end if;
    -- Four-eyes: the approver must not be the author or the submitter (SoD).
    if v_emp is not null and (
         v_row.issued_by = v_emp
         or v_row.created_by = auth.uid()
         or exists (
           select 1 from public.decision_actions da
           where da.decision_id = p_decision_id
             and da.action_type in ('create','submit_review')
             and da.actor_employee_id = v_emp
         )
       ) then
      raise exception 'FOUR_EYES_REQUIRED: the approver must differ from the author/submitter' using errcode='42501';
    end if;
    v_to:='approved';
  elsif p_action='return' and v_from='in_review' then v_to:='draft';
  elsif p_action='schedule' and v_from='approved' and p_scheduled_for>now() then v_to:='scheduled';
  elsif p_action='publish' and v_from in ('approved','scheduled') then v_to:='published';
  elsif p_action='archive' and v_from='published' then v_to:='archived';
  elsif p_action='revoke' and v_from in ('approved','scheduled','published') then v_to:='revoked';
  else raise exception 'INVALID_DECISION_TRANSITION'; end if;
  if p_action in ('return','revoke') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
  if p_action not in ('approve') and not(public.current_is_full_access() or public.has_permission('comms.decision.manage')) then raise exception 'FORBIDDEN'; end if;
  update public.administrative_decisions set status=v_to,
    approved_at=case when v_to='approved' then now() else approved_at end,
    approved_by=case when v_to='approved' then v_emp else approved_by end,
    scheduled_for=case when v_to='scheduled' then p_scheduled_for else scheduled_for end,
    published_at=case when v_to='published' then now() else published_at end,
    updated_at=now()
  where id=p_decision_id returning * into v_row;
  insert into public.decision_actions(decision_id,action_type,from_status,to_status,reason,actor_employee_id,actor_user_id)
  values(p_decision_id,p_action,v_from,v_to,nullif(trim(coalesce(p_reason,'')),''),v_emp,auth.uid());
  perform public.log_audit_event('decision.'||p_action,'governance',case when p_action='revoke' then 'warning' else 'info' end,'administrative_decisions',p_decision_id,'انتقال قرار من '||v_from||' إلى '||v_to,p_reason,jsonb_build_object('from',v_from,'to',v_to));
  return v_row;
end $$;



create or replace function public.transition_dispute_case(p_case_id uuid,p_action text,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases; v_next text; v_target uuid; v_priority text; v_role_ok boolean;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 v_role_ok:=public.current_is_full_access() or public.has_permission('disputes.case.transition');
 if p_action in ('escalate','return_to_committee') then v_role_ok:=v_role_ok or public.has_permission('disputes.case.escalate') or public.has_permission('disputes.executive.manage'); end if;
 if not v_role_ok then raise exception 'FORBIDDEN' using errcode='42501'; end if;

 v_next:=case p_action
  when 'request_more_information' then 'needs_more_information'
  when 'accept' then 'accepted'
  when 'reject' then 'rejected'
  when 'start_review' then 'under_review'
  when 'request_respondent_statement' then 'waiting_for_respondent'
  when 'request_witness_statement' then 'waiting_for_witness'
  when 'start_deliberation' then 'committee_deliberation'
  when 'settlement_pending' then 'settlement_pending'
  when 'escalate' then 'escalated_to_executive'
  when 'return_to_committee' then 'returned_to_committee'
  when 'close' then 'closed'
  when 'reopen' then 'reopened'
  when 'resolve_friendly' then 'resolved_friendly'
  when 'force_status' then p_metadata->>'status'
  else null end;

 if p_action='extend_review' then
  if v.status not in ('submitted','needs_more_information') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'EXTENSION_NOT_ALLOWED' using errcode='22023'; end if;
  update public.dispute_cases set review_due_at=greatest(coalesce(review_due_at,now()),now())+interval '24 hours',review_extended_at=now(),review_extension_reason=trim(p_reason),updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id) values(p_case_id,'extend_review',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid());
  perform public.log_audit_event('dispute.review_extended','workflow','warning','dispute_cases',p_case_id,'تمديد مهلة مراجعة المشكلة',trim(p_reason));
  return v.status;
 end if;

 if p_action='change_priority' then
  v_priority=p_metadata->>'priority';
  if v_priority not in ('normal','urgent','critical') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'INVALID_PRIORITY_CHANGE' using errcode='22023'; end if;
  update public.dispute_cases set severity=v_priority,updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata) values(p_case_id,'change_priority',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid(),jsonb_build_object('from',v.severity,'to',v_priority));
  perform public.log_audit_event('dispute.priority_changed','workflow','warning','dispute_cases',p_case_id,'تغيير أولوية المشكلة',trim(p_reason),jsonb_build_object('from',v.severity,'to',v_priority));
  return v.status;
 end if;

 if v_next is null then raise exception 'UNKNOWN_ACTION' using errcode='22023'; end if;
 if p_action='request_more_information' and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('accept','reject') and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action='start_review' and v.status not in ('accepted','reopened','returned_to_committee') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('request_respondent_statement','request_witness_statement') and v.status not in ('accepted','under_review','waiting_for_respondent','waiting_for_witness') then raise exception 'INVALID_STATE'; end if;
 -- V23: resolve_friendly allowed from active review states
 if p_action='resolve_friendly' then
  if v.status not in ('under_review','waiting_for_respondent','waiting_for_witness','committee_deliberation') then raise exception 'INVALID_STATE'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
 end if;
 if p_action='close' then
  -- V23 + 0202: إضافة 'executed' للسماح بإغلاق القضايا بعد تنفيذ الإجراء الإداري
  if v.status not in ('decision_issued','settlement_pending','resolved_friendly','executed') then raise exception 'CLOSE_NOT_ALLOWED'; end if;
  if exists(select 1 from public.dispute_actions where case_id=p_case_id and execution_status in ('pending','in_progress','failed')) or exists(select 1 from public.dispute_settlements where case_id=p_case_id and status='pending') then raise exception 'PENDING_IMPLEMENTATION'; end if;
 end if;
 -- V23: add resolved_friendly to force_status allowed list (+ executed)
 if p_action='force_status' and (not public.current_is_full_access() or v_next not in ('submitted','needs_more_information','accepted','rejected','under_review','waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed','committee_deliberation','settlement_pending','escalated_to_executive','returned_to_committee','decision_issued','resolved_friendly','executed','closed','reopened','cancelled_by_employee')) then raise exception 'INVALID_FORCE_STATUS'; end if;
 if p_action in ('reject','request_more_information','escalate','return_to_committee','close','reopen','force_status') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;

 if p_action='accept' then
  update public.dispute_cases set accepted_at=coalesce(accepted_at,now()),accepted_by=public.current_employee_id(),decision_due_at=coalesce(decision_due_at,now()+interval '7 days') where id=p_case_id;
 elsif p_action in ('request_respondent_statement','request_witness_statement') then
  v_target=(p_metadata->>'employeeId')::uuid;
  update public.dispute_parties set notification_status='notified',notified_at=coalesce(notified_at,now()),statement_requested_at=now(),updated_at=now()
  where case_id=p_case_id and employee_id=v_target and party_type=case when p_action='request_witness_statement' then 'witness' else 'respondent' end;
  if not found then raise exception 'PARTY_NOT_FOUND' using errcode='P0002'; end if;
  update public.dispute_cases set shareable_summary=coalesce(nullif(trim(p_metadata->>'summary'),''),shareable_summary,'توجد مشكلة تتطلب إفادتك'),respondent_notified_at=case when p_action='request_respondent_statement' then coalesce(respondent_notified_at,now()) else respondent_notified_at end where id=p_case_id;
  perform public.enqueue_dispute_notification(p_case_id,v_target,p_action||':'||v_target::text,
   case when p_action='request_witness_statement' then 'طلب إفادة شاهد' else 'طلب إفادة بشأن مشكلة' end,
   coalesce(nullif(trim(p_metadata->>'summary'),''),'يرجى فتح قسم الشكاوى وتقديم إفادتك.'),'high');
 elsif p_action='escalate' then
  update public.dispute_cases set escalated_at=now(),escalated_by=public.current_employee_id() where id=p_case_id;
  for v_target in select distinct e.id from public.employees e join public.user_roles ur on ur.user_id=e.user_id join public.roles r on r.id=ur.role_id where r.slug='executive-director' and ur.effective_from<=now() and (ur.effective_to is null or ur.effective_to>now()) loop
   perform public.enqueue_dispute_notification(p_case_id,v_target,'escalated:'||v_target::text,'قضية مصعدة للمدير التنفيذي',coalesce(trim(p_reason),'تتطلب مراجعة تنفيذية'),'urgent');
  end loop;
 elsif p_action='resolve_friendly' then
  -- V23: set resolution fields for friendly resolution
  update public.dispute_cases set resolved_at=now(),resolution_summary=trim(p_reason) where id=p_case_id;
 elsif p_action='close' then
  update public.dispute_cases set closed_at=now(),closed_by=public.current_employee_id(),closure_reason=trim(p_reason) where id=p_case_id;
 elsif p_action='reopen' then
  update public.dispute_cases set reopened_at=now(),closed_at=null,closed_by=null where id=p_case_id;
 end if;

 update public.dispute_cases set status=v_next,updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,p_action,v.status,v_next,nullif(trim(p_reason),''),public.current_employee_id(),auth.uid(),coalesce(p_metadata,'{}'::jsonb));
 perform public.log_audit_event('dispute.'||p_action,'workflow',case when p_action in ('escalate','force_status') then 'warning' else 'notice' end,'dispute_cases',p_case_id,'تغيير مسار المشكلة',p_reason,jsonb_build_object('from',v.status,'to',v_next));

 if v.actor_employee_id is not null and p_action in ('accept','reject','request_more_information','escalate','return_to_committee','close','reopen','resolve_friendly') then
  perform public.enqueue_dispute_notification(p_case_id,v.actor_employee_id,p_action||':actor',
   case p_action when 'accept' then 'تم قبول المشكلة للدراسة' when 'reject' then 'تم رفض المشكلة شكليًا' when 'request_more_information' then 'مطلوب استكمال بيانات المشكلة' when 'escalate' then 'تم تصعيد المشكلة' when 'return_to_committee' then 'أعيدت المشكلة إلى اللجنة' when 'close' then 'تم إغلاق المشكلة' when 'resolve_friendly' then 'تم حل المشكلة وديًا' else 'أعيد فتح المشكلة' end,
   coalesce(nullif(trim(p_reason),''),'يمكنك متابعة الحالة من قسم الشكاوى.'),case when p_action in ('reject','request_more_information') then 'high' else 'normal' end);
 end if;
 return v_next;
end $$;



create or replace function public.transition_job_offer_admin(
  p_offer_id uuid,
  p_action text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_current text; v_next text; v_app uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.offer.manage')) then raise exception 'FORBIDDEN'; end if;
  select status, application_id into v_current, v_app from public.job_offers where id = p_offer_id for update;
  if v_current is null then raise exception 'OFFER_NOT_FOUND'; end if;

  v_next := case
    when p_action = 'submit'   and v_current = 'draft'    then 'pending'
    when p_action = 'approve'  and v_current = 'pending'  then 'approved'
    when p_action = 'send'     and v_current = 'approved' then 'sent'
    when p_action = 'accept'   and v_current = 'sent'     then 'accepted'
    when p_action = 'decline'  and v_current = 'sent'     then 'declined'
    when p_action = 'withdraw' and v_current in ('draft','pending','approved','sent') then 'withdrawn'
    else null
  end;
  if v_next is null then raise exception 'INVALID_OFFER_TRANSITION'; end if;

  update public.job_offers set status = v_next, updated_at = now() where id = p_offer_id;
  perform public.log_audit_event('recruitment.offer_'||v_next,'workflow','info','job_offers',p_offer_id,
    'انتقال حالة عرض توظيف', null, jsonb_build_object('applicationId',v_app,'from',v_current,'to',v_next));
  return jsonb_build_object('offerId', p_offer_id, 'status', v_next);
end $$;



CREATE OR REPLACE FUNCTION public.transition_my_task(p_task_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_task public.tasks%rowtype;
  v_onboarding public.onboarding_tasks%rowtype;
  v_journey public.onboarding_journeys%rowtype;
  v_db_status text;
  v_remaining integer;
begin
  if p_status not in ('pending','in_progress','done') then
    raise exception 'حالة مهمة غير مدعومة' using errcode = '22023';
  end if;

  select * into v_task from public.tasks where id = p_task_id for update;
  if found then
    if v_task.assignee_employee_id is distinct from v_employee_id then
      raise exception 'المهمة خارج نطاقك' using errcode = '42501';
    end if;
    if v_task.status = 'cancelled' then
      raise exception 'المهمة الملغاة لا تتغير' using errcode = 'P0001';
    end if;
    if v_task.status = 'done' and p_status <> 'done' then
      raise exception 'إعادة فتح المهمة المكتملة لصاحبها أو الإدارة فقط' using errcode = '42501';
    end if;
    update public.tasks set status = p_status, updated_at = now() where id = p_task_id;
    return jsonb_build_object('id', p_task_id, 'sourceType', 'task', 'status', p_status, 'updatedAt', now());
  end if;

  select ot.* into v_onboarding
  from public.onboarding_tasks ot
  where ot.id = p_task_id
  for update;
  if not found then raise exception 'المهمة غير موجودة' using errcode = 'P0002'; end if;

  select j.* into v_journey
  from public.onboarding_journeys j
  where j.id = v_onboarding.journey_id
  for update;

  if not (
    v_onboarding.assignee_id = v_employee_id
    or (v_onboarding.assignee_id is null and v_journey.employee_id = v_employee_id and lower(coalesce(v_onboarding.owner_role, '')) in ('employee','موظف'))
  ) then
    raise exception 'مهمة التهيئة خارج نطاقك' using errcode = '42501';
  end if;
  if v_onboarding.status in ('completed','skipped') and p_status <> 'done' then
    raise exception 'الموظف لا يعيد فتح مهمة تهيئة مكتملة' using errcode = '42501';
  end if;

  v_db_status := case p_status when 'done' then 'completed' else p_status end;
  update public.onboarding_tasks set
    status = v_db_status,
    completed_at = case when v_db_status = 'completed' then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id;

  select count(*) into v_remaining
  from public.onboarding_tasks
  where journey_id = v_onboarding.journey_id and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_onboarding.journey_id;
    update public.employees set status = 'active', updated_at = now()
    where id = v_journey.employee_id and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_onboarding.journey_id;
  end if;

  return jsonb_build_object(
    'id', p_task_id, 'sourceType', 'onboarding', 'status', p_status,
    'journeyId', v_onboarding.journey_id, 'remainingTasks', v_remaining,
    'updatedAt', now()
  );
end;
$function$;



CREATE OR REPLACE FUNCTION public.transition_onboarding_task_admin(p_task_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_journey uuid;
  v_remaining integer;
  v_employee uuid;
begin
  if p_status not in ('pending','in_progress','completed','skipped') then
    raise exception 'حالة مهمة تهيئة غير صالحة' using errcode = '22023';
  end if;
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'انتقال مهمة التهيئة مرفوض' using errcode = '42501';
  end if;

  update public.onboarding_tasks set
    status = p_status,
    completed_at = case when p_status in ('completed','skipped') then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id
  returning journey_id into v_journey;
  if v_journey is null then raise exception 'مهمة التهيئة غير موجودة' using errcode = 'P0002'; end if;

  select count(*) into v_remaining from public.onboarding_tasks
  where journey_id = v_journey and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_journey;
    select employee_id into v_employee from public.onboarding_journeys where id = v_journey;
    update public.employees set status = 'active', updated_at = now() where id = v_employee and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_journey;
  end if;

  return jsonb_build_object('journeyId', v_journey, 'remainingTasks', v_remaining, 'completed', v_remaining = 0);
end;
$function$;



create or replace function public.trg_announcement_broadcast_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فقط عند الانتقال إلى حالة published
  if new.status <> 'published' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'published' then
    return new;
  end if;

  -- إدراج إشعار لكل موظف نشط لديه حساب مستخدم
  insert into public.notifications(
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    entity_type,
    entity_id,
    metadata,
    created_by
  )
  select
    p.id,
    e.id,
    'إعلان رسمي جديد',
    left(new.title, 200),
    'announcement',
    coalesce(new.priority, 'normal'),
    'announcement',
    new.id,
    jsonb_build_object(
      'announcement_id', new.id::text,
      'category', coalesce(new.category, 'general')
    ),
    coalesce(new.created_by, '00000000-0000-0000-0000-000000000000'::uuid)
  from public.employees e
  join public.profiles p on p.employee_id = e.id
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active'
    and e.user_id is not null;

  return new;
end;
$$;



create or replace function public.trg_casual_leave_auto_approved_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.status = new.status
     or new.status <> 'approved'
     or new.request_type <> 'leave'
     or coalesce(new.payload->>'leaveType', '') <> 'casual'
     or new.decided_by is distinct from new.employee_id then
    return new;
  end if;

  perform public.notify_employee(
    new.employee_id,
    'تم اعتماد إجازتك العارضة',
    coalesce(new.title, 'تم تسجيل الإجازة العارضة وتنفيذها مباشرة.'),
    'request', 'normal', 'request', new.id,
    jsonb_build_object(
      'kind', 'casual_leave_auto_approved',
      'decision', 'approve',
      'requestType', 'leave'
    )
  );

  return new;
end;
$$;



create or replace function public.trg_fn_device_pending_notify_admins()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin record;
  v_emp_name text;
begin
  if NEW.status <> 'pending' then
    return NEW;
  end if;

  select full_name_ar into v_emp_name
  from public.employees where id = NEW.employee_id;

  for v_admin in
    select e.id as employee_id, p.id as user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id and r.is_full_access = true
    join public.profiles p on p.id = ur.user_id and p.status = 'active'
    join public.employees e on e.id = p.employee_id and e.is_active = true
  loop
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, entity_type, entity_id, metadata, created_by
    ) values (
      v_admin.user_id, v_admin.employee_id,
      'جهاز جديد بانتظار الموافقة',
      'الموظف ' || coalesce(v_emp_name, 'غير معروف') || ' سجّل جهازاً جديداً (' || coalesce(NEW.device_name, 'جهاز') || ') وينتظر موافقتك.',
      'system', 'normal',
      'employee_device', NEW.id,
      jsonb_build_object('kind', 'device_pending_approval', 'employeeId', NEW.employee_id, 'deviceName', NEW.device_name),
      NEW.user_id
    );
  end loop;

  return NEW;
end;
$$;



create or replace function public.trg_fn_employee_devices_auto_replace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- إبعاد كل جهاز آخر نشط لنفس الموظف — الجهاز الحالي هو الوحيد النشط.
  update public.employee_devices
  set status = 'replaced',
      revoked_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb)
               || jsonb_build_object('replacedByDevice', NEW.id)
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and status = 'active';
  return NEW;
end;
$$;



create or replace function public.trg_fn_public_holiday_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp record;
begin
  if NEW.is_active is not true then
    return NEW;
  end if;

  for v_emp in
    select e.id as employee_id, p.id as user_id
    from public.employees e
    join public.profiles p on p.employee_id = e.id and p.status = 'active'
    where e.is_active = true and e.status = 'active'
  loop
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, entity_type, entity_id, metadata, created_by
    ) values (
      v_emp.user_id, v_emp.employee_id,
      'عطلة رسمية: ' || NEW.name,
      'تم الإعلان عن عطلة رسمية «' || NEW.name || '» بتاريخ ' || NEW.holiday_date::text || '.',
      'announcement', 'normal',
      'public_holiday', NEW.id,
      jsonb_build_object('kind', 'public_holiday_announced', 'holidayName', NEW.name, 'holidayDate', NEW.holiday_date),
      coalesce(NEW.created_by, v_emp.user_id)
    );
  end loop;

  return NEW;
end;
$$;



create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal',
        'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), v_user_id)
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal',
        'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), v_user_id)
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;



create or replace function public.trg_request_step_activated_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req public.requests;
begin
  if new.status <> 'active' or old.status = 'active' or new.assignee_employee_id is null then
    return new;
  end if;

  select * into v_req from public.requests where id = new.request_id;
  if v_req.id is null or new.assignee_employee_id = v_req.employee_id then
    return new;
  end if;

  if not exists (
    select 1 from public.notifications n
    where n.recipient_employee_id = new.assignee_employee_id
      and n.entity_type = 'request'
      and n.entity_id = new.request_id
      and n.metadata->>'eventKey' = 'step-active:' || new.id::text
  ) then
    perform public.notify_employee(
      new.assignee_employee_id,
      'طلب بانتظار مراجعتك',
      format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object(
        'kind', 'request_approval_needed',
        'eventKey', 'step-active:' || new.id::text,
        'requestType', v_req.request_type,
        'stepOrder', new.step_order
      )
    );
  end if;

  return new;
end;
$$;



create or replace function public.unlock_attendance_period(p_period_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.attendance_periods; v_end date;
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.period.unlock')) then raise exception 'FORBIDDEN'; end if;
 if length(trim(p_reason))<8 then raise exception 'REASON_REQUIRED'; end if;
 select * into strict v from public.attendance_periods where id=p_period_id for update; v_end:=(v.period_month+interval '1 month - 1 day')::date;
 update public.attendance_periods set status='unlocked',unlocked_at=now(),unlocked_by=public.current_employee_id(),unlock_reason=trim(p_reason),updated_at=now() where id=p_period_id;
 update public.attendance_daily a set is_finalized=false,updated_at=now() from public.employees e where e.id=a.employee_id and a.work_date between v.period_month and v_end and (v.branch_id is null or e.branch_id=v.branch_id);
 perform public.log_audit_event('attendance.period.unlocked','security','warning','attendance_periods',p_period_id,'إعادة فتح فترة حضور',p_reason,jsonb_build_object('period',v.period_month));
end $$;



create or replace function public.update_employee_admin(
  p_employee_id uuid,
  p_changes jsonb,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_has_sensitive boolean;
  v_has_basic boolean;
  v_employee public.employees;
  v_updates text[] := '{}';
  v_basic_fields text[] := array['fullNameAr','fullNameEn','phoneE164','photoUrl'];
  v_sensitive_fields text[] := array[
    'departmentId','teamId','branchId','workSiteId',
    'jobTitleId','positionId','gradeId','employmentTypeId',
    'hireDate','contractEnd','probationEnd','status',
    'jobTitleName','gradeName'
  ];
  v_key text;
  v_has_sensitive_change boolean := false;
  v_old_snapshot jsonb;
  v_jt_name text;
  v_jt_id uuid;
  v_jt_code text;
  v_gr_name text;
  v_gr_id uuid;
  v_gr_code text;
begin
  if v_actor_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_changes is null or p_changes = '{}'::jsonb then
    raise exception 'no_changes_provided' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'change_reason_required' using errcode = '22023';
  end if;

  v_has_sensitive := public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive');
  v_has_basic := v_has_sensitive
    or public.has_permission('people.employee.update_basic');

  if not v_has_basic then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;

  if not public.can_access_employee(p_employee_id, 'people.employee.update_basic')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_changes) loop
    if v_key = any(v_sensitive_fields) then
      v_has_sensitive_change := true;
    end if;
    if v_key <> all(v_basic_fields) and v_key <> all(v_sensitive_fields) then
      raise exception 'unknown field: %', v_key using errcode = '22023';
    end if;
  end loop;

  if v_has_sensitive_change and not v_has_sensitive then
    raise exception 'sensitive_field_requires_elevated_permission' using errcode = '42501';
  end if;

  -- P0-FIX: طبّع الهاتف إلى E.164 قبل أي منطق آخر يعتمد عليه (فحص تكرار /
  -- UPDATE). بدون هذه الخطوة يفشل identifier-sign-in عند محاولة الدخول لاحقاً
  -- لأنه يبحث بالصيغة المُطبّعة بينما المخزن بقي بصيغة محلية.
  if p_changes ? 'phoneE164' and nullif(trim(p_changes->>'phoneE164'), '') is not null then
    p_changes := jsonb_set(
      p_changes, '{phoneE164}',
      to_jsonb(public.normalize_phone_e164(trim(p_changes->>'phoneE164'))),
      true
    );
  end if;

  -- حل المسمى الوظيفي من النص إلى UUID
  if p_changes ? 'jobTitleName' then
    v_jt_name := nullif(trim(p_changes->>'jobTitleName'), '');
    if v_jt_name is not null then
      select id into v_jt_id
      from public.job_titles
      where lower(name) = lower(v_jt_name) and is_active = true
      limit 1;

      if v_jt_id is null then
        v_jt_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_titles (code, name, is_active, created_by)
        values (v_jt_code, v_jt_name, true, v_actor_id)
        on conflict ((lower(name))) where is_active = true
        do update set updated_at = now()
        returning id into v_jt_id;
      end if;

      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', v_jt_id);
      end if;
    else
      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', null);
      end if;
    end if;
    p_changes := p_changes - 'jobTitleName';
  end if;

  -- حل الدرجة الوظيفية من النص إلى UUID
  if p_changes ? 'gradeName' then
    v_gr_name := nullif(trim(p_changes->>'gradeName'), '');
    if v_gr_name is not null then
      select id into v_gr_id
      from public.job_grades
      where lower(name) = lower(v_gr_name) and is_active = true
      limit 1;

      if v_gr_id is null then
        v_gr_code := 'GR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_grades (code, name, level, is_active, created_by)
        values (v_gr_code, v_gr_name, 1, true, v_actor_id)
        returning id into v_gr_id;
      end if;

      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', v_gr_id);
      end if;
    else
      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', null);
      end if;
    end if;
    p_changes := p_changes - 'gradeName';
  end if;

  -- تحميل الموظف مع قفل
  select * into v_employee
  from public.employees
  where id = p_employee_id and is_deleted = false
  for update;

  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  v_old_snapshot := jsonb_build_object(
    'fullNameAr', v_employee.full_name_ar,
    'fullNameEn', v_employee.full_name_en,
    'phoneE164', v_employee.phone_e164,
    'photoUrl', v_employee.photo_url,
    'departmentId', v_employee.department_id,
    'teamId', v_employee.team_id,
    'branchId', v_employee.branch_id,
    'workSiteId', v_employee.work_site_id,
    'jobTitleId', v_employee.job_title_id,
    'positionId', v_employee.position_id,
    'gradeId', v_employee.grade_id,
    'employmentTypeId', v_employee.employment_type_id,
    'hireDate', v_employee.hire_date,
    'contractEnd', v_employee.contract_end,
    'probationEnd', v_employee.probation_end,
    'status', v_employee.status
  );

  update public.employees set
    full_name_ar = case when p_changes ? 'fullNameAr'
      then trim(p_changes->>'fullNameAr') else full_name_ar end,
    full_name_en = case when p_changes ? 'fullNameEn'
      then nullif(trim(p_changes->>'fullNameEn'), '') else full_name_en end,
    phone_e164 = case when p_changes ? 'phoneE164'
      then nullif(trim(p_changes->>'phoneE164'), '') else phone_e164 end,
    photo_url = case when p_changes ? 'photoUrl'
      then nullif(trim(p_changes->>'photoUrl'), '') else photo_url end,
    department_id = case when p_changes ? 'departmentId'
      then (p_changes->>'departmentId')::uuid else department_id end,
    team_id = case when p_changes ? 'teamId'
      then (p_changes->>'teamId')::uuid else team_id end,
    branch_id = case when p_changes ? 'branchId'
      then (p_changes->>'branchId')::uuid else branch_id end,
    work_site_id = case when p_changes ? 'workSiteId'
      then (p_changes->>'workSiteId')::uuid else work_site_id end,
    job_title_id = case when p_changes ? 'jobTitleId'
      then (p_changes->>'jobTitleId')::uuid else job_title_id end,
    position_id = case when p_changes ? 'positionId'
      then (p_changes->>'positionId')::uuid else position_id end,
    grade_id = case when p_changes ? 'gradeId'
      then (p_changes->>'gradeId')::uuid else grade_id end,
    employment_type_id = case when p_changes ? 'employmentTypeId'
      then (p_changes->>'employmentTypeId')::uuid else employment_type_id end,
    hire_date = case when p_changes ? 'hireDate'
      then (p_changes->>'hireDate')::date else hire_date end,
    contract_end = case when p_changes ? 'contractEnd'
      then (p_changes->>'contractEnd')::date else contract_end end,
    probation_end = case when p_changes ? 'probationEnd'
      then (p_changes->>'probationEnd')::date else probation_end end,
    status = case when p_changes ? 'status'
      then (p_changes->>'status') else status end,
    updated_at = now()
  where id = p_employee_id;

  -- فحص تكرار الهاتف بعد التحديث (يستخدم القيمة المُطبّعة المخزّنة حديثاً)
  if p_changes ? 'phoneE164' and (p_changes->>'phoneE164') is not null then
    if exists (
      select 1 from public.employees
      where phone_e164 = trim(p_changes->>'phoneE164')
        and id <> p_employee_id
        and is_active = true and is_deleted = false
    ) then
      raise exception 'phone number already belongs to an active employee' using errcode = '23505';
    end if;
  end if;

  -- التدقيق (نفس توقيع النسخة الأصلية — بدون تعديل)
  perform public.log_audit_event(
    'employee_updated', 'people', 'info', 'employees', p_employee_id,
    'تعديل بيانات الموظف',
    trim(p_reason),
    jsonb_build_object('before', v_old_snapshot, 'after', p_changes)
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'updatedFields', (select jsonb_agg(k) from jsonb_object_keys(p_changes) as k),
    'updatedAt', now()
  );
end;
$$;



CREATE OR REPLACE FUNCTION public.update_release_policy(p_platform text, p_environment text, p_latest_version text, p_latest_build integer, p_min_supported_version text, p_min_supported_build integer, p_force_update boolean, p_maintenance_enabled boolean, p_maintenance_message_ar text, p_update_message_ar text, p_store_url text, p_rollout_percent integer DEFAULT 100, p_reason text DEFAULT NULL::text)
 RETURNS app_release_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.app_release_policies;
begin
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'سياسة الإصدار مرفوضة' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  if p_latest_build < p_min_supported_build then raise exception 'latest build must be >= minimum build' using errcode='22023'; end if;
  insert into public.app_release_policies(
    platform,environment,latest_version,latest_build,min_supported_version,min_supported_build,
    force_update,maintenance_enabled,maintenance_message_ar,update_message_ar,store_url,
    rollout_percent,created_by,updated_by
  ) values (
    p_platform,p_environment,p_latest_version,p_latest_build,p_min_supported_version,p_min_supported_build,
    coalesce(p_force_update,false),coalesce(p_maintenance_enabled,false),p_maintenance_message_ar,
    p_update_message_ar,p_store_url,greatest(0,least(coalesce(p_rollout_percent,100),100)),auth.uid(),auth.uid()
  )
  on conflict (platform,environment) do update set
    latest_version=excluded.latest_version,latest_build=excluded.latest_build,
    min_supported_version=excluded.min_supported_version,min_supported_build=excluded.min_supported_build,
    force_update=excluded.force_update,maintenance_enabled=excluded.maintenance_enabled,
    maintenance_message_ar=excluded.maintenance_message_ar,update_message_ar=excluded.update_message_ar,
    store_url=excluded.store_url,rollout_percent=excluded.rollout_percent,updated_by=auth.uid(),updated_at=now()
  returning * into v_row;
  perform public.log_audit_event('release.policy.updated','system','warning','app_release_policies',v_row.id,
    'تحديث سياسة إصدار',p_reason,jsonb_build_object('platform',p_platform,'environment',p_environment,'latestBuild',p_latest_build,'minimumBuild',p_min_supported_build,'maintenance',p_maintenance_enabled));
  return v_row;
end;
$function$;



CREATE OR REPLACE FUNCTION public.update_system_settings(p_updates jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_item jsonb;
  v_key text;
  v_val text;
  v_updated integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('settings.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'object' then
    raise exception 'التحديثات يجب أن تكون كائن JSON' using errcode='22023';
  end if;

  for v_item in select * from jsonb_each(p_updates)
  loop
    v_key := v_item ->> 'key';
    v_val := (v_item -> 'value')::text;
    update public.system_settings
       set value = v_val,
           updated_at = now()
     where key = v_key
       and is_editable = true
       and is_secret = false;
    if found then v_updated := v_updated + 1; end if;
  end loop;

  if v_updated > 0 then
    perform public.log_audit_event(
      'settings.updated', 'system', 'info',
      'system_settings', null, 'تحديث إعدادات النظام', null,
      jsonb_build_object('updatedKeys', v_updated));
  end if;

  return v_updated;
end $function$;



CREATE OR REPLACE FUNCTION public.upsert_department_admin(p_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_parent_id uuid, p_manager_id uuid, p_code text, p_name text, p_name_en text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.department.manage') or public.has_permission('organization.unit.manage')) then
    raise exception 'إدارة الأقسام مرفوضة' using errcode = '42501';
  end if;
  if nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'كود واسم القسم مطلوبان' using errcode = '22023';
  end if;
  if p_legal_entity_id is null then
    raise exception 'الكيان القانوني مطلوب' using errcode = '22023';
  end if;
  if p_id is not null and p_parent_id = p_id then
    raise exception 'القسم لا يتبع نفسه' using errcode = '22023';
  end if;

  if p_id is not null and p_parent_id is not null then
    with recursive descendants as (
      select d.id from public.departments d where d.parent_id = p_id
      union all
      select d.id from public.departments d join descendants x on d.parent_id = x.id
    )
    select exists(select 1 from descendants where id = p_parent_id) into v_cycle;
    if v_cycle then
      raise exception 'دورة في تسلسل الأقسام' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.departments(
      legal_entity_id, branch_id, parent_id, manager_id,
      code, name, name_en, is_active, created_by
    ) values (
      p_legal_entity_id, p_branch_id, p_parent_id, p_manager_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.departments set
      legal_entity_id = p_legal_entity_id,
      branch_id = p_branch_id,
      parent_id = p_parent_id,
      manager_id = p_manager_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'القسم غير موجود' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$function$;



CREATE OR REPLACE FUNCTION public.upsert_knowledge_category(p_id uuid DEFAULT NULL::uuid, p_slug text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('knowledge.manage')) then
    raise exception 'FORBIDDEN';
  end if;
  if p_slug is null or p_name is null then
    raise exception 'المعرّف والاسم مطلوبان';
  end if;

  if p_id is null then
    insert into public.knowledge_categories (slug, name, description, is_active, created_by)
    values (lower(btrim(p_slug)), trim(p_name), nullif(btrim(coalesce(p_description,'')),''), p_is_active, auth.uid())
    returning id into v_id;
  else
    update public.knowledge_categories
       set slug = lower(btrim(p_slug)), name = trim(p_name),
           description = nullif(btrim(coalesce(p_description,'')),''),
           is_active = p_is_active
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'NOT_FOUND';
    end if;
  end if;
  return v_id;
end $function$;



CREATE OR REPLACE FUNCTION public.upsert_my_daily_report(p_report_date date, p_achievements text, p_blockers text DEFAULT NULL::text, p_tomorrow_plan text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_employee_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_report_date > (now() at time zone 'Africa/Cairo')::date then
    raise exception 'التقرير اليومي المستقبلي غير مسموح' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_achievements, ''))) < 3 then
    raise exception 'الإنجازات مطلوبة' using errcode = '22023';
  end if;

  select id into v_id
  from public.daily_reports
  where employee_id = v_employee_id and report_date = p_report_date
  order by created_at desc limit 1;

  if v_id is null then
    insert into public.daily_reports (
      employee_id, report_date, achievements, blockers, tomorrow_plan, created_by
    ) values (
      v_employee_id, p_report_date, trim(p_achievements), nullif(trim(coalesce(p_blockers,'')),''),
      nullif(trim(coalesce(p_tomorrow_plan,'')),''), auth.uid()
    ) returning id into v_id;
  else
    update public.daily_reports
    set achievements = trim(p_achievements),
        blockers = nullif(trim(coalesce(p_blockers,'')),''),
        tomorrow_plan = nullif(trim(coalesce(p_tomorrow_plan,'')),''),
        updated_at = now()
    where id = v_id and reviewed_by is null;

    if not found then
      raise exception 'التقرير المُراجَع لا يُعدَّل' using errcode = '42501';
    end if;
  end if;

  return v_id;
end;
$function$;



create or replace function public.upsert_my_push_token(p_fcm_token text, p_platform text default 'android')
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(trim(coalesce(p_fcm_token,'')))<16 then raise exception 'invalid fcm token' using errcode='22023'; end if;
  if p_platform is not null and p_platform not in ('android','ios','web') then raise exception 'invalid platform' using errcode='22023'; end if;

  insert into public.push_subscriptions(user_id,endpoint,p256dh_key,auth_key,fcm_token,platform,is_active,last_used_at,created_by)
  values(auth.uid(),'fcm://'||p_fcm_token,'-','-',p_fcm_token,coalesce(p_platform,'android'),true,now(),auth.uid())
  on conflict (fcm_token) do update
    set user_id=excluded.user_id, is_active=true, platform=excluded.platform,
        last_used_at=now(), updated_at=now();
end;
$$;



CREATE OR REPLACE FUNCTION public.upsert_position_admin(p_id uuid, p_department_id uuid, p_team_id uuid, p_job_title_id uuid, p_grade_id uuid, p_reports_to_id uuid, p_code text, p_name text, p_name_en text DEFAULT NULL::text, p_headcount integer DEFAULT 1, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.position.manage')) then
    raise exception 'إدارة المناصب مرفوضة' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'القسم وكود واسم المنصب مطلوبة' using errcode = '22023';
  end if;
  if coalesce(p_headcount, 0) < 0 then raise exception 'لا يمكن أن يكون العدد سالباً' using errcode = '22023'; end if;
  if p_id is not null and p_reports_to_id = p_id then raise exception 'لا يمكن أن يتبع المنصب نفسه' using errcode = '22023'; end if;

  if p_id is not null and p_reports_to_id is not null then
    with recursive descendants as (
      select p.id from public.positions p where p.reports_to_position_id = p_id
      union all
      select p.id from public.positions p join descendants x on p.reports_to_position_id = x.id
    )
    select exists(select 1 from descendants where id = p_reports_to_id) into v_cycle;
    if v_cycle then raise exception 'تم رصد دورة في تسلسل المناصب' using errcode = '22023'; end if;
  end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams t where t.id = p_team_id and t.department_id = p_department_id
  ) then
    raise exception 'الفريق لا يتبع القسم المختار' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.positions(
      department_id, team_id, job_title_id, job_grade_id, reports_to_position_id,
      code, name, name_en, headcount, is_active, created_by
    ) values (
      p_department_id, p_team_id, p_job_title_id, p_grade_id, p_reports_to_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_headcount, 1), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.positions set
      department_id = p_department_id,
      team_id = p_team_id,
      job_title_id = p_job_title_id,
      job_grade_id = p_grade_id,
      reports_to_position_id = p_reports_to_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      headcount = coalesce(p_headcount, headcount),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'المنصب غير موجود' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$function$;



create or replace function public.validate_password_strength(p_password text)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_issues text[] := '{}';
begin
  if p_password is null or length(p_password) < 12 then
    v_issues := array_append(v_issues, 'يجب أن تكون 12 حرفًا على الأقل');
  end if;
  if length(p_password) > 72 then
    v_issues := array_append(v_issues, 'يجب ألا تتجاوز 72 حرفًا');
  end if;
  if p_password !~ '[A-Z]' then
    v_issues := array_append(v_issues, 'حرف كبير واحد على الأقل (A-Z)');
  end if;
  if p_password !~ '[a-z]' then
    v_issues := array_append(v_issues, 'حرف صغير واحد على الأقل (a-z)');
  end if;
  if p_password !~ '[0-9]' then
    v_issues := array_append(v_issues, 'رقم واحد على الأقل (0-9)');
  end if;
  if p_password !~ '[!@#$%^&*()_\-+=[\]{};''":\\|,.<>/?`~]' then
    v_issues := array_append(v_issues, 'رمز خاص واحد على الأقل (!@#$...)');
  end if;
  if p_password ~ '(.)\1{4,}' then
    v_issues := array_append(v_issues, 'تكرار مفرط لنفس الحرف (5+ متتالية)');
  end if;

  return jsonb_build_object(
    'valid', cardinality(v_issues) = 0,
    'issues', to_jsonb(v_issues)
  );
end $$;



create or replace function public.verify_critical_cron_jobs()
 returns table(jobname text, active boolean, last_run timestamptz, last_run_status text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_missing text[];
  v_has_cron boolean;
  v_dispatch_last_success timestamptz;
  v_outbox_oldest_pending timestamptz;
  v_failed_push_7d bigint;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and not public.current_is_full_access()
     and (auth.jwt() ->> 'role') is distinct from 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select exists (
    select 1
    from pg_available_extensions
    where name = 'pg_cron' and installed_version is not null
  ) into v_has_cron;

  if not v_has_cron then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_pg_cron_unavailable', 'P0',
      'pg_cron غير مفعّل في بيئة التشغيل',
      'لا يمكن جدولة المهام الحرجة حتى تفعيل pg_cron أو توثيق بديل خارجي معتمد.',
      'cron', jsonb_build_object('category', 'cron_health'), 'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          occurrences = public.system_alerts.occurrences + 1;
    return;
  end if;

  select array_agg(j.expected_jobname order by j.expected_jobname)
    into v_missing
  from (
    values
      ('hr_request_sla'),
      ('hr_leave_accrual'),
      ('hr_scheduled_reports'),
      ('hr_notification_dispatch'),
      ('hr_integration_outbox'),
      ('hr_retention_cleanup_storage'),
      ('hr_scheduled_report_runner')
  ) as j(expected_jobname)
  where not exists (
    select 1
    from cron.job cj
    where cj.jobname = j.expected_jobname
      and cj.active
  );

  if coalesce(cardinality(v_missing), 0) > 0 then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_critical_jobs_missing', 'P0',
      'مهام cron حرجة غير مجدولة أو غير نشطة',
      'المهام المفقودة: ' || array_to_string(v_missing, ', '),
      'cron',
      jsonb_build_object('category', 'cron_health', 'missingJobs', to_jsonb(v_missing)),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          detail = excluded.detail,
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'cron_critical_jobs_missing' and status = 'open';
  end if;

  -- ── 0467: تأخر ساحب الإشعارات (يعمل كل دقيقة) ──────────────────────────
  select max(d.start_time)
    into v_dispatch_last_success
  from cron.job cj
  join cron.job_run_details d on d.jobid = cj.jobid
  where cj.jobname = 'hr_notification_dispatch'
    and d.status = 'succeeded';

  if v_dispatch_last_success is not null
       and v_dispatch_last_success < now() - interval '10 minutes' then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'notification_dispatch_stalled', 'P1',
      'ساحب الإشعارات متوقف عن النجاح',
      'لم يسجّل hr_notification_dispatch أي تشغيل ناجح خلال آخر 10 دقائق؛ إشعارات الطابور قد تتأخر أو تتراكم.',
      'cron',
      jsonb_build_object(
        'category', 'queue_health',
        'lastSuccessAt', to_char(v_dispatch_last_success, 'YYYY-MM-DD"T"HH24:MI:SSOF')
      ),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'notification_dispatch_stalled' and status = 'open';
  end if;

  -- ── 0467: تأخر طابور التكاملات (العامل يعمل كل 5 دقائق) ────────────────
  select min(o.created_at)
    into v_outbox_oldest_pending
  from public.integration_outbox o
  where o.status in ('pending', 'retry');

  if v_outbox_oldest_pending is not null
       and v_outbox_oldest_pending < now() - interval '15 minutes' then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'integration_outbox_lag', 'P1',
      'طابور التكاملات متأخر',
      'توجد صفوف integration_outbox بانتظار المعالجة منذ أكثر من 15 دقيقة — تحقق من worker أو نقطة الاستقبال.',
      'queue',
      jsonb_build_object(
        'category', 'queue_health',
        'oldestPendingAt', to_char(v_outbox_oldest_pending, 'YYYY-MM-DD"T"HH24:MI:SSOF')
      ),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'integration_outbox_lag' and status = 'open';
  end if;

  -- ── 0473: فيض إشعارات push الفاشلة خلال أسبوع (P1 بدل P2 المرفوض بالقيد) ─
  select count(*)
    into v_failed_push_7d
  from public.notification_jobs j
  where j.status = 'failed'
    and j.channel = 'push'
    and j.created_at > now() - interval '7 days';

  if v_failed_push_7d >= 50 then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'notification_push_failures_spike', 'P1',
      'تراكم إشعارات push فاشلة',
      'فشل ' || v_failed_push_7d::text || ' إشعار push خلال آخر 7 أيام — غالباً غياب توكنات FCM صالحة أو عطل في التسليم.',
      'notification',
      jsonb_build_object('category', 'queue_health', 'failedCount7d', v_failed_push_7d),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          detail = excluded.detail,
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'notification_push_failures_spike' and status = 'open';
  end if;

  return query
  select
    cj.jobname::text,
    cj.active,
    cr.start_time,
    cr.status::text
  from cron.job cj
  left join lateral (
    select d.start_time, d.status
    from cron.job_run_details d
    where d.jobid = cj.jobid
    order by d.start_time desc
    limit 1
  ) cr on true
  where cj.jobname like 'hr_%'
  order by cj.jobname;
end;
$function$;



CREATE OR REPLACE FUNCTION public.waive_employee_penalty(p_penalty_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'لا يوجد ملف موظف لصاحب الطلب' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;

  update public.employee_penalties
     set status = 'waived', waived_by = v_me, waived_at = now(), waive_reason = p_reason,
         updated_at = now()
   where id = p_penalty_id
     and status in ('issued', 'deducted')
  returning * into v_row;

  if v_row.id is null then raise exception 'الجزاء غير موجود أو غير قابل للإسقاط' using errcode='P0002'; end if;

  perform public.log_audit_event(
    'penalty.waived', 'financial', 'info',
    'employee_penalties', v_row.id, 'إسقاط مخالفة مالية', null,
    jsonb_build_object('employeeId', v_row.employee_id, 'amount', v_row.amount));

  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'waivedAt', v_row.waived_at);
end $function$;



create or replace function public.withdraw_escalation(
  p_request_id uuid,
  p_reason text
)
returns public.requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_req public.requests;
begin
  if not (public.current_is_full_access()
          or public.has_permission('requests.request.override')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.requests
    set workflow_status = 'awaiting_manager', escalated_at = null, updated_at = now(),
        payload = payload || jsonb_build_object('escalationWithdrawn',
          jsonb_build_object('reason', p_reason, 'at', now()))
    where id = p_request_id and status = 'pending'
    returning * into v_req;
  if not found then raise exception 'request not found or not pending' using errcode = 'P0002'; end if;

  insert into public.request_actions(request_id, actor_employee_id, action, comment)
  values(p_request_id, public.current_employee_id(), 'comment',
    coalesce(p_reason, 'سحب التصعيد'));

  perform public.log_audit_event('request.escalation.withdrawn', 'workflow', 'info',
    'requests', p_request_id, 'سحب تصعيد الطلب', p_reason, '{}'::jsonb);
  return v_req;
end $$;
