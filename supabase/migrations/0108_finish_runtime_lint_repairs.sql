-- 0108: Finish catalog-column and overload repairs reported by plpgsql_check.

create or replace function public.upsert_my_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user_id uuid:=auth.uid(); v_token text:=trim(p_fcm_token);
begin
  if v_user_id is null then raise exception 'unauthorized' using errcode='42501'; end if;
  if length(v_token)<16 then raise exception 'token_too_short' using errcode='22023'; end if;
  if p_platform not in ('android','ios','web') then raise exception 'invalid_platform' using errcode='22023'; end if;
  insert into public.push_subscriptions(user_id,fcm_token,platform,is_active,last_used_at)
  values(v_user_id,v_token,p_platform,true,now())
  on conflict(user_id,fcm_token) where fcm_token is not null do update set
    is_active=true,platform=excluded.platform,last_used_at=now();
end;
$$;

revoke all on function public.upsert_my_push_token(text,text) from public,anon,authenticated;
grant execute on function public.upsert_my_push_token(text,text) to authenticated;

create or replace function public.get_my_offboarding_portal()
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp
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
      'assignedAt',aa.handed_over_at,'status',aa.status
    ) order by aa.handed_over_at desc) from public.asset_assignments aa
      join public.asset_inventory a on a.id=aa.asset_id
      where aa.employee_id=v_emp and aa.status='assigned'),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_offboarding_portal() from public,anon;
grant execute on function public.get_my_offboarding_portal() to authenticated;

create or replace function public.change_employee_manager_admin(
  p_employee_id uuid,
  p_manager_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
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
    'تغيير المدير المباشر',trim(p_reason),jsonb_build_object(
      'previousManagerId',v_old_manager,'managerId',p_manager_id,'reason',trim(p_reason))
  );
  return jsonb_build_object('employeeId',p_employee_id,
    'previousManagerId',v_old_manager,'managerId',p_manager_id,'updatedAt',now());
end;
$$;

revoke all on function public.change_employee_manager_admin(uuid,uuid,text) from public,anon;
grant execute on function public.change_employee_manager_admin(uuid,uuid,text) to authenticated;

notify pgrst, 'reload schema';
