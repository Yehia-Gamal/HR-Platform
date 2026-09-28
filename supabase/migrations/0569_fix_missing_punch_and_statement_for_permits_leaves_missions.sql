-- =====================================================================
-- 0569: منع وسم نسيان البصمة (missingCheckIn / missingCheckOut)
--       لأصحاب أذونات الحضور والانصراف والإجازات والمأموريات والمعفيين
-- =====================================================================
-- المشاكل المعالجة:
-- 1. في كشف الحضور الشهري (سلسلة _build_attendance_statement)، كان النظام
--    يفحص جدول attendance_permits وهو فارغ، بدلاً من فحص جدول requests الموحّد
--    الذي تُحفظ فيه أذونات الحضور (late_permit) والانصراف (early_permit).
-- 2. ونتيجة لذلك، كان يعتبر إذن الحضور معدوماً، ويعتبر اليوم "غائب دون إذن"
--    و"نسيان بصمة حضور" (missingCheckIn = true) ويزيد عداد نسيان الحضور،
--    ويُظهر للموظف في التطبيق "لديك بصمات تحتاج لتصحيح / نسيان بصمة حضور"!
-- 3. كما كانت الدوال الفرعية v251 و v266 تُعيد فرض missingCheckIn = true
--    وتتجاهل أذونات الحضور والإعفاءات الإدارية.
-- 4. كما أن آلية تصفية الانصراف الليلية finalize_missing_checkouts كانت تسجل
--    "بصمة خروج مفقودة" حتى لمن لديه إذن انصراف أو إعفاء من الحضور.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) إعادة بناء دالة الكشف الشهري الأساسية _build_attendance_statement_v186
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
    e.hire_date, e.birth_date, e.is_attendance_exempt,
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

    -- 2) عطلة رسمية؟
    elsif exists (select 1 from public.public_holidays where holiday_date = v_day) then
      v_status := coalesce(
        (select name_ar from public.public_holidays where holiday_date = v_day limit 1),
        'عطلة رسمية');
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
-- 2) تحديث دالة _build_attendance_statement_v251
--    لضمان عدم وسم نسيان البصمة أو الغياب لمن لديه إذن أو إعفاء
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
        -- يوم معذور/مستثنى (إجازة، مأمورية، إذن حضور/انصراف، إعفاء إداري)
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
        end if;
      else
        -- يوم عمل عادي غير معفى
        if v_daily.first_check_in is not null then
          v_is_due := true;
          v_present_days := v_present_days + 1;

          if v_daily.last_check_out is not null then
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes :=
              v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
          elsif v_now_local <= v_shift_end_at then
            v_is_open := true;
            v_open_shift_days := v_open_shift_days + 1;
            v_status := 'حاضر — بانتظار الانصراف';
          else
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
           and v_now_local > v_shift_end_at then
          v_missing_in := true;
          v_missing_checkin := v_missing_checkin + 1;
        end if;

        v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
        v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
        v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
        v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

        if v_daily.last_check_out is not null
           or v_now_local > v_shift_end_at then
          v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
          v_compliance_work_minutes :=
            v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
        end if;
      end if;
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'shiftName', coalesce(v_shift_name, ''),
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'requiredHours', round(v_scheduled_minutes / 60.0, 2),
      'status', v_status,
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'missingCheckIn', (v_missing_in and not v_has_late_p and not v_is_exempt),
      'missingCheckOut', (v_missing_out and not v_has_early_p and not v_is_exempt),
      'notes', case
        when v_is_open then 'لم تسجل حضورك في الوردية وهي زالت مفتوحة'
        else v_day_obj->>'notes'
      end
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_presence_days > 0
        then round(v_completed_work_minutes / 60.0 / v_completed_presence_days, 2)
        else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'attendanceRate', case when v_due_days > 0
        then round(v_present_days * 100.0 / v_due_days, 2)
        else 0 end,
      'hoursComplianceAvailable', (v_total_required_minutes > 0),
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_compliance_work_minutes * 100.0 / v_total_required_minutes, 2))
        else 0 end
    )
  );

  return v_result;
end
$function$;

revoke all on function public._build_attendance_statement_v251(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v251(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) تحديث دالة _build_attendance_statement_v252
--    لقراءة الأذونات من جدول requests الموحّد ومنع وسم missingCheckIn
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
     order by lr.start_date desc
     limit 1;

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
         (r.payload->>'permitDate')::date,
         (r.payload->>'date')::date,
         (r.payload->>'startDate')::date,
         (r.payload->>'workDate')::date,
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

    -- 5) Still-missing punches (مع منع الوسم إذا كان هناك إذن أو إعفاء)
    v_missing := jsonb_build_object(
      'checkIn',  coalesce((v_day_obj->>'missingCheckIn')::boolean,  false) and not v_has_late_p and not v_is_exempt,
      'checkOut', coalesce((v_day_obj->>'missingCheckOut')::boolean, false) and not v_has_early_p and not v_is_exempt
    );

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
-- 4) تحديث دالة _build_attendance_statement_v266
--    لضمان عدم وسم نسيان البصمة لأصحاب الأذونات والإعفاءات
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
        end if;
      else
        if v_daily.first_check_in is not null then
          v_present_days := v_present_days + 1;

          if v_daily.last_check_out is not null then
            v_is_due := true;
            v_is_completed := true;
            v_completed_presence_days := v_completed_presence_days + 1;
            v_completed_work_minutes :=
              v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
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
           and v_now_local > v_shift_end_at then
          v_missing_in := true;
          v_missing_checkin := v_missing_checkin + 1;
        end if;

        v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
        v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
        v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
        v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

        if v_daily.last_check_out is not null
           or v_now_local > v_shift_end_at then
          v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
          v_compliance_work_minutes :=
            v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
        end if;
      end if;
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'shiftName', coalesce(v_shift_name, ''),
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'requiredHours', round(v_scheduled_minutes / 60.0, 2),
      'status', v_status,
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'missingCheckIn', (v_missing_in and not v_has_late_p and not v_is_exempt),
      'missingCheckOut', (v_missing_out and not v_has_early_p and not v_is_exempt)
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_presence_days > 0
        then round(v_completed_work_minutes / 60.0 / v_completed_presence_days, 2)
        else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'attendanceRate', case when v_due_days > 0
        then round(
               ((v_present_days - v_open_shift_days) * 100.0) / v_due_days,
               2
             )
        else 0 end,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', (v_present_days - v_open_shift_days),
        'dueDays',      v_due_days,
        'presentDays',  v_present_days,
        'absentDays',   v_absent_days,
        'openShiftDays', v_open_shift_days,
        'upcomingDays', v_upcoming_days
      ),
      'hoursComplianceAvailable', (v_total_required_minutes > 0),
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_compliance_work_minutes * 100.0 / v_total_required_minutes, 2))
        else 0 end,
      'compliantWorkMinutes', v_compliance_work_minutes,
      'requiredMinutes', v_total_required_minutes
    )
  );

  return v_result;
end
$function$;

revoke all on function public._build_attendance_statement_v266(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement_v266(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث دالة _build_attendance_statement النهائية
--    لمعالجة الطلبات المعلقة لأذونات الحضور وضمان دقة العرض العربي
-- ─────────────────────────────────────────────────────────────────────
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
  v_pending_permit boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
  v_is_exempt boolean;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';
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
    v_pending_permit := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
        and r.status = 'pending'
        and coalesce(
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
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
      'hasPendingConvoyFundi', v_pending_convoy,
      'hasPendingPermit', v_pending_permit,
      -- ضمان قاطع بعدم وسم نسيان الحضور/الانصراف لأصحاب الأذونات أو الإعفاءات
      'missingCheckIn', (coalesce((v_day_obj->>'missingCheckIn')::boolean, false) and not v_has_late_p and not v_pending_permit and not v_is_exempt),
      'missingCheckOut', (coalesce((v_day_obj->>'missingCheckOut')::boolean, false) and not v_has_early_p and not v_pending_permit and not v_is_exempt)
    ));

    if v_day_obj is not null then
      v_days := v_days || jsonb_build_array(v_day_obj);
    end if;
  end loop;

  v_absent_days := (select count(*)::int
    from jsonb_array_elements(v_days) d
    where d is not null and coalesce((d->>'isAbsent')::boolean, false));

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'missingCheckInCount', (
        select count(*)::int from jsonb_array_elements(v_days) d
        where coalesce((d->>'missingCheckIn')::boolean, false)
      ),
      'missingCheckOutCount', (
        select count(*)::int from jsonb_array_elements(v_days) d
        where coalesce((d->>'missingCheckOut')::boolean, false)
      ),
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
end;
$$;

revoke all on function public._build_attendance_statement(uuid, integer, integer) from public, anon;
grant execute on function public._build_attendance_statement(uuid, integer, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 6) تحديث دالة finalize_missing_checkouts لمنع وسم نسيان الانصراف
--    للمعفيين أو لأصحاب إذن الانصراف أو المأموريات
-- ─────────────────────────────────────────────────────────────────────
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
      -- استثناء المعفيين دائماً من الحضور
      and not public.is_employee_attendance_exempt(ad.employee_id)
      -- استثناء من لديه إذن انصراف مبكر أو تصريح رسمي
      and not exists (
        select 1 from public.requests r
        where r.employee_id = ad.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('early_permit', 'permit')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = ad.work_date
      )
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف = عمل خارجي → لا يُصفّى كنقص انصراف
      and not exists (
        select 1 from public.requests r
        where r.employee_id = ad.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
          and ad.work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                               and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
      )
      and not exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = ad.employee_id
          and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
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

        v_count := v_count + 1;
      end if;
    end if;
  end loop;

  return v_count;
end;
$function$;

revoke all on function public.finalize_missing_checkouts() from public, anon;
grant execute on function public.finalize_missing_checkouts() to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 7) تنظيف الاستثناءات الخاطئة الناتجة عن نقص الحضور/الانصراف لأصحاب الإعفاءات أو الأذونات
-- ─────────────────────────────────────────────────────────────────────
delete from public.attendance_exceptions ae
where ae.kind in ('missing_check_in', 'missing_check_out')
  and (
    public.is_employee_attendance_exempt(ae.employee_id)
    or exists (
      select 1 from public.requests r
      where r.employee_id = ae.employee_id
        and r.status not in ('rejected', 'cancelled')
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
        and coalesce(
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
          r.created_at::date
        ) = ae.work_date
    )
    or exists (
      select 1 from public.requests r
      where r.employee_id = ae.employee_id
        and r.status not in ('rejected', 'cancelled')
        and r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
        and ae.work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                             and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
    )
  );

commit;
