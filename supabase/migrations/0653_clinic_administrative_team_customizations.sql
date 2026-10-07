-- =====================================================================
-- 0653: تخصيصات وتعديلات هاتف التيم الإداري بالعيادات الطبية
-- =====================================================================
-- متطلبات السياسة الخاصة بالتيم الإداري بالعيادات (تحت إشراف مصطفى أحمد):
--   1) حصر مسار اعتمادات طلباتهم (إجازات، أذونات، تصحيح بصمة، أي طلبات) بمديرهم
--      المباشر مصطفى أحمد فقط، ومنع أي تصعيد تلقائي بعد ساعتين لمدير التشغيل (أبو عمار).
--   2) حصر أنواع الطلبات الذاتية: حجب المأموريات والقوافل والفاندي عنهم.
--   3) استمرار حجب التقارير اليومية ولوحة الشرف وصفحة القرارات والتعاميم.
--   4) ضبط طلبات المواقع: طلبات المدير التنفيذي لا تصل للموظفين بل لمديرهم مصطفى أحمد،
--      وأي طلب موقع مباشر لموظفي العيادات يصدر حصراً من مديرهم المباشر مصطفى أحمد
--      ويصلهم للموافقة والاستجابة.
--   5) فترات العمل الخاصة بالعيادات: فترة صباحية (10:00 ص – 6:00 م) وفترة مسائية (3:00 ع – 11:00 م).
-- =====================================================================

begin;

-- ─── 0) دالة مركزية لتحديد أعضاء طاقم العيادات ──────────────────────────────
create or replace function public.is_clinic_team_member(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where e.id = p_employee_id
      and (
        public.is_clinic_staff_exempt(e.id)
        or public.is_employee_isolated(e.id)
        or coalesce(d.is_isolated, false) = true
        or coalesce(d.code, '') in ('MED-ADMIN', 'CLINICS')
        or coalesce(d.name, '') like '%عياد%'
        or exists (
          select 1 from public.manager_relations mr
          where mr.employee_id = e.id
            and mr.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
            and mr.effective_from <= now()
            and (mr.effective_to is null or mr.effective_to >= now())
        )
        or e.id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
      )
  );
$$;

comment on function public.is_clinic_team_member(uuid) is
  '0653: فحص ما إذا كان الموظف يتبع طاقم العيادات أو تحت إدارة مصطفى أحمد.';

-- ─── 1) حل معتمد الطلبات: لموظفي العيادات -> مصطفى أحمد حصراً ──────────────
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

  -- ★ طاقم العيادات (الموظفون): معتمدهم المباشر دائماً مصطفى أحمد كمال الدين ★
  if public.is_clinic_team_member(p_employee_id)
     and p_employee_id <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c' then
    return '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid;
  end if;

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

  -- 6) المدير العام أو التنفيذي
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

  return v_mgr;
end;
$$;

-- ─── 2) تعريف مسارات العمل الخاصة بالعيادات (خطوة واحدة فقط بلا تصعيد) ───────
insert into public.workflow_definitions (code, name_ar, description, request_type, version, is_active, is_default, auto_escalate, default_due_hours)
values
  ('medical_leave_v1', 'اعتماد إجازات العيادات', 'مسار إجازات العيادات: مصطفى أحمد حصراً بلا تصعيد للأوبريشن', 'leave', 1, true, false, false, 48),
  ('medical_late_permit_v1', 'اعتماد إذن تأخير العيادات', 'مسار أذونات العيادات: مصطفى أحمد حصراً بلا تصعيد', 'late_permit', 1, true, false, false, 48),
  ('medical_early_permit_v1', 'اعتماد إذن انصراف العيادات', 'مسار أذونات العيادات: مصطفى أحمد حصراً بلا تصعيد', 'early_permit', 1, true, false, false, 48),
  ('medical_att_permit_v1', 'اعتماد إذن حضور العيادات', 'مسار أذونات العيادات: مصطفى أحمد حصراً بلا تصعيد', 'attendance_permit', 1, true, false, false, 48),
  ('medical_correction_v1', 'اعتماد تصحيح بصمة العيادات', 'مسار تصحيح بصمة العيادات: مصطفى أحمد حصراً بلا تصعيد', 'attendance_correction', 1, true, false, false, 48),
  ('medical_shift_change_v1', 'اعتماد تغيير وردية العيادات', 'مسار تغيير وردية العيادات: مصطفى أحمد حصراً بلا تصعيد', 'shift_change', 1, true, false, false, 48),
  ('medical_generic_v1', 'اعتماد طلبات العيادات العامة', 'مسار طلبات العيادات العامة: مصطفى أحمد حصراً بلا تصعيد', 'generic', 1, true, false, false, 48)
on conflict (code, version) do update set
  name_ar = excluded.name_ar,
  description = excluded.description,
  request_type = excluded.request_type,
  is_active = true,
  auto_escalate = false,
  default_due_hours = 48,
  updated_at = now();

-- خطوات سير العمل الموحدة: خطوة واحدة للمدير المباشر
insert into public.workflow_steps (definition_id, step_order, name_ar, step_type, approver_type, approver_employee_id, sla_hours)
select d.id, 1, 'مدير العيادات الطبية (مصطفى أحمد)', 'approval', 'specific_employee', '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 48
from public.workflow_definitions d
where d.code in (
  'medical_leave_v1', 'medical_late_permit_v1', 'medical_early_permit_v1',
  'medical_att_permit_v1', 'medical_correction_v1', 'medical_shift_change_v1', 'medical_generic_v1'
)
and not exists (
  select 1 from public.workflow_steps ws where ws.definition_id = d.id
);

-- ─── 3) تحديث _submit_request_for لاستخدام مسارات العيادات المعزولة ─────────
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
  v_is_clinic      boolean := false;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  v_is_clinic := public.is_clinic_team_member(p_employee_id) and p_employee_id <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';

  -- لموظفي العيادات: المدير المباشر هو مصطفى أحمد حصراً
  if v_is_clinic then
    p_manager_employee_id := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
      -- مسارات العيادات الطبية المحصورة
      select * into v_def from public.workflow_definitions
        where code like 'medical_%' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null and public.is_employee_isolated(p_employee_id) then
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
    -- طاقم العيادات لا يخضع للتصعيد التلقائي إطلاقاً
    if v_def.auto_escalate and not v_is_clinic then
      v_esc := v_due;
    else
      v_esc := null;
    end if;
  else
    v_due := now() + interval '48 hours';
    v_esc := null;
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
      case when ws.step_order = 1 and ws.escalate_after_hours is not null and not v_is_clinic
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

    select assignee_employee_id into v_first_approver
    from public.request_steps
    where request_id = v_row.id and step_order = 1;

    update public.requests
      set current_step_id = (select id from public.request_steps where request_id = v_row.id and step_order = 1 limit 1),
          workflow_status = 'in_progress',
          updated_at = now()
    where id = v_row.id;
  end if;

  -- إشعار المدير المعتمد
  v_label := case p_request_type
    when 'leave' then 'إجازة'
    when 'mission' then 'مأمورية'
    when 'convoy' then 'قافلة'
    when 'fundraising' then 'فاندي ترفيهي'
    when 'late_permit' then 'إذن تأخير'
    when 'early_permit' then 'إذن انصراف'
    when 'attendance_permit' then 'إذن حضور'
    when 'attendance_correction' then 'تصحيح حضور'
    when 'shift_change' then 'تغيير وردية'
    else 'طلب'
  end;

  if p_manager_employee_id is not null then
    perform public.notify_employee(
      p_manager_employee_id,
      'طلب ' || v_label || ' جديد بانتظار قرارك',
      'قدّم ' || coalesce((select full_name_ar from public.employees where id = p_employee_id), 'الموظف')
        || ' طلب ' || v_label || ' جديد: ' || coalesce(p_title, ''),
      'request', 'high', 'request', v_row.id,
      jsonb_build_object('deepLink', '/requests/' || v_row.id)
    );
  end if;

  return v_row;
end;
$$;

-- ─── 4) حماية SLA من تصعيد طلبات العيادات إلى مدير التشغيل (أبو عمار) ────────
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_target   uuid;
  v_role     text;
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
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop

    -- ── ★ استثناء طاقم العيادات: يبقى كل شيء بالعيادات حصراً لدى مصطفى أحمد ★ ──
    -- لا يتم رفع الأمر لمدير التشغيل (أبو عمار) بعد ساعتين كما في باقي السيستم
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then

      -- إرسال تذكير دوري لمدير العيادات مصطفى أحمد فقط، وإعادة جدولة المهلة 24 ساعة
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
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = now() + interval '24 hours',
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
        'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      if v_next.status is distinct from 'active' then
        perform public.notify_executive_fullscreen(
          'تصعيد طلب — للمتابعة',
          coalesce(v_row.title, ''),
          'request',
          'request', v_row.request_id,
          '/requests/' || v_row.request_id,
          jsonb_build_object(
            'escalation', 'executive_notify',
            'tier', v_next.step_order
          )
        );
      end if;
    else
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;
exception
  when others then
    insert into public.cron_health_log(job_name, rows_affected, status, detail)
    values ('process_request_sla', 0, 'error', sqlerrm);
    raise;
end;
$$;

revoke all on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

-- ─── 5) حجب المأموريات والقوافل والفاندي عن تقديم طاقم العيادات ذاتياً ───────
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
  v_me                    uuid := public.current_employee_id();
  v_manager               uuid;
  v_row                   public.requests;
  v_payload               jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start           date := date_trunc('month', v_today)::date;
  v_day_mark              boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date            date;
  v_end_date              date;
  v_permit_date           date;
  v_minutes               integer;
  v_leave_type            text;
  v_leave_type_id         uuid;
  v_affects               boolean;
  v_days                  numeric;
  v_substitute            uuid;
  v_correction_date       date;
  v_correction_type       text;
  v_corrected_time        text;
  v_permit_kind           text;
  v_geofence_id           uuid;
  v_has_prior_office_punch boolean := false;
  v_is_clinic             boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_is_clinic := public.is_clinic_team_member(v_me) and v_me <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';

  -- ★ حظر المأموريات والقوافل والفاندي على طاقم العيادات ★
  if v_is_clinic and p_request_type in ('mission', 'convoy', 'fundraising') then
    raise exception 'طلبات المأموريات والقوافل والأنشطة الميدانية غير متاحة لطاقم العيادات' using errcode = '22023';
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
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'العنوان وسبب الطلب مطلوبان (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'تعديل حالة اليوم يتطلب تاريخاً صالحاً' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'تعديل حالة اليوم يكون ليوم واحد فقط' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'تعديل حالة اليوم متاح فقط خلال أيام الشهر الحالي' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'لا يمكن تعديل حالة الأيام المستقبلية' using errcode = '22023';
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
        if v_leave_type = 'unpaid' then
          raise exception 'لا يمكن للموظف طلب إجازة بدون راتب ذاتياً؛ تُمنح فقط بقرار من إدارة الموارد البشرية' using errcode = '22023';
        end if;
        if v_leave_type not in ('annual','casual','sick','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم: %', v_leave_type using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية الإجازة مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية الإجازة يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم إجازة عن أشهر سابقة' using errcode = '22023';
        end if;

        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'نوع الإجازة غير نشط أو غير معروف: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual' and v_start_date >= v_today));

      -- ─── مأمورية ───────────────────────────────────────────────────────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم مأمورية عن أشهر سابقة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل خارجية'),
          'days', 1,
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', case when v_day_mark then false else true end);

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
        if v_start_date < v_month_start then
          raise exception 'لا يمكن تقديم تكليف عن أشهر سابقة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(
            nullif(trim(coalesce(v_payload->>'location', '')), ''),
            case when p_request_type = 'convoy' then 'قافلة ميدانية' else 'فعالية فاندي' end
          ),
          'days', ((v_end_date - v_start_date) + 1));

      -- ─── إذن تأخير صباحي ──────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن التأخير بأثر رجعي غير مسموح' using errcode = '22023';
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
          raise exception 'إذن الانصراف بأثر رجعي غير مسموح' using errcode = '22023';
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
          raise exception 'الوقت المصحح يجب أن يكون بصيغة HH:MM' using errcode = '22023';
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

    if v_leave_type = 'casual' and v_start_date >= v_today then
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

  -- ── 0643: بدء المأمورية فور طلبها لليوم الحالي ──
  if p_request_type in ('mission', 'convoy', 'fundraising') and not v_day_mark and v_start_date = v_today then
    insert into public.mission_executions(
      request_id, employee_id, status, started_at
    ) values (
      v_row.id, v_me, 'in_progress', coalesce(v_row.created_at, now())
    ) on conflict (request_id) do update
      set status = 'in_progress',
          started_at = coalesce(public.mission_executions.started_at, v_row.created_at, now()),
          updated_at = now();

    select exists (
      select 1 from public.attendance_events ae
       where ae.employee_id = v_me
         and (ae.event_at at time zone 'Africa/Cairo')::date = v_today
         and ae.event_type = 'CHECK_IN'
         and ae.status in ('accepted', 'adjusted')
         and ae.source not in ('mission_auto')
         and ae.event_at < coalesce(v_row.created_at, now())
    ) into v_has_prior_office_punch;

    if not v_has_prior_office_punch then
      insert into public.attendance_daily (
        employee_id, work_date, status, first_check_in, late_minutes, updated_at
      ) values (
        v_me, v_today, 'present', coalesce(v_row.created_at, now()), 0, now()
      ) on conflict (employee_id, work_date) do update
        set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            status = 'present',
            late_minutes = 0,
            updated_at = now();

      update public.attendance_events
         set late_minutes = 0
       where employee_id = v_me
         and (event_at at time zone 'Africa/Cairo')::date = v_today;

      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: بدء مأمورية عمل من بداية اليوم',
             updated_at = now()
        where employee_id = v_me
          and work_date = v_today
          and status in ('pending_payment', 'doubled');
    else
      update public.attendance_daily
         set updated_at = now()
       where employee_id = v_me
         and work_date = v_today;
    end if;

    if not exists (
      select 1 from public.attendance_events
       where employee_id = v_me
         and (event_at at time zone 'Africa/Cairo')::date = v_today
         and event_type = 'CHECK_IN'
         and status in ('accepted', 'adjusted')
    ) then
      select id into v_geofence_id
        from public.geofences where is_active = true
        order by created_at limit 1;

      insert into public.attendance_events (
        employee_id, geofence_id, event_type, event_at, status,
        requires_review, verification_status, server_verified,
        is_mock_location, source, notes, late_minutes
      ) values (
        v_me, v_geofence_id, 'CHECK_IN', coalesce(v_row.created_at, now()), 'adjusted',
        true, 'server_verified', true,
        false, 'mission_auto', 'auto_check_in_from_mission_creation', 0
      );
    end if;
  end if;

  return v_row;
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ─── 6) ضبط طلبات المواقع الخاصة بالعيادات ومصطفى أحمد ───────────────────────
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot'::text,
  p_reason text default ''::text
)
returns public.live_location_requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
  v_deep_link text;
  v_target_emp_id uuid := p_employee_id;
  v_orig_emp_name text;
  v_clinic_mgr_emp_id uuid := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'; -- مصطفى أحمد كمال الدين
  v_is_clinic_redirect boolean := false;
  v_is_clinic_direct_from_mgr boolean := false;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode='42501';
  end if;

  -- الصلاحية: المدير التنفيذي، أو مصطفى أحمد لطلب موقع أفراد طاقم العيادات
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['executive', 'executive-director'])
    or (v_me = v_clinic_mgr_emp_id and public.is_clinic_team_member(p_employee_id))
    or (public.current_has_active_role(array['clinics-manager']) and public.is_clinic_team_member(p_employee_id))
  ) then
    raise exception 'only executive director or clinics manager may request employee location' using errcode='42501';
  end if;

  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode='22023';
  end if;

  -- استبعاد المدير التنفيذي كهدف
  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  -- ★ توجيه طلبات المواقع الخاصة بالعيادات:
  -- أ) إذا كان الطالب هو مدير العيادات مصطفى أحمد نفسه: الطلب يصل للموظف مباشرة.
  -- ب) إذا كان الطالب هو المدير التنفيذي: لا يصل للموظفة بل يتحول لمديرها مصطفى أحمد للتحقق.
  if public.is_clinic_team_member(p_employee_id) and p_employee_id <> v_clinic_mgr_emp_id then
    if v_me = v_clinic_mgr_emp_id or public.current_has_active_role(array['clinics-manager']) then
      v_target_emp_id := p_employee_id;
      v_is_clinic_direct_from_mgr := true;
    else
      select full_name_ar into v_orig_emp_name from public.employees where id = p_employee_id;
      v_target_emp_id := v_clinic_mgr_emp_id;
      v_is_clinic_redirect := true;
      p_reason := 'طلب موقع لموظفة العيادات (' || coalesce(v_orig_emp_name, 'موظفة') || ') — مرسل مباشرة للمدير مصطفى أحمد للمتابعة والتحقق' ||
                  case when nullif(trim(p_reason), '') is not null then ' | سبب إضافي: ' || trim(p_reason) else '' end;
    end if;
  end if;

  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees
    where id = v_target_emp_id and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;

  -- مهلة 30 ثانية
  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = v_target_emp_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_target_emp_id, v_me, coalesce(nullif(trim(p_reason), ''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V18',
      'isClinicRedirect', v_is_clinic_redirect,
      'isClinicDirectFromManager', v_is_clinic_direct_from_mgr,
      'originalTargetEmployeeId', p_employee_id::text
    ),
    auth.uid()
  )
  returning * into v_req;

  update public.live_location_requests
     set metadata = metadata || jsonb_build_object('requestId', v_req.id)
   where id = v_req.id
  returning * into v_req;

  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = v_target_emp_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by
    ) values (
      v_target_user, v_target_emp_id,
      case
        when v_is_clinic_direct_from_mgr then 'طلب موقع من مديرك المباشر مصطفى أحمد'
        when v_is_clinic_redirect then 'طلب موقع عاجل (طاقم العيادات)'
        else 'طلب موقع عاجل'
      end,
      case
        when v_is_clinic_direct_from_mgr
          then 'طلب موقع مرسل من مديرك المباشر مصطفى أحمد للمتابعة والتحقق. يرجى الضغط للموافقة.'
        when v_is_clinic_redirect
          then 'طلب موقع يخص موظفة بالعيادات (' || coalesce(v_orig_emp_name, '') || ') — محول إليك كمسؤول للعيادات للموافقة الفورية.'
        else 'اجتمع التنفيذ لمعرفة موقعك فوراً. يرجى الضغط للموافقة.'
      end,
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id,
      jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v7',
        'deepLink', v_deep_link
      ),
      auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'طلب موقع حي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', v_target_emp_id, 'requestId', v_req.id, 'originalTargetEmployeeId', p_employee_id)
  );

  return v_req;
end;
$function$;

-- ─── 7) إضافة وردية العيادات المسائية (3 عصراً – 11 مساءً) ─────────────────
insert into public.shifts (code, name, name_en, start_time, end_time, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
values
  ('SHIFT_CLINIC_3_11', 'فترة العيادات المسائية (3 ع – 11 م)', 'Clinics Evening (15:00–23:00)', '15:00:00', '23:00:00', 0, 15, 0, true)
on conflict (code) do update set
  name = excluded.name,
  name_en = excluded.name_en,
  start_time = excluded.start_time,
  end_time = excluded.end_time,
  grace_in_minutes = excluded.grace_in_minutes,
  is_active = true,
  updated_at = now();

-- ─── 8) تحديث get_my_work_shift_info ليعرض فترات عمل العيادات الخاصة ───────
create or replace function public.get_my_work_shift_info()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_today         date := (now() at time zone 'Africa/Cairo')::date;
  v_assign        record;
  v_default_shift record;
  v_current_shift jsonb;
  v_available     jsonb;
  v_pending       jsonb := null;
  v_req           record;
  v_today_permit  record;
  v_permit_obj    jsonb := null;
  v_shift_start   time;
  v_shift_end     time;
  v_shift_grace   integer := 15;
  v_eff_start     time;
  v_eff_grace_end time;
  v_eff_end       time;
  v_has_permit    boolean := false;
  v_is_clinic     boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_is_clinic := public.is_clinic_team_member(v_me);

  -- 1) فحص الوردية المعتمدة المسندة حالياً للموظف
  select sa.id as assignment_id, sa.effective_from, sa.notes,
         s.id as shift_id, s.code, s.name, s.name_en, s.start_time, s.end_time,
         coalesce(s.grace_in_minutes, 15) as grace_in_minutes
    into v_assign
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
   where sa.employee_id = v_me
     and sa.is_active = true
     and sa.effective_from <= v_today
     and (sa.effective_to is null or sa.effective_to >= v_today)
   order by sa.effective_from desc
   limit 1;

  if v_assign.shift_id is not null then
    v_shift_start := coalesce(v_assign.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_assign.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_assign.grace_in_minutes, 15);
  else
    -- الدوام الأساسي الافتراضي العام (10 ص – 6 م)
    select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
           coalesce(s.grace_in_minutes, 15) as grace_in_minutes
      into v_default_shift
      from public.shifts s
     where s.code = 'OFFICIAL' and s.is_active
     limit 1;

    if v_default_shift.id is null then
      select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
             coalesce(s.grace_in_minutes, 15) as grace_in_minutes
        into v_default_shift
        from public.shifts s
       where s.id = public.default_shift_id();
    end if;

    v_shift_start := coalesce(v_default_shift.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_default_shift.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_default_shift.grace_in_minutes, 15);
  end if;

  -- 2) فحص أي إذن معتمد لليوم
  select r.id, r.request_type, r.title, r.status, r.payload,
         coalesce(
           (r.payload->>'minutes')::integer,
           (r.payload->>'duration')::integer,
           ((r.payload->>'hours')::numeric * 60)::integer,
           120
         ) as permit_minutes,
         coalesce(r.payload->>'permitKind',
                  case when r.request_type = 'early_permit' then 'early_departure' else 'late_arrival' end) as permit_kind
    into v_today_permit
    from public.requests r
   where r.employee_id = v_me
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = v_today
   order by r.created_at desc
   limit 1;

  v_eff_start := v_shift_start;
  v_eff_grace_end := (v_shift_start + (v_shift_grace || ' minutes')::interval)::time;
  v_eff_end := v_shift_end;

  if v_today_permit.id is not null then
    v_has_permit := true;
    if v_today_permit.permit_kind = 'late_arrival' then
      v_eff_start := (v_shift_start + (v_today_permit.permit_minutes || ' minutes')::interval)::time;
      v_eff_grace_end := (v_eff_start + (v_shift_grace || ' minutes')::interval)::time;
    elsif v_today_permit.permit_kind = 'early_departure' then
      v_eff_end := (v_shift_end - (v_today_permit.permit_minutes || ' minutes')::interval)::time;
    end if;

    v_permit_obj := jsonb_build_object(
      'id', v_today_permit.id,
      'requestType', v_today_permit.request_type,
      'title', coalesce(v_today_permit.title, 'إذن معتمد'),
      'permitMinutes', v_today_permit.permit_minutes,
      'permitKind', v_today_permit.permit_kind,
      'status', v_today_permit.status,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- بناء كائن الوردية الحالية
  if v_assign.shift_id is not null then
    v_current_shift := jsonb_build_object(
      'id', v_assign.shift_id,
      'code', v_assign.code,
      'name', v_assign.name,
      'nameEn', v_assign.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', true,
      'assignmentId', v_assign.assignment_id,
      'effectiveFrom', v_assign.effective_from,
      'status', 'approved',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  else
    v_current_shift := jsonb_build_object(
      'id', v_default_shift.id,
      'code', coalesce(v_default_shift.code, 'OFFICIAL'),
      'name', coalesce(v_default_shift.name, 'الدوام الأساسي (10 ص – 6 م)'),
      'nameEn', v_default_shift.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', false,
      'assignmentId', null,
      'effectiveFrom', v_today,
      'status', 'default',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- 3) قائمة الورديات المرنة المتاحة للاختيار
  if v_is_clinic then
    -- لطاقم العيادات: ورديتان فقط (10 ص – 6 م) و (3 ع – 11 م)
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'OFFICIAL' then 'فترة صباحية تبدأ 10:00 ص (سماح حتى 10:15 ص) وتنتهي 6:00 م'
                 when 'SHIFT_CLINIC_3_11' then 'فترة مسائية تبدأ 3:00 عصراً (سماح حتى 3:15 ع) وتنتهي 11:00 م'
                 else 'فترة عمل معتمدة للعيادات'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('OFFICIAL', 'SHIFT_CLINIC_3_11');
  else
    -- لباقي الموظفين
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'SHIFT_9_5' then 'فترة صباحية تبدأ 9:00 ص (سماح حتى 9:15 ص) وتنتهي 5:00 م'
                 when 'OFFICIAL' then 'الدوام الأساسي العام يبدأ 10:00 ص (سماح حتى 10:15 ص) وينتهي 6:00 م'
                 when 'SHIFT_11_7' then 'فترة مسائية تبدأ 11:00 ص (سماح حتى 11:15 ص) وتنتهي 7:00 م'
                 else 'فترة عمل معتمدة'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7');
  end if;

  -- 4) فحص أي طلب معلق لتغيير فترة العمل
  select r.id, r.title, r.reason, r.created_at, r.status,
         r.payload->>'shiftId' as requested_shift_id,
         r.payload->>'shiftName' as requested_shift_name
    into v_req
    from public.requests r
   where r.employee_id = v_me
     and r.request_type = 'shift_change'
     and r.status = 'pending'
   order by r.created_at desc
   limit 1;

  if v_req.id is not null then
    v_pending := jsonb_build_object(
      'requestId', v_req.id,
      'title', v_req.title,
      'reason', v_req.reason,
      'requestedShiftId', v_req.requested_shift_id,
      'requestedShiftName', v_req.requested_shift_name,
      'createdAt', v_req.created_at,
      'status', v_req.status
    );
  end if;

  return jsonb_build_object(
    'currentShift', v_current_shift,
    'availableShifts', v_available,
    'pendingRequest', v_pending,
    'todayPermit', v_permit_obj
  );
end;
$$;

revoke all on function public.get_my_work_shift_info() from public, anon;
grant execute on function public.get_my_work_shift_info() to authenticated;

-- ─── 9) تحديث مطابقة الوردية المرنة لدعم وردية العيادات (3 عصراً) ────────────
create or replace function public.match_flexible_shift(p_check_in timestamptz)
returns uuid
language plpgsql
stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_time time;
  v_shift_code text;
  v_shift_id uuid;
begin
  if p_check_in is null then
    return public.default_shift_id();
  end if;

  v_time := (p_check_in at time zone 'Africa/Cairo')::time;

  -- مطابقة نافذة الحضور:
  -- 1) حضور بعد 13:30 (1:30 ظهراً) -> الوردية المسائية للعيادات (3 ع – 11 م)
  -- 2) حضور حتى 09:15 ص -> الوردية الصباحية (9 ص – 5 م)
  -- 3) حضور بين 09:15 ص و 13:30 -> الدوام الأساسي (10 ص – 6 م)
  if v_time >= '13:30:00'::time and exists (select 1 from public.shifts where code = 'SHIFT_CLINIC_3_11' and is_active) then
    v_shift_code := 'SHIFT_CLINIC_3_11';
  elsif v_time <= '09:15:00'::time then
    v_shift_code := 'SHIFT_9_5';
  else
    v_shift_code := 'OFFICIAL';
  end if;

  select id into v_shift_id
  from public.shifts
  where code = v_shift_code and is_active
  limit 1;

  return coalesce(v_shift_id, public.default_shift_id());
end;
$fn$;

-- ─── 10) تحديث get_employee_home و get_my_access_context ───────────────────
create or replace function public.get_employee_home()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
  v_is_clinic boolean := false;
begin
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'pendingRequests', 0,
      'activeTasks', 0,
      'kpiStage', null,
      'unreadNotifications', (select count(*) from public.notifications
        where recipient_user_id = auth.uid() and is_read = false),
      'unreadOfficial', 0,
      'pendingLocationRequests', 0,
      'lastUpdatedAt', now()
    );
  end if;

  v_is_clinic := public.is_clinic_team_member(v_me);

  return jsonb_build_object(
    'pendingRequests', (select count(*) from public.requests
      where employee_id = v_me and status = 'pending'),
    'activeTasks', (select count(*) from public.tasks
      where assignee_employee_id = v_me
        and status not in ('done', 'cancelled')),
    'kpiStage', (select current_stage from public.kpi_evaluations
      where employee_id = v_me order by created_at desc limit 1),
    'unreadNotifications', (select count(*) from public.notifications
      where recipient_user_id = auth.uid() and is_read = false),
    -- حجب القرارات الإدارية عن طاقم العيادات
    'unreadOfficial', case when v_is_clinic then 0 else (
      select count(*) from public.decision_recipients dr
      join public.administrative_decisions d on d.id = dr.decision_id
      left join public.decision_reads rr on rr.decision_id = d.id
        and rr.employee_id = dr.employee_id
      where dr.employee_id = v_me
        and d.status = 'published'
        and rr.id is null
    ) end,
    -- طلبات الموقع للموظف (تشمل طلبات مصطفى أحمد الموجهة لموظفي العيادات)
    'pendingLocationRequests', (
      select count(*) from public.live_location_requests
      where employee_id = v_me
        and status = 'pending'
        and expires_at > now()
    ),
    'lastUpdatedAt', now()
  );
end;
$function$;

create or replace function public.get_my_access_context()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_profile_status text;
  v_employee_status text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
  v_is_clinic_staff boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar,'مستخدم النظام'), e.employee_code, e.photo_url, p.status, e.status
    into v_employee_id, v_display_name, v_employee_code, v_photo_url, v_profile_status, v_employee_status
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id;

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  if v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_employee_code in ('+201154869616','01154869616')
     or exists (select 1 from public.employees e where e.id = v_employee_id and (e.phone_e164 in ('+201154869616','01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  end if;

  if not v_is_immune_admin and (coalesce(v_profile_status,'')='suspended' or coalesce(v_employee_status,'')='suspended') then
    v_is_suspended := true;
    select p.current_amount into v_suspension_amount
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id and p.status = 'suspended'
    order by p.created_at desc limit 1;
    if found then
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := coalesce(v_suspension_amount,500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    else
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    end if;
    return jsonb_build_object(
      'userId', v_user_id, 'employeeId', v_employee_id, 'displayName', v_display_name,
      'employeeCode', v_employee_code, 'photoUrl', v_photo_url,
      'roles', '[]'::jsonb, 'permissions', '[]'::jsonb, 'workspaces', '[]'::jsonb,
      'defaultWorkspace', 'employee', 'isSuspended', true,
      'suspensionReason', v_suspension_reason, 'suspensionMessage', v_suspension_message,
      'suspensionAmount', v_suspension_amount,
      'isClinicStaff', false,
      'attendancePolicy', jsonb_build_object('attendanceRequired',false,'selfPunchEnabled',false,'liveLocationResponseEnabled',false)
    );
  end if;

  if v_profile_status not in ('active','pending') then
    raise exception 'حساب المستخدم غير نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access() or v_is_immune_admin;
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now()) and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director','executive']::text[];
  v_is_operations := v_roles && array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']::text[];
  v_is_manager := v_is_operations or v_roles && array['direct-manager','department-manager','branch-manager','clinics-manager']::text[];
  if not v_is_manager and v_employee_id is not null then
    if exists (select 1 from public.departments d where d.manager_id = v_employee_id) or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_employee_id and mr.relation_type='primary'
        and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())
    ) then
      v_is_manager := true;
    end if;
  end if;

  v_is_hr := v_roles && array['hr-manager','hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_is_immune_admin or v_roles && array['admin','super-admin','super_admin','system-admin','technical-lead','executive-secretary']::text[];
  v_is_committee := v_roles && array['committee-member','committee-chair','committee-secretary']::text[];

  -- فحص طاقم العيادات (الموظفون غير المديرين)
  if v_employee_id is not null then
    v_is_clinic_staff := public.is_clinic_team_member(v_employee_id)
                         and v_employee_id <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';
  end if;

  if v_employee_id is not null and not v_is_executive then v_workspaces := array_append(v_workspaces,'employee'); end if;
  if v_is_manager and not v_is_executive then v_workspaces := array_append(v_workspaces,'manager'); end if;
  if v_is_operations and not v_is_executive then v_workspaces := array_append(v_workspaces,'field_operations'); end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces,'executive'); end if;
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces,'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces,'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then v_workspaces := array_append(v_workspaces,'committee'); end if;

  if v_is_main_admin then v_default_workspace := 'main_admin';
  elsif v_is_executive then v_default_workspace := 'executive';
  elsif v_is_hr then v_default_workspace := 'hr';
  elsif v_is_operations then v_default_workspace := 'field_operations';
  elsif v_is_manager then v_default_workspace := 'manager';
  elsif v_employee_id is not null then v_default_workspace := 'employee';
  else raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'isSuspended', false,
    'suspensionReason', null,
    'suspensionMessage', null,
    'suspensionAmount', null,
    'isClinicStaff', v_is_clinic_staff,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null,
      'selfPunchEnabled', true,
      -- تمكين استجابة طاقم العيادات لطلبات الموقع الصادرة من مديرهم المباشر مصطفى أحمد
      'liveLocationResponseEnabled', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null
    )
  );
end;
$function$;

notify pgrst, 'reload schema';

commit;
