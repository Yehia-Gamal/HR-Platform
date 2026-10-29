-- =====================================================================
-- 0712: إرجاع الغرامة المضاعفة لأصلها وتبويب الموظفين الموقوفين وتصحيح البصمة
-- =====================================================================
-- 1) دالة revert_doubled_instant_penalty:
--    إرجاع أي غرامة تضاعفت إلى 500 ج.م لقيمتها الأصلية (20 أو 50 أو 150 ج.م)
--    مع إرجاع الحالة إلى pending_payment بدون مضاعفة لتمكين الموظف من السداد.
--
-- 2) دالة get_suspended_employees_admin:
--    استرجاع قائمة الموظفين الموقوفين عن العمل (المعلقين بسبب الغرامات أو النظام)
--    مع إجمالي المبالغ المستحقة الأصلية والمضاعفة وتفاصيل غراماتهم.
--
-- 3) دالة lift_employee_suspension_admin:
--    رفع الإيقاف إدارياً عن الموظف وإعادة تفعيل حسابه وإرجاع غراماته إلى أصلها.
--
-- 4) تصحيح سجل بصمة انصراف مصطفى أحمد كمال الدين ليوم 13-10-2026.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة إرجاع الغرامة المضاعفة لقيمتها الأصلية (بدون مضاعفة 500 ج.م)
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
    'financial', 'normal', 'instant_attendance_penalties', p_penalty_id,
    jsonb_build_object('penaltyId', p_penalty_id, 'amount', v_row.original_amount)
  );

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'newAmount', v_row.current_amount,
    'originalAmount', v_row.original_amount,
    'status', v_row.status,
    'employeeStatus', case when v_has_other_suspended then 'suspended' else 'active' end
  );
end;
$$;

revoke all on function public.revert_doubled_instant_penalty(uuid, text) from public, anon;
grant execute on function public.revert_doubled_instant_penalty(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) دالة استرجاع الموظفين الموقوفين عن العمل get_suspended_employees_admin
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_suspended_employees_admin()
returns jsonb
language plpgsql
stable
security definer
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
      bool_or(p.current_amount >= 500 or p.status in ('doubled', 'suspended')) as has_doubled,
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
-- 3) دالة رفع الإيقاف إدارياً عن الموظف وإعادة تفعيله
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
    raise exception 'غير مسموح' using errcode = '42501';
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

  -- 1) إعادة تفعيل الموظف والحساب
  update public.employees
     set status = 'active',
         is_active = true,
         updated_at = now()
   where id = p_employee_id;

  update public.profiles
     set status = 'active',
         updated_at = now()
   where employee_id = p_employee_id;

  -- 2) إرجاع أي غرامات موقوفة أو مضاعفة للموظف إلى قيمتها الأصلية وبانتظار السداد
  with updated_penalties as (
    update public.instant_attendance_penalties
       set status = 'pending_payment',
           escalation_level = 'initial',
           current_amount = original_amount,
           suspension_lifted_at = now(),
           suspension_lifted_by = v_me,
           notes = coalesce(notes || ' | ', '') || 'رفع الإيقاف إدارياً وإرجاع الغرامة للأصل' || case when p_reason is not null and btrim(p_reason) <> '' then ': ' || btrim(p_reason) else '' end,
           updated_at = now()
     where employee_id = p_employee_id
       and status in ('suspended', 'doubled')
    returning id
  )
  select count(*) into v_lifted_count from updated_penalties;

  -- 3) سجل التدقيق
  perform public.log_audit_event(
    'employee.suspension_lifted', 'operations', 'warning',
    'employees', p_employee_id,
    'رفع الإيقاف عن العمل إدارياً للموظف: ' || coalesce(v_emp_name, 'موظف'),
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
    'تم رفع الإيقاف وإعادة فتح حسابك على المنظومة بنجاح. يمكنك الآن الدخول ومباشرة مهامك.',
    'system', 'high', 'employees', p_employee_id,
    jsonb_build_object('employeeId', p_employee_id)
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
-- 4) تصحيح سجل حضور وانصراف مصطفى أحمد كمال الدين ليوم 13-10-2026
-- ─────────────────────────────────────────────────────────────────────

-- أ) تحديث سجل اليوم 2026-10-13 بالانصراف 16:10:00 (19:10 بتوقيت القاهرة) والحالة حاضر
update public.attendance_daily
   set last_check_out = '2026-10-13 16:10:00+00',
       status = 'present',
       work_minutes = 494,
       updated_at = now()
 where employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
   and work_date = '2026-10-13';

-- ب) استعادة الانصراف الأصلي ليوم 2026-10-12
update public.attendance_daily
   set last_check_out = '2026-10-12 16:10:29.205978+00',
       status = 'present',
       work_minutes = 520,
       updated_at = now()
 where employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
   and work_date = '2026-10-12';

-- ج) تحديث سجل التصحيح والطلب ليرتبط باليوم الصحيح 2026-10-13
update public.attendance_corrections
   set work_date = '2026-10-13',
       attendance_daily_id = '4fed17b0-258d-41e7-804a-00b75dbdc657',
       requested_check_out = '2026-10-13 16:10:00+00',
       updated_at = now()
 where id = '2ae445bb-0be7-48d8-a335-f61dfa0408c3';

update public.requests
   set payload = jsonb_set(
         jsonb_set(payload, '{workDate}', '"2026-10-13"'),
         '{requestedCheckOut}', '"2026-10-13T16:10:00+00:00"'
       )
 where id = 'fe6bdc4c-abc8-4d64-b53a-16dd737fbb89';

commit;

