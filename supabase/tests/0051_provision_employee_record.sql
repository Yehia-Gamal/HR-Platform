begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(13);

-- الفاعل (منشئ الموظف) — يجب أن يوجد كسجل auth حتى تمر قيود المفاتيح الأجنبية.
insert into auth.users(id,email,aud,role) values
 ('97000000-0000-4000-8000-000000000001','provisioner@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000010','new-emp-1@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000011','new-emp-2@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000012','new-emp-3@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000013','new-emp-4@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000014','new-emp-5@test.local','authenticated','authenticated');

-- ============================================================================
-- 1) المسار الأساسي: إنشاء موظف كامل مع كود صريح.
-- ============================================================================
select lives_ok(
 $$select public.provision_employee_record(
   '97000000-0000-4000-8000-000000000001'::uuid,
   '97000000-0000-4000-8000-000000000010'::uuid,
   'موظف الاختبار الأول','Test One','EMP-T001','01100000010','employee'
 )$$,
 'provision_employee_record ينشئ موظفاً بالمسار الأساسي');

select is(
 (select employee_code from public.employees where user_id='97000000-0000-4000-8000-000000000010'),
 'EMP-T001','الكود الصريح يُخزَّن كما هو');

select is(
 (select phone_e164 from public.employees where user_id='97000000-0000-4000-8000-000000000010'),
 '01100000010','رقم الهاتف يُخزَّن كما وصل');

select is(
 (select status from public.employees where user_id='97000000-0000-4000-8000-000000000010'),
 'invited','الحالة الافتراضية invited عند دعوة معلّقة');

select ok(
 exists(select 1 from public.profiles where id='97000000-0000-4000-8000-000000000010'),
 'يُنشأ سجل profile مرتبط');

select ok(
 exists(select 1 from public.user_roles where user_id='97000000-0000-4000-8000-000000000010'),
 'يُنشأ سجل user_roles');

-- ============================================================================
-- 2) اشتقاق الكود من الهاتف عند غيابه.
-- ============================================================================
select lives_ok(
 $$select public.provision_employee_record(
   '97000000-0000-4000-8000-000000000001'::uuid,
   '97000000-0000-4000-8000-000000000011'::uuid,
   'موظف الاختبار الثاني',null,null,'01100000011','employee'
 )$$,
 'provision_employee_record يقبل كوداً فارغاً');

select is(
 (select employee_code from public.employees where user_id='97000000-0000-4000-8000-000000000011'),
 '01100000011','الكود يُشتق من رقم الهاتف عند غيابه');

-- ============================================================================
-- 3) رفض الدور غير المعروف.
-- ============================================================================
select throws_ok(
 $$select public.provision_employee_record(
   '97000000-0000-4000-8000-000000000001'::uuid,
   '97000000-0000-4000-8000-000000000012'::uuid,
   'دور غير معروف',null,'EMP-BAD','01100000012','no-such-role'
 )$$,
 '22023',null,'يرفض slug دور غير موجود');

-- ============================================================================
-- 4) رفض تكرار كود الموظف بين النشطين.
-- ============================================================================
select throws_ok(
 $$select public.provision_employee_record(
   '97000000-0000-4000-8000-000000000001'::uuid,
   '97000000-0000-4000-8000-000000000013'::uuid,
   'كود مكرر',null,'EMP-T001','01100000013','employee'
 )$$,
 '23505',null,'يرفض كود موظف مكرر');

-- ============================================================================
-- 5) رفض تكرار رقم الهاتف بين النشطين (فحص صريح من 0125).
-- ============================================================================
select throws_ok(
 $$select public.provision_employee_record(
   '97000000-0000-4000-8000-000000000001'::uuid,
   '97000000-0000-4000-8000-000000000014'::uuid,
   'هاتف مكرر',null,'EMP-T099','01100000010','employee'
 )$$,
 '23505',null,'يرفض رقم هاتف مكرر لموظف نشط');

-- ============================================================================
-- 6) المسمى الوظيفي: مطابقة/إنشاء من الاسم الحر (find-or-create).
-- ============================================================================
insert into auth.users(id,email,aud,role) values
 ('97000000-0000-4000-8000-000000000020','jt-emp-1@test.local','authenticated','authenticated'),
 ('97000000-0000-4000-8000-000000000021','jt-emp-2@test.local','authenticated','authenticated');

select public.provision_employee_record(
  '97000000-0000-4000-8000-000000000001'::uuid,
  '97000000-0000-4000-8000-000000000020'::uuid,
  'موظف مسمى','','EMP-JT01','01100000020','employee',
  null,null,null,null,null,null,null,null,null,null,true,'محاسب أول');

select is(
 (select count(*)::integer from public.job_titles where lower(name)=lower('محاسب أول') and is_active=true),
 1,'يُنشأ مسمى وظيفي واحد من الاسم الحر');

-- استدعاء ثانٍ بنفس الاسم يجب أن يعيد استخدام المسمى ذاته (لا تكرار).
select public.provision_employee_record(
  '97000000-0000-4000-8000-000000000001'::uuid,
  '97000000-0000-4000-8000-000000000021'::uuid,
  'موظف مسمى ثانٍ','','EMP-JT02','01100000021','employee',
  null,null,null,null,null,null,null,null,null,null,true,'محاسب أول');

select is(
 (select count(*)::integer from public.job_titles where lower(name)=lower('محاسب أول') and is_active=true),
 1,'الاستدعاء الثاني بنفس المسمى لا يُنشئ تكراراً');

select * from finish();
rollback;
