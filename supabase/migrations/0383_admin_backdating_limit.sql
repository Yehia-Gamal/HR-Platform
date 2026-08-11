-- migration: 0377
-- description: limit admin backdating to 90 days — prevent historical falsification

begin;

create or replace function public.set_employee_attendance_day_admin(
  p_employee_id   integer,
  p_work_date     date,
  p_status        text,
  p_note          text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := current_date;
  v_min_date date := v_today - interval '90 days';
begin
  -- authz
  if not (current_is_full_access() or auth.role() = 'service_role') then
    raise exception 'PERMISSION_DENIED: requires full-access role';
  end if;

  -- backdating guard (service_role bypasses for migrations/corrections)
  if auth.role() <> 'service_role' then
    if p_work_date > v_today then
      raise exception 'INVALID_DATE: cannot set attendance for a future date';
    end if;
    if p_work_date < v_min_date then
      raise exception 'BACKDATING_LIMIT: cannot modify attendance older than 90 days (date: %, limit: %)', p_work_date, v_min_date;
    end if;
  end if;

  -- validate status value
  if p_status not in ('present','absent','on_leave','on_mission','holiday','weekend','excused_absent') then
    raise exception 'INVALID_STATUS: unknown attendance status %', p_status;
  end if;

  -- upsert the daily record
  insert into public.attendance_daily (
    employee_id, work_date, status, note, source, updated_at
  )
  values (
    p_employee_id, p_work_date, p_status, p_note, 'admin_override', now()
  )
  on conflict (employee_id, work_date) do update
    set status     = excluded.status,
        note       = excluded.note,
        source     = excluded.source,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.set_employee_attendance_day_admin(integer,date,text,text) from anon, authenticated;
grant execute on function public.set_employee_attendance_day_admin(integer,date,text,text) to authenticated;

commit;
