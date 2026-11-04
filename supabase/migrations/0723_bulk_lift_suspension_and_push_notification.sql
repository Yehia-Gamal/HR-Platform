-- ═════════════════════════════════════════════════════════════════════
-- 0723_bulk_lift_suspension_and_push_notification.sql
-- 
-- 1) دالة lift_all_suspended_employees_admin:
--    رفع إيقاف جميع الموظفين الموقوفين دفعة واحدة بضغطة زر واحدة
--    - تفعيل حساباتهم فوراً (status = 'active', is_active = true)
--    - إرجاع غراماتهم الموقوفة/المضاعفة إلى قيمتها الأصلية
--    - إرسال إشعار صوتي فوري عالي الأولوية لكل موظف على شاشة الهاتف حتى والتطبيق مغلق:
--      العنوان: "تم رفع إيقافك عن العمل 🟢"
--      النص: "تم رفع إيقافك عن العمل بنجاح. برجاء العودة للتطبيق وتسجيل حضورك للعمل."
--    - تسجيل الحركة في سجل التدقيق audit_events
--
-- 2) تحديث دالة lift_employee_suspension_admin:
--    - إرسال الإشعار الصوتي الفوري ذو الأولوية العالية نفسه عند رفع الإيقاف الفردي
-- ═════════════════════════════════════════════════════════════════════

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تحديث دالة رفع إيقاف موظف فردياً مع إشعار صوتي فوري
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.lift_employee_suspension_admin(
  p_employee_id uuid,
  p_reason      text default null
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

  -- 2) إرجاع أي غرامات موقوفة أو مضاعفة إلى قيمتها الأصلية وبانتظار السداد
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

  -- 4) إشعار صوتي فوري عالي الأولوية للموظف يظهر على الشاشة حتى لو كان التطبيق مغلقاً
  perform public.notify_employee(
    p_employee_id,
    'تم رفع إيقافك عن العمل 🟢',
    'تم رفع إيقافك عن العمل بنجاح. برجاء العودة للتطبيق وتسجيل حضورك للعمل.',
    'system', 'urgent', 'employees', p_employee_id,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'kind', 'suspension_lifted',
      'penaltiesResetCount', v_lifted_count,
      'deepLink', '/my-day',
      'sound', 'urgent_notification',
      'fullScreen', false
    )
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
-- 2) دالة رفع الإيقاف لجميع الموظفين دفعة واحدة lift_all_suspended_employees_admin
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.lift_all_suspended_employees_admin(
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                    uuid := public.current_employee_id();
  v_emp                   record;
  v_total_lifted          int := 0;
  v_total_penalties_reset int := 0;
  v_cur_penalties_reset   int := 0;
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

  -- تكرار على كل موظف موقوف أو لديه غرامات موقوفة أو مضاعفة
  for v_emp in
    select emp.id as employee_id, emp.full_name_ar as employee_name
    from public.employees emp
    where coalesce(emp.is_deleted, false) = false
      and (
        emp.status = 'suspended'
        or emp.is_active = false
        or exists (
          select 1 from public.instant_attendance_penalties p
          where p.employee_id = emp.id
            and p.status in ('pending_payment', 'doubled', 'suspended')
            and (
              p.current_amount >= 500
              or p.status in ('doubled', 'suspended')
              or p.escalation_level in ('doubled', 'suspended')
              or p.current_amount > p.original_amount
            )
        )
      )
  loop
    -- 1) تفعيل الموظف والحساب فوراً
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_emp.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_emp.employee_id;

    -- 2) إرجاع الغرامات إلى قيمتها الأصلية وبانتظار السداد
    with upd as (
      update public.instant_attendance_penalties
         set status = 'pending_payment',
             escalation_level = 'initial',
             current_amount = original_amount,
             suspension_lifted_at = now(),
             suspension_lifted_by = v_me,
             notes = coalesce(notes || ' | ', '') || 'رفع الإيقاف إدارياً (جماعي) وإرجاع الغرامة للأصل (' || original_amount || ' ج.م)' || case when p_notes is not null and btrim(p_notes) <> '' then ': ' || btrim(p_notes) else '' end,
             updated_at = now()
       where employee_id = v_emp.employee_id
         and (
           status in ('suspended', 'doubled')
           or escalation_level in ('doubled', 'suspended')
           or current_amount > original_amount
         )
         and status not in ('paid', 'cancelled')
      returning id
    )
    select count(*) into v_cur_penalties_reset from upd;

    v_total_penalties_reset := v_total_penalties_reset + v_cur_penalties_reset;
    v_total_lifted := v_total_lifted + 1;

    -- 3) سجل التدقيق
    perform public.log_audit_event(
      'employee.suspension_lifted', 'general', 'info',
      'employees', v_emp.employee_id,
      'رفع الإيقاف عن العمل إدارياً (جماعي) للموظف: ' || coalesce(v_emp.employee_name, 'موظف') || ' — وإرجاع ' || v_cur_penalties_reset || ' غرامة للأصل',
      p_notes,
      jsonb_build_object(
        'employeeId', v_emp.employee_id,
        'penaltiesResetCount', v_cur_penalties_reset,
        'bulk', true
      )
    );

    -- 4) إرسال إشعار صوتي فوري عالي الأولوية لكل موظف
    perform public.notify_employee(
      v_emp.employee_id,
      'تم رفع إيقافك عن العمل 🟢',
      'تم رفع إيقافك عن العمل بنجاح. برجاء العودة للتطبيق وتسجيل حضورك للعمل.',
      'system', 'urgent', 'employees', v_emp.employee_id,
      jsonb_build_object(
        'employeeId', v_emp.employee_id,
        'kind', 'suspension_lifted',
        'penaltiesResetCount', v_cur_penalties_reset,
        'deepLink', '/my-day',
        'sound', 'urgent_notification',
        'fullScreen', false,
        'bulk', true
      )
    );
  end loop;

  return jsonb_build_object(
    'success', true,
    'liftedCount', v_total_lifted,
    'penaltiesResetCount', v_total_penalties_reset
  );
end;
$$;

revoke all on function public.lift_all_suspended_employees_admin(text) from public, anon;
grant execute on function public.lift_all_suspended_employees_admin(text) to authenticated, service_role;

commit;

