-- =======================================================================
-- 0513: Instant Attendance Penalties Enhancements & Cancellation RPC
-- =======================================================================

-- 1) السماح بحالة 'cancelled' في جدول الغرامات الفورية
alter table public.instant_attendance_penalties
  drop constraint if exists instant_attendance_penalties_status_check;

alter table public.instant_attendance_penalties
  add constraint instant_attendance_penalties_status_check
  check (status in ('pending_payment','paid','doubled','suspended','cancelled'));

-- 2) تحديث دالة رفع التعليق اليدوي لتعيد الغرامة إلى pending_payment
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
  v_emp_name text;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  if not (public.current_is_full_access()
          or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الرواتب' using errcode = '42501';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status <> 'suspended' then
    raise exception 'الغرامة ليست في حالة تعليق' using errcode = '22023';
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

  -- إعادة تفعيل الحساب
  update public.employees
     set status = 'active',
         is_active = true,
         updated_at = now()
   where id = v_row.employee_id;

  update public.profiles
     set status = 'active',
         updated_at = now()
   where employee_id = v_row.employee_id;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  perform public.log_audit_event(
    'instant_penalty.suspension_lifted', 'financial', 'warning',
    'instant_attendance_penalties', v_row.id,
    'رفع تعليق الموظف يدوياً: ' || coalesce(v_emp_name, 'موظف') || ' دون تأكيد سداد كامل',
    null,
    jsonb_build_object('employeeId', v_row.employee_id, 'notes', p_notes)
  );

  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '⚠️ رفع تعليق الحساب (استثناء يدوي)',
    'تم رفع تعليق ' || coalesce(v_emp_name, 'الموظف') || ' وإعادة تفعيل حسابه استثنائياً. الغرامة لا تزال مستحقة للسداد.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'channel', 'instant_penalty_suspension_lifted',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'suspensionLiftedAt', v_row.suspension_lifted_at
  );
end;
$$;

-- 3) دالة إلغاء الغرامة بواسطة HR
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
  v_emp_name text;
  v_was_suspended boolean;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  if not (public.current_is_full_access()
          or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الرواتب' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'يجب ذكر سبب الإلغاء' using errcode = '22023';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status = 'paid' then
    raise exception 'لا يمكن إلغاء غرامة مدفوعة بالفعل' using errcode = '22023';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'الغرامة ملغاة بالفعل' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  update public.instant_attendance_penalties
     set status = 'cancelled',
         notes = 'إلغاء: ' || p_reason,
         suspension_lifted_at = case when v_was_suspended then now() else suspension_lifted_at end,
         suspension_lifted_by = case when v_was_suspended then v_me else suspension_lifted_by end,
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  -- إعادة تفعيل الحساب إذا كان معلّقاً
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

  perform public.log_audit_event(
    'instant_penalty.cancelled', 'financial', 'warning',
    'instant_attendance_penalties', v_row.id,
    'إلغاء غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — ' || v_row.current_amount || ' ج.م — السبب: ' || p_reason,
    null,
    jsonb_build_object(
      'employeeId', v_row.employee_id,
      'amount', v_row.current_amount,
      'reason', p_reason,
      'wasSuspended', v_was_suspended
    )
  );

  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '❌ تم إلغاء غرامة التأخير',
    coalesce(v_emp_name, 'الموظف') || ' — تم إلغاء غرامة التأخير بقيمة ' || v_row.current_amount || ' ج.م. السبب: ' || p_reason ||
      case when v_was_suspended then ' — تم فتح السيستم ورفع التعليق.' else '.' end,
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'reason', p_reason,
      'wasSuspended', v_was_suspended,
      'channel', 'instant_penalty_cancelled',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended
  );
end;
$$;

revoke all on function public.lift_instant_penalty_suspension(uuid, text) from public, anon;
grant execute on function public.lift_instant_penalty_suspension(uuid, text) to authenticated;

revoke all on function public.cancel_instant_penalty(uuid, text) from public, anon;
grant execute on function public.cancel_instant_penalty(uuid, text) to authenticated;
