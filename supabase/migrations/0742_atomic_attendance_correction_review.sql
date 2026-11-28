-- Both review entry points take the request lock before the correction lock.
-- Keep the existing authorization, attendance, and penalty logic in one place.
alter function public.decide_attendance_correction(uuid, text, text)
  rename to _apply_attendance_correction_decision;
revoke all on function public._apply_attendance_correction_decision(uuid, text, text)
  from public, anon, authenticated, service_role;

create function public.decide_attendance_correction(
  p_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_open_request_ids uuid[];
begin
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  select array_agg(r.id) filter (where r.status in ('pending', 'under_review', 'escalated'))
    into v_open_request_ids
    from (
      select id, status from public.requests
      where request_type = 'attendance_correction' and payload->>'correctionId' = p_id::text
      order by id
      for update
    ) r;

  perform public._apply_attendance_correction_decision(p_id, p_decision, p_note);

  -- A decision from the correction queue also closes the linked workflow.
  if v_open_request_ids is not null then
    update public.requests
       set status = case when p_decision = 'approved' then 'approved' else 'rejected' end,
           workflow_status = case when p_decision = 'approved' then 'completed' else 'terminated' end,
           decided_at = now(), decided_by = public.current_employee_id(),
           review_note = p_note, updated_at = now()
     where id = any(v_open_request_ids);

    update public.request_steps
       set status = 'skipped', updated_at = now()
     where request_id = any(v_open_request_ids) and status in ('pending', 'active', 'escalated');
  end if;
end;
$$;

alter function public.decide_request(uuid, text, text) rename to _decide_request_workflow;
revoke all on function public._decide_request_workflow(uuid, text, text)
  from public, anon, authenticated, service_role;

create function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_request public.requests;
  v_correction_id uuid;
begin
  v_request := public._decide_request_workflow(p_request_id, p_decision, p_comment);

  if v_request.status = 'approved' and v_request.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_request.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      -- Let a failed attendance write abort the request approval too.
      perform public.decide_attendance_correction(v_correction_id, 'approved', p_comment);
    end if;
  end if;

  return v_request;
end;
$$;

revoke all on function public.decide_attendance_correction(uuid, text, text) from public, anon;
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_attendance_correction(uuid, text, text) to authenticated, service_role;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;

-- Serialize pending submissions for the same punch, including offline retries.
-- Existing records stay available for review even if they contain duplicates.
create function public.guard_pending_attendance_correction()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status <> 'pending' then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'attendance_correction:' || new.employee_id || ':' || new.work_date || ':' || new.correction_type, 0
  ));

  if exists (
    select 1 from public.attendance_corrections c
    where c.employee_id = new.employee_id and c.work_date = new.work_date
      and c.correction_type = new.correction_type and c.status = 'pending'
  ) then
    raise exception 'يوجد طلب تصحيح من النوع نفسه قيد المراجعة لهذا اليوم' using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_pending_attendance_correction() from public, anon, authenticated, service_role;
create trigger guard_pending_attendance_correction
before insert on public.attendance_corrections
for each row execute function public.guard_pending_attendance_correction();
