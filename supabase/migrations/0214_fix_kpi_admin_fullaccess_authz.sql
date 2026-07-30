-- 0214: إصلاح صلاحيات full-access للوظائف الإدارية لدورات KPI
-- المشكلة: get_kpi_admin_catalog يعطي canManageCycles=true للمستخدم full-access،
-- لكن 5 وظائف mutation ترفض full-access وتقبل executive_secretary فقط.
-- الحل: إضافة current_is_full_access() لجميع الوظائف المتأثرة.

begin;

-- 1. manage_kpi_cycle — التحكم في حالة الدورة (فتح/إغلاق/تعليق/...)
create or replace function public.manage_kpi_cycle(p_cycle_id uuid,p_action text,p_reason text,p_extended_until timestamptz default null)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_old text;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'CONTROL_REASON_REQUIRED'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id for update;
 v_old:=v_cycle.status;
 case p_action
  when 'open' then
   if v_cycle.status not in ('draft','suspended','in_review') then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='open',opened_at=coalesce(opened_at,now()),opened_by=public.current_employee_id(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when current_stage='self' then 'OPEN_FOR_SELF_EVALUATION' when workflow_status in ('OVERDUE','CYCLE_CLOSED') then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'reopen' then
   if v_cycle.status not in ('locked','suspended','in_review') then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='open',locked_at=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when workflow_status in ('OVERDUE','CYCLE_CLOSED') then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'extend' then
   if p_extended_until is null or p_extended_until<=coalesce(v_cycle.extended_until,v_cycle.deadline_at,now()) then raise exception 'INVALID_EXTENSION_DEADLINE'; end if;
   update public.kpi_cycles set status='open',extended_until=p_extended_until,locked_at=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=false,workflow_status=case when workflow_status='OVERDUE' then 'RETURNED_FOR_REVISION' else workflow_status end,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'suspend' then
   if v_cycle.status<>'open' then raise exception 'INVALID_CYCLE_STATE'; end if;
   update public.kpi_cycles set status='suspended',override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=true,updated_at=now() where cycle_id=p_cycle_id and current_stage not in ('finalized','closed','archived');
  when 'cancel_open' then
   if v_cycle.status not in ('open','draft') then raise exception 'INVALID_CYCLE_STATE'; end if;
   if exists(select 1 from public.kpi_evaluations e where e.cycle_id=p_cycle_id and (e.current_stage<>'self' or exists(select 1 from public.kpi_scores s where s.evaluation_id=e.id and s.reviewer_stage='self'))) then raise exception 'CYCLE_ALREADY_STARTED'; end if;
   update public.kpi_cycles set status='draft',opened_at=null,opened_by=null,override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set locked=true,workflow_status='DRAFT',updated_at=now() where cycle_id=p_cycle_id;
  when 'close' then
   update public.kpi_cycles set status='locked',locked_at=now(),override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
   update public.kpi_evaluations set
    workflow_status=case when current_stage='finalized' then 'CYCLE_CLOSED' else 'OVERDUE' end,
    current_stage=case when current_stage='finalized' then 'closed' else current_stage end,
    stage=case when stage='finalized' then 'closed' else stage end,
    locked=true,updated_at=now()
   where cycle_id=p_cycle_id;
  when 'archive' then
   if v_cycle.status<>'locked' then raise exception 'CYCLE_MUST_BE_CLOSED'; end if;
   update public.kpi_evaluations set stage='archived',current_stage='archived',workflow_status='ARCHIVED',locked=true,updated_at=now()
   where cycle_id=p_cycle_id and current_stage='closed';
   update public.kpi_cycles set override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now() where id=p_cycle_id;
  else raise exception 'INVALID_CYCLE_ACTION';
 end case;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 perform public.log_audit_event('kpi.cycle.'||p_action,'workflow','warning','kpi_cycles',p_cycle_id,'تحكم السكرتير التنفيذي في دورة KPI',trim(p_reason),jsonb_build_object('oldStatus',v_old,'newStatus',v_cycle.status,'extendedUntil',p_extended_until));
 return v_cycle;
end $$;

-- 2. create_kpi_cycle_admin — إنشاء دورة KPI جديدة
create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true,
 p_use_parallel_flow boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid;
 v_open timestamptz; v_deadline timestamptz; v_status text:='draft';
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 if coalesce(p_open_now,false) and now() between v_open and v_deadline then v_status:='open'; end if;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,use_parallel_flow,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,coalesce(p_use_parallel_flow,false),auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),
  use_parallel_flow=excluded.use_parallel_flow,updated_at=now()
 returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,locked,created_by)
 select e.id,v_id,v_template,'self','self',case when v_status='open' then 'OPEN_FOR_SELF_EVALUATION' else 'DRAFT' end,v_status<>'open',auth.uid()
 from public.employees e
 where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
   and not exists(
     select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
     where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
       and (ur.effective_from is null or ur.effective_from<=now())
       and (ur.effective_to is null or ur.effective_to>now())
   )
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI',null,jsonb_build_object('month',v_month,'openAt',v_open,'deadline',v_deadline,'status',v_status,'parallelFlow',p_use_parallel_flow));
 return v_id;
end $$;

-- 3. reschedule_kpi_cycle — تعديل مواعيد الدورة
create or replace function public.reschedule_kpi_cycle(p_cycle_id uuid,p_open_at timestamptz,p_deadline_at timestamptz,p_reason text)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 or p_open_at is null or p_deadline_at is null or p_deadline_at<=p_open_at then raise exception 'INVALID_SCHEDULE'; end if;
 update public.kpi_cycles set scheduled_open_at=p_open_at,deadline_at=p_deadline_at,extended_until=null,
  self_due_at=p_deadline_at,manager_due_at=p_deadline_at,secretary_due_at=p_deadline_at,executive_due_at=p_deadline_at,
  override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now()
 where id=p_cycle_id returning * into v_cycle;
 if v_cycle.id is null then raise exception 'CYCLE_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.cycle.rescheduled','workflow','warning','kpi_cycles',p_cycle_id,'تعديل موعد دورة KPI',trim(p_reason),jsonb_build_object('openAt',p_open_at,'deadlineAt',p_deadline_at));
 return v_cycle;
end $$;

-- 4. decide_kpi_appeal — البت في اعتراض KPI
create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then
  -- V17: route to manager_review (the finalization step), not manager_final
  update public.kpi_evaluations set stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now() where id=v.evaluation_id;
 end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض KPI',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
end $$;

-- 5. get_kpi_cycle_report — تقرير دورة KPI
create or replace function public.get_kpi_cycle_report(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary() or public.current_is_hr_reviewer() or public.has_any_permission(array['performance.kpi.report.read','reports.performance.read'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 return jsonb_build_object(
  'cycleId',v_cycle.id,'periodMonth',v_cycle.period_month,'status',v_cycle.status,'deadlineAt',public.kpi_effective_deadline(v_cycle),
  'summary',(select jsonb_build_object('total',count(*),'approved',count(*) filter(where current_stage in ('finalized','closed','archived')),'overdue',count(*) filter(where workflow_status='OVERDUE'),'averageScore',round(avg(final_score),2)) from public.kpi_evaluations where cycle_id=p_cycle_id),
  'distribution',(select coalesce(jsonb_object_agg(coalesce(final_rating,'غير مكتمل'),count),'{}'::jsonb) from (select final_rating,count(*) count from public.kpi_evaluations where cycle_id=p_cycle_id group by final_rating)x),
  'evaluations',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,'stage',e.current_stage,'workflowStatus',e.workflow_status,'finalScore',e.final_score,'finalRating',e.final_rating,'breakdown',e.final_breakdown,'attendance',(select to_jsonb(a)-'id'-'evaluation_id' from public.kpi_attendance_snapshots a where a.evaluation_id=e.id)) order by emp.full_name_ar) from public.kpi_evaluations e join public.employees emp on emp.id=e.employee_id where e.cycle_id=p_cycle_id),'[]'::jsonb),
  'generatedAt',now()
 );
end $$;

commit;
