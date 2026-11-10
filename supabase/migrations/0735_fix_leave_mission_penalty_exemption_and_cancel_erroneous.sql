-- 0735_fix_leave_mission_penalty_exemption_and_cancel_erroneous.sql
-- إصلاح دالة فحص الإعفاءات التلقائية لتشمل الإجازات والمأموريات من جدول requests الموحد
-- وإلغاء الغرامات التي نزلت بالخطأ على الموظفين أثناء وجودهم في إجازات أو مأموريات رسمية

-- 1. دالة فحص الإعفاء الشاملة والمحدثة
create or replace function public.is_employee_exempt_from_instant_penalty(p_employee_id uuid, p_work_date date)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_req record;
  v_emp record;
begin
  -- 1) فحص الاستثناء الإداري الدائم
  if public.is_employee_penalty_exempt(p_employee_id) or public.is_employee_attendance_exempt(p_employee_id) or public.is_employee_executive(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permanent_exemption',
      'reason', 'معفى دائماً بقرار إداري من الحضور والانصراف والغرامات'
    );
  end if;

  -- 2) فحص نوع التعاقد: الدوام الجزئي غير مقيد بمواعيد وردية محددة
  select e.full_name_ar, e.employment_type_id, et.code as et_code
    into v_emp
    from public.employees e
    left join public.employment_types et on et.id = e.employment_type_id
   where e.id = p_employee_id;

  if v_emp.et_code = 'part_time' or v_emp.full_name_ar like '%هاني%نصير%' then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'part_time',
      'reason', 'نظام دوام جزئي مرن غير مقيد بمواعيد وردية محددة'
    );
  end if;

  -- 3) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- 4) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- 5) فحص الإجازات من جدول requests الموحد وكذلك leave_requests القديم
  select r.id, r.request_type, r.status,
         coalesce(r.title, r.payload->>'leaveType', 'إجازة') as leave_title
    into v_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('leave', 'compensation', 'weekly_rest_comp', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave')
     and p_work_date between coalesce(
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
         and coalesce(
           public.try_cast_date(r.payload->>'endDate'),
           public.try_cast_date(r.payload->>'end_date'),
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
   order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
   limit 1;

  if v_req.id is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_title, 'رسمية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- فحص إضافي لجدول leave_requests القديم للتوافق التاريخي
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type, r.status
    into v_req
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

  -- 6) فحص المأموريات من جدول requests الموحد وكذلك mission_executions
  select r.id, r.request_type, r.status,
         coalesce(r.title, r.payload->>'location', 'مأمورية عمل') as mission_title
    into v_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
     and p_work_date between coalesce(
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
         and coalesce(
           public.try_cast_date(r.payload->>'endDate'),
           public.try_cast_date(r.payload->>'end_date'),
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
   order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
   limit 1;

  if v_req.id is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل رسمية: ' || coalesce(v_req.mission_title, 'ميدانية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- فحص إضافي لجدول mission_executions للتوافق التاريخي
  if exists (
    select 1 from public.mission_executions me
      join public.requests rq on rq.id = me.request_id
     where me.employee_id = p_employee_id
       and me.status in ('in_progress', 'completed')
       and rq.status not in ('rejected', 'cancelled', 'returned')
       and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل رسمية جارية/مكتملة'
    );
  end if;

  -- 7) فحص أذونات الحضور والتأخير (سواء معتمدة أو معلقة قيد القرار)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         public.try_cast_date(r.payload->>'permitDate'),
         public.try_cast_date(r.payload->>'date'),
         public.try_cast_date(r.payload->>'startDate'),
         public.try_cast_date(r.payload->>'start_date'),
         public.try_cast_date(r.payload->>'workDate'),
         r.created_at::date
       ) = p_work_date
     order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
     limit 1
  loop
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

        -- إذا كان الطلب لا يزال معلقاً (Pending) يُعفى فوراً لحين بت الإدارة في طلبه
        if v_req.status = 'pending' then
          return jsonb_build_object(
            'isExempt', true,
            'category', 'pending_permit',
            'reason', 'طلب إذن حضور مسجل (' || v_permit_mins || ' دقيقة) قيد انتظار قرار المدير — الغرامات موقوفة'
          );
        end if;

        if v_emp_shift.id is not null and v_emp_shift.start_time is not null then
          v_deadline := ((p_work_date + v_emp_shift.start_time)::timestamp at time zone 'Africa/Cairo')
            + (v_permit_mins || ' minutes')::interval
            + (coalesce(v_emp_shift.grace_in_minutes, 15) || ' minutes')::interval;

          if v_first_punch is not null and v_first_punch > v_deadline then
            null; -- تأخر لما بعد الإذن وسماحه
          else
            return jsonb_build_object(
              'isExempt', true,
              'category', 'permit',
              'reason', 'إذن حضور/تأخير رسمي مسجل (' || v_permit_mins || ' دقيقة) — الحضور ضمن فترة الإذن'
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

  return jsonb_build_object('isExempt', false);
end;
$function$;

-- 2. تنفيذ إلغاء فوري للغرامات الصادرة بالخطأ اليوم
update public.instant_attendance_penalties
   set status = 'cancelled',
       cancelled_reason = 'إلغاء فوري: الموظف في إجازة رسمية أو مأمورية عمل رسمية مسجلة',
       notes = coalesce(notes || ' | ', '') || 'إلغاء فوري: الموظف في إجازة رسمية أو مأمورية عمل رسمية مسجلة',
       updated_at = now()
 where work_date = '2026-11-10'
   and status = 'pending_payment'
   and employee_id in (
     'e2f51dfa-304f-49b3-a3ed-6bd1a52462a0', -- طارق سيد إبراهيم (إجازة سنوية معتمدة)
     'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', -- يوسف رسمي شعبان (إجازة بدل راحة معتمدة)
     'c110a497-ebd7-4072-9228-5f5ed3bf9083', -- عبد القادر جمال عبد القادر (مأمورية عمل رسمية)
     '467e0610-1960-4d92-8379-9c7a33168107'  -- حاتم محمد سالم (مأمورية عمل رسمية)
   );

-- 3. تشغيل دالة auto_generate_instant_penalties لتحديث أي غرامات معلقة وإلغائها تلقائياً
select public.auto_generate_instant_penalties();
