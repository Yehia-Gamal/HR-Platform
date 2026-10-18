-- =====================================================================
-- Migration 0698: Fix Attendance Statement for Convoys, Missions and Leaves
-- Description:
-- 1. Ensure public.requests with type 'convoy', 'mission', 'fundraising'
--    are recognized as covered/attended in the entire statement builder pipeline.
-- 2. Ensure leave types like 'بدل راحة أسبوعية' (weekly_rest_comp) that don't
--    contain the word 'إجازة' have hasLeave=true and are not marked absent.
-- 3. Enhance tg_assignment_day_present to update existing absent rows in
--    attendance_daily when an assignment request is approved.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Rebuild _build_attendance_statement_v186
-- ─────────────────────────────────────────────────────────────────────
create or replace function public._build_attendance_statement_v186(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
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
  v_is_absent boolean;
  v_is_holiday boolean;
  v_has_late_permit boolean;
  v_has_early_permit boolean;
  v_is_leave boolean;
  v_is_mission boolean;
  v_is_convoy_fundi boolean;
  v_is_exempt boolean;
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
  v_total_required_minutes integer := 0;
  -- مساعد لحل التكليف
  v_asgn_kind text;
  v_asgn_title text;
begin
  -- بيانات الموظف
  select e.id, e.employee_code, e.full_name_ar, e.full_name_en,
    e.hire_date, e.birth_date, e.is_attendance_exempt, e.photo_url,
    coalesce(d.name, '') as department_name,
    coalesce(jt.name, jt.name_en, '') as job_title,
    coalesce(b.name, '') as branch_name,
    coalesce(mgr.full_name_ar, '') as manager_name
  into v_emp
  from public.employees e
  left join public.departments d on d.id = e.department_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.branches b on b.id = e.branch_id
  left join lateral (
    select m.full_name_ar
    from public.manager_relations mr
    join public.employees m on m.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
    order by case mr.relation_type
      when 'primary' then 1 when 'functional' then 2 else 3 end
    limit 1
  ) mgr on true
  where e.id = p_employee_id;

  if v_emp.id is null then
    return null;
  end if;

  v_is_exempt := coalesce(v_emp.is_attendance_exempt, false) or public.is_employee_attendance_exempt(p_employee_id);

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month - 1 day')::date;

  v_day := v_start;
  while v_day <= v_end loop
    v_total_days := v_total_days + 1;
    v_is_absent := false;
    v_is_holiday := false;
    v_has_late_permit := false;
    v_has_early_permit := false;
    v_is_leave := false;
    v_is_mission := false;
    v_is_convoy_fundi := false;
    v_asgn_kind := null;
    v_asgn_title := null;

    -- سجل الحضور لليوم
    select * into v_row
    from public.attendance_daily
    where employee_id = p_employee_id and work_date = v_day;

    -- الوردية
    select s.name, s.start_time, s.end_time, s.crosses_midnight, coalesce(s.break_minutes, 0)
    into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses, v_shift_break
    from public.shifts s
    where s.id = v_row.shift_id;

    if v_shift_name is null then
      select s.name, s.start_time, s.end_time, s.crosses_midnight, coalesce(s.break_minutes, 0)
      into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses, v_shift_break
      from public.shifts s
      where s.is_active = true
      order by s.updated_at desc nulls last
      limit 1;
    end if;

    -- حساب الساعات
    if v_shift_start is not null and v_shift_end is not null then
      v_scheduled_minutes := case
        when v_shift_crosses then
          (extract(hour from v_shift_end)*60 + extract(minute from v_shift_end) + 1440)
          - (extract(hour from v_shift_start)*60 + extract(minute from v_shift_start))
          - v_shift_break
        else
          (extract(hour from v_shift_end)*60 + extract(minute from v_shift_end))
          - (extract(hour from v_shift_start)*60 + extract(minute from v_shift_start))
          - v_shift_break
      end;
      v_required_hours := round(v_scheduled_minutes / 60.0, 1);
    else
      v_scheduled_minutes := 480;
      v_required_hours := 8.0;
    end if;

    v_work_hours := round(coalesce(v_row.work_minutes, 0) / 60.0, 1);

    -- 1) الجمعة = راحة أسبوعية
    if extract(isodow from v_day) = 5 then
      v_status := 'راحة أسبوعية';
      v_rest_days := v_rest_days + 1;
      v_required_hours := 0;

    -- 2) عطلة رسمية؟ قراءة من public.public_holidays
    elsif exists (
      select 1 from public.public_holidays h
      where coalesce(h.is_active, true)
        and v_day between h.holiday_date and coalesce(h.end_date, h.holiday_date)
    ) then
      v_status := 'عطلة رسمية';
      v_holiday_days := v_holiday_days + 1;
      v_is_holiday := true;
      v_required_hours := 0;

    -- 3) يوم عمل مجدول
    else
      v_scheduled_days := v_scheduled_days + 1;
      v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;

      -- فحص التكليفات / المأموريات / القوافل من work_assignments و requests و missions
      select
        case
          when wa.assignment_type is not null then wa.assignment_type
          when r.request_type in ('convoy', 'field_convoy') or r.payload->>'missionType' = 'convoy' then 'CONVOY'
          when r.request_type in ('fundraising', 'fandy', 'fundi') or r.payload->>'missionType' = 'fundraising' then 'FUNDRAISING'
          else 'MISSION'
        end,
        coalesce(nullif(wa.title, ''), nullif(r.title, ''), nullif(m.purpose, ''), nullif(r.payload->>'location', ''))
      into v_asgn_kind, v_asgn_title
      from (select 1) _dummy
      left join lateral (
        select wa.assignment_type, wa.title
        from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id
          and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at at time zone 'Africa/Cairo')::date
        order by wa.start_at desc limit 1
      ) wa on true
      left join lateral (
        select r.request_type, r.title, r.payload
        from public.requests r
        where r.employee_id = p_employee_id
          and r.status not in ('rejected', 'cancelled')
          and (
            r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy',
                               'fundraising', 'fandy', 'fundi', 'remote_work')
            or coalesce(r.payload->>'missionType', r.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy', 'fundi')
          )
          and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date)
                        and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date)
        order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc limit 1
      ) r on true
      left join lateral (
        select m.purpose
        from public.missions m
        join public.requests rm on rm.id = m.request_id
        where m.employee_id = p_employee_id
          and rm.status not in ('rejected', 'cancelled')
          and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                        and (m.end_at at time zone 'Africa/Cairo')::date
        order by m.start_at desc limit 1
      ) m on true
      where wa.assignment_type is not null or r.request_type is not null or m.purpose is not null
      limit 1;

      -- أ) تكليف عمل (مأمورية أو قافلة أو فاندي)
      if v_asgn_kind is not null then
        if v_asgn_kind = 'CONVOY' then
          v_status := 'قافلة';
          v_convoy_fundi_days := v_convoy_fundi_days + 1;
          v_is_convoy_fundi := true;
        elsif v_asgn_kind = 'FUNDRAISING' then
          v_status := 'فاندي';
          v_convoy_fundi_days := v_convoy_fundi_days + 1;
          v_is_convoy_fundi := true;
        else
          v_status := 'مأمورية عمل';
          v_mission_days := v_mission_days + 1;
          v_is_mission := true;
        end if;
        v_present_days := v_present_days + 1;
        v_is_absent := false;

      -- ب) إجازة معتمدة (من leave_requests عبر requests أو requests مباشرة أو حضور مسجل كإجازة)
      elsif v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id
          and r.status not in ('rejected', 'cancelled')
          and v_day between lr.start_date and lr.end_date
      ) or exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
          and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                        and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                     public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
      ) then
        v_is_leave := true;
        v_status := coalesce(
          (select lt.name_ar
           from public.leave_requests lr
           join public.leave_types lt on lt.id = lr.leave_type_id
           join public.requests r on r.id = lr.request_id
           where lr.employee_id = p_employee_id
             and r.status not in ('rejected', 'cancelled')
             and v_day between lr.start_date and lr.end_date
           order by case when r.status = 'approved' then 1 else 2 end, lr.start_date desc
           limit 1),
          (select case r.payload->>'leaveType'
                    when 'weekly_rest_comp' then 'بدل راحة أسبوعية'
                    when 'annual' then 'إجازة اعتيادية'
                    when 'casual' then 'إجازة عارضة (طارئة)'
                    when 'sick' then 'إجازة مرضية'
                    when 'unpaid' then 'إجازة بدون أجر'
                    else coalesce(
                      (select lt.name_ar from public.leave_types lt where lt.code = (r.payload->>'leaveType') limit 1),
                      r.title,
                      'إجازة معتمدة'
                    )
                  end
           from public.requests r
           where r.employee_id = p_employee_id
             and r.status not in ('rejected', 'cancelled')
             and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
             and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                        public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
           order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
           limit 1),
          'إجازة معتمدة'
        );
        v_leave_days := v_leave_days + 1;
        v_is_absent := false;

      -- ج) حضور فعلي أو مسجل present في attendance_daily
      elsif v_row.first_check_in is not null or v_row.status = 'present' then
        v_status := 'حاضر';
        v_present_days := v_present_days + 1;
        v_is_absent := false;

      -- د) لم يحضر وهو يوم عمل
      else
        if v_day > (now() at time zone 'Africa/Cairo')::date then
          v_status := 'مستقبلي';
        else
          v_status := 'غائب دون إذن';
          v_absent_days := v_absent_days + 1;
          v_is_absent := true;
        end if;
      end if;
    end if;

    -- 4) فحص أذونات الحضور والتأخير
    v_has_late_permit := exists(
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          r.request_type in ('late_permit', 'permission', 'errand', 'late_excuse')
          or (r.request_type = 'permit' and coalesce(r.payload->>'permitKind', 'late_arrival') = 'late_arrival')
        )
        and coalesce(
          public.try_cast_date(r.payload->>'permitDate'),
          public.try_cast_date(r.payload->>'date'),
          public.try_cast_date(r.payload->>'startDate'),
          public.try_cast_date(r.payload->>'workDate'),
          r.created_at::date
        ) = v_day
    ) or exists(
      select 1 from public.attendance_permits p
      where p.employee_id = p_employee_id and p.permit_date = v_day
        and p.status in ('approved', 'pending') and p.kind = 'arrival'
    );

    v_has_early_permit := exists(
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          r.request_type in ('early_permit')
          or (r.request_type = 'permit' and coalesce(r.payload->>'permitKind', '') = 'early_departure')
        )
        and coalesce(
          public.try_cast_date(r.payload->>'permitDate'),
          public.try_cast_date(r.payload->>'date'),
          public.try_cast_date(r.payload->>'startDate'),
          public.try_cast_date(r.payload->>'workDate'),
          r.created_at::date
        ) = v_day
    ) or exists(
      select 1 from public.attendance_permits p
      where p.employee_id = p_employee_id and p.permit_date = v_day
        and p.status in ('approved', 'pending') and p.kind = 'departure'
    );

    if v_has_late_permit or v_has_early_permit then
      v_permit_count := v_permit_count + 1;
      if v_status in ('غائب دون إذن', 'يحتاج مراجعة') and v_has_late_permit then
        v_status := 'إذن حضور مسجل';
        if v_is_absent then
          v_is_absent := false;
          v_absent_days := greatest(0, v_absent_days - 1);
        end if;
      end if;
    end if;

    -- 5) استثناء القيادات والمعفيين إدارياً
    if v_is_exempt then
      if v_status in ('غائب دون إذن', 'يحتاج مراجعة') or v_is_absent then
        v_status := 'معفى من الحضور';
        if v_is_absent then
          v_is_absent := false;
          v_absent_days := greatest(0, v_absent_days - 1);
        end if;
        v_present_days := v_present_days + 1;
      end if;
    end if;

    -- 6) تصحيح معتمد؟
    if exists (select 1 from public.attendance_corrections c
               where c.employee_id = p_employee_id and c.work_date = v_day
                 and c.status = 'approved') then
      v_correction_count := v_correction_count + 1;
      if v_status in ('غائب دون إذن', 'يحتاج مراجعة') then
        v_status := 'تصحيح معتمد';
        if v_is_absent then
          v_is_absent := false;
          v_absent_days := greatest(0, v_absent_days - 1);
          v_present_days := v_present_days + 1;
        end if;
      end if;
    end if;

    -- 7) نسيان ختم
    if v_row.id is not null and v_row.status not in ('on_leave','holiday','weekend')
       and v_status not like '%عطلة%' and v_status not like '%راحة%'
       and not v_is_leave and not v_is_mission and not v_is_convoy_fundi
       and v_status not like '%معفى%' and v_status <> 'إذن حضور مسجل'
       and not v_has_late_permit and not v_is_exempt then
      if v_row.first_check_in is null and v_row.status <> 'absent' then
        v_missing_checkin := v_missing_checkin + 1;
      end if;
      if v_row.last_check_out is null and v_row.first_check_in is not null and not v_has_early_permit then
        v_missing_checkout := v_missing_checkout + 1;
      end if;
    end if;

    -- تراكمات الدقائق
    v_total_work_minutes := v_total_work_minutes + coalesce(v_row.work_minutes, 0);
    v_total_late_minutes := v_total_late_minutes + coalesce(v_row.late_minutes, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce(v_row.early_leave_minutes, 0);
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_row.overtime_minutes, 0);

    -- بناء صف اليوم
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
      'isAbsent', v_is_absent,
      'isOfficialHoliday', v_is_holiday,
      'hasLeave', (v_is_leave or v_status like '%إجازة%' or v_status = 'بدل راحة أسبوعية'),
      'hasLatePermit', v_has_late_permit,
      'hasEarlyPermit', v_has_early_permit,
      'hasPermit', (v_has_late_permit or v_has_early_permit),
      'hasMission', v_is_mission,
      'hasConvoyFundi', v_is_convoy_fundi,
      'missingCheckIn', (
        v_row.first_check_in is null
        and v_row.id is not null
        and v_row.status not in ('absent','on_leave','holiday','weekend')
        and v_status not like '%عطلة%' and v_status not like '%راحة%'
        and not v_is_leave and not v_is_mission and not v_is_convoy_fundi
        and v_status not like '%معفى%' and v_status <> 'إذن حضور مسجل'
        and not v_has_late_permit
        and not v_is_exempt
      ),
      'missingCheckOut', (
        v_row.last_check_out is null
        and v_row.first_check_in is not null
        and not v_has_early_permit
        and not v_is_exempt
        and not v_is_mission
        and not v_is_convoy_fundi
      ),
      'hasCorrection', exists(select 1 from public.attendance_corrections c
                              where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved'),
      'correctionNote', (select c.reason from public.attendance_corrections c
                         where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved' limit 1),
      'notes', null::text,
      'penalties', 0
    );

    v_days := v_days || v_day_obj;
    v_day := v_day + 1;
  end loop;

  return jsonb_build_object(
    'employee', jsonb_build_object(
      'id', v_emp.id,
      'code', v_emp.employee_code,
      'name', v_emp.full_name_ar,
      'nameEn', v_emp.full_name_en,
      'department', v_emp.department_name,
      'jobTitle', v_emp.job_title,
      'branch', v_emp.branch_name,
      'manager', v_emp.manager_name,
      'photoUrl', v_emp.photo_url,
      'hireDate', v_emp.hire_date
    ),
    'period', jsonb_build_object(
      'year', p_year,
      'month', p_month,
      'startDate', v_start,
      'endDate', v_end
    ),
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
      'totalWorkMinutes', v_total_work_minutes,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 1),
      'totalRequiredMinutes', v_total_required_minutes,
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 1),
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'correctionCount', v_correction_count
    ),
    'days', v_days
  );
end;
$$;

revoke all on function public._build_attendance_statement_v186(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v186(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Rebuild _build_attendance_statement_v251
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement_v251(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_now_local timestamp := now() at time zone 'Africa/Cairo';
  v_daily public.attendance_daily%rowtype;
  v_shift_id uuid;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_grace_out integer;
  v_start_override time;
  v_end_override time;
  v_shift_end_at timestamp;
  v_scheduled_minutes integer;
  v_is_scheduled boolean;
  v_is_excused boolean;
  v_is_future boolean;
  v_is_due boolean;
  v_is_open boolean;
  v_is_completed boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_status text;
  v_due_days integer := 0;
  v_upcoming_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_open_shift_days integer := 0;
  v_completed_presence_days integer := 0;
  v_completed_work_minutes integer := 0;
  v_compliance_work_minutes integer := 0;
  v_total_work_minutes integer := 0;
  v_total_required_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
  v_is_exempt boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);

  v_result := public._build_attendance_statement_v186(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_status := coalesce(v_day_obj->>'status', '');
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

    v_is_scheduled := v_status not in ('راحة أسبوعية', 'عطلة رسمية');
    v_is_excused :=
      coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      or (v_day_obj->'details'->'assignment') is not null
      or (v_day_obj->'details'->'leave') is not null
      or v_status in ('بدل راحة أسبوعية', 'قافلة', 'فاندي', 'مأمورية', 'مأمورية عمل')
      or v_status like '%إجازة%'
      or v_status like '%مأمورية%'
      or v_status like '%قافلة%'
      or v_status like '%فاندي%'
      or v_has_late_p
      or v_has_early_p
      or coalesce((v_day_obj->>'hasPermit')::boolean, false)
      or v_status in ('إذن حضور مسجل', 'معفى من الحضور')
      or v_is_exempt;

    v_is_future := v_is_scheduled and not v_is_excused and v_day > v_today;
    v_is_due := false;
    v_is_open := false;
    v_is_completed := false;
    v_missing_in := false;
    v_missing_out := false;

    select * into v_daily
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_day;

    v_shift_id := v_daily.shift_id;
    v_start_override := null;
    v_end_override := null;

    if v_shift_id is null then
      select rd.shift_id, rd.start_override, rd.end_override
        into v_shift_id, v_start_override, v_end_override
      from public.roster_days rd
      join public.work_rosters wr
        on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_day
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last, wr.created_at desc
      limit 1;
    end if;

    if v_shift_id is null then
      select sa.shift_id into v_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active
        and sa.effective_from <= v_day
        and (sa.effective_to is null or sa.effective_to >= v_day)
      order by sa.effective_from desc, sa.created_at desc
      limit 1;
    end if;

    if v_shift_id is null and v_is_scheduled then
      select s.id into v_shift_id
      from public.shifts s
      where s.is_active
      order by (s.code = 'OFFICIAL') desc,
               s.updated_at desc nulls last,
               s.created_at desc
      limit 1;
    end if;

    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    v_grace_out := 0;
    v_scheduled_minutes := 0;

    if v_shift_id is not null then
      select s.name,
             coalesce(v_start_override, s.start_time),
             coalesce(v_end_override, s.end_time),
             s.crosses_midnight or coalesce(v_end_override, s.end_time) <= coalesce(v_start_override, s.start_time),
             coalesce(s.break_minutes, 0),
             coalesce(s.grace_out_minutes, 0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses,
             v_shift_break, v_grace_out
      from public.shifts s
      where s.id = v_shift_id;

      if v_shift_start is not null and v_shift_end is not null then
        v_scheduled_minutes := greatest(
          0,
          (extract(epoch from (
            (v_day + v_shift_end
              + case when v_shift_crosses then interval '1 day' else interval '0' end)
            - (v_day + v_shift_start)
          )) / 60)::integer - v_shift_break
        );
        v_shift_end_at := v_day + v_shift_end
          + case when v_shift_crosses then interval '1 day' else interval '0' end
          + make_interval(mins => v_grace_out);
      else
        v_shift_end_at := v_day::timestamp + interval '1 day';
      end if;
    else
      v_shift_end_at := v_day::timestamp + interval '1 day';
    end if;

    if v_is_scheduled then
      if v_is_future then
        v_upcoming_days := v_upcoming_days + 1;
        if v_status = 'غائب دون إذن' then
          v_status := 'يوم قادم';
        end if;
      elsif v_is_excused then
        if v_is_exempt then
          v_status := 'معفى من الحضور';
          v_present_days := v_present_days + 1;
        elsif v_has_late_p and v_daily.first_check_in is null then
          v_status := 'إذن حضور مسجل';
          v_present_days := v_present_days + 1;
        elsif v_daily.first_check_in is not null then
          v_present_days := v_present_days + 1;
          if v_daily.last_check_out is not null then
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_has_early_p then
            v_status := 'حاضر (إذن انصراف)';
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_now_local <= v_shift_end_at then
            v_is_open := true;
            v_open_shift_days := v_open_shift_days + 1;
            v_status := 'حاضر — بانتظار الانصراف';
          end if;
        else
          -- معذور بلا بصمة (مأمورية/قافلة/إجازة)
          if v_status in ('غائب دون إذن', 'يحتاج مراجعة') then
            v_status := coalesce(v_day_obj->>'status', 'معذور');
          end if;
          if v_status not like '%إجازة%' and v_status <> 'بدل راحة أسبوعية' then
            v_present_days := v_present_days + 1;
          end if;
        end if;
      else
        if v_daily.first_check_in is not null then
          v_present_days := v_present_days + 1;
          if v_daily.last_check_out is not null then
            v_is_due := true;
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_now_local <= v_shift_end_at then
            v_is_open := true;
            v_open_shift_days := v_open_shift_days + 1;
            v_status := 'حاضر — بانتظار الانصراف';
          else
            v_is_due := true;
            v_missing_out := true;
            v_missing_checkout := v_missing_checkout + 1;
            v_status := 'حضور ناقص — لم يسجل الانصراف';
          end if;
        elsif coalesce((v_day_obj->>'hasCorrection')::boolean, false)
              and not coalesce((v_day_obj->>'isAbsent')::boolean, false) then
          v_is_due := true;
          v_present_days := v_present_days + 1;
        elsif v_daily.id is not null and v_daily.status = 'absent' then
          v_is_due := true;
          v_absent_days := v_absent_days + 1;
          v_status := 'غائب دون إذن';
        elsif v_now_local <= v_shift_end_at then
          v_status := 'بانتظار تسجيل الحضور';
        else
          v_is_due := true;
          v_absent_days := v_absent_days + 1;
          v_status := 'غائب دون إذن';
        end if;

        if v_is_due then
          v_due_days := v_due_days + 1;
        end if;

        if v_daily.id is not null
           and v_daily.first_check_in is null
           and v_daily.status <> 'absent'
           and not v_has_late_p
           and not v_is_exempt then
          v_missing_in := true;
          v_missing_checkin := v_missing_checkin + 1;
        end if;
      end if;
    end if;

    if v_is_due and v_is_completed then
      v_compliance_work_minutes := v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
    end if;

    v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
    v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
    v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

    v_day_obj := v_day_obj || jsonb_build_object(
      'status', v_status,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'isDue', v_is_due,
      'isFuture', v_is_future,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  return v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout
    )
  );
end
$function$;

revoke all on function public._build_attendance_statement_v251(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v251(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Rebuild _build_attendance_statement_v252
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement_v252(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_leave jsonb;
  v_assignment jsonb;
  v_permit jsonb;
  v_correction jsonb;
  v_missing jsonb;
  v_is_exempt boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);

  v_result := public._build_attendance_statement_v251(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

    -- 1) Approved or pending leave for this day
    select jsonb_build_object(
             'typeLabel', coalesce(lt.name_ar, 'إجازة') || case when r.status = 'pending' then ' (قيد الاعتماد)' else '' end,
             'startDate', lr.start_date,
             'endDate',   lr.end_date,
             'isHalfDay', lr.is_half_day,
             'daysCount', lr.days_count,
             'reason',    nullif(r.reason, '')
           )
      into v_leave
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      left join public.leave_types lt on lt.id = lr.leave_type_id
     where lr.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and v_day between lr.start_date and lr.end_date
     order by case when r.status = 'approved' then 1 else 2 end, lr.start_date desc
     limit 1;

    if v_leave is null then
      select jsonb_build_object(
               'typeLabel', coalesce(
                              (select lt.name_ar from public.leave_types lt where lt.code = (r.payload->>'leaveType') limit 1),
                              case r.payload->>'leaveType'
                                when 'weekly_rest_comp' then 'بدل راحة أسبوعية'
                                when 'annual' then 'إجازة اعتيادية'
                                when 'casual' then 'إجازة عارضة (طارئة)'
                                when 'sick' then 'إجازة مرضية'
                                when 'unpaid' then 'إجازة بدون أجر'
                                else coalesce(r.title, 'إجازة')
                              end
                            ) || case when r.status = 'pending' then ' (قيد الاعتماد)' else '' end,
               'startDate', coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')),
               'endDate',   coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                     public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')),
               'isHalfDay', coalesce((r.payload->>'isHalfDay')::boolean, false),
               'daysCount', coalesce((r.payload->>'days')::numeric, 1),
               'reason',    nullif(r.reason, '')
             )
        into v_leave
        from public.requests r
       where r.employee_id = p_employee_id
         and r.status not in ('rejected', 'cancelled')
         and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
         and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                       and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                    public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
       order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
       limit 1;
    end if;

    -- 2) Approved work assignment (mission / convoy / fundraising)
    select jsonb_build_object(
             'typeLabel', case wa.assignment_type
                            when 'MISSION'     then 'مأمورية عمل'
                            when 'CONVOY'      then 'قافلة'
                            when 'FUNDRAISING' then 'فاندي'
                            else 'تكليف عمل'
                          end,
             'assignmentType', wa.assignment_type,
             'title',    nullif(wa.title, ''),
             'location', nullif(wa.location, ''),
             'startAt',  (wa.start_at at time zone 'Africa/Cairo'),
             'endAt',    (wa.end_at   at time zone 'Africa/Cairo')
           )
      into v_assignment
      from public.work_assignment_participants wp
      join public.work_assignments wa on wa.id = wp.assignment_id
     where wp.employee_id = p_employee_id
       and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
       and coalesce(wa.counts_as_work_day, true)
       and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                     and (wa.end_at   at time zone 'Africa/Cairo')::date
     order by wa.start_at desc
     limit 1;

    if v_assignment is null then
      select jsonb_build_object(
               'typeLabel', case
                              when r.request_type in ('convoy', 'field_convoy') or r.payload->>'missionType' = 'convoy' then 'قافلة'
                              when r.request_type in ('fundraising', 'fandy', 'fundi') or r.payload->>'missionType' = 'fundraising' then 'فاندي'
                              else 'مأمورية عمل'
                            end || case when r.status = 'pending' then ' (قيد الاعتماد)' else '' end,
               'assignmentType', case
                                   when r.request_type in ('convoy', 'field_convoy') or r.payload->>'missionType' = 'convoy' then 'CONVOY'
                                   when r.request_type in ('fundraising', 'fandy', 'fundi') or r.payload->>'missionType' = 'fundraising' then 'FUNDRAISING'
                                   else 'MISSION'
                                 end,
               'title',    coalesce(nullif(r.title, ''), nullif(r.payload->>'location', ''), nullif(r.reason, '')),
               'location', coalesce(nullif(r.payload->>'location', ''), nullif(r.payload->>'destination', '')),
               'startAt',  coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date),
               'endAt',    coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date)
             )
        into v_assignment
        from public.requests r
       where r.employee_id = p_employee_id
         and r.status not in ('rejected', 'cancelled')
         and (
           r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy',
                              'fundraising', 'fandy', 'fundi', 'remote_work')
           or coalesce(r.payload->>'missionType', r.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy', 'fundi')
         )
         and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date)
                       and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'workDate'), r.created_at::date)
       order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
       limit 1;
    end if;

    if v_assignment is null then
      select jsonb_build_object(
               'typeLabel', 'مأمورية عمل',
               'assignmentType', 'MISSION',
               'title',    nullif(m.purpose, ''),
               'location', nullif(m.destination, ''),
               'startAt',  (m.start_at at time zone 'Africa/Cairo'),
               'endAt',    (m.end_at   at time zone 'Africa/Cairo')
             )
        into v_assignment
        from public.missions m
        join public.requests r on r.id = m.request_id
       where m.employee_id = p_employee_id
         and r.status not in ('rejected', 'cancelled')
         and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                       and (m.end_at   at time zone 'Africa/Cairo')::date
       order by m.start_at desc
       limit 1;
    end if;

    -- 3) إذن الحضور/الانصراف من جدول requests الموحّد
    select jsonb_build_object(
             'kindLabel', case
                            when r.request_type = 'late_permit' or r.payload->>'permitKind' = 'late_arrival' then 'إذن حضور متأخر'
                            when r.request_type = 'early_permit' or r.payload->>'permitKind' = 'early_departure' then 'إذن انصراف مبكر'
                            else 'إذن شخصي'
                          end || case when r.status = 'pending' then ' (قيد المراجعة)' else '' end,
             'permitKind', case
                             when r.request_type = 'late_permit' or r.payload->>'permitKind' = 'late_arrival' then 'arrival'
                             when r.request_type = 'early_permit' or r.payload->>'permitKind' = 'early_departure' then 'departure'
                             else 'personal'
                           end,
             'minutes', coalesce((r.payload->>'minutes')::integer, 120),
             'reason', nullif(r.reason, '')
           )
      into v_permit
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and (
         r.request_type in ('late_permit', 'early_permit', 'permission', 'errand', 'late_excuse')
         or (r.request_type = 'permit')
       )
       and coalesce(
         public.try_cast_date(r.payload->>'permitDate'),
         public.try_cast_date(r.payload->>'date'),
         public.try_cast_date(r.payload->>'startDate'),
         public.try_cast_date(r.payload->>'workDate'),
         r.created_at::date
       ) = v_day
     order by case when r.request_type = 'late_permit' then 1 else 2 end,
              r.created_at desc
     limit 1;

    -- 4) Approved attendance correction for this day
    select jsonb_build_object(
             'typeLabel', case c.correction_type
                            when 'missing_check_in'  then 'تصحيح نقص بصمة حضور'
                            when 'missing_check_out' then 'تصحيح نقص بصمة انصراف'
                            when 'wrong_time'        then 'تصحيح خطأ بصمة'
                            when 'wrong_status'      then 'تصحيح حالة اليوم'
                            when 'mission'           then 'تصحيح (مأمورية)'
                            when 'leave'             then 'تصحيح (إجازة)'
                            else 'تصحيح حضور'
                          end,
             'correctionType', c.correction_type,
             'reason', nullif(c.reason, '')
           )
      into v_correction
      from public.attendance_corrections c
     where c.employee_id = p_employee_id
       and c.work_date = v_day
       and c.status = 'approved'
     order by c.reviewed_at desc nulls last, c.created_at desc
     limit 1;

    -- 5) Still-missing punches
    v_missing := jsonb_build_object(
      'checkIn',  coalesce((v_day_obj->>'missingCheckIn')::boolean,  false) and not v_has_late_p and not v_is_exempt and v_assignment is null and v_leave is null,
      'checkOut', coalesce((v_day_obj->>'missingCheckOut')::boolean, false) and not v_has_early_p and not v_is_exempt and v_assignment is null and v_leave is null
    );

    -- تحديث أعلام v_day_obj
    if v_assignment is not null then
      v_day_obj := v_day_obj || jsonb_build_object(
        'hasMission', (v_assignment->>'assignmentType' = 'MISSION'),
        'hasConvoyFundi', (v_assignment->>'assignmentType' in ('CONVOY', 'FUNDRAISING')),
        'isAbsent', false,
        'missingCheckIn', false,
        'missingCheckOut', false,
        'status', case
                    when coalesce(v_day_obj->>'status', '') in ('غائب دون إذن', 'يحتاج مراجعة')
                         or coalesce((v_day_obj->>'isAbsent')::boolean, false)
                    then case
                           when (v_assignment->>'assignmentType') = 'CONVOY' then 'قافلة'
                           when (v_assignment->>'assignmentType') = 'FUNDRAISING' then 'فاندي'
                           else 'مأمورية عمل'
                         end
                    else coalesce(v_day_obj->>'status', '')
                  end
      );
    end if;

    if v_leave is not null then
      v_day_obj := v_day_obj || jsonb_build_object(
        'hasLeave', true,
        'isAbsent', false,
        'missingCheckIn', false,
        'missingCheckOut', false,
        'status', case
                    when coalesce(v_day_obj->>'status', '') in ('غائب دون إذن', 'يحتاج مراجعة')
                         or coalesce((v_day_obj->>'isAbsent')::boolean, false)
                    then v_leave->>'typeLabel'
                    else coalesce(v_day_obj->>'status', '')
                  end
      );
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'details', jsonb_strip_nulls(jsonb_build_object(
        'leave',      v_leave,
        'assignment', v_assignment,
        'permit',     v_permit,
        'correction', v_correction,
        'missing',    v_missing
      ))
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  return v_result || jsonb_build_object('days', v_days);
end
$function$;

revoke all on function public._build_attendance_statement_v252(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v252(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) Rebuild _build_attendance_statement_v266
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement_v266(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_now_local timestamp := now() at time zone 'Africa/Cairo';
  v_daily public.attendance_daily%rowtype;
  v_shift_id uuid;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_grace_out integer;
  v_start_override time;
  v_end_override time;
  v_shift_end_at timestamp;
  v_scheduled_minutes integer;
  v_is_scheduled boolean;
  v_is_excused boolean;
  v_is_future boolean;
  v_is_due boolean;
  v_is_open boolean;
  v_is_completed boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_status text;
  v_due_days integer := 0;
  v_upcoming_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_open_shift_days integer := 0;
  v_completed_presence_days integer := 0;
  v_completed_work_minutes integer := 0;
  v_compliance_work_minutes integer := 0;
  v_total_work_minutes integer := 0;
  v_total_required_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
  v_is_exempt boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);

  v_result := public._build_attendance_statement_v252(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_status := coalesce(v_day_obj->>'status', '');
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

    v_is_scheduled := v_status not in ('راحة أسبوعية', 'عطلة رسمية');
    v_is_excused :=
      coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      or (v_day_obj->'details'->'assignment') is not null
      or (v_day_obj->'details'->'leave') is not null
      or v_status in ('بدل راحة أسبوعية', 'قافلة', 'فاندي', 'مأمورية', 'مأمورية عمل')
      or v_status like '%إجازة%'
      or v_status like '%مأمورية%'
      or v_status like '%قافلة%'
      or v_status like '%فاندي%'
      or v_has_late_p
      or v_has_early_p
      or coalesce((v_day_obj->>'hasPermit')::boolean, false)
      or v_status in ('إذن حضور مسجل', 'معفى من الحضور')
      or v_is_exempt;

    v_is_future := v_is_scheduled and not v_is_excused and v_day > v_today;
    v_is_due := false;
    v_is_open := false;
    v_is_completed := false;
    v_missing_in := false;
    v_missing_out := false;

    select * into v_daily
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_day;

    v_shift_id := v_daily.shift_id;
    v_start_override := null;
    v_end_override := null;

    if v_shift_id is null then
      select rd.shift_id, rd.start_override, rd.end_override
        into v_shift_id, v_start_override, v_end_override
      from public.roster_days rd
      join public.work_rosters wr
        on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_day
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last, wr.created_at desc
      limit 1;
    end if;

    if v_shift_id is null then
      select sa.shift_id into v_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active
        and sa.effective_from <= v_day
        and (sa.effective_to is null or sa.effective_to >= v_day)
      order by sa.effective_from desc, sa.created_at desc
      limit 1;
    end if;

    if v_shift_id is null and v_is_scheduled then
      select s.id into v_shift_id
      from public.shifts s
      where s.is_active
      order by (s.code = 'OFFICIAL') desc,
               s.updated_at desc nulls last,
               s.created_at desc
      limit 1;
    end if;

    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    v_grace_out := 0;
    v_scheduled_minutes := 0;

    if v_shift_id is not null then
      select s.name,
             coalesce(v_start_override, s.start_time),
             coalesce(v_end_override, s.end_time),
             s.crosses_midnight or coalesce(v_end_override, s.end_time) <= coalesce(v_start_override, s.start_time),
             coalesce(s.break_minutes, 0),
             coalesce(s.grace_out_minutes, 0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses,
             v_shift_break, v_grace_out
      from public.shifts s
      where s.id = v_shift_id;

      if v_shift_start is not null and v_shift_end is not null then
        v_scheduled_minutes := greatest(
          0,
          (extract(epoch from (
            (v_day + v_shift_end
              + case when v_shift_crosses then interval '1 day' else interval '0' end)
            - (v_day + v_shift_start)
          )) / 60)::integer - v_shift_break
        );
        v_shift_end_at := v_day + v_shift_end
          + case when v_shift_crosses then interval '1 day' else interval '0' end
          + make_interval(mins => v_grace_out);
      else
        v_shift_end_at := v_day::timestamp + interval '1 day';
      end if;
    else
      v_shift_end_at := v_day::timestamp + interval '1 day';
    end if;

    if v_is_scheduled then
      if v_is_future then
        v_upcoming_days := v_upcoming_days + 1;
        if v_status = 'غائب دون إذن' then
          v_status := 'يوم قادم';
        end if;
      elsif v_is_excused then
        if v_is_exempt then
          v_status := 'معفى من الحضور';
          v_present_days := v_present_days + 1;
        elsif v_has_late_p and v_daily.first_check_in is null then
          v_status := 'إذن حضور مسجل';
          v_present_days := v_present_days + 1;
        elsif v_daily.first_check_in is not null then
          v_present_days := v_present_days + 1;
          if v_daily.last_check_out is not null then
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_has_early_p then
            v_status := 'حاضر (إذن انصراف)';
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_now_local <= v_shift_end_at then
            v_is_open := true;
            v_open_shift_days := v_open_shift_days + 1;
            v_status := 'حاضر — بانتظار الانصراف';
          end if;
        else
          -- معذور بلا بصمة (مأمورية/قافلة/إجازة)
          if v_status in ('غائب دون إذن', 'يحتاج مراجعة') then
            v_status := coalesce(v_day_obj->>'status', 'معذور');
          end if;
          if v_status not like '%إجازة%' and v_status <> 'بدل راحة أسبوعية' then
            v_present_days := v_present_days + 1;
          end if;
        end if;
      else
        if v_daily.first_check_in is not null then
          v_present_days := v_present_days + 1;
          if v_daily.last_check_out is not null then
            v_is_due := true;
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes := v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_now_local <= v_shift_end_at then
            v_is_open := true;
            v_open_shift_days := v_open_shift_days + 1;
            v_status := 'حاضر — بانتظار الانصراف';
          else
            v_is_due := true;
            v_missing_out := true;
            v_missing_checkout := v_missing_checkout + 1;
            v_status := 'حضور ناقص — لم يسجل الانصراف';
          end if;
        elsif coalesce((v_day_obj->>'hasCorrection')::boolean, false)
              and not coalesce((v_day_obj->>'isAbsent')::boolean, false) then
          v_is_due := true;
          v_present_days := v_present_days + 1;
        elsif v_daily.id is not null and v_daily.status = 'absent' then
          v_is_due := true;
          v_absent_days := v_absent_days + 1;
          v_status := 'غائب دون إذن';
        elsif v_now_local <= v_shift_end_at then
          v_status := 'بانتظار تسجيل الحضور';
        else
          v_is_due := true;
          v_absent_days := v_absent_days + 1;
          v_status := 'غائب دون إذن';
        end if;

        if v_is_due then
          v_due_days := v_due_days + 1;
        end if;

        if v_daily.id is not null
           and v_daily.first_check_in is null
           and v_daily.status <> 'absent'
           and not v_has_late_p
           and not v_is_exempt then
          v_missing_in := true;
          v_missing_checkin := v_missing_checkin + 1;
        end if;
      end if;
    end if;

    if v_is_due and v_is_completed then
      v_compliance_work_minutes := v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
    end if;

    v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
    v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
    v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

    v_day_obj := v_day_obj || jsonb_build_object(
      'status', v_status,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'isDue', v_is_due,
      'isFuture', v_is_future,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  return v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout
    )
  );
end
$function$;

revoke all on function public._build_attendance_statement_v266(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v266(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) Rebuild _build_attendance_statement_v287
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement_v287(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_matched public.shifts%rowtype;
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
      if v_override.id is null then
        v_work_minutes := coalesce(public.calculate_paired_work_minutes(
          p_employee_id,
          (v_day::text || ' 00:00:00 Africa/Cairo')::timestamptz,
          (v_day::text || ' 23:59:59 Africa/Cairo')::timestamptz), 0);
      end if;
      if v_work_minutes = 0 then
        v_work_minutes := greatest(0, (extract(epoch from (
          (v_day + v_check_out + case when v_check_out <= v_check_in then interval '1 day' else interval '0' end)
          - (v_day + v_check_in)
        )) / 60)::integer);
      end if;
    end if;

    v_matched := null;
    if v_check_in is not null and v_scheduled and not exists (
      select 1 from public.shift_assignments sa
      where sa.employee_id = p_employee_id and sa.is_active
        and sa.effective_from <= v_day and (sa.effective_to is null or sa.effective_to >= v_day)
    ) then
      select s.* into v_matched from public.shifts s
      where s.id = public.match_flexible_shift(((v_day + v_check_in)::timestamp at time zone 'Africa/Cairo'));
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
        or (v_day_obj->'details'->'assignment') is not null
        or (v_day_obj->'details'->'leave') is not null
        or (v_day_obj->>'status') in ('بدل راحة أسبوعية', 'قافلة', 'فاندي', 'مأمورية', 'مأمورية عمل')
        or (v_day_obj->>'status') like '%إجازة%'
        or (v_day_obj->>'status') like '%مأمورية%'
        or (v_day_obj->>'status') like '%قافلة%'
        or (v_day_obj->>'status') like '%فاندي%'
      ))
    );

    v_is_open := v_check_in is not null and v_check_out is null and not v_is_future;
    v_is_due := v_scheduled and not v_is_future and not v_is_open and not (
      v_type in ('leave', 'mission', 'convoy', 'fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
        or (v_day_obj->'details'->'assignment') is not null
        or (v_day_obj->'details'->'leave') is not null
        or (v_day_obj->>'status') in ('بدل راحة أسبوعية', 'قافلة', 'فاندي', 'مأمورية', 'مأمورية عمل')
        or (v_day_obj->>'status') like '%إجازة%'
        or (v_day_obj->>'status') like '%مأمورية%'
        or (v_day_obj->>'status') like '%قافلة%'
        or (v_day_obj->>'status') like '%فاندي%'
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

    if v_type = 'leave' or (v_override.id is null and (coalesce((v_day_obj->>'hasLeave')::boolean, false) or (v_day_obj->>'status') = 'بدل راحة أسبوعية' or (v_day_obj->>'status') like '%إجازة%')) then
      v_leave_days := v_leave_days + 1;
    end if;
    if v_type = 'mission' or (v_override.id is null and (coalesce((v_day_obj->>'hasMission')::boolean, false) or (v_day_obj->>'status') like '%مأمورية%')) then
      v_mission_days := v_mission_days + 1;
    end if;
    if v_type in ('convoy','fundraising') or (v_override.id is null and (coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or (v_day_obj->>'status') like '%قافلة%' or (v_day_obj->>'status') like '%فاندي%')) then
      v_convoy_days := v_convoy_days + 1;
    end if;
    if not v_scheduled then
      if extract(isodow from v_day) = 5 or v_type = 'rest' then v_rest_days := v_rest_days + 1;
      else v_holiday_days := v_holiday_days + 1;
      end if;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn', case when v_check_in is null then null else to_char(v_check_in, 'HH24:MI') end,
      'shiftName', case when v_matched.id is not null then v_matched.name else null end,
      'shiftStart', case when v_matched.id is not null then v_matched.start_time::text else null end,
      'shiftEnd', case when v_matched.id is not null then v_matched.end_time::text else null end,
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
      'hasLeave', case when v_override.id is null then coalesce((v_day_obj->>'hasLeave')::boolean, false) or (v_day_obj->>'status') = 'بدل راحة أسبوعية' or (v_day_obj->>'status') like '%إجازة%' else v_type = 'leave' end,
      'hasMission', case when v_override.id is null then coalesce((v_day_obj->>'hasMission')::boolean, false) or (v_day_obj->>'status') like '%مأمورية%' else v_type = 'mission' end,
      'hasConvoyFundi', case when v_override.id is null then coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or (v_day_obj->>'status') like '%قافلة%' or (v_day_obj->>'status') like '%فاندي%' else v_type in ('convoy','fundraising') end,
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
        when (v_override.id is null) and (coalesce((v_day_obj->>'hasMission')::boolean, false) or (v_day_obj->>'status') like '%مأمورية%') then 'مأمورية'
        when (v_override.id is null) and ((coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or (v_day_obj->>'status') like '%فاندي%') and v_day_obj->>'status' = 'فاندي') then 'فاندي'
        when (v_override.id is null) and (coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or (v_day_obj->>'status') like '%قافلة%') then 'قافلة'
        when (v_override.id is null) and ((v_day_obj->>'status') = 'بدل راحة أسبوعية') then 'بدل راحة أسبوعية'
        when (v_override.id is null) and ((v_day_obj->>'status') like '%إجازة%') then v_day_obj->>'status'
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
      'totalWorkMinutes', v_total_work_minutes,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'monthRequiredMinutes', v_month_required_minutes,
      'monthDeficitMinutes', v_month_deficit_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes
    )
  );

  return v_result;
end;
$function$;

revoke execute on function public._build_attendance_statement_v287(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v287(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 6) Rebuild _build_attendance_statement (outermost)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._build_attendance_statement(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_late_grace constant integer := 15;
  c_late_cap   constant integer := 120;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
  v_summary jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
  v_pending_permit boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
  v_is_exempt boolean;
  v_hire_date date;
  v_emp_name text;
  v_emp_code text;
  v_emp_photo text;
  v_job_title text;
  v_dept_name text;
  v_override_type text;
  v_scheduled boolean;
  v_on_leave boolean;
  v_offsite boolean;
  v_pending boolean;
  v_exempt_day boolean;
  v_waiting_today boolean;
  v_expected boolean;
  v_attended boolean;
  v_open_today boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_shift_start time;
  v_shift_end time;
  v_late integer;
  v_early integer;
  v_day_work integer;
  v_day_required integer;
  -- المجاميع
  v_pending_days integer := 0;
  v_expected_days integer := 0;
  v_attended_days integer := 0;
  v_offsite_days integer := 0;
  v_excl_leave integer := 0;
  v_excl_pending integer := 0;
  v_excl_exempt integer := 0;
  v_absent_days integer := 0;
  v_open_days integer := 0;
  v_missing_in_count integer := 0;
  v_missing_out_count integer := 0;
  v_hours_days integer := 0;
  v_required_minutes integer := 0;
  v_worked_minutes integer := 0;
  v_deficit_minutes integer := 0;
  v_late_total integer := 0;
  v_late_days integer := 0;
  v_early_total integer := 0;
  v_early_days integer := 0;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);
  select e.hire_date, e.full_name_ar, e.employee_code, e.photo_url,
         jt.name, d.name
    into v_hire_date, v_emp_name, v_emp_code, v_emp_photo, v_job_title, v_dept_name
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
   where e.id = p_employee_id;
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    continue when v_day_obj is null or v_day_obj = 'null'::jsonb;

    v_day := (v_day_obj->>'date')::date;

    if v_hire_date is not null and v_day < v_hire_date then
      v_days := v_days || jsonb_build_array(v_day_obj || jsonb_build_object(
        'status', 'قبل تاريخ التعيين',
        'isAbsent', false, 'isDue', false, 'isOpenShift', false,
        'missingCheckIn', false, 'missingCheckOut', false,
        'lateMinutes', 0, 'earlyLeaveMinutes', 0));
      continue;
    end if;

    v_ci := nullif(v_day_obj->>'checkIn', '');
    v_co := nullif(v_day_obj->>'checkOut', '');
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

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
        and r.request_type in ('mission', 'external_mission', 'administrative_mission')
        and r.status = 'pending'
        and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                      and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                   public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
        and r.status = 'pending'
        and v_day between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                      and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                   public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
    );
    v_pending_permit := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
        and r.status = 'pending'
        and coalesce(
          public.try_cast_date(r.payload->>'permitDate'),
          public.try_cast_date(r.payload->>'date'),
          public.try_cast_date(r.payload->>'startDate'),
          public.try_cast_date(r.payload->>'workDate'),
          r.created_at::date
        ) = v_day
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه بصمة → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy or v_pending_permit)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        when v_pending_permit then 'بانتظار اعتماد إذن'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    if v_is_exempt and (v_status in ('غائب دون إذن', 'بانتظار حضور') or v_is_absent) then
      v_status := 'معفى من الحضور';
      v_is_absent := false;
    end if;

    -- adminOverride.leaveType
    if (v_day_obj->'adminOverride') is not null and (v_day_obj->'adminOverride') <> 'null'::jsonb then
      v_day_obj := jsonb_set(
        v_day_obj,
        '{adminOverride,leaveType}',
        coalesce(
          (v_day_obj->'adminOverride'->'leaveType'),
          to_jsonb((
            select o.leave_type
            from public.attendance_day_overrides o
            where o.employee_id = p_employee_id
              and o.work_date = v_day
              and o.is_active
            limit 1
          )),
          'null'::jsonb
        ),
        true
      );
    end if;

    -- ── تصنيف اليوم ──
    v_override_type := coalesce(v_day_obj->'adminOverride'->>'dayType', '');
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_override_type not in ('holiday', 'rest');
    v_on_leave := (coalesce((v_day_obj->>'hasLeave')::boolean, false)
                   or (v_day_obj->'details'->'leave') is not null
                   or (v_day_obj->>'status') = 'بدل راحة أسبوعية'
                   or (v_day_obj->>'status') like '%إجازة%') and v_ci is null;
    v_offsite := coalesce((v_day_obj->>'hasMission')::boolean, false)
              or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
              or (v_day_obj->'details'->'assignment') is not null
              or (v_day_obj->>'status') in ('قافلة', 'فاندي', 'مأمورية', 'مأمورية عمل')
              or (v_day_obj->>'status') like '%قافلة%'
              or (v_day_obj->>'status') like '%فاندي%'
              or (v_day_obj->>'status') like '%مأمورية%';

    if (v_offsite or v_on_leave) and v_is_absent then
      v_is_absent := false;
    end if;

    v_pending := v_status like 'بانتظار اعتماد%';
    v_exempt_day := v_status = 'معفى من الحضور';
    v_waiting_today := v_day = v_today and v_ci is null and not v_is_absent and not v_offsite;
    v_expected := v_scheduled and v_day <= v_today and not v_on_leave and not v_pending
                  and not v_exempt_day and not v_waiting_today;
    v_attended := v_expected and (v_ci is not null or v_offsite);
    v_open_today := v_day = v_today and v_ci is not null and v_co is null;

    -- ── أعلام النقص ──
    v_missing_out := v_scheduled and v_day < v_today and v_ci is not null and v_co is null
                     and not v_offsite and not v_has_early_p and not v_pending_permit and not v_is_exempt;
    v_missing_in := v_scheduled and v_ci is null
                    and (v_co is not null or coalesce((v_day_obj->>'missingCheckIn')::boolean, false))
                    and not v_offsite and not v_on_leave and not v_has_late_p and not v_pending_permit and not v_is_exempt;

    -- ── التأخير والخروج المبكر ──
    v_late := 0;
    v_early := 0;
    if v_ci is not null then
      begin
        v_late := public.attendance_policy_late_minutes(
          p_employee_id, v_day, ((v_day + v_ci::time)::timestamp at time zone 'Africa/Cairo'), null);
      exception when others then
        v_late := 0;
      end;
    end if;
    if v_scheduled and v_ci is not null and not v_offsite and not v_is_exempt and not v_pending_permit then
      v_shift_end := nullif(v_day_obj->>'shiftEnd', '')::time;
      if v_shift_end is not null and v_co is not null and not v_has_early_p
         and v_co::time > v_ci::time and v_co::time < v_shift_end then
        v_early := floor(extract(epoch from (v_shift_end - v_co::time)) / 60)::integer;
      end if;
    end if;

    -- ── الساعات ──
    v_day_work := greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer;
    v_day_required := greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60))::integer;
    if v_day_required = 0 then v_day_required := 480; end if;
    if v_expected and not v_open_today and (not v_offsite or (v_ci is not null and v_co is not null)) then
      v_hours_days := v_hours_days + 1;
      v_required_minutes := v_required_minutes + v_day_required;
      v_worked_minutes := v_worked_minutes + v_day_work;
      v_deficit_minutes := v_deficit_minutes + greatest(0, v_day_required - v_day_work);
    end if;

    -- ── المجاميع ──
    if v_scheduled and v_day <= v_today then
      if v_on_leave then v_excl_leave := v_excl_leave + 1;
      elsif v_pending then v_excl_pending := v_excl_pending + 1;
      elsif v_exempt_day then v_excl_exempt := v_excl_exempt + 1;
      end if;
    end if;
    if v_expected then
      v_expected_days := v_expected_days + 1;
      if v_attended then
        v_attended_days := v_attended_days + 1;
        if v_ci is null then v_offsite_days := v_offsite_days + 1; end if;
      end if;
    end if;
    if v_open_today then v_open_days := v_open_days + 1; end if;
    if v_missing_in then v_missing_in_count := v_missing_in_count + 1; end if;
    if v_missing_out then v_missing_out_count := v_missing_out_count + 1; end if;
    if v_late > 0 then v_late_total := v_late_total + v_late; v_late_days := v_late_days + 1; end if;
    if v_early > 0 then v_early_total := v_early_total + v_early; v_early_days := v_early_days + 1; end if;

    if v_day < v_today and v_status = 'حاضر — بانتظار الانصراف' then
      v_status := case
        when v_has_early_p then 'حاضر (إذن انصراف)'
        when v_missing_out then 'حضور ناقص — لم يسجل الانصراف'
        else 'حاضر'
      end;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(v_day_work),
      'status', v_status
    )) || jsonb_build_object(
      'isAbsent', v_is_absent,
      'isDue', v_expected,
      'isOpenShift', v_open_today,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy,
      'hasPendingPermit', v_pending_permit,
      'hasMission', (coalesce((v_day_obj->>'hasMission')::boolean, false) or v_status like '%مأمورية%'),
      'hasConvoyFundi', (coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) or v_status in ('قافلة', 'فاندي') or v_status like '%قافلة%' or v_status like '%فاندي%'),
      'hasLeave', (coalesce((v_day_obj->>'hasLeave')::boolean, false) or v_status = 'بدل راحة أسبوعية' or v_status like '%إجازة%'),
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out,
      'lateMinutes', v_late,
      'earlyLeaveMinutes', v_early
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int from jsonb_array_elements(v_days) d
                    where coalesce((d->>'isAbsent')::boolean, false));

  v_summary := coalesce(v_result->'summary', '{}'::jsonb);
  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', v_summary || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'dueScheduledDays', v_expected_days,
      'openShiftDays', v_open_days,
      'missingCheckInCount', v_missing_in_count,
      'missingCheckOutCount', v_missing_out_count,
      'isAttendanceExempt', v_is_exempt,
      'attendanceRate', case when v_expected_days > 0
        then round(least(v_attended_days, v_expected_days) * 100.0 / v_expected_days, 2)
        else 0 end,
      'attendanceRateAvailable', v_expected_days > 0 and not v_is_exempt,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', least(v_attended_days, v_expected_days),
        'dueDays', v_expected_days,
        'presentDays', coalesce((v_summary->>'presentDays')::integer, 0),
        'offsiteDays', v_offsite_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_days,
        'upcomingDays', coalesce((v_summary->>'upcomingDays')::integer, 0),
        'excludedLeaveDays', v_excl_leave,
        'excludedPendingDays', v_excl_pending,
        'excludedExemptDays', v_excl_exempt,
        'basis', 'elapsed_workdays_excluding_leave_pending_exempt'
      ),
      'hoursComplianceAvailable', v_required_minutes > 0 and not v_is_exempt,
      'hoursComplianceRate', case when v_required_minutes > 0
        then least(100, round(v_worked_minutes * 100.0 / v_required_minutes, 2))
        else 0 end,
      'totalRequiredHours', round(v_required_minutes / 60.0, 2),
      'requiredMinutes', v_required_minutes,
      'compliantWorkMinutes', v_worked_minutes,
      'totalDeficitMinutes', v_deficit_minutes,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_worked_minutes,
        'requiredMinutes', v_required_minutes,
        'scheduledDays', v_hours_days,
        'deficitMinutes', v_deficit_minutes,
        'overtimeMinutes', coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0),
        'monthRequiredMinutes', coalesce((v_summary->'hoursRateBasis'->>'requiredMinutes')::integer, 0),
        'basis', 'elapsed_office_days'
      ),
      'totalLateMinutes', v_late_total,
      'lateDays', v_late_days,
      'totalEarlyLeaveMinutes', v_early_total,
      'earlyLeaveDays', v_early_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_summary->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(v_required_minutes),
      'totalDeficitFormatted', public._fmt_minutes_ar(v_deficit_minutes),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(v_late_total),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(v_early_total)
    )
  );

  v_result := v_result || jsonb_build_object('employee', jsonb_build_object(
    'id', p_employee_id,
    'name', v_emp_name,
    'fullNameAr', v_emp_name,
    'employeeCode', v_emp_code,
    'jobTitle', v_job_title,
    'department', v_dept_name,
    'photoUrl', v_emp_photo
  ));

  return v_result;
end;
$function$;

revoke execute on function public._build_attendance_statement(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 7) Update Trigger tg_assignment_day_present to update existing absent rows
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.tg_assignment_day_present()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start date;
  v_end   date;
  v_day   date;
  v_guard integer := 0;
begin
  if new.request_type not in ('mission','convoy','fundraising','external_mission','field_convoy','fandy','fundi') then
    return new;
  end if;
  if new.status = 'approved' and old.status is distinct from 'approved' then
    v_start := coalesce(public.try_cast_date(new.payload->>'startDate'), public.try_cast_date(new.payload->>'start_date'), public.try_cast_date(new.payload->>'date'), new.created_at::date);
    v_end   := coalesce(public.try_cast_date(new.payload->>'endDate'), public.try_cast_date(new.payload->>'end_date'), v_start);
    if v_start is null then
      return new;
    end if;
    v_day := v_start;
    while v_day <= v_end and v_guard < 90 loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values (new.employee_id, v_day, 'present')
      on conflict (employee_id, work_date) do update
        set status = 'present'
        where attendance_daily.first_check_in is null
          and attendance_daily.status in ('absent', 'pending');
      v_day  := v_day + 1;
      v_guard := v_guard + 1;
    end loop;
  end if;
  return new;
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- 8) Backfill: Ensure all approved convoy/mission/fundraising days are present in attendance_daily
-- ─────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
  v_day date;
  v_end date;
  v_guard integer;
begin
  for r in
    select req.id, req.employee_id,
           coalesce(public.try_cast_date(req.payload->>'startDate'), public.try_cast_date(req.payload->>'start_date'), public.try_cast_date(req.payload->>'date'), req.created_at::date) as start_date,
           coalesce(public.try_cast_date(req.payload->>'endDate'), public.try_cast_date(req.payload->>'end_date'),
                    public.try_cast_date(req.payload->>'startDate'), public.try_cast_date(req.payload->>'start_date'), req.created_at::date) as end_date
      from public.requests req
     where req.status = 'approved'
       and (
         req.request_type in ('mission','convoy','fundraising','external_mission','field_convoy','fandy','fundi')
         or coalesce(req.payload->>'missionType', req.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy', 'fundi')
       )
       and coalesce(public.try_cast_date(req.payload->>'startDate'), public.try_cast_date(req.payload->>'start_date'), public.try_cast_date(req.payload->>'date'), req.created_at::date) is not null
  loop
    v_day   := r.start_date;
    v_end   := coalesce(r.end_date, r.start_date);
    v_guard := 0;
    while v_day <= v_end and v_guard < 90 loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values (r.employee_id, v_day, 'present')
      on conflict (employee_id, work_date) do update
        set status = 'present'
        where attendance_daily.first_check_in is null
          and attendance_daily.status in ('absent', 'pending');
      v_day := v_day + 1;
      v_guard := v_guard + 1;
    end loop;
  end loop;
end $$;

commit;
