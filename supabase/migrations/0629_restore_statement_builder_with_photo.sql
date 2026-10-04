-- 0629: إصلاح عاجل — الكشف الشهري للحضور معطّل لكل الموظفين منذ تطبيق 0627
-- ===========================================================================
-- 0627 (مطبّقة يدويًا ~15:12 بتوقيت القاهرة) أعادت تعريف
-- _build_attendance_statement_v186 (أساس سلسلة الكشف الحية) من نسخة قديمة:
--   • public.official_holidays غير موجود → 42P01 لكل يوم غير الجمعة، أي فشل
--     الكشف لكل موظف (التطبيق يُظهره 404، والرئيسية تعيد المحاولة بلا توقف)؛
--   • وأسقطت إصلاحات لاحقة: الإعفاء (is_attendance_exempt)، المدير عبر كل علاقات
--     الإدارة، الوردية الافتراضية، الساعات المطلوبة الافتراضية، شرط العطلات (0622)؛
--   • وغيّرت مفاتيح كائن employee (code→employeeCode، name→fullNameAr) التي
--     تقرؤها الواجهات.
--
-- الإصلاح: استبدال كنوني كامل = نسخة 0622 المنشورة سابقًا حرفيًا + قصد 0627
-- الوحيد: photo_url في كائن employee (مفتاح photoUrl) دون تغيير المفاتيح القائمة.
-- ===========================================================================

begin;

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
  v_temp_type text;
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

    -- 2) عطلة رسمية؟ — 0622: نفس شرط attendance_day_facts (النشاط ومدى الأيام)،
    -- والحالة الحرفية «عطلة رسمية» لأن v251/v266 تتعرّف على العطلة بها؛ اسم
    -- العطلة كحالة جعلها تُعامَل يوم عمل فيُكتب الغائب «غائب دون إذن».
    -- (كانت تقرأ public_holidays.name_ar غير الموجود فتُسقط الكشف كله.)
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

      -- أ) تكليف عمل (work_assignments)
      if exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id
          and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at at time zone 'Africa/Cairo')::date
      ) then
        v_status := coalesce(
          (select case wa.assignment_type
                    when 'MISSION' then 'مأمورية عمل'
                    when 'CONVOY' then 'قافلة'
                    when 'FUNDRAISING' then 'فاندي'
                  end
            from public.work_assignment_participants wp
            join public.work_assignments wa on wa.id = wp.assignment_id
            where wp.employee_id = p_employee_id
              and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
              and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                            and (wa.end_at at time zone 'Africa/Cairo')::date
            limit 1),
          'مأمورية عمل');
        if v_status = 'مأمورية عمل' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;

      -- ب) مأمورية قديمة (missions table)?
      elsif exists (
        select 1 from public.missions m
        join public.requests r on r.id = m.request_id
        where m.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
          and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                        and (m.end_at at time zone 'Africa/Cairo')::date
      ) then
        v_status := 'مأمورية عمل';
        v_mission_days := v_mission_days + 1;

      -- ج) مأمورية / قافلة / فاندي من جدول requests (معتمدة أو مسجلة قيد المراجعة)
      elsif exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id
          and r.status not in ('rejected', 'cancelled')
          and (
            r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
            or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
          )
          and coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date) is not null
          and v_day between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
      ) then
        select case
                 when r.request_type in ('convoy', 'field_convoy') or coalesce(r.payload->>'missionType', '') = 'convoy' then 'قافلة'
                 when r.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(r.payload->>'missionType', '') = 'fundraising' then 'فاندي'
                 else 'مأمورية عمل'
               end || case when r.status = 'pending' then ' (قيد الاعتماد)' else '' end,
               r.request_type
          into v_status, v_temp_type
          from public.requests r
         where r.employee_id = p_employee_id
           and r.status not in ('rejected', 'cancelled')
           and (
             r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
             or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
           )
           and coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date) is not null
           and v_day between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                         and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
         order by r.created_at desc
         limit 1;

        if v_status like '%مأمورية%' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;

      -- د) إجازة معتمدة أو مسجلة قيد المراجعة؟
      elsif v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
          and v_day between lr.start_date and lr.end_date
      ) or exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
          and coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date) is not null
          and v_day between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
      ) then
        select 'إجازة' || case when r.status = 'pending' then ' (قيد الاعتماد)' else ' معتمدة' end
          into v_status
          from public.requests r
         where r.employee_id = p_employee_id
           and r.status not in ('rejected', 'cancelled')
           and (
             r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
             or exists (select 1 from public.leave_requests lr where lr.request_id = r.id and v_day between lr.start_date and lr.end_date)
           )
         order by r.created_at desc
         limit 1;
        v_status := coalesce(v_status, 'إجازة معتمدة');
        v_leave_days := v_leave_days + 1;

      -- هـ) حاضر / متأخر / جزئي / غائب
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

    -- 4) فحص أذونات الحضور والتأخير (late_permit) والانصراف المبكر (early_permit)
    --    من جدول requests الموحّد وجدول attendance_permits
    v_has_late_permit := exists(
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          r.request_type in ('late_permit', 'permission', 'errand', 'late_excuse')
          or (r.request_type = 'permit' and coalesce(r.payload->>'permitKind', 'late_arrival') = 'late_arrival')
        )
        and coalesce(
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
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
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
          r.created_at::date
        ) = v_day
    ) or exists(
      select 1 from public.attendance_permits p
      where p.employee_id = p_employee_id and p.permit_date = v_day
        and p.status in ('approved', 'pending') and p.kind = 'departure'
    );

    if v_has_late_permit or v_has_early_permit then
      v_permit_count := v_permit_count + 1;
      -- إذا كان اليوم مسجلاً كغياب ولكن الموظف لديه إذن حضور، نعدل الحالة ونلغي الغياب
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

    -- 7) نسيان ختم (فقط إذا لم يكن هناك إذن ولا مأمورية ولا إجازة ولا إعفاء)
    if v_row.id is not null and v_row.status not in ('on_leave','holiday','weekend')
       and v_status not like '%عطلة%' and v_status not like '%راحة%'
       and v_status not like '%إجازة%' and v_status not like '%مأمورية%'
       and v_status not like '%قافلة%' and v_status not like '%فاندي%'
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
      'hasLeave', (v_status like '%إجازة%'),
      'hasLatePermit', v_has_late_permit,
      'hasEarlyPermit', v_has_early_permit,
      'hasPermit', (v_has_late_permit or v_has_early_permit),
      'hasMission', (v_status like '%مأمورية%'),
      'hasConvoyFundi', (v_status like '%قافلة%' or v_status like '%فاندي%'),
      -- منع احتساب نسيان البصمة لأي موظف لديه إذن أو إجازة أو مأمورية أو إعفاء
      'missingCheckIn', (
        v_row.first_check_in is null
        and v_row.id is not null
        and v_row.status not in ('absent','on_leave','holiday','weekend')
        and v_status not like '%عطلة%' and v_status not like '%راحة%'
        and v_status not like '%إجازة%' and v_status not like '%مأمورية%'
        and v_status not like '%قافلة%' and v_status not like '%فاندي%'
        and v_status not like '%معفى%' and v_status <> 'إذن حضور مسجل'
        and not v_has_late_permit
        and not v_is_exempt
      ),
      'missingCheckOut', (
        v_row.last_check_out is null
        and v_row.first_check_in is not null
        and not v_has_early_permit
        and not v_is_exempt
        and v_status not like '%مأمورية%'
        and v_status not like '%قافلة%'
        and v_status not like '%فاندي%'
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

commit;
