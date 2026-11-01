-- Migration 0717: Fix lift suspension and doubled penalty revert logic
-- Ensures that administratively lifting an employee's suspension:
-- 1) Reactivates employee and profile records.
-- 2) Reverts all doubled/suspended/500 EGP penalties back to original amounts (20/50/150 EGP).
-- 3) Automatically removes the employee from the Suspended Employees list.
-- 4) Fixes revert_doubled_instant_penalty and confirm_instant_penalty_payment so lifting suspension
--    checks across all escalated penalties (not just status = 'suspended').

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة رفع الإيقاف إدارياً وتفعيل الحساب
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.lift_employee_suspension_admin(
  p_employee_id uuid,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me         uuid := public.current_employee_id();
  v_emp_name   text;
  v_lifted_count int := 0;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'super-admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin', 'operations-manager-1', 'operations-manager-2')
       )
     ) then
    raise exception 'غير مسموح: يتطلب صلاحية إدارة النظام أو الموارد البشرية' using errcode = '42501';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  select full_name_ar into v_emp_name
    from public.employees where id = p_employee_id;

  if not found then
    raise exception 'الموظف غير موجود' using errcode = 'P0002';
  end if;

  -- 1) إعادة تفعيل الموظف والحساب فوراً
  update public.employees
     set status = 'active',
         is_active = true,
         updated_at = now()
   where id = p_employee_id;

  update public.profiles
     set status = 'active',
         updated_at = now()
   where employee_id = p_employee_id;

  -- 2) إرجاع أي غرامات موقوفة أو مضاعفة (500 ج.م) للموظف إلى قيمتها الأصلية وبانتظار السداد
  -- يشمل كل الغرامات غير المسددة التي تضاعفت أو تم تعليقها بغض النظر عن الحقل status أو escalation_level
  with updated_penalties as (
    update public.instant_attendance_penalties
       set status = 'pending_payment',
           escalation_level = 'initial',
           current_amount = original_amount,
           suspension_lifted_at = now(),
           suspension_lifted_by = v_me,
           notes = coalesce(notes || ' | ', '') || 'رفع الإيقاف إدارياً وإرجاع الغرامة للأصل (' || original_amount || ' ج.م)' || case when p_reason is not null and btrim(p_reason) <> '' then ': ' || btrim(p_reason) else '' end,
           updated_at = now()
     where employee_id = p_employee_id
       and (
         status in ('suspended', 'doubled')
         or escalation_level in ('doubled', 'suspended')
         or current_amount > original_amount
       )
       and status not in ('paid', 'cancelled')
    returning id
  )
  select count(*) into v_lifted_count from updated_penalties;

  -- 3) سجل التدقيق
  perform public.log_audit_event(
    'employee.suspension_lifted', 'general', 'info',
    'employees', p_employee_id,
    'رفع الإيقاف عن العمل إدارياً للموظف: ' || coalesce(v_emp_name, 'موظف') || ' — وإرجاع ' || v_lifted_count || ' غرامة لقيمتها الأصلية',
    p_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'penaltiesResetCount', v_lifted_count
    )
  );

  -- 4) إشعار الموظف
  perform public.notify_employee(
    p_employee_id,
    'تم رفع الإيقاف عن العمل',
    'تم رفع الإيقاف وإعادة فتح حسابك على المنظومة بنجاح، وإرجاع الغرامات إلى قيمتها الأصلية بانتظار السداد. يمكنك الآن الدخول ومباشرة مهامك.',
    'system', 'high', 'employees', p_employee_id,
    jsonb_build_object('employeeId', p_employee_id, 'penaltiesResetCount', v_lifted_count)
  );

  return jsonb_build_object(
    'success', true,
    'employeeId', p_employee_id,
    'status', 'active',
    'penaltiesResetCount', v_lifted_count
  );
end;
$$;

revoke all on function public.lift_employee_suspension_admin(uuid, text) from public, anon;
grant execute on function public.lift_employee_suspension_admin(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) دالة إرجاع الغرامة المفردة للأصل مع فحص شامل لرفع التعليق
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.revert_doubled_instant_penalty(
  p_penalty_id uuid,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me         uuid := public.current_employee_id();
  v_row        public.instant_attendance_penalties;
  v_emp_name   text;
  v_has_other_doubled boolean := false;
  v_old_amount numeric(12,2);
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'super-admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin', 'operations-manager-1', 'operations-manager-2')
       )
     ) then
    raise exception 'غير مسموح: يتطلب صلاحية إدارة النظام أو الموارد البشرية' using errcode = '42501';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status in ('paid', 'cancelled') then
    raise exception 'لا يمكن تعديل غرامة مسددة أو ملغاة' using errcode = '22023';
  end if;

  v_old_amount := v_row.current_amount;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  -- 1) إعادة الغرامة إلى أصلها وإلغاء التصعيد
  update public.instant_attendance_penalties
     set current_amount = original_amount,
         status = 'pending_payment',
         escalation_level = 'initial',
         suspension_lifted_at = case when status = 'suspended' or escalation_level in ('doubled', 'suspended') then now() else suspension_lifted_at end,
         suspension_lifted_by = case when status = 'suspended' or escalation_level in ('doubled', 'suspended') then v_me else suspension_lifted_by end,
         notes = coalesce(notes || ' | ', '') || 'إرجاع إداري لأصل الغرامة (' || original_amount || ' ج.م) بدلاً من ' || v_old_amount || ' ج.م' || case when p_reason is not null and btrim(p_reason) <> '' then ': ' || btrim(p_reason) else '' end,
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- 2) فحص هل توجد غرامات أخرى معلقة أو مضاعفة للموظف
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and (
         status in ('suspended', 'doubled')
         or escalation_level in ('doubled', 'suspended')
         or current_amount > original_amount
       )
       and status not in ('paid', 'cancelled')
  ) into v_has_other_doubled;

  -- إذا لم يعد لدى الموظف أي غرامة مضاعفة أو موقوفة، يتم تفعيل حسابه فوراً
  if not v_has_other_doubled then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id
       and status = 'suspended';

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id
       and status = 'suspended';
  end if;

  -- 3) تسجيل في سجل التدقيق
  perform public.log_audit_event(
    'instant_penalty.reverted_to_original', 'general', 'info',
    'instant_attendance_penalties', p_penalty_id,
    'إرجاع غرامة فورية لأصلها: ' || coalesce(v_emp_name, 'موظف') || ' — ' || v_row.original_amount || ' ج.م (بدلاً من ' || v_old_amount || ' ج.م)',
    p_reason,
    jsonb_build_object(
      'employeeId', v_row.employee_id,
      'originalAmount', v_row.original_amount,
      'previousAmount', v_old_amount,
      'penaltyId', p_penalty_id
    )
  );

  -- 4) إشعار الموظف
  perform public.notify_employee(
    v_row.employee_id,
    'إعادة قيمة الغرامة للأصل',
    'تم إرجاع غرامة التأخير ليوم ' || v_row.work_date || ' إلى قيمتها الأصلية (' || v_row.original_amount || ' ج.م) بقرار إداري. يمكنك الآن السداد لدى الـ HR دون مضاعفة.',
    'attendance', 'normal', 'instant_attendance_penalties', p_penalty_id,
    jsonb_build_object('penaltyId', p_penalty_id, 'amount', v_row.original_amount)
  );

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'newAmount', v_row.current_amount,
    'originalAmount', v_row.original_amount,
    'status', v_row.status,
    'isEmployeeSuspended', v_has_other_doubled
  );
end;
$$;

revoke all on function public.revert_doubled_instant_penalty(uuid, text) from public, anon;
grant execute on function public.revert_doubled_instant_penalty(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) دالة سداد الغرامة مع فحص شامل للغرامات المضاعفة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.confirm_instant_penalty_payment(
  p_penalty_id uuid,
  p_notes      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_my_name text;
  v_current_balance numeric(12,2) := 0;
  v_new_balance numeric(12,2) := 0;
  v_was_suspended boolean := false;
  v_has_other_doubled boolean := false;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin')
       )
     ) then
    raise exception 'غير مسموح' using errcode = '42501';
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
    raise exception 'الغرامة مدفوعة بالفعل ومودعة في صندوق الزمالة' using errcode = '22023';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'الغرامة ملغاة ولا يمكن تحصيلها' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended' or v_row.current_amount >= 500);

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

  -- 2) رفع التعليق فوراً إن لم توجد غرامات معلقة أو مضاعفة أخرى للموظف
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and (
         status in ('suspended', 'doubled')
         or escalation_level in ('doubled', 'suspended')
         or current_amount > original_amount
       )
       and status not in ('paid', 'cancelled')
  ) into v_has_other_doubled;

  if not v_has_other_doubled then
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

  -- 3) توريد المبلغ لصندوق الزمالة والتكافل
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0)
    into v_current_balance
    from public.fellowship_fund_transactions;

  v_new_balance := v_current_balance + v_row.current_amount;

  insert into public.fellowship_fund_transactions(
    employee_id, employee_name, amount, transaction_type, source_type,
    instant_penalty_id, performed_by, performer_name, balance_after, reason, notes
  ) values (
    v_row.employee_id,
    v_emp_name,
    v_row.current_amount,
    'inflow',
    'instant_penalty',
    v_row.id,
    v_me,
    v_my_name,
    v_new_balance,
    'سداد غرامة فورية عن يوم ' || v_row.work_date,
    'سداد غرامة فورية ليوم ' || v_row.work_date || ' (تأخير ' || v_row.late_minutes || ' دقيقة) — المحصّل: ' || coalesce(v_my_name, 'HR')
  );

  -- 4) سجل التدقيق
  perform public.log_audit_event(
    'instant_penalty.paid', 'general', 'info',
    'instant_attendance_penalties', v_row.id,
    'سداد غرامة فورية: ' || v_emp_name || ' — ' || v_row.current_amount || ' ج.م تم توريدها لصندوق الزمالة' || case when v_was_suspended and not v_has_other_doubled then ' (تم رفع التعليق وإعادة فتح الحساب)' else '' end,
    null,
    jsonb_build_object(
      'penaltyId', v_row.id,
      'employeeId', v_row.employee_id,
      'amount', v_row.current_amount,
      'confirmedBy', v_me,
      'fellowshipNewBalance', v_new_balance,
      'wasSuspended', v_was_suspended,
      'suspensionLifted', not v_has_other_doubled
    )
  );

  -- 5) إشعار الموظف
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم سداد الغرامة الفورية بنجاح',
    'تم تأكيد سداد غرامة التأخير بقيمة ' || v_row.current_amount || ' ج.م وإيداعها في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_doubled then '. تم رفع الإيقاف وإعادة فتح حسابك بنجاح ومباشرة العمل.' else '.' end,
    'instant_penalty_paid',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'channel', 'instant_penalty_paid',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', 'paid',
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended,
    'suspensionLifted', not v_has_other_doubled,
    'fellowshipBalance', v_new_balance,
    'message', 'تم تأكيد السداد وإيداع ' || v_row.current_amount || ' ج.م في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_doubled then ' وتمت إعادة تفعيل حساب الموظف.' else '.' end
  );
end;
$$;

revoke all on function public.confirm_instant_penalty_payment(uuid, text) from public, anon;
grant execute on function public.confirm_instant_penalty_payment(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة get_suspended_employees_admin لضمان دقة القائمة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_suspended_employees_admin()
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
declare
  v_res jsonb;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'super-admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin', 'operations-manager-1', 'operations-manager-2')
       )
     ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'employeeId',       emp.id,
        'employeeName',     emp.full_name_ar,
        'employeeCode',     emp.employee_code,
        'departmentName',   d.name,
        'jobTitle',         jt.name,
        'photoUrl',         emp.photo_url,
        'phone',            emp.phone_e164,
        'status',           emp.status,
        'isActive',         emp.is_active,
        'totalCurrentDue',  coalesce(pen.total_current, 0),
        'totalOriginalDue', coalesce(pen.total_original, 0),
        'has500Penalty',    coalesce(pen.has_doubled, false),
        'unpaidCount',      coalesce(pen.unpaid_count, 0),
        'penalties',        coalesce(pen.penalties_list, '[]'::jsonb)
      )
      order by coalesce(pen.total_current, 0) desc, emp.full_name_ar asc
    ),
    '[]'::jsonb
  ) into v_res
  from public.employees emp
  left join public.departments d on d.id = emp.department_id
  left join public.job_titles jt on jt.id = emp.job_title_id
  left join lateral (
    select
      sum(p.current_amount) as total_current,
      sum(p.original_amount) as total_original,
      bool_or(p.current_amount >= 500 or p.status in ('doubled', 'suspended') or p.escalation_level in ('doubled', 'suspended')) as has_doubled,
      count(p.id) as unpaid_count,
      jsonb_agg(
        jsonb_build_object(
          'id',             p.id,
          'workDate',       p.work_date,
          'lateMinutes',    p.late_minutes,
          'originalAmount', p.original_amount,
          'currentAmount',  p.current_amount,
          'status',         p.status,
          'escalationLevel',p.escalation_level,
          'notes',          p.notes,
          'suspendedAt',    p.suspended_at
        ) order by p.work_date desc
      ) as penalties_list
    from public.instant_attendance_penalties p
    where p.employee_id = emp.id
      and p.status in ('pending_payment', 'doubled', 'suspended')
  ) pen on true
  where coalesce(emp.is_deleted, false) = false
    and (
      emp.status = 'suspended'
      or emp.is_active = false
      or pen.has_doubled = true
      or exists (
        select 1 from public.instant_attendance_penalties p2
        where p2.employee_id = emp.id and p2.status = 'suspended'
      )
    );

  return v_res;
end;
$$;

revoke all on function public.get_suspended_employees_admin() from public, anon;
grant execute on function public.get_suspended_employees_admin() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تطبيق فوري على غرامة مصطفى محمد فايد ليوم 2026-10-31
--    لرفع الإيقاف عنه وإرجاع غرامته إلى أصلها (150 ج.م) بانتظار السداد
-- ─────────────────────────────────────────────────────────────────────

select public.lift_employee_suspension_admin(
  '6ad20b22-51d7-4ddc-a127-62a54a45c8e6',
  'تطبيق فوري لقرار رفع الإيقاف الإداري وإرجاع الغرامة للأصل'
);

commit;
