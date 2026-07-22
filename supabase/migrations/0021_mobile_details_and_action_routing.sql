-- Migration 0021: Mobile detail read models and robust action routing.
-- Extends the canonical request/KPI/feed models without introducing parallel tables.

begin;

create or replace function public.get_mobile_action_target(p_action_id text, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'invalid action identifier' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$$;
revoke execute on function public.get_mobile_action_target(text,text) from public;
grant execute on function public.get_mobile_action_target(text,text) to authenticated;

create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_request public.requests;
  v_employee public.employees;
  v_can_decide boolean := false;
  v_can_cancel boolean := false;
  v_steps jsonb := '[]'::jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;
  if not (
    v_request.employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
  ) then
    raise exception 'request access denied' using errcode='42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  v_can_cancel := v_request.status = 'pending'
    and v_request.employee_id = public.current_employee_id();

  v_can_decide := v_request.status = 'pending' and (
    public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.has_permission('requests.request.approve')
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'order', s.step_order,
    'name', s.name_ar,
    'status', s.status,
    'decision', case when s.status in ('approved','rejected') then s.status else null end,
    'comment', s.comment,
    'decidedAt', s.acted_at,
    'dueAt', s.due_at
  ) order by s.step_order), '[]'::jsonb)
  into v_steps
  from public.request_steps s where s.request_id = p_request_id;

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
    'steps', v_steps
  );
end;
$$;
revoke execute on function public.get_mobile_request_detail(uuid) from public;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;

create or replace function public.get_mobile_feed_item(p_kind text, p_item_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if lower(p_kind) = 'announcement' then
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'requiresAcknowledgement', a.requires_acknowledgement,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'attachments', case when a.banner_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',a.banner_url,'type','banner')) end
    ) into v_result
    from public.announcements a where a.id=p_item_id and a.status='published';
  elsif lower(p_kind) = 'decision' then
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'requiresAcknowledgement', d.requires_read_receipt,
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'decisionNumber', d.decision_number,
      'effectiveDate', d.effective_date,
      'attachments', case when d.attachment_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',d.attachment_url,'type','attachment')) end
    ) into v_result
    from public.administrative_decisions d where d.id=p_item_id and d.status='published';
  else
    raise exception 'unsupported feed item kind' using errcode='22023';
  end if;
  if v_result is null then raise exception 'feed item not found or not visible' using errcode='P0002'; end if;
  return v_result;
end;
$$;
grant execute on function public.get_mobile_feed_item(text,uuid) to authenticated;

create or replace function public.get_my_passkeys()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'deviceLabel', p.device_label,
    'status', p.status,
    'trusted', p.trusted,
    'deviceType', p.credential_device_type,
    'backedUp', p.credential_backed_up,
    'lastUsedAt', p.last_used,
    'createdAt', p.created_at
  ) order by p.created_at desc), '[]'::jsonb)
  from public.passkey_credentials p
  where p.user_id=auth.uid() and p.employee_id=public.current_employee_id();
$$;
grant execute on function public.get_my_passkeys() to authenticated;

commit;
