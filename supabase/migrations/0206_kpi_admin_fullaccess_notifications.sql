begin;

-- ============================================================================
-- Migration 0205: إصلاح صفحة دورات KPI
--   1. canManageCycles يشمل full_access (ليس executive-secretary فقط)
--   2. RPC لإرسال إشعارات KPI يدويًا من الواجهة
--   3. إضافة evaluations مفصّلة في get_kpi_admin_catalog
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) إعادة تعريف get_kpi_admin_catalog مع canManageCycles موسّع
--    + إضافة evaluations لكل دورة (اسم الموظف + المرحلة + الدرجة)
-- ----------------------------------------------------------------------------
create or replace function public.get_kpi_admin_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date;
begin
 if not (public.current_is_full_access()
         or public.current_is_executive_secretary()
         or public.current_is_hr_reviewer()
         or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.report.read',
              'reports.performance.read','performance.cycle.manage',
              'performance.kpi.cycle.control'])) then
   raise exception 'FORBIDDEN';
 end if;

 return jsonb_build_object(
  'month', v_month,
  'canManageCycles', public.current_is_full_access() or public.current_is_executive_secretary(),
  'officialTemplateId', (select id from public.kpi_templates where official_code='OFFICIAL_KPI_100'),

  -- الدورات مع عدد التقييمات
  'cycles', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id,
      'periodMonth', c.period_month,
      'status', c.status,
      'templateId', c.template_id,
      'templateName', t.name_ar,
      'selfDueAt', c.self_due_at,
      'managerDueAt', c.manager_due_at,
      'secretaryDueAt', c.secretary_due_at,
      'executiveDueAt', c.executive_due_at,
      'scheduledOpenAt', c.scheduled_open_at,
      'deadlineAt', c.deadline_at,
      'extendedUntil', c.extended_until,
      'effectiveDeadline', public.kpi_effective_deadline(c),
      'openedAt', c.opened_at,
      'lockedAt', c.locked_at,
      'overrideReason', c.override_reason,
      'evaluations', (select count(*) from public.kpi_evaluations e where e.cycle_id=c.id),
      'finalized', (select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.current_stage in ('finalized','closed','archived')),
      'overdue', (select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.workflow_status='OVERDUE'),
      'averageScore', (select round(avg(e.final_score),2) from public.kpi_evaluations e where e.cycle_id=c.id and e.final_score is not null),
      -- ★ تفاصيل تقييمات الموظفين لكل دورة
      'employeeEvaluations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', e.id,
          'employeeId', e.employee_id,
          'employeeName', emp.full_name_ar,
          'employeeCode', emp.employee_code,
          'stage', e.current_stage,
          'workflowStatus', e.workflow_status,
          'finalScore', e.final_score,
          'finalRating', e.final_rating,
          'locked', e.locked
        ) order by emp.full_name_ar)
        from public.kpi_evaluations e
        join public.employees emp on emp.id=e.employee_id
        where e.cycle_id=c.id
      ), '[]'::jsonb)
    ) order by c.period_month desc)
    from public.kpi_cycles c
    left join public.kpi_templates t on t.id=c.template_id
    where c.period_month between (v_month - interval '6 months')::date
                             and (v_month + interval '1 month')::date
  ), '[]'::jsonb),

  -- القوالب
  'templates', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name_ar, 'version', t.version,
      'active', t.is_active, 'officialCode', t.official_code,
      'criteria', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', k.id, 'code', k.code, 'name', k.name_ar,
          'weight', k.weight, 'maxScore', k.max_score,
          'sourceType', k.source_type, 'attendanceMetric', k.attendance_metric,
          'evaluatorStage', k.evaluator_stage, 'calculationMethod', k.calculation_method,
          'requiresEvidence', k.requires_evidence
        ) order by k.sort_order)
        from public.kpi_criteria k where k.template_id=t.id
      ), '[]'::jsonb)
    ) order by t.created_at desc)
    from public.kpi_templates t
  ), '[]'::jsonb),

  -- الاعتراضات المعلقة
  'appeals', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'evaluationId', a.evaluation_id,
      'employeeId', a.employee_id, 'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code, 'reason', a.reason,
      'requestedOutcome', a.requested_outcome, 'status', a.status,
      'submittedAt', a.submitted_at, 'resolutionDueAt', a.resolution_due_at,
      'reviewNote', a.review_note
    ) order by a.submitted_at desc)
    from public.kpi_appeals a
    join public.employees e on e.id=a.employee_id
    where a.status in ('submitted','under_review')
  ), '[]'::jsonb),

  -- توزيع المراحل
  'stageCounts', coalesce((
    select jsonb_object_agg(x.current_stage, x.count)
    from (
      select e.current_stage, count(*) count
      from public.kpi_evaluations e
      join public.kpi_cycles c on c.id=e.cycle_id
      where c.period_month=v_month
      group by e.current_stage
    ) x
  ), '{}'::jsonb),

  -- السياسة النشطة
  'policy', (
    select jsonb_build_object(
      'id', id, 'version', version, 'name', name_ar,
      'weights', criteria_weights, 'attendanceRules', attendance_rules,
      'ratingBands', rating_bands
    )
    from public.kpi_policy_versions where is_active
  ),

  'lastUpdatedAt', now()
 );
end $$;

-- ----------------------------------------------------------------------------
-- 2) RPC لإرسال إشعارات KPI يدويًا (زر في الواجهة)
-- ----------------------------------------------------------------------------
create or replace function public.send_kpi_notifications_admin(p_cycle_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  -- فقط full-access أو السكرتير التنفيذي
  if not (public.current_is_full_access() or public.current_is_executive_secretary()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- إرسال إشعارات الدورة الحالية
  v_count := public.generate_kpi_cycle_notifications(now());

  perform public.log_audit_event(
    'kpi.notifications.manual_send', 'workflow', 'info',
    'kpi_cycles', p_cycle_id,
    'إرسال إشعارات KPI يدوي من الواجهة',
    null,
    jsonb_build_object('sentCount', v_count, 'triggeredBy', auth.uid())
  );

  return v_count;
end $$;

revoke all on function public.send_kpi_notifications_admin(uuid) from public, anon;
grant execute on function public.send_kpi_notifications_admin(uuid) to authenticated;

comment on function public.send_kpi_notifications_admin(uuid) is
  'إرسال إشعارات دورة KPI يدويًا من واجهة الإدارة. متاح فقط لـ full-access والسكرتير التنفيذي.';

commit;
