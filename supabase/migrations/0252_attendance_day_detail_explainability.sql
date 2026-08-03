-- 0252: Enrich every statement day with human-friendly "details" explainability.
--
-- Upstream 0251 already re-normalizes status/summary (as-of-date semantics).
-- This migration keeps that behavior by renaming the 0251 builder to
-- _build_attendance_statement_v251 and wrapping it in a new final function that
-- only injects a per-day "details" object. No counters or rates change.
--
-- Per-day details payload:
--   details.leave       → { typeLabel, startDate, endDate, isHalfDay, daysCount, reason? }
--   details.assignment  → { typeLabel, title?, location?, startAt, endAt }
--   details.permit      → { kindLabel, minutes?, reason? }
--   details.correction  → { typeLabel, reason }
--   details.missing     → { checkIn: bool, checkOut: bool }
--
-- Idempotent: safe to re-run; create-or-replace of the final function only.

begin;

-- 1) Pin the current (0251) builder under a private name so we can wrap it.
do $rename$
begin
  if to_regprocedure('public._build_attendance_statement_v251(uuid,integer,integer)') is null then
    alter function public._build_attendance_statement(uuid, integer, integer)
      rename to _build_attendance_statement_v251;
  end if;
end
$rename$;

revoke execute on function public._build_attendance_statement_v251(uuid, integer, integer)
  from public, anon, authenticated;

-- 2) Final statement builder = v251 normalization + per-day details.
create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_leave jsonb;
  v_assignment jsonb;
  v_permit jsonb;
  v_correction jsonb;
  v_missing jsonb;
begin
  -- Re-normalize through 0251 (which internally wraps the legacy V18 builder).
  v_result := public._build_attendance_statement_v251(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;

    -- ─── Approved leave for this day ─────────────────────────────────────
    select jsonb_build_object(
             'typeLabel', coalesce(lt.name_ar, 'إجازة'),
             'startDate', lr.start_date,
             'endDate',   lr.end_date,
             'isHalfDay', lr.is_half_day,
             'daysCount', lr.days_count,
             'reason',    nullif(r.reason, '')
           )
      into v_leave
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      left join public.leave_types lt on lt.id = lr.leave_type_id
     where lr.employee_id = p_employee_id
       and r.status = 'approved'
       and v_day between lr.start_date and lr.end_date
     order by lr.start_date desc
     limit 1;

    -- ─── Approved work assignment (mission / convoy / fundraising) ──────
    select jsonb_build_object(
             'typeLabel', case wa.assignment_type
                            when 'MISSION'     then 'مأمورية عمل'
                            when 'CONVOY'      then 'قافلة'
                            when 'FUNDRAISING' then 'فاندي'
                            else 'تكليف عمل'
                          end,
             'assignmentType', wa.assignment_type,
             'title',    nullif(wa.title, ''),
             'location', nullif(wa.location, ''),
             'startAt',  (wa.start_at at time zone 'Africa/Cairo'),
             'endAt',    (wa.end_at   at time zone 'Africa/Cairo')
           )
      into v_assignment
      from public.work_assignment_participants wp
      join public.work_assignments wa on wa.id = wp.assignment_id
     where wp.employee_id = p_employee_id
       and wa.status = 'APPROVED'
       and coalesce(wa.counts_as_work_day, true)
       and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                     and (wa.end_at   at time zone 'Africa/Cairo')::date
     order by wa.start_at desc
     limit 1;

    -- Legacy missions table fallback when no assignment row matches.
    if v_assignment is null then
      select jsonb_build_object(
               'typeLabel', 'مأمورية عمل',
               'assignmentType', 'MISSION',
               'title',    nullif(m.purpose, ''),
               'location', nullif(m.destination, ''),
               'startAt',  (m.start_at at time zone 'Africa/Cairo'),
               'endAt',    (m.end_at   at time zone 'Africa/Cairo')
             )
        into v_assignment
        from public.missions m
        join public.requests r on r.id = m.request_id
       where m.employee_id = p_employee_id
         and r.status = 'approved'
         and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                       and (m.end_at   at time zone 'Africa/Cairo')::date
       order by m.start_at desc
       limit 1;
    end if;

    -- ─── Approved attendance permit for this day ─────────────────────────
    select jsonb_build_object(
             'kindLabel', case p.kind
                            when 'arrival'   then 'إذن حضور متأخر'
                            when 'departure' then 'إذن انصراف مبكر'
                            else 'إذن شخصي'
                          end,
             'permitKind', p.kind,
             'minutes', p.grace_minutes,
             'reason', nullif(p.reason, '')
           )
      into v_permit
      from public.attendance_permits p
     where p.employee_id = p_employee_id
       and p.permit_date = v_day
       and p.status = 'approved'
     order by case p.kind when 'arrival' then 1 else 2 end,
              p.created_at desc
     limit 1;

    -- ─── Approved attendance correction for this day ─────────────────────
    select jsonb_build_object(
             'typeLabel', case c.correction_type
                            when 'missing_check_in'  then 'تصحيح نسيان بصمة حضور'
                            when 'missing_check_out' then 'تصحيح نسيان بصمة انصراف'
                            when 'wrong_time'        then 'تصحيح وقت بصمة'
                            when 'wrong_status'      then 'تصحيح حالة اليوم'
                            when 'mission'           then 'تصحيح (مأمورية)'
                            when 'leave'             then 'تصحيح (إجازة)'
                            else 'تصحيح حضور'
                          end,
             'correctionType', c.correction_type,
             'reason', nullif(c.reason, '')
           )
      into v_correction
      from public.attendance_corrections c
     where c.employee_id = p_employee_id
       and c.work_date = v_day
       and c.status = 'approved'
     order by c.reviewed_at desc nulls last, c.created_at desc
     limit 1;

    -- ─── Still-missing punches (passthrough of 0251's computation) ──────
    v_missing := jsonb_build_object(
      'checkIn',  coalesce((v_day_obj->>'missingCheckIn')::boolean,  false),
      'checkOut', coalesce((v_day_obj->>'missingCheckOut')::boolean, false)
    );

    v_day_obj := v_day_obj || jsonb_build_object(
      'details', jsonb_strip_nulls(jsonb_build_object(
        'leave',      v_leave,
        'assignment', v_assignment,
        'permit',     v_permit,
        'correction', v_correction,
        'missing',    v_missing
      ))
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  return v_result || jsonb_build_object('days', v_days);
end
$$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0252: statement with per-day explainability (details: leave / assignment / permit / correction / missing).';

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

commit;
