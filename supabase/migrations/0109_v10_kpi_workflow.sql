-- V10 KPI workflow: employee -> direct manager -> HR -> direct manager final approval.
-- Historical stage values remain valid for old audit/history rows, but all new work uses
-- the canonical V10 stages and workflow statuses below.
begin;

create or replace function public.current_has_active_role(p_slugs text[])
returns boolean
language sql stable security definer
set search_path=public,pg_temp
as $$
  select exists(
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid()
      and r.slug=any(p_slugs)
      and (ur.effective_from is null or ur.effective_from<=now())
      and (ur.effective_to is null or ur.effective_to>now())
  );
$$;

create or replace function public.current_is_executive_secretary()
returns boolean
language sql stable security definer
set search_path=public,pg_temp
as $$
  select public.current_has_active_role(array['executive-secretary']);
$$;

create or replace function public.current_is_hr_reviewer()
returns boolean
language sql stable security definer
set search_path=public,pg_temp
as $$
  select public.current_has_active_role(array['hr-manager','hr-specialist']);
$$;

create or replace function public.kpi_is_direct_manager(p_employee_id uuid)
returns boolean
language sql stable security definer
set search_path=public,pg_temp
as $$
  select public.current_employee_id() is distinct from p_employee_id
    and exists(
      select 1
      from public.manager_relations mr
      where mr.employee_id=p_employee_id
        and mr.manager_employee_id=public.current_employee_id()
        and mr.relation_type='primary'
        and mr.effective_from<=current_date
        and (mr.effective_to is null or mr.effective_to>=current_date)
    )
    and public.has_permission('performance.kpi.manager_assess');
$$;

revoke all on function public.current_has_active_role(text[]) from public,anon;
revoke all on function public.current_is_executive_secretary() from public,anon;
revoke all on function public.current_is_hr_reviewer() from public,anon;
revoke all on function public.kpi_is_direct_manager(uuid) from public,anon;
grant execute on function public.current_has_active_role(text[]) to authenticated,service_role;
grant execute on function public.current_is_executive_secretary() to authenticated,service_role;
grant execute on function public.current_is_hr_reviewer() to authenticated,service_role;
grant execute on function public.kpi_is_direct_manager(uuid) to authenticated,service_role;

alter table public.kpi_cycles drop constraint if exists kpi_cycles_status_check;
alter table public.kpi_cycles add constraint kpi_cycles_status_check
  check(status in ('draft','open','in_review','suspended','finalized','locked'));

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_stage_check;
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_current_stage_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_stage_check check(stage in (
  'self','manager_review','hr_review','manager_final','finalized','closed','archived',
  'manager','hr','acknowledgement','secretary','executive'
));
alter table public.kpi_evaluations add constraint kpi_evaluations_current_stage_check check(current_stage in (
  'self','manager_review','hr_review','manager_final','finalized','closed','archived',
  'manager','hr','acknowledgement','secretary','executive'
));

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_workflow_status_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_workflow_status_check check(workflow_status in (
  'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW',
  'HR_REVIEW','RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL','MANAGER_APPROVED',
  'INCLUDED_IN_MONTHLY_REPORT','CYCLE_CLOSED','ARCHIVED','RETURNED_FOR_REVISION','OVERDUE',
  'NOT_STARTED','EMPLOYEE_INPUT_IN_PROGRESS','HR_DATA_PENDING','SESSION_SCHEDULED',
  'SESSION_COMPLETED','MANAGER_EVALUATION_IN_PROGRESS','HR_EVALUATION_IN_PROGRESS',
  'EMPLOYEE_ACKNOWLEDGEMENT_PENDING','EMPLOYEE_ACKNOWLEDGED','FINAL_REVIEW',
  'SENT_TO_EXECUTIVE_DIRECTOR','APPROVED','CLOSED'
));

alter table public.kpi_scores drop constraint if exists kpi_scores_reviewer_stage_check;
alter table public.kpi_scores add constraint kpi_scores_reviewer_stage_check check(reviewer_stage in (
  'self','manager','hr','manager_final','secretary','executive','finalized'
));

alter table public.kpi_evidence drop constraint if exists kpi_evidence_submitted_stage_check;
alter table public.kpi_evidence add constraint kpi_evidence_submitted_stage_check check(submitted_stage in (
  'self','manager_review','hr_review','manager_final','manager','hr','secretary','executive'
));

-- Move unfinished rows to the V10 route. Scores, evidence and stage history are retained.
update public.kpi_evaluations
set stage=case current_stage
      when 'manager' then 'manager_review'
      when 'hr' then 'hr_review'
      when 'acknowledgement' then 'manager_final'
      when 'secretary' then 'manager_final'
      when 'executive' then 'manager_final'
      else stage end,
    current_stage=case current_stage
      when 'manager' then 'manager_review'
      when 'hr' then 'hr_review'
      when 'acknowledgement' then 'manager_final'
      when 'secretary' then 'manager_final'
      when 'executive' then 'manager_final'
      else current_stage end,
    workflow_status=case current_stage
      when 'self' then case when workflow_status='NOT_STARTED' then 'DRAFT' else 'OPEN_FOR_SELF_EVALUATION' end
      when 'manager' then 'MANAGER_REVIEW'
      when 'hr' then 'HR_REVIEW'
      when 'acknowledgement' then 'RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL'
      when 'secretary' then 'RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL'
      when 'executive' then 'RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL'
      when 'finalized' then 'INCLUDED_IN_MONTHLY_REPORT'
      when 'closed' then 'CYCLE_CLOSED'
      else workflow_status end,
    updated_at=now()
where current_stage in ('self','manager','hr','acknowledgement','secretary','executive','finalized','closed');

create or replace function public.tg_kpi_stage_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order text[]:=array['self','manager_review','hr_review','manager_final','finalized','closed','archived'];
begin
 if new.current_stage is distinct from old.current_stage then
  insert into public.kpi_stage_history(evaluation_id,from_stage,to_stage,action,actor_employee_id,actor_user_id)
  values(new.id,old.current_stage,new.current_stage,
   case when coalesce(array_position(v_order,new.current_stage),0)>coalesce(array_position(v_order,old.current_stage),0) then 'advance' else 'return' end,
   public.current_employee_id(),auth.uid());
 end if;
 return new;
end $$;

create or replace function public.kpi_effective_score(p_evaluation_id uuid,p_criterion_id uuid)
returns numeric language sql stable security definer set search_path=public,pg_temp as $$
 select case
   when c.evaluator_stage='hr' then coalesce(
     max(s.score) filter(where s.reviewer_stage='secretary'),
     max(s.score) filter(where s.reviewer_stage='hr')
   )
   else coalesce(
     max(s.score) filter(where s.reviewer_stage='secretary'),
     max(s.score) filter(where s.reviewer_stage='manager')
   ) end
 from public.kpi_criteria c
 left join public.kpi_scores s on s.criterion_id=c.id and s.evaluation_id=p_evaluation_id
 where c.id=p_criterion_id
 group by c.evaluator_stage;
$$;

create or replace function public.get_kpi_validation_errors(p_evaluation_id uuid)
returns text[] language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_errors text[]:='{}'; v_total numeric;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if exists(
   select 1 from public.kpi_criteria c
   where c.template_id=v_eval.template_id and public.kpi_effective_score(v_eval.id,c.id) is null
 ) then v_errors:=array_append(v_errors,'لم تكتمل درجات البنود السبعة.'); end if;
 if not exists(select 1 from public.kpi_scores s join public.kpi_criteria c on c.id=s.criterion_id where s.evaluation_id=v_eval.id and s.reviewer_stage='self' group by s.evaluation_id having count(distinct s.criterion_id)=7)
 then v_errors:=array_append(v_errors,'التقييم الذاتي للبنود السبعة غير مكتمل.'); end if;
 if not exists(select 1 from public.kpi_attendance_snapshots a where a.evaluation_id=p_evaluation_id)
    or exists(select 1 from public.kpi_attendance_snapshots a where a.evaluation_id=p_evaluation_id and a.has_pending_items)
 then v_errors:=array_append(v_errors,'بيانات الحضور غير محسوبة أو ما زالت معلقة.'); end if;
 if (select count(*) from public.kpi_compliance_records where evaluation_id=p_evaluation_id and metric in ('PRAYER','HALAQA'))<>2
 then v_errors:=array_append(v_errors,'يجب على HR استكمال الصلاة والحلقة.'); end if;
 if nullif(trim(coalesce(v_eval.manager_comment,'')),'') is null
 then v_errors:=array_append(v_errors,'ملاحظة المدير مطلوبة قبل الاعتماد النهائي.'); end if;
 v_total:=public.kpi_total_score(p_evaluation_id);
 if v_total<0 or v_total>100 then v_errors:=array_append(v_errors,'المجموع النهائي يجب أن يكون بين صفر و100.'); end if;
 return v_errors;
end $$;

create or replace function public.save_kpi_goal(
 p_evaluation_id uuid,p_goal_id uuid,p_title text,p_description text,p_target_value numeric,
 p_achieved_value numeric,p_unit text,p_weight numeric,p_due_date date,p_evidence_source text,
 p_employee_note text,p_manager_note text,p_status text
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_id uuid; v_owner boolean; v_manager boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_owner:=v_eval.employee_id=public.current_employee_id();
 v_manager:=public.kpi_is_direct_manager(v_eval.employee_id);
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if p_status not in ('NOT_STARTED','IN_PROGRESS','COMPLETED','PARTIALLY_COMPLETED','BLOCKED','CANCELLED_BY_MANAGEMENT','DEFERRED_WITH_MANAGER_APPROVAL') then raise exception 'INVALID_GOAL_STATUS'; end if;
 if v_manager and v_eval.current_stage='manager_review' then
  if length(trim(coalesce(p_title,'')))<3 or p_target_value<=0 or p_achieved_value<0 or p_weight<=0 or p_weight>40 then raise exception 'INVALID_GOAL'; end if;
  if p_goal_id is null then
   insert into public.kpi_goals(evaluation_id,title,description,target_value,achieved_value,unit,weight,due_date,evidence_source,employee_note,manager_note,status,created_by)
   values(p_evaluation_id,trim(p_title),p_description,p_target_value,p_achieved_value,trim(p_unit),p_weight,p_due_date,p_evidence_source,p_employee_note,p_manager_note,p_status,auth.uid()) returning id into v_id;
  else
   update public.kpi_goals set title=trim(p_title),description=p_description,target_value=p_target_value,achieved_value=p_achieved_value,unit=trim(p_unit),weight=p_weight,due_date=p_due_date,evidence_source=p_evidence_source,employee_note=p_employee_note,manager_note=p_manager_note,status=p_status,updated_at=now()
   where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
  end if;
 elsif v_owner and v_eval.current_stage='self' and v_eval.workflow_status<>'DRAFT' and p_goal_id is not null then
  update public.kpi_goals set achieved_value=p_achieved_value,evidence_source=p_evidence_source,employee_note=p_employee_note,status=p_status,updated_at=now()
  where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_id is null then raise exception 'GOAL_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.goal.saved','workflow','info','kpi_goals',v_id,'حفظ هدف تقييم الأداء',null,jsonb_build_object('evaluationId',p_evaluation_id,'status',p_status));
 return v_id;
end $$;

create or replace function public.save_kpi_review_session(p_evaluation_id uuid,p_session jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_manager uuid; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.current_stage<>'manager_review' or not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 v_manager:=public.current_employee_id();
 if coalesce(p_session->>'mode','') not in ('ONSITE','REMOTE') then raise exception 'INVALID_SESSION_MODE'; end if;
 insert into public.kpi_review_sessions(evaluation_id,employee_id,manager_employee_id,scheduled_at,held_at,mode,discussion_summary,strengths,improvement_points,next_month_goals,employee_notes,manager_notes,employee_attended,manager_attended,manager_approved_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,v_manager,nullif(p_session->>'scheduledAt','')::timestamptz,nullif(p_session->>'heldAt','')::timestamptz,p_session->>'mode',nullif(trim(p_session->>'discussionSummary'),''),nullif(trim(p_session->>'strengths'),''),nullif(trim(p_session->>'improvementPoints'),''),nullif(trim(p_session->>'nextMonthGoals'),''),nullif(trim(p_session->>'employeeNotes'),''),nullif(trim(p_session->>'managerNotes'),''),coalesce((p_session->>'employeeAttended')::boolean,false),coalesce((p_session->>'managerAttended')::boolean,false),case when nullif(p_session->>'heldAt','') is not null then now() end,auth.uid())
 on conflict(evaluation_id) do update set scheduled_at=excluded.scheduled_at,held_at=excluded.held_at,mode=excluded.mode,discussion_summary=excluded.discussion_summary,strengths=excluded.strengths,improvement_points=excluded.improvement_points,next_month_goals=excluded.next_month_goals,employee_notes=excluded.employee_notes,manager_notes=excluded.manager_notes,employee_attended=excluded.employee_attended,manager_attended=excluded.manager_attended,manager_approved_at=excluded.manager_approved_at,updated_at=now()
 returning id into v_id;
 perform public.log_audit_event('kpi.session.saved','workflow','notice','kpi_review_sessions',v_id,'تسجيل جلسة تقييم الموظف والمدير',null,jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;

create or replace function public.save_kpi_compliance_metric(
 p_evaluation_id uuid,p_metric text,p_required integer,p_actual integer,p_exempt integer default 0,p_cancelled integer default 0,p_note text default null
)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_eligible integer; v_score numeric; v_criterion uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.current_stage<>'hr_review' or not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_metric not in ('PRAYER','HALAQA') or least(p_required,p_actual,p_exempt,p_cancelled)<0 then raise exception 'INVALID_COMPLIANCE_INPUT'; end if;
 v_eligible:=greatest(p_required-p_exempt-p_cancelled,0);
 if p_actual>v_eligible then raise exception 'ACTUAL_EXCEEDS_REQUIRED'; end if;
 v_score:=case when v_eligible=0 then 5 else round(p_actual::numeric/v_eligible*5,2) end;
 insert into public.kpi_compliance_records(evaluation_id,metric,required_count,actual_count,exempt_count,cancelled_count,calculated_score,note,approved_at,approved_by,created_by)
 values(p_evaluation_id,p_metric,p_required,p_actual,p_exempt,p_cancelled,v_score,p_note,now(),public.current_employee_id(),auth.uid())
 on conflict(evaluation_id,metric) do update set required_count=excluded.required_count,actual_count=excluded.actual_count,exempt_count=excluded.exempt_count,cancelled_count=excluded.cancelled_count,calculated_score=excluded.calculated_score,note=excluded.note,approved_at=now(),approved_by=public.current_employee_id(),updated_at=now();
 select c.id into strict v_criterion from public.kpi_criteria c where c.template_id=v_eval.template_id and c.code=p_metric;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,v_criterion,v_score,'hr',p_note,auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 perform public.log_audit_event('kpi.compliance.calculated','workflow','info','kpi_evaluations',p_evaluation_id,'احتساب معيار HR',null,jsonb_build_object('metric',p_metric,'score',v_score));
 return v_score;
end $$;

create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid,p_action text,p_scores jsonb default null,p_note text default null
)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_expected text; v_next text; v_workflow text;
 v_row jsonb; v_score numeric; v_criterion public.kpi_criteria; v_errors text[]; v_total numeric; v_rating text;
 v_required_count integer; v_received_count integer;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 case p_action
  when 'self' then v_expected:='self';v_next:='manager_review';v_workflow:='SUBMITTED_TO_DIRECT_MANAGER';
  when 'manager' then v_expected:='manager_review';v_next:='hr_review';v_workflow:='HR_REVIEW';
  when 'manager_review' then v_expected:='manager_review';v_next:='hr_review';v_workflow:='HR_REVIEW';
  when 'hr' then v_expected:='hr_review';v_next:='manager_final';v_workflow:='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL';
  when 'hr_review' then v_expected:='hr_review';v_next:='manager_final';v_workflow:='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL';
  when 'manager_final' then v_expected:='manager_final';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
  when 'finalize' then v_expected:='manager_final';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
  else raise exception 'INVALID_KPI_ACTION';
 end case;
 if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

 if v_expected='self' then
  if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id() or not public.has_permission('performance.kpi.self_assess') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if not public.kpi_is_direct_manager(v_eval.employee_id) and not exists(
    select 1 from public.manager_relations mr where mr.employee_id=v_eval.employee_id and mr.relation_type='primary'
      and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date)
  ) then raise exception 'DIRECT_MANAGER_NOT_ASSIGNED'; end if;
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id;
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
  select count(*) into v_received_count from jsonb_array_elements(p_scores);
  if v_received_count<>v_required_count then raise exception 'ALL_SELF_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id;
   if v_criterion.id is null then raise exception 'INVALID_SELF_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'self',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;
 elsif v_expected='manager_review' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id and evaluator_stage='manager';
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'MANAGER_SCORES_REQUIRED'; end if;
  select count(*) into v_received_count from jsonb_array_elements(p_scores);
  if v_received_count<>v_required_count then raise exception 'ALL_MANAGER_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='manager';
   if v_criterion.id is null then raise exception 'INVALID_MANAGER_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'manager',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;
 elsif v_expected='hr_review' then
  if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
  if not exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id)
     or exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id and has_pending_items) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
  if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;
 elsif v_expected='manager_final' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  v_errors:=public.get_kpi_validation_errors(v_eval.id);
  if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
  v_total:=public.kpi_total_score(v_eval.id);
  if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
  v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
 end if;

 update public.kpi_evaluations set
  stage=v_next,current_stage=v_next,workflow_status=v_workflow,
  manager_comment=case when v_expected in ('manager_review','manager_final') and nullif(trim(p_note),'') is not null then trim(p_note) else manager_comment end,
  manager_approved_at=case when v_expected='manager_final' then now() else manager_approved_at end,
  manager_approved_by=case when v_expected='manager_final' then public.current_employee_id() else manager_approved_by end,
  hr_comment=case when v_expected='hr_review' then nullif(trim(p_note),'') else hr_comment end,
  hr_approved_at=case when v_expected='hr_review' then now() else hr_approved_at end,
  hr_approved_by=case when v_expected='hr_review' then public.current_employee_id() else hr_approved_by end,
  final_score=case when v_next='finalized' then v_total else final_score end,
  final_rating=case when v_next='finalized' then v_rating else final_rating end,
  final_breakdown=case when v_next='finalized' then (select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id)) from public.kpi_criteria c where c.template_id=v_eval.template_id) else final_breakdown end,
  rating_policy_snapshot=case when v_next='finalized' then (select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id) else rating_policy_snapshot end,
  locked=(v_next='finalized'),updated_at=now()
 where id=v_eval.id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,'انتقال مرحلة تقييم الأداء',null,jsonb_build_object('action',p_action,'from',v_expected,'to',v_next,'workflowStatus',v_workflow,'note',p_note,'finalScore',v_total));
 if v_next='finalized' then
  perform public.log_audit_event('kpi.manager.approved','workflow','notice','kpi_evaluations',v_eval.id,'اعتماد المدير المباشر للنتيجة النهائية',p_note,jsonb_build_object('finalScore',v_total));
  perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
 end if;
 return v_eval;
end $$;

create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_from text;
begin
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'RETURN_REASON_REQUIRED'; end if;
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_from:=v_eval.current_stage;
 if v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if v_from='manager_review' and p_target_stage='self' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
 elsif v_from='hr_review' and p_target_stage in ('manager_review','self') then
  if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN'; end if;
 elsif v_from='manager_final' and p_target_stage in ('hr_review','self') then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
 elsif public.current_is_executive_secretary() and p_target_stage in ('self','manager_review','hr_review','manager_final') then
  null;
 else raise exception 'INVALID_RETURN_TARGET'; end if;
 update public.kpi_evaluations set stage=p_target_stage,current_stage=p_target_stage,workflow_status='RETURNED_FOR_REVISION',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now()
 where id=p_evaluation_id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,'إعادة التقييم للتصحيح',trim(p_note),jsonb_build_object('from',v_from,'to',p_target_stage));
 return v_eval;
end $$;

create or replace function public.override_kpi_score(p_evaluation_id uuid,p_criterion_id uuid,p_score numeric,p_reason text)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_max numeric; v_old numeric;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'OVERRIDE_REASON_REQUIRED'; end if;
 select c.max_score into strict v_max from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id where e.id=p_evaluation_id and c.id=p_criterion_id;
 if p_score<0 or p_score>v_max then raise exception 'SCORE_OUT_OF_RANGE'; end if;
 select public.kpi_effective_score(p_evaluation_id,p_criterion_id) into v_old;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,p_criterion_id,p_score,'secretary',trim(p_reason),auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 update public.kpi_evaluations set final_score=null,final_rating=null,final_breakdown=null,locked=false,
  stage='manager_final',current_stage='manager_final',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',updated_at=now()
 where id=p_evaluation_id;
 perform public.log_audit_event('kpi.score.overridden','workflow','warning','kpi_evaluations',p_evaluation_id,'تعديل استثنائي موثق لدرجة KPI',trim(p_reason),jsonb_build_object('criterionId',p_criterion_id,'oldScore',v_old,'newScore',p_score));
 return p_score;
end $$;

create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid;
 v_open timestamptz; v_deadline timestamptz; v_status text:='draft';
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 if coalesce(p_open_now,false) and now() between v_open and v_deadline then v_status:='open'; end if;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),updated_at=now()
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
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI وفق V10',null,jsonb_build_object('month',v_month,'openAt',v_open,'deadline',v_deadline,'status',v_status));
 return v_id;
end $$;

create or replace function public.manage_kpi_cycle(p_cycle_id uuid,p_action text,p_reason text,p_extended_until timestamptz default null)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_old text;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
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

create or replace function public.reschedule_kpi_cycle(p_cycle_id uuid,p_open_at timestamptz,p_deadline_at timestamptz,p_reason text)
returns public.kpi_cycles language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 or p_open_at is null or p_deadline_at is null or p_deadline_at<=p_open_at then raise exception 'INVALID_SCHEDULE'; end if;
 update public.kpi_cycles set scheduled_open_at=p_open_at,deadline_at=p_deadline_at,extended_until=null,
  self_due_at=p_deadline_at,manager_due_at=p_deadline_at,secretary_due_at=p_deadline_at,executive_due_at=p_deadline_at,
  override_reason=trim(p_reason),overridden_at=now(),overridden_by=public.current_employee_id(),updated_at=now()
 where id=p_cycle_id returning * into v_cycle;
 if v_cycle.id is null then raise exception 'CYCLE_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.cycle.rescheduled','workflow','warning','kpi_cycles',p_cycle_id,'تعديل موعد دورة KPI',trim(p_reason),jsonb_build_object('openAt',p_open_at,'deadlineAt',p_deadline_at));
 return v_cycle;
end $$;

create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles; v_editable text; v_locked boolean; v_criteria jsonb;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);
 if not v_locked then
  if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_editable:='self';
  elsif v_eval.current_stage='manager_review' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_review';
  elsif v_eval.current_stage='hr_review' and public.current_is_hr_reviewer() then v_editable:='hr_review';
  elsif v_eval.current_stage='manager_final' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_final';
  end if;
 end if;
 if v_editable='manager_review' and v_eval.workflow_status='SUBMITTED_TO_DIRECT_MANAGER' then
  update public.kpi_evaluations set workflow_status='MANAGER_REVIEW',updated_at=now() where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.manager.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء المدير المباشر مراجعة التقييم',null,null);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',case when v_editable='self' then true when v_editable='manager_review' then c.evaluator_stage='manager' else false end,
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}'::jsonb)
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;
 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'cycle',jsonb_build_object('id',v_cycle.id,'status',v_cycle.status,'scheduledOpenAt',v_cycle.scheduled_open_at,'deadlineAt',v_cycle.deadline_at,'extendedUntil',v_cycle.extended_until,'effectiveDeadline',public.kpi_effective_deadline(v_cycle)),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'description',g.description,'targetValue',g.target_value,'achievedValue',g.achieved_value,'unit',g.unit,'weight',g.weight,'dueDate',g.due_date,'evidenceSource',g.evidence_source,'employeeNote',g.employee_note,'managerNote',g.manager_note,'status',g.status,'calculatedScore',g.calculated_score) order by g.created_at) from public.kpi_goals g where g.evaluation_id=v_eval.id),'[]'::jsonb),
  'session',(select jsonb_build_object('id',s.id,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'mode',s.mode,'discussionSummary',s.discussion_summary,'strengths',s.strengths,'improvementPoints',s.improvement_points,'nextMonthGoals',s.next_month_goals,'employeeNotes',s.employee_notes,'managerNotes',s.manager_notes,'employeeAttended',s.employee_attended,'managerAttended',s.manager_attended,'employeeConfirmedAt',s.employee_confirmed_at) from public.kpi_review_sessions s where s.evaluation_id=v_eval.id),
  'compliance',coalesce((select jsonb_agg(jsonb_build_object('metric',r.metric,'requiredCount',r.required_count,'actualCount',r.actual_count,'exemptCount',r.exempt_count,'cancelledCount',r.cancelled_count,'score',r.calculated_score,'note',r.note)) from public.kpi_compliance_records r where r.evaluation_id=v_eval.id),'[]'::jsonb),
  'attendance',(select jsonb_build_object('periodStart',a.period_start,'periodEnd',a.period_end,'lateCount',a.late_count,'earlyLeaveCount',a.early_leave_count,'unexcusedAbsenceCount',a.unexcused_absence_count,'shortagePenalty',a.shortage_penalty,'missingPunchCount',a.missing_punch_count,'score',a.score,'hasPendingItems',a.has_pending_items,'calculatedAt',a.calculated_at) from public.kpi_attendance_snapshots a where a.evaluation_id=v_eval.id),
  'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'criterionId',x.criterion_id,'type',x.evidence_type,'title',x.title,'description',x.description,'storagePath',x.storage_path,'externalUrl',x.external_url,'submittedStage',x.submitted_stage,'createdAt',x.created_at) order by x.created_at) from public.kpi_evidence x where x.evaluation_id=v_eval.id),'[]'::jsonb),
  'validationErrors',to_jsonb(public.get_kpi_validation_errors(v_eval.id)),
  'lastUpdatedAt',coalesce(v_eval.updated_at,v_eval.created_at)
 );
end $$;

create or replace function public.add_kpi_evidence(p_evaluation_id uuid,p_criterion_id uuid,p_type text,p_title text,p_description text default null,p_storage_path text default null,p_external_url text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_stage text; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.locked then raise exception 'EVALUATION_LOCKED'; end if;
 if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_stage:='self';
 elsif v_eval.current_stage='manager_review' and public.kpi_is_direct_manager(v_eval.employee_id) then v_stage:='manager_review';
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_type not in ('document','link','note','task','report','other') or length(trim(coalesce(p_title,'')))<3 then raise exception 'INVALID_EVIDENCE'; end if;
 if p_criterion_id is not null and not exists(select 1 from public.kpi_criteria where id=p_criterion_id and template_id=v_eval.template_id) then raise exception 'INVALID_CRITERION'; end if;
 insert into public.kpi_evidence(evaluation_id,criterion_id,evidence_type,title,description,storage_path,external_url,submitted_stage,submitted_by,created_by)
 values(p_evaluation_id,p_criterion_id,p_type,trim(p_title),p_description,p_storage_path,p_external_url,v_stage,public.current_employee_id(),auth.uid()) returning id into v_id;
 perform public.log_audit_event('kpi.evidence.added','workflow','info','kpi_evidence',v_id,'إضافة دليل إلى التقييم',null,jsonb_build_object('evaluationId',p_evaluation_id,'criterionId',p_criterion_id));
 return v_id;
end $$;

create or replace function public.get_kpi_admin_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date;
begin
 if not (public.current_is_executive_secretary() or public.current_is_hr_reviewer() or public.has_any_permission(array['performance.kpi.read','performance.kpi.report.read','reports.performance.read'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'month',v_month,'canManageCycles',public.current_is_executive_secretary(),
  'officialTemplateId',(select id from public.kpi_templates where official_code='OFFICIAL_KPI_100'),
  'cycles',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'periodMonth',c.period_month,'status',c.status,'templateId',c.template_id,'templateName',t.name_ar,'selfDueAt',c.self_due_at,'managerDueAt',c.manager_due_at,'secretaryDueAt',c.secretary_due_at,'executiveDueAt',c.executive_due_at,'scheduledOpenAt',c.scheduled_open_at,'deadlineAt',c.deadline_at,'extendedUntil',c.extended_until,'effectiveDeadline',public.kpi_effective_deadline(c),'openedAt',c.opened_at,'lockedAt',c.locked_at,'overrideReason',c.override_reason,'evaluations',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id),'finalized',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.current_stage in ('finalized','closed','archived')),'overdue',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.workflow_status='OVERDUE'),'averageScore',(select round(avg(e.final_score),2) from public.kpi_evaluations e where e.cycle_id=c.id and e.final_score is not null)) order by c.period_month desc) from public.kpi_cycles c left join public.kpi_templates t on t.id=c.template_id where c.period_month between (v_month-interval '6 months')::date and (v_month+interval '1 month')::date),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name_ar,'version',t.version,'active',t.is_active,'officialCode',t.official_code,'criteria',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'code',k.code,'name',k.name_ar,'weight',k.weight,'maxScore',k.max_score,'sourceType',k.source_type,'attendanceMetric',k.attendance_metric,'evaluatorStage',k.evaluator_stage,'calculationMethod',k.calculation_method,'requiresEvidence',k.requires_evidence) order by k.sort_order) from public.kpi_criteria k where k.template_id=t.id),'[]'::jsonb)) order by t.created_at desc) from public.kpi_templates t),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'evaluationId',a.evaluation_id,'employeeId',a.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'reason',a.reason,'requestedOutcome',a.requested_outcome,'status',a.status,'submittedAt',a.submitted_at,'resolutionDueAt',a.resolution_due_at,'reviewNote',a.review_note) order by a.submitted_at desc) from public.kpi_appeals a join public.employees e on e.id=a.employee_id where a.status in ('submitted','under_review')),'[]'::jsonb),
  'stageCounts',coalesce((select jsonb_object_agg(x.current_stage,x.count) from (select e.current_stage,count(*) count from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=v_month group by e.current_stage)x),'{}'::jsonb),
  'policy',(select jsonb_build_object('id',id,'version',version,'name',name_ar,'weights',criteria_weights,'attendanceRules',attendance_rules,'ratingBands',rating_bands) from public.kpi_policy_versions where is_active),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.get_kpi_cycle_report(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles;
begin
 if not (public.current_is_executive_secretary() or public.current_is_hr_reviewer() or public.has_any_permission(array['performance.kpi.report.read','reports.performance.read'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 return jsonb_build_object(
  'cycleId',v_cycle.id,'periodMonth',v_cycle.period_month,'status',v_cycle.status,'deadlineAt',public.kpi_effective_deadline(v_cycle),
  'summary',(select jsonb_build_object('total',count(*),'approved',count(*) filter(where current_stage in ('finalized','closed','archived')),'overdue',count(*) filter(where workflow_status='OVERDUE'),'averageScore',round(avg(final_score),2)) from public.kpi_evaluations where cycle_id=p_cycle_id),
  'distribution',(select coalesce(jsonb_object_agg(coalesce(final_rating,'غير مكتمل'),count),'{}'::jsonb) from (select final_rating,count(*) count from public.kpi_evaluations where cycle_id=p_cycle_id group by final_rating)x),
  'evaluations',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,'stage',e.current_stage,'workflowStatus',e.workflow_status,'finalScore',e.final_score,'finalRating',e.final_rating,'breakdown',e.final_breakdown,'attendance',(select to_jsonb(a)-'id'-'evaluation_id' from public.kpi_attendance_snapshots a where a.evaluation_id=e.id)) order by emp.full_name_ar) from public.kpi_evaluations e join public.employees emp on emp.id=e.employee_id where e.cycle_id=p_cycle_id),'[]'::jsonb),
  'generatedAt',now()
 );
end $$;

create or replace function public.process_kpi_cycle_schedule(p_at timestamptz default now())
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_count integer:=0;
begin
 for v_cycle in select * from public.kpi_cycles where status='draft' and scheduled_open_at<=p_at and p_at<=coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='open',opened_at=p_at,updated_at=p_at where id=v_cycle.id;
  update public.kpi_evaluations set locked=false,workflow_status='OPEN_FOR_SELF_EVALUATION',updated_at=p_at where cycle_id=v_cycle.id and current_stage='self';
  perform public.log_audit_event('kpi.cycle.auto_opened','workflow','notice','kpi_cycles',v_cycle.id,'فتح دورة KPI تلقائيًا',null,jsonb_build_object('at',p_at));
  v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at);
 for v_cycle in select * from public.kpi_cycles where status='open' and p_at>coalesce(extended_until,deadline_at) for update loop
  update public.kpi_cycles set status='locked',locked_at=p_at,updated_at=p_at where id=v_cycle.id;
  update public.kpi_evaluations set
   workflow_status=case when current_stage='finalized' then 'CYCLE_CLOSED' else 'OVERDUE' end,
   current_stage=case when current_stage='finalized' then 'closed' else current_stage end,
   stage=case when stage='finalized' then 'closed' else stage end,
   locked=true,updated_at=p_at where cycle_id=v_cycle.id;
  perform public.log_audit_event('kpi.cycle.auto_closed','workflow','warning','kpi_cycles',v_cycle.id,'إغلاق دورة KPI تلقائيًا بعد الموعد',null,jsonb_build_object('at',p_at));
  v_count:=v_count+1;
 end loop;
 perform public.generate_kpi_cycle_notifications(p_at+interval '1 second');
 return v_count;
end $$;

create or replace function public.acknowledge_kpi_evaluation(p_evaluation_id uuid,p_note text default null,p_appeal_reason text default null)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.employee_id<>public.current_employee_id() or v_eval.current_stage not in ('finalized','closed','archived') then raise exception 'FORBIDDEN_OR_WRONG_STAGE'; end if;
 update public.kpi_evaluations set employee_comment=nullif(trim(p_note),''),employee_acknowledged_at=coalesce(employee_acknowledged_at,now()),updated_at=now() where id=p_evaluation_id returning * into v_eval;
 if nullif(trim(coalesce(p_appeal_reason,'')),'') is not null then perform public.submit_kpi_appeal(p_evaluation_id,p_appeal_reason,null); end if;
 perform public.log_audit_event('kpi.employee.acknowledged','workflow','info','kpi_evaluations',p_evaluation_id,'اطلاع الموظف على نتيجة KPI',p_note,null);
 return v_eval;
end $$;

create or replace function public.submit_kpi_appeal(p_evaluation_id uuid,p_reason text,p_requested_outcome text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if v_eval.employee_id<>public.current_employee_id() or v_eval.current_stage not in ('finalized','closed','archived') then raise exception 'FORBIDDEN_OR_NOT_AVAILABLE'; end if;
 if length(trim(p_reason))<10 then raise exception 'REASON_TOO_SHORT'; end if;
 insert into public.kpi_appeals(evaluation_id,employee_id,reason,requested_outcome,status,resolution_due_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,trim(p_reason),p_requested_outcome,'submitted',now()+interval '7 days',auth.uid())
 on conflict(evaluation_id,employee_id) do update set reason=excluded.reason,requested_outcome=excluded.requested_outcome,status='submitted',submitted_at=now(),review_note=null,reviewed_at=null,reviewed_by=null,updated_at=now()
 returning id into v_id;
 perform public.log_audit_event('kpi.appeal.submitted','workflow','warning','kpi_appeals',v_id,'تقديم اعتراض على KPI',trim(p_reason),jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;

create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then
  update public.kpi_evaluations set stage='manager_final',current_stage='manager_final',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now() where id=v.evaluation_id;
 end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض KPI',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
end $$;

revoke execute on function public.reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text) to authenticated;

commit;
