-- ===========================================================================
-- 0643: إصلاح احتساب تأخير أذونات الحضور ومنع إلغاء غرامات الصباح بالمأموريات
-- ===========================================================================
-- المشكلتان المعالجتان:
--
-- 1) أذونات الحضور والتأخير (late_permit):
--    كانت دالتا is_lateness_excused و is_employee_exempt_from_instant_penalty
--    تعفيان اليوم بالكامل بمجرد وجود إذن تأخير مسجل!
--    النتيجة: من لديه إذن ساعتان (مثلاً ورديته من 11:00 ص فموعده المصرح 1:00 م)
--    وحضر بعد انتهاء الإذن (مثلاً 1:16 م أو 1:30 م) كان يُعفى كلياً وتُلغى غرامته!
--    الإصلاح:
--      • إذن التأخير لا يُعفي اليوم كلياً، بل يؤخر موعد بداية الوردية المحسوب
--        بمقدار دقائق الإذن (مثلاً 11:00 ص + 120 دقيقة = 1:00 م).
--      • الحضور ضمن فترة الإذن وسماح الوردية (حتى 1:15 م) = 0 تأخير ومعفى.
--      • الحضور بعد انتهاء الإذن وفترة السماح = يُحسب التأخير من الموعد المصرح
--        (1:00 م) وتُطبق عليه شرائح الغرامات المعتمدة ولا يُعفى منها.
--
-- 2) مأموريات وسط اليوم (Hatem case):
--    عندما يبصم الموظف صباحاً متأخراً (مثلاً حاتم تأخر 16 دقيقة وفُرضت عليه غرامة
--    20 ج.م)، ثم يقوم بعمل مأمورية في وسط اليوم، كانت دوال submit_my_request
--    و start_my_mission و is_employee_exempt_from_instant_penalty تقوم تلقائياً
--    وعشوائياً بتصفير دقائق التأخير وإلغاء الغرامة الصباحية بدعوى بدء مأمورية!
--    الإصلاح:
--      • المأمورية لا تعفي إلا إذا بدأت من الصباح كأول حدث حضور للموظف.
--      • إذا كان للموظف بصمة حضور سابقة بالمقر اليوم (قبل المأمورية)، فلا تُلغى
--        غرامته الصباحية ولا تُصفّر دقائق تأخيره الصباحي.
--
-- 3) معالجة البيانات بأثر رجعي:
--      • لحاتم: إعادة تفعيل غرامة التأخير الصباحي (16 دقيقة = 20 ج.م) ليوم 2026-10-04.
--      • لعبد الرحمن: فحص موعد بصمته ليوم 2026-10-05 ومقارنته بموعد 1:00 م
--        (11:00 ص + إذن ساعتان)، وتثبيت دقائق التأخير والغرامة المستحقة إن وجدت.
-- ===========================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث is_lateness_excused:
--    إزالة إعفاء late_permit الكلي (يُعالج بحساب الموعد الفعلي)،
--    وحصر إعفاء المأموريات بمن لم يكن لديه بصمة متأخرة بالمقر سابقاً.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_lateness_excused(p_employee_id uuid, p_work_date date)
returns boolean
language sql
stable security definer
set search_path = public, pg_temp
as $fn$
  select public.is_employee_attendance_exempt(p_employee_id)
    or public.is_employee_penalty_exempt(p_employee_id)
    or extract(isodow from p_work_date) = 5
    -- عطلة رسمية
    or exists (
      select 1 from public.public_holidays h
      where coalesce(h.is_active, true)
        and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
    -- تعديل إداري معتمد
    or exists (
      select 1 from public.attendance_day_overrides o
      where o.employee_id = p_employee_id and o.work_date = p_work_date and o.is_active
        and o.day_type in ('leave', 'holiday', 'rest'))
    -- حالة الحضور اليومي كإجازة
    or exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id and ad.work_date = p_work_date and ad.status = 'on_leave')
    -- طلب إجازة غير ملغي وغير مرفوض
    or exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and p_work_date between lr.start_date and lr.end_date)
    -- مأمورية جارية أو مكتملة (تعفي الحضور الصباحي فقط إن لم تسبقها بصمة مقر متأخرة)
    or exists (
      select 1 from public.mission_executions me
      where me.employee_id = p_employee_id
        and me.status in ('in_progress', 'completed')
        and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
        and not exists (
          select 1 from public.attendance_events ae
          where ae.employee_id = p_employee_id
            and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
            and ae.event_type = 'CHECK_IN'
            and ae.status in ('accepted', 'adjusted')
            and ae.source not in ('mission_auto')
            and ae.event_at < me.started_at
            and coalesce(ae.late_minutes, 0) > 0
        )
    )
    -- طلب مأمورية معتمد أو جارٍ (يعفي فقط إن لم تسبقه بصمة مقر متأخرة)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status in ('approved', 'in_progress', 'pending')
        and (
          r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
          or coalesce(r.payload->>'missionType', r.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy')
        )
        and p_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                            and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                         public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
        and not exists (
          select 1 from public.attendance_events ae
          where ae.employee_id = p_employee_id
            and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
            and ae.event_type = 'CHECK_IN'
            and ae.status in ('accepted', 'adjusted')
            and ae.source not in ('mission_auto')
            and ae.event_at < r.created_at
            and coalesce(ae.late_minutes, 0) > 0
        )
    );
$fn$;

comment on function public.is_lateness_excused(uuid, date) is
  '0643: استثناء التأخير لمن لديه إعفاء أو إجازة أو عطلة أو مأمورية صباحية غير مسبوقة ببصمة متأخرة. أذونات التأخير تُحسب بتأخير موعد الوردية ولا تعفي اليوم كلياً.';

revoke execute on function public.is_lateness_excused(uuid, date) from public, anon, authenticated;
grant execute on function public.is_lateness_excused(uuid, date) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث attendance_policy_late_minutes:
--    تأخير موعد بداية الوردية الفعلي بمقدار دقائق إذن التأخير الصباحي (إن وُجد)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.attendance_policy_late_minutes(
  p_employee_id uuid,
  p_work_date date,
  p_check_in timestamptz,
  p_shift_id uuid default null
)
returns integer
language plpgsql
stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_shift public.shifts%rowtype;
  v_diff integer;
  v_target_shift_id uuid;
  v_permit_minutes integer := null;
  v_effective_start_epoch timestamptz;
  v_permit_req record;
begin
  if p_check_in is null then
    return 0;
  end if;

  -- 1) فحص الأعذار الكاملة (إجازة، عطلة، استثناء دائم، مأمورية صباحية)
  if public.is_lateness_excused(p_employee_id, p_work_date) then
    return 0;
  end if;

  v_target_shift_id := p_shift_id;

  -- 2) تحديد الوردية المعتمدة في shift_assignments
  if v_target_shift_id is null and p_employee_id is not null then
    select sa.shift_id into v_target_shift_id
      from public.shift_assignments sa
     where sa.employee_id = p_employee_id
       and sa.is_active = true
       and sa.effective_from <= p_work_date
       and (sa.effective_to is null or sa.effective_to >= p_work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_target_shift_id is null then
    v_target_shift_id := public.match_flexible_shift(p_check_in);
  end if;

  select * into v_shift from public.shifts where id = v_target_shift_id;
  if v_shift.id is null or v_shift.start_time is null then
    return 0;
  end if;

  -- 3) فحص هل يوجد إذن تأخير صباحي (late_permit / permit / permission / errand)
  select r.id, r.request_type, r.payload into v_permit_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(r.payload->>'permitKind', 'late_arrival') <> 'early_departure'
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = p_work_date
   order by r.created_at desc
   limit 1;

  if v_permit_req.id is not null then
    v_permit_minutes := coalesce(
      (v_permit_req.payload->>'minutes')::integer,
      (v_permit_req.payload->>'duration')::integer,
      ((v_permit_req.payload->>'hours')::numeric * 60)::integer,
      120
    );
  end if;

  -- 4) حساب وقت البداية الفعلي مع إضافة دقائق الإذن إن وُجد
  v_effective_start_epoch := ((p_work_date + v_shift.start_time)::timestamp at time zone 'Africa/Cairo')
    + (coalesce(v_permit_minutes, 0) || ' minutes')::interval;

  v_diff := floor(extract(epoch from (p_check_in - v_effective_start_epoch)) / 60)::integer;

  return case when v_diff > coalesce(v_shift.grace_in_minutes, 0) then least(greatest(0, v_diff), 120) else 0 end;
end;
$fn$;

comment on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) is
  '0643: احتساب دقائق التأخير مع إزاحة موعد الحضور بدقائق إذن التأخير الصباحي وحصر التأخير بما بعد الإذن وفترة السماح.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث is_employee_exempt_from_instant_penalty:
--    أ. إذن التأخير لا يُعفي من الغرامة إن حضر الموظف متأخراً بعد انتهاء مدة الإذن.
--    ب. مأمورية وسط اليوم لا تُعفي من غرامة تأخير الصباح إن سبقتها بصمة متأخرة بالمقر.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_employee_exempt_from_instant_penalty(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req record;
  v_wa record;
  v_att record;
  v_loc text;
begin
  -- 1) فحص الاستثناء الإداري الدائم
  if public.is_employee_penalty_exempt(p_employee_id) or public.is_employee_attendance_exempt(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permanent_exemption',
      'reason', case
        when public.is_employee_attendance_exempt(p_employee_id)
          then 'معفى دائماً بقرار إداري من الحضور والانصراف والغرامات'
        else
          'معفى دائماً بقرار إداري من جميع الغرامات والخصومات'
      end
    );
  end if;

  -- 2) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- 3) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- 4) فحص الإجازات في جدول leave_requests
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type, r.status into v_req
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    left join public.leave_types lt on lt.id = lr.leave_type_id
   where lr.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and p_work_date between lr.start_date and lr.end_date
   limit 1;

  if v_req.request_type is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_type, 'رسمية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- 5) فحص أذونات الحضور والتأخير (late_permit, early_permit, permit, permission)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         (r.payload->>'permitDate')::date,
         (r.payload->>'date')::date,
         (r.payload->>'startDate')::date,
         (r.payload->>'start_date')::date,
         (r.payload->>'workDate')::date,
         r.created_at::date
       ) = p_work_date
     order by r.created_at desc
     limit 1
  loop
    -- إذا كان إذن حضور أو تأخير صباحي
    if v_req.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(v_req.payload->>'permitKind', 'late_arrival') <> 'early_departure' then
      declare
        v_first_punch timestamptz;
        v_emp_shift public.shifts%rowtype;
        v_permit_mins integer;
        v_deadline timestamptz;
      begin
        select coalesce(
          (select ad.first_check_in from public.attendance_daily ad where ad.employee_id = p_employee_id and ad.work_date = p_work_date limit 1),
          (select min(ae.event_at) from public.attendance_events ae where ae.employee_id = p_employee_id and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date and ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted'))
        ) into v_first_punch;

        select s.* into v_emp_shift
          from public.shifts s
         where s.id = coalesce(
           (select sa.shift_id from public.shift_assignments sa where sa.employee_id = p_employee_id and sa.is_active = true and sa.effective_from <= p_work_date and (sa.effective_to is null or sa.effective_to >= p_work_date) order by sa.effective_from desc limit 1),
           public.match_flexible_shift(v_first_punch),
           public.default_shift_id()
         );

        v_permit_mins := coalesce(
          (v_req.payload->>'minutes')::integer,
          (v_req.payload->>'duration')::integer,
          ((v_req.payload->>'hours')::numeric * 60)::integer,
          120
        );

        if v_emp_shift.id is not null and v_emp_shift.start_time is not null then
          v_deadline := ((p_work_date + v_emp_shift.start_time)::timestamp at time zone 'Africa/Cairo')
            + (v_permit_mins || ' minutes')::interval
            + (coalesce(v_emp_shift.grace_in_minutes, 15) || ' minutes')::interval;

          -- إن بصم الموظف بعد موعد الإذن + فترة السماح: لا يُعفى من غرامة التأخير الزائد!
          if v_first_punch is not null and v_first_punch > v_deadline then
            null; -- نتابع لعدم إعفائه
          else
            return jsonb_build_object(
              'isExempt', true,
              'category', 'permit',
              'reason', 'إذن حضور/تأخير رسمي مسجل (' || v_permit_mins || ' دقيقة) — الحضور ضمن فترة الإذن المعتمدة'
            );
          end if;
        else
          return jsonb_build_object(
            'isExempt', true,
            'category', 'permit',
            'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
          );
        end if;
      end;
    else
      -- إذن انصراف مبكر
      return jsonb_build_object(
        'isExempt', true,
        'category', 'permit',
        'reason', 'إذن رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
      );
    end if;
  end loop;

  -- 6) فحص سجل تنفيذ المأموريات المباشر (in_progress أو completed لليوم)
  -- تحصين: المأمورية لا تعفي من غرامة الصباح إن كان الموظف قد بصم متأخراً بالمقر أولاً
  declare
    v_has_prior_late_punch boolean := false;
  begin
    select exists (
      select 1 from public.attendance_events ae
       where ae.employee_id = p_employee_id
         and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
         and ae.event_type = 'CHECK_IN'
         and ae.status in ('accepted', 'adjusted')
         and ae.source not in ('mission_auto')
         and coalesce(ae.late_minutes, 0) > 0
         and exists (
           select 1 from public.mission_executions me
            where me.employee_id = p_employee_id
              and me.status in ('in_progress', 'completed')
              and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
              and me.started_at > ae.event_at
         )
    ) into v_has_prior_late_punch;

    if not v_has_prior_late_punch and exists (
      select 1 from public.mission_executions me
      where me.employee_id = p_employee_id
        and me.status in ('in_progress', 'completed')
        and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
    ) then
      return jsonb_build_object(
        'isExempt', true,
        'category', 'mission',
        'reason', 'مأمورية عمل جارية أو مكتملة اليوم'
      );
    end if;
  end;

  -- 7) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and (
         -- طلب إجازة
         (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
          and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- مأمورية عمل
         or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- قافلة ميدانية
         or (r.request_type in ('convoy', 'field_convoy')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فاندي / جمع تبرعات
         or (r.request_type in ('fundraising', 'fandy', 'fundi')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فحص داخل payload للأنواع المدمجة
         or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- عمل عن بعد أو تعويض
         or (r.request_type in ('remote_work', 'compensation')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
       )
     order by r.created_at desc
     limit 1
  loop
    -- إن كانت مأمورية/قافلة/فاندي، نتأكد أنها لم تسبقها بصمة حضور متأخرة بالمقر
    if v_req.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
       or coalesce(v_req.payload->>'missionType', v_req.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy') then
      if exists (
        select 1 from public.attendance_events ae
         where ae.employee_id = p_employee_id
           and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
           and ae.event_type = 'CHECK_IN'
           and ae.status in ('accepted', 'adjusted')
           and ae.source not in ('mission_auto')
           and coalesce(ae.late_minutes, 0) > 0
           and ae.event_at < r.created_at
      ) then
        null; -- لا نُعفيه من تأخير الصباح
      else
        v_loc := case
          when v_req.request_type in ('convoy', 'field_convoy') or coalesce(v_req.payload->>'missionType', '') = 'convoy' then 'قافلة ميدانية'
          when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') = 'fundraising' then 'فاندي (جمع تبرعات)'
          when v_req.request_type in ('mission', 'external_mission', 'administrative_mission') then 'مأمورية عمل'
          else 'مأمورية'
        end;
        return jsonb_build_object(
          'isExempt', true,
          'category', 'mission',
          'reason', v_loc || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
        );
      end if;
    else
      v_loc := case
        when v_req.request_type = 'remote_work' then 'عمل عن بعد'
        when v_req.request_type = 'compensation' then 'يوم راحة تعويضي'
        else 'إجازة رسمية'
      end;
      return jsonb_build_object(
        'isExempt', true,
        'category', case when v_req.request_type = 'compensation' then 'compensation' else 'leave' end,
        'reason', v_loc || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
      );
    end if;
  end loop;

  -- 8) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.responsible_employee_id = p_employee_id
     and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
     and p_work_date between wa.start_at::date and wa.end_at::date
     and not exists (
       select 1 from public.attendance_events ae
        where ae.employee_id = p_employee_id
          and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
          and ae.event_type = 'CHECK_IN'
          and ae.status in ('accepted', 'adjusted')
          and ae.source not in ('mission_auto')
          and ae.event_at < wa.start_at
          and coalesce(ae.late_minutes, 0) > 0
     )
   limit 1;

  if v_wa.assignment_type is not null then
    v_loc := case
      when upper(v_wa.assignment_type) in ('CONVOY', 'FIELD_CONVOY') then 'قافلة ميدانية'
      when upper(v_wa.assignment_type) in ('FUNDRAISING', 'FANDY') then 'فاندي (جمع تبرعات)'
      when upper(v_wa.assignment_type) in ('MISSION', 'EXTERNAL') then 'مأمورية عمل'
      else 'مهمة عمل رسمية (' || coalesce(v_wa.title, v_wa.assignment_type) || ')'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', 'assignment',
      'reason', v_loc || ' مكلف بها رسمياً'
    );
  end if;

  -- 9) فحص التعديلات الإدارية على اليوم (attendance_day_overrides)
  if exists (
    select 1 from public.attendance_day_overrides
     where employee_id = p_employee_id
       and work_date = p_work_date
       and is_active = true
       and day_type in ('leave', 'holiday', 'rest')
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'override',
      'reason', 'تعديل إداري معتمد على حالة اليوم'
    );
  end if;

  -- 10) فحص حالة الحضور المسجلة كإجازة في attendance_daily
  select status into v_att
    from public.attendance_daily
   where employee_id = p_employee_id
     and work_date = p_work_date
     and status = 'on_leave'
   limit 1;

  if v_att.status is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'daily_status',
      'reason', 'حالة الحضور اليومية: إجازة'
    );
  end if;

  -- غير معفى
  return jsonb_build_object('isExempt', false, 'category', 'none', 'reason', '');
end;
$$;

comment on function public.is_employee_exempt_from_instant_penalty(uuid, date) is
  '0643: فحص الإعفاء مع تحصين: عدم إعفاء من تجاوز موعد الإذن المصرح، وعدم إلغاء غرامة الصباح بمأمورية وسط اليوم.';

revoke all on function public.is_employee_exempt_from_instant_penalty(uuid, date) from public, anon;
grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث submit_my_request:
--    عدم تصفير التأخير أو إلغاء الغرامات إذا كان للموظف بصمة حضور سابقة بالمقر
-- ─────────────────────────────────────────────────────────────────────────────

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
  v_month_start           date := date_trunc('month', v_today)::date;
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
  v_geofence_id           uuid;
  v_has_prior_office_punch boolean := false;
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

  -- ── 0643: بدء المأمورية فور طلبها لليوم الحالي ──
  if p_request_type in ('mission', 'convoy', 'fundraising') and not v_day_mark and v_start_date = v_today then
    -- 1. تسجيل بدء المأمورية في mission_executions
    insert into public.mission_executions(
      request_id, employee_id, status, started_at
    ) values (
      v_row.id, v_me, 'in_progress', coalesce(v_row.created_at, now())
    ) on conflict (request_id) do update
      set status = 'in_progress',
          started_at = coalesce(public.mission_executions.started_at, v_row.created_at, now()),
          updated_at = now();

    -- 0643: التحقق أولاً هل للموظف بصمة حضور سابقة بالمقر اليوم قبل بدء المأمورية
    select exists (
      select 1 from public.attendance_events ae
       where ae.employee_id = v_me
         and (ae.event_at at time zone 'Africa/Cairo')::date = v_today
         and ae.event_type = 'CHECK_IN'
         and ae.status in ('accepted', 'adjusted')
         and ae.source not in ('mission_auto')
         and ae.event_at < coalesce(v_row.created_at, now())
    ) into v_has_prior_office_punch;

    -- إذا لم تكن هناك بصمة حضور سابقة بالمقر: المأمورية هي بداية اليوم → تصفير التأخير وإلغاء الغرامات
    if not v_has_prior_office_punch then
      -- 2. تثبيت الحضور اليومي كـ present وتصفير أي تأخير
      insert into public.attendance_daily (
        employee_id, work_date, status, first_check_in, late_minutes, updated_at
      ) values (
        v_me, v_today, 'present', coalesce(v_row.created_at, now()), 0, now()
      ) on conflict (employee_id, work_date) do update
        set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            status = 'present',
            late_minutes = 0,
            updated_at = now();

      -- 3. تصفير دقائق التأخير في أحداث البصمة لليوم
      update public.attendance_events
         set late_minutes = 0
       where employee_id = v_me
         and (event_at at time zone 'Africa/Cairo')::date = v_today;

      -- 4. إلغاء فوري لأي غرامات حضور معلقة لليوم
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
             updated_at = now()
       where employee_id = v_me
         and work_date = v_today
         and status in ('pending_payment', 'doubled');
    else
      -- حضر للمقر صباحاً وبدأ مأمورية في وسط اليوم: لا نلغي تأخيره الصباحي ولا غرامته
      update public.attendance_daily
         set updated_at = now()
       where employee_id = v_me
         and work_date = v_today;
    end if;

    -- 5. إدراج حدث بصمة دخول آلي من المأمورية فقط إن لم يكن هناك أي حدث CHECK_IN لليوم
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
        is_mock_location, source, notes, late_minutes
      ) values (
        v_me, v_geofence_id, 'CHECK_IN', coalesce(v_row.created_at, now()), 'adjusted',
        true, 'server_verified', true,
        false, 'mission_auto', 'auto_check_in_from_mission_creation', 0
      );
    end if;
  end if;

  return v_row;
end;
$$;

comment on function public.submit_my_request(text, text, text, jsonb, uuid) is
  '0643: بدء المأمورية لليوم مع حماية غرامات وتأخير الصباح من الإلغاء إن كان الموظف قد بصم بالمقر أولاً.';

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) تحديث start_my_mission:
--    عدم تصفير التأخير أو إلغاء الغرامة الصباحية إن كانت المأمورية في وسط اليوم
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.start_my_mission(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                     uuid := public.current_employee_id();
  v_req                    public.requests;
  v_today                  date := (now() at time zone 'Africa/Cairo')::date;
  v_id                     uuid;
  v_end                    date;
  v_geofence_id            uuid;
  v_has_prior_office_punch boolean := false;
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

  if v_req.status not in ('approved', 'pending') then
    raise exception 'لا يمكن بدء مأمورية ملغاة أو مرفوضة' using errcode = '22023';
  end if;

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

  -- 0643: فحص هل كان للموظف بصمة حضور بالمقر اليوم قبل بدء المأمورية
  select exists (
    select 1 from public.attendance_events ae
     where ae.employee_id = v_me
       and (ae.event_at at time zone 'Africa/Cairo')::date = v_today
       and ae.event_type = 'CHECK_IN'
       and ae.status in ('accepted', 'adjusted')
       and ae.source not in ('mission_auto')
       and ae.event_at < coalesce(v_req.created_at, now())
  ) into v_has_prior_office_punch;

  -- تسجيل الحضور اليومي
  if not v_has_prior_office_punch then
    insert into public.attendance_daily (
      employee_id, work_date, status, first_check_in, late_minutes, updated_at
    ) values (
      v_me, v_today, 'present', coalesce(v_req.created_at, now()), 0, now()
    ) on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          status = 'present',
          late_minutes = 0,
          updated_at = now();

    update public.attendance_events
       set late_minutes = 0
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today;

    update public.instant_attendance_penalties
       set status = 'cancelled',
           cancelled_reason = 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
           notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
           updated_at = now()
     where employee_id = v_me
       and work_date = v_today
       and status in ('pending_payment', 'doubled');
  else
    update public.attendance_daily
       set updated_at = now()
     where employee_id = v_me
       and work_date = v_today;
  end if;

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
      is_mock_location, source, notes, late_minutes
    ) values (
      v_me, v_geofence_id, 'CHECK_IN', coalesce(v_req.created_at, now()), 'adjusted',
      true, 'server_verified', true,
      false, 'mission_auto', 'auto_check_in_from_mission_start', 0
    );
  end if;

  return v_id;
end $$;

comment on function public.start_my_mission(uuid) is
  '0643: بدء مأمورية مع عدم إلغاء غرامات أو تأخير الصباح إن سبقتها بصمة متأخرة بالمقر.';

revoke all on function public.start_my_mission(uuid) from public, anon;
grant execute on function public.start_my_mission(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) معالجة البيانات لحاتم (2026-10-04) وعبد الرحمن (2026-10-05)
-- ─────────────────────────────────────────────────────────────────────────────

-- أ. استعادة غرامة حاتم ليوم 2026-10-04 (تأخر 16 دقيقة وألغتها مأمورية وسط اليوم)
do $$
declare
  v_hatem_id uuid;
begin
  select id into v_hatem_id
    from public.employees
   where full_name_ar like '%حاتم%'
   limit 1;

  if v_hatem_id is not null then
    -- 1) إعادة تفعيل الغرامة الملغاة
    update public.instant_attendance_penalties
       set status = 'pending_payment',
           cancelled_reason = null,
           late_minutes = 16,
           original_amount = 20.00,
           current_amount = 20.00,
           notes = 'إعادة تفعيل الغرامة: تأخير حضور صباحي 16 دقيقة (المأمورية اللاحقة في وسط اليوم لا تلغي غرامة الصباح)',
           updated_at = now()
     where employee_id = v_hatem_id
       and work_date = '2026-10-04'::date
       and status = 'cancelled'
       and (cancelled_reason like '%مأمورية%' or notes like '%مأمورية%');

    -- 2) إعادة دقائق التأخير في attendance_daily
    update public.attendance_daily
       set late_minutes = 16,
           status = 'late',
           updated_at = now()
     where employee_id = v_hatem_id
       and work_date = '2026-10-04'::date
       and late_minutes = 0;

    -- 3) إعادة دقائق التأخير في حدث البصمة الصباحية
    update public.attendance_events
       set late_minutes = 16
     where employee_id = v_hatem_id
       and (event_at at time zone 'Africa/Cairo')::date = '2026-10-04'::date
       and event_type = 'CHECK_IN'
       and source not in ('mission_auto')
       and late_minutes = 0;
  end if;
end $$;

-- ب. فحص وضبط حضور عبد الرحمن ليوم 2026-10-05
--    الوردية: 11:00 ص إلى 07:00 م
--    الإذن: ساعتان (120 دقيقة) → الموعد المصرح 1:00 م (سماح حتى 1:15 م)
do $$
declare
  v_abdelrahman_id uuid;
  v_check_in timestamptz;
  v_permit_start timestamptz;
  v_deadline timestamptz;
  v_late integer := 0;
  v_amount numeric(12,2) := 0;
begin
  select id into v_abdelrahman_id
    from public.employees
   where full_name_ar like '%عبد الرحمن%' or full_name_ar like '%عبدالرحمن%'
   limit 1;

  if v_abdelrahman_id is not null then
    -- استخراج وقت البصمة الفعلي لعبد الرحمن اليوم
    select coalesce(
      (select ad.first_check_in from public.attendance_daily ad where ad.employee_id = v_abdelrahman_id and ad.work_date = '2026-10-05'::date limit 1),
      (select min(ae.event_at) from public.attendance_events ae where ae.employee_id = v_abdelrahman_id and (ae.event_at at time zone 'Africa/Cairo')::date = '2026-10-05'::date and ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted'))
    ) into v_check_in;

    -- الموعد المصرح بعد إذن الساعتين: 1:00 م بتوقيت القاهرة
    v_permit_start := ('2026-10-05 13:00:00'::timestamp at time zone 'Africa/Cairo');
    -- انتهاء فترة السماح (15 دقيقة): 1:15 م
    v_deadline := v_permit_start + interval '15 minutes';

    if v_check_in is not null then
      if v_check_in > v_deadline then
        -- حساب التأخير الفعلي لما بعد موعد 1:00 م
        v_late := least(120, floor(extract(epoch from (v_check_in - v_permit_start)) / 60)::integer);
        v_amount := public.calc_instant_penalty_amount(v_late);

        -- تحديث attendance_daily
        update public.attendance_daily
           set late_minutes = v_late,
               status = 'late',
               updated_at = now()
         where employee_id = v_abdelrahman_id
           and work_date = '2026-10-05'::date;

        -- تحديث حدث البصمة
        update public.attendance_events
           set late_minutes = v_late
         where employee_id = v_abdelrahman_id
           and (event_at at time zone 'Africa/Cairo')::date = '2026-10-05'::date
           and event_type = 'CHECK_IN'
           and source not in ('mission_auto');

        -- تسجيل الغرامة الفورية المستحقة
        if v_amount > 0 then
          insert into public.instant_attendance_penalties (
            employee_id, work_date, late_minutes,
            original_amount, current_amount, currency,
            status, escalation_level, notes, created_by
          ) values (
            v_abdelrahman_id, '2026-10-05'::date, v_late,
            v_amount, v_amount, 'EGP',
            'pending_payment', 'initial',
            'تأخير حضور بعد انتهاء إذن الساعتين المعتمد (الوردية تبدأ 11:00 ص، والإذن ينتهي 1:00 م، الحضور الفعلي ' || to_char(v_check_in at time zone 'Africa/Cairo', 'HH12:MI AM') || ')',
            null
          )
          on conflict (employee_id, work_date) do update
            set late_minutes = excluded.late_minutes,
                original_amount = excluded.original_amount,
                current_amount = excluded.current_amount,
                status = 'pending_payment',
                cancelled_reason = null,
                notes = excluded.notes,
                updated_at = now();
        end if;
      else
        -- بصم في أو قبل 1:15 م (ضمن الإذن وفترة السماح)
        update public.attendance_daily
           set late_minutes = 0,
               status = 'present',
               updated_at = now()
         where employee_id = v_abdelrahman_id
           and work_date = '2026-10-05'::date;

        update public.instant_attendance_penalties
           set status = 'cancelled',
               cancelled_reason = 'إعفاء: الحضور ضمن فترة إذن الساعتين المعتمد (قبل 1:15 م)',
               updated_at = now()
            where employee_id = v_abdelrahman_id
              and work_date = '2026-10-05'::date;
      end if;
    end if;
  end if;
end $$;

commit;
