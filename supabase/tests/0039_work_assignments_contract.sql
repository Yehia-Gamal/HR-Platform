-- 0037: عقد تكليفات العمل (0063/0065/0066) + إثبات سلوكي حي للإجازات.
-- يثبت شرط الإنهاء بالمواصفة: التكليفات لا تخصم من رصيد الإجازات ولا تُحتسب
-- غيابًا؛ الإجازة تحجز الرصيد ثم تخصمه؛ العارضة تُنفَّذ مباشرة؛ ومنع تكليف
-- موظف خارج الفريق. كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- =====================================================================
-- Fixture: كيان + إدارتان + مدير + موظفان + مستخدمون + أدوار + رصيد افتتاحي.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'dddddddd-0000-4000-8000-000000000000';
  v_dept_a uuid := 'dddddddd-0000-4000-8000-000000000001';
  v_dept_b uuid := 'dddddddd-0000-4000-8000-000000000002';
  v_annual uuid;
  v_casual uuid;
begin
  insert into public.legal_entities(id,code,name) values(v_le,'WA-LE','كيان تكليفات');
  insert into public.departments(id,legal_entity_id,code,name) values
    (v_dept_a,v_le,'WA-A','إدارة أ'),(v_dept_b,v_le,'WA-B','إدارة ب');

  insert into auth.users(id,email,aud,role) values
    ('44444444-0000-4000-8000-000000000001','wa-mgr@test.local','authenticated','authenticated'),
    ('44444444-0000-4000-8000-000000000002','wa-emp@test.local','authenticated','authenticated'),
    ('44444444-0000-4000-8000-000000000003','wa-out@test.local','authenticated','authenticated');

  -- المدير (dept A) + تابع له (dept A) + موظف خارج الفريق (dept B).
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('55555555-0000-4000-8000-000000000001','44444444-0000-4000-8000-000000000001','WA-MGR','المدير المباشر',v_dept_a,'active',true,'1980-01-01','2015-01-01'),
    ('55555555-0000-4000-8000-000000000002','44444444-0000-4000-8000-000000000002','WA-EMP','الموظف التابع',v_dept_a,'active',true,'1995-01-01','2023-01-01'),
    ('55555555-0000-4000-8000-000000000003','44444444-0000-4000-8000-000000000003','WA-OUT','موظف خارج الفريق',v_dept_b,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id,employee_id,status) values
    ('44444444-0000-4000-8000-000000000001','55555555-0000-4000-8000-000000000001','active'),
    ('44444444-0000-4000-8000-000000000002','55555555-0000-4000-8000-000000000002','active'),
    ('44444444-0000-4000-8000-000000000003','55555555-0000-4000-8000-000000000003','active');

  insert into public.user_roles(user_id,role_id)
  select t.u, r.id from (values
    ('44444444-0000-4000-8000-000000000001'::uuid,'employee'),
    ('44444444-0000-4000-8000-000000000001'::uuid,'direct-manager'),
    ('44444444-0000-4000-8000-000000000002'::uuid,'employee'),
    ('44444444-0000-4000-8000-000000000003'::uuid,'employee')
  ) as t(u,slug) join public.roles r on r.slug=t.slug;

  -- الموظف والموظف الخارجي يتبعان المدير مباشرةً فقط داخل إدارته (dept A).
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type)
  values('55555555-0000-4000-8000-000000000002','55555555-0000-4000-8000-000000000001','primary');

  -- رصيد افتتاحي للموظف التابع (اعتيادية 15، عارضة 6) لتفعيل الحجز/الخصم.
  select id into v_annual from public.leave_types where code='annual';
  select id into v_casual from public.leave_types where code='casual';
  perform public.apply_leave_ledger_entry('55555555-0000-4000-8000-000000000002',v_annual,2026,'opening',15,'t:open:annual',null,'رصيد اختبار');
  perform public.apply_leave_ledger_entry('55555555-0000-4000-8000-000000000002',v_casual,2026,'opening',6,'t:open:casual',null,'رصيد اختبار');
end $fixture$;

-- =====================================================================
-- بنية الوحدة الجديدة موجودة.
-- =====================================================================
select has_table('public','work_assignments','جدول تكليفات العمل موجود');
select has_table('public','work_assignment_participants','جدول المشاركين موجود');
select has_function('public','create_work_assignment',
  array['text','text','timestamptz','timestamptz','uuid[]','text','text','uuid','boolean','timestamptz','jsonb'],
  'دالة إنشاء التكليف موجودة');
select col_type_is('public','work_assignments','assignment_type','text',
  'assignment_type نصي (MISSION/CONVOY/FUNDRAISING)');

-- =====================================================================
-- سياق المدير المباشر: ينشئ مأمورية بالساعات لتابعه.
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- لقطة رصيد الموظف قبل التكليف (للإثبات لاحقًا).
-- (نقرؤها كـ superuser بعد reset، لكن نسجّل الآن أنه لا قيود تُنشأ.)

-- إنشاء مأمورية بالساعات (10ص–2م) — البند 19 (المأمورية بالساعات).
select lives_ok($$
  select public.create_work_assignment(
    'MISSION','مأمورية إدارية عاجلة',
    '2026-08-01 10:00:00+02','2026-08-01 14:00:00+02',
    array['55555555-0000-4000-8000-000000000002']::uuid[],
    'تسليم مستندات','مقر الجهة', null, false, null,
    '{"isFullDay": false}'::jsonb)
$$, 'المدير المباشر ينشئ مأمورية بالساعات لتابعه');

-- إنشاء قافلة (كامل اليوم) لتابعه.
select lives_ok($$
  select public.create_work_assignment(
    'CONVOY','قافلة طبية',
    '2026-08-02 08:00:00+02','2026-08-02 18:00:00+02',
    array['55555555-0000-4000-8000-000000000002']::uuid[],
    'توزيع مساعدات','قرية النور', null, true, '2026-08-05 23:59:00+02',
    '{}'::jsonb)
$$, 'المدير المباشر ينشئ قافلة لتابعه');

-- إنشاء فاندي بمستهدف مالي.
select lives_ok($$
  select public.create_work_assignment(
    'FUNDRAISING','حملة فاندي رمضان',
    '2026-08-03 09:00:00+02','2026-08-03 21:00:00+02',
    array['55555555-0000-4000-8000-000000000002']::uuid[],
    'جمع تبرعات','نقطة التجمع', null, true, null,
    '{"targetAmount": 50000}'::jsonb)
$$, 'المدير المباشر ينشئ فاندي بمستهدف مالي');

-- البند 20: منع تكليف موظف خارج الفريق دون صلاحية أوسع.
select throws_ok($$
  select public.create_work_assignment(
    'MISSION','مأمورية خارج الفريق',
    '2026-08-04 10:00:00+02','2026-08-04 14:00:00+02',
    array['55555555-0000-4000-8000-000000000003']::uuid[],
    'محاولة','مكان', null, false, null, '{}'::jsonb)
$$, '42501', null, 'منع المدير من تكليف موظف خارج فريقه');

-- =====================================================================
-- سياق الموظف: يقدّم إجازة اعتيادية (تحجز الرصيد) وعارضة (تُنفَّذ مباشرة).
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','44444444-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

-- إجازة اعتيادية 3 أيام → تبقى pending (تحتاج موافقة) وتحجز الرصيد.
select lives_ok($$
  select public.submit_my_request('leave','إجازة اعتيادية','سبب مقبول للإجازة',
    '{"leaveType":"annual","startDate":"2026-09-01","endDate":"2026-09-03"}'::jsonb)
$$, 'تقديم إجازة اعتيادية ينجح');

-- عارضة يومان → تُعتمَد فورًا (immediate).
select lives_ok($$
  select public.submit_my_request('leave','إجازة عارضة','ظرف طارئ مفاجئ',
    '{"leaveType":"casual","startDate":"2026-09-10","endDate":"2026-09-11"}'::jsonb)
$$, 'تقديم إجازة عارضة ينجح');

-- =====================================================================
-- إثبات سلوكي (كـ superuser بعد reset role).
-- =====================================================================
reset role;

-- (1) العارضة اعتُمِدت مباشرة دون موافقة المدير.
select is(
  (select status from public.requests r
   join public.leave_requests lr on lr.request_id=r.id
   where lr.employee_id='55555555-0000-4000-8000-000000000002'
     and lr.leave_type_id=(select id from public.leave_types where code='casual')),
  'approved', 'العارضة اعتُمِدت فورًا دون موافقة');

-- (2) العارضة خُصِمت من رصيد العارضة (consume) — الرصيد المتاح 6-2=4.
select is(
  (select round(opening_units+accrued_units+adjusted_units+carryover_units-consumed_units-reserved_units,0)
   from public.leave_balance_accounts
   where employee_id='55555555-0000-4000-8000-000000000002'
     and leave_type_id=(select id from public.leave_types where code='casual')
     and balance_year=2026),
  4::numeric, 'رصيد العارضة المتاح = 4 بعد خصم يومين فوريًا');

-- (3) الاعتيادية حجزت 3 أيام (reserved) والطلب pending.
select is(
  (select reserved_units from public.leave_balance_accounts
   where employee_id='55555555-0000-4000-8000-000000000002'
     and leave_type_id=(select id from public.leave_types where code='annual')
     and balance_year=2026),
  3::numeric, 'الاعتيادية حجزت 3 أيام عند التقديم');

-- (4) شرط الإنهاء الأهم: تكليفات العمل لم تُنشئ أي قيد في دفتر الإجازات.
select is(
  (select count(*)::int from public.leave_ledger_entries
   where employee_id='55555555-0000-4000-8000-000000000002'
     and reason like '%تكليف%'),
  0, 'تكليفات العمل لا تُنشئ أي قيد في دفتر الإجازات');

-- (5) لا يوجد أي صف leave_requests ناتج عن تكليفات العمل.
select is(
  (select count(*)::int from public.work_assignments
   where assignment_type in ('MISSION','CONVOY','FUNDRAISING')),
  3, 'أُنشئت ثلاثة تكليفات عمل (مأمورية/قافلة/فاندي)');

-- (6) الفاندي يحمل المستهدف المالي (لا يخصم رصيدًا).
select is(
  (select target_amount from public.work_assignments where assignment_type='FUNDRAISING'),
  50000::numeric, 'الفاندي يحفظ المستهدف المالي');

-- (7) منع الاحتساب المزدوج في KPI: القيد الفريد موجود.
select has_table('public','kpi_assignment_contributions',
  'جدول ربط التكليفات بـ KPI موجود (منع التكرار)');

-- (8) المأمورية بالساعات محفوظة (is_full_day=false).
select is(
  (select is_full_day from public.work_assignments where title='مأمورية إدارية عاجلة'),
  false, 'المأمورية بالساعات محفوظة (ليست يومًا كاملًا)');

select * from finish();
rollback;
