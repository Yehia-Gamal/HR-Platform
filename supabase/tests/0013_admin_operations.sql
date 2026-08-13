begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(24);

select has_function('public','get_organization_admin_catalog',array[]::text[],'organization admin catalog exists');
select has_function('public','upsert_department_admin',array['uuid','uuid','uuid','uuid','uuid','text','text','text','boolean'],'department admin RPC exists');
select has_function('public','upsert_position_admin',array['uuid','uuid','uuid','uuid','uuid','uuid','text','text','text','integer','boolean'],'position admin RPC exists');
select has_function('public','get_access_admin_catalog',array[]::text[],'access admin catalog exists');
select has_function('public','get_onboarding_admin_catalog',array['integer'],'onboarding admin catalog exists');
select has_function('public','create_onboarding_journey_admin',array['uuid','timestamp with time zone','date','jsonb'],'onboarding journey RPC exists');
select has_function('public','transition_onboarding_task_admin',array['uuid','text'],'onboarding task transition RPC exists');
select has_function('public','create_job_requisition_admin',array['uuid','text','integer','text','text','boolean'],'job requisition RPC exists');

select has_trigger('public','departments','trg_departments_audit','department changes are audited');
select has_trigger('public','positions','trg_positions_audit','position changes are audited');
select has_trigger('public','onboarding_journeys','trg_onboarding_journeys_audit','onboarding journeys are audited');
select has_trigger('public','onboarding_tasks','trg_onboarding_tasks_audit','onboarding tasks are audited');
select has_trigger('public','job_requisitions','trg_job_requisitions_audit','job requisitions are audited');

-- منذ 0349: الكتابة المباشرة عبر سياسة <table>_admin واحدة موقوفة على
-- full-access + أدوار HR فقط (لا كتابة عامة/غير مقيدة). الكتابة الاعتيادية تبقى RPCs.
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='departments' and cmd in ('INSERT','UPDATE','DELETE','ALL')),
  1, 'departments have exactly one gated admin write policy'
);
select ok(
  exists (select 1 from pg_policies
    where schemaname='public' and tablename='departments' and policyname='departments_admin'
      and cmd='ALL'
      and qual like '%current_is_full_access()%'
      and qual like '%hr-manager%'),
  'departments admin write policy is gated to full access + HR'
);
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='positions' and cmd in ('INSERT','UPDATE','DELETE','ALL')),
  1, 'positions have exactly one gated admin write policy'
);
select ok(
  exists (select 1 from pg_policies
    where schemaname='public' and tablename='positions' and policyname='positions_admin'
      and cmd='ALL'
      and qual like '%current_is_full_access()%'
      and qual like '%hr-manager%'),
  'positions admin write policy is gated to full access + HR'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='job_requisitions' and cmd in ('INSERT','UPDATE','DELETE','ALL') $$,
  'job requisitions have no direct write policies'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='onboarding_journeys' and cmd in ('INSERT','UPDATE','DELETE','ALL') $$,
  'onboarding journeys have no direct write policies'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='onboarding_tasks' and cmd in ('INSERT','UPDATE','DELETE','ALL') $$,
  'onboarding tasks have no direct write policies'
);

select function_privs_are('public','get_organization_admin_catalog',array[]::text[],'authenticated',array['EXECUTE'],'authenticated can call protected organization catalog');
select function_privs_are('public','get_access_admin_catalog',array[]::text[],'authenticated',array['EXECUTE'],'authenticated can call protected access catalog');
select function_privs_are('public','get_onboarding_admin_catalog',array['integer'],'authenticated',array['EXECUTE'],'authenticated can call protected onboarding catalog');
select function_privs_are('public','create_job_requisition_admin',array['uuid','text','integer','text','text','boolean'],'authenticated',array['EXECUTE'],'authenticated can call permission-gated requisition RPC');

select * from finish();
rollback;
