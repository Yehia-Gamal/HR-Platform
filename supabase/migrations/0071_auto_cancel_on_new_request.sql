-- 0071: Auto-cancel previous active location request when a new one is sent
-- Replaces the duplicate-check exception with a silent auto-cancel so the
-- executive director can send a new request at any time.

-- Drop then recreate to avoid signature conflicts between migrations 0067/0068
drop function if exists public.request_live_location(uuid, text, text);

create function public.request_live_location(
  p_employee_id uuid,
  p_mode        text,
  p_reason      text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me            uuid    := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_row           public.live_location_requests;
  v_target_user   uuid;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode = '42501';
  end if;
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id, 'live_location.request')) then
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
    when 'snapshot'       then 1
    when 'video_5s'       then 2
    when 'location_video' then 2
    when 'track_5'        then 5
    when 'track_10'       then 10
    when 'track_15'       then 15
    when 'track_30'       then 30
    else null
  end;
  if v_duration is null then
    raise exception 'invalid request mode' using errcode = '22023';
  end if;
  if p_mode in ('video_5s', 'location_video') then
    v_video_seconds := 5;
  end if;

  -- إلغاء أي طلب نشط سابق للموظف تلقائياً (بدلاً من رفض الطلب الجديد)
  update public.live_location_requests
     set status     = 'rejected',
         expires_at = now(),
         metadata   = jsonb_set(
                        coalesce(metadata, '{}'::jsonb),
                        '{autoCancelledByNewRequest}', 'true'
                      )
   where employee_id = p_employee_id
     and status in ('pending', 'accepted', 'active')
     and (expires_at is null or expires_at > now());

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  )
  values (
    p_employee_id, v_me,
    coalesce(nullif(trim(p_reason), ''), null),
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
      'طلب المدير التنفيذي التحقق من موقعك. يرجى الاستجابة فوراً.',
      'system', 'urgent',
      '/location-requests', 'live_location_request', v_row.id, auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location_requested', 'live_location_requests', v_row.id,
    jsonb_build_object('mode', p_mode, 'employeeId', p_employee_id)
  );

  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$$;

revoke execute on function public.request_live_location(uuid, text, text) from public;
grant  execute on function public.request_live_location(uuid, text, text) to authenticated;
