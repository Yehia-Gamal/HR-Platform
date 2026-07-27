-- pgTAP: V23 §1E — rate limiting expansion (migration 0174)
-- تتحقق من: جدول rate_limit_log، دالة check_rate_limit، الدوال المتخصصة
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(22);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) جدول rate_limit_log
-- ═══════════════════════════════════════════════════════════════════════
select has_table('public', 'rate_limit_log',
  'rate_limit_log table exists');

select has_column('public', 'rate_limit_log', 'id',
  'rate_limit_log has id column');

select has_column('public', 'rate_limit_log', 'user_id',
  'rate_limit_log has user_id column');

select has_column('public', 'rate_limit_log', 'domain',
  'rate_limit_log has domain column');

select has_column('public', 'rate_limit_log', 'created_at',
  'rate_limit_log has created_at column');

-- RLS مفعل
select ok(
  (select relrowsecurity from pg_class
   where relname = 'rate_limit_log' and relnamespace = 'public'::regnamespace),
  'rate_limit_log has RLS enabled'
);

-- فهرس البحث
select has_index('public', 'rate_limit_log', 'idx_rate_limit_log_lookup',
  'rate_limit_log lookup index exists');

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الدالة العامة check_rate_limit
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', 'check_rate_limit', array['text', 'integer', 'integer'],
  'check_rate_limit(text, integer, integer) exists');

select ok(
  (select p.prosecdef from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public' and p.proname = 'check_rate_limit'
   and p.pronargs = 3),
  'check_rate_limit is SECURITY DEFINER'
);

select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'check_rate_limit'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'check_rate_limit has pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) 6 دوال متخصصة موجودة
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', 'check_employee_create_rate_limit', '{}',
  'check_employee_create_rate_limit() exists');

select has_function('public', 'check_role_assign_rate_limit', '{}',
  'check_role_assign_rate_limit() exists');

select has_function('public', 'check_device_register_rate_limit', '{}',
  'check_device_register_rate_limit() exists');

select has_function('public', 'check_attendance_punch_rate_limit', '{}',
  'check_attendance_punch_rate_limit() exists');

select has_function('public', 'check_location_request_rate_limit', '{}',
  'check_location_request_rate_limit() exists');

select has_function('public', 'check_post_publish_rate_limit', '{}',
  'check_post_publish_rate_limit() exists');

-- ═══════════════════════════════════════════════════════════════════════
-- 4) كل الدوال المتخصصة SECURITY DEFINER مع search_path
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  (select every(p.prosecdef) from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public'
   and p.proname in (
     'check_employee_create_rate_limit',
     'check_role_assign_rate_limit',
     'check_device_register_rate_limit',
     'check_attendance_punch_rate_limit',
     'check_location_request_rate_limit',
     'check_post_publish_rate_limit'
   )),
  'all 6 specialized rate-limit functions are SECURITY DEFINER'
);

select ok(
  (select every(exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%'))
   from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public'
   and p.proname in (
     'check_employee_create_rate_limit',
     'check_role_assign_rate_limit',
     'check_device_register_rate_limit',
     'check_attendance_punch_rate_limit',
     'check_location_request_rate_limit',
     'check_post_publish_rate_limit'
   )),
  'all 6 specialized rate-limit functions have pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 5) صلاحيات: الدالة العامة لا تُنفذ من public
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  not has_function_privilege('public', 'check_rate_limit(text,integer,integer)', 'execute'),
  'check_rate_limit not executable by public role'
);

select ok(
  has_function_privilege('authenticated', 'check_rate_limit(text,integer,integer)', 'execute'),
  'check_rate_limit executable by authenticated role'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 6) RLS policies تمنع الوصول المباشر
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_policies
    where tablename = 'rate_limit_log' and schemaname = 'public'
      and policyname = 'rate_limit_log_deny_select'
  ),
  'deny select policy exists on rate_limit_log'
);

select ok(
  exists(
    select 1 from pg_policies
    where tablename = 'rate_limit_log' and schemaname = 'public'
      and policyname = 'rate_limit_log_deny_insert'
  ),
  'deny insert policy exists on rate_limit_log'
);

select * from finish();
rollback;
