begin;

-- ============================================================================
-- 0662: تفويض الاعتماد الإداري وحوكمة البديل الساري (بند 7 من المرحلة الثانية)
--       - جدول approval_delegations مع سياسات RLS المحكمة
--       - دوال set_my_approval_delegation و cancel_my_approval_delegation و get_my_approval_delegations
--       - دالة فحص البديل get_active_approval_delegate
--       - تحديث resolve_request_approver لإرجاع البديل الساري
--       - تحديث process_request_sla لتحويل الطلب للبديل قبل التصعيد عند إجازة المدير
-- ============================================================================

-- 1) جدول تفويض الاعتمادات
create table if not exists public.approval_delegations (
  id uuid primary key default gen_random_uuid(),
  manager_employee_id uuid not null references public.employees(id) on delete cascade,
  delegate_employee_id uuid not null references public.employees(id) on delete cascade,
  starts_at date not null,
  ends_at date not null,
  reason text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint chk_delegation_dates check (ends_at >= starts_at),
  constraint chk_delegation_not_self check (manager_employee_id <> delegate_employee_id)
);

create index if not exists idx_approval_delegations_lookup
  on public.approval_delegations(manager_employee_id, starts_at, ends_at)
  where cancelled_at is null;

create index if not exists idx_approval_delegations_delegate
  on public.approval_delegations(delegate_employee_id, starts_at, ends_at)
  where cancelled_at is null;

alter table public.approval_delegations enable row level security;

drop policy if exists approval_delegations_read on public.approval_delegations;
create policy approval_delegations_read on public.approval_delegations
  for select to authenticated
  using (
    manager_employee_id = public.current_employee_id()
    or delegate_employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'executive', 'executive-director'])
    or public.has_any_permission(array['requests.request.read', 'organization.structure.read'])
  );

-- 2) دالة فحص البديل النشط لمدير معين
create or replace function public.get_active_approval_delegate(
  p_manager_employee_id uuid,
  p_as_of date default ((now() at time zone 'Africa/Cairo')::date)
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_delegate uuid;
begin
  if p_manager_employee_id is null then
    return null;
  end if;

  select d.delegate_employee_id into v_delegate
  from public.approval_delegations d
  join public.employees e on e.id = d.delegate_employee_id
  where d.manager_employee_id = p_manager_employee_id
    and d.starts_at <= p_as_of
    and d.ends_at >= p_as_of
    and d.cancelled_at is null
    and e.is_active and not e.is_deleted
  order by d.created_at desc
  limit 1;

  return v_delegate;
end;
$$;

-- 3) دالة تعيين تفويض الاعتماد للمدير الحالي
create or replace function public.set_my_approval_delegation(
  p_delegate_employee_id uuid,
  p_starts_at date,
  p_ends_at date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_inserted_id uuid;
  v_manager_name text;
begin
  if v_me is null then
    raise exception 'UNAUTHENTICATED_EMPLOYEE' using errcode = '42501';
  end if;

  if p_delegate_employee_id is null or p_delegate_employee_id = v_me then
    raise exception 'INVALID_DELEGATE_SELF_OR_NULL' using errcode = '22023';
  end if;

  if p_starts_at is null or p_ends_at is null or p_ends_at < p_starts_at then
    raise exception 'INVALID_DELEGATION_DATE_RANGE' using errcode = '22023';
  end if;

  if p_ends_at < v_today then
    raise exception 'CANNOT_DELEGATE_IN_PAST' using errcode = '22023';
  end if;

  -- التأكد من أن البديل موظف نشط
  if not exists (
    select 1 from public.employees
    where id = p_delegate_employee_id and is_active and not is_deleted
  ) then
    raise exception 'DELEGATE_NOT_ACTIVE' using errcode = '22023';
  end if;

  -- إلغاء أي تفويض سابق متداخل لنفس المدير
  update public.approval_delegations
    set cancelled_at = now()
  where manager_employee_id = v_me
    and cancelled_at is null
    and starts_at <= p_ends_at
    and ends_at >= p_starts_at;

  insert into public.approval_delegations(
    manager_employee_id,
    delegate_employee_id,
    starts_at,
    ends_at,
    reason
  )
  values (
    v_me,
    p_delegate_employee_id,
    p_starts_at,
    p_ends_at,
    trim(p_reason)
  )
  returning id into v_inserted_id;

  -- إشعار البديل
  select full_name_ar into v_manager_name from public.employees where id = v_me;
  perform public.notify_employee(
    p_delegate_employee_id,
    'تفويض صلاحيات اعتماد',
    'فوضك ' || coalesce(v_manager_name, 'المدير') || ' لصلاحيات اعتماد الطلبات من ' || p_starts_at::text || ' إلى ' || p_ends_at::text,
    'request',
    'normal',
    'delegation',
    v_inserted_id,
    jsonb_build_object(
      'delegationId', v_inserted_id,
      'managerId', v_me,
      'startsAt', p_starts_at,
      'endsAt', p_ends_at
    )
  );

  return jsonb_build_object(
    'id', v_inserted_id,
    'manager_employee_id', v_me,
    'delegate_employee_id', p_delegate_employee_id,
    'starts_at', p_starts_at,
    'ends_at', p_ends_at,
    'reason', p_reason,
    'success', true
  );
end;
$$;

-- 4) دالة إلغاء التفويض
create or replace function public.cancel_my_approval_delegation(
  p_delegation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_rec record;
begin
  if v_me is null and not public.current_is_full_access() then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;

  select * into v_rec
  from public.approval_delegations
  where id = p_delegation_id;

  if v_rec.id is null then
    raise exception 'DELEGATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_rec.manager_employee_id <> v_me and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  update public.approval_delegations
    set cancelled_at = now()
  where id = p_delegation_id
    and cancelled_at is null;

  -- إشعار البديل بالإلغاء
  perform public.notify_employee(
    v_rec.delegate_employee_id,
    'إلغاء تفويض الاعتماد',
    'تم إلغاء تفويض صلاحيات الاعتماد من المدير.',
    'request',
    'normal',
    'delegation',
    v_rec.id,
    jsonb_build_object('delegationId', v_rec.id, 'status', 'cancelled')
  );

  return true;
end;
$$;

-- 5) دالة جلب قائمة التفويضات للمدير الحالي أو البديل (الأحدث أولاً)
create or replace function public.get_my_approval_delegations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_result jsonb;
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', d.id,
      'manager_employee_id', d.manager_employee_id,
      'manager_name', m.full_name_ar,
      'manager_code', m.employee_code,
      'delegate_employee_id', d.delegate_employee_id,
      'delegate_name', del.full_name_ar,
      'delegate_code', del.employee_code,
      
      'starts_at', d.starts_at,
      'ends_at', d.ends_at,
      'reason', d.reason,
      'cancelled_at', d.cancelled_at,
      'created_at', d.created_at,
      'is_mine', (d.manager_employee_id = v_me),
      'is_active', (d.cancelled_at is null and d.starts_at <= v_today and d.ends_at >= v_today),
      'status', case
        when d.cancelled_at is not null then 'cancelled'
        when d.ends_at < v_today then 'expired'
        when d.starts_at > v_today then 'scheduled'
        else 'active'
      end
    ) order by d.created_at desc
  ), '[]'::jsonb) into v_result
  from public.approval_delegations d
  join public.employees m on m.id = d.manager_employee_id
  join public.employees del on del.id = d.delegate_employee_id
  where d.manager_employee_id = v_me
     or d.delegate_employee_id = v_me
     or public.current_is_full_access();

  return v_result;
end;
$$;

-- 6) تحديث resolve_request_approver لدمج البديل الساري
create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default ((now() at time zone 'Africa/Cairo')::date)
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
  v_delegate uuid;
begin
  if p_employee_id is null then return null; end if;

  -- ★ طاقم العيادات (الموظفون): معتمدهم المباشر دائماً مصطفى أحمد كمال الدين ★
  if public.is_clinic_team_member(p_employee_id)
     and p_employee_id <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c' then
    v_mgr := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid;
  else
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

    -- 2) مدير القسم من departments.manager_id
    if v_mgr is null then
      select e.department_id into v_dept_id
      from public.employees e
      where e.id = p_employee_id;

      if v_dept_id is not null then
        select d.manager_id into v_dept_mgr
        from public.departments d
        where d.id = v_dept_id and d.is_active;

        if v_dept_mgr is not null and v_dept_mgr <> p_employee_id then
          v_mgr := v_dept_mgr;
        else
          select parent_dept.manager_id into v_dept_mgr
          from public.departments child_dept
          join public.departments parent_dept on parent_dept.id = child_dept.parent_id
          where child_dept.id = v_dept_id and parent_dept.is_active
            and parent_dept.manager_id is not null
            and parent_dept.manager_id <> p_employee_id
          limit 1;

          if v_dept_mgr is not null then
            v_mgr := v_dept_mgr;
          end if;
        end if;
      end if;
    end if;

    -- 3) عمود manager_id المخزن على الموظف
    if v_mgr is null and v_emp_mgr is not null and v_emp_mgr <> p_employee_id then
      if exists (select 1 from public.employees where id = v_emp_mgr and is_active and not is_deleted) then
        v_mgr := v_emp_mgr;
      end if;
    end if;

    -- 4) مدير الموارد البشرية (hr-manager)
    if v_mgr is null then
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
    end if;

    -- 5) مسؤول الموارد البشرية (hr-specialist / hr-officer)
    if v_mgr is null then
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
    end if;

    -- 6) المدير العام أو التنفيذي
    if v_mgr is null then
      select e.id into v_mgr
      from public.employees e
      join public.user_roles ur on ur.user_id = e.user_id
      join public.roles r on r.id = ur.role_id
      where r.slug in ('general-manager', 'executive-director', 'executive')
        and e.is_active and not e.is_deleted
        and e.id <> p_employee_id
        and (ur.effective_to is null or ur.effective_to > now())
      order by e.created_at
      limit 1;
    end if;
  end if;

  -- ★ فحص تفويض الاعتماد: إذا كان المدير v_mgr لديه بديل ساري اليوم ولا يساوي مقدم الطلب نفسه ★
  if v_mgr is not null then
    v_delegate := public.get_active_approval_delegate(v_mgr, p_as_of);
    if v_delegate is not null and v_delegate <> p_employee_id then
      return v_delegate;
    end if;
  end if;

  return v_mgr;
end;
$$;

-- 7) تحديث process_request_sla لتفضيل البديل قبل التصعيد عند إجازة المدير
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count      integer := 0;
  v_row        record;
  v_next       record;
  v_ops_emp    uuid;
  v_target     uuid;
  v_role       text;
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_absent     boolean;
  v_due        boolean;
  v_delegate   uuid;
  v_del_name   text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      rs.assignee_employee_id,
      rs.escalation_deadline,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and (
        (rs.status in ('active', 'escalated')
         and rs.escalation_deadline is not null
         and rs.escalation_deadline < now())
        -- 0658: المدير المباشر في إجازة اليوم — لا ينتظر الطلب انقضاء مهلته
        or (rs.status = 'active' and rs.step_order = 1
            and public.employee_on_leave(coalesce(rs.assignee_employee_id, r.manager_employee_id), v_today))
      )
    order by rs.escalation_deadline nulls first
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    v_due := v_row.escalation_deadline is not null and v_row.escalation_deadline < now();
    v_absent := not v_due and v_row.step_order = 1 and v_row.step_status = 'active';

    -- ── ★ استثناء طاقم العيادات: يبقى كل شيء بالعيادات حصراً لدى مصطفى أحمد ★ ──
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then
      if not v_due then
        continue;
      end if;

      if v_row.manager_employee_id is not null then
        perform public.notify_employee(
          v_row.manager_employee_id,
          'تذكير: طلب من طاقم العيادات بانتظار قرارك',
          coalesce(v_row.title, '') || ' — يحتاج قرارك كمدير مباشر.',
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'clinic_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours',
            updated_at = now()
      where id = v_row.step_id;

      continue;
    end if;

    -- ── تفضيل البديل الساري للمدير عند الغياب قبل التصعيد للخطوة 2 ──
    if v_absent and v_row.step_order = 1 then
      v_delegate := public.get_active_approval_delegate(
        coalesce(v_row.assignee_employee_id, v_row.manager_employee_id),
        v_today
      );

      if v_delegate is not null and v_delegate <> v_row.employee_id then
        select full_name_ar into v_del_name from public.employees where id = v_delegate;

        update public.request_steps
          set assignee_employee_id = v_delegate,
              escalation_deadline  = now() + interval '2 hours',
              updated_at           = now()
        where id = v_row.step_id;

        insert into public.request_actions(
          request_id, actor_employee_id, action, from_status, to_status, comment, metadata
        ) values (
          v_row.request_id, null, 'delegate', 'pending', 'pending',
          'تحويل تلقائي للبديل المفوض (' || coalesce(v_del_name, 'البديل') || ') — المدير الأصيل في إجازة اليوم',
          jsonb_build_object('delegateEmployeeId', v_delegate, 'reason', 'manager_on_leave_delegated')
        );

        perform public.notify_employee(
          v_delegate,
          'طلب محوَّل إليك كبديل مفوض',
          coalesce(v_row.title, '') || ' — المدير الأصيل في إجازة، الطلب محول لك للبت فيه.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'delegated_on_leave',
            'deepLink', '/requests/' || v_row.request_id
          )
        );

        v_count := v_count + 1;
        continue;
      end if;
    end if;

    -- ── الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد ──
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير). المدير المباشر لم يبتّ والطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── الخطوة 1 (المدير المباشر العام): تصعيد إلى الخطوة 2 (أبو عمار) ──
    if v_row.step_status = 'escalated' then
      update public.request_steps
        set escalation_deadline = null, updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = null,
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        case when v_absent then 'تصعيد تلقائي — المدير المباشر في إجازة اليوم'
             else 'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)' end,
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role,
                           'reason', case when v_absent then 'manager_on_leave' else 'timeout' end)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', case when v_absent then 'manager_absent' else 'timeout_tier1' end,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- 8) الصلاحيات
revoke all on function public.set_my_approval_delegation(uuid, date, date, text) from public, anon;
grant execute on function public.set_my_approval_delegation(uuid, date, date, text) to authenticated;

revoke all on function public.cancel_my_approval_delegation(uuid) from public, anon;
grant execute on function public.cancel_my_approval_delegation(uuid) to authenticated;

revoke all on function public.get_my_approval_delegations() from public, anon;
grant execute on function public.get_my_approval_delegations() to authenticated;

revoke all on function public.get_active_approval_delegate(uuid, date) from public, anon;
grant execute on function public.get_active_approval_delegate(uuid, date) to authenticated, service_role;

revoke all on function public.process_request_sla(integer) from public, anon;
grant execute on function public.process_request_sla(integer) to service_role;

commit;
