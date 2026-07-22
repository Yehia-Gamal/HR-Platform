-- 0068: Live location UX fixes
-- 1. Remove mandatory reason from request_live_location (reason is now optional)
-- 2. Fix get_location_directory to show ALL active employees for full-access callers
--    (executive director was missing some employees due to can_access_employee scope)
-- 3. Update notification body to not mention reason

-- ── 1 & 3: request_live_location — reason optional, neutral notification ──────
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode        text,
  p_reason      text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_row           public.live_location_requests;
  v_target_user   uuid;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode = '42501';
  end if;
  if not public.can_access_employee(p_employee_id, 'live_location.request') then
    raise exception 'target outside permitted scope' using errcode = '42501';
  end if;
  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.employees where id = p_employee_id and status = 'active'
  ) then
    raise exception 'employee is not active' using errcode = 'P0002';
  end if;

  v_duration := case p_mode
    when 'snapshot'  then 1
    when 'video_5s'  then 2
    when 'track_5'   then 5
    when 'track_10'  then 10
    when 'track_15'  then 15
    when 'track_30'  then 30
    else null
  end;
  if v_duration is null then
    raise exception 'invalid request mode' using errcode = '22023';
  end if;
  if p_mode = 'video_5s' then v_video_seconds := 5; end if;

  if exists (
    select 1 from public.live_location_requests
    where employee_id = p_employee_id
      and status in ('pending','accepted','active')
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'employee already has an active location request' using errcode = '23505';
  end if;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  )
  values (
    p_employee_id, v_me, coalesce(nullif(trim(p_reason),''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes',
    v_duration,
    jsonb_build_object('mode', p_mode, 'videoSeconds', v_video_seconds),
    auth.uid()
  )
  returning * into v_row;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, created_by
    )
    values (
      v_target_user, p_employee_id,
      'طلب تحقق من الموقع',
      'طلب المدير التنفيذي التحقق من موقعك. يرجى الاستجابة.',
      'system', 'urgent',
      '/location-requests', 'live_location_request', v_row.id, auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'warning',
    'live_location_requests', v_row.id, 'طلب موقع حي', null,
    jsonb_build_object(
      'employeeId', p_employee_id, 'mode', p_mode,
      'duration', v_duration, 'reason', trim(coalesce(p_reason,''))
    )
  );
  return v_row;
end;
$$;

-- ── 2: get_location_directory — full-access callers see all active employees ──
create or replace function public.get_location_directory(
  p_search text    default null,
  p_limit  integer default 100
)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.request')) then
    raise exception 'live location request permission required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) order by q.full_name_ar)
    from (
      select
        e.id, e.full_name_ar, e.employee_code,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status
      from public.employees e
      left join public.job_titles  jt  on jt.id = e.job_title_id
      left join public.departments d   on d.id  = e.department_id
      left join lateral (
        select l.latitude, l.longitude, l.accuracy, l.recorded_at
        from public.employee_locations l
        where l.employee_id = e.id
        order by l.recorded_at desc limit 1
      ) last_point on true
      left join lateral (
        select r.id, r.status
        from public.live_location_requests r
        where r.employee_id = e.id
          and r.status in ('pending','accepted','active')
          and (r.expires_at is null or r.expires_at > now())
        order by r.requested_at desc limit 1
      ) active_req on true
      where e.status = 'active'
        and e.is_deleted = false
        and e.id is distinct from public.current_employee_id()
        -- Full-access callers (executive director) see everyone; others are
        -- scoped by can_access_employee as before.
        and (
          public.current_is_full_access()
          or public.can_access_employee(e.id, 'live_location.request')
        )
        and (
          coalesce(trim(p_search), '') = ''
          or e.full_name_ar    ilike '%' || trim(p_search) || '%'
          or e.employee_code   ilike '%' || trim(p_search) || '%'
        )
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.request_live_location(uuid,text,text)  from public;
grant  execute on function public.request_live_location(uuid,text,text)  to authenticated;
revoke execute on function public.get_location_directory(text,integer)   from public;
grant  execute on function public.get_location_directory(text,integer)   to authenticated;
