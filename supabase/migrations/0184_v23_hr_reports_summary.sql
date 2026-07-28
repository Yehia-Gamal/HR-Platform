-- Migration 0184: V23 — get_hr_reports_summary RPC
-- إنشاء دالة ملخص تقارير HR للوحة المراقبة التنفيذية.
-- تُصحح الأخطاء في النسخة المركونة (0165) التي استخدمت أسماء أعمدة وقيم حالة غير صحيحة.
begin;

create or replace function public.get_hr_reports_summary()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $fn$
declare
  v_att jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
begin
  -- فحص الصلاحية
  if not (public.current_is_full_access()
          or public.has_permission('reports.people.read')
          or public.has_permission('attendance.record.read')) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- ═══ الحضور ═══
  -- attendance_events: event_type = 'CHECK_IN'/'CHECK_OUT' (أحرف كبيرة)
  -- event_at (timestamptz) — لا يوجد عمود event_date
  -- requires_review (وليس needs_review)
  select jsonb_build_object(
    'totalEvents', count(*),
    'checkIns',    count(*) filter (where event_type = 'CHECK_IN'  and event_at::date = current_date),
    'checkOuts',   count(*) filter (where event_type = 'CHECK_OUT' and event_at::date = current_date),
    'pendingReview', count(*) filter (where requires_review = true),
    'thisMonth',   count(*) filter (where event_at >= date_trunc('month', current_date))
  ) into v_att from public.attendance_events;

  -- ═══ الإجازات ═══
  -- leave_requests لا يحتوي على عمود status — الحالة في جدول requests عبر request_id
  select jsonb_build_object(
    'totalRequests', count(*),
    'approved',  count(*) filter (where r.status = 'approved'),
    'pending',   count(*) filter (where r.status = 'pending'),
    'rejected',  count(*) filter (where r.status = 'rejected'),
    'activeNow', count(*) filter (where r.status = 'approved'
                                    and current_date between lr.start_date and lr.end_date)
  ) into v_leaves
  from public.leave_requests lr
  join public.requests r on r.id = lr.request_id;

  -- ═══ التكليفات ═══
  -- work_assignments.status بأحرف كبيرة: APPROVED, IN_PROGRESS, COMPLETED, DRAFT, SUBMITTED, PENDING_APPROVAL ...
  select jsonb_build_object(
    'total',     count(*),
    'active',    count(*) filter (where status in ('APPROVED','IN_PROGRESS')),
    'completed', count(*) filter (where status = 'COMPLETED'),
    'pending',   count(*) filter (where status in ('DRAFT','SUBMITTED','PENDING_APPROVAL'))
  ) into v_assignments from public.work_assignments;

  -- ═══ مؤشرات الأداء ═══
  -- kpi_cycles.status: draft, open, in_review, suspended, finalized, locked (أحرف صغيرة)
  -- kpi_evaluations لا يحتوي على عمود status — يستخدم workflow_status (أحرف كبيرة)
  select jsonb_build_object(
    'activeCycles',         (select count(*) from public.kpi_cycles where status = 'open'),
    'totalEvaluations',     count(*),
    'pendingEvaluations',   count(*) filter (where workflow_status in (
      'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_HR','HR_REVIEW',
      'SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW','PARALLEL_REVIEW_IN_PROGRESS',
      'HR_EVALUATION_IN_PROGRESS','MANAGER_EVALUATION_IN_PROGRESS'
    )),
    'completedEvaluations', count(*) filter (where workflow_status in (
      'APPROVED','CLOSED','CYCLE_CLOSED','ARCHIVED','EXECUTIVE_ACKNOWLEDGED'
    ))
  ) into v_kpi from public.kpi_evaluations;

  -- ═══ النزاعات ═══
  -- الجدول: dispute_cases (وليس disputes)
  select jsonb_build_object(
    'total',     count(*),
    'open',      count(*) filter (where status in (
      'submitted','needs_more_information','accepted','under_review',
      'waiting_for_respondent','waiting_for_witness','session_scheduled',
      'session_completed','committee_deliberation','settlement_pending',
      'returned_to_committee','reopened','action_proposed','pending_execution'
    )),
    'resolved',  count(*) filter (where status in (
      'resolved_friendly','closed','decision_issued','executed',
      'cancelled_by_employee','rejected'
    )),
    'escalated', count(*) filter (where status = 'escalated_to_executive')
  ) into v_disputes from public.dispute_cases;

  -- ═══ طلبات الموقع ═══
  -- location_requests.status: pending, fulfilled, rejected, expired, cancelled
  select jsonb_build_object(
    'totalRequests', count(*),
    'pending',   count(*) filter (where status = 'pending'),
    'responded', count(*) filter (where status = 'fulfilled')
  ) into v_location from public.location_requests;

  return jsonb_build_object(
    'attendance',   v_att,
    'leaves',       v_leaves,
    'assignments',  v_assignments,
    'kpi',          v_kpi,
    'disputes',     v_disputes,
    'location',     v_location,
    'generatedAt',  now()
  );
end;
$fn$;

grant execute on function public.get_hr_reports_summary() to authenticated;

commit;
