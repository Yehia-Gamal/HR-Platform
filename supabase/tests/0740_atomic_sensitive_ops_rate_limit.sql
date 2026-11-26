-- =====================================================================
-- 0740: اختبار تحديد المعدل الذري وصلاحيات التنفيذ على دوال الـ quota
-- ---------------------------------------------------------------------
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

do $fixture$
declare
  v_le    uuid := 'b7400000-0000-4000-8000-000000000001';
  v_dept  uuid := 'b7400000-0000-4000-8000-000000000002';
  v_actor uuid := 'b7400000-0000-4000-8000-000000000003';
  v_emp   uuid := 'b7400000-0000-4000-8000-000000000004';
begin
  insert into public.legal_entities(id, code, name)
  values (v_le, 'M740-LE', 'كيان اختبار تحديد المعدل');

  insert into public.departments(id, legal_entity_id, code, name)
  values (v_dept, v_le, 'M740-D', 'إدارة اختبار المعدل');

  insert into auth.users(id, email, aud, role)
  values (v_actor, 'm740-actor@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, birth_date, hire_date)
  values (v_emp, v_actor, 'M740-EMP', 'موظف اختبار المعدل', v_dept, 'active', true, '1992-01-01', '2021-01-01');
end $fixture$;

-- 1-2) صلاحيات التنفيذ مقتصرة على service_role فقط (ممنوعة عن authenticated)
select is(
  has_function_privilege(
    'authenticated',
    'public.consume_admin_sensitive_op_quota(uuid,text,uuid,integer,integer)',
    'EXECUTE'
  ),
  false,
  'authenticated must not execute consume_admin_sensitive_op_quota'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.consume_auth_invite_quota(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  false,
  'authenticated must not execute consume_auth_invite_quota'
);

-- 3-4) consume_admin_sensitive_op_quota تسمح ضمن الحد وتمنع عند تجاوزه
select is(
  public.consume_admin_sensitive_op_quota(
    'b7400000-0000-4000-8000-000000000003'::uuid,
    'set_password',
    'b7400000-0000-4000-8000-000000000004'::uuid,
    2,
    300
  ),
  true,
  'first sensitive op within quota is allowed'
);

select is(
  (
    select array_agg(res order by step)
    from (
      select 2 as step, public.consume_admin_sensitive_op_quota(
        'b7400000-0000-4000-8000-000000000003'::uuid,
        'set_password',
        'b7400000-0000-4000-8000-000000000004'::uuid,
        2,
        300
      ) as res
      union all
      select 3 as step, public.consume_admin_sensitive_op_quota(
        'b7400000-0000-4000-8000-000000000003'::uuid,
        'set_password',
        'b7400000-0000-4000-8000-000000000004'::uuid,
        2,
        300
      ) as res
    ) q
  ),
  array[true, false]::boolean[],
  'second op succeeds and third op exceeds max_count=2 atomically'
);

-- 5-6) consume_auth_invite_quota تسمح بالمحاولة الأولى وتمنع الثانية خلال النافذة
select is(
  public.consume_auth_invite_quota(
    'b7400000-0000-4000-8000-000000000004'::uuid,
    'b7400000-0000-4000-8000-000000000003'::uuid,
    'M740-EMP@test.local',
    60
  ),
  true,
  'first auth invite within window is allowed'
);

select is(
  public.consume_auth_invite_quota(
    'b7400000-0000-4000-8000-000000000004'::uuid,
    'b7400000-0000-4000-8000-000000000003'::uuid,
    'm740-emp@test.local',
    60
  ),
  false,
  'second auth invite within window is rejected atomically'
);

select * from finish();
rollback;
