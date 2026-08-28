-- ============================================================
-- 0487: canonical completion for function groups untouched by 0483/0484
--
-- 0483 rebuilt 289 functions from clean migration sources. This migration
-- finishes the 10 whose clean sources were not found under their exact names:
--
--   * 6 catalog/rpc helpers rebuilt from their newest clean CREATE in the
--     repo (locking clean Arabic):
--       create_onboarding_journey_admin, get_employee_monthly_attendance_statement,
--       get_kpi_admin_catalog, get_mobile_manager_operations, rpc_assign_role,
--       run_monthly_leave_accrual
--
--   * 4 legacy _build_attendance_statement_vXXX variants that only ever
--     existed via ALTER FUNCTION ... RENAME (never a CREATE in the repo).
--     Their intact PL/pgSQL logic is rebuilt verbatim from prod with the
--     Arabic literals restored to clean canonical values. External callers: 0.
-- ============================================================

create or replace function public.create_onboarding_journey_admin(
  p_employee_id uuid,
  p_started_at timestamptz default now(),
  p_probation_end date default null,
  p_tasks jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_task jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'onboarding management denied' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_tasks, '[]'::jsonb)) > 200 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  if not exists(select 1 from public.employees e where e.id = p_employee_id and e.is_deleted = false) then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  if exists(select 1 from public.onboarding_journeys j where j.employee_id = p_employee_id and j.status in ('not_started','in_progress')) then
    raise exception 'employee already has an active onboarding journey' using errcode = '23505';
  end if;

  insert into public.onboarding_journeys(employee_id, started_at, probation_end, status, created_by)
  values (p_employee_id, coalesce(p_started_at, now()), p_probation_end, 'in_progress', auth.uid())
  returning id into v_id;

  for v_task in select * from jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) loop
    if nullif(trim(v_task->>'title'), '') is not null then
      insert into public.onboarding_tasks(journey_id, title, owner_role, assignee_id, due_offset_days, status, created_by)
      values (
        v_id,
        trim(v_task->>'title'),
        nullif(trim(v_task->>'ownerRole'), ''),
        nullif(v_task->>'assigneeId', '')::uuid,
        coalesce(nullif(v_task->>'dueOffsetDays', '')::integer, 0),
        'pending', auth.uid()
      );
    end if;
  end loop;

  update public.employees set status = 'onboarding', updated_at = now()
  where id = p_employee_id and status in ('draft','invited');
  return v_id;
end;
$$;

create or replace function public.get_employee_monthly_attendance_statement(
  p_employee_id uuid,
  p_year integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer,
  p_month integer default extract(month from (now() at time zone 'Africa/Cairo'))::integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_month < 1 or p_month > 12 then raise exception 'INVALID_MONTH' using errcode = '22023'; end if;
  -- الصلاحية: full-access أو وصول نطاقي فعلي (المدير المباشر/الإدارة/HR/التنفيذي)
  -- بصلاحية قراءة الحضور أو التقارير — بنطاق self لا يمر (لا يُرى سوى الموظف نفسه).
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.record.read')
    or public.can_access_employee(p_employee_id, 'reports.attendance.read')
  ) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية كشف هذا الموظف' using errcode = '42501';
  end if;
  return public._build_attendance_statement(p_employee_id, p_year, p_month);
end $$;

create or replace function public.get_kpi_admin_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.read','performance.cycle.manage','performance.kpi.cycle.control','performance.kpi.secretary_review','performance.kpi.executive_review'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'month',v_month,'canManageCycles',public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.cycle.control']),
  'officialTemplateId',(select id from public.kpi_templates where official_code='OFFICIAL_KPI_100'),
  'cycles',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'periodMonth',c.period_month,'status',c.status,'templateId',c.template_id,'templateName',t.name_ar,'selfDueAt',c.self_due_at,'managerDueAt',c.manager_due_at,'secretaryDueAt',c.secretary_due_at,'executiveDueAt',c.executive_due_at,'scheduledOpenAt',c.scheduled_open_at,'deadlineAt',c.deadline_at,'extendedUntil',c.extended_until,'effectiveDeadline',public.kpi_effective_deadline(c),'openedAt',c.opened_at,'lockedAt',c.locked_at,'overrideReason',c.override_reason,'evaluations',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id),'finalized',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.current_stage in ('finalized','closed')),'overdue',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.workflow_status='OVERDUE'),'averageScore',(select round(avg(e.final_score),2) from public.kpi_evaluations e where e.cycle_id=c.id and e.final_score is not null)) order by c.period_month desc) from public.kpi_cycles c left join public.kpi_templates t on t.id=c.template_id where c.period_month between (v_month-interval '6 months')::date and (v_month+interval '1 month')::date),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name_ar,'version',t.version,'active',t.is_active,'officialCode',t.official_code,'criteria',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'code',k.code,'name',k.name_ar,'weight',k.weight,'maxScore',k.max_score,'sourceType',k.source_type,'attendanceMetric',k.attendance_metric,'evaluatorStage',k.evaluator_stage,'calculationMethod',k.calculation_method,'requiresEvidence',k.requires_evidence) order by k.sort_order) from public.kpi_criteria k where k.template_id=t.id),'[]'::jsonb)) order by t.created_at desc) from public.kpi_templates t),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'evaluationId',a.evaluation_id,'employeeId',a.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'reason',a.reason,'requestedOutcome',a.requested_outcome,'status',a.status,'submittedAt',a.submitted_at,'resolutionDueAt',a.resolution_due_at,'reviewNote',a.review_note) order by a.submitted_at desc) from public.kpi_appeals a join public.employees e on e.id=a.employee_id where a.status in ('submitted','under_review')),'[]'::jsonb),
  'stageCounts',coalesce((select jsonb_object_agg(x.current_stage,x.count) from (select e.current_stage,count(*) count from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=v_month group by e.current_stage)x),'{}'::jsonb),
  'policy',(select jsonb_build_object('id',id,'version',version,'name',name_ar,'weights',criteria_weights,'attendanceRules',attendance_rules,'ratingBands',rating_bands) from public.kpi_policy_versions where is_active),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.get_mobile_manager_operations(
  p_from date default ((now() at time zone 'Africa/Cairo')::date),
  p_to date default (((now() at time zone 'Africa/Cairo')::date) + 14)
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager_id uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 45 then
    raise exception 'invalid operations date range' using errcode = '22023';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1
      from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  with team_scope as (
    select e.id, e.employee_code, e.full_name_ar
    from public.manager_relations mr
    join public.employees e on e.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
      and e.is_active = true
      and e.is_deleted = false
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'metrics', jsonb_build_object(
      'scheduledToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status = 'scheduled'
      ),
      'awayToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status in ('leave','mission','rest','holiday')
      ),
      'overdueTasks', (
        select count(*)
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress') and t.due_date < v_today
      ),
      'expiringDocuments', (
        select count(*)
        from public.documents d
        join team_scope ts on ts.id = d.owner_employee_id
        where d.status <> 'archived' and d.expiry_date between v_today and v_today + 60
      ),
      'missingReports', (
        select count(*)
        from team_scope ts
        where not exists (
          select 1 from public.daily_reports dr
          where dr.employee_id = ts.id and dr.report_date = v_today
        )
      )
    ),
    'calendar', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rd.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'workDate', rd.work_date,
        'dayStatus', rd.day_status,
        'shiftName', s.name,
        'startsAt', coalesce(rd.start_override, s.start_time),
        'endsAt', coalesce(rd.end_override, s.end_time),
        'notes', rd.notes
      ) order by rd.work_date, ts.full_name_ar)
      from public.roster_days rd
      join team_scope ts on ts.id = rd.employee_id
      left join public.shifts s on s.id = rd.shift_id
      where rd.work_date between p_from and p_to and rd.day_status <> 'cancelled'
    ), '[]'::jsonb),
    'documentAlerts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'title', d.title,
        'documentType', d.doc_type,
        'expiryDate', d.expiry_date,
        'status', case when d.expiry_date < v_today then 'expired' else d.status end
      ) order by d.expiry_date, ts.full_name_ar)
      from public.documents d
      join team_scope ts on ts.id = d.owner_employee_id
      where d.status <> 'archived' and d.expiry_date <= v_today + 60
    ), '[]'::jsonb),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'employeeId', x.employee_id,
        'employeeName', x.employee_name,
        'title', x.title,
        'priority', x.priority,
        'status', x.status,
        'dueDate', x.due_date,
        'isOverdue', x.due_date is not null and x.due_date < v_today
      ) order by x.is_overdue desc, x.due_date nulls last, x.created_at desc)
      from (
        select t.*, ts.id employee_id, ts.full_name_ar employee_name,
          (t.due_date is not null and t.due_date < v_today) is_overdue
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress')
        order by is_overdue desc, t.due_date nulls last, t.created_at desc
        limit 40
      ) x
    ), '[]'::jsonb),
    'missingReports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code
      ) order by ts.full_name_ar)
      from team_scope ts
      where not exists (
        select 1 from public.daily_reports dr
        where dr.employee_id = ts.id and dr.report_date = v_today
      )
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.rpc_assign_role(
  p_user_id uuid, p_role_id uuid, p_scope_override jsonb default null,
  p_effective_from timestamptz default now(), p_effective_to timestamptz default null
)
returns public.user_roles
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_row public.user_roles; v_role public.roles;
begin
  -- فحص التخويل الأساسي
  if not (public.current_is_full_access() or public.has_permission('access.role.assign')) then
    raise exception 'not authorized to assign roles' using errcode = '42501';
  end if;

  select * into v_role from public.roles where id = p_role_id;
  if v_role is null then
    raise exception 'role not found' using errcode = '42501';
  end if;

  -- منح full-access محصور بـsuper-admin فقط
  if v_role.is_full_access and not public.current_is_super_admin() then
    raise exception 'only super-admin may assign a full-access role' using errcode = '42501';
  end if;

  -- منع منح النفس دوراً أعلى
  if p_user_id = auth.uid() and v_role.is_full_access then
    raise exception 'cannot self-grant full access' using errcode = '42501';
  end if;

  -- V23: مستخدمو HR محدودون بأدوار الموظف/المدير/التشغيل فقط
  -- Main Admin وحده يمنح الأدوار العليا وعضوية اللجنة
  if public.current_is_hr_only() then
    if v_role.slug = any(array[
      'admin','super-admin','super_admin','system-admin','technical-lead',
      'executive-director','executive','executive-secretary',
      'hr-manager','hr-specialist',
      'committee-member','committee-chair','committee-secretary'
    ]) or v_role.is_full_access or v_role.is_system then
      raise exception 'HR may only assign employee, manager, or operations roles'
        using errcode = '42501';
    end if;
  end if;

  insert into public.user_roles (user_id, role_id, scope_override, effective_from, effective_to, granted_by)
  values (p_user_id, p_role_id, p_scope_override, p_effective_from, p_effective_to, auth.uid())
  on conflict (user_id, role_id) do update
    set scope_override = excluded.scope_override,
        effective_from = excluded.effective_from,
        effective_to   = excluded.effective_to,
        granted_by     = auth.uid()
  returning * into v_row;

  -- V23: تدقيق كل عملية إسناد دور
  perform public.log_audit_event(
    'access.role.assigned',
    'access',
    'notice',
    'user_roles',
    p_role_id,
    'تم إسناد دور «' || coalesce(v_role.name_ar, v_role.slug) || '»',
    'Role "' || v_role.slug || '" assigned',
    jsonb_build_object(
      'role_slug', v_role.slug,
      'role_id', p_role_id,
      'target_user_id', p_user_id,
      'is_capability', coalesce(v_role.is_capability, false)
    )
  );

  return v_row;
end;
$$;

create or replace function public.run_monthly_leave_accrual(
  p_year  integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer,
  p_month integer default extract(month from (now() at time zone 'Africa/Cairo'))::integer,
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count   integer := 0;
  v_row     record;
  v_key     text;
  v_ytd     numeric;
  v_grant   numeric;
begin
  -- محصور بالخادم الموثوق أو full access
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_month < 1 or p_month > 12 then
    raise exception 'INVALID_MONTH' using errcode = '22023';
  end if;

  for v_row in
    select e.id as employee_id, lt.id as leave_type_id,
           lt.monthly_accrual_units as rate, lt.max_days_per_year as cap
    from public.employees e
    cross join public.leave_types lt
    where e.is_active = true
      and e.status = 'active'
      and lt.is_active = true
      and lt.affects_balance = true
      and lt.monthly_accrual_units > 0
    limit greatest(1, least(p_limit, 50000))
  loop
    -- مفتاح idempotent فريد لكل موظف/نوع/شهر: لا استحقاق مزدوج ولو تكرر التشغيل
    v_key := format('leave:accrual:%s:%s:%s-%s',
                    v_row.employee_id, v_row.leave_type_id, p_year, lpad(p_month::text, 2, '0'));

    -- تجاوز الحد السنوي: لا نمنح ما يتخطى max_days_per_year (إن حُدّد)
    v_grant := v_row.rate;
    if v_row.cap is not null then
      select coalesce(sum(units), 0) into v_ytd
      from public.leave_ledger_entries
      where employee_id = v_row.employee_id
        and leave_type_id = v_row.leave_type_id
        and entry_type in ('opening','accrual','carryover')
        and extract(year from effective_date)::integer = p_year;
      v_grant := least(v_row.rate, greatest(0, v_row.cap - v_ytd));
    end if;

    if v_grant > 0 then
      -- apply_leave_ledger_entry يتجاهل التكرار عبر unique(source_key)
      perform public.apply_leave_ledger_entry(
        v_row.employee_id, v_row.leave_type_id, p_year,
        'accrual', v_grant, v_key, null,
        format('استحقاق شهري تلقائي %s-%s', p_year, lpad(p_month::text, 2, '0')),
        jsonb_build_object('year', p_year, 'month', p_month, 'rate', v_row.rate)
      );
      v_count := v_count + 1;
    end if;
  end loop;

  perform public.log_audit_event(
    'leave.accrual.run', 'hr', 'info', 'leave_ledger_entries', null,
    'تشغيل الاستحقاق الشهري للإجازات',
    format('السنة %s الشهر %s', p_year, p_month),
    jsonb_build_object('year', p_year, 'month', p_month, 'granted', v_count)
  );
  return v_count;
end $$;

comment on function public.run_monthly_leave_accrual(integer,integer,integer) is
  'server-authored: استحقاق شهري idempotent للإجازات، لا يتجاوز الحد السنوي، يُستدعى من pg_cron أو full access.';

revoke execute on function public.run_monthly_leave_accrual(integer,integer,integer) from public, anon, authenticated;
grant execute on function public.run_monthly_leave_accrual(integer,integer,integer) to service_role;

-- =====================================================================
-- 3) تفعيل pg_cron وجدولة المهام (حارس آمن)
-- =====================================================================
-- ملاحظة: pg_cron متاح على Supabase المُدار. في البيئات التي لا تملكه
-- (بعض إعدادات db reset المحلية) نتجاوز الجدولة دون كسر الترحيل، ويُشغّل
-- المشغّل الخارجي (Scheduled Edge Functions) الدوال نفسها بنفس التواقيع.
do $cron$
declare
  v_has_cron boolean;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_has_cron;
  if not v_has_cron then
    raise notice 'pg_cron غير متاح في هذه البيئة؛ تُشغّل المهام عبر مشغّل خارجي بنفس تواقيع الدوال.';
    return;
  end if;

  create extension if not exists pg_cron;

  -- إزالة الجداول السابقة إن وُجدت لجعل الترحيل idempotent
  perform cron.unschedule(jobname)
  from cron.job
  where jobname in ('hr_request_sla','hr_leave_accrual','hr_retention_cleanup','hr_scheduled_reports');

  -- معالج SLA: كل 10 دقائق
  perform cron.schedule('hr_request_sla', '*/10 * * * *',
    $job$ select public.process_request_sla(500); $job$);

  -- الاستحقاق الشهري: أول كل شهر 00:30 (توقيت الخادم UTC؛ الدالة تحسب شهر القاهرة)
  perform cron.schedule('hr_leave_accrual', '30 0 1 * *',
    $job$ select public.run_monthly_leave_accrual(); $job$);

  -- تنظيف السجلات العابرة المنتهية: يوميًا 02:00
  perform cron.schedule('hr_retention_cleanup', '0 2 * * *',
    $job$ select public.cleanup_expired_ephemeral_records(1000); $job$);

  -- طابور التقارير المستحقة: كل 15 دقيقة
  perform cron.schedule('hr_scheduled_reports', '*/15 * * * *',
    $job$ select public.queue_due_scheduled_reports(); $job$);

  raise notice 'تمت جدولة مهام pg_cron الأربع بنجاح.';
end
$cron$;;

CREATE OR REPLACE FUNCTION public._build_attendance_statement_v251(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_now_local timestamp := now() at time zone 'Africa/Cairo';
  v_daily public.attendance_daily%rowtype;
  v_shift_id uuid;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_grace_out integer;
  v_start_override time;
  v_end_override time;
  v_shift_end_at timestamp;
  v_scheduled_minutes integer;
  v_is_scheduled boolean;
  v_is_excused boolean;
  v_is_future boolean;
  v_is_due boolean;
  v_is_open boolean;
  v_is_completed boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_status text;
  v_due_days integer := 0;
  v_upcoming_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_open_shift_days integer := 0;
  v_completed_presence_days integer := 0;
  v_completed_work_minutes integer := 0;
  v_compliance_work_minutes integer := 0;
  v_total_work_minutes integer := 0;
  v_total_required_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
begin
  v_result := public._build_attendance_statement_v186(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_status := coalesce(v_day_obj->>'status', '');
    v_is_scheduled := v_status not in ('راحة أسبوعية', 'عطلة رسمية');
    v_is_excused :=
      coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_is_future := v_is_scheduled and not v_is_excused and v_day > v_today;
    v_is_due := false;
    v_is_open := false;
    v_is_completed := false;
    v_missing_in := false;
    v_missing_out := false;

    select * into v_daily
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_day;

    -- Resolve the effective shift in the same order used by attendance punch:
    -- daily record -> published roster -> active employee assignment -> active
    -- official/default shift.  Roster time overrides win over shift times.
    v_shift_id := v_daily.shift_id;
    v_start_override := null;
    v_end_override := null;

    if v_shift_id is null then
      select rd.shift_id, rd.start_override, rd.end_override
        into v_shift_id, v_start_override, v_end_override
      from public.roster_days rd
      join public.work_rosters wr
        on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_day
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last, wr.created_at desc
      limit 1;
    end if;

    if v_shift_id is null then
      select sa.shift_id into v_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active
        and sa.effective_from <= v_day
        and (sa.effective_to is null or sa.effective_to >= v_day)
      order by sa.effective_from desc, sa.created_at desc
      limit 1;
    end if;

    if v_shift_id is null and v_is_scheduled then
      select s.id into v_shift_id
      from public.shifts s
      where s.is_active
      order by (s.code = 'OFFICIAL') desc,
               s.updated_at desc nulls last,
               s.created_at desc
      limit 1;
    end if;

    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    v_grace_out := 0;
    v_scheduled_minutes := 0;

    if v_shift_id is not null then
      select s.name,
             coalesce(v_start_override, s.start_time),
             coalesce(v_end_override, s.end_time),
             s.crosses_midnight or coalesce(v_end_override, s.end_time) <= coalesce(v_start_override, s.start_time),
             coalesce(s.break_minutes, 0),
             coalesce(s.grace_out_minutes, 0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses,
             v_shift_break, v_grace_out
      from public.shifts s
      where s.id = v_shift_id;

      if v_shift_start is not null and v_shift_end is not null then
        v_scheduled_minutes := greatest(
          0,
          (extract(epoch from (
            (v_day + v_shift_end
              + case when v_shift_crosses then interval '1 day' else interval '0' end)
            - (v_day + v_shift_start)
          )) / 60)::integer - v_shift_break
        );
        v_shift_end_at := v_day + v_shift_end
          + case when v_shift_crosses then interval '1 day' else interval '0' end
          + make_interval(mins => v_grace_out);
      else
        v_shift_end_at := v_day::timestamp + interval '1 day';
      end if;
    else
      -- Without a known shift, never accuse the current day before it ends.
      v_shift_end_at := v_day::timestamp + interval '1 day';
    end if;

    if v_is_scheduled then
      if v_is_future then
        v_upcoming_days := v_upcoming_days + 1;
        if v_status = 'غائب دون إذن' then
          v_status := 'يوم قادم';
        end if;
      else
        -- Approved leave/mission classifications from the legacy builder are
        -- preserved and excluded from attendance/hours denominators. Only
        -- ordinary attendance days are normalized here.
        if not v_is_excused then
          if v_daily.first_check_in is not null then
            v_is_due := true;
            v_present_days := v_present_days + 1;

            if v_daily.last_check_out is not null then
              v_is_completed := true;
              v_completed_presence_days := v_completed_presence_days + 1;
              v_completed_work_minutes :=
                v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
            elsif v_now_local <= v_shift_end_at then
              v_is_open := true;
              v_open_shift_days := v_open_shift_days + 1;
              v_status := 'حاضر — بانتظار الانصراف';
            else
              v_missing_out := true;
              v_missing_checkout := v_missing_checkout + 1;
              v_status := 'حضور ناقص — لم يسجل الانصراف';
            end if;
          elsif coalesce((v_day_obj->>'hasCorrection')::boolean, false)
                and not coalesce((v_day_obj->>'isAbsent')::boolean, false) then
            -- A correction can establish presence without a physical check-in.
            -- When a physical punch exists, the branch above must remain
            -- authoritative so an active shift still appears as open.
            v_is_due := true;
            v_present_days := v_present_days + 1;
          elsif v_daily.id is not null and v_daily.status = 'absent' then
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          elsif v_now_local <= v_shift_end_at then
            v_status := 'بانتظار تسجيل الحضور';
          else
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          end if;

          if v_is_due then
            v_due_days := v_due_days + 1;
          end if;

          if v_daily.id is not null
             and v_daily.first_check_in is null
             and v_daily.status <> 'absent'
             and v_now_local > v_shift_end_at then
            v_missing_in := true;
            v_missing_checkin := v_missing_checkin + 1;
          end if;

          v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
          v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
          v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
          v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

          -- An open shift is excluded from hours compliance until checkout.
          -- Past days, completed current shifts, and overdue current shifts are
          -- due; approved leave/mission days never enter the denominator.
          if v_daily.last_check_out is not null
             or v_now_local > v_shift_end_at then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
            v_compliance_work_minutes :=
              v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
          end if;
        end if;
      end if;
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'shiftName', coalesce(v_shift_name, ''),
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'requiredHours', round(v_scheduled_minutes / 60.0, 2),
      'status', v_status,
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out,
      'notes', case
        when v_is_open then 'لم تسجل حضورك في الوردية وهي زالت مفتوحة'
        else v_day_obj->>'notes'
      end
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_presence_days > 0
        then round(v_completed_work_minutes / 60.0 / v_completed_presence_days, 2)
        else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'attendanceRate', case when v_due_days > 0
        then round(v_present_days * 100.0 / v_due_days, 2)
        else 0 end,
      'hoursComplianceAvailable', (v_total_required_minutes > 0),
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_compliance_work_minutes * 100.0 / v_total_required_minutes, 2))
        else 0 end
    )
  );

  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION public._build_attendance_statement_v252(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    --  Approved leave for this day 
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

    --  Approved work assignment (mission / convoy / fundraising) 
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

    --  Approved attendance permit for this day 
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

    --  Approved attendance correction for this day 
    select jsonb_build_object(
             'typeLabel', case c.correction_type
                            when 'missing_check_in'  then 'تصحيح نقص بصمة حضور'
                            when 'missing_check_out' then 'تصحيح نقص بصمة انصراف'
                            when 'wrong_time'        then 'تصحيح خطأ بصمة'
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

    --  Still-missing punches (passthrough of 0251's computation) 
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
$function$;

CREATE OR REPLACE FUNCTION public._build_attendance_statement_v266(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_now_local timestamp := now() at time zone 'Africa/Cairo';
  v_daily public.attendance_daily%rowtype;
  v_shift_id uuid;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_grace_out integer;
  v_start_override time;
  v_end_override time;
  v_shift_end_at timestamp;
  v_scheduled_minutes integer;
  v_is_scheduled boolean;
  v_is_excused boolean;
  v_is_future boolean;
  v_is_due boolean;
  v_is_open boolean;
  v_is_completed boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_status text;
  v_due_days integer := 0;
  v_upcoming_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_open_shift_days integer := 0;
  v_completed_presence_days integer := 0;
  v_completed_work_minutes integer := 0;
  v_compliance_work_minutes integer := 0;
  v_total_work_minutes integer := 0;
  v_total_required_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
begin
  -- Keep 0252's per-day "details" explainability as the data source.
  v_result := public._build_attendance_statement_v252(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_status := coalesce(v_day_obj->>'status', '');
    v_is_scheduled := v_status not in ('راحة أسبوعية', 'عطلة رسمية');
    v_is_excused :=
      coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_is_future := v_is_scheduled and not v_is_excused and v_day > v_today;
    v_is_due := false;
    v_is_open := false;
    v_is_completed := false;
    v_missing_in := false;
    v_missing_out := false;

    select * into v_daily
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_day;

    -- Resolve effective shift (same precedence as 0251/attendance punch).
    v_shift_id := v_daily.shift_id;
    v_start_override := null;
    v_end_override := null;

    if v_shift_id is null then
      select rd.shift_id, rd.start_override, rd.end_override
        into v_shift_id, v_start_override, v_end_override
      from public.roster_days rd
      join public.work_rosters wr
        on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_day
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last, wr.created_at desc
      limit 1;
    end if;

    if v_shift_id is null then
      select sa.shift_id into v_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active
        and sa.effective_from <= v_day
        and (sa.effective_to is null or sa.effective_to >= v_day)
      order by sa.effective_from desc, sa.created_at desc
      limit 1;
    end if;

    if v_shift_id is null and v_is_scheduled then
      select s.id into v_shift_id
      from public.shifts s
      where s.is_active
      order by (s.code = 'OFFICIAL') desc,
               s.updated_at desc nulls last,
               s.created_at desc
      limit 1;
    end if;

    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    v_grace_out := 0;
    v_scheduled_minutes := 0;

    if v_shift_id is not null then
      select s.name,
             coalesce(v_start_override, s.start_time),
             coalesce(v_end_override, s.end_time),
             s.crosses_midnight or coalesce(v_end_override, s.end_time) <= coalesce(v_start_override, s.start_time),
             coalesce(s.break_minutes, 0),
             coalesce(s.grace_out_minutes, 0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses,
             v_shift_break, v_grace_out
      from public.shifts s
      where s.id = v_shift_id;

      if v_shift_start is not null and v_shift_end is not null then
        v_scheduled_minutes := greatest(
          0,
          (extract(epoch from (
            (v_day + v_shift_end
              + case when v_shift_crosses then interval '1 day' else interval '0' end)
            - (v_day + v_shift_start)
          )) / 60)::integer - v_shift_break
        );
        v_shift_end_at := v_day + v_shift_end
          + case when v_shift_crosses then interval '1 day' else interval '0' end
          + make_interval(mins => v_grace_out);
      else
        v_shift_end_at := v_day::timestamp + interval '1 day';
      end if;
    else
      v_shift_end_at := v_day::timestamp + interval '1 day';
    end if;

    if v_is_scheduled then
      if v_is_future then
        v_upcoming_days := v_upcoming_days + 1;
        if v_status = 'غائب دون إذن' then
          v_status := 'يوم قادم';
        end if;
      else
        if not v_is_excused then
          if v_daily.first_check_in is not null then
            -- Count presence the moment a check-in exists.
            v_present_days := v_present_days + 1;

            if v_daily.last_check_out is not null then
              -- Completed presence owes its scheduled minutes  due.
              v_is_due := true;
              v_is_completed := true;
              v_completed_presence_days := v_completed_presence_days + 1;
              v_completed_work_minutes :=
                v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
            elsif v_now_local <= v_shift_end_at then
              -- STILL OPEN: report as in-progress, DO NOT include in due-days.
              v_is_open := true;
              v_open_shift_days := v_open_shift_days + 1;
              v_status := 'حاضر  بانتظار الانصراف';
            else
              -- Overdue without checkout: it is due and flagged.
              v_is_due := true;
              v_missing_out := true;
              v_missing_checkout := v_missing_checkout + 1;
              v_status := 'حضور ناقص  لم يسجل الانصراف';
            end if;
          elsif coalesce((v_day_obj->>'hasCorrection')::boolean, false)
                and not coalesce((v_day_obj->>'isAbsent')::boolean, false) then
            -- Approved correction establishes presence without physical punch.
            v_is_due := true;
            v_present_days := v_present_days + 1;
          elsif v_daily.id is not null and v_daily.status = 'absent' then
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          elsif v_now_local <= v_shift_end_at then
            v_status := 'بانتظار تسجيل الحضور';
          else
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          end if;

          if v_is_due then
            v_due_days := v_due_days + 1;
          end if;

          if v_daily.id is not null
             and v_daily.first_check_in is null
             and v_daily.status <> 'absent'
             and v_now_local > v_shift_end_at then
            v_missing_in := true;
            v_missing_checkin := v_missing_checkin + 1;
          end if;

          v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
          v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
          v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
          v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

          -- Hours compliance: only past or checked-out days owe their minutes.
          if v_daily.last_check_out is not null
             or v_now_local > v_shift_end_at then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
            v_compliance_work_minutes :=
              v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
          end if;
        end if;
      end if;
    end if;

    -- Preserve everything 0252 emitted (details, notes, ) and refresh what we recomputed.
    v_day_obj := v_day_obj || jsonb_build_object(
      'shiftName', coalesce(v_shift_name, ''),
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'requiredHours', round(v_scheduled_minutes / 60.0, 2),
      'status', v_status,
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_presence_days > 0
        then round(v_completed_work_minutes / 60.0 / v_completed_presence_days, 2)
        else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      -- True attendance: only "due" days appear in the denominator,
      -- and the still-open current shift is NOT yet due.
      -- Numerator = present days that are themselves due (excludes open shift).
      'attendanceRate', case when v_due_days > 0
        then round(
               ((v_present_days - v_open_shift_days) * 100.0) / v_due_days,
               2
             )
        else 0 end,
      -- expose the exact pieces so the UI can show its tool-tip
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', (v_present_days - v_open_shift_days),
        'dueDays',      v_due_days,
        'presentDays',  v_present_days,
        'absentDays',   v_absent_days,
        'openShiftDays', v_open_shift_days,
        'upcomingDays', v_upcoming_days
      ),
      'hoursComplianceAvailable', (v_total_required_minutes > 0),
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_compliance_work_minutes * 100.0 / v_total_required_minutes, 2))
        else 0 end,
      -- ااتزا باساعات  دائ اأا اُفة فط
      'compliantWorkMinutes', v_compliance_work_minutes,
      'requiredMinutes', v_total_required_minutes
    )
  );

  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION public._build_attendance_statement_v286(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_summary jsonb;
  v_scheduled_days integer;
  v_present_days integer;
  v_open_shift_days integer;
  v_required_minutes integer;
  v_worked_minutes integer;
  v_deficit_minutes integer;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_reversed_absence_days integer := 0;
begin
  v_result := public._build_attendance_statement_v287(p_employee_id, p_year, p_month);
  v_summary := coalesce(v_result->'summary', '{}'::jsonb);

  -- Keep explicit administrative punch clearing visible in the returned JSON.
  -- Also do not label today absent before the assigned shift has ended.
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    if found and v_override.clear_check_in then
      v_day_obj := v_day_obj || jsonb_build_object('checkIn', null);
    end if;
    if found and v_override.clear_check_out then
      v_day_obj := v_day_obj || jsonb_build_object('checkOut', null);
    end if;

    if v_day = (now() at time zone 'Africa/Cairo')::date
       and coalesce((v_day_obj->>'isAbsent')::boolean, false)
       and nullif(v_day_obj->>'checkIn', '') is null
       and nullif(v_day_obj->>'shiftEnd', '') is not null
       and (now() at time zone 'Africa/Cairo')::time
         <= (v_day_obj->>'shiftEnd')::time then
      v_day_obj := v_day_obj || jsonb_build_object(
        'isAbsent', false,
        'isDue', false,
        'missingCheckIn', false,
        'missingCheckOut', false,
        'status', 'بانتظار حضور'
      );
      v_reversed_absence_days := v_reversed_absence_days + 1;
    end if;

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  if v_reversed_absence_days > 0 then
    v_summary := v_summary || jsonb_build_object(
      'absentDays', greatest(0,
        coalesce((v_summary->>'absentDays')::integer, 0) - v_reversed_absence_days),
      'dueScheduledDays', greatest(0,
        coalesce((v_summary->>'dueScheduledDays')::integer, 0) - v_reversed_absence_days)
    );
  end if;

  v_scheduled_days := greatest(0, coalesce((v_summary->>'scheduledDays')::integer, 0));
  v_present_days := greatest(0, coalesce((v_summary->>'presentDays')::integer, 0));
  v_open_shift_days := greatest(0, coalesce((v_summary->>'openShiftDays')::integer, 0));
  v_required_minutes := greatest(0, coalesce(
    (v_summary->'hoursRateBasis'->>'requiredMinutes')::integer,
    (v_summary->>'requiredMinutes')::integer,
    round(coalesce((v_summary->>'totalRequiredHours')::numeric, 0) * 60)::integer,
    0
  ));
  v_worked_minutes := greatest(0, coalesce(
    (v_summary->'hoursRateBasis'->>'workedMinutes')::integer,
    (v_summary->>'compliantWorkMinutes')::integer,
    round(coalesce((v_summary->>'totalWorkHours')::numeric, 0) * 60)::integer,
    0
  ));
  v_deficit_minutes := greatest(0, v_required_minutes - v_worked_minutes);

  v_summary := v_summary || jsonb_build_object(
    'attendanceRate', case when v_scheduled_days > 0
      then round(least(v_present_days, v_scheduled_days) * 100.0 / v_scheduled_days, 2)
      else 0
    end,
    'attendanceRateBasis', coalesce(v_summary->'attendanceRateBasis', '{}'::jsonb)
      || jsonb_build_object(
        'presentInDue', least(v_present_days, v_scheduled_days),
        'dueDays', v_scheduled_days,
        'presentDays', v_present_days,
        'openShiftDays', v_open_shift_days,
        'basis', 'full_month_scheduled_days'
      ),
    'hoursComplianceRate', case when v_required_minutes > 0
      then least(100, round(v_worked_minutes * 100.0 / v_required_minutes, 2))
      else 0
    end,
    'totalDeficitMinutes', v_deficit_minutes,
    'hoursRateBasis', coalesce(v_summary->'hoursRateBasis', '{}'::jsonb)
      || jsonb_build_object(
        'workedMinutes', v_worked_minutes,
        'requiredMinutes', v_required_minutes,
        'scheduledDays', v_scheduled_days,
        'deficitMinutes', v_deficit_minutes,
        'basis', 'full_month_required_minutes'
      )
  );

  return v_result || jsonb_build_object('days', v_days, 'summary', v_summary);
end
$function$;
