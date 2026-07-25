-- 0052: V17 employee edit/enriched-list runtime contract for migration 0129.
-- Uses isolated fixtures and rolls back all writes.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

select has_function(
  'public', 'update_employee_admin', array['uuid','jsonb','text'],
  'employee admin patch RPC exists'
);
select has_function(
  'public', 'get_employees_enriched', array['text','text','integer'],
  'enriched employee list RPC exists'
);

do $fixture$
declare
  v_entity uuid := 'a5200000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-EMP-LE', 'كيان اختبار تعديل الموظف');

  insert into public.departments(id, legal_entity_id, code, name) values
    ('a5200000-0000-4000-8000-000000000010', v_entity, 'V17-OLD', 'الإدارة القديمة'),
    ('a5200000-0000-4000-8000-000000000011', v_entity, 'V17-NEW', 'الإدارة الجديدة');

  insert into auth.users(id, email, aud, role) values
    ('a5200000-0000-4000-8000-000000000101', 'v17-admin@test.local', 'authenticated', 'authenticated'),
    ('a5200000-0000-4000-8000-000000000102', 'v17-employee@test.local', 'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id,
    status, is_active, is_deleted
  ) values
    ('a5200000-0000-4000-8000-000000000201', 'a5200000-0000-4000-8000-000000000101', 'V17-ADM', 'مسؤول الاختبار', 'a5200000-0000-4000-8000-000000000010', 'active', true, false),
    ('a5200000-0000-4000-8000-000000000202', 'a5200000-0000-4000-8000-000000000102', 'V17-EMP', 'موظف الاختبار', 'a5200000-0000-4000-8000-000000000010', 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a5200000-0000-4000-8000-000000000101', 'a5200000-0000-4000-8000-000000000201', 'active'),
    ('a5200000-0000-4000-8000-000000000102', 'a5200000-0000-4000-8000-000000000202', 'active');

  insert into public.user_roles(user_id, role_id)
  select 'a5200000-0000-4000-8000-000000000101', id from public.roles where slug='admin';
  insert into public.user_roles(user_id, role_id)
  select 'a5200000-0000-4000-8000-000000000102', id from public.roles where slug='employee';
end
$fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

select pg_temp.act_as('a5200000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $$select public.update_employee_admin(
    'a5200000-0000-4000-8000-000000000202',
    '{"fullNameAr":"تعديل غير مسموح"}'::jsonb,
    'اختبار رفض الصلاحية'
  )$$,
  '42501', null, 'employee cannot update employee administration fields'
);

reset role;
select pg_temp.act_as('a5200000-0000-4000-8000-000000000101');
set local role authenticated;

select lives_ok(
  $$select public.update_employee_admin(
    'a5200000-0000-4000-8000-000000000202',
    '{"fullNameAr":"موظف محدث","departmentId":"a5200000-0000-4000-8000-000000000011"}'::jsonb,
    'نقل إداري معتمد للاختبار'
  )$$,
  'full-access administrator can patch basic and sensitive fields'
);

select is(
  (select full_name_ar from public.employees where id='a5200000-0000-4000-8000-000000000202'),
  'موظف محدث', 'basic field persisted'
);
select is(
  (select department_id from public.employees where id='a5200000-0000-4000-8000-000000000202'),
  'a5200000-0000-4000-8000-000000000011'::uuid, 'sensitive FK field persisted'
);

select is(
  (public.get_employee_360('a5200000-0000-4000-8000-000000000202')->>'departmentId')::uuid,
  'a5200000-0000-4000-8000-000000000011'::uuid,
  'employee 360 returns raw department id'
);

select is(
  (select item->>'department'
   from jsonb_array_elements(public.get_employees_enriched('V17-EMP', 'active', 20)) item
   where item->>'id'='a5200000-0000-4000-8000-000000000202'),
  'الإدارة الجديدة', 'enriched list returns joined department name'
);

select is(
  jsonb_array_length(public.get_employees_enriched('V17', 'active', 0)) >= 1,
  true, 'non-positive limit is safely clamped'
);

select throws_ok(
  $$select public.update_employee_admin(
    'a5200000-0000-4000-8000-000000000202',
    '{"unexpected":"value"}'::jsonb,
    'حقل غير معروف'
  )$$,
  '22023', null, 'unknown patch field is rejected'
);

select throws_ok(
  $$select public.update_employee_admin(
    'a5200000-0000-4000-8000-000000000202',
    '{"fullNameAr":"اسم آخر"}'::jsonb,
    ' '
  )$$,
  '22023', null, 'change reason is mandatory'
);

select is(
  (select count(*)::int >= 1 from public.audit_events
   where target_table='employees'
     and target_id='a5200000-0000-4000-8000-000000000202'),
  true, 'employee update writes an audit event'
);

select * from finish();
rollback;
