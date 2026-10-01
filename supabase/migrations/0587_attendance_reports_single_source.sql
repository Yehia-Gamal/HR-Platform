-- =====================================================================
-- 0587: نسب الحضور في كل التقارير من مصدر واحد مطابق لكشف الحضور
--
--  1) كشف الحضور: أيام ما قبل تاريخ التعيين كانت تُعدّ «غائب دون إذن» (موظفة
--     عُيّنت 29/9 ظهر لها 24 يوم غياب في سبتمبر) → «قبل تاريخ التعيين» بلا غياب.
--  2) attendance_day_facts: حقائق كل (موظف × يوم) — يوم عمل؟ إجازة؟ ميداني؟ حضر؟
--     مستحق؟ غائب؟ دقائق تأخير — طابقت كشف الحضور في كل أيام سبتمبر (962 يوماً).
--  3) اتجاه الحضور (الهاتف) ولوحة التحليلات: كانا يعدّان حالات لا تُسجَّل
--     ('absent'، 'present_late') → غياب/تأخير صفر دائماً ويُسقطان المتأخر ومن لم
--     يسجل انصرافاً. الآن فئات منفصلة للرسم المكدّس. الهاتف: فحص صلاحية صريح.
--  4) الملخص الأسبوعي: كان حضور 100%/تأخر 0%/غياب 0% دائماً وقائمتاه فارغتين.
--  5) الموجز اليومي: الإجازة في المقام، والعدّ المزدوج، والجمعة/العطلة تُفرغ نص
--     الموجز كله (NULL) → مصحّحة.
--  6) مطابقة التأخير المخزَّن مع التعريف لأيام بصمت أثناء نشر 0586 (سباق نشر)،
--     دون تشغيل أي تريجر (لا غرامات ولا إشعارات).
-- =====================================================================

begin;

CREATE OR REPLACE FUNCTION public._build_attendance_statement(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_late_grace constant integer := 15;   -- فترة السماح (0576)
  c_late_cap   constant integer := 120;  -- حد احتساب التأخير (0576)
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
  select e.hire_date into v_hire_date from public.employees e where e.id = p_employee_id;
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    continue when v_day_obj is null or v_day_obj = 'null'::jsonb;

    v_day := (v_day_obj->>'date')::date;

    -- 0587: أيام ما قبل التعيين ليست أيام عمل مستحقة ولا غياباً (كانت تُعدّ
    -- «غائب دون إذن» لمن عُيّن في منتصف الشهر — 24 يوماً لموظفة عُيّنت 29/9)
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
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy', 'fundraising')
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

    -- ── تصنيف اليوم ──
    v_override_type := coalesce(v_day_obj->'adminOverride'->>'dayType', '');
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_override_type not in ('holiday', 'rest');
    v_on_leave := coalesce((v_day_obj->>'hasLeave')::boolean, false) and v_ci is null;
    v_offsite := coalesce((v_day_obj->>'hasMission')::boolean, false)
              or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_pending := v_status like 'بانتظار اعتماد%';
    v_exempt_day := v_status = 'معفى من الحضور';
    -- اليوم الجاري قبل نهاية الدوام بلا بصمة (v286: «بانتظار حضور») لا يُحتسب بعد
    v_waiting_today := v_day = v_today and v_ci is null and not v_is_absent and not v_offsite;
    v_expected := v_scheduled and v_day <= v_today and not v_on_leave and not v_pending
                  and not v_exempt_day and not v_waiting_today;
    v_attended := v_expected and (v_ci is not null or v_offsite);
    v_open_today := v_day = v_today and v_ci is not null and v_co is null;

    -- ── أعلام النقص من البيانات النهائية (بعد التعديلات الإدارية) ──
    v_missing_out := v_scheduled and v_day < v_today and v_ci is not null and v_co is null
                     and not v_offsite and not v_has_early_p and not v_pending_permit and not v_is_exempt;
    v_missing_in := v_scheduled and v_ci is null
                    and (v_co is not null or coalesce((v_day_obj->>'missingCheckIn')::boolean, false))
                    and not v_has_late_p and not v_pending_permit and not v_is_exempt;

    -- ── التأخير والخروج المبكر (أيام الدوام بالبصمة فقط) ──
    v_late := 0;
    v_early := 0;
    -- 0586: التأخير من الدالة نفسها التي تحسبه البصمة والغرامة (مصدر واحد)
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

    -- ── الساعات: أيام الدوام المستحقة (والمأمورية إن اكتملت بصمتاها) ──
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

    -- يوم ماضٍ بلا انصراف: v287 يسمّيه «بانتظار الانصراف» لكل الأيام
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

  return v_result;
end;
$function$;

-- ─── حقائق يوم الحضور: مصدر واحد للتقارير والاتجاهات (مطابق لكشف الحضور) ───
create or replace function public.attendance_day_facts(p_start date, p_end date)
returns table (
  employee_id uuid,
  work_date date,
  is_workday boolean,
  is_exempt boolean,
  leave_like boolean,
  offsite boolean,
  checked_in boolean,
  attended boolean,
  expected boolean,
  absent boolean,
  late_minutes integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  with now_local as (
    select (now() at time zone 'Africa/Cairo') as ts, (now() at time zone 'Africa/Cairo')::date as today
  ),
  shift as (
    select s.end_time from public.shifts s where s.id = public.default_shift_id()
  ),
  days as (
    select d::date as work_date from generate_series(p_start, p_end, interval '1 day') d
  ),
  emp as (
    select e.id, e.hire_date, public.is_employee_attendance_exempt(e.id) as exempt
    from public.employees e
    where e.is_active and not e.is_deleted
  ),
  base as (
    select e.id as employee_id, d.work_date, e.exempt, o.day_type as override_type,
      case
        when o.id is not null and (coalesce(o.clear_check_in, false)
             or o.day_type in ('leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest', 'absent')) then null
        when o.id is not null and o.check_in_override is not null
          then ((d.work_date + o.check_in_override)::timestamp at time zone 'Africa/Cairo')
        else ad.first_check_in
      end as check_in,
      ad.status as ad_status,
      coalesce(ad.late_minutes, 0) as ad_late,
      (extract(isodow from d.work_date) <> 5
        and not exists (
          select 1 from public.public_holidays h
          where coalesce(h.is_active, true)
            and d.work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
        and coalesce(o.day_type, '') not in ('holiday', 'rest')) as is_workday
    from emp e
    cross join days d
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = d.work_date
    left join public.attendance_day_overrides o on o.employee_id = e.id and o.work_date = d.work_date and o.is_active
    where e.hire_date is null or d.work_date >= e.hire_date
  ),
  flags as (
    select b.*,
      (coalesce(b.override_type, '') = 'leave' or coalesce(b.ad_status, '') = 'on_leave'
        or exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = b.employee_id and r.status not in ('rejected', 'cancelled')
            and b.work_date between lr.start_date and lr.end_date)
        or exists (
          select 1 from public.requests r
          where r.employee_id = b.employee_id and r.status not in ('rejected', 'cancelled')
            and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
            and b.work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                                and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                             public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')))
      ) as leave_flag,
      (coalesce(b.override_type, '') in ('mission', 'convoy', 'fundraising')
        or (b.override_type is null and exists (
          select 1 from public.requests r
          where r.employee_id = b.employee_id and r.status not in ('rejected', 'cancelled')
            and (r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy',
                                    'fundraising', 'fandy', 'fundi', 'remote_work')
                 or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission'))
            and b.work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                                and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                             public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))))
      ) as offsite_flag,
      exists (
        select 1 from public.requests r
        where r.employee_id = b.employee_id and r.status = 'pending'
          and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
          and coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'),
                       public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'workDate'),
                       r.created_at::date) = b.work_date
      ) as pending_permit
    from base b
  ),
  classified as (
    select f.*,
      (f.leave_flag and f.check_in is null) as is_leave,
      (f.check_in is not null or f.offsite_flag) as is_attended,
      (f.is_workday and not f.exempt
        and not (f.leave_flag and f.check_in is null)
        and not (f.pending_permit and f.check_in is null and not f.offsite_flag)
        and f.work_date <= (select today from now_local)
        and (f.work_date < (select today from now_local)
             or f.check_in is not null or f.offsite_flag
             or (select ts from now_local)::time > coalesce((select end_time from shift), '18:00'::time))
      ) as is_expected
    from flags f
  )
  select c.employee_id, c.work_date, c.is_workday, c.exempt, c.is_leave, c.offsite_flag,
         c.check_in is not null, c.is_attended, c.is_expected,
         c.is_expected and not c.is_attended,
         case when c.check_in is not null
              then public.attendance_policy_late_minutes(c.employee_id, c.work_date, c.check_in, null)
              else 0 end
  from classified c;
$fn$;
revoke execute on function public.attendance_day_facts(date, date) from public, anon, authenticated;
grant execute on function public.attendance_day_facts(date, date) to service_role;

create or replace function public.get_mobile_attendance_trend(p_days integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  -- 0587: كان يعدّ «حاضر» = present|partial فقط (يُسقط المتأخر ومن لم يسجل انصرافاً)
  -- و«غائب» = حالة absent التي لا تُسجَّل أبداً → غياب 0 دائماً. الآن من حقائق يوم
  -- الحضور، وفئات منفصلة للرسم المكدّس: حاضر في الموعد / متأخر / غائب.
  if not (public.current_is_full_access()
          or public.has_permission('reports.attendance.read')
          or public.current_has_active_role(array['executive', 'executive-director', 'general-manager', 'hr-manager'])) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(t order by t.work_date), '[]'::jsonb)
    from (
      select f.work_date,
        count(*) filter (where f.expected and f.attended and f.late_minutes = 0)::int as present,
        count(*) filter (where f.expected and f.attended and f.late_minutes > 0)::int as late,
        count(*) filter (where f.absent)::int as absent
      from public.attendance_day_facts(
             (now() at time zone 'Africa/Cairo')::date - greatest(p_days, 1) + 1,
             (now() at time zone 'Africa/Cairo')::date) f
      where not f.is_exempt
      group by f.work_date
      having count(*) filter (where f.is_workday) > 0
    ) t
  );
end
$fn$;
revoke execute on function public.get_mobile_attendance_trend(integer) from public, anon;
grant execute on function public.get_mobile_attendance_trend(integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_analytics_dashboard(p_months_back integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- بداية أسبوع العمل من السبت:
  -- في extract(dow): 0=أحد, 1=إثنين, 2=ثلاثاء, 3=أربعاء, 4=خميس, 5=جمعة, 6=سبت
  -- الإزاحة إلى السبت = (dow + 1) % 7
  v_week_start := v_today - ((extract(dow from v_today)::integer + 1) % 7);

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
    -- 0587: mv_monthly_request_stats لا يحوي عمود cancelled فكانت الدالة كلها
    -- تفشل (42703) وصفحة التحليلات معطلة لكل المستخدمين → العدّ من الطلبات مباشرة.
    select
      date_trunc('month', r.created_at)::date as month,
      count(*) filter (where r.status = 'approved')  as approved,
      count(*) filter (where r.status = 'rejected')  as rejected,
      count(*) filter (where r.status = 'pending')   as pending,
      count(*) filter (where r.status = 'cancelled') as cancelled
    from public.requests r
    where r.created_at >= v_from_month
    group by date_trunc('month', r.created_at)
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

  -- ── 3. اتجاه الحضور (أيام العمل في الأسبوع الحالي من السبت حتى اليوم) ──
  -- 0587: كان يعدّ حالات لا تُسجَّل أبداً ('present_late'، 'absent') فالتأخير
  -- والغياب صفر دائماً ويُسقط المتأخر ومن لم يسجل انصرافاً. الآن من حقائق يوم
  -- الحضور، بفئات منفصلة للرسم المكدّس (حاضر في الموعد / متأخر / غائب).
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',    to_char(w.work_date, 'Dy'),
        'date',    w.work_date,
        'present', w.present_count,
        'late',    w.late_count,
        'absent',  w.absent_count
      )
      order by w.work_date
    ),
    '[]'::jsonb
  )
  into v_attendance
  from (
    select f.work_date,
      count(*) filter (where f.expected and f.attended and f.late_minutes = 0) as present_count,
      count(*) filter (where f.expected and f.attended and f.late_minutes > 0) as late_count,
      count(*) filter (where f.absent) as absent_count
    from public.attendance_day_facts(v_week_start, v_today) f
    where not f.is_exempt and extract(isodow from f.work_date) <> 5
    group by f.work_date
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

  -- 0587: كان يعدّ حالات attendance_daily 'late'/'absent' التي لا تُسجَّل (الغياب
  -- صف غير موجود) → حضور 100% وتأخر 0% وغياب 0% دائماً، وقائمتا «أكثر تأخراً»
  -- و«غياب > 3 أيام» فارغتان. الآن من حقائق يوم الحضور (مطابقة لكشف الحضور):
  -- المقام = أيام العمل المستحقة (بعد الإجازات)، والحاضر يشمل الميداني.
  select count(*) into v_total_emp
  from public.employees e
  where e.is_active = true and e.is_deleted = false and e.status = 'active'
    and not public.is_employee_attendance_exempt(e.id);

  with f as (
    select * from public.attendance_day_facts(v_start, v_end) where not is_exempt
  ), c as (
    select
      count(*) filter (where expected) as expected_days,
      count(*) filter (where expected and attended and late_minutes = 0) as present_on_time,
      count(*) filter (where expected and attended and late_minutes > 0) as late_days,
      count(*) filter (where absent) as absent_days,
      count(*) filter (where is_workday and leave_like) as leave_days,
      count(*) filter (where not is_workday and extract(isodow from work_date) <> 5) as holiday_days,
      count(*) filter (where extract(isodow from work_date) = 5) as weekend_days,
      coalesce(sum(late_minutes) filter (where expected and attended), 0) as late_minutes_total
    from f
  )
  select jsonb_build_object(
    'startDate',       v_start,
    'endDate',         v_end,
    'periodId',        v_period_id,
    'activeEmployees', v_total_emp,
    'totalDayRecords', c.expected_days + c.leave_days,
    'present',         c.present_on_time,
    'late',            c.late_days,
    'absent',          c.absent_days,
    'onLeave',         c.leave_days,
    'holiday',         c.holiday_days,
    'weekend',         c.weekend_days,
    'partial',         0,
    'totalLateMinutes', c.late_minutes_total,
    'totalEarlyLeaveMinutes', 0,
    'totalOvertimeMinutes', 0,
    'workdayRecords',  c.expected_days,
    'attendanceRate',  case when c.expected_days = 0 then 0
                            else round(100.0 * (c.present_on_time + c.late_days) / c.expected_days, 2) end,
    'presentRate',     case when c.expected_days = 0 then 0
                            else round(100.0 * (c.present_on_time + c.late_days) / c.expected_days, 2) end,
    'lateRate',        case when c.expected_days = 0 then 0
                            else round(100.0 * c.late_days / c.expected_days, 2) end,
    'absentRate',      case when c.expected_days = 0 then 0
                            else round(100.0 * c.absent_days / c.expected_days, 2) end,
    'onLeaveRate',     case when c.expected_days + c.leave_days = 0 then 0
                            else round(100.0 * c.leave_days / (c.expected_days + c.leave_days), 2) end
  ) into v_summary
  from c;

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
    select e.id as employee_id, e.full_name_ar, e.employee_code, d.name as department,
           count(*) filter (where f.expected and f.attended and f.late_minutes > 0) as late_days,
           coalesce(sum(f.late_minutes) filter (where f.expected and f.attended), 0) as total_late_minutes
    from public.attendance_day_facts(v_start, v_end) f
    join public.employees e on e.id = f.employee_id
    left join public.departments d on d.id = e.department_id
    where not f.is_exempt
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where f.expected and f.attended and f.late_minutes > 0) > 0
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
    select e.id as employee_id, e.full_name_ar, e.employee_code, d.name as department,
           count(*) filter (where f.absent) as absent_days
    from public.attendance_day_facts(v_start, v_end) f
    join public.employees e on e.id = f.employee_id
    left join public.departments d on d.id = e.department_id
    where not f.is_exempt
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where f.absent) > 3
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

CREATE OR REPLACE FUNCTION public.generate_executive_daily_digest(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_day_name text;
  v_total_active int := 0;
  v_present int := 0;
  v_missions int := 0;
  v_convoys int := 0;
  v_fandy int := 0;
  v_leaves int := 0;
  v_absent int := 0;
  v_penalties_issued int := 0;
  v_penalties_issued_amount numeric(12,2) := 0.00;
  v_penalties_paid int := 0;
  v_penalties_paid_amount numeric(12,2) := 0.00;
  v_fund_balance numeric(12,2) := 0.00;
  v_missions_list text := '';
  v_text text;
begin
  -- أسماء الأيام بالعربية
  v_day_name := case extract(isodow from v_date)
    when 1 then 'الاثنين'
    when 2 then 'الثلاثاء'
    when 3 then 'الأربعاء'
    when 4 then 'الخميس'
    when 5 then 'الجمعة'
    when 6 then 'السبت'
    when 7 then 'الأحد'
  end;
  -- 0587: من حقائق يوم الحضور. كان المقام يشمل من في إجازة معتمدة (فيُخفض
  -- الانضباط)، ومن بصم في يوم مأمورية يُعدّ مرتين (قد تتجاوز النسبة 100%)، والجمعة
  -- والعطلات تُظهر نسبة قرب الصفر. «القوة الملزمة» = من عليه دوام اليوم بعد الإجازات
  -- (بمن فيهم من لم يحضر بعد)، و«الانضباط» = من حضر أو في الميدان منهم.
  select
    count(*) filter (where f.is_workday and not f.leave_like),
    count(*) filter (where f.checked_in),
    count(*) filter (where f.offsite and not f.checked_in),
    count(*) filter (where f.is_workday and f.leave_like)
  into v_total_active, v_present, v_missions, v_leaves
  from public.attendance_day_facts(v_date, v_date) f
  where not f.is_exempt;
  v_convoys := 0;
  v_fandy := 0;
  v_absent := greatest(0, v_total_active - v_present - v_missions);
  -- الغرامات الصادرة والمدفوعة لهذا اليوم
  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_issued, v_penalties_issued_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status in ('pending_payment', 'doubled', 'paid');
  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_paid, v_penalties_paid_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status = 'paid';
  -- رصيد صندوق الزمالة الحالي
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0.00)
    into v_fund_balance
    from public.fellowship_fund_transactions;
  -- تجميع أسماء أبرز المتواجدين في مهام ميدانية
  select string_agg('• ' || e.full_name_ar || ' (' || coalesce(q.request_type, 'مهمة') || ')', E'\n')
    into v_missions_list
    from (
      select distinct r.employee_id, r.request_type
        from public.requests r
       where r.request_type in ('mission', 'convoy', 'fundraising')
         and r.status = 'approved'
         and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date)
       limit 5
    ) q
    join public.employees e on e.id = q.employee_id;
  -- صياغة النص التنفيذي المنمق الموجه للإدارة العليا
  v_text :=
    '🌟 *موجز العمليات اليومي — مؤسسة أحلى شباب*' || E'\n' ||
    '📅 *اليوم:* ' || v_day_name || ' ' || to_char(v_date, 'YYYY/MM/DD') || E'\n' ||
    '⏰ *التحديث:* ' || to_char((now() at time zone 'Africa/Cairo'), 'HH12:MI AM') || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '👥 *مؤشرات القوة العاملة والانضباط:*' || E'\n' ||
    '• إجمالي القوة الملزمة: ' || v_total_active || ' موظف' || E'\n' ||
    '• الحضور الفعلي المسجل: ' || v_present || ' زميل ✅' || E'\n' ||
    '• الميدان والقوافل: ' || (v_missions + v_convoys + v_fandy) || ' زميل 🚚' || E'\n' ||
    '• الإجازات المعتمدة: ' || v_leaves || ' زميل 🏖️' || E'\n' ||
    '• نسبة الانضباط العام: ' || coalesce(round(((v_present + v_missions + v_convoys + v_fandy)::numeric / nullif(v_total_active, 0)) * 100, 1)::text || '%', 'لا دوام اليوم (عطلة)') || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '💰 *الموقف المالي وصندوق الزمالة والتكافل:*' || E'\n' ||
    '• غرامات التأخير الصادرة: ' || v_penalties_issued || ' (' || v_penalties_issued_amount || ' ج.م)' || E'\n' ||
    '• المحصل والمودع بالصندوق: ' || v_penalties_paid || ' (' || v_penalties_paid_amount || ' ج.م) 🪙' || E'\n' ||
    '• الرصيد الإجمالي التراكمي للصندوق: ' || v_fund_balance || ' ج.م 🏦' || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    case when v_missions_list is not null and v_missions_list <> '' then
      '📍 *الفرق الميدانية في القوافل والمأموريات:*' || E'\n' || v_missions_list || E'\n' || '━━━━━━━━━━━━━━━━━━━━' || E'\n'
    else '' end ||
    '✨ *دمتم ذخراً لشباب الخير وعمار الأرض* 🌿';
  return jsonb_build_object(
    'date', v_date,
    'dayName', v_day_name,
    'totalActive', v_total_active,
    'present', v_present,
    'fieldMissions', (v_missions + v_convoys + v_fandy),
    'leaves', v_leaves,
    'absent', v_absent,
    'penaltiesIssued', v_penalties_issued,
    'penaltiesIssuedAmount', v_penalties_issued_amount,
    'penaltiesPaid', v_penalties_paid,
    'penaltiesPaidAmount', v_penalties_paid_amount,
    'fundBalance', v_fund_balance,
    'digestText', v_text
  );
end;
$function$;

-- ─── 6) مطابقة التأخير المخزَّن (دون تريجرات) ───────────────────────────
set local session_replication_role = replica;

with calc as (
  select ad.id,
         public.attendance_policy_late_minutes(
           ad.employee_id, ad.work_date,
           case
             when o.id is not null and o.clear_check_in then null
             when o.id is not null and o.check_in_override is not null
               then ((ad.work_date + o.check_in_override)::timestamp at time zone 'Africa/Cairo')
             else ad.first_check_in
           end,
           ad.shift_id) as late
  from public.attendance_daily ad
  left join public.attendance_day_overrides o
    on o.employee_id = ad.employee_id and o.work_date = ad.work_date and o.is_active
  where ad.first_check_in is not null or o.check_in_override is not null
)
update public.attendance_daily ad
   set late_minutes = c.late,
       status = case
         when ad.status = 'present' and c.late > 0 then 'late'
         when ad.status = 'late' and c.late = 0 then 'present'
         else ad.status end
  from calc c
 where c.id = ad.id
   and (ad.late_minutes is distinct from c.late
        or (ad.status = 'present' and c.late > 0)
        or (ad.status = 'late' and c.late = 0));

set local session_replication_role = origin;

commit;
