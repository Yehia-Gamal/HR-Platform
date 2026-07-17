-- 0070: Allow requester to cancel an active location request
-- Executive director can cancel a pending/accepted request to resend a new one.

create or replace function public.cancel_location_request_as_requester(
  p_request_id uuid
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me  uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  select * into v_req from public.live_location_requests where id = p_request_id;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  -- Only the original requester OR a full-access user can cancel.
  if v_req.requested_by is distinct from v_me and not public.current_is_full_access() then
    raise exception 'can only cancel your own location requests' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'accepted') then
    raise exception 'request cannot be cancelled in its current status' using errcode = '22023';
  end if;

  update public.live_location_requests
    set status     = 'rejected',
        expires_at = now(),
        metadata   = jsonb_set(
          coalesce(metadata, '{}'::jsonb),
          '{cancelledByRequester}',
          'true'
        )
    where id = p_request_id;

  perform public.log_audit_event(
    'live_location.request_cancelled', 'security', 'info',
    'live_location_requests', p_request_id,
    'إلغاء طلب الموقع من قِبل المدير', null,
    jsonb_build_object('requestId', p_request_id, 'cancelledBy', v_me)
  );
end;
$$;

revoke execute on function public.cancel_location_request_as_requester(uuid) from public;
grant  execute on function public.cancel_location_request_as_requester(uuid) to authenticated;
