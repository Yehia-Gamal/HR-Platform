-- =====================================================================
-- 0104: إصلاحات التدقيق 0263 — منح الدوال الأربع + حرّاس RPC
--   1-4. الدوال الأربع ممنوحة للمصادقين (EXECUTE) بعدما كانت محظورة.
--   5-6. admin_create_task/admin_transition_task قابلة للاستدعاء للمصادقين.
--   7.   موظف عادي (بلا tasks.write) يُرفض من إنشاء المهام (42501).
--   8.   صاحب صلاحية كاملة: عنوان فارغ → 22023 (TITLE_REQUIRED).
--   9.   صاحب صلاحية كاملة: أولوية غير صالحة → 22023 (INVALID_PRIORITY).
--   10.  صاحب صلاحية كاملة: حالة مهمة غير صالحة → 22023 (INVALID_TASK_STATUS).
--   11.  موظف عادي يُرفض من سحب الأدوار (42501).
--   12.  دور full-access غير super-admin لا يسحب دور full-access (42501).
--   13.  موظف عادي لا يقرأ كتالوج المؤسسة (42501).
--   14.  صاحب صلاحية كاملة يقرأ كتالوج المؤسسة.
--   15.  الموظف لا يغيّر is_deleted على نفسه (42501 عبر trigger).
-- 15 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- تعطيل trigger الإشعارات لتجنب أخطاء الـ fixture
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

-- =====================================================================
-- 1-6. منح الدوال (superuser)
-- =====================================================================
select function_privs_are('public','get_audit_security_data',array[]::text[],'authenticated',array['EXECUTE'],'1. get_audit_security_data ممنوحة للمصادقين');
select function_privs_are('public','get_integration_center_data',array[]::text[],'authenticated',array['EXECUTE'],'2. get_integration_center_data ممنوحة للمصادقين');
select function_privs_are('public','get_operations_center_data',array[]::text[],'authenticated',array['EXECUTE'],'3. get_operations_center_data ممنوحة للمصادقين');
select function_privs_are('public','get_employee_photo_url',array['uuid'],'authenticated',array['EXECUTE'],'4. get_employee_photo_url ممنوحة للمصادقين');
select function_privs_are('public','admin_create_task',array['text','text','uuid','text','date'],'authenticated',array['EXECUTE'],'5. admin_create_task ممنوحة للمصادقين');
select function_privs_are('public','admin_transition_task',array['uuid','text'],'authenticated',array['EXECUTE'],'6. admin_transition_task ممنوحة للمصادقين');

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
declare
  v_le         uuid := 'a7a80000-0000-4000-8000-000000000000';
  v_dept       uuid := 'a7a80000-0000-4000-8000-000000000010';
  v_user_e     uuid := 'a7a80000-0000-4000-8000-000000000001'; -- موظف عادي
  v_user_a     uuid := 'a7a80000-0000-4000-8000-000000000002'; -- full-access مخصص
  v_user_a2    uuid := 'a7a80000-0000-4000-8000-000000000003'; -- full-access مخصص (هدف)
  v_emp_e      uuid := 'a7a80000-0000-4000-8000-000000000011';
  v_emp_a      uuid := 'a7a80000-0000-4000-8000-000000000012';
  v_emp_a2     uuid := 'a7a80000-0000-4000-8000-000000000013';
  v_role_emp   uuid;
  v_role_full  uuid;
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'A8-LE', 'كيان اختبار تدقيق 0263');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'A8-D1', 'إدارة اختبار تدقيق 0263');

  insert into auth.users (id, email, aud, role) values
    (v_user_e,  'a8-emp@test.local',   'authenticated', 'authenticated'),
    (v_user_a,  'a8-admin@test.local', 'authenticated', 'authenticated'),
    (v_user_a2, 'a8-admin2@test.local','authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    (v_emp_e,  v_user_e,  'A8-001', 'موظف عادي',   v_dept, 'active', true),
    (v_emp_a,  v_user_a,  'A8-002', 'مسؤول كامل',  v_dept, 'active', true),
    (v_emp_a2, v_user_a2, 'A8-003', 'مسؤول كامل 2',v_dept, 'active', true);

  insert into public.profiles (id, employee_id, status) values
    (v_user_e,  v_emp_e,  'active'),
    (v_user_a,  v_emp_a,  'active'),
    (v_user_a2, v_emp_a2, 'active');

  select id into v_role_emp from public.roles where slug = 'employee';

  -- دور full-access مخصص (ليس في قائمة super-admin slugs) لاختبار الحارس.
  insert into public.roles (slug, name_ar, description, is_system, is_full_access)
  values ('test-full-access-0263', 'اختبار وصول كامل', 'دور اختبار', false, true)
  on conflict (slug) do update set is_full_access = excluded.is_full_access;
  select id into v_role_full from public.roles where slug = 'test-full-access-0263';

  insert into public.user_roles (user_id, role_id) values
    (v_user_e,  v_role_emp),
    (v_user_a,  v_role_full),
    (v_user_a2, v_role_full);
end
$fixture$;

-- =====================================================================
-- 7. موظف عادي بلا tasks.write يُرفض من إنشاء المهام
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.admin_create_task('مهمة', null, null, 'medium', null)$$,
  '42501', null,
  '7. الموظف العادي لا ينشئ المهام (يحتاج tasks.write)'
);

-- =====================================================================
-- 8. full-access: عنوان فارغ → TITLE_REQUIRED
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.admin_create_task('   ', null, null, 'medium', null)$$,
  '22023', null,
  '8. عنوان المهمة الفارغ مرفوض (TITLE_REQUIRED)'
);

-- =====================================================================
-- 9. full-access: أولوية غير صالحة
-- =====================================================================
select throws_ok(
  $$select public.admin_create_task('مهمة', null, null, 'bogus', null)$$,
  '22023', null,
  '9. الأولوية غير الصالحة مرفوضة (INVALID_PRIORITY)'
);

-- =====================================================================
-- 10. full-access: حالة مهمة غير صالحة
-- =====================================================================
select throws_ok(
  $$select public.admin_transition_task('a7a80000-0000-4000-8000-0000000000ff', 'bogus')$$,
  '22023', null,
  '10. حالة المهمة غير الصالحة مرفوضة (INVALID_TASK_STATUS)'
);

-- =====================================================================
-- 11. موظف عادي يُرفض من سحب الأدوار
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_revoke_role('a7a80000-0000-4000-8000-000000000002',
      (select id from public.roles where slug='test-full-access-0263'))$$,
  '42501', null,
  '11. الموظف العادي لا يسحب الأدوار'
);

-- =====================================================================
-- 12. full-access غير super-admin لا يسحب دور full-access
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.rpc_revoke_role('a7a80000-0000-4000-8000-000000000003',
      (select id from public.roles where slug='test-full-access-0263'))$$,
  '42501', null,
  '12. دور full-access غير super-admin لا يسحب دور full-access'
);

-- =====================================================================
-- 13. موظف عادي لا يقرأ كتالوج المؤسسة
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_enterprise_management_catalog()$$,
  '42501', null,
  '13. الموظف العادي لا يقرأ كتالوج المؤسسة'
);

-- =====================================================================
-- 14. صاحب الصلاحية الكاملة يقرأ كتالوج المؤسسة
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_enterprise_management_catalog()$$,
  '14. صاحب الصلاحية الكاملة يقرأ كتالوج المؤسسة'
);

-- =====================================================================
-- 15. الموظف لا يغيّر is_deleted على نفسه (حارس tg_employees_protect_job_fields)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a80000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a80000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$update public.employees set is_deleted = true where id = 'a7a80000-0000-4000-8000-000000000011'$$,
  '42501', null,
  '15. الموظف لا يغيّر is_deleted على نفسه (يتطلب people.employee.update_sensitive)'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
