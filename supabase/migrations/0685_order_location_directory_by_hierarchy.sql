-- ==============================================================================
-- Migration 0685: Order Location Directory by Hierarchy & Exclude Clinic Medical Staff
-- ==============================================================================
-- 1) ترتيب دليل طلب المواقع حسب الهيكل الإداري المعتمد:
--    السكرتير التنفيذي (يحيى السبع) → أوبريشن 1 (أبو عمار) → أوبريشن 2 (ياسر) → باقي المديرين → باقي الموظفين
-- 2) استبعاد تيم العيادات (الطاقم الطبي / بنات العيادات) نهائياً من دليل طلب المواقع،
--    ومن طلب الموقع الجماعي، ومن أي طلب موقع فردي، حفاظاً على الخصوصية وطبيعة عملهن في مقار ثابتة.
-- ==============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) get_location_directory: استبعاد الطاقم الطبي والترتيب بالهيكل الإداري
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_location_directory(p_search text default null::text, p_limit integer default 100)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_search text;
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.request')) then
    raise exception 'live location request permission required' using errcode = '42501';
  end if;

  v_search := nullif(trim(coalesce(p_search, '')), '');

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'photoUrl',            q.photo_url,
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) order by q.hierarchy_rank, q.full_name_ar)
    from (
      select
        e.id, e.full_name_ar, e.employee_code, e.photo_url,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status,
        public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) as hierarchy_rank
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
      where e.status in ('active', 'invited', 'onboarding')
        and e.is_deleted = false
        and e.id is distinct from public.current_employee_id()
        and e.user_id is not null
        and not public.is_employee_executive(e.id)  -- استبعاد المدير التنفيذي
        and not public.is_employee_isolated(e.id)   -- استبعاد الموظفين المعزولين
        and not public.employee_blocks_inbound_alerts(e.id)  -- استبعاد طاقم العيادات
        and public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) <> 7 -- استبعاد الطاقم الطبي للعيادات قطيعاً
        and (
          public.current_is_full_access()
          or public.can_access_employee(e.id, 'live_location.request')
        )
        and (
          v_search is null
          or e.full_name_ar  ilike '%' || public.escape_ilike(v_search) || '%'
          or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%'
        )
      order by public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name), e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_location_directory(text, integer) from public, anon;
grant execute on function public.get_location_directory(text, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) request_live_location_broadcast: استبعاد الطاقم الطبي من طلب الموقع الجماعي
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.request_live_location_broadcast(
  p_mode text default 'snapshot'::text,
  p_reason text default 'تحقق ميداني جماعي'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me            uuid := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_needs_point   boolean := true;
  v_needs_video   boolean := false;
  v_target        record;
  v_row           public.live_location_requests;
  v_created       integer := 0;
  v_items         jsonb := '[]'::jsonb;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_permission('live_location.request')) then
    raise exception 'live location request permission required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required' using errcode='22023'; end if;

  v_duration := case p_mode
    when 'snapshot'       then 1
    when 'video_5s'       then 2
    when 'location_video' then 2
    when 'track_5'        then 5
    when 'track_10'       then 10
    when 'track_15'       then 15
    when 'track_30'       then 30
    else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;

  if p_mode = 'video_5s' then
    v_video_seconds := 5; v_needs_point := false; v_needs_video := true;
  elsif p_mode = 'location_video' then
    v_video_seconds := 5; v_needs_point := true;  v_needs_video := true;
  end if;

  for v_target in
    select e.*
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
    where e.status = 'active'
      and e.is_deleted = false
      and e.id <> v_me
      and e.user_id is not null
      and not public.is_employee_executive(e.id)
      and not public.is_employee_isolated(e.id)
      and not public.employee_blocks_inbound_alerts(e.id)
      and public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) <> 7 -- استبعاد الطاقم الطبي
      and not exists (
        select 1 from public.live_location_requests r
        where r.employee_id = e.id
          and r.status in ('pending', 'accepted', 'active')
          and (r.expires_at is null or r.expires_at > now())
      )
  loop
    insert into public.live_location_requests (
      employee_id, requested_by, reason, status, purpose,
      requested_at, expires_at, duration_minutes, metadata, created_by
    ) values (
      v_target.id, v_me, p_reason, 'pending', 'verification',
      now(), now() + interval '5 minutes', v_duration,
      jsonb_build_object(
        'mode', p_mode,
        'videoSeconds', v_video_seconds,
        'needsPoint', v_needs_point,
        'needsVideo', v_needs_video,
        'isTracking', false,
        'broadcast', true
      ),
      auth.uid()
    )
    returning * into v_row;

    v_created := v_created + 1;
    v_items := v_items || jsonb_build_object(
      'requestId', v_row.id,
      'employeeId', v_target.id,
      'name', v_target.full_name_ar
    );
  end loop;

  return jsonb_build_object(
    'createdCount', v_created,
    'items', v_items
  );
end;
$function$;

revoke all on function public.request_live_location_broadcast(text, text) from public, anon;
grant execute on function public.request_live_location_broadcast(text, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) request_live_location: حظر طلب الموقع من الطاقم الطبي للعيادات
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot'::text,
  p_reason text default ''::text
)
returns live_location_requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
  v_deep_link text;
  v_target_name text;
  v_target_title text;
  v_target_dept text;
  v_rank integer;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode='42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['executive', 'executive-director'])
    or public.has_permission('live_location.request')
  ) then
    raise exception 'live location request permission required' using errcode='42501';
  end if;

  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode='22023';
  end if;

  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  -- فحص هل الموظف المستهدف من الطاقم الطبي للعيادات (الرتبة 7 أو معزول)
  select e.full_name_ar, jt.name, d.name, e.user_id
    into v_target_name, v_target_title, v_target_dept, v_target_user
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
   where e.id = p_employee_id;

  v_rank := public.get_employee_hierarchy_rank(v_target_name, v_target_title, v_target_dept);

  if v_rank = 7 or public.is_employee_isolated(p_employee_id) or public.employee_blocks_inbound_alerts(p_employee_id) then
    raise exception 'لا يمكن طلب الموقع من أفراد الطاقم الطبي للعيادات' using errcode='22023';
  end if;

  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees
    where id = p_employee_id and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;

  -- مهلة 30 ثانية
  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = p_employee_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    p_employee_id, v_me, coalesce(nullif(trim(p_reason), ''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V17'
    ),
    auth.uid()
  )
  returning * into v_req;

  update public.live_location_requests
     set metadata = metadata || jsonb_build_object('requestId', v_req.id)
   where id = v_req.id
  returning * into v_req;

  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by
    ) values (
      v_target_user, p_employee_id,
      'طلب موقع عاجل',
      'طلب موقع عاجل لمتابعة مسار العمل. يرجى الضغط للموافقة.',
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id,
      jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v6',
        'deepLink', v_deep_link
      ),
      auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'طلب موقع حي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id)
  );

  return v_req;
end;
$function$;

revoke all on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated, service_role;

commit;
