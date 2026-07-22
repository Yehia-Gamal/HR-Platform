-- V10 acceptance repairs for leave/mission requests.
-- Forward-only: private attachments, substitutes/conflicts, mandatory rejection
-- reason, and explicit Operations decision attribution.
begin;

-- Private request attachments. Object paths start with auth.uid().
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('request-attachments','request-attachments',false,10485760,array[
  'application/pdf','image/jpeg','image/png','image/webp'
])
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create unique index if not exists ux_attachments_entity_path
on public.attachments(entity_type,entity_id,storage_path);

drop policy if exists request_attachments_storage_insert on storage.objects;
create policy request_attachments_storage_insert on storage.objects
for insert to authenticated with check(
  bucket_id='request-attachments'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists request_attachments_storage_read on storage.objects;
create policy request_attachments_storage_read on storage.objects
for select to authenticated using(
  bucket_id='request-attachments' and (
    (storage.foldername(name))[1]=auth.uid()::text
    or exists(
      select 1
      from public.attachments a
      join public.requests r on r.id=a.entity_id
      where a.entity_type='request' and a.storage_path=name
        and (
          r.employee_id=public.current_employee_id()
          or r.manager_employee_id=public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_employee(r.employee_id,'requests.request.read')
          or public.can_access_employee(r.employee_id,'requests.request.approve')
        )
    )
  )
);

drop policy if exists request_attachments_storage_delete on storage.objects;
create policy request_attachments_storage_delete on storage.objects
for delete to authenticated using(
  bucket_id='request-attachments'
  and (storage.foldername(name))[1]=auth.uid()::text
);

-- Link payload attachmentPaths to the append-only attachment catalog.
create or replace function public.tg_link_request_attachments()
returns trigger language plpgsql security definer set search_path=public,storage,pg_temp as $$
declare v_item jsonb; v_path text; v_mime text; v_size bigint; v_count integer;
begin
  if new.payload ? 'attachmentPaths' then
    if jsonb_typeof(new.payload->'attachmentPaths')<>'array' then
      raise exception 'INVALID_REQUEST_ATTACHMENTS' using errcode='22023';
    end if;
    v_count:=jsonb_array_length(new.payload->'attachmentPaths');
    if v_count>5 then raise exception 'TOO_MANY_REQUEST_ATTACHMENTS' using errcode='22023'; end if;
    for v_item in select value from jsonb_array_elements(new.payload->'attachmentPaths') loop
      v_path:=nullif(trim(v_item->>'path'),'');
      v_mime:=nullif(trim(v_item->>'mimeType'),'');
      begin v_size:=nullif(v_item->>'sizeBytes','')::bigint;
      exception when invalid_text_representation then
        raise exception 'INVALID_REQUEST_ATTACHMENT_SIZE' using errcode='22023';
      end;
      if v_path is null
        or split_part(v_path,'/',1)<>auth.uid()::text
        or v_mime not in ('application/pdf','image/jpeg','image/png','image/webp')
        or coalesce(v_size,0)<1 or v_size>10485760
        or not exists(select 1 from storage.objects o where o.bucket_id='request-attachments' and o.name=v_path)
      then raise exception 'INVALID_REQUEST_ATTACHMENT' using errcode='22023'; end if;
      insert into public.attachments(entity_type,entity_id,storage_path,mime,size_bytes,created_by)
      values('request',new.id,v_path,v_mime,v_size,auth.uid())
      on conflict(entity_type,entity_id,storage_path) do nothing;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists trg_link_request_attachments on public.requests;
create trigger trg_link_request_attachments
after insert on public.requests for each row execute function public.tg_link_request_attachments();

-- Validate the chosen substitute and mirror the first attachment path in the
-- legacy leave_requests.attachment_url column for backward compatibility.
create or replace function public.tg_validate_leave_request_v10()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_payload jsonb; v_first jsonb;
begin
  if new.substitute_employee_id is not null then
    if new.substitute_employee_id=new.employee_id then
      raise exception 'SUBSTITUTE_CANNOT_BE_REQUESTER' using errcode='22023';
    end if;
    if not exists(select 1 from public.employees e where e.id=new.substitute_employee_id and e.is_active and e.status='active' and not coalesce(e.is_deleted,false)) then
      raise exception 'INVALID_SUBSTITUTE' using errcode='22023';
    end if;
  end if;
  select payload into v_payload from public.requests where id=new.request_id;
  if new.attachment_url is null and jsonb_typeof(v_payload->'attachmentPaths')='array'
     and jsonb_array_length(v_payload->'attachmentPaths')>0 then
    v_first:=(v_payload->'attachmentPaths')->0;
    new.attachment_url:=v_first->>'path';
  end if;
  return new;
end $$;

drop trigger if exists trg_validate_leave_request_v10 on public.leave_requests;
create trigger trg_validate_leave_request_v10
before insert or update on public.leave_requests for each row execute function public.tg_validate_leave_request_v10();

-- Enforce the rejection reason in the database, and preserve the real actor
-- on every decision including Operations acting after escalation.
create or replace function public.tg_guard_request_decision_v10()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_escalation jsonb; v_actor_name text;
begin
  if new.action='reject' and length(trim(coalesce(new.comment,'')))<3 then
    raise exception 'REJECTION_REASON_REQUIRED' using errcode='22023';
  end if;
  if new.action in ('approve','reject') then
    select r.payload->'escalation',e.full_name_ar
      into v_escalation,v_actor_name
    from public.requests r
    left join public.employees e on e.id=new.actor_employee_id
    where r.id=new.request_id;
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object(
      'actorEmployeeId',new.actor_employee_id,
      'actorName',v_actor_name,
      'onBehalfOfExecutive',coalesce((v_escalation->>'onBehalfOfExecutive')::boolean,false),
      'decisionMode',case
        when coalesce((v_escalation->>'onBehalfOfExecutive')::boolean,false)
          then 'OPERATIONS_ON_BEHALF_OF_EXECUTIVE_DIRECTOR'
        else 'DIRECT_AUTHORIZED_DECISION'
      end
    );
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_request_decision_v10 on public.request_actions;
create trigger trg_guard_request_decision_v10
before insert on public.request_actions for each row execute function public.tg_guard_request_decision_v10();

-- Decision context shown to the manager: substitute and concrete overlaps.
create or replace function public.get_request_decision_context(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_req public.requests; v_start date; v_end date; v_sub uuid; v_sub_name text; v_conflicts jsonb;
begin
  select * into v_req from public.requests where id=p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  if not(
    v_req.employee_id=public.current_employee_id()
    or v_req.manager_employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_req.employee_id,'requests.request.read')
    or public.can_access_employee(v_req.employee_id,'requests.request.approve')
  ) then raise exception 'REQUEST_ACCESS_DENIED' using errcode='42501'; end if;

  begin
    v_start:=nullif(v_req.payload->>'startDate','')::date;
    v_end:=nullif(v_req.payload->>'endDate','')::date;
  exception when invalid_text_representation then
    v_start:=null; v_end:=null;
  end;
  select lr.substitute_employee_id,e.full_name_ar into v_sub,v_sub_name
  from public.leave_requests lr left join public.employees e on e.id=lr.substitute_employee_id
  where lr.request_id=p_request_id;

  if v_start is null or v_end is null then v_conflicts:='[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'type',q.kind,'message',q.message,'requestId',q.request_id
    ) order by q.kind,q.message),'[]'::jsonb) into v_conflicts
    from (
      select 'employee_overlap'::text kind,
        format('لدى الموظف طلب %s متداخل (%s إلى %s)',r.request_number,r.payload->>'startDate',r.payload->>'endDate') message,
        r.id request_id
      from public.requests r
      where r.id<>p_request_id and r.employee_id=v_req.employee_id
        and r.status in ('pending','approved')
        and r.request_type in ('leave','mission','convoy')
        and nullif(r.payload->>'startDate','') is not null
        and nullif(r.payload->>'endDate','') is not null
        and (r.payload->>'startDate')::date<=v_end and (r.payload->>'endDate')::date>=v_start
      union all
      select 'substitute_overlap',
        format('البديل لديه طلب متداخل رقم %s',r.request_number),r.id
      from public.requests r
      where v_sub is not null and r.employee_id=v_sub and r.status in ('pending','approved')
        and r.request_type in ('leave','mission','convoy')
        and nullif(r.payload->>'startDate','') is not null
        and nullif(r.payload->>'endDate','') is not null
        and (r.payload->>'startDate')::date<=v_end and (r.payload->>'endDate')::date>=v_start
    ) q;
  end if;
  return jsonb_build_object(
    'substitute',case when v_sub is null then null else jsonb_build_object('id',v_sub,'name',v_sub_name) end,
    'hasConflict',jsonb_array_length(v_conflicts)>0,
    'conflicts',v_conflicts
  );
end $$;

revoke all on function public.get_request_decision_context(uuid) from public,anon;
grant execute on function public.get_request_decision_context(uuid) to authenticated;

-- Extended mobile detail with actor identity, escalation attribution, decision
-- context and registered attachments. Signature remains unchanged.
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_request public.requests; v_employee public.employees;
  v_can_decide boolean:=false; v_can_cancel boolean:=false;
  v_steps jsonb:='[]'::jsonb; v_attachments jsonb:='[]'::jsonb;
  v_decision_actor text; v_decision_mode text; v_decision_on_behalf boolean:=false;
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
    'decisionOnBehalfOfExecutive',v_decision_on_behalf
  );
end $$;

revoke all on function public.get_mobile_request_detail(uuid) from public,anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;

commit;
