-- =====================================================================
-- 0517: إصلاح صلاحيات تأكيد الدفع واستعلام الغرامات المعلقة وتوافق البيانات
-- =====================================================================
-- 1) توسيع صلاحيات confirm_instant_penalty_payment لتشمل جميع أدوار HR والإدارة.
-- 2) معالجة v_me بمرونة لضمان عدم توقف الإجراء في حال عدم ربط المستخدم بملف موظف.
-- 3) إرجاع كائن JSON كامل ومتوافق (id, penaltyId, status, paidAt, currentAmount, amount, ...).
-- 4) إتاحة get_employees_with_pending_instant_penalties لجميع المستخدمين الموثقين للشفافية.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تحديث get_employees_with_pending_instant_penalties
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_employees_with_pending_instant_penalties()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- متاح لجميع المستخدمين الموثقين للشفافية وعرض الشارات في الدليل
  if auth.uid() is null and current_user not in ('postgres', 'service_role') then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(sub.item)
    from (
      select jsonb_build_object(
        'employeeId', p.employee_id,
        'employeeName', e.full_name_ar,
        'employeeCode', e.employee_code,
        'departmentName', d.name,
        'pendingCount', count(*),
        'totalAmount', sum(p.current_amount),
        'isSuspended', bool_or(p.status = 'suspended'),
        'latestDate', max(p.work_date)
      ) as item
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      where p.status in ('pending_payment', 'doubled', 'suspended')
      group by p.employee_id, e.full_name_ar, e.employee_code, d.name
      order by bool_or(p.status = 'suspended') desc, sum(p.current_amount) desc
    ) sub
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.get_employees_with_pending_instant_penalties() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث confirm_instant_penalty_payment
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.confirm_instant_penalty_payment(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_my_name text;
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_was_suspended boolean;
  v_current_balance numeric(12,2) := 0.00;
  v_new_balance numeric(12,2) := 0.00;
  v_tx_id uuid;
begin
  -- التحقق من الصلاحيات بمرونة لجميع مسؤولي الموارد البشرية والإدارة
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'hr-specialist', 'executive', 'executive-secretary', 'executive-director', 'system-admin', 'operations-manager')
       )
       or public.has_any_permission(array[
         'payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage',
         'attendance.record.process', 'attendance.record.review',
         'employees.update', 'employees.read', 'finance.manage', 'finance.read'
       ])
     ) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الموارد البشرية أو الغرامات' using errcode = '42501';
  end if;

  -- العثور على معرّف الموظف المنفّذ بمرونة
  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  if v_me is null then
    select id into v_me from public.employees where is_active = true and is_deleted = false order by created_at limit 1;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status = 'paid' then
    raise exception 'الغرامة مدفوعة بالفعل ومودعة في صندوق الزمالة' using errcode = '22023';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'الغرامة ملغاة ولا يمكن تحصيلها' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  select full_name_ar into v_my_name
    from public.employees where id = v_me;

  -- 1) تحديث حالة الغرامة إلى مدفوعة
  update public.instant_attendance_penalties
     set status = 'paid',
         paid_at = now(),
         confirmed_by = v_me,
         suspension_lifted_at = case when v_was_suspended then now() else suspension_lifted_at end,
         suspension_lifted_by = case when v_was_suspended then v_me else suspension_lifted_by end,
         notes = coalesce(p_notes, notes),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- 2) رفع التعليق فوراً إن كان الموظف معلقاً وإعادة تفعيل حسابه
  if v_was_suspended then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id;
  end if;

  -- 3) حساب الرصيد الحالي وإيداع المبلغ في صندوق الزمالة والتكافل
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0)
    into v_current_balance
    from public.fellowship_fund_transactions;

  v_new_balance := v_current_balance + v_row.current_amount;

  insert into public.fellowship_fund_transactions (
    transaction_type,
    amount,
    source_type,
    instant_penalty_id,
    employee_id,
    employee_name,
    performed_by,
    performer_name,
    category,
    reason,
    balance_after,
    notes
  ) values (
    'inflow',
    v_row.current_amount,
    'instant_penalty',
    v_row.id,
    v_row.employee_id,
    coalesce(v_emp_name, 'موظف'),
    v_me,
    coalesce(v_my_name, 'مسؤول النظام'),
    'غرامة تأخير حضور',
    'غرامة تأخير حضور وانصراف ليوم ' || to_char(v_row.work_date, 'YYYY-MM-DD') || ' (' || v_row.late_minutes || ' دقيقة)',
    v_new_balance,
    p_notes
  ) returning id into v_tx_id;

  -- 4) سجل التدقيق
  perform public.log_audit_event(
    'fellowship_fund.deposit', 'financial', 'info',
    'fellowship_fund_transactions', v_tx_id,
    'تم استلام غرامة تأخير من ' || coalesce(v_emp_name, 'موظف') || ' بقيمة ' || v_row.current_amount || ' ج.م وإيداعها في صندوق الزمالة (الرصيد: ' || v_new_balance || ' ج.م)' ||
      case when v_was_suspended then ' — تم رفع التعليق وفتح السيستم وعودته لمباشرة العمل' else '' end,
    null,
    jsonb_build_object(
      'employeeId', v_row.employee_id,
      'penaltyId', v_row.id,
      'amount', v_row.current_amount,
      'newBalance', v_new_balance,
      'wasSuspended', v_was_suspended
    )
  );

  -- 5) إشعار الموظف نفسه
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم استلام الغرامة وإيداعها بصندوق الزمالة',
    'تم استلام مبلغ ' || v_row.current_amount || ' ج.م من ' || coalesce(v_emp_name, 'الموظف') || ' وإيداعه في صندوق الزمالة والتكافل' ||
      case when v_was_suspended then ' — تم فتح السيستم ورفع التعليق وعودته لمباشرة العمل.' else '.' end,
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'penaltyId', v_row.id::text,
      'amount', v_row.current_amount,
      'fundBalance', v_new_balance,
      'channel', 'fellowship_fund_deposit'
    )
  );

  -- 6) إرسال إشعار فوري لكامل الفريق بالشفافية المطلوبة
  perform public._broadcast_team_notification(
    '💰 إيداع جديد في صندوق الزمالة والتكافل',
    'تم استلام مبلغ ' || v_row.current_amount || ' ج.م من الزميل ' || coalesce(v_emp_name, 'أحد الزملاء') || ' وإيداعه في صندوق الزمالة (غرامة تأخير حضور). رصيد الصندوق الحالي: ' || v_new_balance || ' ج.م.',
    'fellowship_fund',
    v_tx_id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'newBalance', v_new_balance,
      'channel', 'fellowship_fund_deposit',
      'deepLink', 'ahlashabab://action/fellowship-fund'
    )
  );

  -- إرجاع كائن كامل يتضمن id و penaltyId و status و paidAt و currentAmount
  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', v_row.status,
    'paidAt', to_char(v_row.paid_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'amount', v_row.current_amount,
    'currentAmount', v_row.current_amount,
    'employeeId', v_row.employee_id,
    'employeeName', v_emp_name,
    'fundBalanceAfter', v_new_balance,
    'wasSuspended', v_was_suspended,
    'transactionId', v_tx_id,
    'message', 'تم استلام المبلغ بنجاح وإيداعه في صندوق الزمالة والتكافل وإشعار الفريق'
  );
end;
$$;

grant execute on function public.confirm_instant_penalty_payment(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) تحديث lift_instant_penalty_suspension
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.lift_instant_penalty_suspension(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin')
       )
     ) then
    raise exception 'غير مسموح: يحتاج صلاحية إدارة النظام' using errcode = '42501';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  if v_me is null then
    select id into v_me from public.employees where is_active = true and is_deleted = false order by created_at limit 1;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id and status = 'suspended';

  if not found then
    raise exception 'الغرامة غير موجودة أو ليست في حالة تعليق' using errcode = 'P0002';
  end if;

  update public.instant_attendance_penalties
     set status = 'pending_payment',
         escalation_level = 'initial',
         current_amount = original_amount,
         suspension_lifted_at = now(),
         suspension_lifted_by = v_me,
         notes = coalesce(p_notes, notes),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  update public.employees
     set status = 'active',
         is_active = true,
         updated_at = now()
   where id = v_row.employee_id;

  update public.profiles
     set status = 'active',
         updated_at = now()
   where employee_id = v_row.employee_id;

  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', v_row.status,
    'currentAmount', v_row.current_amount,
    'wasSuspended', true,
    'message', 'تم رفع التعليق بنجاح وإعادة تفعيل حساب الموظف'
  );
end;
$$;

grant execute on function public.lift_instant_penalty_suspension(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) تحديث cancel_instant_penalty
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.cancel_instant_penalty(
  p_penalty_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_was_suspended boolean;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin')
       )
     ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'سبب الإلغاء مطلوب (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  if v_me is null then
    select id into v_me from public.employees where is_active = true and is_deleted = false order by created_at limit 1;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status = 'paid' then
    raise exception 'لا يمكن إلغاء غرامة تم دفعها وتوريدها لصندوق الزمالة' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  update public.instant_attendance_penalties
     set status = 'cancelled',
         notes = 'تم الإلغاء بواسطة الإدارة: ' || trim(p_reason) || coalesce(' (' || notes || ')', ''),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  if v_was_suspended then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', 'cancelled',
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended,
    'message', 'تم إلغاء الغرامة بنجاح'
  );
end;
$$;

grant execute on function public.cancel_instant_penalty(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
