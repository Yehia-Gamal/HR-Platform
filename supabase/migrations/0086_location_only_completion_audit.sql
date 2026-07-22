-- 0086: Explicitly complete video-mode requests when the employee chooses the
-- permitted location-only fallback. Preserve that decision in metadata/audit.

create or replace function public.complete_my_live_location_request(p_request_id uuid)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.live_location_requests;
  v_mode text;
  v_video_waived boolean := false;
begin
  select * into v_row
  from public.live_location_requests
  where id = p_request_id and employee_id = v_me
  for update;
  if not found then
    raise exception 'active request not found' using errcode = 'P0002';
  end if;
  if v_row.status not in ('accepted', 'active') or v_row.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  v_mode := coalesce(v_row.metadata->>'mode', 'snapshot');
  if v_mode in ('video_5s', 'location_video') then
    if not exists (
      select 1 from public.employee_locations
      where live_request_id = p_request_id and employee_id = v_me
    ) then
      raise exception 'location point required before video waiver' using errcode = '22023';
    end if;
    v_video_waived := true;
  end if;

  update public.live_location_requests
  set status = 'completed',
      expires_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'videoWaived', v_video_waived,
        'completionMode', case when v_video_waived then 'location_only' else 'normal' end,
        'completedAt', now()
      )
  where id = p_request_id
  returning * into v_row;

  perform public.log_audit_event(
    'live_location_completed', 'security', 'info',
    'live_location_requests', p_request_id,
    case when v_video_waived then 'إكمال طلب الموقع دون فيديو' else 'إكمال طلب الموقع' end,
    null,
    jsonb_build_object(
      'mode', v_mode,
      'videoWaived', v_video_waived,
      'completionMode', case when v_video_waived then 'location_only' else 'normal' end
    )
  );
  return v_row;
end;
$$;

revoke execute on function public.complete_my_live_location_request(uuid) from public, anon;
grant execute on function public.complete_my_live_location_request(uuid) to authenticated;
notify pgrst, 'reload schema';
