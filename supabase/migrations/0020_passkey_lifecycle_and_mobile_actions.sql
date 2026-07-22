-- Migration 0020: Complete passkey lifecycle metadata and mobile action routing contracts.
-- This migration extends the existing canonical tables; it does not create a parallel model.

begin;

alter table public.webauthn_challenges
  add column if not exists options_json jsonb,
  add column if not exists relying_party_id text;

alter table public.passkey_credentials
  add column if not exists webauthn_user_id text,
  add column if not exists credential_device_type text,
  add column if not exists credential_backed_up boolean not null default false;

create index if not exists idx_passkey_webauthn_user
  on public.passkey_credentials(webauthn_user_id)
  where webauthn_user_id is not null;

comment on column public.passkey_credentials.public_key is
  'WebAuthn credential public key in COSE byte form, encoded as base64url without padding.';
comment on column public.webauthn_challenges.options_json is
  'Exact server-authored PublicKeyCredential options used for verification; never client-authored.';

-- Only the service role may write or consume challenges/credentials. Existing RLS remains read-only
-- for owners where explicitly allowed. Edge Functions use service_role after validating the user JWT.
revoke insert, update, delete on public.webauthn_challenges from authenticated;
revoke insert, update, delete on public.passkey_credentials from authenticated;

-- A compact mobile route descriptor avoids hard-coding web URLs inside Flutter.
create or replace function public.get_mobile_action_target(p_action_id text, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'invalid action identifier' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$$;
revoke execute on function public.get_mobile_action_target(text,text) from public;
grant execute on function public.get_mobile_action_target(text,text) to authenticated;

commit;
