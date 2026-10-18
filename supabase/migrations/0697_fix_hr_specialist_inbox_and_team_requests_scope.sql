-- ─── 0697_fix_hr_specialist_inbox_and_team_requests_scope.sql ───────────
-- ضمان ظهور طلبات الموظفين لجميع كوادر الموارد البشرية (hr-manager, hr-specialist, hr-officer)
-- والنظام التقني والمديرين بدون اشتراط وجود تبعية مباشرة في manager_relations.

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

  v_broad := v_full or v_roles && array[
    'admin', 'super-admin', 'system-admin',
    'executive', 'executive-director', 'general-manager', 'executive-secretary',
    'hr-manager', 'hr-specialist', 'hr-officer',
    'operations-manager-1', 'operations-manager'
  ];

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
               and (mr.effective_to is null or mr.effective_to >= current_date)
          )
    ),
    picked as (
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
comment on function public.get_request_inbox(integer) is 'صندوق الطلبات لجميع المستويات مع إدراج hr-specialist و hr-officer و system-admin ضمن النطاق الشامل v_broad';
