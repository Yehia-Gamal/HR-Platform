begin;

-- Restore content lost during the merge renumbering (0273 fix_kpi_admin_grants_and_diagnostics
-- was replaced by an empty placeholder before it was committed, while production already applied it).
-- The only surviving artifact is the diagnostic helper public.kpi_diag_run(date).
-- This recreates it byte-for-byte from the production definition so fresh databases
-- (dev reset / new environments) match production. Idempotent: CREATE OR REPLACE.
-- The function is a self-contained diagnostic only; nothing in app code calls it.

create or replace function public.kpi_diag_run(p_month date default null::date)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_month         date := coalesce(p_month, date_trunc('month', (now() at time zone 'Africa/Cairo'))::date);
  v_report        jsonb := '{}'::jsonb;
  v_template_id   uuid;
  v_policy_id     uuid;
  v_missing_funcs text[];
  v_missing_tbls  text[];
  v_missing_cols  jsonb;
  v_grants        jsonb;
  v_cycle_attempt text;
  v_catalog_attempt text;
  v_sqlstate      text;
  v_sqlerrm       text;
  v_ctx           text;
  v_dummy_cycle_id uuid;
begin
  -- أ) الدوال المساعدة + دوال KPI الحرجة
  select coalesce(array_agg(fname order by fname), '{}'::text[]) into v_missing_funcs
  from (
    values
      ('current_is_full_access'),
      ('current_is_executive_secretary'),
      ('current_is_hr_reviewer'),
      ('current_employee_id'),
      ('has_any_permission'),
      ('has_permission'),
      ('can_access_employee'),
      ('kpi_effective_deadline'),
      ('log_audit_event'),
      ('refresh_kpi_attendance_inputs'),
      ('generate_kpi_cycle_notifications'),
      ('get_kpi_admin_catalog'),
      ('create_kpi_cycle_admin'),
      ('manage_kpi_cycle'),
      ('reschedule_kpi_cycle'),
      ('decide_kpi_appeal'),
      ('get_kpi_cycle_report'),
      ('send_kpi_notifications_admin'),
      ('create_kpi_policy_version')
  ) as t(fname)
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = t.fname
  );
  v_report := jsonb_set(v_report, '{missingFunctions}', to_jsonb(v_missing_funcs), true);

  -- ب) الجداول
  select coalesce(array_agg(tname order by tname), '{}'::text[]) into v_missing_tbls
  from (
    values
      ('kpi_templates'),('kpi_criteria'),('kpi_cycles'),('kpi_evaluations'),
      ('kpi_scores'),('kpi_attendance_snapshots'),('kpi_policy_versions'),
      ('kpi_appeals'),('employees'),('attendance_daily'),('attendance_permits'),
      ('attendance_exceptions'),('attendance_corrections'),('attendance_events'),
      ('roster_days'),('leave_requests'),('requests'),('missions'),
      ('work_assignment_participants'),('work_assignments'),('shifts'),
      ('audit_events'),('user_roles'),('roles')
  ) as t(tname)
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = t.tname and c.relkind in ('r','p')
  );
  v_report := jsonb_set(v_report, '{missingTables}', to_jsonb(v_missing_tbls), true);

  -- ج) الأعمدة الحرجة (نفس قائمة 0271)
  with required(tbl, col) as (
    values
      ('kpi_templates','official_code'),('kpi_templates','is_active'),
      ('kpi_cycles','period_month'),('kpi_cycles','template_id'),('kpi_cycles','scheduled_open_at'),
      ('kpi_cycles','deadline_at'),('kpi_cycles','self_due_at'),('kpi_cycles','manager_due_at'),
      ('kpi_cycles','secretary_due_at'),('kpi_cycles','executive_due_at'),('kpi_cycles','opened_at'),
      ('kpi_cycles','opened_by'),('kpi_cycles','policy_version_id'),('kpi_cycles','use_parallel_flow'),
      ('kpi_cycles','locked_at'),('kpi_cycles','override_reason'),
      ('kpi_evaluations','employee_id'),('kpi_evaluations','cycle_id'),('kpi_evaluations','template_id'),
      ('kpi_evaluations','stage'),('kpi_evaluations','current_stage'),('kpi_evaluations','workflow_status'),
      ('kpi_evaluations','locked'),('kpi_evaluations','final_score'),('kpi_evaluations','final_rating'),
      ('kpi_policy_versions','is_active'),('kpi_policy_versions','attendance_rules'),('kpi_policy_versions','rating_bands'),
      ('kpi_scores','reviewer_stage'),('kpi_attendance_snapshots','evaluation_id'),
      ('employees','is_active'),('employees','is_deleted'),('employees','user_id'),('employees','status'),
      ('attendance_daily','employee_id'),('attendance_daily','work_date'),('attendance_daily','shift_id'),
      ('attendance_daily','late_minutes'),('attendance_daily','early_leave_minutes'),
      ('attendance_daily','work_minutes'),('attendance_daily','status'),
      ('attendance_daily','first_check_in'),('attendance_daily','last_check_out'),
      ('shifts','crosses_midnight'),('shifts','end_time'),('shifts','start_time'),('shifts','break_minutes'),
      ('work_assignment_participants','assignment_id'),
      ('work_assignments','counts_as_work_day'),('work_assignments','start_at'),
      ('work_assignments','end_at'),('work_assignments','status')
  )
  select coalesce(jsonb_agg(jsonb_build_object('table', tbl, 'column', col) order by tbl, col), '[]'::jsonb)
  into v_missing_cols
  from required
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = required.tbl and column_name = required.col
  );
  v_report := jsonb_set(v_report, '{missingColumns}', v_missing_cols, true);

  -- د) القالب والسياسة
  select id into v_template_id from public.kpi_templates where official_code = 'OFFICIAL_KPI_100' and is_active limit 1;
  select id into v_policy_id   from public.kpi_policy_versions where is_active limit 1;
  v_report := jsonb_set(v_report, '{officialTemplateId}', to_jsonb(v_template_id), true);
  v_report := jsonb_set(v_report, '{activePolicyId}',     to_jsonb(v_policy_id),    true);

  -- هـ) صلاحيات EXECUTE على كل التوقيعات المنشورة
  with fn(sig_label, args) as (
    values
      ('get_kpi_admin_catalog(date)',
        'public.get_kpi_admin_catalog(date)'),
      ('create_kpi_cycle_admin(8 args)',
        'public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean,boolean)'),
      ('manage_kpi_cycle(uuid,text,text,timestamptz)',
        'public.manage_kpi_cycle(uuid,text,text,timestamptz)'),
      ('reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)',
        'public.reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)'),
      ('decide_kpi_appeal(uuid,text,text)',
        'public.decide_kpi_appeal(uuid,text,text)'),
      ('refresh_kpi_attendance_inputs(uuid)',
        'public.refresh_kpi_attendance_inputs(uuid)'),
      ('get_kpi_cycle_report(uuid)',
        'public.get_kpi_cycle_report(uuid)'),
      ('send_kpi_notifications_admin(uuid)',
        'public.send_kpi_notifications_admin(uuid)'),
      ('kpi_diag_run(date)',
        'public.kpi_diag_run(date)')
  )
  select jsonb_object_agg(
    sig_label,
    jsonb_build_object(
      'authenticated', coalesce(has_function_privilege('authenticated', args, 'EXECUTE'), false),
      'service_role',  coalesce(has_function_privilege('service_role', args, 'EXECUTE'), false)
    )
  ) into v_grants from fn;
  v_report := jsonb_set(v_report, '{grants}', v_grants, true);

  -- و) نبضة بسيطة — استدعاء get_kpi_admin_catalog الحقيقي
  begin
    perform public.get_kpi_admin_catalog(v_month);
    v_catalog_attempt := 'OK';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
    v_catalog_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
  end;
  v_report := jsonb_set(v_report, '{catalogCall}', to_jsonb(v_catalog_attempt), true);

  -- ز) نبضة بسيطة — استدعاء create_kpi_cycle_admin الحقيقي مع فرض rollback
  if v_template_id is not null and v_policy_id is not null then
    begin
      v_dummy_cycle_id := public.create_kpi_cycle_admin(
        p_month             := v_month,
        p_template_id       := v_template_id,
        p_self_due          := now(),
        p_manager_due       := now(),
        p_secretary_due     := now(),
        p_executive_due     := now(),
        p_open_now          := false,
        p_use_parallel_flow := false
      );
      -- النجاح يلزمنا بالتراجع حتى لا نُنشئ دورة وهمية
      raise exception '__DIAG_FORCE_ROLLBACK__ cycle_id=%', v_dummy_cycle_id using errcode = 'P0001';
    exception when others then
      get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
      if v_sqlerrm like '__DIAG_FORCE_ROLLBACK__%' then
        v_cycle_attempt := 'OK — نجحت الدالة (لم تُحفظ الدورة بسبب التراجع التشخيصي)';
      else
        v_cycle_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
      end if;
    end;
  else
    v_cycle_attempt := 'SKIPPED — لا قالب رسمي نشط أو لا سياسة نشطة';
  end if;
  v_report := jsonb_set(v_report, '{createCycleCall}', to_jsonb(v_cycle_attempt), true);

  -- metadata
  v_report := jsonb_set(v_report, '{month}', to_jsonb(v_month), true);
  v_report := jsonb_set(v_report, '{diagAt}', to_jsonb(now()), true);
  v_report := jsonb_set(v_report, '{diagVersion}', to_jsonb('0273_v1'::text), true);
  return v_report;
end $function$;

-- Keep execute privileges matching the audit role (diagnostic only, like before).
grant execute on function public.kpi_diag_run(date) to authenticated;
grant execute on function public.kpi_diag_run(date) to service_role;

commit;
