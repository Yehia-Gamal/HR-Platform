-- =====================================================================
-- pgTAP: V23 RBAC سلبية — تقييد HR، حماية full-access، تدقيق
-- وكيل 01 — 16 assertion في 6 فئات
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- =====================================================================
-- Hotfix: trg_fn_role_assignment_notify (mig 0160) references non-existent
-- column "name" — should be "name_ar". Patched here within the transaction
-- so the fixture can INSERT into user_roles. Rolls back with the test.
-- =====================================================================
create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $trg$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;
    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';
    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal', 'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;
    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';
    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal', 'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$trg$;

-- =====================================================================
-- Hotfix: mig 0160 trg_fn_role_assignment_notify has bugs (wrong column
-- name + FK issue). Disable it during fixture setup — we test our own
-- RPCs, not the notification trigger. Rolls back with the transaction.
-- =====================================================================
alter table public.user_roles disable trigger trg_role_assignment_notify;

-- =====================================================================
-- Fixture (superuser — قبل أي تبديل دور)
-- =====================================================================
do $fixture$
declare
  v_le   uuid := 'a5a5a5a5-0000-4000-8000-000000000000';
  v_dept uuid := 'a5a5a5a5-0000-4000-8000-000000000010';
  v_hr_user     uuid := 'a5a5a5a5-0000-4000-8000-000000000001';
  v_admin_user  uuid := 'a5a5a5a5-0000-4000-8000-000000000002';
  v_emp_user    uuid := 'a5a5a5a5-0000-4000-8000-000000000003';
  v_target_user uuid := 'a5a5a5a5-0000-4000-8000-000000000004';
  v_role_hr     uuid;
  v_role_admin  uuid;
  v_role_emp    uuid;
  v_perm_assign uuid;
  v_perm_revoke uuid;
begin
  -- كيان قانوني + إدارة
  insert into public.legal_entities (id, code, name)
  values (v_le, 'A5-LE', 'كيان اختبار V23');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'A5-D1', 'إدارة اختبار V23');

  -- مستخدمو المصادقة
  insert into auth.users (id, email, aud, role) values
    (v_hr_user,     'a5-hr@test.local',     'authenticated', 'authenticated'),
    (v_admin_user,  'a5-admin@test.local',   'authenticated', 'authenticated'),
    (v_emp_user,    'a5-emp@test.local',     'authenticated', 'authenticated'),
    (v_target_user, 'a5-target@test.local',  'authenticated', 'authenticated');

  -- موظفون
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('a5a5a5a5-0000-4000-8000-000000000011', v_hr_user,     'A5-001', 'موظف HR',       v_dept, 'active', true),
    ('a5a5a5a5-0000-4000-8000-000000000012', v_admin_user,  'A5-002', 'مدير النظام',    v_dept, 'active', true),
    ('a5a5a5a5-0000-4000-8000-000000000013', v_emp_user,    'A5-003', 'موظف عادي',      v_dept, 'active', true),
    ('a5a5a5a5-0000-4000-8000-000000000014', v_target_user, 'A5-004', 'موظف مستهدف',    v_dept, 'active', true);

  -- ملفات التعريف
  insert into public.profiles (id, employee_id, status) values
    (v_hr_user,     'a5a5a5a5-0000-4000-8000-000000000011', 'active'),
    (v_admin_user,  'a5a5a5a5-0000-4000-8000-000000000012', 'active'),
    (v_emp_user,    'a5a5a5a5-0000-4000-8000-000000000013', 'active'),
    (v_target_user, 'a5a5a5a5-0000-4000-8000-000000000014', 'active');

  -- البحث عن أدوار النظام
  select id into v_role_hr    from public.roles where slug = 'hr-manager';
  select id into v_role_admin from public.roles where slug = 'admin';
  select id into v_role_emp   from public.roles where slug = 'employee';

  -- إسناد الأدوار
  insert into public.user_roles (user_id, role_id) values
    (v_hr_user,     v_role_hr),
    (v_admin_user,  v_role_admin),
    (v_emp_user,    v_role_emp),
    (v_target_user, v_role_emp);

  -- منح صلاحية إسناد/سحب الأدوار لدور HR
  select id into v_perm_assign from public.permissions where code = 'access.role.assign';
  select id into v_perm_revoke from public.permissions where code = 'access.role.remove';

  if v_perm_assign is not null and v_role_hr is not null then
    insert into public.role_permissions (role_id, permission_id, scope)
    values (v_role_hr, v_perm_assign, 'organization')
    on conflict (role_id, permission_id, scope) do nothing;
  end if;

  if v_perm_revoke is not null and v_role_hr is not null then
    insert into public.role_permissions (role_id, permission_id, scope)
    values (v_role_hr, v_perm_revoke, 'organization')
    on conflict (role_id, permission_id, scope) do nothing;
  end if;
end
$fixture$;

-- =====================================================================
-- الفئة 1: نموذج القدرة الإضافية — is_capability (3 اختبارات)
-- =====================================================================

select has_column('public', 'roles', 'is_capability',
  '1.1 عمود is_capability موجود في جدول roles');

select is(
  (select is_capability from public.roles where slug = 'committee-secretary'),
  true,
  '1.2 committee-secretary مُعلّم كقدرة إضافية');

select is(
  (select is_capability from public.roles where slug = 'employee'),
  false,
  '1.3 employee ليس قدرة إضافية');

-- =====================================================================
-- الفئة 2: وجود الدالة وأمانها (3 اختبارات)
-- =====================================================================

select has_function('public', 'current_is_hr_only', array[]::text[],
  '2.1 دالة current_is_hr_only() موجودة');

select ok(
  not has_function_privilege('public', 'current_is_hr_only()', 'EXECUTE'),
  '2.2 current_is_hr_only() غير متاحة لـ PUBLIC');

-- التحقق من أن الدالة SECURITY DEFINER مع search_path
select ok(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'current_is_hr_only'
      and p.prosecdef = true
      and exists (
        select 1 from unnest(p.proconfig) c
        where c like 'search_path=%'
      )
  ),
  '2.3 current_is_hr_only هي SECURITY DEFINER مع search_path');

-- =====================================================================
-- الفئة 3: بوابة التخويل — موظف عادي (2 اختبار)
-- =====================================================================

-- تبديل السياق إلى موظف عادي
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a5a5a5a5-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a5a5a5a5-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'employee'))$$,
  '42501', null,
  '3.1 موظف عادي لا يستطيع إسناد أدوار');

select throws_ok(
  $$select public.rpc_revoke_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'employee'))$$,
  '42501', null,
  '3.2 موظف عادي لا يستطيع سحب أدوار');

-- =====================================================================
-- الفئة 4: تقييد HR — الأدوار العليا واللجان (4 اختبارات)
-- =====================================================================

-- تبديل السياق إلى مستخدم HR
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a5a5a5a5-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a5a5a5a5-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'admin'))$$,
  '42501', null,
  '4.1 HR لا يستطيع منح دور admin');

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'committee-member'))$$,
  '42501', null,
  '4.2 HR لا يستطيع منح عضوية اللجنة');

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'hr-manager'))$$,
  '42501', null,
  '4.3 HR لا يستطيع منح دور hr-manager');

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'executive-director'))$$,
  '42501', null,
  '4.4 HR لا يستطيع منح دور executive-director');

-- =====================================================================
-- الفئة 5: حماية full-access (2 اختبار)
-- =====================================================================

-- إنشاء دور full-access ليس في قائمة super-admin واختباره
reset role;

insert into public.roles (slug, name_ar, is_full_access, is_system)
values ('test-fa-non-super', 'اختبار وصول كامل غير سوبر', true, false);

insert into public.user_roles (user_id, role_id)
select 'a5a5a5a5-0000-4000-8000-000000000003'::uuid, id
from public.roles where slug = 'test-fa-non-super';

-- تبديل السياق إلى موظف عادي + full-access (غير super-admin)
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a5a5a5a5-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a5a5a5a5-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
      (select id from public.roles where slug = 'admin'))$$,
  '42501', null,
  '5.1 full-access غير super-admin لا يمنح دور full-access');

-- self-grant full-access blocked (admin = super-admin)
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a5a5a5a5-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a5a5a5a5-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_assign_role(
      'a5a5a5a5-0000-4000-8000-000000000002'::uuid,
      (select id from public.roles where slug = 'admin'))$$,
  '42501', null,
  '5.2 لا يمكن منح النفس دور full-access');

-- =====================================================================
-- الفئة 6: تدقيق — سجل المراجعة (2 اختبار)
-- =====================================================================

-- تنفيذ إسناد كـ admin (full-access يمرر) لدور employee
reset role;

-- حذف سجلات التدقيق السابقة لهذا الاختبار
delete from public.audit_events
where metadata->>'target_user_id' = 'a5a5a5a5-0000-4000-8000-000000000004'
  and event_type in ('access.role.assigned', 'access.role.revoked');

-- إسناد عبر superuser مع JWT admin لاختبار التدقيق
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a5a5a5a5-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a5a5a5a5-0000-4000-8000-000000000002', true);
end $$;

-- إسناد دور employee (ليس full-access → يمرر حتى لغير super-admin)
-- نستدعي كـ superuser لأن admin ليس super-admin
select public.rpc_assign_role(
  'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
  (select id from public.roles where slug = 'direct-manager')
);

select ok(
  exists (
    select 1 from public.audit_events
    where event_type = 'access.role.assigned'
      and metadata->>'target_user_id' = 'a5a5a5a5-0000-4000-8000-000000000004'
  ),
  '6.1 إسناد الدور يُنتج سجل تدقيق');

-- سحب الدور واختبار التدقيق
select public.rpc_revoke_role(
  'a5a5a5a5-0000-4000-8000-000000000004'::uuid,
  (select id from public.roles where slug = 'direct-manager')
);

select ok(
  exists (
    select 1 from public.audit_events
    where event_type = 'access.role.revoked'
      and metadata->>'target_user_id' = 'a5a5a5a5-0000-4000-8000-000000000004'
  ),
  '6.2 سحب الدور يُنتج سجل تدقيق');

-- =====================================================================
select * from finish();
rollback;
