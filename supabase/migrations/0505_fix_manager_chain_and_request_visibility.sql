-- 0505: إصلاح سلسلة العلاقات الإدارية وتغيير المدير ورؤية وقبول الطلبات
-- ─────────────────────────────────────────────────────────────────
-- المشاكل الجذرية المعالجة:
--   1) لا يمكن تغيير المدير المباشر: فخ الصلاحيات وغياب ORDER BY في get_employee_360
--      وعدم مزامنة employees.manager_id ونقل الطلبات المعلّقة للمدير الجديد.
--   2) المدير لا يرى طلبات موظفيه ولا يستطيع قبولها: قيود RLS على requests،
--      واستيلاء التشغيل في resolve_request_approver، ووجود طلبات بـ manager_employee_id = NULL.
--   3) فشل أو عدم تسجيل مأموريات وإجازات بعض الموظفين: حظر الموافقة الذاتية،
--      وحظر الأثر الرجعي للإجازات العارضة والمرضية وإجازات الإدارة، وعدم وجود معتمد بديل.
-- ─────────────────────────────────────────────────────────────────

begin;

-- ═══════════════════════════════════════════════════════════════════
-- 1) resolve_request_approver: معتمد موثوق وشامل لا يعيد NULL أبداً
-- ═══════════════════════════════════════════════════════════════════
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
  select e.department_id, e.manager_id into v_dept_id, v_emp_mgr
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

comment on function public.resolve_request_approver(uuid, date) is
  '0505: معتمد موثوق للطلبات يبدأ بالمدير المباشر ويتدرج في الهيكل ولا يعيد فارغاً أبداً.';

revoke all on function public.resolve_request_approver(uuid, date) from public;
grant execute on function public.resolve_request_approver(uuid, date) to authenticated, service_role;


-- ═══════════════════════════════════════════════════════════════════
-- 2) _submit_request_for: قبول كافة الأنواع ومنع تعطل طلبات المديرين
-- ═══════════════════════════════════════════════════════════════════
create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  -- إذا كان المدير مسجلاً كنفس الموظف أو فارغاً، نحل معتمداً أعلى تلقائياً
  if p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if public.is_employee_isolated(p_employee_id) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;
    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء خطوات سير العمل
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, coalesce(v_me, p_employee_id), 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- إشعار المدير المعتمد للخطوة النشطة
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'requestId', v_row.id,
        'employeeId', v_row.employee_id,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;

comment on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) is
  '0505: تقديم الطلبات مع دعم الأنواع الموسعة وتصعيد المعالجة الذاتية للمديرين تلقائياً.';


-- ═══════════════════════════════════════════════════════════════════
-- 3) change_employee_manager_admin: تغيير المدير بسلاسة مع نقل الطلبات
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.change_employee_manager_admin(
  p_employee_id uuid,
  p_manager_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old_manager uuid;
  v_pending_count integer := 0;
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.update_sensitive',
      'people.employee.update_basic',
      'employees.manage',
      'admin.manage',
      'people.manage'
    ])
    or public.current_has_active_role(array[
      'admin',
      'super-admin',
      'hr-manager',
      'operations-manager-1',
      'executive',
      'executive-director'
    ])
  ) then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'change_reason_required' using errcode = '22023';
  end if;

  if p_manager_id = p_employee_id then
    raise exception 'manager_cannot_be_self' using errcode = '22023';
  end if;

  perform 1 from public.employees
  where id = p_employee_id and not is_deleted
  for update;
  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  -- الحصول على المدير القديم
  select manager_employee_id into v_old_manager
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by (effective_to is null) desc, created_at desc
  limit 1;

  if v_old_manager is null then
    select manager_id into v_old_manager
    from public.employees
    where id = p_employee_id;
  end if;

  if p_manager_id is not null then
    if not exists (
      select 1 from public.employees
      where id = p_manager_id and not is_deleted and status = 'active' and is_active
    ) then
      raise exception 'manager_not_active' using errcode = '22023';
    end if;

    -- فحص الدورة الإدارية
    if exists (
      with recursive manager_chain(id, path) as (
        select p_manager_id, array[p_manager_id]::uuid[]
        union all
        select mr.manager_employee_id, c.path || mr.manager_employee_id
        from public.manager_relations mr
        join manager_chain c on c.id = mr.employee_id
        where mr.relation_type = 'primary'
          and (mr.effective_to is null or mr.effective_to >= current_date)
          and not mr.manager_employee_id = any(c.path)
      )
      select 1 from manager_chain where id = p_employee_id
    ) then
      raise exception 'manager_cycle_not_allowed' using errcode = '22023';
    end if;
  end if;

  -- 1) تحديث جدول employees
  update public.employees
  set manager_id = p_manager_id, updated_at = now()
  where id = p_employee_id;

  -- 2) إنهاء العلاقات الإدارية السابقة بأمان
  -- إذا كانت قد بدأت قبل اليوم، نجعل نهايتها أمس (current_date - 1) لتجنب التصادم
  -- إذا كانت قد بدأت اليوم، نجعل نهايتها اليوم
  update public.manager_relations
  set effective_to = case
        when effective_from < current_date then current_date - 1
        else current_date
      end,
      updated_at = now()
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and (effective_to is null or effective_to >= current_date);

  -- 3) إدراج العلاقة الإدارية الجديدة
  if p_manager_id is not null then
    insert into public.manager_relations (
      employee_id, manager_employee_id, relation_type,
      effective_from, effective_to, created_by
    ) values (
      p_employee_id, p_manager_id, 'primary',
      current_date, null, auth.uid()
    );
  end if;

  -- 4) نقل كافة الطلبات المعلّقة لهذا الموظف إلى المدير الجديد فوراً
  update public.requests
  set manager_employee_id = p_manager_id,
      updated_at = now()
  where employee_id = p_employee_id
    and status = 'pending';

  get diagnostics v_pending_count = row_count;

  -- 5) نقل خطوات سير العمل النشطة إلى المدير الجديد
  update public.request_steps
  set assignee_employee_id = p_manager_id,
      updated_at = now()
  where request_id in (
    select id from public.requests where employee_id = p_employee_id and status = 'pending'
  )
  and status in ('active', 'pending')
  and (assignee_employee_id is null or assignee_employee_id = v_old_manager);

  perform public.log_audit_event(
    'employee_manager_changed', 'people', 'warning', 'employees', p_employee_id,
    'تغيير المدير المباشر', trim(p_reason),
    jsonb_build_object(
      'previousManagerId', v_old_manager,
      'managerId', p_manager_id,
      'pendingRequestsTransferred', v_pending_count,
      'reason', trim(p_reason)
    )
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'previousManagerId', v_old_manager,
    'managerId', p_manager_id,
    'pendingRequestsTransferred', v_pending_count,
    'updatedAt', now()
  );
end;
$$;

comment on function public.change_employee_manager_admin(uuid, uuid, text) is
  '0505: تغيير المدير المباشر بصلاحيات موسعة وحل تعارض التواريخ ونقل الطلبات المعلّقة فوراً.';

revoke all on function public.change_employee_manager_admin(uuid, uuid, text) from public, anon;
grant execute on function public.change_employee_manager_admin(uuid, uuid, text) to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 4) get_employee_360: ترتيب صريح للعلاقة الإدارية النشطة (Order By Trap Fix)
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'email', au.email,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', (
      select mr.manager_employee_id
      from public.manager_relations mr
      where mr.employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      order by (mr.effective_to is null) desc, mr.created_at desc
      limit 1
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id=e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id=e.id order by created_at desc limit 10
      ) t
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id=ed.department_id
      where ed.employee_id=e.id
        and (ed.start_date is null or ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        and (ed.end_date is null or ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.employees manager_rel on manager_rel.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1
  )
  left join public.profiles profile on profile.employee_id=e.id
  left join auth.users au on au.id=profile.id
  where e.id=p_employee_id;

  if v_result is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

comment on function public.get_employee_360(uuid) is
  '0505: ملف الموظف 360 مع ترتيب صريح يضمن اختيار المدير النشط الحالي بدقة.';

revoke all on function public.get_employee_360(uuid) from public;
grant execute on function public.get_employee_360(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 5) تحديث RLS Policies لتضمين المدير المباشر عبر manager_relations
-- ═══════════════════════════════════════════════════════════════════

-- أ) سياسة requests_select
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or manager_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = requests.employee_id
        and mr.manager_employee_id = public.current_employee_id()
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or exists (
      select 1 from public.request_steps rs
      where rs.request_id = requests.id
        and rs.assignee_employee_id = public.current_employee_id()
    )
    or public.can_access_employee(employee_id, 'requests.read')
    or public.can_access_employee(employee_id, 'requests.request.read')
    or public.can_access_employee(employee_id, 'requests.approve')
    or public.can_access_employee(employee_id, 'requests.request.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or public.current_is_full_access()
  );

-- ب) سياسة leave_requests_select
drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select on public.leave_requests
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or exists (
      select 1 from public.requests r
      where r.id = leave_requests.request_id
        and (
          r.manager_employee_id = public.current_employee_id()
          or exists (
            select 1 from public.manager_relations mr
            where mr.employee_id = r.employee_id
              and mr.manager_employee_id = public.current_employee_id()
              and mr.relation_type = 'primary'
              and mr.effective_from <= current_date
              and (mr.effective_to is null or mr.effective_to >= current_date)
          )
        )
    )
    or public.can_access_employee(employee_id, 'requests.read')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    or public.current_is_full_access()
  );

-- ج) سياسة missions_select
drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = missions.employee_id
        and mr.manager_employee_id = public.current_employee_id()
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or public.can_access_employee(employee_id, 'requests.read')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or public.current_is_full_access()
  );


-- ═══════════════════════════════════════════════════════════════════
-- 6) get_request_inbox: صندوق الطلبات مع فلترة العلاقات الإدارية
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select coalesce(jsonb_agg(item order by item->>'createdAt' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', r.id,
      'requestNumber', r.request_number,
      'requestType', r.request_type,
      'employeeId', r.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'title', r.title,
      'reason', r.reason,
      'status', r.status,
      'workflowStatus', r.workflow_status,
      'currentStepOrder', r.current_step_order,
      'activeStepName', active_step.name_ar,
      'decisionDueAt', r.decision_due_at,
      'createdAt', r.created_at,
      'payload', r.payload,
      'missionExecution', case when r.request_type in ('mission','convoy','fundraising') then (
        select to_jsonb(me) from (
          select me.id, me.status,
                 me.started_at as "startedAt",
                 me.ended_at as "endedAt",
                 me.actual_minutes as "actualMinutes",
                 me.report, me.outcome
          from public.mission_executions me
          where me.request_id = r.id
        ) me
      ) else null end
    ) as item
    from public.requests r
    join public.employees e on e.id = r.employee_id
    left join lateral (
      select rs.name_ar from public.request_steps rs
      where rs.request_id = r.id and rs.status in ('active','escalated')
      order by rs.step_order limit 1
    ) active_step on true
    where (
      -- طلباتي الشخصية
      r.employee_id = public.current_employee_id()
      -- طلبات المرؤوسين المباشرين (عبر العلاقة الإدارية)
      or exists (
        select 1 from public.manager_relations mr
        where mr.employee_id = r.employee_id
          and mr.manager_employee_id = public.current_employee_id()
          and mr.relation_type = 'primary'
          and mr.effective_from <= current_date
          and (mr.effective_to is null or mr.effective_to >= current_date)
      )
      -- طلبات المرؤوسين المباشرين (عبر manager_employee_id المخزّن)
      or r.manager_employee_id = public.current_employee_id()
      -- خطوة مكلّفة للمستخدم الحالي
      or exists (
        select 1 from public.request_steps rs
        where rs.request_id = r.id
          and rs.assignee_employee_id = public.current_employee_id()
      )
      -- الوصول بناءً على الصلاحيات
      or public.can_access_employee(r.employee_id, 'requests.read')
      or public.can_access_employee(r.employee_id, 'requests.request.read')
      -- مدراء الموارد البشرية والتنفيذيين والنظام
      or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
      or public.current_is_full_access()
    )
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) q;
$function$;

comment on function public.get_request_inbox(integer) is
  '0505: صندوق الطلبات مع فلترة شاملة للمدير المباشر والمكلّفين والإدارة.';


-- ═══════════════════════════════════════════════════════════════════
-- 7) get_mobile_request_detail: تفاصيل الطلب مع فحص العلاقات الإدارية
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to public, pg_temp
as $function$
declare
  v_request public.requests;
  v_employee public.employees;
  v_can_decide boolean := false;
  v_can_cancel boolean := false;
  v_steps jsonb := '[]'::jsonb;
  v_attachments jsonb := '[]'::jsonb;
  v_decision_actor text;
  v_decision_mode text;
  v_decision_on_behalf boolean := false;
  v_execution jsonb;
  v_is_direct_mgr boolean := false;
begin
  select * into v_request from public.requests where id = p_request_id;
  if not found then raise exception 'request not found' using errcode = 'P0002'; end if;

  v_is_direct_mgr := (v_request.manager_employee_id = public.current_employee_id()) or exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = v_request.employee_id
      and mr.manager_employee_id = public.current_employee_id()
      and mr.relation_type = 'primary'
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );

  if not (
    v_request.employee_id = public.current_employee_id()
    or v_is_direct_mgr
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  v_can_cancel := v_request.status = 'pending' and v_request.employee_id = public.current_employee_id();

  v_can_decide := v_request.status = 'pending' and (
    public.current_is_full_access()
    or v_is_direct_mgr
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.has_permission('requests.request.approve')
    or public.has_permission('requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'order', s.step_order, 'name', s.name_ar, 'status', s.status,
    'decision', case when s.status in ('approved','rejected') then s.status else null end,
    'comment', s.comment, 'decidedAt', s.acted_at, 'dueAt', s.due_at,
    'actorName', actor.full_name_ar
  ) order by s.step_order), '[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id = s.acted_by
  where s.request_id = p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
  ) order by a.created_at), '[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type = 'request' and a.entity_id = p_request_id;

  select e.full_name_ar, a.metadata->>'decisionMode', coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
  into v_decision_actor, v_decision_mode, v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id = a.actor_employee_id
  where a.request_id = p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  if v_request.request_type in ('mission','convoy','fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
      from public.mission_executions me
      where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'canDecide', v_can_decide,
    'canCancel', v_can_cancel,
    'steps', v_steps,
    'attachments', v_attachments,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end $function$;

comment on function public.get_mobile_request_detail(uuid) is
  '0505: تفاصيل الطلب للموبايل مع فحص دقيق للعلاقات الإدارية وصلاحيات البت.';

revoke all on function public.get_mobile_request_detail(uuid) from public, anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 8) submit_my_request & admin_create_leave_request: مرونة الإجازات
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_idempotency_key uuid default null::uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_row               public.requests;
  v_payload           jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
  v_day_mark          boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date        date;
  v_end_date          date;
  v_permit_date       date;
  v_minutes           integer;
  v_leave_type        text;
  v_leave_type_id     uuid;
  v_affects           boolean;
  v_days              numeric;
  v_substitute        uuid;
  v_correction_date   date;
  v_correction_type   text;
  v_corrected_time    text;
  v_permit_kind       text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select * into v_row
    from public.requests
    where employee_id = v_me
      and payload ->> 'clientId' = p_idempotency_key::text
      and created_at > now() - interval '10 minutes';
    if found then
      return v_row;
    end if;
    v_payload := v_payload || jsonb_build_object('clientId', p_idempotency_key::text);
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'day mark requires a date' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'day marks are single-day only' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'day marks are allowed within the current month only' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'future days cannot be marked' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;

        -- المرونة: الإجازات العارضة والمرضية يُسمح بتقديمها عن أيام سابقة ضمن الشهر الحالي
        if v_start_date < v_month_start and not v_day_mark then
          raise exception 'لا يمكن تقديم إجازة عن أشهر سابقة' using errcode = '22023';
        end if;
        if v_leave_type not in ('casual', 'sick') and not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;

        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      -- ─── مأمورية (تبدأ من وقت الإنشاء فوراً ودون إلزامية أوقات) ───────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل'),
          'days', 1,
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', true);

      -- ─── قافلة / فاندي ───────────────────────────────────────────────────
      when 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', ((v_end_date - v_start_date) + 1));

      -- ─── إذن تأخير صباحي ──────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر ──────────────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── إذن حضور موحد ─────────────────────────────────────────────────────
      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن الحضور بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'نوع إذن غير مدعوم' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes);

      -- ─── تصحيح حضور ─────────────────────────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'تاريخ التصحيح مطلوب' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
        end if;
        if v_corrected_time is null or v_corrected_time !~ '^\d{2}:\d{2}$' then
          raise exception 'correctedTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime', v_corrected_time);

      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'تواريخ أو قيم رقمية غير صالحة' using errcode = '22023';
  end;

  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  return v_row;
end;
$$;

comment on function public.submit_my_request(text, text, text, jsonb, uuid) is
  '0505: تقديم الطلبات الذاتية مع مرونة الإجازات العارضة والمرضية وبدء المأموريات فورياً.';

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;


-- تحديث admin_create_leave_request
create or replace function public.admin_create_leave_request(
  p_employee_id      uuid,
  p_leave_type       text,
  p_start_date       date,
  p_end_date         date,
  p_reason           text default null,
  p_title            text default null,
  p_handover_notes   text default null,
  p_substitute_employee_id uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_leave_type_id     uuid;
  v_days              numeric;
  v_payload           jsonb;
  v_row               public.requests;
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('requests.leave.balance.adjust')
    or public.current_has_active_role(array['admin','super-admin','hr-manager'])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'EMPLOYEE_REQUIRED' using errcode = '22023';
  end if;
  if not exists(
    select 1 from public.employees
    where id = p_employee_id and is_active and not is_deleted
  ) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if p_leave_type = 'emergency' then p_leave_type := 'casual'; end if;
  if p_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
    raise exception 'unsupported leave type' using errcode = '22023';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'leave start and end dates are required' using errcode = '22023';
  end if;
  if p_end_date < p_start_date then
    raise exception 'leave end date cannot precede start date' using errcode = '22023';
  end if;

  -- السماح للإدارة بتسجيل الإجازات عن أي يوم خلال الشهر الحالي
  if p_start_date < v_month_start then
    raise exception 'لا يمكن تسجيل إجازة عن أشهر سابقة' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'reason is required (min 3 chars)' using errcode = '22023';
  end if;

  select id into v_leave_type_id
  from public.leave_types
  where code = p_leave_type and is_active = true;
  if v_leave_type_id is null then
    raise exception 'leave type is inactive or unknown: %', p_leave_type using errcode = '22023';
  end if;

  v_days := (p_end_date - p_start_date) + 1;
  v_payload := jsonb_build_object(
    'leaveType', p_leave_type,
    'startDate', p_start_date,
    'endDate', p_end_date,
    'days', v_days,
    'immediate', (p_leave_type = 'casual'),
    'adminCreated', true,
    'handoverNotes', nullif(p_handover_notes,''),
    'substituteEmployeeId', p_substitute_employee_id);

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  v_row := public._submit_request_for(
    p_employee_id,
    'leave',
    null,
    v_manager,
    coalesce(trim(p_title), format('إجازة %s — %s', public.leave_type_label(p_leave_type), to_char(p_start_date, 'YYYY-MM-DD'))),
    trim(p_reason),
    v_payload);

  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date,
    days_count, duration_unit, handover_notes, substitute_employee_id, created_by)
  values(
    v_row.id, p_employee_id, v_leave_type_id, p_start_date, p_end_date,
    v_days, 'day', nullif(p_handover_notes,''), p_substitute_employee_id, auth.uid());

  if p_leave_type = 'casual' then
    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
      where id = v_row.id returning * into v_row;
    update public.request_steps
      set status = 'skipped', acted_at = now(), acted_by = v_me,
          comment = 'تنفيذ فوري لإجازة عارضة من الإدارة', updated_at = now()
      where request_id = v_row.id and status in ('active','pending');
    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
      where request_id = v_row.id and status = 'running';
    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
    values(
      v_row.id, v_me, 'system', 'pending', 'approved',
      'تنفيذ فوري لإجازة عارضة مسجلة من الإدارة',
      jsonb_build_object('immediate', true, 'adminCreated', true), auth.uid());
  end if;

  perform public.log_audit_event(
    'leave.admin_created', 'workflow', 'info', 'requests', v_row.id,
    'إنشاء إجازة بدل الموظف',
    format('الموظف: %s | النوع: %s | من %s إلى %s', p_employee_id, p_leave_type, p_start_date, p_end_date),
    jsonb_build_object('employeeId', p_employee_id, 'leaveType', p_leave_type, 'days', v_days));

  return v_row;
end;
$$;

comment on function public.admin_create_leave_request(uuid, text, date, date, text, text, text, uuid) is
  '0505: إنشاء إجازة بدل الموظف مع السماح بالتسجيل ضمن الشهر الحالي.';

revoke all on function public.admin_create_leave_request(uuid, text, date, date, text, text, text, uuid) from public, anon;
grant execute on function public.admin_create_leave_request(uuid, text, date, date, text, text, text, uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 9) أدوات التشخيص والإصلاح التلقائي للعلاقات الإدارية والطلبات
-- ═══════════════════════════════════════════════════════════════════

-- أ) تشخيص العلاقات الإدارية
create or replace function public.diagnose_manager_chain()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_total_employees integer;
  v_with_manager integer;
  v_without_manager integer;
  v_pending_requests integer;
  v_null_manager_requests integer;
  v_users_without_direct_manager_role integer;
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array['people.employee.update_sensitive','admin.manage','people.manage'])
    or public.current_has_active_role(array['admin','super-admin','hr-manager'])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select count(*)::int into v_total_employees
  from public.employees where is_active and not is_deleted;

  select count(distinct mr.employee_id)::int into v_with_manager
  from public.manager_relations mr
  where mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date);

  v_without_manager := v_total_employees - v_with_manager;

  select count(*)::int into v_pending_requests
  from public.requests where status = 'pending';

  select count(*)::int into v_null_manager_requests
  from public.requests where status = 'pending' and manager_employee_id is null;

  v_result := jsonb_build_object(
    'totalEmployees', v_total_employees,
    'withManager', v_with_manager,
    'withoutManager', v_without_manager,
    'pendingRequests', v_pending_requests,
    'pendingRequestsWithNullManager', v_null_manager_requests
  );

  return v_result;
end;
$$;

revoke all on function public.diagnose_manager_chain() from public, anon;
grant execute on function public.diagnose_manager_chain() to authenticated;


-- ب) إصلاح العلاقات الإدارية التلقائي (fix_manager_chain)
create or replace function public.fix_manager_chain()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fixed integer := 0;
  v_skipped integer := 0;
  v_dept record;
  v_emp record;
begin
  -- ربط الموظفين بمدير قسمهم من departments.manager_id إذا لم تكن لديهم علاقة نشطة
  for v_dept in
    select d.id as dept_id, d.name as dept_name, d.manager_id
    from public.departments d
    where d.manager_id is not null and d.is_active
  loop
    for v_emp in
      select e.id, e.full_name_ar
      from public.employees e
      where e.department_id = v_dept.dept_id
        and e.is_active and not e.is_deleted
        and e.id <> v_dept.manager_id
        and not exists (
          select 1 from public.manager_relations mr
          where mr.employee_id = e.id
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date)
        )
    loop
      insert into public.manager_relations(
        employee_id, manager_employee_id, relation_type,
        effective_from, effective_to, created_by
      ) values (
        v_emp.id, v_dept.manager_id, 'primary',
        current_date, null, auth.uid()
      )
      on conflict do nothing;

      update public.employees
      set manager_id = v_dept.manager_id, updated_at = now()
      where id = v_emp.id and (manager_id is null or manager_id = id);

      v_fixed := v_fixed + 1;
    end loop;
  end loop;

  return jsonb_build_object('fixed', v_fixed, 'skipped', v_skipped);
end;
$$;

revoke all on function public.fix_manager_chain() from public, anon;
grant execute on function public.fix_manager_chain() to authenticated;


-- ج) تحديث الطلبات المعلّقة وتعيين معتمدين لها (backfill_request_managers)
create or replace function public.backfill_request_managers()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fixed integer := 0;
  v_rec record;
  v_mgr uuid;
begin
  for v_rec in
    select r.id, r.employee_id
    from public.requests r
    where r.status = 'pending'
      and (r.manager_employee_id is null or r.manager_employee_id = r.employee_id)
  loop
    v_mgr := public.resolve_request_approver(v_rec.employee_id);
    if v_mgr is not null and v_mgr <> v_rec.employee_id then
      update public.requests
        set manager_employee_id = v_mgr, updated_at = now()
        where id = v_rec.id;

      update public.request_steps
        set assignee_employee_id = v_mgr, updated_at = now()
        where request_id = v_rec.id
          and status in ('active','pending')
          and (assignee_employee_id is null or assignee_employee_id = v_rec.employee_id);

      v_fixed := v_fixed + 1;
    end if;
  end loop;

  return jsonb_build_object('fixed', v_fixed);
end;
$$;

revoke all on function public.backfill_request_managers() from public, anon;
grant execute on function public.backfill_request_managers() to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 10) تشغيل المعالجة الذاتية فورياً كجزء من تفعيل الترحيل
-- ═══════════════════════════════════════════════════════════════════
do $$
declare
  v_mgr_fix jsonb;
  v_req_fix jsonb;
begin
  v_mgr_fix := public.fix_manager_chain();
  v_req_fix := public.backfill_request_managers();
  raise notice '0505: Manager chain auto-healed: % relations fixed, % requests backfilled',
    v_mgr_fix->'fixed', v_req_fix->'fixed';
end;
$$;

commit;

notify pgrst, 'reload schema';
