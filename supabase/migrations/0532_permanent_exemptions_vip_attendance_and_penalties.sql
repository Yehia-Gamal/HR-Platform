-- =====================================================================
-- 0532: استثناء دائم من الحضور والانصراف والغرامات
-- =====================================================================
-- 1) استثناء دائم من الحضور والانصراف والغرامات لكل من:
--    - ألشيخ محمد يوسف (المدير التنفيذي)
--    - محمد عبدالباسط (أبو عمار)
--    - عبدالعزيز طارق محمود الباسل
--    - عبدالله احمد نصر
-- 2) استثناء دائم من جميع الغرامات (دون إعفاء من الحضور) لـ:
--    - هاني احمد نصير
-- 3) إضافة أعمدة is_attendance_exempt و is_penalty_exempt في جدول employees
-- 4) تحديث دوال فحص الإعفاء والكرون التلقائي ودوال الحضور والانصراف
-- 5) إلغاء جميع الغرامات السابقة المعلقة وتصفير أي تعليق للحسابات
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) إضافة أعمدة الإعفاء في جدول employees
-- ─────────────────────────────────────────────────────────────────────

alter table public.employees
  add column if not exists is_attendance_exempt boolean not null default false,
  add column if not exists is_penalty_exempt boolean not null default false;

comment on column public.employees.is_attendance_exempt is
  '0532: هل الموظف مستثنى دائماً من تسجيل الحضور والانصراف وقوائم الغياب';

comment on column public.employees.is_penalty_exempt is
  '0532: هل الموظف مستثنى دائماً من الغرامات الفورية والخصومات المالية';

-- ─────────────────────────────────────────────────────────────────────
-- 2) تطبيق الإعفاءات الإدارية المحددة بالاسم والكود والـ ID
-- ─────────────────────────────────────────────────────────────────────

-- أ) إعفاء كامل من الحضور والانصراف والغرامات:
--    الشيخ محمد يوسف + أبو عمار + عبدالعزيز الباسل + عبدالله نصر
update public.employees
   set is_attendance_exempt = true,
       is_penalty_exempt = true,
       updated_at = now()
 where id in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
   '886f4942-c469-4a03-8f02-659fd02c4a02', -- ألشيخ محمد يوسف (أرشيف)
   '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
   'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- عبدالله احمد نصر
 )
 or employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229')
 or full_name_ar ilike '%محمد يوسف%'
 or full_name_ar ilike '%ابو عمار%'
 or full_name_ar ilike '%الباسل%'
 or full_name_ar ilike '%عبدالله%نصر%';

-- ب) إعفاء من الغرامات فقط (مع بقاء تسجيل الحضور): هاني احمد نصير
update public.employees
   set is_attendance_exempt = false,
       is_penalty_exempt = true,
       updated_at = now()
 where id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804' -- هاني احمد نصير
    or employee_code = '+201012141949'
    or full_name_ar ilike '%هاني%نصير%';

-- ─────────────────────────────────────────────────────────────────────
-- 3) دوال مركزية موحدة لفحص الإعفاء الدائم
-- ─────────────────────────────────────────────────────────────────────

-- دالة فحص الإعفاء من الحضور والانصراف
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

  -- 1. فحص المدير التنفيذي
  if public.is_employee_executive(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, full_name_ar, is_attendance_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 3. شبكة أمان بالمعرفات والأكواد والأسماء
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02',
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- عبدالله احمد نصر
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229')
    or v_rec.full_name_ar ilike '%محمد يوسف%'
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%الباسل%'
    or v_rec.full_name_ar ilike '%عبدالله%نصر%' then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.is_employee_attendance_exempt(uuid) is
  '0532: هل الموظف مستثنى دائماً بقرار إداري من الحضور والانصراف؟';

grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, anon;


-- دالة فحص الإعفاء من جميع الغرامات المالية
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

  -- 1. أي موظف معفى من الحضور فهو معفى حكماً من الغرامات
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, full_name_ar, is_penalty_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  -- 3. فحص هاني احمد نصير وشبكة أمان
  if p_employee_id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
     or v_rec.employee_code = '+201012141949'
     or v_rec.full_name_ar ilike '%هاني%نصير%' then
    return true;
  end if;

  return false;
end;
$$;

comment on function public.is_employee_penalty_exempt(uuid) is
  '0532: هل الموظف مستثنى دائماً بقرار إداري من جميع الغرامات الفورية؟';

grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة فحص الإعفاء من الغرامات الفورية للتأخير
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
  -- 1) فحص الاستثناء الإداري الدائم (الشيخ محمد يوسف، أبو عمار، عبدالعزيز الباسل، عبدالله نصر، هاني نصير)
  if public.is_employee_penalty_exempt(p_employee_id) then
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

  -- 4) فحص الإجازات المعتمدة أو قيد المراجعة في جدول leave_requests
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type into v_req
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    left join public.leave_types lt on lt.id = lr.leave_type_id
   where lr.employee_id = p_employee_id
     and r.status in ('approved', 'completed', 'pending')
     and p_work_date between lr.start_date and lr.end_date
   limit 1;

  if v_req.request_type is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_type, 'معتمدة') || ' (طلب رسمي مسجل)'
    );
  end if;

  -- 5) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status in ('approved', 'completed', 'pending')
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
      'reason', v_loc || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمدة)' end
    );
  end loop;

  -- 6) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
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

  -- 7) فحص حالة الحضور اليومي في attendance_daily
  select ad.status into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date
   limit 1;

  if v_att.status in ('on_leave', 'holiday', 'weekend') then
    return jsonb_build_object(
      'isExempt', true,
      'category', v_att.status,
      'reason', case v_att.status
        when 'on_leave' then 'مسجل في عطلة/إجازة رسمية'
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

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث دالة توليد الغرامة لمنع أي غرامة على المعفيين
-- ─────────────────────────────────────────────────────────────────────

drop function if exists public.generate_instant_penalty(uuid, date, integer);

create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
  v_exempt jsonb;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح)
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- 1. فحص الإعفاء الشامل
  v_exempt := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى من غرامات الحضور والانصراف: ' || (v_exempt->>'reason')
    );
  end if;

  -- 2. التحقق من الموظف
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and is_deleted = false and is_active = true;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود أو غير نشط' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- 3. حساب المبلغ بحسب الشرائح
  v_amount := public.calc_instant_penalty_amount(p_late_minutes);

  -- إذا كان التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15 = 0 ج.م)
  if v_amount <= 0.00 then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isGracePeriod', true,
      'amount', 0,
      'message', 'التأخير ضمن فترة السماح الرسمية (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة'
    );
  end if;

  v_default_notes := coalesce(p_notes, 'تأخير عن موعد العمل الرسمي (10:00 ص)');

  -- محاولة الإدخال
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, notes, created_by
  ) values (
    p_employee_id, p_work_date, p_late_minutes,
    v_amount, v_amount, 'EGP',
    'pending_payment', 'initial', v_default_notes, auth.uid()
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- إذا كانت الغرامة مسجلة مسبقاً لهذا اليوم:
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    -- إذا كانت لا تزال قيد السداد وكان المبلغ الجديد أكبر:
    if v_row.status = 'pending_payment' and v_amount > v_row.current_amount then
      update public.instant_attendance_penalties
         set late_minutes = p_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        v_emp_name || ': تزايد التأخير إلى ' || p_late_minutes || ' دقيقة — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'workDate', p_work_date::text,
          'lateMinutes', p_late_minutes,
          'amount', v_amount,
          'channel', 'instant_penalty'
        )
      );
    elsif v_row.status = 'pending_payment' and p_notes is not null then
      update public.instant_attendance_penalties
         set late_minutes = p_late_minutes,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'status', v_row.status,
      'currentAmount', v_row.current_amount,
      'notes', v_row.notes
    );
  end if;

  -- سجل التدقيق للغرامة الجديدة
  perform public.log_audit_event(
    'instant_penalty.issued', 'financial', 'warning',
    'instant_attendance_penalties', v_row.id,
    'غرامة تأخير فورية: ' || v_emp_name || ' (' || v_default_notes || ') — ' || v_amount || ' ج.م',
    null,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'lateMinutes', p_late_minutes,
      'amount', v_amount,
      'notes', v_default_notes
    )
  );

  -- إشعار المعنيين
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ غرامة تأخير فورية',
    v_emp_name || ': ' || v_default_notes || ' — غرامة فورية ' || v_amount || ' ج.م مطلوب سدادها اليوم.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'workDate', p_work_date::text,
      'lateMinutes', p_late_minutes,
      'amount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'employeeId', v_row.employee_id,
    'workDate', v_row.work_date,
    'lateMinutes', v_row.late_minutes,
    'originalAmount', v_row.original_amount,
    'currentAmount', v_row.current_amount,
    'status', v_row.status,
    'alreadyExists', false
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) تحديث auto_generate_instant_penalties وإلغاء الغرامات السابقة
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

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة أو مضاعفة لموظفين لديهم إعفاء
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
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_pen.id;

      -- رفع التعليق إن لم تكن هناك غرامات مضاعفة أخرى
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = v_pen.employee_id
           and status in ('doubled', 'suspended')
           and id != v_pen.id
      ) then
        update public.employees set is_active = true where id = v_pen.employee_id;
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
  loop
    -- فحص الإعفاء الشامل
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

-- ─────────────────────────────────────────────────────────────────────
-- 7) تحديث استعلامات ولوحات الحضور لاستبعاد المعفيين من الحضور
-- ─────────────────────────────────────────────────────────────────────

-- أ) get_attendance_today_overview
create or replace function public.get_attendance_today_overview(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $func$
declare
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
  v_is_friday boolean := (extract(isodow from p_date) = 5);
begin
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    or public.has_permission('attendance.record.read')
    or public.has_permission('people.employee.read')
    or current_user in ('postgres', 'service_role')
  ) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- 0532: استبعاد المعفيين دائماً من الحضور والانصراف (الشيخ محمد يوسف، أبو عمار، عبدالعزيز الباسل، عبدالله نصر)
  select count(*) into v_total_active
  from public.employees e
  where e.status = 'active'
    and coalesce(e.is_deleted, false) = false
    and not public.is_employee_attendance_exempt(e.id);

  select count(distinct lr.employee_id) into v_on_leave
  from public.leave_requests lr
  join public.requests req on req.id = lr.request_id
  where req.status = 'approved'
    and p_date between lr.start_date and lr.end_date
    and not public.is_employee_attendance_exempt(lr.employee_id);

  select count(distinct wa.responsible_employee_id) into v_on_assignment
  from public.work_assignments wa
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date
    and not public.is_employee_attendance_exempt(wa.responsible_employee_id);

  select count(distinct ae.employee_id) into v_present
  from public.attendance_events ae
  where ae.event_at::date = p_date and ae.event_type = 'CHECK_IN'
    and not public.is_employee_attendance_exempt(ae.employee_id);

  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_at::date = p_date
    and ae.event_type = 'CHECK_IN'
    and coalesce(ae.late_minutes, 0) > 0
    and not public.is_employee_attendance_exempt(ae.employee_id);

  if v_is_friday then
    v_expected := coalesce(v_on_assignment, 0);
  else
    v_expected := greatest(0, coalesce(v_total_active, 0) - coalesce(v_on_leave, 0) - coalesce(v_on_assignment, 0));
  end if;

  v_not_checked_in := greatest(0, coalesce(v_expected, 0) - coalesce(v_present, 0));
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', coalesce(v_total_active, 0),
    'expected', coalesce(v_expected, 0),
    'expectedToday', coalesce(v_expected, 0),
    'present', coalesce(v_present, 0),
    'late', coalesce(v_late, 0),
    'onLeave', coalesce(v_on_leave, 0),
    'onAssignment', coalesce(v_on_assignment, 0),
    'notCheckedIn', coalesce(v_not_checked_in, 0),
    'absent', coalesce(v_absent, 0),
    'isFriday', v_is_friday,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now(),
    'generatedAt', now()
  );
end;
$func$;

grant execute on function public.get_attendance_today_overview(date) to authenticated;


-- ب) get_attendance_dashboard
create or replace function public.get_attendance_dashboard(
  p_date          date default null,
  p_department_id uuid default null,
  p_branch_id     uuid default null,
  p_manager_id    uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_attendance_exempt(e.id)  -- 0532: استبعاد المعفيين من الحضور
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (
         p_manager_id is null or exists (
           select 1
             from public.manager_relations mr
            where mr.employee_id = e.id
              and mr.manager_employee_id = p_manager_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
         )
       )
  ), daily as (
    select d.*
      from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_assignments as (
    select distinct a.responsible_employee_id as employee_id
      from public.work_assignments a
      join params p on p.work_date between (a.start_at at time zone 'Africa/Cairo')::date
                                       and (a.end_at   at time zone 'Africa/Cairo')::date
      join visible_employees ve on ve.id = a.responsible_employee_id
     where a.status in ('APPROVED', 'IN_PROGRESS')
  ), excused_absent as (
    select distinct lr.employee_id
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      join params p on p.work_date between lr.start_date and lr.end_date
      join visible_employees ve on ve.id = lr.employee_id
     where r.status in ('approved', 'completed')
    union
    select employee_id from approved_assignments
    union
    select distinct r.employee_id
      from public.requests r
      join params p on (
        (r.request_type in ('leave', 'mission', 'convoy') and p.work_date between (r.payload->>'startDate')::date and (r.payload->>'endDate')::date)
        or (r.request_type = 'fundraising' and p.work_date between (r.payload->>'startDate')::date and (r.payload->>'endDate')::date)
      )
      join visible_employees ve on ve.id = r.employee_id
     where r.status in ('approved', 'completed')
  ), pending_excuse as (
    select distinct r.employee_id
      from public.requests r
      join params p on (
        (r.request_type in ('leave', 'mission', 'convoy') and p.work_date between (r.payload->>'startDate')::date and (r.payload->>'endDate')::date)
        or (r.request_type = 'fundraising' and p.work_date between (r.payload->>'startDate')::date and (r.payload->>'endDate')::date)
      )
      join visible_employees ve on ve.id = r.employee_id
     where r.status = 'pending'
  ), base_daily as (
    select
      ve.id as employee_id,
      coalesce(
        d.status,
        case
          when extract(isodow from (select work_date from params)) = 5 then 'weekend'
          when ex.employee_id is not null then 'excused'
          when pe.employee_id is not null then 'pending'
          else 'absent'
        end
      ) as derived_status,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce(d.early_leave_minutes, 0) as early_leave_minutes
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join excused_absent ex on ex.employee_id = ve.id
    left join pending_excuse pe on pe.employee_id = ve.id
  )
  select jsonb_build_object(
    'date', (select work_date from params),
    'scheduled', (select count(*) from visible_employees),
    'totalEmployees', (select count(*) from visible_employees),
    'expected', (
      select count(*) from visible_employees
      where (select extract(isodow from work_date) from params) <> 5
    ),
    'present', (select count(*) from base_daily where derived_status in ('present', 'late', 'partial')),
    'presentCount', (select count(*) from base_daily where derived_status in ('present', 'late', 'partial')),
    'late', (select count(*) from base_daily where late_minutes > 0 or derived_status = 'late'),
    'lateCount', (select count(*) from base_daily where late_minutes > 0 or derived_status = 'late'),
    'earlyLeave', (select count(*) from base_daily where early_leave_minutes > 0),
    'onLeave', (select count(*) from excused_absent),
    'excusedCount', (select count(*) from excused_absent),
    'pendingCount', (select count(*) from pending_excuse),
    'absent', (
      select count(*) from base_daily
      where derived_status = 'absent'
        and (select extract(isodow from work_date) from params) <> 5
    ),
    'unexcusedAbsent', (
      select count(*) from base_daily
      where derived_status = 'absent'
        and (select extract(isodow from work_date) from params) <> 5
    ),
    'isWeekend', ((select extract(isodow from work_date) from params) = 5),
    'firstCheckIn', (select min(e.event_at) filter (where e.event_type = 'CHECK_IN') from visible_events e),
    'lastCheckOut', (select max(e.event_at) filter (where e.event_type = 'CHECK_OUT') from visible_events e)
  );
$function$;

grant execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) to authenticated;


-- ج) get_attendance_day_roster
create or replace function public.get_attendance_day_roster(
  p_date          date default null,
  p_department_id uuid default null,
  p_branch_id     uuid default null,
  p_manager_id    uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
begin
  return coalesce((
    with base as (
      select
        e.id,
        e.full_name_ar,
        e.employee_code,
        e.photo_url,
        jt.name_ar as job_title,
        d.name_ar  as department,
        m.full_name_ar as manager_name,
        ad.status as att_status,
        ad.first_check_in,
        ad.last_check_out,
        ad.late_minutes,
        ad.early_leave_minutes,
        exists (
          select 1 from public.leave_requests lr
          join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id
            and r.status in ('approved', 'completed')
            and v_date between lr.start_date and lr.end_date
        ) as on_leave,
        (
          select wa.assignment_type
          from public.work_assignments wa
          where wa.responsible_employee_id = e.id
            and wa.status in ('APPROVED','IN_PROGRESS')
            and v_date between (wa.start_at at time zone 'Africa/Cairo')::date
                           and (wa.end_at   at time zone 'Africa/Cairo')::date
          limit 1
        ) as assignment_type
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.manager_relations mr on mr.employee_id = e.id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
      left join public.employees m on m.id = mr.manager_employee_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_date
      where e.status = 'active'
        and coalesce(e.is_deleted, false) = false
        and not public.is_employee_attendance_exempt(e.id) -- 0532: استبعاد المعفيين
        and (p_department_id is null or e.department_id = p_department_id)
        and (p_branch_id is null or e.branch_id = p_branch_id)
        and (
          p_manager_id is null or exists (
            select 1 from public.manager_relations mr2
            where mr2.employee_id = e.id
              and mr2.manager_employee_id = p_manager_id
              and mr2.effective_from <= now()
              and (mr2.effective_to is null or mr2.effective_to > now())
          )
        )
    ),
    classified as (
      select *,
        case
          when on_leave then 'on_leave'
          when assignment_type is not null then 'assignment'
          when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
          when att_status = 'present' then 'present'
          when att_status = 'late' then 'late'
          when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
          when last_check_out is not null then 'checked_out'
          when att_status = 'absent' then 'absent'
          when extract(isodow from v_date) = 5 then 'weekend'
          else 'not_yet'
        end as derived_status
      from base
    )
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'name', full_name_ar,
      'employeeCode', employee_code,
      'avatarUrl', photo_url,
      'jobTitle', job_title,
      'department', department,
      'managerName', manager_name,
      'status', derived_status,
      'attStatus', att_status,
      'firstCheckIn', first_check_in,
      'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes,
      'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave,
      'assignmentType', assignment_type
    ) order by full_name_ar)
    from classified
  ), '[]'::jsonb);
end;
$function$;

grant execute on function public.get_attendance_day_roster(date, uuid, uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 8) التنظيف الفوري بأثر رجعي لجميع الغرامات المعلقة والمضاعفة للمعفيين
-- ─────────────────────────────────────────────────────────────────────

update public.instant_attendance_penalties
   set status = 'cancelled',
       notes = coalesce(notes || ' | ', '') || 'إلغاء بأثر رجعي: استثناء دائم بقرار إداري من الغرامات',
       updated_at = now()
 where employee_id in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- ألشيخ محمد يوسف
   '886f4942-c469-4a03-8f02-659fd02c4a02',
   '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
   'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
   '8e21d363-f87c-4c80-b06d-1b84a2dd3804'  -- هاني احمد نصير
 )
 and status in ('pending_payment', 'doubled', 'suspended');

-- ضمان تفعيل الموظفين ورفع أي تعليق
update public.employees
   set is_active = true,
       status = 'active',
       updated_at = now()
 where id in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e',
   '767eae8e-e7be-458e-a6ca-879414e46b08',
   'fad7044c-fe47-4db3-b7bb-54856e7ba851',
   'c61c2a26-19db-49fb-ad8b-ace2d8a765af',
   '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
 );

commit;
