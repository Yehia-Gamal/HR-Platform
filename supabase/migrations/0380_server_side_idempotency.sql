-- migration: 0380
-- description: server-side idempotency key — auto-generate when client omits it

begin;

-- helper: compute canonical idempotency key from request signature
create or replace function public._request_idempotency_key(
  p_employee_id  integer,
  p_request_type text,
  p_start_date   date,
  p_end_date     date
) returns uuid
language sql
immutable
security definer
set search_path = public
as $$
  select uuid_generate_v5(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid,
    format('%s|%s|%s|%s', p_employee_id, p_request_type, p_start_date, p_end_date)
  );
$$;

-- update submit_my_request to use auto-generated key when none provided
create or replace function public.submit_my_request(
  p_request_type    text,
  p_start_date      date,
  p_end_date        date,
  p_payload         jsonb    default '{}',
  p_idempotency_key uuid     default null
) returns public.requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id  integer;
  v_idem_key     uuid;
  v_existing     public.requests%rowtype;
  v_today        date := current_date;
begin
  -- resolve caller employee
  select id into v_employee_id
  from public.employees
  where user_id = auth.uid() and is_active = true;

  if v_employee_id is null then
    raise exception 'EMPLOYEE_NOT_FOUND';
  end if;

  -- compute idempotency key (use provided or auto-generate)
  v_idem_key := coalesce(
    p_idempotency_key,
    public._request_idempotency_key(v_employee_id, p_request_type, p_start_date, p_end_date)
  );

  -- check for duplicate within 10 minutes
  select * into v_existing
  from public.requests
  where employee_id = v_employee_id
    and request_type = p_request_type
    and (payload ->> 'clientId')::uuid = v_idem_key
    and created_at > now() - interval '10 minutes';

  if found then
    return v_existing;
  end if;

  -- backdating guard
  if p_start_date < v_today then
    raise exception 'RETROACTIVE_REQUEST_NOT_ALLOWED: start_date % is in the past', p_start_date;
  end if;

  -- delegate to core submit_request
  return public.submit_request(
    p_employee_id  => v_employee_id,
    p_request_type => p_request_type,
    p_start_date   => p_start_date,
    p_end_date     => p_end_date,
    p_payload      => p_payload || jsonb_build_object('clientId', v_idem_key)
  );
end;
$$;

revoke all on function public.submit_my_request(text,date,date,jsonb,uuid) from anon;
grant execute on function public.submit_my_request(text,date,date,jsonb,uuid) to authenticated;
revoke all on function public._request_idempotency_key(integer,text,date,date) from anon, authenticated;

commit;
