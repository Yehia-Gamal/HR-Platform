-- pgTAP: V23 §6 — multi-assignment P0 (migration 0173)
-- تتحقق من: أعمدة employee_departments الجديدة، الدالة المحدثة، القيود
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) الأعمدة الجديدة موجودة
-- ═══════════════════════════════════════════════════════════════════════
select has_column('public', 'employee_departments', 'allocation_percentage',
  'employee_departments has allocation_percentage column');

select col_type_is('public', 'employee_departments', 'allocation_percentage', 'integer',
  'allocation_percentage is integer');

select col_default_is('public', 'employee_departments', 'allocation_percentage', '100',
  'allocation_percentage defaults to 100');

select has_column('public', 'employee_departments', 'start_date',
  'employee_departments has start_date column');

select col_type_is('public', 'employee_departments', 'start_date', 'date',
  'start_date is date');

select has_column('public', 'employee_departments', 'end_date',
  'employee_departments has end_date column');

select col_type_is('public', 'employee_departments', 'end_date', 'date',
  'end_date is date');

select col_is_null('public', 'employee_departments', 'end_date',
  'end_date is nullable (NULL = ongoing)');

select has_column('public', 'employee_departments', 'functional_manager_id',
  'employee_departments has functional_manager_id column');

select col_is_null('public', 'employee_departments', 'functional_manager_id',
  'functional_manager_id is nullable');

-- ═══════════════════════════════════════════════════════════════════════
-- 2) القيد allocation_percentage بين 1 و 100
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class t on c.conrelid = t.oid
    join pg_namespace n on t.relnamespace = n.oid
    where n.nspname = 'public' and t.relname = 'employee_departments'
      and c.contype = 'c' and c.conname = 'chk_allocation_range'
  ),
  'CHECK constraint chk_allocation_range exists'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) FK على functional_manager_id → employees
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class t on c.conrelid = t.oid
    join pg_namespace n on t.relnamespace = n.oid
    where n.nspname = 'public' and t.relname = 'employee_departments'
      and c.contype = 'f'
      and pg_get_constraintdef(c.oid) like '%functional_manager_id%'
  ),
  'FK constraint on functional_manager_id references employees'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 4) الفهارس الجديدة
-- ═══════════════════════════════════════════════════════════════════════
select has_index('public', 'employee_departments', 'idx_employee_departments_functional_mgr',
  'index on functional_manager_id exists');

select has_index('public', 'employee_departments', 'idx_employee_departments_active',
  'index on active assignments exists');

-- ═══════════════════════════════════════════════════════════════════════
-- 5) الدالة المحدثة assign_employee_department بـ 9 معاملات
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'assign_employee_department'
    and p.pronargs = 9
  ),
  'assign_employee_department with 9 params exists'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 6) get_employee_departments يُعيد الحقول الجديدة
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', 'get_employee_departments', array['uuid'],
  'get_employee_departments(uuid) exists');

select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'get_employee_departments'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  'get_employee_departments has pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 7) الأعمدة الأصلية لم تتأثر
-- ═══════════════════════════════════════════════════════════════════════
select has_column('public', 'employee_departments', 'is_primary',
  'is_primary column still exists');

select * from finish();
rollback;
