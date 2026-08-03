-- pgTAP: V17 — سياسة القراءة على employee_departments (migration 0254)
-- يتحقق من أن سياسة SELECT الجديدة تسمح فقط لـ: صاحب السجل / full-access /
-- HR / مدير مباشر (can_access_employee) — وتُرفض القراءة لأي شخص آخر.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

-- ═══════════════════════════════════════════════════════════════════════
-- Fixture: كيان + إدارتان + 3 مستخدمين (full-access / موظف عادي / HR)
-- ═══════════════════════════════════════════════════════════════════════
do $fixture$
declare
  v_le uuid := 'fb000000-0000-4000-8000-000000000100';
  v_dept_a uuid := 'fb000000-0000-4000-8000-000000000101';
  v_dept_b uuid := 'fb000000-0000-4000-8000-000000000102';
  v_admin_uid uuid := 'fb000000-0000-4000-8000-000000000190';
  v_plain_uid uuid := 'fb000000-0000-4000-8000-000000000191';
  v_hr_uid uuid := 'fb000000-0000-4000-8000-000000000192';
  v_emp_target uuid := 'fb000000-0000-4000-8000-000000000193';
  v_emp_plain uuid := 'fb000000-0000-4000-8000-000000000194';
  v_emp_admin uuid := 'fb000000-0000-4000-8000-000000000195';
  v_emp_hr uuid := 'fb000000-0000-4000-8000-000000000196';
begin
  insert into public.legal_entities(id,code,name) values(v_le,'MD96-LE','كيان RLS قراءة');
  insert into public.departments(id,legal_entity_id,code,name) values
    (v_dept_a,v_le,'MD96-A','إدارة أ'),
    (v_dept_b,v_le,'MD96-B','إدارة ب');

  insert into auth.users(id,email,aud,role) values
    (v_admin_uid,'md96-admin@test.local','authenticated','authenticated'),
    (v_plain_uid,'md96-plain@test.local','authenticated','authenticated'),
    (v_hr_uid,'md96-hr@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values
      (v_emp_target,null,'MD96-TGT','موظف مستهدف',null,'active',true,'1990-01-01','2020-01-01'),
      (v_emp_plain,v_plain_uid,'MD96-PLN','موظف عادي',null,'active',true,'1991-01-01','2020-01-01'),
      (v_emp_admin,v_admin_uid,'MD96-ADM','أدمن',null,'active',true,'1985-01-01','2018-01-01'),
      (v_emp_hr,v_hr_uid,'MD96-HR','موظف HR',null,'active',true,'1986-01-01','2019-01-01');

  insert into public.profiles(id,employee_id,status) values
    (v_admin_uid,v_emp_admin,'active'),
    (v_plain_uid,v_emp_plain,'active'),
    (v_hr_uid,v_emp_hr,'active');

  insert into public.user_roles(user_id,role_id,effective_from)
    select v_admin_uid, id, now() from public.roles where slug = 'executive-secretary';
  insert into public.user_roles(user_id,role_id,effective_from)
    select v_plain_uid, id, now() from public.roles where slug = 'employee';
  insert into public.user_roles(user_id,role_id,effective_from)
    select v_hr_uid, id, now() from public.roles where slug = 'hr-specialist';

  -- المستهدف يعمل في إدارتين
  insert into public.employee_departments(employee_id,department_id,is_primary) values
    (v_emp_target,v_dept_a,true),
    (v_emp_target,v_dept_b,false);
  -- الموظف العادي في إدارة واحدة
  insert into public.employee_departments(employee_id,department_id,is_primary) values
    (v_emp_plain,v_dept_a,true);
end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) full-access يقرأ كل شيء
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000190',true);

select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000193'),
  2::bigint,
  'full-access reads all target departments');

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الموظف العادي يقرأ سجله فقط (self)
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000191',true);

select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000194'),
  1::bigint,
  'plain employee reads own department row');

-- 3) لا يقرأ إدارات موظف آخر
select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000193'),
  0::bigint,
  'plain employee cannot read another employee departments');

-- ═══════════════════════════════════════════════════════════════════════
-- 4) مدير مباشر يقرأ إدارات مرؤوسه
-- ═══════════════════════════════════════════════════════════════════════
reset role;
insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
  values ('fb000000-0000-4000-8000-000000000193',
          'fb000000-0000-4000-8000-000000000194','primary',now());

set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000191',true);

select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000193'),
  2::bigint,
  'direct manager reads subordinate departments');

-- ═══════════════════════════════════════════════════════════════════════
-- 5) إزالة العلاقة → يعود محجوباً
-- ═══════════════════════════════════════════════════════════════════════
reset role;
delete from public.manager_relations
 where employee_id = 'fb000000-0000-4000-8000-000000000193'
   and manager_employee_id = 'fb000000-0000-4000-8000-000000000194';

set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000191',true);

select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000193'),
  0::bigint,
  'plain employee blocked again after manager relation removed');

-- ═══════════════════════════════════════════════════════════════════════
-- 6) HR (بدون full-access) يقرأ إدارات الموظفين
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000192',true);

select is(
  (select count(*) from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000193'),
  2::bigint,
  'hr-only user reads target departments');

-- ═══════════════════════════════════════════════════════════════════════
-- 7) RPC get_employee_departments (secdef) لا يزال يعمل لمستدعٍ مخوّل
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000190',true);

select is(
  (select jsonb_array_length(public.get_employee_departments('fb000000-0000-4000-8000-000000000193'))),
  2,
  'get_employee_departments RPC still works for authorized caller');

select * from finish();
rollback;
