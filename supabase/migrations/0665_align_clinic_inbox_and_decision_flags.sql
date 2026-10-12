-- ============================================================================
-- 0665: مواءمة صندوق الطلبات وأعلام القرار للإدارة المشتركة لمصطفى أحمد ويوسف رسمي
-- ============================================================================
-- المشكلة:
--   في 0646، تم بناء الدوال request_decision_flags و get_request_inbox
--   و get_mobile_request_detail لحساب canDecide و awaitingMe بناءً على
--   المدير المباشر المسجل في حقل manager_employee_id.
--   وعند تقديم طلب من طاقم العيادات، يُسند إلى مصطفى أحمد كمعتمد افتراضي.
--   مما جعل يوسف رسمي (الشريك في إدارة العيادات) لا يرى طلبات العيادات في
--   صندوق الوارد مع canDecide = true و awaitingMe = true.
--
-- الحل:
--   1) تحديث request_decision_flags للتعرف على إدارة العيادات المشتركة
--      (مصطفى أحمد ويوسف رسمي ودور clinics-manager) كمديرين معتمدين لطلبات العيادات.
--   2) تحديث get_request_inbox ليشمل طلبات العيادات في استعلام visible لكلا المديرين.
--   3) تحديث get_mobile_request_detail لمنح حق الوصول وعرض أزرار القرار لكلا المديرين.
-- ============================================================================

begin;

-- ─── 1) أعلام القرار — تمكين مصطفى أحمد ويوسف رسمي كمديرين معتمدين ────────────

create or replace function public.request_decision_flags(
  p_req   public.requests,
  p_me    uuid,
  p_full  boolean,
  p_roles text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_roles         text[] := coalesce(p_roles, '{}'::text[]);
  v_step          public.request_steps;
  v_is_clinic_mgr boolean;
  v_is_mgr        boolean;
  v_is_ops        boolean;
  v_override      boolean;
  v_can           boolean;
  v_awaiting      boolean;
begin
  -- لا قرار على طلب غير معلّق ولا على طلب المستخدم نفسه
  if p_me is null or p_req.id is null or p_req.status <> 'pending'
     or p_req.employee_id = p_me then
    return jsonb_build_object('canDecide', false, 'awaitingMe', false);
  end if;

  -- نفس اختيار decide_request: الخطوة النشطة أولًا ثم أول escalated/pending
  select * into v_step
    from public.request_steps
   where request_id = p_req.id
     and status in ('active', 'escalated', 'pending')
   order by (status = 'active') desc, step_order
   limit 1;

  v_is_clinic_mgr := (
    p_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  v_is_mgr := p_req.manager_employee_id is not distinct from p_me
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(p_req.employee_id)
        or p_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = p_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_req.employee_id
         and mr.manager_employee_id = p_me
         and mr.relation_type = 'primary'
         and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_is_ops := 'operations-manager-1' = any(v_roles);
  v_override := coalesce(p_full, false)
    or v_roles && array['executive', 'executive-director', 'general-manager',
                        'hr-manager', 'hr-specialist', 'hr-officer',
                        'admin', 'super-admin'];

  v_can := v_override
    or v_is_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = p_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or (v_is_ops and (
          coalesce(v_step.step_order, 0) >= 2
       or coalesce(v_step.escalation_deadline, p_req.escalation_deadline) < now()
       or p_req.workflow_status in ('escalated', 'awaiting_operator')
       or p_req.request_type in ('mission', 'convoy', 'fundraising')));

  -- «دورك الآن»: الخطوة الحالية مُسندة إليك باسمك أو بدورك أو لإدارة العيادات المشتركة
  v_awaiting := v_can and (
       (v_step.id is not null and (
         v_step.assignee_employee_id = p_me
         or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
       ))
    or (v_step.id is not null and v_step.assignee_role_slug is not null
        and (v_step.assignee_role_slug = any(v_roles) or (v_is_clinic_mgr and v_step.assignee_role_slug = 'clinics-manager')))
    or (v_step.id is not null and v_step.assignee_employee_id is null
        and v_step.assignee_role_slug is null and v_is_mgr)
    or (v_step.id is null and (
          v_is_mgr
       or (v_is_ops and p_req.workflow_status in ('escalated', 'awaiting_operator')))));

  return jsonb_build_object('canDecide', v_can, 'awaitingMe', coalesce(v_awaiting, false));
end;
$$;

revoke all on function public.request_decision_flags(public.requests, uuid, boolean, text[])
  from public, anon, authenticated;

-- ─── 2) صندوق الطلبات — تضمين طلبات العيادات في استعلام visible ──────────────

create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_full          boolean := public.current_is_full_access();
  v_roles         text[];
  v_broad         boolean;
  v_is_clinic_mgr boolean;
  v_limit         integer := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  v_broad := v_full or v_roles && array['admin', 'super-admin', 'executive',
    'executive-director', 'general-manager', 'hr-manager', 'operations-manager-1'];

  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  return (
    with visible as (
      select r.id, r.status, r.employee_id, r.created_at
        from public.requests r
       where v_broad
          or r.employee_id = v_me
          or r.manager_employee_id = v_me
          or (
            v_is_clinic_mgr and (
              public.is_clinic_team_member(r.employee_id)
              or r.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
              or exists (
                select 1 from public.workflow_definitions wd
                where wd.id = r.workflow_definition_id and wd.code like 'medical_%'
              )
            )
          )
          or exists (
            select 1 from public.manager_relations mr
             where mr.employee_id = r.employee_id
               and mr.manager_employee_id = v_me
               and mr.relation_type = 'primary'
               and mr.effective_from <= current_date
               and (mr.effective_to is null or mr.effective_to >= current_date))
          or exists (
            select 1 from public.request_steps s
             where s.request_id = r.id and (
               s.assignee_employee_id = v_me
               or (v_is_clinic_mgr and s.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
             ))
          or public.can_access_employee(r.employee_id, 'requests.request.approve')
          or public.can_access_employee(r.employee_id, 'requests.request.read')
          or public.can_access_employee(r.employee_id, 'requests.read')
          or public.can_access_employee(r.employee_id, 'requests.approve')
    ),
    picked as (
      -- المعلّق أولًا ثم طلباتي ثم الأحدث — قبل القصّ لا بعده
      select v.id
        from visible v
       order by (v.status = 'pending') desc,
                (v.employee_id is not distinct from v_me) desc,
                v.created_at desc
       limit v_limit
    )
    select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb)
      from (
        select p.created_at,
               jsonb_build_object(
                 'id', p.id,
                 'requestNumber', p.request_number,
                 'requestType', p.request_type,
                 'employeeId', p.employee_id,
                 'employeeName', e.full_name_ar,
                 'employeeCode', e.employee_code,
                 'employeePhotoUrl', e.photo_url,
                 'employeeDepartment', d.name,
                 'employeeJobTitle', jt.name,
                 'title', p.title,
                 'reason', p.reason,
                 'status', p.status,
                 'workflowStatus', p.workflow_status,
                 'currentStepOrder', coalesce(p.current_step_order, 0),
                 'activeStepName', cs.name_ar,
                 'activeStepRole', cs.assignee_role_slug,
                 'activeStepStatus', cs.status,
                 'activeStepDueAt', cs.due_at,
                 'decisionDueAt', p.decision_due_at,
                 'decidedAt', p.decided_at,
                 'decidedByName', dec.full_name_ar,
                 'createdAt', p.created_at,
                 'updatedAt', p.updated_at,
                 'payload', p.payload,
                 'isMine', coalesce(p.employee_id = v_me, false),
                 'canDecide', coalesce((fl.flags->>'canDecide')::boolean, false),
                 'awaitingMe', coalesce((fl.flags->>'awaitingMe')::boolean, false),
                 'missionExecution', case when p.request_type in ('mission', 'convoy', 'fundraising') then (
                   select to_jsonb(me) from (
                     select me.id, me.status,
                            me.started_at as "startedAt",
                            me.ended_at as "endedAt",
                            me.actual_minutes as "actualMinutes",
                            me.report, me.outcome
                       from public.mission_executions me
                      where me.request_id = p.id
                   ) me
                 ) end
               ) as item
          from picked k
          join public.requests p on p.id = k.id
          join public.employees e on e.id = p.employee_id
          left join public.departments d on d.id = e.department_id
          left join public.job_titles jt on jt.id = e.job_title_id
          left join public.employees dec on dec.id = p.decided_by
          left join lateral (
            select rs.name_ar, rs.assignee_role_slug, rs.status, rs.due_at
              from public.request_steps rs
             where rs.request_id = p.id
               and p.status = 'pending'
               and rs.status in ('active', 'escalated', 'pending')
             order by (rs.status = 'active') desc, rs.step_order
             limit 1
          ) cs on true
          cross join lateral (
            select public.request_decision_flags(p, v_me, v_full, v_roles) as flags
          ) fl
      ) x
  );
end;
$$;

revoke all on function public.get_request_inbox(integer) from public, anon;
grant execute on function public.get_request_inbox(integer) to authenticated;

-- ─── 3) تفاصيل الطلب — إتاحة الوصول لكلا مديري العيادات ──────────────────────

create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_is_clinic_mgr      boolean;
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
  v_current_step       uuid;
  v_steps              jsonb;
  v_history            jsonb;
  v_attachments        jsonb;
  v_context            jsonb;
  v_decided_by         text;
  v_cancelled_by       text;
  v_decision_actor     text;
  v_decision_mode      text;
  v_decision_on_behalf boolean;
  v_execution          jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  if not coalesce(
       v_request.employee_id = v_me
    or v_request.manager_employee_id = v_me
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_request.employee_id)
        or v_request.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_request.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
         select 1 from public.manager_relations mr
          where mr.employee_id = v_request.employee_id
            and mr.manager_employee_id = v_me
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date))
    or exists (
         select 1 from public.request_steps s
          where s.request_id = v_request.id and (
            s.assignee_employee_id = v_me
            or (v_is_clinic_mgr and s.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
          ))
    or v_full
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'operations-manager-1']
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve'),
    false
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  select d.name into v_department from public.departments d where d.id = v_employee.department_id;
  select jt.name into v_job_title from public.job_titles jt where jt.id = v_employee.job_title_id;

  v_flags := public.request_decision_flags(v_request, v_me, v_full, v_roles);

  if v_request.status = 'pending' then
    select s.id into v_current_step
      from public.request_steps s
     where s.request_id = v_request.id
       and s.status in ('active', 'escalated', 'pending')
     order by (s.status = 'active') desc, s.step_order
     limit 1;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'order', s.step_order,
           'name', s.name_ar,
           'roleSlug', s.assignee_role_slug,
           'status', s.status,
           'decision', case
               when s.status = 'approved' then 'approved'
               when s.status = 'rejected' and v_request.status = 'returned' then 'returned'
               when s.status = 'rejected' then 'rejected'
             end,
           'comment', case when s.status in ('approved', 'rejected') then nullif(trim(s.comment), '') end,
           'decidedAt', case when s.status in ('approved', 'rejected') then s.acted_at end,
           'actorName', case when s.status in ('approved', 'rejected') then actor.full_name_ar end,
           'dueAt', s.due_at,
           'escalatedAt', s.escalated_at,
           'isCurrent', s.id is not distinct from v_current_step
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = p_request_id;

  with base as (
    select a.*,
           sum((a.action = 'submit')::int) over (
             order by a.created_at, a.id
             rows between unbounded preceding and current row) as cycle_no
      from public.request_actions a
     where a.request_id = p_request_id
       and a.action in ('submit', 'approve', 'reject', 'return', 'request_changes',
                        'cancel', 'withdraw', 'escalate', 'expire', 'reassign')
  ),
  ranked as (
    select b.*,
           row_number() over w as rn,
           count(*) over w as cnt
      from base b
    window w as (
      partition by b.cycle_no, b.action,
                   coalesce(b.metadata->>'targetRole', b.metadata->>'escalatedToRole', '')
      order by b.created_at, b.id
      rows between unbounded preceding and unbounded following)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'action', x.action,
           'at', x.created_at,
           'actorName', case when x.action in ('escalate', 'expire') then null else actor.full_name_ar end,
           'comment', case when x.action in ('approve', 'reject', 'return', 'request_changes',
                                             'cancel', 'withdraw', 'reassign')
                           then nullif(trim(x.comment), '') end,
           'stepOrder', st.step_order,
           'stepName', st.name_ar,
           'stepRole', st.assignee_role_slug,
           'targetRole', coalesce(x.metadata->>'targetRole', x.metadata->>'escalatedToRole'),
           'repeat', case when x.action = 'escalate' then x.cnt end,
           'isResubmit', x.action = 'submit' and x.from_status in ('rejected', 'returned')
         ) order by x.created_at, x.id), '[]'::jsonb)
    into v_history
    from ranked x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.action <> 'escalate' or x.rn = 1;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
         ) order by a.created_at), '[]'::jsonb)
    into v_attachments
    from public.attachments a
   where a.entity_type = 'request' and a.entity_id = p_request_id;

  begin
    v_context := public.get_request_decision_context(p_request_id);
  exception when others then
    v_context := null;
  end;

  select e.full_name_ar into v_decided_by from public.employees e where e.id = v_request.decided_by;
  select e.full_name_ar into v_cancelled_by from public.employees e where e.id = v_request.cancelled_by;

  select e.full_name_ar, a.metadata->>'decisionMode',
         coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions a
    left join public.employees e on e.id = a.actor_employee_id
   where a.request_id = p_request_id and a.action in ('approve', 'reject', 'return')
   order by a.created_at desc
   limit 1;

  if v_request.request_type in ('mission', 'convoy', 'fundraising') then
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
    'employeePhotoUrl', v_employee.photo_url,
    'employeeDepartment', v_department,
    'employeeJobTitle', v_job_title,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'decidedAt', v_request.decided_at,
    'decidedByName', v_decided_by,
    'cancelledAt', v_request.cancelled_at,
    'cancelReason', v_request.cancel_reason,
    'cancelledByName', v_cancelled_by,
    'isMine', coalesce(v_request.employee_id = v_me, false),
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'canCancel', v_request.status = 'pending' and coalesce(v_request.employee_id = v_me, false),
    'canResubmit', v_request.status in ('rejected', 'returned')
                   and coalesce(v_request.employee_id = v_me, false)
                   and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                  'late_permit', 'early_permit'),
    'steps', v_steps,
    'history', v_history,
    'attachments', v_attachments,
    'decisionContext', v_context,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;

revoke all on function public.get_mobile_request_detail(uuid) from public, anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
