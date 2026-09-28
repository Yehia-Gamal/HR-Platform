-- =====================================================================
-- 0568: إعفاء كامل لطلبات الإجازات والمأموريات وأذونات الحضور من تذكيرات البصمة والغرامات الفورية
-- =====================================================================
-- المشكلة المعالجة:
-- 1. عندما يطلب الموظف إجازة أو مأمورية أو إذن حضور (سواء كان قيد المراجعة أو معتمداً)،
--    كان النظام يستمر في إرسال تذكيرات البصمة ("⚠️ تأخير في الحضور - لم تسجل بصمة حضورك")،
--    ويوقع عليه الغرامة الفورية تلقائياً!
-- 2. دالة is_employee_exempt_from_instant_penalty لم تكن تفحص أذونات الحضور (late_permit, permit)،
--    وكانت تفحص فقط الحالات المعتمدة وتتجاهل الطلبات قيد المراجعة، مما يؤدي لتغريم الموظف أثناء انتظار الموافقة.
-- 3. دالة generate_punch_reminders كانت تفتقر تماماً لفحص طلبات الإجازات والمأموريات والأذونات،
--    ولا تفحص الإعفاءات الدائمة للموظفين.
-- 4. إعادة تثبيت الإعفاء الإداري الدائم للقيادات وإلغاء الغرامات الخاطئة الناتجة عن هذا الخلل.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تحديث أعلام الإعفاء في جدول الموظفين للقيادات
-- ─────────────────────────────────────────────────────────────────────
update public.employees
   set is_attendance_exempt = true,
       is_penalty_exempt = true,
       updated_at = now()
 where id in (
   'b452c987-ae08-4e12-8433-272cc66c85f9', -- يحيى جمال السبع
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف
   '886f4942-c469-4a03-8f02-659fd02c4a02', -- الشيخ محمد يوسف (أرشيف)
   '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
   'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
   '8e21d363-f87c-4c80-b06d-1b84a2dd3804'  -- هاني احمد نصير
 )
 or phone_e164 in (
   '+201154869616', '01154869616',
   '+201121622820', '01121622820',
   '+201226905602', '01226905602',
   '+201000867705', '01000867705',
   '+201016664229', '01016664229',
   '+201012141949', '01012141949'
 );

-- ─────────────────────────────────────────────────────────────────────
-- 2) دالة فحص الإعفاء الدائم من الحضور والانصراف
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_attendance_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 1. فحص العلم المباشر في جدول الموظفين
  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 2. الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع)
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_rec.full_name_ar ilike '%يحيى%جمال%' then
    return true;
  end if;

  -- 3. شبكة أمان كبار المسؤولين والقيادات
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02',
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
    '8e21d363-f87c-4c80-b06d-1b84a2dd3804'  -- هاني احمد نصير
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229', '+201012141949')
    or v_rec.phone_e164 in ('+201121622820', '01121622820', '+201226905602', '01226905602', '+201000867705', '01000867705', '+201016664229', '01016664229', '+201012141949', '01012141949')
    or v_rec.full_name_ar ilike '%محمد يوسف%'
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%عبدالباسط%'
    or v_rec.full_name_ar ilike '%الباسل%'
    or v_rec.full_name_ar ilike '%عبدالله%نصر%'
    or v_rec.full_name_ar ilike '%هاني%نصير%' then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) دالة فحص الإعفاء الدائم من الغرامات الفورية
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  -- أي موظف معفى من الحضور فهو معفى تلقائياً من غرامات الحضور والانصراف
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_penalty_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) دالة الفحص الشامل للإعفاء من الغرامة في تاريخ محدد
--    يشمل: إذن الحضور، الإجازة، المأمورية، القافلة، الفاندي (معتمدة أو مقدمة)
-- ─────────────────────────────────────────────────────────────────────
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

  -- 4) فحص الإجازات في جدول leave_requests (معتمدة أو قيد المراجعة / طلب مقدم)
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
  --    الموظف الذي طلب إذن حضور أو تأخير يُعفى من غرامة ذلك اليوم
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
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permit',
      'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
    );
  end loop;

  -- 6) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
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
    v_loc := case
      when v_req.request_type in ('convoy', 'field_convoy') or coalesce(v_req.payload->>'missionType', '') = 'convoy' then 'قافلة ميدانية'
      when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') = 'fundraising' then 'فاندي (جمع تبرعات)'
      when v_req.request_type in ('mission', 'external_mission', 'administrative_mission') then 'مأمورية عمل'
      when v_req.request_type = 'remote_work' then 'عمل عن بعد'
      when v_req.request_type = 'compensation' then 'يوم راحة تعويضي'
      else 'إجازة رسمية'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', v_req.request_type,
      'reason', v_loc || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end loop;

  -- 7) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.responsible_employee_id = p_employee_id
     and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
     and p_work_date between wa.start_at::date and wa.end_at::date
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

  -- 8) فحص حالة الحضور اليومي في attendance_daily
  select ad.status into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date
   limit 1;

  if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
    return jsonb_build_object(
      'isExempt', true,
      'category', v_att.status,
      'reason', case v_att.status
        when 'on_leave' then 'مسجل في عطلة/إجازة رسمية'
        when 'mission'  then 'مسجل في مأمورية عمل'
        when 'excused'  then 'معذور رسمياً في سجل الحضور'
        when 'holiday'  then 'عطلة رسمية'
        when 'weekend'  then 'راحة أسبوعية'
        else v_att.status
      end
    );
  end if;

  -- الموظف غير معفى
  return jsonb_build_object(
    'isExempt', false,
    'category', 'none',
    'reason', null
  );
end;
$$;

grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث دالة تذكيرات البصمة generate_punch_reminders
--    استثناء الموظفين المعفيين، والذين لديهم إجازة أو مأمورية أو إذن حضور
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.generate_punch_reminders(p_lead_minutes integer default 15)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  -- قفل استشاري يمنع تشغيلَين متزامنين للوظيفة
  perform pg_advisory_xact_lock(hashtext('generate_punch_reminders'));
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة فقط عطلة (السبت=6، الأحد=7، الإثنين..الخميس=1..4)
  if v_dow = 5 then
    return 0;
  end if;

  -- استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- الوردية الرسمية الحالية
  select * into v_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  if v_shift.id is null then
    return 0;
  end if;

  for v_emp in
    select e.id as employee_id, e.user_id, e.is_attendance_exempt, e.is_penalty_exempt
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
      -- استثناء: المدير التنفيذي + مدير العمليات (لا يسجلون بصمة)
      and not exists (
        select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive', 'executive-director', 'operations-manager-1')
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
  loop
    -- 1. استثناء الموظف المعفى دائماً بقرار إداري
    if coalesce(v_emp.is_attendance_exempt, false) = true
       or coalesce(v_emp.is_penalty_exempt, false) = true
       or public.is_employee_attendance_exempt(v_emp.employee_id)
       or public.is_employee_penalty_exempt(v_emp.employee_id) then
      continue;
    end if;

    -- 2. استثناء الموظف المكلف بمهمة عمل أو قافلة رسمية اليوم
    if exists (
      select 1 from public.work_assignments wa
      where wa.responsible_employee_id = v_emp.employee_id
        and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
        and v_today between wa.start_at::date and wa.end_at::date
    ) then
      continue;
    end if;

    -- 3. استثناء الموظف إذا كان لديه طلب إجازة مسجل أو معتمد في leave_requests
    if exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and v_today between lr.start_date and lr.end_date
    ) then
      continue;
    end if;

    -- 4. استثناء الموظف إذا كان لديه طلب (إجازة، مأمورية، قافلة، فاندي، عمل عن بعد، تعويض) في requests
    if exists (
      select 1 from public.requests r
      where r.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          -- إجازة
          (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
           and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                           and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- مأمورية عمل
          or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- قافلة ميدانية
          or (r.request_type in ('convoy', 'field_convoy')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- فاندي / جمع تبرعات
          or (r.request_type in ('fundraising', 'fandy', 'fundi')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- داخل payload
          or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- عمل عن بعد أو تعويض
          or (r.request_type in ('remote_work', 'compensation')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
        )
    ) then
      continue;
    end if;

    -- 5. سجل اليوم للموظف
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id
      and work_date = v_today;

    -- إذا كانت حالة الحضور اليومي معذورة بالفعل
    if v_daily.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

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

    -- 6. فحص أذونات الحضور والانصراف:
    -- أ) في حالة تذكير الحضور أو تنبيه التأخر (before_in أو late_in):
    -- إذا كان الموظف قد طلب إذن حضور/تأخير (late_permit, permit, permission) لا نرسل له تذكيراً
    if v_kind in ('before_in', 'late_in') then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    -- ب) في حالة تذكير الانصراف (before_out):
    -- إذا كان الموظف لديه إذن انصراف مبكر (early_permit, permit) لا نرسل له تذكيراً
    if v_kind = 'before_out' then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('early_permit', 'permit')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    -- منع التكرار: نفس (المستخدم/اليوم/النوع) مرة واحدة
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

revoke all on function public.generate_punch_reminders(integer) from public, anon;
grant execute on function public.generate_punch_reminders(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 6) تحديث auto_generate_instant_penalties وإلغاء الغرامات الخاطئة
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_now_cairo::date;
  v_time_cairo time := v_now_cairo::time;
  v_isodow integer := extract(isodow from v_now_cairo)::integer;
  v_elapsed_mins integer;
  v_processed integer := 0;
  v_emp record;
  v_att record;
  v_penalty_minutes integer;
  v_notes text;
  v_exempt jsonb;
  v_pen record;
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1. استثناء عطلة الجمعة
  if v_isodow = 5 then
    return 0;
  end if;

  -- 2. استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة أو مضاعفة لموظفين لديهم إعفاء أو إذن أو مأمورية أو إجازة
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
  loop
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_pen.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'معفى من الغرامة'),
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'معفى من الغرامة'),
             updated_at = now()
       where id = v_pen.id;

      -- رفع التعليق إن لم تكن هناك غرامات مضاعفة أخرى
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = v_pen.employee_id
           and status in ('doubled', 'suspended')
           and id != v_pen.id
      ) then
        update public.employees set is_active = true, status = 'active' where id = v_pen.employee_id;
      end if;
    end if;
  end loop;

  -- 4. قبل انتهاء فترة السماح (10:15 ص): لا توجد غرامات
  if v_time_cairo <= '10:15:00'::time then
    return 0;
  end if;

  -- حساب الدقائق المنقضية منذ 10:00 ص
  v_elapsed_mins := floor(extract(epoch from (v_time_cairo - '10:00:00'::time)) / 60)::integer;
  if v_elapsed_mins <= 15 then
    return 0;
  end if;

  -- 5. فحص جميع الموظفين النشطين
  for v_emp in
    select e.id as employee_id, e.full_name_ar
      from public.employees e
     where e.is_active = true
       and e.is_deleted = false
       and e.status = 'active'
  loop
    -- فحص الإعفاء الشامل (إذن حضور، إجازة، مأمورية، قافلة، إعفاء دائم)
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    -- فحص سجل الحضور اليومي للموظف
    select ad.id, ad.status, ad.late_minutes, ad.first_check_in into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today
     limit 1;

    -- إذا كانت حالة السجل تشير إلى إجازة أو مأمورية أو عذر
    if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- الحالة أ: الموظف بصم حضوراً ولديه تأخير فعلي
    if v_att.id is not null and v_att.first_check_in is not null then
      if coalesce(v_att.late_minutes, 0) > 15 then
        v_penalty_minutes := v_att.late_minutes;
        v_notes := 'تأخير حضور فعلي (' || v_penalty_minutes || ' دقيقة) — وقت البصمة: ' ||
                   to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM');
        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
      continue;
    end if;

    -- الحالة ب: الموظف لم يسجل بصمة حضور حتى الآن وتجاوزنا 10:15 ص
    v_penalty_minutes := v_elapsed_mins;
    v_notes := 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (' ||
               to_char(v_now_cairo, 'HH12:MI AM') || ')';

    perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;

revoke all on function public.auto_generate_instant_penalties() from public, anon;
grant execute on function public.auto_generate_instant_penalties() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 7) إلغاء الغرامات المسجلة اليوم (2026-09-28) للموظفين المعفيين
-- ─────────────────────────────────────────────────────────────────────
update public.instant_attendance_penalties p
   set status = 'cancelled',
       cancelled_reason = 'إلغاء بأثر رجعي: ' || coalesce(
         (public.is_employee_exempt_from_instant_penalty(p.employee_id, p.work_date)->>'reason'),
         'معفى لوجود إذن أو مأمورية أو إجازة أو إعفاء دائم'
       ),
       notes = coalesce(notes || ' | ', '') || 'إلغاء: معفى من الغرامة',
       updated_at = now()
 where p.work_date = '2026-09-28'
   and p.status in ('pending_payment', 'doubled', 'suspended')
   and coalesce((public.is_employee_exempt_from_instant_penalty(p.employee_id, p.work_date)->>'isExempt')::boolean, false) = true;

-- رفع التعليق عن أي موظف تم إيقافه خطأً
update public.employees
   set status = 'active',
       is_active = true,
       updated_at = now()
 where id in (
   select distinct employee_id
     from public.instant_attendance_penalties
    where work_date = '2026-09-28'
      and status = 'cancelled'
 )
 and not exists (
   select 1 from public.instant_attendance_penalties
    where employee_id = employees.id
      and status in ('doubled', 'suspended')
 );

commit;
