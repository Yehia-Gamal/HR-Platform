-- 0059: V17 §2.2.1 — اختبار إصلاحات مصفوفة الصلاحيات (migration 0138).
-- يتحقق من:
--   1) وجود دور hr-specialist
--   2) disputes.admin_action.decide ممنوحة لـ executive (وليس executive-secretary)
--   3) performance.cycle.manage غير ممنوحة لـ executive
--   4) hr-specialist لديه صلاحيات HR الأساسية

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

-- =====================================================================
-- 1. دور hr-specialist موجود في جدول roles
-- =====================================================================

select ok(
  exists(
    select 1 from public.roles where slug = 'hr-specialist' and is_system = true
  ),
  'دور hr-specialist موجود وهو دور نظامي'
);

select ok(
  exists(
    select 1 from public.roles
    where slug = 'hr-specialist' and is_full_access = false
  ),
  'hr-specialist ليس full-access'
);

-- =====================================================================
-- 2. disputes.admin_action.decide ممنوحة لـ executive
-- =====================================================================

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'executive'
      and p.code = 'disputes.admin_action.decide'
  ),
  'disputes.admin_action.decide ممنوحة لـ executive'
);

-- =====================================================================
-- 3. disputes.admin_action.decide ليست ممنوحة لـ executive-secretary
-- =====================================================================

select ok(
  not exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'executive-secretary'
      and p.code = 'disputes.admin_action.decide'
  ),
  'disputes.admin_action.decide غير ممنوحة لـ executive-secretary'
);

-- =====================================================================
-- 4. performance.cycle.manage غير ممنوحة لـ executive
-- =====================================================================

select ok(
  not exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'executive'
      and p.code = 'performance.cycle.manage'
  ),
  'performance.cycle.manage غير ممنوحة لـ executive'
);

-- =====================================================================
-- 5. performance.cycle.manage لا تزال ممنوحة لـ executive-secretary
-- =====================================================================

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'executive-secretary'
      and p.code = 'performance.cycle.manage'
  ),
  'performance.cycle.manage لا تزال ممنوحة لـ executive-secretary'
);

-- =====================================================================
-- 6-10. hr-specialist لديه صلاحيات HR الأساسية
-- =====================================================================

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-specialist'
      and p.code = 'people.employee.read'
  ),
  'hr-specialist لديه people.employee.read'
);

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-specialist'
      and p.code = 'attendance.record.read'
  ),
  'hr-specialist لديه attendance.record.read'
);

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-specialist'
      and p.code = 'performance.kpi.read'
  ),
  'hr-specialist لديه performance.kpi.read'
);

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-specialist'
      and p.code = 'requests.request.read'
  ),
  'hr-specialist لديه requests.request.read'
);

select ok(
  exists(
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-specialist'
      and p.code = 'performance.kpi.hr_review'
  ),
  'hr-specialist لديه performance.kpi.hr_review'
);

select * from finish();
rollback;
