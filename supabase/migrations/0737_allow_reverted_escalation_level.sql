-- Migration 0737: Allow 'reverted' in instant_attendance_penalties escalation_level constraint
-- and refine revert_doubled_instant_penalty function.

-- 1) تحديث قيد التحقق من مستوى التصعيد ليشمل 'reverted' لمنع خطأ 23514 / القيمة المدخلة غير مقبولة
alter table public.instant_attendance_penalties
  drop constraint if exists instant_attendance_penalties_escalation_level_check;

alter table public.instant_attendance_penalties
  add constraint instant_attendance_penalties_escalation_level_check
  check (escalation_level in ('initial', 'doubled', 'suspended', 'reverted'));

-- 2) تحديث دالة إرجاع الغرامة المضاعفة للأصل مع إشعار الموظف والتحقق الدقيق
create or replace function public.revert_doubled_instant_penalty(
  p_penalty_id uuid,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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

  -- إعادة الغرامة للأصل وتعيين المستوى إلى 'reverted' لمنع الكرون من مضاعفتها تلقائياً مرة أخرى
  update public.instant_attendance_penalties
     set escalation_level = 'reverted',
         current_amount = original_amount,
         status = 'pending_payment',
         notes = coalesce(notes || ' | ', '') || 'رفع الإيقاف إدارياً وإرجاع الغرامة للأصل (' || original_amount || ' ج.م)' || case when p_reason is not null and length(trim(p_reason)) > 0 then ': ' || p_reason else '' end,
         updated_at = now()
   where id = p_penalty_id;

  -- فحص ما إذا كان للموظف غرامات أخرى مضاعفة أو معلقة الإيقاف
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and status not in ('paid', 'cancelled')
       and (status in ('doubled', 'suspended') or escalation_level in ('doubled', 'suspended') or current_amount >= 500)
  ) into v_has_other_doubled;

  -- إذا لم يعد هناك غرامات توقف الحساب، يتم رفع الإيقاف فوراً وتفعيل الموظف
  if not v_has_other_doubled then
    update public.employees
       set is_active = true,
           status = 'active',
           updated_at = now()
     where id = v_row.employee_id
       and status = 'suspended';

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id
       and status = 'suspended';
  end if;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  perform public.log_audit_event(
    'instant_penalty.reverted', 'finance', 'medium',
    'instant_attendance_penalties', p_penalty_id,
    coalesce(v_emp_name, 'موظف') || ' — تم رفع الإيقاف وإرجاع الغرامة للأصل (' || v_row.original_amount || ' ج.م)',
    p_reason,
    jsonb_build_object(
      'penaltyId', p_penalty_id,
      'employeeId', v_row.employee_id,
      'oldAmount', v_old_amount,
      'newAmount', v_row.original_amount,
      'reason', p_reason
    )
  );

  -- إشعار الموظف بإرجاع الغرامة للأصل لإتاحة السداد
  perform public.notify_employee(
    v_row.employee_id,
    'إعادة قيمة الغرامة للأصل',
    'تم إرجاع غرامة التأخير ليوم ' || v_row.work_date || ' إلى قيمتها الأصلية (' || v_row.original_amount || ' ج.م) بقرار إداري. يمكنك الآن السداد لدى قسم الموارد البشرية.',
    'attendance', 'normal', 'instant_attendance_penalties', p_penalty_id,
    jsonb_build_object('penaltyId', p_penalty_id, 'amount', v_row.original_amount)
  );

  return jsonb_build_object(
    'success', true,
    'message', 'تم رفع الإيقاف وإرجاع الغرامة للأصل بنجاح',
    'penaltyId', p_penalty_id,
    'oldAmount', v_old_amount,
    'currentAmount', v_row.original_amount,
    'originalAmount', v_row.original_amount
  );
end;
$$;

revoke all on function public.revert_doubled_instant_penalty(uuid, text) from public, anon;
grant execute on function public.revert_doubled_instant_penalty(uuid, text) to authenticated, service_role;
