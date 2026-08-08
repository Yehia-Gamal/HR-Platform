-- =====================================================================
-- 0318: ????? ????????? (mission execution)
-- ---------------------------------------------------------------------
-- ?????? ???? ???????/????? ?????? ?????? ?? ?????? ?????? ??????
-- (????? ??????? ??? ????? ?????? ?????? - ????? ?? ?????? ????? � 1 ?????).
-- - ???? mission_executions (??? ????? ???? ??? ??? - request_id ????).
-- - start_my_mission / end_my_mission: RPCs ?????? ?????? (security definer).
-- - submit_my_request: ???? startTime/endTime ????????? ????? HH:MM (??? "9:00").
-- - get_request_inbox / get_mobile_request_detail: ????? payload + missionExecution.
-- =====================================================================

create table if not exists public.mission_executions (
  id              uuid primary key default gen_random_uuid(),
  request_id      uuid not null unique references public.requests(id) on delete cascade,
  employee_id     uuid not null references public.employees(id),
  status          text not null default 'not_started'
                  check (status in ('not_started','in_progress','completed')),
  started_at      timestamptz,
  ended_at        timestamptz,
  actual_minutes  integer check (actual_minutes is null or actual_minutes >= 1),
  report          text,
  outcome         text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ended_at is null or started_at is not null),
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists mission_executions_employee_idx
  on public.mission_executions(employee_id);

comment on table public.mission_executions is
  'سجل تنفيذ المأموريات/القوافل المعتمدة — بدء الموظف وإنهاؤه بالتقرير';

-- RLS: الوصول عبر RPCs حصرياً (security definer يتجاوز RLS كمالك).
alter table public.mission_executions enable row level security;

-- ─── RPC: بدء المأمورية ───────────────────────────────────────────────────
drop function if exists public.start_my_mission(uuid);
create or replace function public.start_my_mission(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me  uuid := public.current_employee_id();
  v_req public.requests;
  v_id  uuid;
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
  if v_req.request_type not in ('mission','convoy') then
    raise exception 'not an assignment request' using errcode = '22023';
  end if;
  if v_req.status <> 'approved' then
    raise exception 'mission must be approved before start' using errcode = '22023';
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', now())
  returning id into v_id;

  return v_id;
end $$;

-- ─── RPC: إنهاء المأمورية بالتقرير ────────────────────────────────────────
drop function if exists public.end_my_mission(uuid, text, text);
create or replace function public.end_my_mission(
  p_request_id uuid,
  p_report text,
  p_outcome text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := public.current_employee_id();
  v_exec    public.mission_executions;
  v_minutes integer;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_exec from public.mission_executions where request_id = p_request_id;
  if not found then
    raise exception 'execution not started' using errcode = 'P0002';
  end if;
  if v_exec.employee_id <> v_me then
    raise exception 'mission ownership required' using errcode = '42501';
  end if;
  if v_exec.status <> 'in_progress' then
    raise exception 'execution already finished' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_report, ''))) < 3 then
    raise exception 'report is required (min 3 chars)' using errcode = '22023';
  end if;

  v_minutes := greatest(1, round(extract(epoch from (now() - v_exec.started_at)) / 60)::integer);

  update public.mission_executions
     set ended_at         = now(),
         actual_minutes   = v_minutes,
         report           = trim(p_report),
         outcome          = nullif(trim(coalesce(p_outcome, '')), ''),
         status           = 'completed',
         updated_at       = now()
   where id = v_exec.id;

  return v_exec.id;
end $$;

grant execute on function public.start_my_mission(uuid) to authenticated;
grant execute on function public.end_my_mission(uuid, text, text) to authenticated;
revoke execute on function public.start_my_mission(uuid) from public, anon;
revoke execute on function public.end_my_mission(uuid, text, text) from public, anon;

-- ─── submit_my_request: startTime/endTime بصيغة HH:MM (اختياريان) ─────────
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns requests
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_start_date date;
  v_end_date date;
  v_permit_date date;
  v_minutes integer;
  v_leave_type text;
  v_leave_type_id uuid;
  v_affects boolean;
  v_days numeric;
  v_substitute uuid;
  v_correction_date date;
  v_correction_type text;
  v_corrected_time text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8: 6 أنواع رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- توافق خلفي: emergency → casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid') then
          raise exception 'unsupported leave type' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
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

      -- ─── مأمورية / قافلة ────────────────────────────────────────────────────
      when 'mission', 'convoy' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        -- 0318: وقت مخطط اختياري بصيغة HH:MM — يرفض "9:00"
        if nullif(trim(coalesce(v_payload->>'startTime','')),'') is not null
           and v_payload->>'startTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'startTime must be in HH:MM format' using errcode = '22023';
        end if;
        if nullif(trim(coalesce(v_payload->>'endTime','')),'') is not null
           and v_payload->>'endTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'endTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1,
          'startTime', nullif(trim(coalesce(v_payload->>'startTime','')),''),
          'endTime', nullif(trim(coalesce(v_payload->>'endTime','')),''));

      -- ─── إذن تأخير (V17 §8 — كان attendance_permit + late_arrival) ─────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر (V17 §8 — كان attendance_permit + early_departure) ─
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── تصحيح حضور (V17 §8 — نوع جديد) ──────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'correction date is required' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'correctionType must be check_in, check_out, or both' using errcode = '22023';
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
      raise exception 'invalid request dates or numeric values' using errcode = '22023';
  end;

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل)
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public.submit_request(
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026)
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

    -- العارضة/الطارئة: تُنفَّذ مباشرة دون موافقة المدير المباشر
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
end $function$;

-- ─── get_request_inbox: إرفاق payload + missionExecution ──────────────────
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
      'missionExecution', case when r.request_type in ('mission','convoy') then (
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

-- ─── get_mobile_request_detail: إرفاق missionExecution ────────────────────
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

  -- 0318: سجل تنفيذ المأمورية (إن وُجد)
  if v_request.request_type in ('mission','convoy') then
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
