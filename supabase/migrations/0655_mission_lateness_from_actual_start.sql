-- ============================================================================
-- 0655: المأمورية لا تمسح التأخير إلا من لحظة بدئها الفعلية
-- ============================================================================
-- المشكلة (2026-10-06): أي مأمورية في اليوم كانت تمسح التأخير كله مهما كانت ساعة
-- فتحها، وحتى قبل اعتمادها؛ ففتح الموظف مأمورية الساعة 11 أو 12 يلغي غرامة الصباح
-- (32 من 53 مأمورية لإدارة الحركة في 30 يومًا فُتحت بعد 10:15). ومسارات المسح:
--   • is_employee_exempt_from_instant_penalty (الكرون + بصمة الحضور)
--   • is_lateness_excused (دقائق التأخير في البصمة والكشف)
--   • start_my_mission يصفّر التأخير ويلغي غرامة اليوم دائمًا
--   • trg_fn_cancel_penalties_on_request_change يلغي غرامة اليوم عند تقديم أي مأمورية
-- خطأ مصاحب: الخطوة 7 في is_employee_exempt_from_instant_penalty تشير إلى r خارج
--   استعلامها (42P01) — فشل كرون الغرامات 23 مرة في أسبوعين، وتفشل بصمة المتأخر
--   الذي لديه قافلة/مأمورية ممتدة (الاستدعاء خارج كتلة الاستثناء في المحفّز).
-- القاعدة الجديدة: المأمورية/القافلة/الفاندي تعفي من تأخير اليوم فقط إن بدأت/قُدِّمت
--   قبل نهاية سماح الدوام (بداية الوردية + السماح)؛ وإلا فلحظة بدئها بصمة حضور
--   يُحسب تأخيرها بالقاعدة المعتادة (حتى 120 دقيقة). الطلب المرفوض/المسحوب/المعاد
--   لا يعفي. الإجازات والأذونات والتكليف الرسمي من المدير (work_assignments) بلا تغيير.
-- الاستبدال كنوني كامل للدوال الأربع من أجسامها الحية + دالة مساعدة داخلية.

create or replace function public.employee_lateness_deadline(p_employee_id uuid, p_work_date date)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_start time;
  v_grace integer;
begin
  -- نفس ترتيب auto_generate_instant_penalties: الوردية المسندة ثم الجدول المنشور ثم الدوام الأساسي
  select s.start_time, coalesce(s.grace_in_minutes, 15) into v_start, v_grace
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
   where sa.employee_id = p_employee_id and sa.is_active
     and sa.effective_from <= p_work_date
     and (sa.effective_to is null or sa.effective_to >= p_work_date)
   order by sa.effective_from desc
   limit 1;

  if v_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15) into v_start, v_grace
      from public.roster_days rd
      join public.shifts s on s.id = rd.shift_id
      join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
     where rd.employee_id = p_employee_id and rd.work_date = p_work_date
       and rd.day_status = 'scheduled'
     order by wr.published_at desc nulls last
     limit 1;
  end if;

  if v_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15) into v_start, v_grace
      from public.shifts s where s.is_active and s.code = 'OFFICIAL' limit 1;
  end if;
  if v_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15) into v_start, v_grace
      from public.shifts s where s.id = public.default_shift_id();
  end if;

  return ((p_work_date + coalesce(v_start, '10:00'::time))::timestamp at time zone 'Africa/Cairo')
         + make_interval(mins => coalesce(v_grace, 15));
end;
$$;

comment on function public.employee_lateness_deadline(uuid, date) is
  '0655: داخلية — نهاية سماح الحضور لموظف في يوم (بداية ورديته + السماح) بتوقيت القاهرة.';
revoke all on function public.employee_lateness_deadline(uuid, date) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_lateness_excused(p_employee_id uuid, p_work_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- 0655: مأمورية بدأت في الموعد (قبل نهاية السماح) ولم يُرفض طلبها أو يُسحب؛
    -- المأمورية المتأخرة لا تعفي — لحظة بدئها تُحسب كبصمة حضور.
    or exists (
      select 1 from public.mission_executions me
      join public.requests rq on rq.id = me.request_id
      where me.employee_id = p_employee_id
        and me.status in ('in_progress', 'completed')
        and rq.status not in ('rejected', 'cancelled', 'returned')
        and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
        and me.started_at <= public.employee_lateness_deadline(p_employee_id, p_work_date)
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
    -- طلب مأمورية معتمد أو جارٍ قُدِّم قبل نهاية سماح اليوم (0655) ولم تسبقه بصمة مقر متأخرة
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status in ('approved', 'in_progress', 'pending')
        and r.created_at <= public.employee_lateness_deadline(p_employee_id, p_work_date)
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
$function$;

CREATE OR REPLACE FUNCTION public.is_employee_exempt_from_instant_penalty(p_employee_id uuid, p_work_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- 6) مأمورية بدأت اليوم (0655): تعفي فقط إن بدأت في الموعد (قبل نهاية السماح)،
  --    ولم يُرفض طلبها أو يُسحب، ولم تسبقها بصمة مقر متأخرة. المأمورية المتأخرة
  --    تُعامل كبصمة حضور متأخرة (start_my_mission يسجّل تأخيرها).
  if exists (
    select 1 from public.mission_executions me
      join public.requests rq on rq.id = me.request_id
     where me.employee_id = p_employee_id
       and me.status in ('in_progress', 'completed')
       and rq.status not in ('rejected', 'cancelled', 'returned')
       and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
       and me.started_at <= public.employee_lateness_deadline(p_employee_id, p_work_date)
       and not exists (
         select 1 from public.attendance_events ae
          where ae.employee_id = p_employee_id
            and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
            and ae.event_type = 'CHECK_IN'
            and ae.status in ('accepted', 'adjusted')
            and ae.source not in ('mission_auto')
            and coalesce(ae.late_minutes, 0) > 0
            and ae.event_at < me.started_at)
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل بدأت في موعد الدوام'
    );
  end if;

  -- 7) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload, r.created_at
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled', 'returned')
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
  loop
    -- مأمورية/قافلة/فاندي: تعفي فقط إن قُدِّمت قبل نهاية سماح اليوم (0655) ولم تسبقها
    -- بصمة مقر متأخرة. (كان الشرط يشير إلى r خارج الاستعلام فيُسقط الدالة 42P01
    -- ويوقف حساب الغرامات كلها وبصمة المتأخر.)
    if v_req.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
       or coalesce(v_req.payload->>'missionType', v_req.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy') then
      if v_req.created_at > public.employee_lateness_deadline(p_employee_id, p_work_date)
         or exists (
        select 1 from public.attendance_events ae
         where ae.employee_id = p_employee_id
           and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date
           and ae.event_type = 'CHECK_IN'
           and ae.status in ('accepted', 'adjusted')
           and ae.source not in ('mission_auto')
           and coalesce(ae.late_minutes, 0) > 0
           and ae.event_at < v_req.created_at
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
$function$;

CREATE OR REPLACE FUNCTION public.start_my_mission(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me                     uuid := public.current_employee_id();
  v_req                    public.requests;
  v_today                  date := (now() at time zone 'Africa/Cairo')::date;
  v_id                     uuid;
  v_end                    date;
  v_geofence_id            uuid;
  v_has_prior_office_punch boolean := false;
  v_late                   integer := 0;
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

  -- 0655: بدء المأمورية بصمة حضور — تأخيرها يُحسب كأي بصمة (صفر إن بدأت في الموعد)
  v_late := coalesce(public.attendance_policy_late_minutes(v_me, v_today, coalesce(v_req.created_at, now())), 0);

  -- تسجيل الحضور اليومي
  if not v_has_prior_office_punch then
    insert into public.attendance_daily (
      employee_id, work_date, status, first_check_in, late_minutes, updated_at
    ) values (
      v_me, v_today, 'present', coalesce(v_req.created_at, now()), v_late, now()
    ) on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          status = 'present',
          late_minutes = v_late,
          updated_at = now();

    update public.attendance_events
       set late_minutes = v_late
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today;

    -- إلغاء غرامة اليوم فقط إن بدأت المأمورية في الموعد
    if v_late = 0 then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: بدء مأمورية عمل في موعد الدوام',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: بدء مأمورية عمل في موعد الدوام',
             updated_at = now()
       where employee_id = v_me
         and work_date = v_today
         and status in ('pending_payment', 'doubled');
    end if;
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
      false, 'mission_auto', 'auto_check_in_from_mission_start', v_late
    );
  end if;

  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.trg_fn_cancel_penalties_on_request_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_start date;
  v_end date;
  v_type text;
  v_reason text;
begin
  v_type := coalesce(NEW.request_type, '');
  if v_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave',
                'mission', 'external_mission', 'administrative_mission',
                'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
     or coalesce(NEW.payload->>'missionType', NEW.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission') then

    if NEW.status in ('approved', 'completed', 'pending') then
      v_start := coalesce((NEW.payload->>'startDate')::date, (NEW.payload->>'start_date')::date);
      v_end   := coalesce((NEW.payload->>'endDate')::date, (NEW.payload->>'end_date')::date, v_start);

      if v_start is not null then
        v_reason := case
          when v_type like '%mission%' or coalesce(NEW.payload->>'missionType', '') = 'mission' then 'مأمورية عمل رسمية'
          when v_type like '%convoy%' or coalesce(NEW.payload->>'missionType', '') = 'convoy' then 'قافلة ميدانية'
          when v_type in ('fundraising', 'fandy', 'fundi') or coalesce(NEW.payload->>'missionType', '') in ('fundraising', 'fandy') then 'فعالية فاندي / جمع تبرعات'
          else 'إجازة رسمية'
        end;

        -- إلغاء الغرامات المعلقة في هذه التواريخ. 0655: المأمورية/القافلة/الفاندي
        -- لا تُلغي غرامة يوم قُدِّمت فيه بعد نهاية السماح (كان فتحها متأخرًا يمسح الغرامة).
        update public.instant_attendance_penalties p
           set status = 'cancelled',
               notes = coalesce(p.notes || ' | ', '') || 'إلغاء تلقائي: ' || v_reason || ' (طلب رقم ' || substr(NEW.id::text, 1, 8) || ')',
               updated_at = now()
         where p.employee_id = NEW.employee_id
           and p.work_date between v_start and v_end
           and p.status in ('pending_payment', 'doubled', 'suspended')
           and (v_reason = 'إجازة رسمية'
                or NEW.created_at <= public.employee_lateness_deadline(NEW.employee_id, p.work_date));

        -- فحص رفع تعليق الموظف
        if not exists (
          select 1 from public.instant_attendance_penalties
           where employee_id = NEW.employee_id
             and status in ('doubled', 'suspended')
        ) then
          update public.employees set is_active = true where id = NEW.employee_id;
        end if;
      end if;
    end if;
  end if;
  return NEW;
end;
$function$;
