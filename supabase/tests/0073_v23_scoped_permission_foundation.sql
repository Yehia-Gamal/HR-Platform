-- pgTAP: V23 §3 — scoped permission foundation (migration 0172)
-- تتحقق من: current_employee_scope, has_scoped_permission, has_any_scoped_permission, feature flag
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) Feature flag موجود ومعطل
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(select 1 from public.settings
    where scope = 'organization' and category = 'security'
      and key = 'scoped_rls_enabled'),
  'scoped_rls_enabled setting exists'
);

select is(
  (select value::text from public.settings
   where scope = 'organization' and category = 'security'
     and key = 'scoped_rls_enabled'),
  'false',
  'scoped_rls_enabled defaults to false'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الدوال موجودة
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', 'current_employee_scope', '{}',
  'current_employee_scope() function exists');

select function_returns('public', 'current_employee_scope', '{}', 'jsonb',
  'current_employee_scope returns jsonb');

select has_function('public', 'has_scoped_permission', array['text', 'text', 'uuid'],
  'has_scoped_permission(text, text, uuid) exists');

select function_returns('public', 'has_scoped_permission', array['text', 'text', 'uuid'], 'boolean',
  'has_scoped_permission returns boolean');

select has_function('public', 'has_any_scoped_permission', array['text[]', 'text', 'uuid'],
  'has_any_scoped_permission(text[], text, uuid) exists');

select function_returns('public', 'has_any_scoped_permission', array['text[]', 'text', 'uuid'], 'boolean',
  'has_any_scoped_permission returns boolean');

-- ═══════════════════════════════════════════════════════════════════════
-- 3) جميع الدوال تملك search_path مثبت
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'current_employee_scope'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'current_employee_scope has pinned search_path'
);

select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'has_scoped_permission'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'has_scoped_permission has pinned search_path'
);

select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'has_any_scoped_permission'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'has_any_scoped_permission has pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 4) جميع الدوال SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════════════
select is(
  (select p.prosecdef from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public' and p.proname = 'current_employee_scope'
   and p.pronargs = 0),
  true,
  'current_employee_scope is SECURITY DEFINER'
);

select is(
  (select p.prosecdef from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public' and p.proname = 'has_scoped_permission'
   and p.pronargs = 3),
  true,
  'has_scoped_permission is SECURITY DEFINER'
);

select is(
  (select p.prosecdef from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public' and p.proname = 'has_any_scoped_permission'
   and p.pronargs = 3),
  true,
  'has_any_scoped_permission is SECURITY DEFINER'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 5) صلاحية التنفيذ مسحوبة من public وممنوحة لـ authenticated
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  not has_function_privilege('public', 'has_scoped_permission(text,text,uuid)', 'execute'),
  'has_scoped_permission not executable by public role'
);

select ok(
  has_function_privilege('authenticated', 'has_scoped_permission(text,text,uuid)', 'execute'),
  'has_scoped_permission executable by authenticated role'
);

select * from finish();
rollback;
