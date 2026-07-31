-- 0242: Repair broken runtime RPCs and cron health checks.
--
-- This migration intentionally supersedes broken historical definitions.  It
-- does not rewrite any previously-applied migration.

begin;

-- ---------------------------------------------------------------------------
-- Invite throttling: audit_events uses target_table/target_id, not the removed
-- entity_type/entity_id pair.
-- ---------------------------------------------------------------------------
create or replace function public.check_invite_rate_limit(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_last_invite timestamptz;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  -- current_user is the function owner inside SECURITY DEFINER and therefore
  -- cannot identify the caller. A JWT-backed caller must be full-access;
  -- trusted server invocations have no end-user auth.uid().
  if auth.uid() is not null
     and not public.current_is_full_access() then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  select max(ae.created_at)
    into v_last_invite
  from public.audit_events ae
  where ae.target_table = 'employees'
    and ae.target_id = p_employee_id
    and ae.event_type in ('employee.invite.resent', 'employee.invite.sent');

  if v_last_invite is not null
     and v_last_invite > now() - interval '60 seconds' then
    raise exception 'invite_rate_limit_exceeded'
      using errcode = '42501',
            hint = 'يرجى الانتظار 60 ثانية قبل إعادة إرسال الدعوة.';
  end if;
end;
$$;

revoke all on function public.check_invite_rate_limit(uuid)
  from public, anon, authenticated;
grant execute on function public.check_invite_rate_limit(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Official holidays: legal entity belongs to the employee department.
-- ---------------------------------------------------------------------------
create or replace function public.is_official_holiday(
  p_date date,
  p_employee_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_dept_id uuid;
  v_entity_id uuid;
begin
  if p_date is null then
    return false;
  end if;

  if p_employee_id is not null then
    select e.department_id, d.legal_entity_id
      into v_dept_id, v_entity_id
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where e.id = p_employee_id
      and e.is_active
      and not e.is_deleted;
  end if;

  return exists (
    select 1
    from public.public_holidays h
    where h.is_active
      and p_date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
      and (
        h.scope = 'all'
        or (h.scope = 'legal_entity' and h.legal_entity_id = v_entity_id)
        or (h.scope = 'department' and h.department_id = v_dept_id)
      )
      and (
        coalesce(cardinality(h.excluded_department_ids), 0) = 0
        or v_dept_id is null
        or not (v_dept_id = any(h.excluded_department_ids))
      )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Live-location completion: use the canonical request/response schema.
-- ---------------------------------------------------------------------------
create or replace function public.complete_live_location_response(
  p_request_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy numeric,
  p_address text default null,
  p_captured_at timestamptz default now()
)
returns public.live_location_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  if v_me is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if p_request_id is null
     or p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180
     or p_accuracy is null or p_accuracy < 0 then
    raise exception 'INVALID_LOCATION_RESPONSE' using errcode = '22023';
  end if;

  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_req.employee_id is distinct from v_me then
    raise exception 'NOT_TARGET_EMPLOYEE' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'active') then
    raise exception 'REQUEST_NOT_ACTIVE: %', v_req.status using errcode = '22023';
  end if;
  if v_req.expires_at < now() then
    raise exception 'REQUEST_EXPIRED' using errcode = '22023';
  end if;

  insert into public.location_request_responses(
    request_id, employee_id, latitude, longitude, accuracy_meters,
    address, captured_at, upload_status, metadata
  ) values (
    p_request_id, v_me, p_latitude, p_longitude, p_accuracy::double precision,
    nullif(trim(coalesce(p_address, '')), ''), coalesce(p_captured_at, now()),
    'completed', jsonb_build_object('source', 'complete_live_location_response')
  )
  on conflict (request_id) do update set
    employee_id = excluded.employee_id,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_meters = excluded.accuracy_meters,
    address = excluded.address,
    captured_at = excluded.captured_at,
    upload_status = 'completed',
    metadata = public.location_request_responses.metadata || excluded.metadata,
    updated_at = now();

  update public.live_location_requests
  set status = 'completed',
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  if v_req.requested_by is not null then
    perform public.notify_employee(
      v_req.requested_by,
      'وصل الموقع',
      'تم استقبال موقع الموظف المطلوب.',
      'system', 'normal', 'live_location_requests', v_req.id,
      jsonb_build_object(
        'latitude', p_latitude,
        'longitude', p_longitude,
        'accuracy', p_accuracy
      )
    );
  end if;

  perform public.log_audit_event(
    'location.completed', 'workflow', 'info',
    'live_location_requests', v_req.id,
    'اكتمال طلب الموقع (بدون فيديو)', null,
    jsonb_build_object(
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy', p_accuracy,
      'address', p_address
    )
  );

  return v_req;
end;
$$;

revoke all on function public.complete_live_location_response(
  uuid, double precision, double precision, numeric, text, timestamptz
) from public, anon;
grant execute on function public.complete_live_location_response(
  uuid, double precision, double precision, numeric, text, timestamptz
) to authenticated;

-- ---------------------------------------------------------------------------
-- KPI cycle list: recover the remote-only RPC with canonical local columns.
-- Stage scores are derived from kpi_scores rather than nonexistent columns on
-- kpi_evaluations.
-- ---------------------------------------------------------------------------
create or replace function public.get_kpi_cycle_evaluations(p_cycle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_permission('performance.kpi.read')
    or public.has_permission('performance.kpi.hr_review')
    or public.has_permission('performance.kpi.manager_assess')
  ) then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'employeeId', e.employee_id,
        'employeeName', emp.full_name_ar,
        'employeeCode', emp.employee_code,
        'department', d.name,
        'stage', e.current_stage,
        'workflowStatus', e.workflow_status,
        'selfScore', scores.self_score,
        'managerScore', scores.manager_score,
        'finalScore', e.final_score,
        'finalRating', e.final_rating,
        'locked', e.locked,
        'updatedAt', e.updated_at
      ) order by emp.full_name_ar, e.id
    )
    from public.kpi_evaluations e
    join public.employees emp on emp.id = e.employee_id
    left join public.departments d on d.id = emp.department_id
    left join lateral (
      select
        round(avg(s.score) filter (where s.reviewer_stage = 'self'), 2) as self_score,
        round(avg(s.score) filter (where s.reviewer_stage = 'manager'), 2) as manager_score
      from public.kpi_scores s
      where s.evaluation_id = e.id
    ) scores on true
    where e.cycle_id = p_cycle_id
      and (
        public.current_is_full_access()
        or public.has_permission('performance.kpi.hr_review')
        or e.employee_id = public.current_employee_id()
        or public.kpi_is_direct_manager(e.employee_id)
      )
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_kpi_cycle_evaluations(uuid)
  from public, anon;
grant execute on function public.get_kpi_cycle_evaluations(uuid)
  to authenticated;

-- Remove obsolete overloads.  The canonical nine-argument overload has
-- defaults and accepts the named seven-argument mobile call safely.
drop function if exists public.publish_official_announcement(
  text, text, text, text, boolean
);
drop function if exists public.publish_official_announcement(
  text, text, text, text, boolean, text, text
);

-- ---------------------------------------------------------------------------
-- Missing checkout finalizer: attendance_exceptions has no auto_generated
-- column.  Link the exception to attendance_daily and prevent duplicates.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_missing_checkouts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
  v_grace_minutes integer;
  v_tz text;
  v_now timestamptz := now();
  v_rec record;
  v_shift public.shifts%rowtype;
  v_deadline timestamptz;
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  select s.missing_checkout_grace_minutes, s.timezone
    into v_grace_minutes, v_tz
  from public.attendance_settings s
  limit 1;
  v_grace_minutes := coalesce(v_grace_minutes, 60);
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  for v_rec in
    select ad.id, ad.employee_id, ad.work_date, ad.shift_id
    from public.attendance_daily ad
    where ad.first_check_in is not null
      and ad.last_check_out is null
      and not ad.is_finalized
      and ad.status not in ('on_leave', 'holiday', 'weekend', 'missing_checkout')
    for update skip locked
  loop
    v_shift := null;
    if v_rec.shift_id is not null then
      select * into v_shift
      from public.shifts
      where id = v_rec.shift_id;
    end if;

    if v_shift.id is not null then
      v_deadline := (
        v_rec.work_date
        + case when v_shift.crosses_midnight then 1 else 0 end
        + v_shift.end_time
      ) at time zone v_tz
      + make_interval(mins => v_grace_minutes);
    else
      v_deadline := (v_rec.work_date + '18:00'::time) at time zone v_tz
                    + make_interval(mins => v_grace_minutes);
    end if;

    if v_now > v_deadline then
      update public.attendance_daily
      set status = 'missing_checkout', updated_at = now()
      where id = v_rec.id and not is_finalized;

      if found then
        insert into public.attendance_exceptions(
          employee_id, attendance_daily_id, work_date, kind, description
        )
        select
          v_rec.employee_id,
          v_rec.id,
          v_rec.work_date,
          'missing_check_out',
          'بصمة خروج مفقودة — أُنشئ تلقائياً بواسطة finalize_missing_checkouts'
        where not exists (
          select 1
          from public.attendance_exceptions ae
          where ae.attendance_daily_id = v_rec.id
            and ae.kind = 'missing_check_out'
            and ae.status in ('open', 'approved', 'resolved')
        );

        perform public.log_audit_event(
          'attendance.missing_checkout_finalized', 'operations', 'warning',
          'attendance_daily', v_rec.id,
          'بصمة خروج مفقودة — تصفية تلقائية', null,
          jsonb_build_object(
            'workDate', v_rec.work_date,
            'shiftId', v_rec.shift_id,
            'deadline', v_deadline
          )
        );
        v_count := v_count + 1;
      end if;
    end if;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.finalize_missing_checkouts()
  from public, anon, authenticated;
grant execute on function public.finalize_missing_checkouts()
  to service_role;

-- pgcrypto lives in extensions.  Keep the SECURITY DEFINER functions on an
-- explicit, trusted search path so their digest() calls compile and execute.
alter function public.get_my_attendance_state(text)
  set search_path = public, extensions, pg_temp;
alter function public.punch_attendance_local_biometric_v1(
  uuid, text, text, double precision, double precision, double precision, boolean
)
  set search_path = public, extensions, pg_temp;
alter function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text,
  double precision, double precision, double precision,
  bigint, text, boolean
)
  set search_path = public, extensions, pg_temp;

-- ---------------------------------------------------------------------------
-- Cron health: qualify cron.job.jobname and make missing HTTP configuration a
-- persistent P0 signal instead of a warning that disappears with migration
-- output.
-- ---------------------------------------------------------------------------
create or replace function public.verify_critical_cron_jobs()
returns table(jobname text, active boolean, last_run timestamptz, last_run_status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_missing text[];
  v_has_cron boolean;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and not public.current_is_full_access()
     and (auth.jwt() ->> 'role') is distinct from 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select exists (
    select 1
    from pg_available_extensions
    where name = 'pg_cron' and installed_version is not null
  ) into v_has_cron;

  if not v_has_cron then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_pg_cron_unavailable', 'P0',
      'pg_cron غير مفعّل في بيئة التشغيل',
      'لا يمكن جدولة المهام الحرجة حتى تفعيل pg_cron أو توثيق بديل خارجي معتمد.',
      'cron', jsonb_build_object('category', 'cron_health'), 'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          occurrences = public.system_alerts.occurrences + 1;
    return;
  end if;

  select array_agg(j.expected_jobname order by j.expected_jobname)
    into v_missing
  from (
    values
      ('hr_request_sla'),
      ('hr_leave_accrual'),
      ('hr_scheduled_reports'),
      ('hr_notification_dispatch'),
      ('hr_integration_outbox'),
      ('hr_retention_cleanup_storage'),
      ('hr_scheduled_report_runner')
  ) as j(expected_jobname)
  where not exists (
    select 1
    from cron.job cj
    where cj.jobname = j.expected_jobname
      and cj.active
  );

  if coalesce(cardinality(v_missing), 0) > 0 then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_critical_jobs_missing', 'P0',
      'مهام cron حرجة غير مجدولة أو غير نشطة',
      'المهام المفقودة: ' || array_to_string(v_missing, ', '),
      'cron',
      jsonb_build_object('category', 'cron_health', 'missingJobs', to_jsonb(v_missing)),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          detail = excluded.detail,
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'cron_critical_jobs_missing' and status = 'open';
  end if;

  return query
  select
    cj.jobname::text,
    cj.active,
    cr.start_time,
    cr.status::text
  from cron.job cj
  left join lateral (
    select d.start_time, d.status
    from cron.job_run_details d
    where d.jobid = cj.jobid
    order by d.start_time desc
    limit 1
  ) cr on true
  where cj.jobname like 'hr_%'
  order by cj.jobname;
end;
$$;

revoke all on function public.verify_critical_cron_jobs()
  from public, anon, authenticated;
grant execute on function public.verify_critical_cron_jobs()
  to service_role;

do $$
declare
  v_url text := nullif(trim(current_setting('app.settings.functions_base_url', true)), '');
  v_secret text := nullif(trim(current_setting('app.settings.cron_secret', true)), '');
begin
  if v_url is null or v_secret is null then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_http_configuration_missing', 'P0',
      'إعداد HTTP cron غير مكتمل',
      'functions_base_url أو cron_secret غير مضبوط؛ مهام HTTP الحرجة لن تُعد جاهزة.',
      'cron',
      jsonb_build_object('category', 'cron_health', 'secretPresent', v_secret is not null,
                         'baseUrlPresent', v_url is not null),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'cron_http_configuration_missing' and status = 'open';
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
