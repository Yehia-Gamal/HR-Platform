-- pgTAP: V23 §12 — multi-department behavioral tests (migrations 0156 + 0173)
-- يتحقق من: السلوك الفعلي لتعيين/إزالة الإدارات، trigger المزامنة،
--           الترقية التلقائية، حارس الصلاحيات، قيود التخصيص.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(19);

-- ═══════════════════════════════════════════════════════════════════════
-- Fixture: مستخدمون + موظف + إدارتان
-- ═══════════════════════════════════════════════════════════════════════
do $fixture$
declare
  v_le uuid := 'fb000000-0000-4000-8000-000000000000';
  v_dept_a uuid := 'fb000000-0000-4000-8000-000000000001';
  v_dept_b uuid := 'fb000000-0000-4000-8000-000000000002';
  v_dept_c uuid := 'fb000000-0000-4000-8000-000000000003';
  v_emp uuid := 'fb000000-0000-4000-8000-000000000010';
  v_emp_admin uuid := 'fb000000-0000-4000-8000-000000000011';
  v_admin_uid uuid := 'fb000000-0000-4000-8000-000000000090';
  v_plain_uid uuid := 'fb000000-0000-4000-8000-000000000091';
begin
  -- كيان قانوني + 3 إدارات
  insert into public.legal_entities(id,code,name) values(v_le,'MD77-LE','كيان §12');
  insert into public.departments(id,legal_entity_id,code,name) values
    (v_dept_a,v_le,'MD77-A','إدارة أ'),
    (v_dept_b,v_le,'MD77-B','إدارة ب'),
    (v_dept_c,v_le,'MD77-C','إدارة ج');

  -- مستخدمان: admin (full-access) و plain (employee فقط)
  insert into auth.users(id,email,aud,role) values
    (v_admin_uid,'md77-admin@test.local','authenticated','authenticated'),
    (v_plain_uid,'md77-plain@test.local','authenticated','authenticated');

  -- موظفان: واحد للأدمن وواحد للعادي
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values(v_emp,v_plain_uid,'MD77-001','موظف تعدد إدارات',null,'active',true,'1990-01-01','2020-01-01');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values('fb000000-0000-4000-8000-000000000011',v_admin_uid,'MD77-ADM','أدمن تعدد إدارات',null,'active',true,'1985-01-01','2018-01-01');

  insert into public.profiles(id,employee_id,status) values
    (v_admin_uid,'fb000000-0000-4000-8000-000000000011','active'),
    (v_plain_uid,v_emp,'active');

  -- admin يحصل على دور full-access
  insert into public.user_roles(user_id,role_id,effective_from)
    select v_admin_uid, id, now() from public.roles where slug = 'executive-secretary';

  -- plain يحصل على دور موظف فقط
  insert into public.user_roles(user_id,role_id,effective_from)
    select v_plain_uid, id, now() from public.roles where slug = 'employee';
end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) assign أول إدارة → تصبح أساسية تلقائياً
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000090',true);

select lives_ok(
  $$select public.assign_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000001',
    'مسمى أ', false, 'أول تعيين'
  )$$,
  'assign first department succeeds');

-- أول إدارة تصبح أساسية تلقائياً حتى لو أرسلنا false
select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000001'),
  true,
  'first department auto-promoted to primary');

-- ═══════════════════════════════════════════════════════════════════════
-- 2) trigger يزامن employees.department_id مع الإدارة الأساسية
-- ═══════════════════════════════════════════════════════════════════════
reset role;
select is(
  (select department_id from public.employees where id = 'fb000000-0000-4000-8000-000000000010'),
  'fb000000-0000-4000-8000-000000000001'::uuid,
  'employees.department_id synced to primary department A');

-- ═══════════════════════════════════════════════════════════════════════
-- 3) assign إدارة ثانية (ليست أساسية)
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000090',true);

select lives_ok(
  $$select public.assign_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000002',
    'مسمى ب', false, 'ثاني تعيين'
  )$$,
  'assign second department succeeds');

select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000002'),
  false,
  'second department is NOT primary');

-- الأولى لا تزال أساسية
select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000001'),
  true,
  'first department remains primary');

-- ═══════════════════════════════════════════════════════════════════════
-- 4) set_primary_department: نقل الأساسية للثانية
-- ═══════════════════════════════════════════════════════════════════════
select lives_ok(
  $$select public.set_primary_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000002'
  )$$,
  'set_primary_department to B succeeds');

-- الثانية أصبحت أساسية
select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000002'),
  true,
  'department B is now primary');

-- الأولى فقدت العلامة
select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000001'),
  false,
  'department A lost primary flag');

-- employees.department_id تزامن مع B
reset role;
select is(
  (select department_id from public.employees where id = 'fb000000-0000-4000-8000-000000000010'),
  'fb000000-0000-4000-8000-000000000002'::uuid,
  'employees.department_id synced to department B');

-- ═══════════════════════════════════════════════════════════════════════
-- 5) get_employee_departments: يعيد كلتا الإدارتين بالترتيب
-- ═══════════════════════════════════════════════════════════════════════
select is(
  (select jsonb_array_length(public.get_employee_departments('fb000000-0000-4000-8000-000000000010'))),
  2,
  'get_employee_departments returns 2 departments');

-- أول عنصر = الأساسية (B)
select is(
  (select (public.get_employee_departments('fb000000-0000-4000-8000-000000000010')->0->>'isPrimary')::boolean),
  true,
  'first element in result is the primary department');

-- ═══════════════════════════════════════════════════════════════════════
-- 6) remove_employee_department: إزالة الأساسية → ترقية الأقدم
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000090',true);

select lives_ok(
  $$select public.remove_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000002'
  )$$,
  'remove primary department B succeeds');

-- A ترقّت تلقائياً
select is(
  (select is_primary from public.employee_departments
   where employee_id = 'fb000000-0000-4000-8000-000000000010'
     and department_id = 'fb000000-0000-4000-8000-000000000001'),
  true,
  'department A auto-promoted to primary after B removed');

-- employees.department_id تزامن مع A
reset role;
select is(
  (select department_id from public.employees where id = 'fb000000-0000-4000-8000-000000000010'),
  'fb000000-0000-4000-8000-000000000001'::uuid,
  'employees.department_id synced back to A');

-- ═══════════════════════════════════════════════════════════════════════
-- 7) إزالة آخر إدارة → employees.department_id = NULL
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000090',true);

select lives_ok(
  $$select public.remove_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000001'
  )$$,
  'remove last department A succeeds');

reset role;
select is(
  (select department_id from public.employees where id = 'fb000000-0000-4000-8000-000000000010'),
  null::uuid,
  'employees.department_id is NULL after all departments removed');

-- ═══════════════════════════════════════════════════════════════════════
-- 8) حارس الصلاحيات: موظف عادي لا يستطيع assign
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000091',true);

select throws_ok(
  $$select public.assign_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000003'
  )$$,
  '42501',
  'FORBIDDEN',
  'plain employee cannot assign department');

-- ═══════════════════════════════════════════════════════════════════════
-- 9) حارس الصلاحيات: موظف عادي لا يستطيع remove
-- ═══════════════════════════════════════════════════════════════════════
select throws_ok(
  $$select public.remove_employee_department(
    'fb000000-0000-4000-8000-000000000010',
    'fb000000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'FORBIDDEN',
  'plain employee cannot remove department');

select * from finish();
rollback;
