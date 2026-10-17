-- Migration 0671: اشتراط بصمة الانصراف للتأكيد الأمني لمنع التحايل + صندوق الوقت الإضافي
-- ==============================================================================
-- 1. اشتراط بصمة الانصراف:
--    إذا أتمّ الموظف 8 ساعات عمل وهو متواجد، يتم إرسال إشعار تذكيري له:
--    "أتممت 8 ساعات! برجاء تسجيل بصمة الانصراف من مقر العمل لتأكيد التواجد وإلغاء الغرامة".
--    ولا يتم الإلغاء النهائي للغرامة إلا عند تسجيل بصمة الانصراف الفعلية في أو بعد الـ 8 ساعات.
--    وإذا خرج دون بصمة انصراف (missing_checkout) تظل الغرامة مستحقة السداد ويلزمه دفعها.
--
-- 2. احتساب وتوثيق الوقت الإضافي (Overtime):
--    احتساب الدقائق والساعات الإضافية التي قضاها الموظف فوق ساعات العمل المقررة (الوردية/8 ساعات).
--    وتوفير RPC مخصص `get_daily_overtime_summary` لتغذية صندوق الوقت الإضافي في لوحة التحكم والتطبيق.
-- ==============================================================================

begin;

-- ─── 1) تحديث دالة إلغاء الغرامة باشتراط بصمة الانصراف التأكيدية ─────────────────
create or replace function public.auto_waive_penalty_if_completed_eight_hours(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_att record;
  v_pen record;
  v_work_minutes integer;
  v_emp_name text;
  v_mgr_id uuid;
  v_in_str text;
  v_out_str text;
  v_hours integer;
  v_mins integer;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_elapsed_minutes integer;
begin
  if p_employee_id is null or p_work_date is null then
    return jsonb_build_object('waived', false, 'reason', 'invalid_params');
  end if;

  -- 1. استعلام سجل الحضور اليومي
  select ad.id, ad.first_check_in, ad.last_check_out, ad.work_minutes
    into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if not found or v_att.first_check_in is null then
    return jsonb_build_object('waived', false, 'reason', 'no_checkin');
  end if;

  -- 2. فحص الغرامة الفورية المسجلة لذلك اليوم
  select p.id, p.current_amount, p.original_amount, p.status, p.escalation_level, p.notes
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if not found then
    return jsonb_build_object('waived', false, 'reason', 'no_active_penalty');
  end if;

  select e.full_name_ar into v_emp_name
    from public.employees e
   where e.id = p_employee_id;

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;

  -- 3. حالة الموظف الذي لم يسجل انصرافاً بعد (لا يزال متواجداً بالعمل اليوم)
  if v_att.last_check_out is null then
    if p_work_date = v_today then
      v_elapsed_minutes := floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', v_att.first_check_in))) / 60)::integer;
      
      -- إذا تجاوز 8 ساعات وهو متواجد: نرسل له إشعاراً وبانتظار بصمة الانصراف
      if v_elapsed_minutes >= 480 then
        -- إرسال إشعار تذكيري لتسجيل بصمة الانصراف لتأكيد التواجد
        if not exists (
          select 1 from public.notifications n
           where n.user_id = (select user_id from public.employees where id = p_employee_id)
             and n.category = 'instant_penalty'
             and n.metadata->>'promptType' = 'awaiting_checkout_confirmation'
             and n.created_at >= (now() - interval '8 hours')
        ) then
          perform public.notify_employee(
            p_employee_id,
            '🔔 أتممت 8 ساعات عمل — سجّل بصمة الانصراف',
            'عزيزي ' || coalesce(v_emp_name, '') || '، لقد أتممت 8 ساعات عمل بنجاح اليوم (' || (v_elapsed_minutes / 60) || ' ساعة و' || (v_elapsed_minutes % 60) || ' دقيقة). برجاء تسجيل بصمة الانصراف الآن من مقر العمل لتأكيد تواجدك وإلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) نهائياً.',
            'system',
            'high',
            'instant_penalty',
            v_pen.id,
            jsonb_build_object(
              'penaltyId', v_pen.id,
              'promptType', 'awaiting_checkout_confirmation',
              'elapsedMinutes', v_elapsed_minutes,
              'amount', v_pen.current_amount,
              'deepLink', 'ahlashabab://action/attendance'
            )
          );
        end if;

        return jsonb_build_object(
          'waived', false,
          'awaitingCheckout', true,
          'elapsedMinutes', v_elapsed_minutes,
          'message', 'أتم 8 ساعات وبانتظار بصمة الانصراف التأكيدية لإسقاط الغرامة'
        );
      else
        return jsonb_build_object(
          'waived', false,
          'elapsedMinutes', v_elapsed_minutes,
          'remainingMinutes', (480 - v_elapsed_minutes),
          'message', 'لم يكمل 8 ساعات بعد'
        );
      end if;
    else
      -- يوم سابق ولم يبصم انصراف (missing_checkout) → لا إعفاء وتظل الغرامة مستحقة
      return jsonb_build_object('waived', false, 'reason', 'missing_checkout_unwaived');
    end if;
  end if;

  -- 4. الموظف سجّل بصمة انصراف فعلية (last_check_out is not null)
  v_work_minutes := greatest(
    coalesce(v_att.work_minutes, 0),
    floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
  );

  -- إذا غادر قبل إتمام 8 ساعات عمل (أقل من 480 دقيقة)
  if v_work_minutes < 480 then
    return jsonb_build_object(
      'waived', false,
      'penaltyRemaining', true,
      'penaltyId', v_pen.id,
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'remainingMinutes', (480 - v_work_minutes),
      'message', 'الغرامة مستحقة لمغادرة العمل قبل إتمام 8 ساعات عمل'
    );
  end if;

  -- 5. الموظف سجّل بصمة انصراف رسمية وأتمّ 8 ساعات عمل (480 دقيقة أو أكثر) → إلغاء الغرامة نهائياً وتأكيد التواجد
  v_out_str := to_char(v_att.last_check_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (v_att.last_check_out at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_hours := v_work_minutes / 60;
  v_mins := v_work_minutes % 60;

  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء نهائي: تأكيد حضور وانصراف 8 ساعات عمل كاملة (تعويض التأخير)',
         notes = coalesce(notes || ' | ', '') ||
                 'تم تأكيد الحضور والانصراف وإلغاء الخصم لاستيفاء 8 ساعات كاملة بمقر العمل — الدخول: ' ||
                 v_in_str || '، الخروج: ' || v_out_str ||
                 ' (إجمالي العمل: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة)',
         updated_at = now()
   where id = v_pen.id;

  -- رفع التعليق إن كان موقوفاً بسبب هذه الغرامة
  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = p_employee_id
       and status in ('doubled', 'suspended')
       and id <> v_pen.id
  ) then
    update public.employees set is_active = true, status = 'active' where id = p_employee_id;
    update public.profiles set status = 'active' where employee_id = p_employee_id;
  end if;

  -- إرسال الإشعار النهائي للموظف بعد توثيق بصمة الانصراف
  perform public.notify_employee(
    p_employee_id,
    '🎉 تم تأكيد الانصراف وإلغاء غرامة التأخير نهائياً',
    'تم تأكيد بصمة انصرافك وإلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لاستيفائك 8 ساعات عمل كاملة بمقر العمل اليوم. (الحضور: ' || v_in_str || ' — الانصراف: ' || v_out_str || ' — الإجمالي: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة). شكراً لالتزامك!',
    'system',
    'high',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'waived', true,
      'reason', 'eight_hours_verified_on_checkout',
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  -- إشعار المدير المباشر
  select m.id into v_mgr_id
    from public.employees e
    join public.departments d on d.id = e.department_id
    join public.employees m on m.id = d.manager_id
   where e.id = p_employee_id;

  if v_mgr_id is not null and v_mgr_id <> p_employee_id then
    perform public.notify_employee(
      v_mgr_id,
      'إلغاء غرامة تأخير لموظف بالقسم بعد تسجيل الانصراف',
      'تم تأكيد بصمة انصراف الموظف (' || coalesce(v_emp_name, '') || ') بعد استيفاء 8 ساعات عمل كاملة اليوم، وألغى النظام غرامة التأخير (' || v_pen.current_amount || ' ج.م) تلقائياً.',
      'team',
      'normal',
      'instant_penalty',
      v_pen.id,
      jsonb_build_object('penaltyId', v_pen.id, 'employeeId', p_employee_id, 'waived', true)
    );
  end if;

  -- إشعار الموارد البشرية والمالية
  perform public.notify_employees_with_permission(
    'payroll.run.manage',
    'تأكيد انصراف وإلغاء غرامة تأخير (8 ساعات عمل)',
    'سجل الموظف ' || coalesce(v_emp_name, '') || ' انصرافه بعد استيفاء 8 ساعات كاملة وتم إلغاء الغرامة (' || v_pen.current_amount || ' ج.م) تلقائياً.',
    'system',
    'normal',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object('penaltyId', v_pen.id, 'employeeId', p_employee_id, 'workMinutes', v_work_minutes),
    p_employee_id
  );

  -- تسجيل حدث التدقيق الأمني
  perform public.log_audit_event(
    'instant_penalty.waived_on_checkout',
    'instant_attendance_penalties',
    v_pen.id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'work_date', p_work_date,
      'work_minutes', v_work_minutes,
      'check_out', v_att.last_check_out
    )
  );

  return jsonb_build_object(
    'waived', true,
    'penaltyId', v_pen.id,
    'amount', v_pen.current_amount,
    'workMinutes', v_work_minutes,
    'hours', v_hours,
    'minutes', v_mins,
    'checkIn', v_in_str,
    'checkOut', v_out_str,
    'employeeName', v_emp_name
  );
end;
$$;

-- ─── 2) تريجر تلقائي لاحتساب الوقت الإضافي (Overtime) في attendance_daily ─────
create or replace function public.trg_fn_calculate_daily_overtime()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_req_mins integer := 480; -- افتراضي 8 ساعات = 480 دقيقة
  v_shift_mins integer;
begin
  if new.first_check_in is not null and new.last_check_out is not null then
    -- استخراج مدة الوردية المقررة إن وجدت
    if new.shift_id is not null then
      select round(extract(epoch from (s.end_time - s.start_time)) / 60)::integer
        into v_shift_mins
        from public.shifts s
       where s.id = new.shift_id;
      if v_shift_mins is not null and v_shift_mins > 0 then
        v_req_mins := v_shift_mins;
      end if;
    end if;

    -- حساب دقائق العمل الفعلية
    if new.work_minutes is null or new.work_minutes = 0 then
      new.work_minutes := floor(extract(epoch from (date_trunc('minute', new.last_check_out) - date_trunc('minute', new.first_check_in))) / 60)::integer;
    end if;

    -- احتساب دقائق الوقت الإضافي
    if new.work_minutes > v_req_mins then
      new.overtime_minutes := new.work_minutes - v_req_mins;
    else
      new.overtime_minutes := 0;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_calculate_daily_overtime on public.attendance_daily;
create trigger trg_calculate_daily_overtime
  before insert or update of first_check_in, last_check_out, work_minutes
  on public.attendance_daily
  for each row
  execute function public.trg_fn_calculate_daily_overtime();

-- ─── 3) RPC استعلام صندوق الوقت الإضافي لليوم (Daily Overtime Summary) ──────────
create or replace function public.get_daily_overtime_summary(
  p_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_total_ot_mins integer := 0;
  v_emp_count integer := 0;
  v_emp_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'غير مسموح: يجب تسجيل الدخول' using errcode = '42501';
  end if;

  with calculated as (
    select
      ad.id as attendance_id,
      e.id as employee_id,
      e.full_name_ar as employee_name,
      e.employee_code,
      d.name as department_name,
      ad.first_check_in,
      ad.last_check_out,
      (ad.last_check_out is null and ad.first_check_in is not null and v_date = (now() at time zone 'Africa/Cairo')::date) as is_still_working,
      greatest(
        coalesce(ad.work_minutes, 0),
        floor(extract(epoch from (coalesce(ad.last_check_out, now()) - ad.first_check_in)) / 60)::integer
      ) as actual_work_minutes,
      coalesce(
        (select round(extract(epoch from (s.end_time - s.start_time)) / 60)::integer from public.shifts s where s.id = ad.shift_id),
        480
      ) as required_minutes
    from public.attendance_daily ad
    join public.employees e on e.id = ad.employee_id
    left join public.departments d on d.id = e.department_id
    where ad.work_date = v_date
      and ad.first_check_in is not null
      and e.is_deleted = false
  ),
  with_ot as (
    select
      c.*,
      greatest(0, c.actual_work_minutes - c.required_minutes) as ot_minutes
    from calculated c
    where c.actual_work_minutes > c.required_minutes
  )
  select
    coalesce(sum(ot_minutes), 0),
    count(*),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'employeeId', employee_id,
        'employeeName', employee_name,
        'employeeCode', employee_code,
        'departmentName', department_name,
        'firstCheckIn', first_check_in,
        'lastCheckOut', last_check_out,
        'isStillWorking', is_still_working,
        'workMinutes', actual_work_minutes,
        'requiredMinutes', required_minutes,
        'overtimeMinutes', ot_minutes,
        'overtimeHours', round(ot_minutes::numeric / 60.0, 1),
        'overtimeFormatted', (ot_minutes / 60) || ' ساعة و ' || (ot_minutes % 60) || ' دقيقة'
      )
      order by ot_minutes desc
    ), '[]'::jsonb)
  into v_total_ot_mins, v_emp_count, v_emp_rows
  from with_ot;

  return jsonb_build_object(
    'date', v_date,
    'totalOvertimeMinutes', v_total_ot_mins,
    'totalOvertimeHours', round(v_total_ot_mins::numeric / 60.0, 1),
    'totalOvertimeFormatted', (v_total_ot_mins / 60) || ' ساعة و ' || (v_total_ot_mins % 60) || ' دقيقة إضافية',
    'employeesCount', v_emp_count,
    'employees', v_emp_rows
  );
end;
$$;

-- ─── 4) تحديث get_instant_penalties لإضافة حالة الترقب لبصمة الانصراف ─────────
create or replace function public.get_instant_penalties(
  p_employee_id uuid default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_is_admin_or_hr boolean;
  v_me uuid;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسموح: يجب تسجيل الدخول' using errcode = '42501';
  end if;

  v_is_admin_or_hr := public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage', 'attendance.day.override'])
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director']);
  v_me := public.current_employee_id();

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',                     t.id,
        'employeeId',             t.employee_id,
        'employeeName',           t.employee_name,
        'employeeCode',           t.employee_code,
        'departmentName',         t.department_name,
        'workDate',               t.work_date,
        'lateMinutes',            t.late_minutes,
        'originalAmount',         t.original_amount,
        'currentAmount',          t.current_amount,
        'currency',               t.currency,
        'status',                 t.status,
        'escalationLevel',        t.escalation_level,
        'paidAt',                 t.paid_at,
        'confirmedBy',            t.confirmed_by,
        'suspendedAt',            t.suspended_at,
        'suspensionLiftedAt',     t.suspension_lifted_at,
        'notes',                  t.notes,
        'createdAt',              t.created_at,
        'excuseStatus',           t.excuse_status,
        'excuseText',             case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_text end,
        'excuseAttachmentUrl',    case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_attachment_url end,
        'excuseSubmittedAt',      t.excuse_submitted_at,
        'excuseReviewedAt',       t.excuse_reviewed_at,
        'excuseNotes',            case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_notes end,
        'paymentMethod',          t.payment_method,
        'receiptAttachmentUrl',   case when (v_is_admin_or_hr or t.employee_id = v_me) then t.receipt_attachment_url end,
        'receiptSubmittedAt',     t.receipt_submitted_at,
        'receiptReferenceNumber', t.receipt_reference_number,
        'cancelledReason',        t.cancelled_reason,
        'awaitingCheckoutConfirmation', t.awaiting_checkout_confirmation,
        'elapsedMinutesToday',    t.elapsed_minutes_today
      )
      order by t.work_date desc, t.created_at desc
    )
    from (
      select
        p.id,
        p.employee_id,
        e.full_name_ar                        as employee_name,
        e.employee_code,
        d.name                                as department_name,
        p.work_date,
        p.late_minutes,
        p.original_amount,
        p.current_amount,
        p.currency,
        p.status,
        p.escalation_level,
        p.paid_at,
        p.confirmed_by,
        p.suspended_at,
        p.suspension_lifted_at,
        p.notes,
        p.created_at,
        coalesce(p.excuse_status, 'none')     as excuse_status,
        p.excuse_text,
        p.excuse_attachment_url,
        p.excuse_submitted_at,
        p.excuse_reviewed_at,
        p.excuse_notes,
        coalesce(p.payment_method, 'cash')    as payment_method,
        p.receipt_attachment_url,
        p.receipt_submitted_at,
        p.receipt_reference_number,
        p.cancelled_reason,
        (
          p.status in ('pending_payment', 'doubled')
          and ad.first_check_in is not null
          and ad.last_check_out is null
          and p.work_date = v_today
          and floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', ad.first_check_in))) / 60) >= 480
        ) as awaiting_checkout_confirmation,
        case
          when ad.first_check_in is not null and ad.last_check_out is null and p.work_date = v_today then
            floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', ad.first_check_in))) / 60)::integer
          else coalesce(ad.work_minutes, 0)
        end as elapsed_minutes_today
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      left join public.attendance_daily ad on ad.employee_id = p.employee_id and ad.work_date = p.work_date
      where (p_employee_id is null or p.employee_id = p_employee_id)
        and (p_status is null or p.status = p_status)
        and (p_date_from is null or p.work_date >= p_date_from)
        and (p_date_to is null or p.work_date <= p_date_to)
      order by p.work_date desc, p.created_at desc
      limit case when p_limit is null then null else greatest(1, p_limit) end
      offset greatest(0, coalesce(p_offset, 0))
    ) t
  ), '[]'::jsonb);
end;
$$;

commit;
