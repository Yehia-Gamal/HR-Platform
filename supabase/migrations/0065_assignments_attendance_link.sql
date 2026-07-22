-- =====================================================================
-- 0065: ربط الإجازات وتكليفات العمل بالحضور + توسيع إعفاء KPI
-- =====================================================================
-- المرجع: المواصفة الرسمية (البنود 14،15،20).
-- المبدأ:
--   * الإجازة المعتمدة تظهر في الحضور بحالة on_leave (لا تُحتسب غيابًا).
--   * تكليف العمل المعتمد (مأمورية/قافلة/فاندي) وقت عمل رسمي ولا يُحتسب
--     غيابًا/تأخيرًا/نقص ساعات.
-- ملاحظة معمارية مهمة: roster_days.roster_id غير قابل للـNULL ويرتبط بـ
--   work_rosters، فلا يمكن كتابته من هذه التريغرات بلا روستر منشور. لذلك:
--   * الإجازة: نكتب attendance_daily.status='on_leave' للعرض الفوري.
--   * الإعفاء في KPI يُحسب من leave_requests (leave_exempt) ومن
--     work_assignments (assignment_exempt) مباشرة دون حاجة للروستر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) كاتب حالة الحضور عند اعتماد الإجازة → on_leave لكل يوم غير منتهٍ.
-- ---------------------------------------------------------------------
create or replace function public.tg_leave_attendance_on_approval()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lr public.leave_requests; v_day date;
begin
  if new.request_type <> 'leave' or new.status <> 'approved' or old.status = new.status then
    return new;
  end if;
  select * into v_lr from public.leave_requests where request_id = new.id;
  if not found then return new; end if;

  v_day := v_lr.start_date;
  while v_day <= v_lr.end_date loop
    insert into public.attendance_daily(employee_id, work_date, status)
    values(v_lr.employee_id, v_day, 'on_leave')
    on conflict on constraint attendance_daily_uq do update
      set status = 'on_leave', updated_at = now()
      where public.attendance_daily.is_finalized = false
        and public.attendance_daily.status <> 'on_leave';
    v_day := v_day + 1;
  end loop;

  perform public.log_audit_event(
    'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
    'وسم أيام الإجازة المعتمدة في الحضور',
    format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
    jsonb_build_object('requestId', new.id));
  return new;
end $$;

comment on function public.tg_leave_attendance_on_approval() is
  'يضبط أيام الإجازة المعتمدة كـ on_leave في الحضور (البند 14). إعفاء KPI يُحسب من leave_requests.';

drop trigger if exists trg_leave_attendance_on_approval on public.requests;
create trigger trg_leave_attendance_on_approval
  after update of status on public.requests
  for each row execute function public.tg_leave_attendance_on_approval();

-- ---------------------------------------------------------------------
-- 2) توسيع refresh_kpi_attendance_inputs ليشمل work_assignments في الإعفاء.
--    نعيد تعريف الدالة كاملة كما في 0058 مع إضافة assignment_exempt (الفاندي
--    والقافلة والمأمورية الجديدة عبر work_assignments، بجانب missions القديمة).
-- ---------------------------------------------------------------------
create or replace function public.refresh_kpi_attendance_inputs(p_cycle_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_cycle public.kpi_cycles; v_eval record; v_rules jsonb; v_count integer:=0;
 v_start date; v_end date; v_late integer; v_early integer; v_absent integer;
 v_missing integer; v_shortage numeric; v_pending boolean; v_score numeric; v_old numeric;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.attendance.refresh','performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 select attendance_rules into strict v_rules from public.kpi_policy_versions where id=v_cycle.policy_version_id;
 v_start:=date_trunc('month',v_cycle.period_month)::date;
 v_end:=least((v_start+interval '1 month'-interval '1 day')::date,(public.kpi_effective_deadline(v_cycle) at time zone 'Africa/Cairo')::date);

 for v_eval in
  select e.id,e.employee_id,c.id criterion_id from public.kpi_evaluations e
  join public.kpi_criteria c on c.template_id=e.template_id and c.code='ATTENDANCE'
  where e.cycle_id=p_cycle_id
 loop
  with daily as (
   select a.*,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='arrival' and p.status='approved') arrival_permit,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='departure' and p.status='approved') departure_permit,
    exists(select 1 from public.attendance_exceptions x where x.employee_id=a.employee_id and coalesce(x.work_date,a.work_date)=a.work_date and x.status in ('approved','resolved')) exception_settled,
    exists(select 1 from public.attendance_corrections x where x.employee_id=a.employee_id and x.work_date=a.work_date and x.status='approved') correction_settled,
    exists(select 1 from public.roster_days rd where rd.employee_id=a.employee_id and rd.work_date=a.work_date and rd.day_status in ('rest','holiday','leave','mission','cancelled')) roster_exempt,
    exists(select 1 from public.leave_requests lr join public.requests r on r.id=lr.request_id where lr.employee_id=a.employee_id and r.status='approved' and a.work_date between lr.start_date and lr.end_date) leave_exempt,
    exists(select 1 from public.missions m join public.requests r on r.id=m.request_id where m.employee_id=a.employee_id and r.status='approved' and a.work_date between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date) mission_exempt,
    exists(select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id=wp.assignment_id where wp.employee_id=a.employee_id and wa.status='APPROVED' and coalesce(wa.counts_as_work_day,true) and a.work_date between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date) assignment_exempt,
    greatest(0,
      case when s.crosses_midnight then extract(epoch from ((s.end_time+interval '24 hours')-s.start_time))/60
           else extract(epoch from (s.end_time-s.start_time))/60 end-coalesce(s.break_minutes,0)
    )::integer scheduled_minutes
   from public.attendance_daily a left join public.shifts s on s.id=a.shift_id
   where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end
  ), scored as (
   select *, (status in ('on_leave','holiday','weekend') or roster_exempt or leave_exempt or mission_exempt or assignment_exempt) exempt
   from daily
  )
  select
   count(*) filter(where not exempt and late_minutes>0 and not arrival_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and early_leave_minutes>0 and not departure_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status='absent' and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status<>'absent' and (status in ('partial','pending') or first_check_in is null or last_check_out is null) and not exception_settled and not correction_settled),
   coalesce(sum(case when not exempt and status<>'absent' and not exception_settled and not correction_settled and scheduled_minutes>work_minutes
     then least((v_rules->>'maxShortagePerDay')::numeric,ceil((scheduled_minutes-work_minutes)::numeric/60)*(v_rules->>'shortagePerHour')::numeric) else 0 end),0)
  into v_late,v_early,v_absent,v_missing,v_shortage from scored;

  select exists(
   select 1 from public.attendance_daily a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
   union all select 1 from public.attendance_events a where a.employee_id=v_eval.employee_id and (a.event_at at time zone 'Africa/Cairo')::date between v_start and v_end and a.requires_review
   union all select 1 from public.attendance_exceptions a where a.employee_id=v_eval.employee_id and coalesce(a.work_date,v_start) between v_start and v_end and a.status='open'
   union all select 1 from public.attendance_corrections a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
  ) into v_pending;

  v_score:=greatest(0,round(20-
   v_late*(v_rules->>'late')::numeric-v_early*(v_rules->>'earlyLeave')::numeric-
   v_absent*(v_rules->>'unexcusedAbsence')::numeric-v_missing*(v_rules->>'missingPunch')::numeric-v_shortage,2));
  select score into v_old from public.kpi_scores where evaluation_id=v_eval.id and criterion_id=v_eval.criterion_id and reviewer_stage='hr';
  insert into public.kpi_attendance_snapshots(evaluation_id,period_start,period_end,late_count,early_leave_count,unexcused_absence_count,shortage_penalty,missing_punch_count,score,has_pending_items,details,calculated_by)
  values(v_eval.id,v_start,v_end,v_late,v_early,v_absent,v_shortage,v_missing,v_score,v_pending,jsonb_build_object('rules',v_rules),auth.uid())
  on conflict(evaluation_id) do update set period_start=excluded.period_start,period_end=excluded.period_end,late_count=excluded.late_count,early_leave_count=excluded.early_leave_count,unexcused_absence_count=excluded.unexcused_absence_count,shortage_penalty=excluded.shortage_penalty,missing_punch_count=excluded.missing_punch_count,score=excluded.score,has_pending_items=excluded.has_pending_items,details=excluded.details,calculated_at=now(),calculated_by=auth.uid(),updated_at=now();
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_eval.criterion_id,v_score,'hr','محسوب آليًا من الحضور والانصراف والاستثناءات والتكليفات المعتمدة',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  if v_old is distinct from v_score then
   perform public.log_audit_event('kpi.attendance.recalculated','workflow','notice','kpi_evaluations',v_eval.id,'إعادة حساب درجة الحضور',null,jsonb_build_object('oldScore',v_old,'newScore',v_score,'late',v_late,'earlyLeave',v_early,'absence',v_absent,'missingPunch',v_missing,'shortagePenalty',v_shortage,'pending',v_pending));
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end $$;

-- =====================================================================
-- نهاية Migration 0065
-- =====================================================================
