-- ============================================================================
-- Migration 0598: إصلاح أعمدة مفقودة في أربع دوال منشورة
--
-- كل التغييرات هنا تُصلح مراجع أعمدة غير موجودة في الجداول المستهدفة
-- (أسهمت check-function-refs على prod مسبقاً):
--   1) resolve_request_approver (0505): employees.manager_id غير موجود
--      → إزالة الالتقاط، وتبقى خطوة سلسلة المدير (v_emp_mgr) معطّلة بلا تغيير
--      باقي المنطق (departments.manager_id + صلاحيات الموارد البشرية).
--   2) submit_penalty_dispute (0540): employees.direct_manager_id غير موجود
--      → استعلام manager_relations (primary) بنفس نمط 0505.
--   3) confirm_instant_penalty_payment (0567): عمودات fellowship fund الخاطئة
--      (source/reference_id/created_by) → source_type/instant_penalty_id/performed_by
--      + إضافة employee_name و reason الإلزاميين و performer_name المكتشف من 0515.
--   4) get_attendance_day_roster (0572): job_titles/departments تستخدمان name
--      وليس name_ar → jt.name / d.name.
--
-- لا يعدّل أي migration منشورة؛ يستبدل النسخ النهائية للدوال فقط.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) resolve_request_approver — إزالة employees.manager_id
-- ---------------------------------------------------------------------------
create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
  v_dept_id uuid;
  v_dept_mgr uuid;
  v_emp_mgr uuid;
begin
  if p_employee_id is null then return null; end if;

  -- 1) المدير المباشر الفعلي النشط من manager_relations
  select mr.manager_employee_id into v_mgr
  from public.manager_relations mr
  where mr.employee_id = p_employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= p_as_of
    and (mr.effective_to is null or mr.effective_to >= p_as_of)
    and mr.manager_employee_id <> p_employee_id
  order by (mr.effective_to is null) desc, mr.created_at desc
  limit 1;

  if v_mgr is not null then
    return v_mgr;
  end if;

  -- 2) مدير القسم من departments.manager_id
  select e.department_id into v_dept_id
  from public.employees e
  where e.id = p_employee_id;

  if v_dept_id is not null then
    select d.manager_id into v_dept_mgr
    from public.departments d
    where d.id = v_dept_id and d.is_active;

    if v_dept_mgr is not null and v_dept_mgr <> p_employee_id then
      return v_dept_mgr;
    end if;

    -- مدير الإدارة العليا إذا كان قسماً فرعياً
    select parent_dept.manager_id into v_dept_mgr
    from public.departments child_dept
    join public.departments parent_dept on parent_dept.id = child_dept.parent_id
    where child_dept.id = v_dept_id and parent_dept.is_active
      and parent_dept.manager_id is not null
      and parent_dept.manager_id <> p_employee_id
    limit 1;

    if v_dept_mgr is not null then
      return v_dept_mgr;
    end if;
  end if;

  -- 3) عمود manager_id المخزن على الموظف
  if v_emp_mgr is not null and v_emp_mgr <> p_employee_id then
    if exists (select 1 from public.employees where id = v_emp_mgr and is_active and not is_deleted) then
      return v_emp_mgr;
    end if;
  end if;

  -- 4) مدير الموارد البشرية (hr-manager)
  select e.id into v_mgr
  from public.employees e
  join public.user_roles ur on ur.user_id = e.user_id
  join public.roles r on r.id = ur.role_id
  where r.slug = 'hr-manager'
    and e.is_active and not e.is_deleted
    and e.id <> p_employee_id
    and (ur.effective_to is null or ur.effective_to > now())
  order by e.created_at
  limit 1;

  if v_mgr is not null then return v_mgr; end if;

  -- 5) مسؤول الموارد البشرية (hr-specialist / hr-officer)
  select e.id into v_mgr
  from public.employees e
  join public.user_roles ur on ur.user_id = e.user_id
  join public.roles r on r.id = ur.role_id
  where r.slug in ('hr-specialist', 'hr-officer')
    and e.is_active and not e.is_deleted
    and e.id <> p_employee_id
    and (ur.effective_to is null or ur.effective_to > now())
  order by e.created_at
  limit 1;

  if v_mgr is not null then return v_mgr; end if;

  -- 6) مدير العمليات (operations-manager-1)
  select e.id into v_mgr
  from public.employees e
  join public.user_roles ur on ur.user_id = e.user_id
  join public.roles r on r.id = ur.role_id
  where r.slug in ('operations-manager-1', 'operations-manager')
    and e.is_active and not e.is_deleted
    and e.id <> p_employee_id
    and (ur.effective_to is null or ur.effective_to > now())
  order by e.created_at
  limit 1;

  if v_mgr is not null then return v_mgr; end if;

  -- 7) المدير التنفيذي (executive-director / executive / general-manager)
  select e.id into v_mgr
  from public.employees e
  join public.user_roles ur on ur.user_id = e.user_id
  join public.roles r on r.id = ur.role_id
  where r.slug in ('executive-director', 'executive', 'general-manager')
    and e.is_active and not e.is_deleted
    and e.id <> p_employee_id
    and (ur.effective_to is null or ur.effective_to > now())
  order by e.created_at
  limit 1;

  if v_mgr is not null then return v_mgr; end if;

  -- 8) مدير النظام (admin / super-admin)
  select e.id into v_mgr
  from public.employees e
  join public.user_roles ur on ur.user_id = e.user_id
  join public.roles r on r.id = ur.role_id
  where r.slug in ('super-admin', 'admin')
    and e.is_active and not e.is_deleted
    and e.id <> p_employee_id
    and (ur.effective_to is null or ur.effective_to > now())
  order by e.created_at
  limit 1;

  return v_mgr;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) submit_penalty_dispute — إشعار المدير عبر manager_relations
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_penalty_dispute(
  p_penalty_id uuid,
  p_reason     text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee_id uuid;
  v_existing    int;
  v_id          uuid;
  v_penalty_status text;
  v_manager_id  uuid;
begin
  v_employee_id := public.current_employee_id();
  if v_employee_id is null then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  select status into v_penalty_status
  from public.instant_attendance_penalties
  where id = p_penalty_id;

  if v_penalty_status is null then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_penalty_status in ('paid','cancelled') then
    raise exception 'لا يمكن الطعن على غرامة %', case v_penalty_status when 'paid' then 'مدفوعة' else 'ملغاة' end
      using errcode = '22023';
  end if;

  select count(*) into v_existing
  from public.penalty_disputes
  where penalty_id = p_penalty_id and status = 'pending';

  if v_existing > 0 then
    raise exception 'يوجد طعن معلق بالفعل على هذه الغرامة' using errcode = '22023';
  end if;

  insert into public.penalty_disputes (penalty_id, employee_id, reason)
  values (p_penalty_id, v_employee_id, p_reason)
  returning id into v_id;

  -- إشعار الموظف
  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select u.id,
         'تم إرسال طعنك',
         'تم استلام طعنك على الغرامة. سيتم مراجعته من قِبَل الموارد البشرية.',
         'system', 'normal',
         'penalty_dispute', v_id,
         '/me/penalties',
         jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
  from public.employees e
  join auth.users u on u.id = e.user_id
  where e.id = v_employee_id;

  -- إشعار المدير المباشر
  select mr.manager_employee_id into v_manager_id
    from public.manager_relations mr
   where mr.employee_id = v_employee_id
     and mr.relation_type = 'primary'
     and mr.effective_from <= now()
     and (mr.effective_to is null or mr.effective_to > now())
     and mr.manager_employee_id <> v_employee_id
   order by (mr.effective_to is null) desc, mr.created_at desc
   limit 1;

  if v_manager_id is not null then
    insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
    select u.id,
           'طعن جديد على غرامة',
           'أرسل موظف طعناً على غرامة حضور. راجع التفاصيل.',
           'system', 'high',
           'penalty_dispute', v_id,
           '/admin/finance?tab=instant-penalties',
           jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
    from public.employees e
    join auth.users u on u.id = e.user_id
    where e.id = v_manager_id;
  end if;

  -- إشعار HR (بدالة user_has_permission → استعلام مباشر)
  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select u.id,
         'طعن جديد على غرامة',
         'أرسل موظف طعناً على غرامة حضور. يرجى المراجعة.',
         'system', 'high',
         'penalty_dispute', v_id,
         '/admin/finance?tab=instant-penalties',
         jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
  from auth.users u
  where exists (
    select 1 from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = u.id and p.code = 'payroll.run.manage'
  );

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) confirm_instant_penalty_payment — عمودات fellowship_fund_transactions
-- ---------------------------------------------------------------------------
create or replace function public.confirm_instant_penalty_payment(
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
  v_my_name text;
  v_current_balance numeric(12,2) := 0;
  v_new_balance numeric(12,2) := 0;
  v_was_suspended boolean := false;
  v_has_other_suspended boolean := false;
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

  -- 2) رفع التعليق فوراً إن لم توجد غرامات معلقة أخرى للموظف
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
    'instant_penalty.paid', 'financial', 'info',
    'instant_attendance_penalties', v_row.id,
    'سداد غرامة فورية: ' || v_emp_name || ' — ' || v_row.current_amount || ' ج.م تم توريدها لصندوق الزمالة' || case when v_was_suspended and not v_has_other_suspended then ' (تم رفع التعليق وإعادة فتح الحساب)' else '' end,
    null,
    jsonb_build_object(
      'penaltyId', v_row.id,
      'employeeId', v_row.employee_id,
      'amount', v_row.current_amount,
      'confirmedBy', v_me,
      'fellowshipNewBalance', v_new_balance,
      'wasSuspended', v_was_suspended,
      'suspensionLifted', not v_has_other_suspended
    )
  );

  -- 5) إشعار الموظف
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم سداد الغرامة الفورية بنجاح',
    'تم تأكيد سداد غرامة التأخير بقيمة ' || v_row.current_amount || ' ج.م وإيداعها في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_suspended then '. تم رفع الإيقاف وإعادة فتح حسابك بنجاح ومباشرة العمل.' else '.' end,
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
    'suspensionLifted', not v_has_other_suspended,
    'fellowshipBalance', v_new_balance,
    'message', 'تم تأكيد السداد وإيداع ' || v_row.current_amount || ' ج.م في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_suspended then ' وتمت إعادة تفعيل حساب الموظف.' else '.' end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) get_attendance_day_roster — job_titles/departments.name
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(p_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
begin
  -- 0572: موظف العيادات لا يطّلع على دفتر حضور الآخرين.
  if public.employee_blocks_inbound_alerts(public.current_employee_id()) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  return coalesce((
    with base as (
      select
        e.id,
        e.full_name_ar,
        e.employee_code,
        e.photo_url,
        jt.name as job_title,
        d.name  as department,
        m.full_name_ar as manager_name,
        ad.status as att_status,
        ad.first_check_in,
        ad.last_check_out,
        ad.late_minutes,
        ad.early_leave_minutes,
        exists (
          select 1 from public.leave_requests lr
          join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id
            and r.status in ('approved', 'completed')
            and v_date between lr.start_date and lr.end_date
        ) as on_leave,
        (
          select wa.assignment_type
          from public.work_assignments wa
          where wa.responsible_employee_id = e.id
            and wa.status in ('APPROVED','IN_PROGRESS')
            and v_date between (wa.start_at at time zone 'Africa/Cairo')::date
                           and (wa.end_at   at time zone 'Africa/Cairo')::date
          limit 1
        ) as assignment_type
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.manager_relations mr on mr.employee_id = e.id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
      left join public.employees m on m.id = mr.manager_employee_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_date
      where e.status = 'active'
        and coalesce(e.is_deleted, false) = false
        and not public.is_employee_attendance_exempt(e.id) -- 0532: استبعاد المعفيين
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        ) -- 0572: إخفاء المعزول عن غير المرئين له
        and (p_department_id is null or e.department_id = p_department_id)
        and (p_branch_id is null or e.branch_id = p_branch_id)
        and (
          p_manager_id is null or exists (
            select 1 from public.manager_relations mr2
            where mr2.employee_id = e.id
              and mr2.manager_employee_id = p_manager_id
              and mr2.effective_from <= now()
              and (mr2.effective_to is null or mr2.effective_to > now())
          )
        )
    ),
    classified as (
      select *,
        case
          when on_leave then 'on_leave'
          when assignment_type is not null then 'assignment'
          when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
          when att_status = 'present' then 'present'
          when att_status = 'late' then 'late'
          when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
          when last_check_out is not null then 'checked_out'
          when att_status = 'absent' then 'absent'
          when extract(isodow from v_date) = 5 then 'weekend'
          else 'not_yet'
        end as derived_status
      from base
    )
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'name', full_name_ar,
      'employeeCode', employee_code,
      'avatarUrl', photo_url,
      'jobTitle', job_title,
      'department', department,
      'managerName', manager_name,
      'status', derived_status,
      'attStatus', att_status,
      'firstCheckIn', first_check_in,
      'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes,
      'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave,
      'assignmentType', assignment_type
    ) order by full_name_ar)
    from classified
  ), '[]'::jsonb);
end;
$function$;
