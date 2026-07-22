-- 0087: Exact deep-link resolver with a strict kind allowlist and live-location
-- ownership/scope authorization. Accept raw UUIDs used by FCM and legacy
-- kind-prefixed action IDs used by the action center.

create or replace function public.resolve_mobile_action_target(
  p_action_id text,
  p_kind text
)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
begin
  if v_kind not in (
    'request', 'kpi', 'decision', 'live_location_request'
  ) then
    raise exception 'unsupported action kind' using errcode = '22023';
  end if;

  if position(v_kind || '-' in lower(v_raw)) = 1 then
    v_raw := substring(v_raw from length(v_kind) + 2);
  end if;
  begin
    v_uuid := v_raw::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  if v_kind <> 'live_location_request' then
    return public.get_mobile_action_target(v_kind || '-' || v_uuid::text, v_kind);
  end if;

  select * into v_req from public.live_location_requests where id = v_uuid;
  if not found then
    raise exception 'action target not found' using errcode = 'P0002';
  end if;
  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
  ) then
    raise exception 'action target access denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'kind', v_kind,
    'recordId', v_uuid,
    'mobileRoute', 'live_location_request'
  );
end;
$$;

revoke execute on function public.resolve_mobile_action_target(text, text) from public, anon;
grant execute on function public.resolve_mobile_action_target(text, text) to authenticated;
notify pgrst, 'reload schema';
