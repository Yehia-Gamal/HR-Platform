-- Fix get_my_attendance_services throwing column e.legal_entity_id does not exist error
-- Joins the branches table to accurately read the legal_entity_id.

create or replace function public.get_my_attendance_services(
  p_from date default current_date - 31,
  p_to date default current_date + 45
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_emp uuid := public.current_employee_id();
begin
  if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
  if p_to < p_from or p_to-p_from > 370 then raise exception 'INVALID_RANGE'; end if;

  return jsonb_build_object(
    'schedule', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,
        'workDate',d.work_date,
        'dayStatus',d.day_status,
        'shiftId',d.shift_id,
        'shiftName',s.name,
        'startTime',coalesce(d.start_override,s.start_time),
        'endTime',coalesce(d.end_override,s.end_time),
        'workSiteId',d.work_site_id,
        'notes',d.notes
      ) order by d.work_date)
      from public.roster_days d
      left join public.shifts s on s.id=d.shift_id
      join public.work_rosters r on r.id=d.roster_id
      where d.employee_id=v_emp and d.work_date between p_from and p_to
        and d.day_status<>'cancelled' and r.status='published'
    ),'[]'::jsonb),
    'corrections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,
        'workDate',c.work_date,
        'type',c.correction_type,
        'reason',c.reason,
        'status',c.status,
        'requestedCheckIn',c.requested_check_in,
        'requestedCheckOut',c.requested_check_out,
        'requestedStatus',c.requested_status,
        'reviewNote',c.review_note,
        'createdAt',c.created_at
      ) order by c.created_at desc)
      from public.attendance_corrections c
      where c.employee_id=v_emp and c.work_date between p_from and p_to
    ),'[]'::jsonb),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'periodMonth',p.period_month,'status',p.status,'closedAt',p.closed_at
      ) order by p.period_month desc)
      from public.attendance_periods p
      join public.employees e on e.id=v_emp
      left join public.branches b on b.id=e.branch_id
      where p.period_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date
        and (p.branch_id is null or p.branch_id=e.branch_id)
        and (p.legal_entity_id is null or p.legal_entity_id=b.legal_entity_id)
    ),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end $$;
