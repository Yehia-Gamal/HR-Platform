-- Migration 0714: Fix notification category check constraint and revert_doubled_instant_penalty
-- Resolves "violates check constraint notifications_category_check" when reverting doubled penalties.

-- 1) Update notifications_category_check to allow 'financial' category
alter table public.notifications drop constraint if exists notifications_category_check;
alter table public.notifications add constraint notifications_category_check check (
  category in (
    'general', 'decision', 'announcement', 'survey', 'request', 'dispute',
    'recognition', 'system', 'kpi', 'device', 'attendance', 'location',
    'security', 'privacy', 'documents', 'service', 'wellbeing', 'offboarding',
    'access', 'workflow', 'integration', 'data', 'daily_report',
    'daily_report_like', 'daily_report_comment', 'attendance_manager_notify',
    'financial'
  )
);

-- 2) Update revert_doubled_instant_penalty to use 'attendance' category
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
  v_has_other_suspended boolean := false;
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
         suspension_lifted_at = case when status = 'suspended' then now() else suspension_lifted_at end,
         suspension_lifted_by = case when status = 'suspended' then v_me else suspension_lifted_by end,
         notes = coalesce(notes || ' | ', '') || 'إرجاع إداري لأصل الغرامة (' || original_amount || ' ج.م) بدلاً من ' || v_old_amount || ' ج.م' || case when p_reason is not null and btrim(p_reason) <> '' then ': ' || btrim(p_reason) else '' end,
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- 2) إذا كان الموظف موقوفاً، تحقق هل توجد غرامات أخرى معلقة بحالة suspended
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and status = 'suspended'
  ) into v_has_other_suspended;

  if not v_has_other_suspended then
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
    'instant_penalty.reverted_to_original', 'financial', 'info',
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
    'isEmployeeSuspended', v_has_other_suspended
  );
end;
$$;

revoke all on function public.revert_doubled_instant_penalty(uuid, text) from public, anon;
grant execute on function public.revert_doubled_instant_penalty(uuid, text) to authenticated, service_role;

