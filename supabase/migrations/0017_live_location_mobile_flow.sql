begin;

-- Canonical, audited live-location workflow. Clients cannot write sensitive location
-- request, point or video metadata tables directly; all mutations go through these RPCs.

-- Private video bucket (objects are addressed as employee_id/request_id/file.mp4).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('live-location-videos', 'live-location-videos', false, 15728640, array['video/mp4','video/quicktime'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Remove broad legacy mutation policies. Read access is rewritten with canonical permissions.
drop policy if exists live_loc_req_write on public.live_location_requests;
drop policy if exists live_loc_req_respond on public.live_location_requests;
drop policy if exists live_vid_meta_write on public.live_location_videos_meta;
drop policy if exists emp_locations_insert on public.employee_locations;
drop policy if exists emp_locations_manage on public.employee_locations;

drop policy if exists live_loc_req_select on public.live_location_requests;
create policy live_loc_req_select on public.live_location_requests
for select to authenticated using (
  employee_id = public.current_employee_id()
  or requested_by = public.current_employee_id()
  or public.can_access_employee(employee_id, 'live_location.request')
  or public.can_access_employee(employee_id, 'live_location.view_response')
);

drop policy if exists emp_locations_select on public.employee_locations;
create policy emp_locations_select on public.employee_locations
for select to authenticated using (
  employee_id = public.current_employee_id()
  or public.can_access_employee(employee_id, 'live_location.view_response')
);

drop policy if exists live_vid_meta_select on public.live_location_videos_meta;
create policy live_vid_meta_select on public.live_location_videos_meta
for select to authenticated using (
  employee_id = public.current_employee_id()
  or public.can_access_employee(employee_id, 'live_location.view_response')
);

-- Storage policies.
drop policy if exists live_location_video_upload on storage.objects;
create policy live_location_video_upload on storage.objects
for insert to authenticated with check (
  bucket_id = 'live-location-videos'
  and split_part(name, '/', 1) = public.current_employee_id()::text
);

drop policy if exists live_location_video_read on storage.objects;
create policy live_location_video_read on storage.objects
for select to authenticated using (
  bucket_id = 'live-location-videos'
  and (
    split_part(name, '/', 1) = public.current_employee_id()::text
    or exists (
      select 1 from public.live_location_videos_meta m
      where m.storage_path = name
        and public.can_access_employee(m.employee_id, 'live_location.view_response')
    )
  )
);

drop policy if exists live_location_video_delete on storage.objects;
create policy live_location_video_delete on storage.objects
for delete to authenticated using (
  bucket_id = 'live-location-videos'
  and (
    split_part(name, '/', 1) = public.current_employee_id()::text
    or public.current_is_full_access()
    or public.has_permission('live_location.manage_retention')
  )
);

create or replace function public.get_location_directory(p_search text default null, p_limit integer default 100)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.request')) then
    raise exception 'live location request permission required' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'name', q.full_name_ar, 'employeeCode', q.employee_code,
      'jobTitle', q.job_title, 'department', q.department,
      'lastLatitude', q.latitude, 'lastLongitude', q.longitude,
      'lastAccuracy', q.accuracy, 'lastRecordedAt', q.recorded_at,
      'activeRequestId', q.active_request_id, 'activeRequestStatus', q.active_request_status
    ) order by q.full_name_ar)
    from (
      select e.id, e.full_name_ar, e.employee_code, jt.name job_title, d.name department,
        last_point.latitude, last_point.longitude, last_point.accuracy, last_point.recorded_at,
        active_req.id active_request_id, active_req.status active_request_status
      from public.employees e
      left join public.job_titles jt on jt.id=e.job_title_id
      left join public.departments d on d.id=e.department_id
      left join lateral (
        select l.latitude,l.longitude,l.accuracy,l.recorded_at
        from public.employee_locations l where l.employee_id=e.id order by l.recorded_at desc limit 1
      ) last_point on true
      left join lateral (
        select r.id,r.status from public.live_location_requests r
        where r.employee_id=e.id and r.status in ('pending','accepted','active')
          and (r.expires_at is null or r.expires_at>now())
        order by r.requested_at desc limit 1
      ) active_req on true
      where e.status='active'
        and e.id is distinct from public.current_employee_id()
        and public.can_access_employee(e.id,'live_location.request')
        and (coalesce(trim(p_search),'')='' or e.full_name_ar ilike '%'||trim(p_search)||'%' or e.employee_code ilike '%'||trim(p_search)||'%')
      order by e.full_name_ar limit greatest(1,least(coalesce(p_limit,100),300))
    ) q
  ),'[]'::jsonb);
end;
$$;
revoke execute on function public.get_location_directory(text,integer) from public;
grant execute on function public.get_location_directory(text,integer) to authenticated;

create or replace function public.request_live_location(p_employee_id uuid, p_mode text, p_reason text)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_duration integer;
  v_video_seconds integer := 0;
  v_row public.live_location_requests;
  v_target_user uuid;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not public.can_access_employee(p_employee_id,'live_location.request') then raise exception 'target outside permitted scope' using errcode='42501'; end if;
  if p_employee_id=v_me then raise exception 'cannot request own location' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists(select 1 from public.employees where id=p_employee_id and status='active') then raise exception 'employee is not active' using errcode='P0002'; end if;

  v_duration := case p_mode when 'snapshot' then 1 when 'video_5s' then 2 when 'track_5' then 5 when 'track_10' then 10 when 'track_15' then 15 when 'track_30' then 30 else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;
  if p_mode='video_5s' then v_video_seconds:=5; end if;

  if exists(select 1 from public.live_location_requests where employee_id=p_employee_id and status in ('pending','accepted','active') and (expires_at is null or expires_at>now())) then
    raise exception 'employee already has an active location request' using errcode='23505';
  end if;

  insert into public.live_location_requests(employee_id,requested_by,reason,status,purpose,requested_at,expires_at,duration_minutes,metadata,created_by)
  values(p_employee_id,v_me,trim(p_reason),'pending','verification',now(),now()+interval '5 minutes',v_duration,
    jsonb_build_object('mode',p_mode,'videoSeconds',v_video_seconds),auth.uid()) returning * into v_row;

  select user_id into v_target_user from public.employees where id=p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,created_by)
    values(v_target_user,p_employee_id,'طلب تحقق من الموقع','تم إرسال طلب موقع بسبب: '||trim(p_reason),'system','urgent','/location-requests','live_location_request',v_row.id,auth.uid());
  end if;
  perform public.log_audit_event('live_location.requested','security','warning','live_location_requests',v_row.id,'طلب موقع حي',null,jsonb_build_object('employeeId',p_employee_id,'mode',p_mode,'duration',v_duration,'reason',trim(p_reason)));
  return v_row;
end;
$$;
revoke execute on function public.request_live_location(uuid,text,text) from public;
grant execute on function public.request_live_location(uuid,text,text) to authenticated;

create or replace function public.get_my_live_location_requests(p_limit integer default 30)
returns jsonb
language sql stable security invoker set search_path=public,pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'requesterName',q.requester_name,'reason',q.reason,'status',q.effective_status,
    'mode',q.mode,'durationMinutes',q.duration_minutes,'requestedAt',q.requested_at,
    'expiresAt',q.expires_at
  ) order by q.requested_at desc),'[]'::jsonb)
  from (
    select r.id,req.full_name_ar requester_name,r.reason,
      case when r.status in ('pending','accepted','active') and r.expires_at<now() then 'expired' else r.status end effective_status,
      coalesce(r.metadata->>'mode','snapshot') mode,r.duration_minutes,r.requested_at,r.expires_at
    from public.live_location_requests r left join public.employees req on req.id=r.requested_by
    where r.employee_id=public.current_employee_id()
    order by r.requested_at desc limit greatest(1,least(coalesce(p_limit,30),100))
  ) q;
$$;
grant execute on function public.get_my_live_location_requests(integer) to authenticated;

create or replace function public.respond_live_location_request(p_request_id uuid, p_accept boolean)
returns public.live_location_requests
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_me uuid:=public.current_employee_id(); v_row public.live_location_requests;
begin
  select * into v_row from public.live_location_requests where id=p_request_id for update;
  if not found or v_row.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  if v_row.status<>'pending' or v_row.expires_at<=now() then raise exception 'request is no longer pending' using errcode='22023'; end if;
  if p_accept then
    update public.live_location_requests set status='active',responded_at=now(),starts_at=now(),expires_at=now()+make_interval(mins=>duration_minutes) where id=p_request_id returning * into v_row;
  else
    update public.live_location_requests set status='rejected',responded_at=now() where id=p_request_id returning * into v_row;
  end if;
  perform public.log_audit_event(case when p_accept then 'live_location.accepted' else 'live_location.rejected' end,'security','info','live_location_requests',v_row.id,'استجابة الموظف لطلب الموقع',null,jsonb_build_object('accepted',p_accept));
  return v_row;
end;
$$;
revoke execute on function public.respond_live_location_request(uuid,boolean) from public;
grant execute on function public.respond_live_location_request(uuid,boolean) to authenticated;

create or replace function public.submit_live_location_point(p_request_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_altitude double precision default null,p_speed double precision default null,p_heading double precision default null,p_is_mock boolean default false)
returns public.employee_locations
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_me uuid:=public.current_employee_id(); v_req public.live_location_requests; v_row public.employee_locations; v_mode text;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'invalid coordinates' using errcode='22023'; end if;
  if p_accuracy is null or p_accuracy<0 or p_accuracy>10000 then raise exception 'invalid accuracy' using errcode='22023'; end if;
  select * into v_req from public.live_location_requests where id=p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status<>'active' or v_req.expires_at<=now() then raise exception 'location session is not active' using errcode='22023'; end if;
  insert into public.employee_locations(employee_id,live_request_id,latitude,longitude,accuracy,altitude,speed,heading,source,is_mock,recorded_at,created_by)
  values(v_me,p_request_id,p_latitude,p_longitude,p_accuracy,p_altitude,p_speed,p_heading,'mobile',coalesce(p_is_mock,false),now(),auth.uid()) returning * into v_row;
  v_mode:=coalesce(v_req.metadata->>'mode','snapshot');
  if v_mode='snapshot' then update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id; end if;
  return v_row;
end;
$$;
revoke execute on function public.submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean) from public;
grant execute on function public.submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean) to authenticated;

create or replace function public.register_live_location_video(p_request_id uuid,p_storage_path text,p_duration_seconds integer,p_size_bytes bigint,p_mime_type text,p_latitude double precision,p_longitude double precision,p_accuracy double precision)
returns public.live_location_videos_meta
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_me uuid:=public.current_employee_id(); v_req public.live_location_requests; v_row public.live_location_videos_meta;
begin
  select * into v_req from public.live_location_requests where id=p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status<>'active' or v_req.expires_at<=now() or v_req.metadata->>'mode'<>'video_5s' then raise exception 'video request is not active' using errcode='22023'; end if;
  if p_duration_seconds not between 4 and 7 then raise exception 'video must be approximately five seconds' using errcode='22023'; end if;
  if p_size_bytes<=0 or p_size_bytes>15728640 then raise exception 'invalid video size' using errcode='22023'; end if;
  if p_storage_path not like v_me::text||'/'||p_request_id::text||'/%' then raise exception 'invalid storage path' using errcode='42501'; end if;
  insert into public.live_location_videos_meta(live_request_id,employee_id,storage_path,storage_bucket,duration_seconds,size_bytes,mime_type,captured_lat,captured_lng,captured_accuracy,captured_at,status,created_by)
  values(p_request_id,v_me,p_storage_path,'live-location-videos',p_duration_seconds,p_size_bytes,p_mime_type,p_latitude,p_longitude,p_accuracy,now(),'ready',auth.uid()) returning * into v_row;
  update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id;
  perform public.log_audit_event('live_location.video_registered','security','warning','live_location_videos_meta',v_row.id,'تسجيل فيديو تحقق حي',null,jsonb_build_object('requestId',p_request_id,'durationSeconds',p_duration_seconds));
  return v_row;
end;
$$;
revoke execute on function public.register_live_location_video(uuid,text,integer,bigint,text,double precision,double precision,double precision) from public;
grant execute on function public.register_live_location_video(uuid,text,integer,bigint,text,double precision,double precision,double precision) to authenticated;


create or replace function public.complete_my_live_location_request(p_request_id uuid)
returns public.live_location_requests
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_me uuid:=public.current_employee_id(); v_row public.live_location_requests;
begin
  update public.live_location_requests
  set status='completed', expires_at=least(coalesce(expires_at,now()),now())
  where id=p_request_id and employee_id=v_me and status in ('accepted','active')
  returning * into v_row;
  if not found then raise exception 'active request not found' using errcode='P0002'; end if;
  return v_row;
end;
$$;
revoke execute on function public.complete_my_live_location_request(uuid) from public;
grant execute on function public.complete_my_live_location_request(uuid) to authenticated;


create or replace function public.get_employee_home()
returns jsonb
language sql stable security invoker set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'pendingRequests',(select count(*) from public.requests where employee_id=public.current_employee_id() and status='pending'),
    'activeTasks',(select count(*) from public.tasks where assignee_employee_id=public.current_employee_id() and status not in ('done','cancelled')),
    'kpiStage',(select current_stage from public.kpi_evaluations where employee_id=public.current_employee_id() order by created_at desc limit 1),
    'unreadNotifications',(select count(*) from public.notifications where recipient_user_id=auth.uid() and is_read=false),
    'unreadOfficial',(select count(*) from public.decision_recipients dr join public.administrative_decisions d on d.id=dr.decision_id left join public.decision_reads rr on rr.decision_id=d.id and rr.employee_id=dr.employee_id where dr.employee_id=public.current_employee_id() and d.status='published' and coalesce(rr.acknowledged,false)=false),
    'pendingLocationRequests',(select count(*) from public.live_location_requests where employee_id=public.current_employee_id() and status='pending' and expires_at>now()),
    'lastUpdatedAt',now()
  );
$$;
grant execute on function public.get_employee_home() to authenticated;

commit;
