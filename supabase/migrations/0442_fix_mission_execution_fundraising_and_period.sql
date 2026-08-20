-- =====================================================================
-- 0442: إصلاحات تنفيذ المأمورية/القافلة/الفاندي (start_my_mission)
-- ---------------------------------------------------------------------
-- 1) الفاندي (fundraising) يدعم التنفيذ الميداني مثل المأمورية والقافلة:
--    كان الموبايل/الويب يعرضان بطاقة التنفيذ للفاندي لكن الخادم كان
--    يرفض البدء بـ 22023، وكان get_request_inbox/get_mobile_request_detail
--    لا يرفقان missionExecution إلا لـ mission/convoy.
-- 2) منع بدء التنفيذ بعد انتهاء فترة الطلب (endDate).
-- 3) إغلاق سجل التنفيذ المفتوح (in_progress) عند إلغاء/رفض/سحب/انتهاء
--    الطلب بعد بدئه حتى لا يعلق مفتوحًا للأبد.
-- =====================================================================

begin;

-- ─── 1) start_my_mission: قبول fundraising + منع البدء بعد انتهاء الفترة ───
create or replace function public.start_my_mission(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := public.current_employee_id();
  v_req   public.requests;
  v_end   date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_id    uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if v_req.employee_id <> v_me then
    raise exception 'mission ownership required' using errcode = '42501';
  end if;
  if v_req.request_type not in ('mission','convoy','fundraising') then
    raise exception 'not an assignment request' using errcode = '22023';
  end if;
  if v_req.status <> 'approved' then
    raise exception 'mission must be approved before start' using errcode = '22023';
  end if;

  -- 0442: لا يُبدئ التنفيذ بعد انتهاء فترة الطلب (startDate..endDate)
  begin
    v_end := (nullif(v_req.payload->>'endDate', ''))::date;
  exception when others then
    v_end := null;
  end;
  if v_end is not null and v_today > v_end then
    raise exception 'لا يمكن بدء المأمورية بعد انتهاء مدتها' using errcode = '22023';
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', now())
  returning id into v_id;

  return v_id;
end $$;

grant execute on function public.start_my_mission(uuid) to authenticated;
revoke execute on function public.start_my_mission(uuid) from public, anon;

-- ─── 2) get_request_inbox: إرفاق missionExecution للفاندي أيضاً ─────────────
create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language sql
stable
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
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) q;
$function$;

-- ─── 3) get_mobile_request_detail: إرفاق missionExecution للفاندي أيضاً ─────
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to public, pg_temp
as $function$
declare
  v_request public.requests; v_employee public.employees;
  v_can_decide boolean:=false; v_can_cancel boolean:=false;
  v_steps jsonb:='[]'::jsonb; v_attachments jsonb:='[]'::jsonb;
  v_decision_actor text; v_decision_mode text; v_decision_on_behalf boolean:=false;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id=p_request_id;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;
  if not(
    v_request.employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.can_access_employee(v_request.employee_id,'requests.request.read')
    or v_request.manager_employee_id=public.current_employee_id()
  ) then raise exception 'request access denied' using errcode='42501'; end if;

  select * into v_employee from public.employees where id=v_request.employee_id;
  v_can_cancel:=v_request.status='pending' and v_request.employee_id=public.current_employee_id();
  v_can_decide:=v_request.status='pending' and v_request.employee_id<>public.current_employee_id() and (
    public.current_is_full_access()
    or v_request.manager_employee_id=public.current_employee_id()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.has_permission('requests.request.approve')
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'order',s.step_order,'name',s.name_ar,'status',s.status,
    'decision',case when s.status in ('approved','rejected') then s.status else null end,
    'comment',s.comment,'decidedAt',s.acted_at,'dueAt',s.due_at,
    'actorName',actor.full_name_ar
  ) order by s.step_order),'[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id=s.acted_by
  where s.request_id=p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path',a.storage_path,'mimeType',a.mime,'sizeBytes',a.size_bytes
  ) order by a.created_at),'[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type='request' and a.entity_id=p_request_id;

  select e.full_name_ar,a.metadata->>'decisionMode',coalesce((a.metadata->>'onBehalfOfExecutive')::boolean,false)
  into v_decision_actor,v_decision_mode,v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id=a.actor_employee_id
  where a.request_id=p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  -- 0318: سجل تنفيذ المأمورية (إن وُجد) — 0442: يشمل الفاندي
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
    'id',v_request.id,'requestNumber',v_request.request_number,'requestType',v_request.request_type,
    'employeeId',v_request.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
    'title',v_request.title,'reason',v_request.reason,'status',v_request.status,
    'workflowStatus',v_request.workflow_status,'payload',coalesce(v_request.payload,'{}'::jsonb),
    'currentStepOrder',v_request.current_step_order,'decisionDueAt',v_request.decision_due_at,
    'createdAt',v_request.created_at,'updatedAt',v_request.updated_at,
    'canDecide',v_can_decide,'canCancel',v_can_cancel,'steps',v_steps,
    'attachments',v_attachments,'decisionContext',public.get_request_decision_context(p_request_id),
    'decisionActorName',v_decision_actor,'decisionMode',v_decision_mode,
    'decisionOnBehalfOfExecutive',v_decision_on_behalf,
    'missionExecution',v_execution
  );
end $function$;

-- ─── 4) إغلاق سجل التنفيذ المفتوح عند إنهاء الطلب سلباً ─────────────────────
create or replace function public.tg_mission_execution_close_on_cancel()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status in ('rejected','cancelled','withdrawn','expired') then
    update public.mission_executions
       set status     = 'completed',
           ended_at   = coalesce(ended_at, now()),
           report     = coalesce(report, 'أُلغي الطلب قبل إتمام التنفيذ'),
           updated_at = now()
     where request_id = new.id and status = 'in_progress';
  end if;
  return new;
end $$;

drop trigger if exists trg_mission_execution_close_on_cancel on public.requests;
create trigger trg_mission_execution_close_on_cancel
  after update of status on public.requests
  for each row
  when (new.status in ('rejected','cancelled','withdrawn','expired'))
  execute function public.tg_mission_execution_close_on_cancel();

commit;

notify pgrst, 'reload schema';