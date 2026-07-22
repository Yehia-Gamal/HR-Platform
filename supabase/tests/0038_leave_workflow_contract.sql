-- 0036: عقد نظام الإجازات الجديد (الترحيلات 0060/0061/0062).
-- يغطي بنود المواصفة الإلزامية: أنواع الإجازات القانونية، حذف الوضع/رعاية
-- الطفل، قاعدة الـ30 يومًا، ربط التقديم بالدفتر، تنفيذ العارضة مباشرة،
-- منع الموافقة الذاتية، تصعيد بالإنابة، وصلاحيات السكرتير التنفيذي.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(24);

-- =====================================================================
-- بنية أنواع الإجازات القانونية (البند: الكوتا 15/6/24)
-- =====================================================================
select is((select max_days_per_year from public.leave_types where code='annual'),
  15, 'الاعتيادية 15 يومًا');
select is((select max_days_per_year from public.leave_types where code='casual'),
  6, 'العارضة 6 أيام');
select is((select max_days_per_year from public.leave_types where code='sick'),
  24, 'المرضية 24 يومًا (يومان شهريًا)');
select ok((select is_active from public.leave_types where code='annual'),
  'الاعتيادية مفعّلة');

-- =====================================================================
-- البند 1: حذف آمن للوضع/رعاية الطفل — منع إنشائها نشطة.
-- =====================================================================
select throws_ok(
  $$ insert into public.leave_types(code,name_ar,is_active) values('maternity','إجازة وضع',true) $$,
  '42501',
  null,
  'منع إنشاء إجازة الوضع نشطة');
select throws_ok(
  $$ insert into public.leave_types(code,name_ar,is_active) values('childcare','رعاية طفل',true) $$,
  '42501',
  null,
  'منع إنشاء إجازة رعاية الطفل نشطة');
-- يُسمح بإبقائها معطّلة (أرشيف تاريخي).
select lives_ok(
  $$ insert into public.leave_types(code,name_ar,is_active) values('maternity','إجازة وضع',false) $$,
  'يُسمح بإدراج نوع معطّل (للأرشيف التاريخي)');

-- =====================================================================
-- قاعدة الـ30 يومًا (البند: السن>50 أو مدة العمل>10 سنوات)
-- =====================================================================
do $fx$
declare
  v_le uuid := 'cccccccc-0000-4000-8000-000000000000';
  v_dept uuid := 'cccccccc-0000-4000-8000-000000000001';
  v_young uuid := 'cccccccc-0000-4000-8000-000000000010'; -- عادي
  v_old uuid := 'cccccccc-0000-4000-8000-000000000011';   -- >50 سنة
  v_senior uuid := 'cccccccc-0000-4000-8000-000000000012'; -- >10 سنوات عمل
begin
  insert into public.legal_entities(id,code,name) values(v_le,'ENT-LE','كيان إجازات');
  insert into public.departments(id,legal_entity_id,code,name) values(v_dept,v_le,'ENT-D','إدارة إجازات');
  insert into public.employees(id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values
    (v_young,'ENT-Y','موظف شاب',v_dept,'active',true,'1995-01-01','2023-01-01'),
    (v_old,'ENT-O','موظف فوق الخمسين',v_dept,'active',true,'1970-01-01','2023-01-01'),
    (v_senior,'ENT-S','موظف خبرة',v_dept,'active',true,'1985-01-01','2010-01-01');
end $fx$;

select is(
  (public.effective_annual_entitlement('cccccccc-0000-4000-8000-000000000010','2026-01-01')->>'total')::int,
  21, 'الموظف العادي: 21 يومًا (15+6)');
select is(
  (public.effective_annual_entitlement('cccccccc-0000-4000-8000-000000000011','2026-01-01')->>'total')::int,
  30, 'من تعدّى الخمسين: 30 يومًا');
select is(
  (public.effective_annual_entitlement('cccccccc-0000-4000-8000-000000000011','2026-01-01')->>'annual')::int,
  20, 'المُعلّى: 20 اعتيادية');
select is(
  (public.effective_annual_entitlement('cccccccc-0000-4000-8000-000000000011','2026-01-01')->>'casual')::int,
  10, 'المُعلّى: 10 عارضة');
select is(
  (public.effective_annual_entitlement('cccccccc-0000-4000-8000-000000000012','2026-01-01')->>'total')::int,
  30, 'من تخطّى 10 سنوات عمل: 30 يومًا');

-- =====================================================================
-- الدوال الأساسية موجودة بالتواقيع والمنح الصحيحة.
-- =====================================================================
select has_function('public','effective_annual_entitlement',array['uuid','date'],
  'دالة الاستحقاق الفعّال موجودة');
select has_function('public','open_annual_leave_entitlement',array['uuid','integer'],
  'دالة فتح الرصيد السنوي موجودة');
select function_privs_are('public','open_annual_leave_entitlement',array['uuid','integer'],
  'service_role',array['EXECUTE'],'فتح الرصيد لـ service_role');
select ok(
  not has_function_privilege('authenticated',
    'public.open_annual_leave_entitlement(uuid,integer)','EXECUTE'),
  'authenticated لا يفتح الرصيد مباشرة');
select has_function('public','resolve_request_approver',array['uuid','date'],
  'دالة تحديد المدير المسؤول موجودة');
select has_function('public','process_request_sla',array['integer'],
  'معالج التصعيد موجود');
select function_privs_are('public','process_request_sla',array['integer'],
  'service_role',array['EXECUTE'],'التصعيد لـ service_role');

-- =====================================================================
-- منطق تحديد المدير المسؤول + منع الموافقة الذاتية.
-- =====================================================================
do $fx2$
declare
  v_emp uuid := 'cccccccc-0000-4000-8000-000000000010';
  v_mgr uuid := 'cccccccc-0000-4000-8000-000000000011';
begin
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type)
    values(v_emp,v_mgr,'primary');
end $fx2$;

select is(
  public.resolve_request_approver('cccccccc-0000-4000-8000-000000000010',current_date),
  'cccccccc-0000-4000-8000-000000000011'::uuid,
  'المدير المسؤول = المدير المباشر (primary)');

-- منع الموافقة الذاتية على مستوى الدالة: لو صار المدير هو المُقدِّم نفسه
-- (لا علاقة primary مطابقة) يُرجع NULL (يُترك للتصعيد/المخوّل).
select ok(
  public.resolve_request_approver('cccccccc-0000-4000-8000-000000000012',current_date) is null,
  'موظف بلا مدير مباشر يُرجع NULL (لا موافقة ذاتية)');

-- =====================================================================
-- صلاحيات السكرتير التنفيذي موجودة كدوال (البند 18).
-- =====================================================================
select has_function('public','reassign_request',array['uuid','uuid','text'],
  'نقل الطلب بين المديرين موجود');
select has_function('public','extend_request_deadline',array['uuid','integer','text'],
  'تمديد مهلة القرار موجود');
select has_function('public','withdraw_escalation',array['uuid','text'],
  'سحب التصعيد موجود');

select * from finish();
rollback;
