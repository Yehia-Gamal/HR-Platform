-- 0106: Runtime and contract repairs found by the complete local SQL suite.

-- Compatibility overload retained for older trusted attendance callers. The
-- canonical implementation remains the double-precision overload.
create or replace function public.record_attendance_event(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters numeric,
  p_biometric_method text default 'passkey',
  p_selfie_path text default null,
  p_passkey_credential_id uuid default null,
  p_verified boolean default false,
  p_is_mock boolean default false
)
returns uuid
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.record_attendance_event(
    p_employee_id,p_event_type,p_latitude,p_longitude,
    p_accuracy_meters::double precision,p_biometric_method,p_selfie_path,
    p_passkey_credential_id,p_verified,p_is_mock
  );
$$;

revoke all on function public.record_attendance_event(
  uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean
) from public, anon, authenticated;
grant execute on function public.record_attendance_event(
  uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean
) to service_role;

-- Idempotency must be decided by INSERT ... DO NOTHING, never by timing.
-- Opening is one logical annual snapshot; corrections use adjustment entries.
create or replace function public.apply_leave_ledger_entry(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_year integer,
  p_entry_type text,
  p_units numeric,
  p_source_key text,
  p_request_id uuid default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns public.leave_ledger_entries
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_account public.leave_balance_accounts;
  v_entry public.leave_ledger_entries;
  v_available numeric;
begin
  if p_units=0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire'
  ) then raise exception 'INVALID_LEAVE_ENTRY_TYPE'; end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'LEAVE_SOURCE_KEY_REQUIRED';
  end if;
  v_account := public.ensure_leave_account(p_employee_id,p_leave_type_id,p_year);

  select * into v_entry from public.leave_ledger_entries
  where source_key=p_source_key;
  if found then return v_entry; end if;

  if p_entry_type='opening' and v_account.opening_units<>0 then
    select * into v_entry from public.leave_ledger_entries
    where account_id=v_account.id and entry_type='opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

  insert into public.leave_ledger_entries(
    account_id,employee_id,leave_type_id,request_id,entry_type,units,
    effective_date,reason,source_key,metadata,created_by
  ) values (
    v_account.id,p_employee_id,p_leave_type_id,p_request_id,p_entry_type,p_units,
    current_date,p_reason,p_source_key,coalesce(p_metadata,'{}'::jsonb),auth.uid()
  ) on conflict(source_key) do nothing returning * into v_entry;
  if not found then
    select * into strict v_entry from public.leave_ledger_entries
    where source_key=p_source_key;
    return v_entry;
  end if;

  if p_entry_type='opening' then
    update public.leave_balance_accounts set opening_units=opening_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='accrual' then
    update public.leave_balance_accounts set accrued_units=accrued_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='carryover' then
    update public.leave_balance_accounts set carryover_units=carryover_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='adjustment' then
    update public.leave_balance_accounts set adjusted_units=adjusted_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='reserve' then
    select opening_units+accrued_units+adjusted_units+carryover_units-consumed_units-reserved_units
      into v_available from public.leave_balance_accounts where id=v_account.id for update;
    if v_available<p_units then raise exception 'INSUFFICIENT_LEAVE_BALANCE'; end if;
    update public.leave_balance_accounts set reserved_units=reserved_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='release' then
    update public.leave_balance_accounts set reserved_units=greatest(0,reserved_units-abs(p_units)),updated_at=now() where id=v_account.id;
  elsif p_entry_type='consume' then
    update public.leave_balance_accounts set reserved_units=greatest(0,reserved_units-abs(p_units)),consumed_units=consumed_units+abs(p_units),updated_at=now() where id=v_account.id;
  elsif p_entry_type='refund' then
    update public.leave_balance_accounts set consumed_units=greatest(0,consumed_units-abs(p_units)),updated_at=now() where id=v_account.id;
  elsif p_entry_type='expire' then
    update public.leave_balance_accounts set adjusted_units=adjusted_units-abs(p_units),updated_at=now() where id=v_account.id;
  end if;
  return v_entry;
end;
$$;

revoke all on function public.apply_leave_ledger_entry(
  uuid,uuid,integer,text,numeric,text,uuid,text,jsonb
) from public, anon, authenticated;

-- The generic updated-at trigger was already installed on this table.
alter table public.location_request_responses
  add column if not exists updated_at timestamptz;

create or replace function public.get_my_offboarding_portal()
returns jsonb
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare v_emp uuid:=public.current_employee_id(); v_case uuid;
begin
  if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
  select id into v_case from public.offboarding_cases
  where employee_id=v_emp and status not in ('completed','cancelled')
  order by created_at desc limit 1;
  return jsonb_build_object(
    'case',case when v_case is null then null else (
      select jsonb_build_object(
        'id',o.id,'caseNumber',o.case_number,'reasonType',o.reason_type,'reason',o.reason,
        'noticeDate',o.notice_date,'lastWorkingDate',o.last_working_date,'status',o.status,
        'handoverEmployeeId',o.handover_employee_id,'approvedAt',o.approved_at
      ) from public.offboarding_cases o where o.id=v_case) end,
    'clearance',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'category',i.category,'title',i.title,'status',i.status,'dueAt',i.due_at,
      'completionNote',i.completion_note,'completedAt',i.completed_at
    ) order by i.created_at) from public.offboarding_clearance_items i where i.offboarding_case_id=v_case),'[]'::jsonb),
    'knowledgeTransfer',coalesce((select jsonb_agg(jsonb_build_object(
      'id',k.id,'title',k.title,'description',k.description,'status',k.status,
      'destinationEmployeeId',k.destination_employee_id,'acknowledgedAt',k.acknowledged_at
    ) order by k.created_at) from public.knowledge_transfer_items k where k.offboarding_case_id=v_case),'[]'::jsonb),
    'assignedAssets',coalesce((select jsonb_agg(jsonb_build_object(
      'assignmentId',aa.id,'assetId',a.id,'assetCode',a.asset_code,'assetName',a.name_ar,
      'assignedAt',aa.assigned_at,'status',aa.status
    ) order by aa.assigned_at desc) from public.asset_assignments aa
      join public.asset_inventory a on a.id=aa.asset_id
      where aa.employee_id=v_emp and aa.status='assigned'),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_offboarding_portal() from public, anon;
grant execute on function public.get_my_offboarding_portal() to authenticated;

create or replace function public.upsert_my_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
returns void
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare v_user_id uuid:=auth.uid(); v_token text:=trim(p_fcm_token);
begin
  if v_user_id is null then raise exception 'unauthorized' using errcode='42501'; end if;
  if length(v_token)<16 then raise exception 'token_too_short' using errcode='22023'; end if;
  if p_platform not in ('android','ios','web') then raise exception 'invalid_platform' using errcode='22023'; end if;
  insert into public.push_subscriptions(user_id,fcm_token,platform,is_active,last_used_at)
  values(v_user_id,v_token,p_platform,true,now())
  on conflict(user_id,fcm_token) do update set
    is_active=true,platform=excluded.platform,last_used_at=now();
end;
$$;

revoke all on function public.upsert_my_push_token(text,text) from public,anon,authenticated;
grant execute on function public.upsert_my_push_token(text,text) to authenticated;

create or replace function public.mark_my_notification_delivery(
  p_notification_id uuid,
  p_status text
)
returns void
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare v_log public.notification_delivery_log; v_subscription_id uuid;
begin
  if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
  if p_status not in ('delivered','opened') then raise exception 'invalid delivery status' using errcode='22023'; end if;
  if not exists(select 1 from public.notifications n where n.id=p_notification_id and n.recipient_user_id=auth.uid()) then
    raise exception 'notification not owned by current user' using errcode='42501';
  end if;
  select * into v_log from public.notification_delivery_log l
  where l.notification_id=p_notification_id and l.recipient_user_id=auth.uid()
    and l.channel='push' order by l.created_at desc limit 1 for update;
  if v_log.id is null then
    select id into v_subscription_id from public.push_subscriptions
    where user_id=auth.uid() and is_active
    order by last_used_at desc nulls last,created_at desc limit 1;
    insert into public.notification_delivery_log(
      notification_id,subscription_id,recipient_user_id,channel,status,
      attempts,sent_at,delivered_at
    ) values(p_notification_id,v_subscription_id,auth.uid(),'push',p_status,1,now(),now());
  elsif v_log.status<>'opened' or p_status='opened' then
    update public.notification_delivery_log set status=p_status,
      delivered_at=coalesce(delivered_at,now()),updated_at=now() where id=v_log.id;
  end if;
end;
$$;

revoke all on function public.mark_my_notification_delivery(uuid,text) from public,anon,authenticated;
grant execute on function public.mark_my_notification_delivery(uuid,text) to authenticated;

create or replace function public.change_employee_manager_admin(
  p_employee_id uuid,
  p_manager_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare v_old_manager uuid;
begin
  if not(public.current_is_full_access() or public.has_permission('people.employee.update_sensitive')) then
    raise exception 'employee_update_not_allowed' using errcode='42501';
  end if;
  if not public.can_access_employee(p_employee_id,'people.employee.update_sensitive')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'change_reason_required' using errcode='22023'; end if;
  if p_manager_id=p_employee_id then raise exception 'manager_cannot_be_self' using errcode='22023'; end if;
  perform 1 from public.employees where id=p_employee_id and not is_deleted for update;
  if not found then raise exception 'employee_not_found' using errcode='P0002'; end if;
  select manager_employee_id into v_old_manager from public.manager_relations
  where employee_id=p_employee_id and relation_type='primary'
    and effective_from<=current_date and (effective_to is null or effective_to>=current_date)
  order by effective_from desc limit 1;
  if p_manager_id is not null then
    if not exists(select 1 from public.employees where id=p_manager_id and not is_deleted and status='active' and is_active) then
      raise exception 'manager_not_active' using errcode='22023';
    end if;
    if exists(
      with recursive manager_chain(id,path) as (
        select p_manager_id,array[p_manager_id]::uuid[]
        union all
        select mr.manager_employee_id,c.path||mr.manager_employee_id
        from public.manager_relations mr join manager_chain c on c.id=mr.employee_id
        where mr.relation_type='primary' and mr.effective_to is null
          and not mr.manager_employee_id=any(c.path)
      ) select 1 from manager_chain where id=p_employee_id
    ) then raise exception 'manager_cycle_not_allowed' using errcode='22023'; end if;
  end if;
  update public.manager_relations set effective_to=current_date,updated_at=now()
  where employee_id=p_employee_id and relation_type='primary' and effective_to is null;
  if p_manager_id is not null then
    insert into public.manager_relations(
      employee_id,manager_employee_id,relation_type,effective_from,created_by
    ) values(p_employee_id,p_manager_id,'primary',current_date,auth.uid());
  end if;
  perform public.log_audit_event(
    'employee_manager_changed','people','warning','employees',p_employee_id,
    'تغيير المدير المباشر',jsonb_build_object('managerId',v_old_manager),
    jsonb_build_object('managerId',p_manager_id,'reason',trim(p_reason))
  );
  return jsonb_build_object('employeeId',p_employee_id,
    'previousManagerId',v_old_manager,'managerId',p_manager_id,'updatedAt',now());
end;
$$;

revoke all on function public.change_employee_manager_admin(uuid,uuid,text) from public,anon;
grant execute on function public.change_employee_manager_admin(uuid,uuid,text) to authenticated;

create or replace function public.get_release_governance_overview()
returns jsonb
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
begin
  if not(public.current_is_full_access() or public.has_any_permission(array[
    'system.release.read','system.release.manage','access.review.read','access.review.manage',
    'access.break_glass.request','access.break_glass.approve','privacy.request.manage',
    'system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage'
  ])) then raise exception 'governance overview denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'policies',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'platform',p.platform,'environment',p.environment,'latestVersion',p.latest_version,
      'latestBuild',p.latest_build,'minSupportedVersion',p.min_supported_version,
      'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
      'maintenance',p.maintenance_enabled,'maintenanceMessageAr',p.maintenance_message_ar,
      'updateMessageAr',p.update_message_ar,'storeUrl',p.store_url,
      'rolloutPercent',p.rollout_percent,'updatedAt',coalesce(p.updated_at,p.created_at)
    ) order by p.platform,p.environment) from public.app_release_policies p),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'installationId',d.installation_id,'userId',d.user_id,'employeeId',d.employee_id,
      'employeeName',coalesce(e.full_name_ar,e.full_name_en),'employeeCode',e.employee_code,
      'platform',d.platform,'deviceName',d.device_name,'deviceModel',d.device_model,
      'osVersion',d.os_version,'appVersion',d.app_version,'appBuild',d.app_build,
      'environment',d.environment,'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
    ) order by d.last_seen_at desc) from public.managed_devices d left join public.employees e on e.id=d.employee_id),'[]'::jsonb),
    'accessReviews',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,'dueAt',c.due_at,
      'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
      'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
      'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
    ) order by c.created_at desc) from public.access_review_campaigns c),'[]'::jsonb),
    'reviewItems',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,'userId',i.user_id,
      'roleId',i.role_id,'employeeName',coalesce(e.full_name_ar,e.full_name_en),
      'employeeCode',e.employee_code,'roleName',r.name_ar,'decision',i.decision,
      'decisionReason',i.decision_reason,'decidedAt',i.decided_at,'snapshot',i.snapshot
    ) order by i.created_at desc) from public.access_review_items i
      left join public.profiles pr on pr.id=i.user_id left join public.employees e on e.id=pr.employee_id
      join public.roles r on r.id=i.role_id where i.decision='pending'),'[]'::jsonb),
    'breakGlass',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'targetUserId',b.target_user_id,'targetName',coalesce(e.full_name_ar,e.full_name_en),
      'targetCode',e.employee_code,'roleId',b.requested_role_id,'roleName',r.name_ar,
      'durationMinutes',b.duration_minutes,'reason',b.reason,'status',b.status,
      'requestedBy',b.requested_by,'requestedAt',b.requested_at,'activeUntil',b.active_until
    ) order by b.requested_at desc) from public.break_glass_requests b
      left join public.profiles pr on pr.id=b.target_user_id left join public.employees e on e.id=pr.employee_id
      join public.roles r on r.id=b.requested_role_id),'[]'::jsonb),
    'privacyRequests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'requestNumber',p.request_number,'requesterUserId',p.requester_user_id,
      'employeeName',coalesce(e.full_name_ar,e.full_name_en),'employeeCode',e.employee_code,
      'requestType',p.request_type,'details',p.details,'status',p.status,
      'dueAt',p.due_at,'decisionReason',p.decision_reason,'createdAt',p.created_at
    ) order by p.created_at desc) from public.privacy_requests p
      left join public.employees e on e.id=p.requester_employee_id),'[]'::jsonb),
    'outbox',jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles',coalesce((select jsonb_agg(jsonb_build_object(
      'id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access
    ) order by r.name_ar) from public.roles r),'[]'::jsonb),
    'users',coalesce((select jsonb_agg(jsonb_build_object(
      'userId',p.id,'employeeId',p.employee_id,'name',coalesce(e.full_name_ar,e.full_name_en),
      'employeeCode',e.employee_code,'status',p.status
    ) order by coalesce(e.full_name_ar,e.full_name_en)) from public.profiles p
      left join public.employees e on e.id=p.employee_id),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_release_governance_overview() from public,anon;
grant execute on function public.get_release_governance_overview() to authenticated;

notify pgrst, 'reload schema';
