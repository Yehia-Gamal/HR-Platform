-- Migration 0036: workforce planning and a feature-gated payroll/compensation foundation.
-- Payroll formulas remain disabled until Finance/Legal configuration is approved.

create table if not exists public.workforce_plans (
 id uuid primary key default gen_random_uuid(), plan_year integer not null check(plan_year between 2020 and 2100), department_id uuid not null references public.departments(id) on delete cascade,
 position_id uuid references public.positions(id) on delete set null, approved_headcount integer not null default 0 check(approved_headcount>=0), planned_hires integer not null default 0 check(planned_hires>=0),
 planned_cost numeric(16,2), status text not null default 'draft' check(status in('draft','review','approved','locked')), notes text,
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id), unique(plan_year,department_id,position_id)
);
create table if not exists public.capacity_snapshots (
 id uuid primary key default gen_random_uuid(), snapshot_date date not null, department_id uuid not null references public.departments(id) on delete cascade,
 available_minutes integer not null default 0, demand_minutes integer not null default 0, leave_minutes integer not null default 0, overtime_minutes integer not null default 0,
 utilization_percent numeric(6,2), generated_at timestamptz not null default now(), unique(snapshot_date,department_id)
);

create table if not exists public.salary_structures (
 id uuid primary key default gen_random_uuid(), code text not null unique, name_ar text not null, currency text not null default 'EGP', active boolean not null default true,
 effective_from date not null, effective_to date, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.salary_components (
 id uuid primary key default gen_random_uuid(), structure_id uuid not null references public.salary_structures(id) on delete cascade, code text not null,
 name_ar text not null, component_type text not null check(component_type in('earning','deduction','employer_contribution')), calculation_type text not null default 'fixed' check(calculation_type in('fixed','percentage','formula')),
 formula_expression text, taxable boolean not null default false, insurable boolean not null default false, active boolean not null default true, sort_order integer not null default 0,
 unique(structure_id,code)
);
create table if not exists public.employee_compensation (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete cascade, structure_id uuid not null references public.salary_structures(id) on delete restrict,
 base_salary numeric(14,2) not null check(base_salary>=0), effective_from date not null, effective_to date, status text not null default 'active' check(status in('draft','active','superseded','cancelled')),
 bank_account_masked text, statutory_profile jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create unique index if not exists ux_employee_compensation_active on public.employee_compensation(employee_id) where status='active' and effective_to is null;

create table if not exists public.payroll_runs (
 id uuid primary key default gen_random_uuid(), period_month date not null unique check(extract(day from period_month)=1), currency text not null default 'EGP',
 status text not null default 'draft' check(status in('draft','calculated','validation_failed','ready_for_review','approved','posted','paid','closed','cancelled')),
 input_snapshot jsonb not null default '{}'::jsonb, totals jsonb not null default '{}'::jsonb, maker_user_id uuid references auth.users(id), approver_user_id uuid references auth.users(id),
 calculated_at timestamptz, approved_at timestamptz, posted_at timestamptz, closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.payslips (
 id uuid primary key default gen_random_uuid(), payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade, employee_id uuid not null references public.employees(id) on delete restrict,
 gross_amount numeric(14,2) not null default 0, deduction_amount numeric(14,2) not null default 0, net_amount numeric(14,2) not null default 0,
 status text not null default 'draft' check(status in('draft','calculated','approved','issued','paid','reversed')), issued_at timestamptz, paid_at timestamptz,
 storage_path text, content_sha256 text, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id), unique(payroll_run_id,employee_id)
);
create table if not exists public.payslip_lines (
 id uuid primary key default gen_random_uuid(), payslip_id uuid not null references public.payslips(id) on delete cascade, component_code text not null, component_name text not null,
 line_type text not null check(line_type in('earning','deduction','employer_contribution')), amount numeric(14,2) not null, source_type text, source_id uuid, metadata jsonb not null default '{}'::jsonb
);
create table if not exists public.employee_loans (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete cascade, loan_type text not null default 'advance', principal_amount numeric(14,2) not null check(principal_amount>0),
 installment_amount numeric(14,2) not null check(installment_amount>0), outstanding_amount numeric(14,2) not null check(outstanding_amount>=0), start_month date not null,
 status text not null default 'pending' check(status in('pending','approved','active','settled','cancelled')), approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.loan_installments (
 id uuid primary key default gen_random_uuid(), loan_id uuid not null references public.employee_loans(id) on delete cascade, due_month date not null, amount numeric(14,2) not null check(amount>0),
 status text not null default 'scheduled' check(status in('scheduled','deducted','deferred','waived','cancelled')), payslip_id uuid references public.payslips(id) on delete set null, deducted_at timestamptz,
 unique(loan_id,due_month)
);

create table if not exists public.engagement_campaigns (
 id uuid primary key default gen_random_uuid(), title text not null, campaign_type text not null check(campaign_type in('survey','recognition','wellbeing','communication')),
 starts_at timestamptz, ends_at timestamptz, target_config jsonb not null default '{}'::jsonb, status text not null default 'draft' check(status in('draft','scheduled','active','closed','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);
create table if not exists public.wellbeing_requests (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete cascade, category text not null,
 description_encrypted text not null, confidentiality_level text not null default 'restricted' check(confidentiality_level in('confidential','restricted')),
 assigned_specialist_user_id uuid references auth.users(id) on delete set null, status text not null default 'submitted' check(status in('submitted','accepted','in_support','closed','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz, created_by uuid references auth.users(id)
);

DO $$ declare t text; begin foreach t in array array['workforce_plans','salary_structures','employee_compensation','payroll_runs','payslips','employee_loans','engagement_campaigns','wellbeing_requests'] loop execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t); execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()',t,t); end loop; end $$;
DO $$ declare t text; begin foreach t in array array['workforce_plans','capacity_snapshots','salary_structures','salary_components','employee_compensation','payroll_runs','payslips','payslip_lines','employee_loans','loan_installments','engagement_campaigns','wellbeing_requests'] loop execute format('alter table public.%I enable row level security',t); end loop; end $$;

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive) values
('workforce.plan.manage','workforce','plan','manage','إدارة خطة القوى العاملة','sensitive',true),
('payroll.structure.manage','payroll','structure','manage','إدارة هياكل الرواتب','critical',true),
('payroll.run.manage','payroll','run','manage','إنشاء وحساب مسير الرواتب','critical',true),
('payroll.run.approve','payroll','run','approve','اعتماد مسير الرواتب','critical',true),
('payroll.payslip.read','payroll','payslip','read','قراءة كشف الراتب','critical',true),
('engagement.campaign.manage','engagement','campaign','manage','إدارة حملات المشاركة','sensitive',false),
('wellbeing.request.manage','wellbeing','request','manage','إدارة طلبات الدعم السرية','critical',true)
on conflict(code) do update set description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

create policy workforce_plans_admin on public.workforce_plans for all to authenticated using(public.current_is_full_access() or public.has_permission('workforce.plan.manage')) with check(public.current_is_full_access() or public.has_permission('workforce.plan.manage'));
create policy capacity_snapshots_read on public.capacity_snapshots for select to authenticated using(public.current_is_full_access() or public.has_permission('workforce.plan.manage'));
create policy capacity_snapshots_write on public.capacity_snapshots for all to authenticated using(public.current_is_full_access() or public.has_permission('workforce.plan.manage')) with check(public.current_is_full_access() or public.has_permission('workforce.plan.manage'));
DO $$ declare t text; begin foreach t in array array['salary_structures','salary_components','employee_compensation','employee_loans','loan_installments'] loop execute format('create policy %I_payroll_admin on public.%I for all to authenticated using (public.current_is_full_access() or public.has_permission(''payroll.structure.manage'')) with check (public.current_is_full_access() or public.has_permission(''payroll.structure.manage''))',t,t); end loop; end $$;
create policy payroll_runs_manage on public.payroll_runs for all to authenticated using(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve'])) with check(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve']));
create policy payslips_read on public.payslips for select to authenticated using(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve']) or (public.has_permission('payroll.payslip.read') and public.can_access_employee(employee_id)) or employee_id=public.current_employee_id());
create policy payslips_manage on public.payslips for all to authenticated using(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve'])) with check(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve']));
create policy payslip_lines_read on public.payslip_lines for select to authenticated using(exists(select 1 from public.payslips p where p.id=payslip_id and (public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve']) or p.employee_id=public.current_employee_id())));
create policy payslip_lines_manage on public.payslip_lines for all to authenticated using(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve'])) with check(public.current_is_full_access() or public.has_any_permission(array['payroll.run.manage','payroll.run.approve']));
create policy engagement_campaigns_read on public.engagement_campaigns for select to authenticated using(status in('scheduled','active','closed') or public.current_is_full_access() or public.has_permission('engagement.campaign.manage'));
create policy engagement_campaigns_manage on public.engagement_campaigns for all to authenticated using(public.current_is_full_access() or public.has_permission('engagement.campaign.manage')) with check(public.current_is_full_access() or public.has_permission('engagement.campaign.manage'));
create policy wellbeing_requests_owner on public.wellbeing_requests for select to authenticated using(employee_id=public.current_employee_id() or assigned_specialist_user_id=auth.uid() or public.current_is_full_access() or public.has_permission('wellbeing.request.manage'));
create policy wellbeing_requests_create on public.wellbeing_requests for insert to authenticated with check(employee_id=public.current_employee_id());
create policy wellbeing_requests_manage on public.wellbeing_requests for update to authenticated using(assigned_specialist_user_id=auth.uid() or public.current_is_full_access() or public.has_permission('wellbeing.request.manage')) with check(assigned_specialist_user_id=auth.uid() or public.current_is_full_access() or public.has_permission('wellbeing.request.manage'));

create or replace function public.get_people_finance_catalog()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.current_is_full_access() or public.has_any_permission(array['workforce.plan.manage','payroll.structure.manage','payroll.run.manage','payroll.run.approve','engagement.campaign.manage'])) then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
 'workforcePlans',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'year',w.plan_year,'departmentId',w.department_id,'departmentName',d.name,'positionId',w.position_id,'approvedHeadcount',w.approved_headcount,'plannedHires',w.planned_hires,'plannedCost',w.planned_cost,'status',w.status) order by w.plan_year desc,d.name) from public.workforce_plans w join public.departments d on d.id=w.department_id),'[]'::jsonb),
 'capacity',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'snapshotDate',c.snapshot_date,'departmentId',c.department_id,'departmentName',d.name,'availableMinutes',c.available_minutes,'demandMinutes',c.demand_minutes,'leaveMinutes',c.leave_minutes,'overtimeMinutes',c.overtime_minutes,'utilizationPercent',c.utilization_percent) order by c.snapshot_date desc) from public.capacity_snapshots c join public.departments d on d.id=c.department_id),'[]'::jsonb),
 'salaryStructures',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'currency',currency,'active',active,'effectiveFrom',effective_from,'effectiveTo',effective_to) order by created_at desc) from public.salary_structures),'[]'::jsonb),
 'payrollRuns',coalesce((select jsonb_agg(jsonb_build_object('id',id,'periodMonth',period_month,'currency',currency,'status',status,'totals',totals,'calculatedAt',calculated_at,'approvedAt',approved_at,'closedAt',closed_at) order by period_month desc) from public.payroll_runs),'[]'::jsonb),
 'loans',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'employeeId',l.employee_id,'employeeName',e.full_name_ar,'loanType',l.loan_type,'principalAmount',l.principal_amount,'outstandingAmount',l.outstanding_amount,'status',l.status) order by l.created_at desc) from public.employee_loans l join public.employees e on e.id=l.employee_id),'[]'::jsonb),
 'campaigns',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'campaignType',campaign_type,'startsAt',starts_at,'endsAt',ends_at,'status',status) order by created_at desc) from public.engagement_campaigns),'[]'::jsonb),
 'lastUpdatedAt',now());
end $$;

create or replace function public.get_my_payslips()
returns jsonb language plpgsql security definer set search_path=public,auth as $$ declare v_emp uuid:=public.current_employee_id(); begin if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if; return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'periodMonth',r.period_month,'currency',r.currency,'grossAmount',p.gross_amount,'deductionAmount',p.deduction_amount,'netAmount',p.net_amount,'status',p.status,'issuedAt',p.issued_at,'paidAt',p.paid_at,'storagePath',p.storage_path,'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'code',l.component_code,'name',l.component_name,'lineType',l.line_type,'amount',l.amount) order by l.id),'[]'::jsonb) from public.payslip_lines l where l.payslip_id=p.id)) order by r.period_month desc) from public.payslips p join public.payroll_runs r on r.id=p.payroll_run_id where p.employee_id=v_emp and p.status in('approved','issued','paid')),'[]'::jsonb); end $$;

grant execute on function public.get_people_finance_catalog() to authenticated;
grant execute on function public.get_my_payslips() to authenticated;
