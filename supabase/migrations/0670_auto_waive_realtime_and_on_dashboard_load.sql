-- Migration 0670: تفعيل الإلغاء الفوري التلقائي للغرامة بمجرد مرور 8 ساعات وتحديث لوحة التحكم
-- ==============================================================================
-- قاعدة العمل:
-- إذا تأخر الموظف وسُجلت عليه غرامة، وبقي في العمل حتى استوفى 8 ساعات عمل (سواء سجل انصراف
-- أو ما زال في العمل والوقت الفعلي تجاوز 8 ساعات من وقت دخوله، مثل يحيى من 10:23 ص حتى 6:23 م):
-- 1. يتم إلغاء الخصم تلقائياً وبشكل فوري دون اشتراط انتظار ضغط زر الانصراف.
-- 2. عند فتح لوحة التحكم get_instant_penalties يتم عمل مسح فوري وتحديث حالة أي موظف استوفى 8 ساعات.
-- 3. إرسال الإشعار للموظف والمدير والإدارة فوراً مع بيان وقت الحضور والوقت المنقضي.
-- ==============================================================================

begin;

-- ─── 1) تحديث دالة إلغاء الغرامة التلقائية لتدعم الوقت الفعلي الحي (Live Elapsed Time) ───
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
  v_out_time timestamptz;
  v_hours integer;
  v_mins integer;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
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

  -- 2. حساب إجمالي دقائق العمل الفعلية:
  -- إذا انصرف الموظف نستخدم last_check_out
  -- وإذا لم ينصرف بعد وما زال متواجداً بالعمل واليوم هو اليوم الحالي: نستخدم الوقت اللحظي now()
  if v_att.last_check_out is not null then
    v_out_time := v_att.last_check_out;
    v_work_minutes := greatest(
      coalesce(v_att.work_minutes, 0),
      floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
    );
  elsif p_work_date = v_today then
    v_out_time := now();
    v_work_minutes := floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', v_att.first_check_in))) / 60)::integer;
  else
    v_out_time := null;
    v_work_minutes := coalesce(v_att.work_minutes, 0);
  end if;

  -- 3. فحص الغرامة الفورية المسجلة لذلك اليوم (إن وُجدت)
  select p.id, p.current_amount, p.original_amount, p.status, p.escalation_level, p.notes
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if not found then
    return jsonb_build_object(
      'waived', false,
      'workMinutes', v_work_minutes,
      'reason', 'no_active_penalty'
    );
  end if;

  -- إذا لم يكتمل وقت العمل (أقل من 8 ساعات = 480 دقيقة)
  if v_work_minutes < 480 then
    return jsonb_build_object(
      'waived', false,
      'penaltyRemaining', true,
      'penaltyId', v_pen.id,
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'remainingMinutes', (480 - v_work_minutes),
      'message', 'الغرامة مستحقة لعدم إتمام 8 ساعات عمل حتى الآن'
    );
  end if;

  -- 4. الموظف أتمّ 8 ساعات عمل كاملة (480 دقيقة أو أكثر) → إلغاء الغرامة فوراً
  select e.full_name_ar into v_emp_name
    from public.employees e
   where e.id = p_employee_id;

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
              
  v_out_str := to_char(coalesce(v_out_time, now()) at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (coalesce(v_out_time, now()) at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
               
  v_hours := v_work_minutes / 60;
  v_mins := v_work_minutes % 60;

  -- تحديث حالة الغرامة إلى ملغاة مع توثيق الساعات والدقائق
  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء تلقائي: استيفاء 8 ساعات عمل كاملة (تعويض التأخير)',
         notes = coalesce(notes || ' | ', '') ||
                 'تم إلغاء الخصم لاستيفاء وقت العمل المقرر (8 ساعات كاملة) — الدخول: ' ||
                 v_in_str || case when v_att.last_check_out is not null then '، الخروج: ' else '، استيفاء العمل حتى: ' end || v_out_str ||
                 ' (إجمالي العمل: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة)',
         updated_at = now()
   where id = v_pen.id;

  -- رفع التعليق إن كان موقوفاً بسبب هذه الغرامة ولا توجد غرامة أخرى مضاعفة
  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = p_employee_id
       and status in ('doubled', 'suspended')
       and id <> v_pen.id
  ) then
    update public.employees set is_active = true, status = 'active' where id = p_employee_id;
    update public.profiles set status = 'active' where employee_id = p_employee_id;
  end if;

  -- 5. إرسال الإشعارات الشفافة في التطبيق
  -- أ) إشعار الموظف نفسه بالاسم الصريح ومواعيد الحضور والانصراف
  perform public.notify_employee(
    p_employee_id,
    '🎉 إلغاء غرامة التأخير — استيفاء 8 ساعات عمل',
    'تم إلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لبقائك في العمل واستيفائك وقت العمل المقرر كاملاً (8 ساعات). وقت الحضور: ' || v_in_str || ' — ' || case when v_att.last_check_out is not null then 'وقت الانصراف: ' else 'الوقت المستوفى: ' end || v_out_str || ' (إجمالي العمل: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة). شكراً لالتزامك وتعويضك لوقت التأخير!',
    'system',
    'high',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'waived', true,
      'reason', 'eight_hours_completed',
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  -- ب) إشعار المدير المباشر باسم الموظف الصريح
  select m.id into v_mgr_id
    from public.employees e
    join public.departments d on d.id = e.department_id
    join public.employees m on m.id = d.manager_id
   where e.id = p_employee_id;

  if v_mgr_id is not null and v_mgr_id <> p_employee_id then
    perform public.notify_employee(
      v_mgr_id,
      'إلغاء غرامة تأخير لموظف بالقسم — استيفاء 8 ساعات',
      'تم تلقائياً إلغاء غرامة التأخير المقدرة بـ ' || v_pen.current_amount || ' ج.م عن الموظف (' || coalesce(v_emp_name, '') || ') بعد استيفائه 8 ساعات عمل كاملة اليوم (' || v_in_str || ' إلى ' || v_out_str || ').',
      'team',
      'normal',
      'instant_penalty',
      v_pen.id,
      jsonb_build_object(
        'penaltyId', v_pen.id,
        'employeeId', p_employee_id,
        'employeeName', v_emp_name,
        'waived', true
      )
    );
  end if;

  -- ج) إشعار إدارة الموارد البشرية والمالية
  perform public.notify_employees_with_permission(
    'payroll.run.manage',
    'إلغاء غرامة تأخير تلقائياً (استيفاء 8 ساعات)',
    'قام النظام بإلغاء غرامة التأخير تلقائياً للموظف ' || coalesce(v_emp_name, '') || ' بقيمة ' || v_pen.current_amount || ' ج.م لاستيفائه 8 ساعات عمل كاملة (الدخول: ' || v_in_str || '، الوقت: ' || v_out_str || ').',
    'system',
    'normal',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'employeeName', v_emp_name,
      'workMinutes', v_work_minutes
    ),
    p_employee_id
  );

  -- د) تسجيل حدث تدقيق أمني رسمي
  perform public.log_audit_event(
    'instant_penalty.waived_eight_hours',
    'instant_attendance_penalties',
    v_pen.id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'employee_name', v_emp_name,
      'work_date', p_work_date,
      'original_amount', v_pen.original_amount,
      'work_minutes', v_work_minutes,
      'first_check_in', v_att.first_check_in,
      'last_check_out', v_out_time,
      'waived_at', now()
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

-- ─── 2) دالة المسح الشامل لجميع الموظفين المستوفين لـ 8 ساعات اليوم ──────────
create or replace function public.auto_waive_all_completed_eight_hours_today()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  r record;
  v_count integer := 0;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  for r in
    select distinct ad.employee_id, ad.work_date
    from public.attendance_daily ad
    join public.instant_attendance_penalties p on p.employee_id = ad.employee_id and p.work_date = ad.work_date
    where ad.work_date = v_today
      and ad.first_check_in is not null
      and p.status in ('pending_payment', 'doubled', 'suspended')
      and (
        (ad.last_check_out is not null and greatest(coalesce(ad.work_minutes, 0), floor(extract(epoch from (date_trunc('minute', ad.last_check_out) - date_trunc('minute', ad.first_check_in))) / 60)) >= 480)
        or
        (ad.last_check_out is null and floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', ad.first_check_in))) / 60) >= 480)
      )
  loop
    perform public.auto_waive_penalty_if_completed_eight_hours(r.employee_id, r.work_date);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ─── 3) دمج المسح التلقائي داخل RPC استعلام الغرامات get_instant_penalties ─────
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
begin
  if auth.uid() is null then
    raise exception 'غير مسموح: يجب تسجيل الدخول' using errcode = '42501';
  end if;

  -- تنفيذ فحص ومسح تلقائي لإلغاء غرامات أي موظفين استوفوا 8 ساعات اليوم
  perform public.auto_waive_all_completed_eight_hours_today();

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
        'cancelledReason',        t.cancelled_reason
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
        p.cancelled_reason
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
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

-- ─── 4) تشغيل المسح فوراً على البيانات الحالية لتطبيق الإعفاء في هذه اللحظة ───
select public.auto_waive_all_completed_eight_hours_today();

commit;
