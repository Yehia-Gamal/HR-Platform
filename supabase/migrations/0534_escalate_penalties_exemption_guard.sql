-- =====================================================================
-- 0534: حماية التصعيد التلقائي للغرامات من شمول المعفيين أو أصحاب المهام
-- =====================================================================
-- إضافة فحص استباقي للإعفاء (is_employee_exempt_from_instant_penalty)
-- داخل auto_escalate_instant_penalties قبل المضاعفة أو التعليق
-- =====================================================================

begin;

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('payroll.run.manage')) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- ═══ المرحلة 1: مضاعفة الغرامات المتأخرة (pending_payment من أمس فأقدم) ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    -- فحص الإعفاء قبل المضاعفة
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص المضاعفة: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'high',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم يسدد غرامة التأخير في الموعد. تمت مضاعفة الغرامة إلى 500 ج.م. يجب السداد فوراً وإلا سيتم تعليقه عن العمل.',
      'instant_penalty_doubled',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'originalAmount', v_rec.original_amount,
        'newAmount', 500,
        'channel', 'instant_penalty_doubled',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  -- ═══ المرحلة 2: اليوم الثالث — غلق السيستم وإيقاف الموظف عن العمل وإشعار كامل الفريق ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'doubled'
       and p.escalation_level = 'doubled'
       and p.work_date < v_today - 1
  loop
    -- فحص الإعفاء قبل التعليق
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;

      -- رفع أي تعليق إن وجد
      update public.employees set is_active = true where id = v_rec.employee_id;
      continue;
    end if;

    -- 1) تحديث سجل الغرامة
    update public.instant_attendance_penalties
       set status = 'suspended',
           escalation_level = 'suspended',
           suspended_at = now(),
           updated_at = now()
     where id = v_rec.id;

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
    update public.employees
       set status = 'suspended',
           is_active = false,
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'security', 'critical',
      'instant_attendance_penalties', v_rec.id,
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثاني',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', v_rec.current_amount)
    );

    -- 3) إشعار الموظف والمديرين
    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 إيقاف عن العمل وغلق الحساب',
      'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م. يجب التوجه للـ HR وسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', v_rec.current_amount,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    -- 4) إرسال إشعار فوري لكامل الفريق (كل الموظفين النشطين بالشركة)
    perform public.notify_employee(
      e.id,
      '🚫 إشعار إيقاف موظف عن العمل',
      'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
      'system',
      'urgent',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'suspendedEmployeeName', v_emp_name,
        'amount', 500,
        'channel', 'team_suspension_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_rec.employee_id;

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$function$;

comment on function public.auto_escalate_instant_penalties() is
  '0534: تصعيد الغرامات المتأخرة مع فحص مسبق للإعفاءات والمهام الرسمية والإجازات';

commit;
