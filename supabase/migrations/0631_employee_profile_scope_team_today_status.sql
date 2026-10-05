-- 0631: ملف الموظف — ملف أساسي للجميع وتفاصيل لمن يملك الملف، فريقه المباشر،
--       وحالة اليوم وملخص الحضور من نفس مصدر لوحات الإدارة وكشف الحضور
-- ===========================================================================
-- 1) attendance_day_facts تحسب كل الموظفين (~770ms لثلاثين يومًا) ← جسمها ينتقل
--    كما هو إلى attendance_day_facts_scoped(start, end, employee|null)،
--    و attendance_day_board(date) كذلك إلى attendance_day_board_scoped(date,
--    employee|null)؛ وتبقى الدالتان القديمتان غلافين بنفس التوقيع والنتيجة
--    (مصدر واحد، لا نسخة ثانية من المنطق).
-- 2) _today_status_public: تسمية حالة اليوم الواحدة لكل الشاشات — «حاضر في
--    الجمعية / غائب / في مأمورية / في قافلة / في فاندي ترفيهي / في إجازة /
--    انصرف»؛ «متأخر» و«انصرف مبكرًا» لمن يملك ملف الموظف فقط. الغياب يظهر بعد
--    موعد الحضور (كان «لم يسجل» طوال اليوم لأن attendance_daily لا يسجّل الغياب).
-- 3) get_employee_360 (كانت 0605 تفتح الملف كاملًا لكل موظف: البريد والهاتف
--    وتواريخ العقد والطلبات والمهام): الملف الأساسي + مديره المباشر + فريقه
--    المباشر بأسمائهم وحالاتهم للجميع، والتفاصيل لمن يملك قراءة ملفه
--    (can_access_employee … 'people.employee.read': هو، مديره المباشر، الإدارة
--    التنفيذية، الموارد البشرية، مديرو التشغيل في نطاقهم، الوصول الكامل).
--    attendance30 من attendance_day_facts (كان «غياب» = 0 دائمًا).
-- 4) get_mobile_employee_directory: نفس التسمية والنطاق، وLIMIT يعمل فعلًا.
-- 5) get_admin_org_chart: الهيكل الوظيفي لكل منسوبي الجمعية (كان للإدارة وHR
--    فقط فيظهر لبقية الموظفين خطأ صلاحية)، عدا موظفي العيادات المعزولين.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) المصدر الموحّد بنطاق موظف اختياري
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attendance_day_facts_scoped(p_start date, p_end date, p_employee_id uuid)
 RETURNS TABLE(employee_id uuid, work_date date, is_workday boolean, is_exempt boolean, leave_like boolean, offsite boolean, checked_in boolean, attended boolean, expected boolean, absent boolean, late_minutes integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      and (p_employee_id is null or e.id = p_employee_id)
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
$function$;

revoke all on function public.attendance_day_facts_scoped(date, date, uuid) from public, anon, authenticated;
grant execute on function public.attendance_day_facts_scoped(date, date, uuid) to service_role;

CREATE OR REPLACE FUNCTION public.attendance_day_facts(p_start date, p_end date)
 RETURNS TABLE(employee_id uuid, work_date date, is_workday boolean, is_exempt boolean, leave_like boolean, offsite boolean, checked_in boolean, attended boolean, expected boolean, absent boolean, late_minutes integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select * from public.attendance_day_facts_scoped(p_start, p_end, null::uuid);
$function$;

revoke all on function public.attendance_day_facts(date, date) from public, anon, authenticated;
grant execute on function public.attendance_day_facts(date, date) to service_role;

-- ---------------------------------------------------------------------------
-- 2) لوحة حضور اليوم بنطاق موظف اختياري
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attendance_day_board_scoped(p_date date, p_employee_id uuid)
 RETURNS TABLE(employee_id uuid, is_exempt boolean, is_workday boolean, is_holiday boolean, leave_like boolean, approved_leave boolean, offsite boolean, offsite_type text, checked_in boolean, expected boolean, late_minutes integer, first_check_in timestamp with time zone, last_check_out timestamp with time zone, early_leave_minutes integer, att_status text, att_updated_at timestamp with time zone, due_time time without time zone, missing_checkout boolean, board_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with clock as (
    select (now() at time zone 'Africa/Cairo')::date as today,
           (now() at time zone 'Africa/Cairo')::time as now_time
  ),
  f as (
    select * from public.attendance_day_facts_scoped(p_date, p_date, p_employee_id)
  ),
  enriched as (
    select f.*,
      ad.first_check_in as ad_first_in,
      ad.last_check_out as ad_last_out,
      coalesce(ad.early_leave_minutes, 0) as ad_early,
      ad.status as ad_status,
      ad.updated_at as ad_updated_at,
      o.day_type as override_type,
      sh.start_time as shift_start,
      sh.end_time as shift_end,
      sh.grace as shift_grace
    from f
    left join public.attendance_daily ad
      on ad.employee_id = f.employee_id and ad.work_date = f.work_date
    left join public.attendance_day_overrides o
      on o.employee_id = f.employee_id and o.work_date = f.work_date and o.is_active
    left join lateral (
      select s.start_time, s.end_time, coalesce(s.grace_in_minutes, 15) as grace
        from (
          select sa.shift_id, 1 as prio, sa.effective_from::timestamp as ord
            from public.shift_assignments sa
           where sa.employee_id = f.employee_id
             and sa.is_active
             and sa.effective_from <= p_date
             and (sa.effective_to is null or sa.effective_to >= p_date)
          union all
          select rd.shift_id, 2, wr.published_at::timestamp
            from public.roster_days rd
            join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
           where rd.employee_id = f.employee_id
             and rd.work_date = p_date
             and rd.day_status = 'scheduled'
          union all
          select s0.id, 3, null::timestamp
            from public.shifts s0
           where s0.code = 'OFFICIAL' and s0.is_active
        ) c
        join public.shifts s on s.id = c.shift_id
       order by c.prio, c.ord desc nulls last
       limit 1
    ) sh on true
  ),
  typed as (
    select e.*,
      coalesce(e.shift_start, '10:00'::time) + make_interval(mins => coalesce(e.shift_grace, 15)) as due_at,
      (e.leave_like and (
         coalesce(e.override_type, '') = 'leave'
         or coalesce(e.ad_status, '') = 'on_leave'
         or exists (
           select 1 from public.leave_requests lr
             join public.requests r on r.id = lr.request_id
            where lr.employee_id = e.employee_id and r.status = 'approved'
              and p_date between lr.start_date and lr.end_date)
         or exists (
           select 1 from public.requests r
            where r.employee_id = e.employee_id and r.status = 'approved'
              and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
              and p_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                             and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                          public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')))
      )) as approved_leave_flag,
      case when e.offsite then coalesce(
        case e.override_type
          when 'mission' then 'MISSION'
          when 'convoy' then 'CONVOY'
          when 'fundraising' then 'FUNDRAISING'
        end,
        (select case
                  when r.request_type in ('convoy', 'field_convoy')
                       or coalesce(r.payload->>'missionType', r.payload->>'type') = 'convoy' then 'CONVOY'
                  when r.request_type in ('fundraising', 'fandy', 'fundi')
                       or coalesce(r.payload->>'missionType', r.payload->>'type') in ('fundraising', 'fandy') then 'FUNDRAISING'
                  else 'MISSION'
                end
           from public.requests r
          where r.employee_id = e.employee_id
            and r.status not in ('rejected', 'cancelled')
            and (r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy',
                                    'fundraising', 'fandy', 'fundi', 'remote_work')
                 or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission'))
            and p_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                        public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
          order by r.created_at desc
          limit 1),
        'MISSION') end as offsite_kind,
      (exists (
         select 1 from public.public_holidays h
          where coalesce(h.is_active, true)
            and p_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
       or coalesce(e.override_type, '') = 'holiday') as holiday_flag
    from enriched e
  )
  select
    t.employee_id,
    t.is_exempt,
    t.is_workday,
    t.holiday_flag,
    t.leave_like,
    t.approved_leave_flag,
    t.offsite,
    t.offsite_kind,
    t.checked_in,
    (t.is_workday and not t.leave_like and not (t.offsite and not t.checked_in)) as expected,
    coalesce(t.late_minutes, 0),
    t.ad_first_in,
    t.ad_last_out,
    t.ad_early,
    t.ad_status,
    t.ad_updated_at,
    t.due_at,
    (t.checked_in and t.ad_last_out is null
      and (p_date < c.today or (p_date = c.today and c.now_time > coalesce(t.shift_end, '18:00'::time)))) as missing_checkout,
    case
      when t.is_exempt then 'exempt'
      when t.leave_like then 'on_leave'
      when t.offsite and not t.checked_in then 'assignment'
      when t.checked_in then case
        when coalesce(t.late_minutes, 0) > 0 then 'late'
        when t.ad_last_out is not null and t.ad_early > 0 then 'left_early'
        when t.ad_last_out is not null then 'checked_out'
        else 'present'
      end
      when not t.is_workday then 'weekend'
      when p_date > c.today then 'not_yet'
      when p_date < c.today or c.now_time >= t.due_at then 'absent'
      else 'not_yet'
    end
  from typed t
  cross join clock c;
$function$;

revoke all on function public.attendance_day_board_scoped(date, uuid) from public, anon, authenticated;
grant execute on function public.attendance_day_board_scoped(date, uuid) to service_role;

CREATE OR REPLACE FUNCTION public.attendance_day_board(p_date date)
 RETURNS TABLE(employee_id uuid, is_exempt boolean, is_workday boolean, is_holiday boolean, leave_like boolean, approved_leave boolean, offsite boolean, offsite_type text, checked_in boolean, expected boolean, late_minutes integer, first_check_in timestamp with time zone, last_check_out timestamp with time zone, early_leave_minutes integer, att_status text, att_updated_at timestamp with time zone, due_time time without time zone, missing_checkout boolean, board_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select * from public.attendance_day_board_scoped(p_date, null::uuid);
$function$;

revoke all on function public.attendance_day_board(date) from public, anon, authenticated;
grant execute on function public.attendance_day_board(date) to service_role;

-- ---------------------------------------------------------------------------
-- 3) تسمية حالة اليوم من سطر لوحة الحضور — دالة نقية واحدة لكل الشاشات.
--    p_detailed = من يملك قراءة ملف الموظف (مديره/الإدارة/HR): يرى «متأخر»
--    و«انصرف مبكرًا»؛ الزملاء يرون الحالة الواضحة فقط («حاضر في الجمعية»).
-- ---------------------------------------------------------------------------
create or replace function public._today_status_public(
  p_board_status text,
  p_offsite boolean,
  p_offsite_kind text,
  p_is_holiday boolean,
  p_checked_in boolean,
  p_checked_out boolean,
  p_detailed boolean
)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'status', s.status,
    'statusLabel', case s.status
      when 'mission' then 'في مأمورية'
      when 'convoy' then 'في قافلة'
      when 'fundraising' then 'في فاندي ترفيهي'
      when 'on_leave' then 'في إجازة'
      when 'holiday' then 'عطلة رسمية'
      when 'weekend' then 'إجازة أسبوعية'
      when 'exempt' then 'معفى من البصمة'
      when 'late' then 'متأخر'
      when 'left_early' then 'انصرف مبكرًا'
      when 'checked_out' then 'انصرف'
      when 'present' then 'حاضر في الجمعية'
      when 'absent' then 'غائب'
      else 'لم يسجّل حضوره بعد'
    end
  )
  from (
    select case
      when coalesce(p_offsite, false) then case p_offsite_kind
        when 'CONVOY' then 'convoy'
        when 'FUNDRAISING' then 'fundraising'
        else 'mission'
      end
      when p_board_status = 'assignment' then 'mission'
      when p_board_status = 'on_leave' then 'on_leave'
      when p_board_status = 'weekend' then
        case when coalesce(p_is_holiday, false) then 'holiday' else 'weekend' end
      when p_board_status = 'exempt' then
        case
          when not coalesce(p_checked_in, false) then 'exempt'
          when coalesce(p_checked_out, false) then 'checked_out'
          else 'present'
        end
      when p_board_status = 'late' then
        case
          when coalesce(p_detailed, false) then 'late'
          when coalesce(p_checked_out, false) then 'checked_out'
          else 'present'
        end
      when p_board_status = 'left_early' then
        case when coalesce(p_detailed, false) then 'left_early' else 'checked_out' end
      when p_board_status in ('present', 'checked_out', 'absent') then p_board_status
      else 'not_recorded'
    end as status
  ) s;
$function$;

revoke all on function public._today_status_public(text, boolean, text, boolean, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function public._today_status_public(text, boolean, text, boolean, boolean, boolean, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 4) حالة اليوم لموظف واحد من نفس مصدر لوحات الإدارة (attendance_day_board)،
--    ووجهة النشاط/نوع الإجازة وحالة اعتماد طلبه من الطلبات.
-- ---------------------------------------------------------------------------
create or replace function public._employee_today_status(p_employee_id uuid, p_detailed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_board record;
  v_req_status text;
  v_activity text;
  v_work integer;
  v_result jsonb;
begin
  select b.board_status, b.offsite, b.offsite_type, b.is_holiday, b.checked_in,
         b.late_minutes, b.first_check_in, b.last_check_out, b.due_time
    into v_board
  from public.attendance_day_board_scoped(v_today, p_employee_id) b
  limit 1;

  -- طلب نشاط/إجازة اليوم (المعتمد أولًا) — للوجهة ونوع الإجازة وحالة الاعتماد
  select r.status,
         coalesce(
           nullif(r.payload->>'location', ''),
           nullif(r.payload->>'destination', ''),
           nullif(r.title, ''),
           case when r.request_type = 'leave' then
             case coalesce(r.payload->>'leaveType', '')
               when 'annual' then 'إجازة اعتيادية'
               when 'casual' then 'إجازة عارضة'
               when 'sick' then 'إجازة مرضية'
               when 'weekly_rest_comp' then 'بدل راحة أسبوعية'
               else 'إجازة رسمية'
             end
           end)
    into v_req_status, v_activity
  from public.requests r
  where r.employee_id = p_employee_id
    and r.status in ('approved', 'pending')
    and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
    and v_today between
        coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                 (r.created_at at time zone 'Africa/Cairo')::date)
    and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                 public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                 (r.created_at at time zone 'Africa/Cairo')::date)
  order by case when r.status = 'approved' then 1 else 2 end,
           case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 else 4 end,
           r.created_at desc
  limit 1;

  v_result := public._today_status_public(
    v_board.board_status,
    v_board.offsite,
    v_board.offsite_type,
    v_board.is_holiday,
    v_board.checked_in,
    v_board.last_check_out is not null,
    p_detailed
  );

  -- الوجهة تظهر للجميع في المأمورية/القافلة/الفاندي؛ تفاصيل الإجازة لمن يملك الملف فقط
  v_result := v_result || jsonb_build_object('activityTitle', case
    when v_result->>'status' in ('mission', 'convoy', 'fundraising') then v_activity
    when v_result->>'status' = 'on_leave' and p_detailed then v_activity
  end);

  if p_detailed then
    select ad.work_minutes into v_work
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id and ad.work_date = v_today;

    v_result := v_result || jsonb_build_object(
      'requestStatus', case
        when v_result->>'status' in ('mission', 'convoy', 'fundraising', 'on_leave') then v_req_status
      end,
      'lateMinutes', coalesce(v_board.late_minutes, 0),
      'checkInAt', v_board.first_check_in,
      'checkOutAt', v_board.last_check_out,
      'workMinutes', coalesce(v_work, 0),
      'dueTime', to_char(v_board.due_time, 'HH24:MI')
    );
  end if;

  return v_result;
end;
$function$;

revoke all on function public._employee_today_status(uuid, boolean) from public, anon, authenticated;
grant execute on function public._employee_today_status(uuid, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 5) get_employee_360: ملف أساسي لكل منسوبي الجمعية + تفاصيل لمن يملك الملف
-- ---------------------------------------------------------------------------
create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_full boolean;
  v_basic jsonb;
  v_details jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  -- الحفاظ على عزل الإدارة الطبية / فتيات العيادات للمصرح لهم فقط
  if public.is_employee_isolated(p_employee_id) and not public.can_view_isolated_employee(p_employee_id) then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  -- من يملك قراءة ملف هذا الموظف (نفس نطاقات الصلاحيات): هو نفسه، مديره
  -- المباشر، الإدارة التنفيذية، الموارد البشرية، مديرو التشغيل في نطاقهم،
  -- والوصول الكامل. غيرهم يرى الملف الأساسي وحالته اليومية الواضحة فقط.
  v_full := public.can_access_employee(p_employee_id, 'people.employee.read');

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'jobTitle', jt.name,
    'position', pos.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerId', mgr.id,
    'managerName', mgr.full_name_ar,
    'manager', case when mgr.id is not null then jsonb_build_object(
      'id', mgr.id,
      'fullNameAr', mgr.full_name_ar,
      'jobTitle', mgr_jt.name,
      'photoUrl', mgr.photo_url
    ) end,
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', coalesce(tm.member_count, 0),
    'teamMembers', coalesce(tm.members, '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id = ed.department_id
      where ed.employee_id = e.id
        and (ed.start_date is null or ed.start_date <= v_today)
        and (ed.end_date is null or ed.end_date >= v_today)
    ), '[]'::jsonb),
    'todayStatus', public._employee_today_status(e.id, v_full),
    'viewerScope', case when v_full then 'full' else 'basic' end,
    -- حقول التفاصيل حاضرة بقيمة فارغة للملف الأساسي (عقد web employee360Schema)
    'phoneE164', null,
    'hireDate', null,
    'contractEnd', null,
    'probationEnd', null,
    'grade', null,
    'accountStatus', null,
    'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
  )
  into v_basic
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions pos on pos.id = e.position_id
  left join public.departments dept on dept.id = e.department_id
  left join public.teams team on team.id = e.team_id
  left join public.branches branch on branch.id = e.branch_id
  left join public.work_sites site on site.id = e.work_site_id
  left join public.employees mgr on mgr.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1
  )
  left join public.job_titles mgr_jt on mgr_jt.id = mgr.job_title_id
  -- فريقه المباشر: الأعضاء النشطون (مع احترام عزل العيادات) وحالة كل منهم اليوم
  left join lateral (
    select count(*) as member_count,
           jsonb_agg(
             jsonb_build_object(
               'id', m.id,
               'fullNameAr', m.full_name_ar,
               'jobTitle', m_jt.name,
               'photoUrl', m.photo_url
             )
             || (public._employee_today_status(m.id, public.can_access_employee(m.id, 'people.employee.read'))
                 - 'requestStatus' - 'lateMinutes' - 'checkInAt' - 'checkOutAt' - 'workMinutes' - 'dueTime')
             order by m.full_name_ar
           ) as members
    from (
      select distinct mr.employee_id
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    ) rel
    join public.employees m on m.id = rel.employee_id and m.is_active and not m.is_deleted
    left join public.job_titles m_jt on m_jt.id = m.job_title_id
    where not public.is_employee_isolated(m.id) or public.can_view_isolated_employee(m.id)
  ) tm on true
  where e.id = p_employee_id;

  if v_basic is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if not v_full then
    return v_basic;
  end if;

  select jsonb_build_object(
    'email', au.email,
    'phoneE164', e.phone_e164,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'grade', grade.name,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    -- نفس مصدر كشف الحضور الشهري (attendance_day_facts): أيام المأموريات
    -- والقوافل حضور، ويوم نسيان الانصراف حضور، والغياب = يوم عمل مستحق بلا حضور،
    -- والتأخير وفق اللائحة. الساعات من الأيام المكتملة فقط (حضور + انصراف).
    'attendance30', (
      select jsonb_build_object(
        'present', count(*) filter (where f.attended),
        'lateDays', count(*) filter (where f.late_minutes > 0),
        'absent', count(*) filter (where f.absent),
        'offsiteDays', count(*) filter (where f.offsite),
        'workMinutes', coalesce((
          select sum(a.work_minutes)
          from public.attendance_daily a
          where a.employee_id = e.id
            and a.work_date between v_today - 29 and v_today
            and a.first_check_in is not null
            and a.last_check_out is not null
            and a.last_check_out > a.first_check_in
        ), 0),
        'missingCheckout', (
          select count(*)
          from public.attendance_daily a
          where a.employee_id = e.id
            and a.work_date between v_today - 29 and v_today - 1
            and a.first_check_in is not null
            and a.last_check_out is null
        )
      )
      from public.attendance_day_facts_scoped(v_today - 29, v_today, e.id) f
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
      'approved', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'rejected')
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < v_today then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id = e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id = aa.asset_id
      where aa.employee_id = e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id = e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id = e.id order by created_at desc limit 10
      ) t
    ), '[]'::jsonb)
  )
  into v_details
  from public.employees e
  left join public.job_grades grade on grade.id = e.grade_id
  left join public.profiles profile on profile.employee_id = e.id
  left join auth.users au on au.id = profile.id
  where e.id = p_employee_id;

  return v_basic || coalesce(v_details, '{}'::jsonb);
end;
$function$;

revoke all on function public.get_employee_360(uuid) from public, anon;
grant execute on function public.get_employee_360(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) دليل الموظفين: نفس تسمية حالة اليوم ونطاقها (لوحة الحضور مرة واحدة لكل
--    الموظفين). الزملاء لا يرون «متأخر» ولا تفاصيل الإجازة.
--    وأيضًا: LIMIT كان يُطبّق على ناتج التجميع (صف واحد) فلا يحدّ شيئًا.
-- ---------------------------------------------------------------------------
create or replace function public.get_mobile_employee_directory(p_search text default null::text, p_limit integer default 40)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_me uuid;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  v_me := public.current_employee_id();

  return coalesce((
    with board as (
      select * from public.attendance_day_board(v_today)
    ),
    listed as (
      select e.id, e.full_name_ar, e.employee_code, e.photo_url,
             jt.name as job_title, d.name as department
      from public.employees e
      left join public.job_titles  jt on jt.id = e.job_title_id
      left join public.departments d  on d.id  = e.department_id
      where e.is_active  = true
        and e.is_deleted = false
        and not public.is_employee_executive(e.id)
        and public.can_see_directory_entry(v_me, e.id)
        and (
          v_search is null
          or e.full_name_ar  ilike '%' || v_search || '%'
          or e.employee_code ilike '%' || v_search || '%'
          or jt.name         ilike '%' || v_search || '%'
          or d.name          ilike '%' || v_search || '%'
        )
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 40), 100))
    ),
    enriched as (
      select l.*, req.activity_title, sc.detailed,
             public._today_status_public(
               b.board_status, b.offsite, b.offsite_type, b.is_holiday, b.checked_in,
               b.last_check_out is not null, sc.detailed
             ) as st
      from listed l
      left join board b on b.employee_id = l.id
      cross join lateral (
        select public.can_access_employee(l.id, 'people.employee.read') as detailed
      ) sc
      left join lateral (
        select coalesce(nullif(r.payload->>'location', ''), nullif(r.payload->>'destination', ''), nullif(r.title, '')) as activity_title
        from public.requests r
        where r.employee_id = l.id
          and r.status in ('approved', 'pending')
          and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
          and v_today between
              coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                       (r.created_at at time zone 'Africa/Cairo')::date)
          and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                       public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                       (r.created_at at time zone 'Africa/Cairo')::date)
        order by case when r.status = 'approved' then 1 else 2 end,
                 case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 else 4 end,
                 r.created_at desc
        limit 1
      ) req on true
    )
    select jsonb_agg(jsonb_build_object(
      'id',               x.id,
      'name',             x.full_name_ar,
      'employeeCode',     x.employee_code,
      'photoUrl',         x.photo_url,
      'jobTitle',         x.job_title,
      'department',       x.department,
      'statusToday',      x.st->>'status',
      'statusTodayLabel', x.st->>'statusLabel',
      'activityTitle',    case
                            when x.st->>'status' in ('mission', 'convoy', 'fundraising') then x.activity_title
                            when x.st->>'status' = 'on_leave' and x.detailed then x.activity_title
                          end
    ) order by x.full_name_ar)
    from enriched x
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_mobile_employee_directory(text, integer) from public, anon;
grant execute on function public.get_mobile_employee_directory(text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) الهيكل الوظيفي (تبويب «الهيكل» في شاشة الموظفين) لكل منسوبي الجمعية
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_admin_org_chart()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_me uuid;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  BEGIN
    v_me := public.current_employee_id();
  EXCEPTION WHEN others THEN
    v_me := NULL;
  END;

  -- 0631: الهيكل الوظيفي متاح لكل منسوبي الجمعية، عدا موظفي العيادات المعزولين
  -- (0572)؛ والمعزولون لا يظهرون في الشجرة إلا لمن يحق له (emp_base أدناه).
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read')
    OR (v_me IS NOT NULL AND NOT public.employee_blocks_inbound_alerts(v_me))
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
      AND NOT (
        public.is_employee_isolated(e.id)
        AND NOT public.can_view_isolated_employee(e.id)
      )  -- 0572: إخفاء المعزول عن غير المرئين له في الشجرة
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
$function$;

revoke all on function public.get_admin_org_chart() from public, anon;
grant execute on function public.get_admin_org_chart() to authenticated, service_role;

commit;
