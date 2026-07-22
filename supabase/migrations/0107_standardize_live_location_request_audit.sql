-- 0107: Preserve independent requests while restoring the canonical dotted
-- audit event consumed by the audit UI and V10 acceptance contract.

create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text,
  p_reason text default ''
)
returns public.live_location_requests
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
  v_me uuid:=public.current_employee_id();
  v_duration integer;
  v_video_seconds integer:=0;
  v_needs_video boolean:=false;
  v_row public.live_location_requests;
  v_target_user uuid;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not(public.current_is_full_access() or public.can_access_employee(p_employee_id,'live_location.request')) then
    raise exception 'target outside permitted scope' using errcode='42501';
  end if;
  if p_employee_id=v_me then raise exception 'cannot request own location' using errcode='22023'; end if;
  if not exists(select 1 from public.employees where id=p_employee_id
    and status in ('active','invited','onboarding') and user_id is not null) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;
  if exists(select 1 from public.live_location_requests
    where requested_by=v_me and employee_id=p_employee_id
      and requested_at>now()-interval '30 seconds') then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;
  v_duration:=case p_mode when 'snapshot' then 1 when 'video_5s' then 2
    when 'location_video' then 2 when 'track_5' then 5 when 'track_10' then 10
    when 'track_15' then 15 when 'track_30' then 30 else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;
  if p_mode in ('video_5s','location_video') then v_video_seconds:=5; v_needs_video:=true; end if;
  insert into public.live_location_requests(
    employee_id,requested_by,reason,status,purpose,requested_at,expires_at,
    duration_minutes,metadata,created_by
  ) values(
    p_employee_id,v_me,coalesce(nullif(trim(p_reason),''),null),'pending','verification',
    now(),now()+interval '5 minutes',v_duration,jsonb_build_object(
      'mode',p_mode,'videoSeconds',v_video_seconds,'needsPoint',p_mode<>'video_5s',
      'needsVideo',v_needs_video),auth.uid()
  ) returning * into v_row;
  update public.live_location_requests
  set metadata=metadata||jsonb_build_object('requestId',v_row.id)
  where id=v_row.id returning * into v_row;
  select user_id into v_target_user from public.employees where id=p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id,recipient_employee_id,title,body,category,priority,
      action_url,entity_type,entity_id,metadata,created_by
    ) values(
      v_target_user,p_employee_id,'طلب تحقق من الموقع',
      'المدير يطلب التحقق من موقعك. يرجى الاستجابة فوراً.','system','urgent',
      'ahlashabab://action/live_location_request/'||v_row.id::text,
      'live_location_request',v_row.id,jsonb_build_object(
        'fullScreen',true,'kind','live_location_request','requestId',v_row.id,
        'entityId',v_row.id,'deepLink','ahlashabab://action/live_location_request/'||v_row.id::text,
        'channel','urgent_location_v4'),auth.uid()
    );
  end if;
  perform public.log_audit_event(
    'live_location.requested','security','warning','live_location_requests',v_row.id,
    'طلب موقع حي',null,jsonb_build_object(
      'mode',p_mode,'employeeId',p_employee_id,'requestId',v_row.id)
  );
  perform public.nudge_notification_dispatcher();
  return v_row;
end;
$$;

revoke all on function public.request_live_location(uuid,text,text) from public,anon;
grant execute on function public.request_live_location(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
