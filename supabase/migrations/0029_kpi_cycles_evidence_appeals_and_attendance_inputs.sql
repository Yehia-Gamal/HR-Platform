-- Migration 0029: advanced KPI cycle administration, evidence, history, appeals and objective attendance inputs
begin;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('performance.kpi.evidence.manage','performance','kpi_evidence','manage','إدارة أدلة تقييم الأداء','sensitive',true),
 ('performance.kpi.appeal.submit','performance','kpi_appeal','submit','تقديم اعتراض على تقييم نهائي','normal',false),
 ('performance.kpi.appeal.review','performance','kpi_appeal','review','مراجعة اعتراضات التقييم','sensitive',true),
 ('performance.kpi.attendance.refresh','performance','kpi_attendance','refresh','تحديث مدخل الحضور الموضوعي','sensitive',true)
on conflict(code) do nothing;

alter table public.kpi_cycles drop constraint if exists kpi_cycles_status_check;
alter table public.kpi_cycles add constraint kpi_cycles_status_check check(status in ('draft','open','in_review','finalized','locked'));
alter table public.kpi_cycles
 add column if not exists self_due_at timestamptz,
 add column if not exists manager_due_at timestamptz,
 add column if not exists secretary_due_at timestamptz,
 add column if not exists executive_due_at timestamptz,
 add column if not exists opened_at timestamptz,
 add column if not exists finalized_at timestamptz,
 add column if not exists template_id uuid references public.kpi_templates(id) on delete set null,
 add column if not exists notes text;

alter table public.kpi_criteria
 add column if not exists source_type text not null default 'manual' check(source_type in ('manual','attendance')),
 add column if not exists attendance_metric text check(attendance_metric in ('attendance_rate','punctuality_rate','completion_rate')),
 add column if not exists requires_evidence boolean not null default false,
 add column if not exists description text;

create table if not exists public.kpi_evidence (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null references public.kpi_evaluations(id) on delete cascade,
 criterion_id uuid references public.kpi_criteria(id) on delete set null,
 evidence_type text not null default 'document' check(evidence_type in ('document','link','note','task','report','other')),
 title text not null,
 description text,
 storage_path text,
 external_url text,
 submitted_stage text not null check(submitted_stage in ('self','manager','secretary','executive')),
 submitted_by uuid references public.employees(id) on delete set null,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);

create table if not exists public.kpi_stage_history (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null references public.kpi_evaluations(id) on delete cascade,
 from_stage text,
 to_stage text not null,
 action text not null default 'advance',
 note text,
 actor_employee_id uuid references public.employees(id) on delete set null,
 created_at timestamptz not null default now(),
 actor_user_id uuid references auth.users(id)
);

create table if not exists public.kpi_appeals (
 id uuid primary key default gen_random_uuid(),
 evaluation_id uuid not null references public.kpi_evaluations(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade,
 reason text not null,
 requested_outcome text,
 status text not null default 'submitted' check(status in ('submitted','under_review','accepted','rejected','closed')),
 submitted_at timestamptz not null default now(),
 review_note text,
 reviewed_by uuid references public.employees(id) on delete set null,
 reviewed_at timestamptz,
 resolution_due_at timestamptz,
 created_by uuid references auth.users(id),
 updated_at timestamptz,
 unique(evaluation_id,employee_id)
);

create index if not exists ix_kpi_evidence_evaluation on public.kpi_evidence(evaluation_id,criterion_id);
create index if not exists ix_kpi_stage_history_eval on public.kpi_stage_history(evaluation_id,created_at);
create index if not exists ix_kpi_appeals_status on public.kpi_appeals(status,submitted_at);

alter table public.kpi_evidence enable row level security;
alter table public.kpi_stage_history enable row level security;
alter table public.kpi_appeals enable row level security;

drop policy if exists kpi_evidence_read on public.kpi_evidence;
create policy kpi_evidence_read on public.kpi_evidence for select to authenticated using (
 exists(select 1 from public.kpi_evaluations e where e.id=kpi_evidence.evaluation_id and (
  e.employee_id=public.current_employee_id() or public.can_access_employee(e.employee_id,'performance.kpi.read')
  or public.has_any_permission(array['performance.kpi.secretary_review','performance.kpi.executive_review','performance.kpi.finalize']) or public.current_is_full_access()
 ))
);
drop policy if exists kpi_history_read on public.kpi_stage_history;
create policy kpi_history_read on public.kpi_stage_history for select to authenticated using (
 exists(select 1 from public.kpi_evaluations e where e.id=kpi_stage_history.evaluation_id and (
  e.employee_id=public.current_employee_id() or public.can_access_employee(e.employee_id,'performance.kpi.read')
  or public.has_any_permission(array['performance.kpi.secretary_review','performance.kpi.executive_review','performance.kpi.finalize']) or public.current_is_full_access()
 ))
);
drop policy if exists kpi_appeals_read on public.kpi_appeals;
create policy kpi_appeals_read on public.kpi_appeals for select to authenticated using (
 employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('performance.kpi.appeal.review')
);
revoke insert,update,delete on public.kpi_evidence,public.kpi_stage_history,public.kpi_appeals from authenticated;

create or replace function public.tg_kpi_stage_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.current_stage is distinct from old.current_stage then
  insert into public.kpi_stage_history(evaluation_id,from_stage,to_stage,action,actor_employee_id,actor_user_id)
  values(new.id,old.current_stage,new.current_stage,case when array_position(array['self','manager','secretary','executive','finalized'],new.current_stage)>array_position(array['self','manager','secretary','executive','finalized'],old.current_stage) then 'advance' else 'return' end,public.current_employee_id(),auth.uid());
 end if;
 return new;
end $$;
drop trigger if exists trg_kpi_stage_history on public.kpi_evaluations;
create trigger trg_kpi_stage_history after update of current_stage on public.kpi_evaluations for each row execute function public.tg_kpi_stage_history();

create or replace function public.get_kpi_admin_catalog(p_month date default date_trunc('month',(now() at time zone 'Africa/Cairo'))::date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_month date:=date_trunc('month',p_month)::date;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.kpi.read','performance.cycle.manage','performance.kpi.secretary_review','performance.kpi.executive_review'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'month',v_month,
  'cycles',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'periodMonth',c.period_month,'status',c.status,'templateId',c.template_id,'templateName',t.name_ar,'selfDueAt',c.self_due_at,'managerDueAt',c.manager_due_at,'secretaryDueAt',c.secretary_due_at,'executiveDueAt',c.executive_due_at,'openedAt',c.opened_at,'lockedAt',c.locked_at,'evaluations',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id),'finalized',(select count(*) from public.kpi_evaluations e where e.cycle_id=c.id and e.current_stage='finalized')) order by c.period_month desc) from public.kpi_cycles c left join public.kpi_templates t on t.id=c.template_id where c.period_month between (v_month-interval '6 months')::date and (v_month+interval '1 month')::date),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name_ar,'version',t.version,'active',t.is_active,'criteria',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'name',k.name_ar,'weight',k.weight,'maxScore',k.max_score,'sourceType',k.source_type,'attendanceMetric',k.attendance_metric,'requiresEvidence',k.requires_evidence) order by k.sort_order) from public.kpi_criteria k where k.template_id=t.id),'[]'::jsonb)) order by t.created_at desc) from public.kpi_templates t),'[]'::jsonb),
  'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'evaluationId',a.evaluation_id,'employeeId',a.employee_id,'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'reason',a.reason,'requestedOutcome',a.requested_outcome,'status',a.status,'submittedAt',a.submitted_at,'resolutionDueAt',a.resolution_due_at,'reviewNote',a.review_note) order by a.submitted_at desc) from public.kpi_appeals a join public.employees e on e.id=a.employee_id where a.status in ('submitted','under_review')),'[]'::jsonb),
  'stageCounts',coalesce((select jsonb_object_agg(x.current_stage,x.count) from (select e.current_stage,count(*) count from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=v_month group by e.current_stage) x),'{}'::jsonb),
  'lastUpdatedAt',now()
 );
end $$;

create or replace function public.refresh_kpi_attendance_inputs(p_cycle_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cycle public.kpi_cycles; v_count integer:=0; v_row record; v_score numeric;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.attendance.refresh'])) then raise exception 'FORBIDDEN'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 for v_row in
  select ev.id evaluation_id,ev.employee_id,k.id criterion_id,k.attendance_metric,k.max_score,
   count(a.*) filter(where a.status not in ('holiday','weekend')) scheduled,
   count(a.*) filter(where a.status in ('present','late')) present,
   count(a.*) filter(where a.status='present') punctual,
   count(a.*) filter(where a.status in ('present','late','on_leave','holiday','weekend')) completed
  from public.kpi_evaluations ev join public.kpi_criteria k on k.template_id=ev.template_id and k.source_type='attendance'
  left join public.attendance_daily a on a.employee_id=ev.employee_id and date_trunc('month',a.work_date)=v_cycle.period_month
  where ev.cycle_id=p_cycle_id group by ev.id,ev.employee_id,k.id,k.attendance_metric,k.max_score
 loop
  v_score:=case v_row.attendance_metric when 'punctuality_rate' then case when v_row.scheduled=0 then v_row.max_score else round(v_row.punctual::numeric/v_row.scheduled*v_row.max_score,2) end when 'completion_rate' then case when v_row.scheduled=0 then v_row.max_score else round(v_row.completed::numeric/v_row.scheduled*v_row.max_score,2) end else case when v_row.scheduled=0 then v_row.max_score else round(v_row.present::numeric/v_row.scheduled*v_row.max_score,2) end end;
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_row.evaluation_id,v_row.criterion_id,greatest(0,least(v_score,v_row.max_score)),'hr','محسوب آليًا من الحضور',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(); v_count:=v_count+1;
 end loop;
 return v_count;
end $$;


create or replace function public.create_kpi_cycle_admin(p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_month date:=date_trunc('month',p_month)::date;
begin
 if not(public.current_is_full_access() or public.has_permission('performance.cycle.manage')) then raise exception 'FORBIDDEN'; end if;
 if not(p_self_due<p_manager_due and p_manager_due<p_secretary_due and p_secretary_due<p_executive_due) then raise exception 'INVALID_DEADLINES'; end if;
 if not exists(select 1 from public.kpi_templates where id=p_template_id and is_active) then raise exception 'INVALID_TEMPLATE'; end if;
 insert into public.kpi_cycles(period_month,status,template_id,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,created_by)
 values(v_month,case when p_open_now then 'open' else 'draft' end,p_template_id,p_self_due,p_manager_due,p_secretary_due,p_executive_due,case when p_open_now then now() end,public.current_employee_id(),auth.uid())
 on conflict(period_month) do update set template_id=excluded.template_id,self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,status=case when kpi_cycles.status='draft' then excluded.status else kpi_cycles.status end,updated_at=now() returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,created_by)
 select e.id,v_id,p_template_id,'self','self',auth.uid() from public.employees e where e.is_active and not e.is_deleted and e.status='active'
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة تقييم',null,jsonb_build_object('month',v_month));
 return v_id;
end $$;

create or replace function public.add_kpi_evidence(p_evaluation_id uuid,p_criterion_id uuid,p_type text,p_title text,p_description text default null,p_storage_path text default null,p_external_url text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_stage text; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 v_stage:=v_eval.current_stage;
 if v_stage not in ('self','manager','secretary','executive') then raise exception 'EVALUATION_LOCKED'; end if;
 if v_stage='self' and v_eval.employee_id<>public.current_employee_id() then raise exception 'FORBIDDEN'; end if;
 if v_stage='manager' and not public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess') then raise exception 'FORBIDDEN'; end if;
 if v_stage='secretary' and not(public.current_is_full_access() or public.has_permission('performance.kpi.secretary_review')) then raise exception 'FORBIDDEN'; end if;
 if v_stage='executive' and not(public.current_is_full_access() or public.has_permission('performance.kpi.executive_review')) then raise exception 'FORBIDDEN'; end if;
 insert into public.kpi_evidence(evaluation_id,criterion_id,evidence_type,title,description,storage_path,external_url,submitted_stage,submitted_by,created_by)
 values(p_evaluation_id,p_criterion_id,p_type,trim(p_title),p_description,p_storage_path,p_external_url,v_stage,public.current_employee_id(),auth.uid()) returning id into v_id; return v_id;
end $$;

create or replace function public.submit_kpi_appeal(p_evaluation_id uuid,p_reason text,p_requested_outcome text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id;
 if v_eval.employee_id<>public.current_employee_id() or v_eval.current_stage<>'finalized' then raise exception 'FORBIDDEN_OR_NOT_FINAL'; end if;
 if length(trim(p_reason))<20 then raise exception 'REASON_TOO_SHORT'; end if;
 insert into public.kpi_appeals(evaluation_id,employee_id,reason,requested_outcome,resolution_due_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,trim(p_reason),p_requested_outcome,now()+interval '7 days',auth.uid()) returning id into v_id; return v_id;
end $$;

create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not(public.current_is_full_access() or public.has_permission('performance.kpi.appeal.review')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') or p_decision not in ('accepted','rejected') or length(trim(p_note))<8 then raise exception 'INVALID_DECISION'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then update public.kpi_evaluations set locked=false,current_stage='executive',stage='executive',updated_at=now() where id=v.evaluation_id; end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض تقييم',p_note,jsonb_build_object('evaluationId',v.evaluation_id));
end $$;

-- Function declaration order compatibility: create cycle references refresh function at execution time.
revoke execute on function public.get_kpi_admin_catalog(date) from public; grant execute on function public.get_kpi_admin_catalog(date) to authenticated;
revoke execute on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean) from public; grant execute on function public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean) to authenticated;
revoke execute on function public.refresh_kpi_attendance_inputs(uuid) from public; grant execute on function public.refresh_kpi_attendance_inputs(uuid) to authenticated;
revoke execute on function public.add_kpi_evidence(uuid,uuid,text,text,text,text,text) from public; grant execute on function public.add_kpi_evidence(uuid,uuid,text,text,text,text,text) to authenticated;
revoke execute on function public.submit_kpi_appeal(uuid,text,text) from public; grant execute on function public.submit_kpi_appeal(uuid,text,text) to authenticated;
revoke execute on function public.decide_kpi_appeal(uuid,text,text) from public; grant execute on function public.decide_kpi_appeal(uuid,text,text) to authenticated;

commit;
