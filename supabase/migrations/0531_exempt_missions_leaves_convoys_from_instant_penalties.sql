-- =====================================================================
-- 0531: إعفاء كامل للموظفين في المأموريات والإجازات والقوافل والفاندي
--       من الغرامات الفورية للتأخير وإلغاء الغرامات المعلقة تلقائياً
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة مركزية موحدة لفحص هل الموظف معفى من غرامة الحضور في تاريخ معين
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
  -- أ) المدير التنفيذي معفى دائماً من نظام الحضور والغرامات
  if public.is_employee_executive(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'executive',
      'reason', 'المدير التنفيذي معفى رسمياً من نظام الحضور والانصراف والغرامات'
    );
  end if;

  -- ب) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- ج) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- د) فحص الإجازات المعتمدة أو قيد المراجعة في جدول leave_requests
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

  -- هـ) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
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
     limit 1
  loop
    v_loc := coalesce(nullif(v_req.payload->>'location', ''), 'ميدانية');
    if v_req.request_type = 'mission' or coalesce(v_req.payload->>'missionType', '') = 'mission' then
      return jsonb_build_object(
        'isExempt', true,
        'category', 'mission',
        'reason', 'مأمورية عمل رسمية (' || v_loc || ')'
      );
    elsif v_req.request_type in ('convoy', 'field_convoy') or coalesce(v_req.payload->>'missionType', '') = 'convoy' then
      return jsonb_build_object(
        'isExempt', true,
        'category', 'convoy',
        'reason', 'قافلة ميدانية معتمدة أو قيد التنفيذ'
      );
    elsif v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy') then
      return jsonb_build_object(
        'isExempt', true,
        'category', 'fandy',
        'reason', 'فعالية فاندي / جمع تبرعات'
      );
    else
      return jsonb_build_object(
        'isExempt', true,
        'category', v_req.request_type,
        'reason', 'طلب رسمي معتمد أو قيد الاعتماد (' || v_req.request_type || ')'
      );
    end if;
  end loop;

  -- و) فحص تكليفات العمل الرسمية (work_assignments)
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.status in ('APPROVED', 'IN_PROGRESS', 'COMPLETED', 'SUBMITTED')
     and wa.assignment_type in ('MISSION', 'CONVOY', 'FUNDRAISING')
     and p_work_date between (wa.start_at at time zone 'Africa/Cairo')::date
                         and (wa.end_at at time zone 'Africa/Cairo')::date
     and (
       wa.created_by_employee_id = p_employee_id
       or wa.responsible_employee_id = p_employee_id
       or exists (
         select 1 from public.work_assignment_participants wap
          where wap.assignment_id = wa.id
            and wap.employee_id = p_employee_id
       )
     )
   limit 1;

  if v_wa.assignment_type is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', lower(v_wa.assignment_type),
      'reason', 'تكليف عمل رسمي: ' || coalesce(v_wa.title, v_wa.assignment_type)
    );
  end if;

  -- ز) فحص سجل الحضور اليومي إذا كان مثبتاً فيه الإعفاء (إجازة أو عطلة)
  select ad.status into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if v_att.status in ('on_leave', 'holiday', 'weekend') then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'attendance_record',
      'reason', 'سجل الحضور اليومي مثبت كـ ' || v_att.status
    );
  end if;

  -- ليس معفى
  return jsonb_build_object(
    'isExempt', false,
    'category', null,
    'reason', null
  );
end;
$$;

grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) ترقية دالة توليد الغرامة لمنع تسجيل أي غرامة للموظف المعفى
-- ─────────────────────────────────────────────────────────────────────

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

  -- 1. فحص الإعفاء (مأمورية / إجازة / قافلة / فاندي / مدير تنفيذي / عطلة)
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
-- 3) ترقية المحرك التلقائي لاستبعاد المعفيين وإلغاء الغرامات المعلقة تلقائياً
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

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة لموظفين لديهم إعفاء اليوم
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.work_date = v_today
       and p.status in ('pending_payment', 'doubled', 'suspended')
  loop
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_today);
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
    -- فحص الإعفاء الشامل (مأمورية / إجازة / قافلة / فاندي / مدير تنفيذي)
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    -- فحص سجل الحضور اليومي للموظف
    select ad.first_check_in, ad.late_minutes, ad.status
      into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today;

    if v_att.first_check_in is not null then
      -- بصم متأخراً بعد فترة السماح
      if coalesce(v_att.late_minutes, 0) > 15 then
        v_penalty_minutes := v_att.late_minutes;
        v_notes := 'تأخير حضور فعلي: ' || v_penalty_minutes || ' دقيقة (سجل بصمته ' || to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM') || ')';
        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
    else
      -- لم يبصم حتى الآن
      v_penalty_minutes := v_elapsed_mins;
      v_notes := 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')';
      perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
      v_processed := v_processed + 1;
    end if;
  end loop;

  return v_processed;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalties.cron_error', 'cron', 'error',
      'instant_attendance_penalties', null,
      'خطأ في المعالجة التلقائية للغرامات الفورية: ' || SQLERRM,
      null,
      jsonb_build_object('error', SQLERRM, 'detail', SQLSTATE)
    );
    return 0;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) ترقية تريجر البصمة لعدم تغريم الموظف العائد من مأمورية أو قافلة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.trg_fn_instant_penalty_on_punch()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_exempt jsonb;
begin
  if NEW.first_check_in is not null and coalesce(NEW.late_minutes, 0) > 15 then
    -- فحص الإعفاء أولاً
    v_exempt := public.is_employee_exempt_from_instant_penalty(NEW.employee_id, NEW.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      return NEW;
    end if;

    perform public.generate_instant_penalty(
      NEW.employee_id,
      NEW.work_date,
      NEW.late_minutes,
      'تأخير حضور فعلي: ' || NEW.late_minutes || ' دقيقة'
    );
  end if;
  return NEW;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تريجر تلقائي على جدول requests لإلغاء أي غرامات فورية عند تقديم أو اعتماد طلب
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.trg_fn_cancel_penalties_on_request_change()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
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

        -- إلغاء أي غرامات معلقة في هذه التواريخ
        update public.instant_attendance_penalties
           set status = 'cancelled',
               notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || v_reason || ' (طلب رقم ' || substr(NEW.id::text, 1, 8) || ')',
               updated_at = now()
         where employee_id = NEW.employee_id
           and work_date between v_start and v_end
           and status in ('pending_payment', 'doubled', 'suspended');

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
$$;

drop trigger if exists trg_cancel_penalties_on_request_change on public.requests;
create trigger trg_cancel_penalties_on_request_change
after insert or update of status, payload
on public.requests
for each row
execute function public.trg_fn_cancel_penalties_on_request_change();

-- ─────────────────────────────────────────────────────────────────────
-- 6) تصحيح وتنظيف البيانات السابقة (Retroactive Data Cleanup)
--    إلغاء جميع الغرامات المعلقة والمضاعفة الصادرة لموظفين لديهم مأمورية/إجازة/قافلة/فاندي
-- ─────────────────────────────────────────────────────────────────────

do $$
declare
  r record;
  v_ex jsonb;
  v_cancelled_count integer := 0;
begin
  for r in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
  loop
    v_ex := public.is_employee_exempt_from_instant_penalty(r.employee_id, r.work_date);
    if coalesce((v_ex->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء بأثر رجعي: ' || (v_ex->>'reason'),
             updated_at = now()
       where id = r.id;

      v_cancelled_count := v_cancelled_count + 1;

      -- فحص رفع التعليق
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = r.employee_id
           and status in ('doubled', 'suspended')
           and id != r.id
      ) then
        update public.employees set is_active = true where id = r.employee_id;
      end if;
    end if;
  end loop;

  raise notice 'تم إلغاء % غرامة غير مستحقة لموظفين في مأموريات/إجازات/قوافل/فاندي بنجاح', v_cancelled_count;
end;
$$;

commit;
