-- Migration 0035: strategy, projects, risks, service desk, meetings, quality, audit, automation and governance.

create table if not exists public.strategic_objectives (
 id uuid primary key default gen_random_uuid(), parent_id uuid references public.strategic_objectives(id) on delete restrict,
 code text not null unique, title text not null, description text, level text not null default 'organization' check(level in('organization','department','team','individual')),
 owner_employee_id uuid references public.employees(id) on delete set null, department_id uuid references public.departments(id) on delete set null,
 period_start date, period_end date, weight numeric(6,2) not null default 1 check(weight>=0), status text not null default 'draft' check(status in('draft','active','at_risk','completed','cancelled')),
 progress numeric(5,2) not null default 0 check(progress between 0 and 100), created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.objective_key_results (
 id uuid primary key default gen_random_uuid(), objective_id uuid not null references public.strategic_objectives(id) on delete cascade,
 title text not null, metric_name text, target_value numeric, current_value numeric not null default 0, unit text, status text not null default 'on_track' check(status in('on_track','at_risk','off_track','completed')),
 due_date date, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.enterprise_projects (
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, description text,
 objective_id uuid references public.strategic_objectives(id) on delete set null, department_id uuid references public.departments(id) on delete set null,
 sponsor_employee_id uuid references public.employees(id) on delete set null, manager_employee_id uuid references public.employees(id) on delete set null,
 start_date date, target_end_date date, status text not null default 'planned' check(status in('planned','active','on_hold','completed','cancelled')),
 priority text not null default 'medium' check(priority in('low','medium','high','critical')), progress numeric(5,2) not null default 0 check(progress between 0 and 100),
 budget_amount numeric(14,2), created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.project_tasks (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.enterprise_projects(id) on delete cascade,
 parent_id uuid references public.project_tasks(id) on delete restrict, title text not null, description text, assignee_employee_id uuid references public.employees(id) on delete set null,
 status text not null default 'todo' check(status in('todo','in_progress','blocked','done','cancelled')), priority text not null default 'medium' check(priority in('low','medium','high','critical')),
 start_date date, due_date date, progress numeric(5,2) not null default 0 check(progress between 0 and 100), created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.enterprise_risks (
 id uuid primary key default gen_random_uuid(), risk_number bigint generated always as identity, title text not null, description text,
 category text not null default 'operational', probability smallint not null default 1 check(probability between 1 and 5), impact smallint not null default 1 check(impact between 1 and 5),
 owner_employee_id uuid references public.employees(id) on delete set null, project_id uuid references public.enterprise_projects(id) on delete set null,
 response_strategy text, mitigation_plan text, status text not null default 'open' check(status in('open','mitigating','accepted','closed')),
 review_date date, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.enterprise_incidents (
 id uuid primary key default gen_random_uuid(), incident_number bigint generated always as identity, title text not null, description text,
 incident_type text not null, severity text not null default 'medium' check(severity in('low','medium','high','critical')), status text not null default 'reported' check(status in('reported','triaged','investigating','resolved','closed')),
 reported_by_employee_id uuid references public.employees(id) on delete set null, assigned_to_employee_id uuid references public.employees(id) on delete set null,
 occurred_at timestamptz, location text, root_cause text, resolution text, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);

create table if not exists public.service_catalog_items (
 id uuid primary key default gen_random_uuid(), code text not null unique, name_ar text not null, description text, category text not null,
 owner_role text, sla_hours integer not null default 24 check(sla_hours>0), workflow_definition_id uuid references public.workflow_definitions(id) on delete set null,
 active boolean not null default true, eligibility_config jsonb not null default '{}'::jsonb, form_schema jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.service_requests (
 id uuid primary key default gen_random_uuid(), request_number bigint generated always as identity, catalog_item_id uuid not null references public.service_catalog_items(id) on delete restrict,
 requester_employee_id uuid not null references public.employees(id) on delete cascade, assigned_to_employee_id uuid references public.employees(id) on delete set null,
 title text not null, description text, payload jsonb not null default '{}'::jsonb, priority text not null default 'normal' check(priority in('low','normal','high','urgent')),
 status text not null default 'submitted' check(status in('draft','submitted','assigned','in_progress','waiting_requester','resolved','closed','cancelled')),
 due_at timestamptz, resolved_at timestamptz, satisfaction_score smallint check(satisfaction_score between 1 and 5), created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.service_request_messages (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.service_requests(id) on delete cascade,
 author_user_id uuid not null references auth.users(id) on delete cascade, body text not null, internal_note boolean not null default false,
 created_at timestamptz not null default now()
);

create table if not exists public.enterprise_meetings (
 id uuid primary key default gen_random_uuid(), title text not null, meeting_type text not null default 'general', starts_at timestamptz, ends_at timestamptz,
 location_or_link text, organizer_employee_id uuid references public.employees(id) on delete set null, status text not null default 'scheduled' check(status in('draft','scheduled','in_progress','completed','cancelled')),
 minutes_status text not null default 'draft' check(minutes_status in('draft','review','approved')), created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.meeting_attendees (
 id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.enterprise_meetings(id) on delete cascade, employee_id uuid not null references public.employees(id) on delete cascade,
 role text not null default 'attendee', response text not null default 'needs_action' check(response in('needs_action','accepted','declined','tentative')), attended boolean,
 unique(meeting_id,employee_id)
);
create table if not exists public.meeting_agenda_items (
 id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.enterprise_meetings(id) on delete cascade,
 order_index integer not null default 0, title text not null, description text, presenter_employee_id uuid references public.employees(id) on delete set null,
 status text not null default 'pending' check(status in('pending','discussed','deferred','closed'))
);
create table if not exists public.meeting_decisions (
 id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.enterprise_meetings(id) on delete cascade,
 agenda_item_id uuid references public.meeting_agenda_items(id) on delete set null, decision_text text not null,
 owner_employee_id uuid references public.employees(id) on delete set null, due_date date, status text not null default 'open' check(status in('open','in_progress','completed','cancelled')),
 created_at timestamptz not null default now(), created_by uuid references auth.users(id)
);

create table if not exists public.quality_cases (
 id uuid primary key default gen_random_uuid(), case_number bigint generated always as identity, source_type text not null, title text not null, description text,
 severity text not null default 'medium' check(severity in('low','medium','high','critical')), owner_employee_id uuid references public.employees(id) on delete set null,
 root_cause text, status text not null default 'open' check(status in('open','investigating','action_planned','verification','closed')),
 due_at timestamptz, closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.corrective_actions (
 id uuid primary key default gen_random_uuid(), quality_case_id uuid not null references public.quality_cases(id) on delete cascade,
 action_type text not null check(action_type in('corrective','preventive')), title text not null, owner_employee_id uuid references public.employees(id) on delete set null,
 due_date date, status text not null default 'planned' check(status in('planned','in_progress','implemented','verified','cancelled')), evidence_path text, effectiveness_note text,
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.internal_audits (
 id uuid primary key default gen_random_uuid(), audit_code text not null unique, title text not null, scope text, lead_auditor_employee_id uuid references public.employees(id) on delete set null,
 planned_start date, planned_end date, status text not null default 'planned' check(status in('planned','in_progress','reporting','closed','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.audit_findings (
 id uuid primary key default gen_random_uuid(), audit_id uuid not null references public.internal_audits(id) on delete cascade,
 finding_number integer not null, title text not null, description text, severity text not null default 'minor' check(severity in('observation','minor','major','critical')),
 owner_employee_id uuid references public.employees(id) on delete set null, due_date date, status text not null default 'open' check(status in('open','action_planned','implemented','verified','closed')),
 unique(audit_id,finding_number)
);

create table if not exists public.automation_rules (
 id uuid primary key default gen_random_uuid(), code text not null unique, name_ar text not null, event_type text not null,
 condition_config jsonb not null default '{}'::jsonb, action_config jsonb not null default '[]'::jsonb, version integer not null default 1,
 active boolean not null default false, requires_approval boolean not null default true, max_runs_per_hour integer not null default 100,
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.automation_runs (
 id uuid primary key default gen_random_uuid(), rule_id uuid not null references public.automation_rules(id) on delete cascade,
 event_id text, idempotency_key text not null unique, status text not null default 'queued' check(status in('queued','running','succeeded','failed','cancelled')),
 input_payload jsonb not null default '{}'::jsonb, output_payload jsonb not null default '{}'::jsonb, attempts integer not null default 0,
 started_at timestamptz, completed_at timestamptz, error_detail text, created_at timestamptz not null default now()
);

create table if not exists public.data_assets (
 id uuid primary key default gen_random_uuid(), code text not null unique, name_ar text not null, source_system text not null,
 owner_employee_id uuid references public.employees(id) on delete set null, steward_employee_id uuid references public.employees(id) on delete set null,
 classification text not null default 'internal' check(classification in('public','internal','confidential','highly_confidential','restricted_hr','restricted_payroll','restricted_medical','restricted_executive')),
 retention_days integer, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.data_quality_rules (
 id uuid primary key default gen_random_uuid(), data_asset_id uuid not null references public.data_assets(id) on delete cascade,
 code text not null, name_ar text not null, rule_expression text not null, severity text not null default 'warning' check(severity in('info','warning','error','critical')),
 active boolean not null default true, last_run_at timestamptz, last_failure_count integer, unique(data_asset_id,code)
);
create table if not exists public.ai_use_cases (
 id uuid primary key default gen_random_uuid(), code text not null unique, name_ar text not null, purpose text not null, owner_employee_id uuid references public.employees(id) on delete set null,
 model_provider text, model_name text, model_version text, risk_level text not null default 'medium' check(risk_level in('low','medium','high','prohibited')),
 human_review_required boolean not null default true, allowed_data_classes text[] not null default '{}', prohibited_actions text[] not null default '{}', active boolean not null default false,
 last_evaluated_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);

-- updated_at and RLS
DO $$ declare t text; begin foreach t in array array['strategic_objectives','objective_key_results','enterprise_projects','project_tasks','enterprise_risks','enterprise_incidents','service_catalog_items','service_requests','enterprise_meetings','quality_cases','corrective_actions','internal_audits','automation_rules','data_assets','data_quality_rules','ai_use_cases'] loop execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t); execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()',t,t); execute format('alter table public.%I enable row level security',t); end loop; end $$;
DO $$ declare t text; begin foreach t in array array['meeting_attendees','meeting_agenda_items','meeting_decisions','audit_findings','automation_runs','service_request_messages'] loop execute format('alter table public.%I enable row level security',t); end loop; end $$;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive) values
('strategy.objective.manage','strategy','objective','manage','إدارة الأهداف الاستراتيجية','sensitive',false),
('projects.project.manage','projects','project','manage','إدارة المشروعات والمهام','sensitive',false),
('risk.risk.manage','risk','risk','manage','إدارة سجل المخاطر','critical',true),
('service.catalog.manage','service','catalog','manage','إدارة كتالوج الخدمات','sensitive',false),
('service.request.manage','service','request','manage','إدارة طلبات الخدمات','sensitive',false),
('meetings.meeting.manage','meetings','meeting','manage','إدارة الاجتماعات والمحاضر','sensitive',false),
('quality.capa.manage','quality','capa','manage','إدارة الجودة والإجراءات التصحيحية','critical',true),
('audit.internal.manage','audit','internal','manage','إدارة التدقيق الداخلي','critical',true),
('automation.rule.manage','automation','rule','manage','إدارة قواعد الأتمتة','critical',true),
('governance.data.manage','governance','data','manage','إدارة حوكمة البيانات','critical',true),
('governance.ai.manage','governance','ai','manage','إدارة حوكمة الذكاء الاصطناعي','critical',true)
on conflict(code) do update set description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

-- Broad admin policies. Self service is handled separately for service requests and meeting attendance.
DO $$ declare t text; begin
 foreach t in array array['strategic_objectives','objective_key_results','enterprise_projects','project_tasks'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_any_permission(array[''strategy.objective.manage'',''projects.project.manage''])) with check (public.current_is_full_access() or public.has_any_permission(array[''strategy.objective.manage'',''projects.project.manage'']))',t,t);
 end loop;
 foreach t in array array['enterprise_risks','enterprise_incidents'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''risk.risk.manage'')) with check (public.current_is_full_access() or public.has_permission(''risk.risk.manage''))',t,t);
 end loop;
 foreach t in array array['service_catalog_items'] loop
  execute format('create policy %I_read on public.%I for select to authenticated using (active or public.current_is_full_access() or public.has_permission(''service.catalog.manage''))',t,t);
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''service.catalog.manage'')) with check (public.current_is_full_access() or public.has_permission(''service.catalog.manage''))',t,t);
 end loop;
 foreach t in array array['enterprise_meetings','meeting_attendees','meeting_agenda_items','meeting_decisions'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''meetings.meeting.manage'')) with check (public.current_is_full_access() or public.has_permission(''meetings.meeting.manage''))',t,t);
 end loop;
 foreach t in array array['quality_cases','corrective_actions'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''quality.capa.manage'')) with check (public.current_is_full_access() or public.has_permission(''quality.capa.manage''))',t,t);
 end loop;
 foreach t in array array['internal_audits','audit_findings'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''audit.internal.manage'')) with check (public.current_is_full_access() or public.has_permission(''audit.internal.manage''))',t,t);
 end loop;
 foreach t in array array['automation_rules','automation_runs'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''automation.rule.manage'')) with check (public.current_is_full_access() or public.has_permission(''automation.rule.manage''))',t,t);
 end loop;
 foreach t in array array['data_assets','data_quality_rules'] loop
  execute format('create policy %I_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''governance.data.manage'')) with check (public.current_is_full_access() or public.has_permission(''governance.data.manage''))',t,t);
 end loop;
 execute 'create policy ai_use_cases_admin on public.ai_use_cases for all to authenticated using (public.current_is_full_access() or public.has_permission(''governance.ai.manage'')) with check (public.current_is_full_access() or public.has_permission(''governance.ai.manage''))';
end $$;

create policy service_requests_read on public.service_requests for select to authenticated using(public.current_is_full_access() or public.has_permission('service.request.manage') or requester_employee_id=public.current_employee_id() or assigned_to_employee_id=public.current_employee_id());
create policy service_requests_create on public.service_requests for insert to authenticated with check(requester_employee_id=public.current_employee_id());
create policy service_requests_manage on public.service_requests for update to authenticated using(public.current_is_full_access() or public.has_permission('service.request.manage') or requester_employee_id=public.current_employee_id()) with check(public.current_is_full_access() or public.has_permission('service.request.manage') or requester_employee_id=public.current_employee_id());
create policy service_messages_read on public.service_request_messages for select to authenticated using(exists(select 1 from public.service_requests r where r.id=request_id and (r.requester_employee_id=public.current_employee_id() or r.assigned_to_employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('service.request.manage'))) and (not internal_note or public.current_is_full_access() or public.has_permission('service.request.manage')));
create policy service_messages_create on public.service_request_messages for insert to authenticated with check(author_user_id=auth.uid() and exists(select 1 from public.service_requests r where r.id=request_id and (r.requester_employee_id=public.current_employee_id() or r.assigned_to_employee_id=public.current_employee_id() or public.current_is_full_access() or public.has_permission('service.request.manage'))));

create or replace function public.get_enterprise_management_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.current_is_full_access() or public.has_any_permission(array['strategy.objective.manage','projects.project.manage','risk.risk.manage','service.request.manage','meetings.meeting.manage','quality.capa.manage','audit.internal.manage','automation.rule.manage','governance.data.manage','governance.ai.manage'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
 'objectives',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'title',title,'level',level,'status',status,'progress',progress,'periodEnd',period_end) order by created_at desc) from public.strategic_objectives),'[]'::jsonb),
 'projects',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'status',status,'priority',priority,'progress',progress,'targetEndDate',target_end_date,'openTasks',(select count(*) from public.project_tasks t where t.project_id=p.id and t.status not in('done','cancelled'))) order by created_at desc) from public.enterprise_projects p),'[]'::jsonb),
 'risks',coalesce((select jsonb_agg(jsonb_build_object('id',id,'number',risk_number,'title',title,'category',category,'probability',probability,'impact',impact,'score',probability*impact,'status',status,'reviewDate',review_date) order by probability*impact desc) from public.enterprise_risks),'[]'::jsonb),
 'incidents',coalesce((select jsonb_agg(jsonb_build_object('id',id,'number',incident_number,'title',title,'severity',severity,'status',status,'occurredAt',occurred_at) order by created_at desc) from public.enterprise_incidents),'[]'::jsonb),
 'serviceRequests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.request_number,'serviceName',c.name_ar,'requesterName',e.full_name_ar,'title',r.title,'priority',r.priority,'status',r.status,'dueAt',r.due_at) order by r.created_at desc) from public.service_requests r join public.service_catalog_items c on c.id=r.catalog_item_id join public.employees e on e.id=r.requester_employee_id),'[]'::jsonb),
 'meetings',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meetingType',meeting_type,'startsAt',starts_at,'status',status,'minutesStatus',minutes_status,'decisions',(select count(*) from public.meeting_decisions d where d.meeting_id=m.id)) order by starts_at desc nulls last) from public.enterprise_meetings m),'[]'::jsonb),
 'qualityCases',coalesce((select jsonb_agg(jsonb_build_object('id',id,'number',case_number,'title',title,'severity',severity,'status',status,'dueAt',due_at) order by created_at desc) from public.quality_cases),'[]'::jsonb),
 'audits',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',audit_code,'title',title,'status',status,'plannedStart',planned_start,'findings',(select count(*) from public.audit_findings f where f.audit_id=a.id)) order by planned_start desc nulls last) from public.internal_audits a),'[]'::jsonb),
 'automations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'eventType',event_type,'version',version,'active',active,'requiresApproval',requires_approval) order by created_at desc) from public.automation_rules),'[]'::jsonb),
 'dataAssets',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'sourceSystem',source_system,'classification',classification,'active',active) order by name_ar) from public.data_assets),'[]'::jsonb),
 'aiUseCases',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'purpose',purpose,'provider',model_provider,'modelName',model_name,'riskLevel',risk_level,'humanReviewRequired',human_review_required,'active',active) order by name_ar) from public.ai_use_cases),'[]'::jsonb),
 'lastUpdatedAt',now());
end $$;

create or replace function public.get_my_service_portal()
returns jsonb language plpgsql security definer set search_path=public,auth as $$ declare v_emp uuid:=public.current_employee_id(); begin if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if; return jsonb_build_object('catalog',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'description',description,'category',category,'slaHours',sla_hours) order by category,name_ar) from public.service_catalog_items where active),'[]'::jsonb),'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.request_number,'serviceName',c.name_ar,'title',r.title,'description',r.description,'priority',r.priority,'status',r.status,'dueAt',r.due_at,'createdAt',r.created_at,'satisfactionScore',r.satisfaction_score) order by r.created_at desc) from public.service_requests r join public.service_catalog_items c on c.id=r.catalog_item_id where r.requester_employee_id=v_emp),'[]'::jsonb),'lastUpdatedAt',now()); end $$;

create or replace function public.submit_my_service_request(p_catalog_item_id uuid,p_title text,p_description text,p_priority text default 'normal',p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$ declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_sla integer; begin if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if; select sla_hours into v_sla from public.service_catalog_items where id=p_catalog_item_id and active; if not found then raise exception 'SERVICE_NOT_AVAILABLE'; end if; insert into public.service_requests(catalog_item_id,requester_employee_id,title,description,payload,priority,due_at,created_by) values(p_catalog_item_id,v_emp,trim(p_title),nullif(trim(p_description),''),coalesce(p_payload,'{}'::jsonb),p_priority,now()+make_interval(hours=>v_sla),auth.uid()) returning id into v_id; return v_id; end $$;

grant execute on function public.get_enterprise_management_catalog() to authenticated;
grant execute on function public.get_my_service_portal() to authenticated;
grant execute on function public.submit_my_service_request(uuid,text,text,text,jsonb) to authenticated;
