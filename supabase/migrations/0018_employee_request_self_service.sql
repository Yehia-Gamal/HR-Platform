begin;

create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_start_date date;
  v_end_date date;
  v_permit_date date;
  v_minutes integer;
  v_leave_type text;
  v_permit_kind text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_request_type not in ('leave','mission','convoy','attendance_permit','generic') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'title and reason are required' using errcode = '22023';
  end if;

  begin
    case p_request_type
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_leave_type not in ('annual','sick','emergency','unpaid') then
          raise exception 'unsupported leave type' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', (v_end_date - v_start_date) + 1
        );

      when 'mission', 'convoy' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1
        );

      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive attendance permits are not allowed' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'unsupported permit kind' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes
        );
      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'invalid request dates or numeric values' using errcode = '22023';
  end;

  select manager_employee_id
  into v_manager
  from public.manager_relations
  where employee_id = v_me
    and relation_type = 'primary'
    and effective_from <= v_today
    and (effective_to is null or effective_to >= v_today)
  order by effective_from desc
  limit 1;

  v_row := public.submit_request(
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload
  );
  return v_row;
end;
$$;
revoke execute on function public.submit_my_request(text,text,text,jsonb) from public;
grant execute on function public.submit_my_request(text,text,text,jsonb) to authenticated;

-- The generic constructor is internal. Employees must use the validated wrapper
-- above, while trusted server jobs may use service_role.
revoke execute on function public.submit_request(text,uuid,uuid,text,text,jsonb) from authenticated;
grant execute on function public.submit_request(text,uuid,uuid,text,text,jsonb) to service_role;

-- Request rows and their audit actions are written only by RPCs.
drop policy if exists requests_insert on public.requests;
drop policy if exists request_actions_insert on public.request_actions;

commit;
