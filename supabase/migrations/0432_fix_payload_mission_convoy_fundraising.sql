-- migration: 0431
-- description: إصلاح جذري لتعليم أيام المأموريات/القوافل/فاندي المعتمدة كأيام عمل
--              + backfill لكل الطلبات المعتمدة الموجودة (قديمة وجديدة)
-- -----------------------------------------------------------------------------
-- السبب الجذري المكتشف (بيانات الإنتاج):
--   * طلبات المأموريات/القوافل/فاندي تُخزّن تواريخها في requests.payload
--     (startDate/endDate) وليس في جداول missions/convoy_requests.
--   * tg_leave_attendance_on_approval (0429) كان يقرأ من الجدولين فقط → لم يعلّم
--     أي أيام → تظهر الأيام غياباً في الكشف الشهري رغم الاعتماد.
--   * الطلبات المعتمدة قبل 0429 لم يكن لها backfill أصلاً.
--   * ترتيب الفحوصات في _build_attendance_statement_v186 كان يعرض الـ on_leave
--     كـ "إجازة معتمدة" قبل التحقق من المأمورية/القافلة/فاندي.
-- الإصلاح:
--   1) _payload_date(): استخراج آمن لتاريخ من payload (يدعم YYYY-MM-DD و ISO).
--   2) tg_leave_attendance_on_approval: fallback إلى payload لـ mission/convoy
--      + فرع جديد كامل لـ fundraising (من payload).
--   3) backfill: تعليم كل الطلبات المعتمدة (leave/mission/convoy/fundraising)
--      الحالية كـ on_leave في attendance_daily (بدون لمس الصفوف المجمّدة).
--   4) _build_attendance_statement_v186: إعادة ترتيب الفحوصات — المأمورية/القافلة/
--      فاندي (تكليفات ثم جدول ثم payload) قبل الإجازة، فلا يظهر أي يوم عمل معتمد
--      غياباً ولا يُصنَّف "إجازة معتمدة" خطأً.
-- ملاحظة: backfill يعلّم الأيام فقط ولا يمنح أرصدة بدل راحة بأثر رجعي
--         (قرار مالي يبقى للإدارة).

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) دالة مساعدة: استخراج تاريخ من payload (يتحمل YYYY-MM-DD أو ISO timestamp)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public._payload_date(p jsonb, k text)
returns date
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select case
    when p is null or (p->>k) is null then null
    when (p->>k) ~ '^\s*\d{4}-\d{2}-\d{2}' then (substring(p->>k from '\d{4}-\d{2}-\d{2}'))::date
    else null
  end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) التريغر: مأمورية/قافلة/فاندي — جدول مخصص إن وُجد، وإلا payload
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_leave_attendance_on_approval()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_lr public.leave_requests; v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
begin
  if old.status = new.status then return new; end if;

  -- إجازة معتمدة: تعليم أيام الطلب كـ on_leave (منذ 0429)
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values(v_lr.employee_id, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'تم تعليم أيام الإجازة المعتمدة كـ on_leave في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- مأمورية/قافلة/فاندي معتمدة: تعليم الأيام (بلا خصم من الرصيد)
  if new.request_type in ('mission','convoy','fundraising') and new.status = 'approved' then
    v_emp := new.employee_id;
    v_start_ts := null;
    v_end_ts := null;
    if new.request_type = 'mission' then
      select start_at, end_at into v_start_ts, v_end_ts
      from public.missions where request_id = new.id;
    elsif new.request_type = 'convoy' then
      select departure_at, coalesce(return_at, departure_at) into v_start_ts, v_end_ts
      from public.convoy_requests where request_id = new.id;
    end if;

    if v_start_ts is null then
      -- مصدر الطلبات الحالية: payload (startDate/endDate)
      v_start := public._payload_date(new.payload, 'startDate');
      v_end := coalesce(public._payload_date(new.payload, 'endDate'), v_start);
    else
      v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
      v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    end if;

    if v_emp is null or v_start is null then
      return new; -- لا بيانات مصدرية للطلب → لا تعليم
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values(v_emp, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
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
      'تم تعليم أيام ' || new.request_type || ' المعتمدة كـ on_leave في الحضور (بلا خصم)',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3) Backfill: تعليم كل الطلبات المعتمدة الحالية (قديمة وجديدة)
--    بدون منح أرصدة بأثر رجعي (قرار مالي للإدارة)
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  r record;
  v_emp uuid;
  v_start date;
  v_end date;
  v_day date;
begin
  for r in
    select rq.id, rq.request_type, rq.employee_id, rq.payload,
           lr.employee_id as lr_emp, lr.start_date as lr_start, lr.end_date as lr_end
      from public.requests rq
      left join public.leave_requests lr on lr.request_id = rq.id
     where rq.status = 'approved'
       and rq.request_type in ('leave','mission','convoy','fundraising')
  loop
    if r.request_type = 'leave' then
      if r.lr_emp is null then
        continue; -- طلب بدون سجل إجازة مفصل
      end if;
      v_emp := r.lr_emp;
      v_start := r.lr_start;
      v_end := coalesce(r.lr_end, r.lr_start);
    else
      v_emp := r.employee_id;
      v_start := public._payload_date(r.payload, 'startDate');
      v_end := coalesce(public._payload_date(r.payload, 'endDate'), v_start);
      if v_start is null then
        continue; -- لا تواريخ في payload (طلب غير مكتمل البيانات)
      end if;
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values (v_emp, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
      v_day := v_day + 1;
    end loop;
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4) الكشف الشهري (v186): إعادة ترتيب الفحوصات —
--    تكليفات ← جدول مأموريات قديم ← payload ← إجازة ← صف الحضور ← غائب
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function "public"."_build_attendance_statement_v186"("p_employee_id" "uuid", "p_year" integer, "p_month" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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

      -- مأمورية عمل (work_assignments)؟
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
      -- مأمورية/قافلة/فاندي من payload الطلبات (المصدر الحالي للتطبيق)?
      elsif exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and public._payload_date(r.payload, 'startDate') is not null
          and v_day between public._payload_date(r.payload, 'startDate')
                        and coalesce(public._payload_date(r.payload, 'endDate'),
                                     public._payload_date(r.payload, 'startDate'))
      ) then
        v_status := case (select r.request_type from public.requests r
                          where r.employee_id = p_employee_id and r.status = 'approved'
                            and r.request_type in ('mission','convoy','fundraising')
                            and public._payload_date(r.payload, 'startDate') is not null
                            and v_day between public._payload_date(r.payload, 'startDate')
                                          and coalesce(public._payload_date(r.payload, 'endDate'),
                                                       public._payload_date(r.payload, 'startDate'))
                          limit 1)
                     when 'mission' then 'مأمورية عمل'
                     when 'convoy' then 'قافلة'
                     else 'فاندي' end;
        if v_status = 'مأمورية عمل' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;
      -- إجازة معتمدة؟
      elsif v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id and r.status = 'approved'
          and v_day between lr.start_date and lr.end_date
      ) then
        v_status := 'إجازة معتمدة';
        v_leave_days := v_leave_days + 1;
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

-- ربط التريغر بجدول requests (كان مفقوداً من 0429 — الدالة وُجدت بلا binding)
drop trigger if exists tg_leave_attendance_on_approval on public.requests;
create trigger tg_leave_attendance_on_approval
  after insert or update of status on public.requests
  for each row execute function public.tg_leave_attendance_on_approval();

-- إصلاح عرض يوم القافلة/الفاندي: كان فرع hasConvoyFundi يعرض 'قافلة' ثابتة
-- فيلتقط أيام الفاندي أيضاً؛ الآن يمرّر status الفعلي القادم من v186
-- (قافلة للقافلة / فاندي للفاندي).
create or replace function "public"."_build_attendance_statement_v287"("p_employee_id" "uuid", "p_year" integer, "p_month" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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

    -- الجمعة والعطلات الرسمية ليست أيام عمل شهرية.
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

    -- سياسة الساعات المرنة: لا غرامة تأخير/انصراف مبكر عندما تكون المدة هي المعيار.
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
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) then v_day_obj->>'status'
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
end;
$$;

commit;