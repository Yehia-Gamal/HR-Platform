begin;

-- Passkey device self-service + personal attendance history.
-- Extends the canonical credential and attendance tables; no parallel model.

create index if not exists idx_passkey_credentials_owner_created
  on public.passkey_credentials(user_id, employee_id, created_at desc);

create index if not exists idx_attendance_events_employee_recent
  on public.attendance_events(employee_id, event_at desc);

create or replace function public.revoke_my_passkey(
  p_credential_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_credential public.passkey_credentials;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode='42501';
  end if;

  select * into v_credential
  from public.passkey_credentials
  where id=p_credential_id
    and user_id=auth.uid()
    and employee_id=v_employee_id
  for update;

  if v_credential.id is null then
    raise exception 'passkey not found' using errcode='P0002';
  end if;

  if v_credential.status='revoked' then
    return jsonb_build_object(
      'id',v_credential.id,
      'status','revoked',
      'alreadyRevoked',true
    );
  end if;

  update public.passkey_credentials
  set status='revoked', trusted=false, updated_at=now()
  where id=v_credential.id;

  perform public.log_audit_event(
    'passkey.revoked',
    'security',
    'warning',
    'passkey_credentials',
    v_credential.id,
    'إلغاء جهاز بصمة موثوق',
    nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'deviceLabel',v_credential.device_label,
      'credentialDeviceType',v_credential.credential_device_type,
      'lastUsedAt',v_credential.last_used
    )
  );

  return jsonb_build_object(
    'id',v_credential.id,
    'status','revoked',
    'alreadyRevoked',false
  );
end;
$$;
revoke execute on function public.revoke_my_passkey(uuid,text) from public;
grant execute on function public.revoke_my_passkey(uuid,text) to authenticated;

create or replace function public.get_my_attendance_history(
  p_limit integer default 60,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_limit integer := greatest(1,least(coalesce(p_limit,60),200));
  v_result jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(item order by event_at desc),'[]'::jsonb)
  into v_result
  from (
    select
      ae.event_at,
      jsonb_build_object(
        'id',ae.id,
        'eventType',ae.event_type,
        'eventAt',ae.event_at,
        'status',ae.status,
        'verificationStatus',ae.verification_status,
        'lateMinutes',ae.late_minutes,
        'requiresReview',ae.requires_review,
        'accuracyMeters',ae.accuracy_meters,
        'distanceMeters',ae.distance_meters,
        'source',ae.source,
        'notes',ae.notes
      ) as item
    from public.attendance_events ae
    where ae.employee_id=v_employee_id
      and (p_before is null or ae.event_at<p_before)
    order by ae.event_at desc
    limit v_limit
  ) history;

  return v_result;
end;
$$;
revoke execute on function public.get_my_attendance_history(integer,timestamptz) from public;
grant execute on function public.get_my_attendance_history(integer,timestamptz) to authenticated;

commit;
