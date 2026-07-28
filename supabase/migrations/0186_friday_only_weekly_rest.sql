-- 0186: تغيير أيام الراحة الأسبوعية — الجمعة فقط (السبت يوم عمل عادي)
-- السبت هو بداية الأسبوع. أيام العمل: السبت–الخميس (isodow 6,7,1,2,3,4).
-- يوم الراحة الوحيد: الجمعة (isodow = 5).
-- يُعدّل دالتين:
--   1) _build_attendance_statement — كشف الحضور الشهري
--   2) generate_punch_reminders   — تذكيرات البصمة
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) _build_attendance_statement: الجمعة فقط راحة أسبوعية
-- ─────────────────────────────────────────────────────────────────────────────

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

      -- إجازة معتمدة؟
      if v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id and r.status = 'approved'
          and v_day between lr.start_date and lr.end_date
      ) then
        v_status := 'إجازة معتمدة';
        v_leave_days := v_leave_days + 1;
      -- مأمورية عمل (work_assignments)?
      elsif exists (
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
      -- مأمورية قديمة (missions table)?
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
end $$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0186: الجمعة فقط راحة أسبوعية (السبت يوم عمل). V23 §14 حقول مفصّلة.';

revoke execute on function public._build_attendance_statement(uuid, integer, integer) from public, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) generate_punch_reminders: الجمعة فقط عطلة (السبت يوم عمل)
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
  '0186: الجمعة فقط عطلة. V10 تذكيرات البصمة مع استثناء المدير التنفيذي.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث working_calendars الافتراضية: الجمعة فقط عطلة
-- ─────────────────────────────────────────────────────────────────────────────

-- تغيير القيمة الافتراضية
alter table public.working_calendars
  alter column weekly_off_days set default '{5}'::integer[],
  alter column working_weekdays set default '{1,2,3,4,6,7}'::integer[];

-- تحديث السجلات الحالية التي لا تزال على الإعداد القديم
update public.working_calendars
set weekly_off_days = '{5}'::integer[],
    working_weekdays = '{1,2,3,4,6,7}'::integer[],
    updated_at = now()
where weekly_off_days = '{5,6}'::integer[];

commit;
