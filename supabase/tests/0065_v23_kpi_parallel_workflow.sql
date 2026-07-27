-- pgTAP: V23 KPI parallel workflow — structure and CHECK constraints.
-- Test file: 0065_v23_kpi_parallel_workflow.sql
begin;
select plan(20);

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema: new columns exist on kpi_cycles
-- ─────────────────────────────────────────────────────────────────────────────
select has_column('public','kpi_cycles','use_parallel_flow',
  'kpi_cycles has use_parallel_flow column');
select col_type_is('public','kpi_cycles','use_parallel_flow','boolean',
  'use_parallel_flow is boolean');
select col_default_is('public','kpi_cycles','use_parallel_flow','false',
  'use_parallel_flow defaults to false');

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Schema: new columns exist on kpi_evaluations
-- ─────────────────────────────────────────────────────────────────────────────
select has_column('public','kpi_evaluations','hr_completed',
  'kpi_evaluations has hr_completed column');
select has_column('public','kpi_evaluations','manager_completed',
  'kpi_evaluations has manager_completed column');
select has_column('public','kpi_evaluations','version',
  'kpi_evaluations has version column');
select col_type_is('public','kpi_evaluations','version','integer',
  'version is integer');
select col_default_is('public','kpi_evaluations','version','1',
  'version defaults to 1');

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CHECK constraints accept V23 stages
-- ─────────────────────────────────────────────────────────────────────────────

-- parallel_review is valid for current_stage
select lives_ok($test$
  do $inner$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_current_stage_check';
    if v_ck is null then raise exception 'CHECK not found'; end if;
    if position('parallel_review' in v_ck)=0 then raise exception 'parallel_review missing from CHECK'; end if;
  end $inner$;
$test$, 'current_stage CHECK accepts parallel_review');

-- secretary_review is valid
select lives_ok($test$
  do $inner$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_current_stage_check';
    if position('secretary_review' in v_ck)=0 then raise exception 'secretary_review missing'; end if;
  end $inner$;
$test$, 'current_stage CHECK accepts secretary_review');

-- executive_review is valid
select lives_ok($test$
  do $inner$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_current_stage_check';
    if position('executive_review' in v_ck)=0 then raise exception 'executive_review missing'; end if;
  end $inner$;
$test$, 'current_stage CHECK accepts executive_review');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. V23 workflow statuses accepted
-- ─────────────────────────────────────────────────────────────────────────────
select lives_ok($test$
  do $$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_workflow_status_check';
    if position('PARALLEL_REVIEW_IN_PROGRESS' in v_ck)=0 then raise exception 'PARALLEL_REVIEW_IN_PROGRESS missing'; end if;
    if position('HR_COMPLETED' in v_ck)=0 then raise exception 'HR_COMPLETED missing'; end if;
    if position('MANAGER_COMPLETED' in v_ck)=0 then raise exception 'MANAGER_COMPLETED missing'; end if;
    if position('SECRETARY_REVIEW' in v_ck)=0 then raise exception 'SECRETARY_REVIEW missing'; end if;
    if position('EXECUTIVE_REVIEW' in v_ck)=0 then raise exception 'EXECUTIVE_REVIEW missing'; end if;
  end $$;
$test$, 'workflow_status CHECK accepts all V23 statuses');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Barrier CHECK constraint exists
-- ─────────────────────────────────────────────────────────────────────────────
select lives_ok($test$
  do $$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_barrier_check';
    if v_ck is null then raise exception 'barrier CHECK not found'; end if;
  end $$;
$test$, 'barrier CHECK constraint exists on kpi_evaluations');

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. V23 evidence stages accepted
-- ─────────────────────────────────────────────────────────────────────────────
select lives_ok($test$
  do $$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc
      on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evidence'
      and tc.constraint_name='kpi_evidence_submitted_stage_check';
    if position('parallel_review' in v_ck)=0 then raise exception 'parallel_review missing from evidence CHECK'; end if;
  end $$;
$test$, 'evidence submitted_stage CHECK accepts parallel_review');

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. CONDUCT criterion is evaluator_stage=manager
-- ─────────────────────────────────────────────────────────────────────────────
select results_eq($$
  select evaluator_stage from public.kpi_criteria
  where code='CONDUCT'
  limit 1
$$, $$values('manager'::text)$$,
  'CONDUCT criterion evaluator_stage is manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. HR criteria sum to 30, Manager criteria sum to 70
-- ─────────────────────────────────────────────────────────────────────────────
select results_eq($$
  select coalesce(sum(max_score),0)::integer
  from public.kpi_criteria c
  join public.kpi_templates t on t.id=c.template_id
  where t.official_code='OFFICIAL_KPI_100' and c.evaluator_stage='hr'
$$, $$values(30)$$,
  'HR criteria total max_score = 30');

select results_eq($$
  select coalesce(sum(max_score),0)::integer
  from public.kpi_criteria c
  join public.kpi_templates t on t.id=c.template_id
  where t.official_code='OFFICIAL_KPI_100' and c.evaluator_stage='manager'
$$, $$values(70)$$,
  'Manager criteria total max_score = 70');

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. RPCs exist with correct signatures
-- ─────────────────────────────────────────────────────────────────────────────
select has_function('public','advance_kpi_stage',
  array['uuid','text','jsonb','text'],
  'advance_kpi_stage(uuid,text,jsonb,text) exists');

select has_function('public','return_kpi_stage',
  array['uuid','text','text'],
  'return_kpi_stage(uuid,text,text) exists');

select finish();
rollback;
