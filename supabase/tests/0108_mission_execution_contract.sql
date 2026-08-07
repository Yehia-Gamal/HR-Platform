-- =====================================================================
-- 0108: عقد تنفيذ المأمورية (0318)
-- ---------------------------------------------------------------------
-- يثبت: بنية الجدول، اشتراط الاعتماد قبل البدء، بدء/إنهاء للمالك فقط،
-- التقرير الإلزامي (≥3 أحرف)، المدة الفعلية غير ملزمة (≥1 دقيقة)،
-- الرفض المزدوج، قبول startTime بصيغة HH:MM (رفض "9:00")،
-- وصول missionExecution في inbox/detail، وإغلاق الوصول عن anon.
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(28);

-- =====================================================================
-- Fixture: كيان + إدارتان + مدير + موظف + دُخَلاو خارج الفريق.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'a1080000-0000-4000-8000-000000000001';
  v_dept_a uuid := 'a1080000-0000-4000-8000-000000000002';
  v_dept_b uuid := 'a1080000-0000-4000-8000-000000000003';
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'ME-LE', 'كيان تنفيذ المأموريات');
  insert into public.departments(id, legal_entity_id, code, name) values
    (v_dept_a, v_le, 'ME-A', 'إدارة أ'),
    (v_dept_b, v_le, 'ME-B', 'إدارة ب');

  insert into auth.users(id, email, aud, role) values
    ('a1080000-0000-4000-8000-000000000004','me-mgr@test.local','authenticated','authenticated'),
    ('a1080000-0000-4000-8000-000000000005','me-emp@test.local','authenticated','authenticated'),
    ('a1080000-0000-4000-8000-000000000006','me-out@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('a1080000-0000-4000-8000-000000000011','a1080000-0000-4000-8000-000000000004','ME-MGR','مدير المأمورية',v_dept_a,'active',true,'1980-01-01','2015-01-01'),
    ('a1080000-0000-4000-8000-000000000012','a1080000-0000-4000-8000-000000000005','ME-EMP','موظف المأمورية',v_dept_a,'active',true,'1995-01-01','2023-01-01'),
    ('a1080000-0000-4000-8000-000000000013','a1080000-0000-4000-8000-000000000006','ME-OUT','موظف خارج الفريق',v_dept_b,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id, employee_id, status) values
    ('a1080000-0000-4000-8000-000000000004','a1080000-0000-4000-8000-000000000011','active'),
    ('a1080000-0000-4000-8000-000000000005','a1080000-0000-4000-8000-000000000012','active'),
    ('a1080000-0000-4000-8000-000000000006','a1080000-0000-4000-8000-000000000013','active');

  insert into public.user_roles(user_id, role_id)
  select t.u, r.id from (values
    ('a1080000-0000-4000-8000-000000000004'::uuid,'employee'),
    ('a1080000-0000-4000-8000-000000000004'::uuid,'direct-manager'),
    ('a1080000-0000-4000-8000-000000000005'::uuid,'employee'),
    ('a1080000-0000-4000-8000-000000000006'::uuid,'employee')
  ) as t(u,slug) join public.roles r on r.slug=t.slug;

  -- الموظف يتبع المدير مباشرة (relation_type primary — effective_from = اليوم).
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type)
  values('a1080000-0000-4000-8000-000000000012','a1080000-0000-4000-8000-000000000011','primary');

  -- سجل معرّفات طلبات الاختبار.
  create temp table pg_temp.me_req_ids(request_id uuid, rtype text) on commit drop;
end $fixture$;

-- مساعد سياق هوية — يبدّل الموظف النشط عبر jwt claims.
-- (الدوال المستهدفة security definer: سياق الجلسة كافٍ بلا set role.)
do $set_emp$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
end $set_emp$;

-- =====================================================================
-- بنية الجدول والدوال.
-- =====================================================================
select has_table('public','mission_executions','جدول mission_executions موجود');
select col_type_is('public','mission_executions','status','text','status نصي');
select col_is_pk('public','mission_executions','id','id مفتاح رئيسي');
select col_is_unique('public','mission_executions','request_id','request_id فريد (تنفيذ واحد لكل طلب)');
select has_function('public','start_my_mission',array['uuid'],'start_my_mission(uuid) موجودة');
select has_function('public','end_my_mission',array['uuid','text','text'],'end_my_mission(uuid,text,text) موجودة');

-- =====================================================================
-- التقديم: startTime اختياري بصيغة HH:MM — يرفض "9:00".
-- =====================================================================
select lives_ok($$
  insert into pg_temp.me_req_ids(request_id, rtype)
  select (public.submit_my_request('mission','مأمورية إدارية','تسليم مستندات رسمية للجهة',
    '{"startDate":"2026-09-01","endDate":"2026-09-02","location":"مقر الجهة","startTime":"10:00","endTime":"14:30"}'::jsonb)).id, 'mission'
$$, 'تقديم مأمورية بوقت مخطط صحيح ينجح');

select throws_ok($$
  select public.submit_my_request('mission','مأمورية خاطئة','سبب مقبول للتقديم',
    '{"startDate":"2026-09-03","endDate":"2026-09-03","location":"جهة","startTime":"9:00"}'::jsonb)
$$, '22023', null, 'startTime "9:00" مرفوض — يجب HH:MM');

select throws_ok($$
  select public.submit_my_request('mission','مأمورية خاطئة','سبب مقبول للتقديم',
    '{"startDate":"2026-09-03","endDate":"2026-09-03","location":"جهة","endTime":"14:5"}'::jsonb)
$$, '22023', null, 'endTime غير صالح (ليس HH:MM) مرفوض');

select is(
  (select payload->>'startTime' from public.requests r
   join pg_temp.me_req_ids t on t.request_id = r.id where t.rtype='mission'),
  '10:00', 'payload يحتفظ بوقت البدء المخطط HH:MM');

-- =====================================================================
-- البدء قبل الاعتماد مرفوض.
-- =====================================================================
select throws_ok($$
  select public.start_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'))
$$, '22023', null, 'البدء قبل اعتماد الطلب مرفوض');

-- =====================================================================
-- اعتماد المدير المباشر ثم البدء.
-- =====================================================================
do $approve$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000004', true);
  perform public.decide_request((select request_id from pg_temp.me_req_ids where rtype='mission'), 'approve', 'موافقة');
end $approve$;

select is(
  (select status from public.requests r join pg_temp.me_req_ids t on t.request_id=r.id where t.rtype='mission'),
  'approved', 'الطلب أصبح معتمدًا بعد موافقة المدير');

do $start$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
  perform public.start_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'));
end $start$;

select is(
  (select status from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission'),
  'in_progress', 'حالة التنفيذ in_progress بعد البدء');

select throws_ok($$
  select public.start_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'))
$$, '23505', null, 'البدء المزدوج مرفوض (قيود request_id الفريد)');

-- =====================================================================
-- الإنهاء: التقرير إلزامي ≥3 أحرف، والمدة الفعلية ≥1 دقيقة.
-- =====================================================================
select throws_ok($$
  select public.end_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'), 'اب')
$$, '22023', null, 'التقرير الأقصر من 3 أحرف مرفوض');

do $end$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
  perform public.end_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'),
    'تم تسليم المستندات واستلام الإفادة', 'successful');
end $end$;

select is(
  (select status from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission'),
  'completed', 'حالة التنفيذ completed بعد الإنهاء بالتقرير');

select ok(
  (select me.actual_minutes from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission') is not null
  and (select me.actual_minutes from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission') >= 1,
  'المدة الفعلية محسوبة وغير ملزمة (≥ 1 دقيقة)');

select is(
  (select me.report from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission'),
  'تم تسليم المستندات واستلام الإفادة', 'التقرير محفوظ كما أُدخل');

select is(
  (select me.outcome from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='mission'),
  'successful', 'النتيجة محفوظة');

select throws_ok($$
  select public.end_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'), 'تقرير مكرر')
$$, '22023', null, 'الإنهاء المزدوج مرفوض');

-- =====================================================================
-- الدخيل (موظف خارج الفريق) لا يملك صلاحية البدء أو الإنهاء.
-- =====================================================================
do $set_out$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000006","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000006', true);
end $set_out$;

select throws_ok($$
  select public.start_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'))
$$, '42501', null, 'الدخيل لا يبدأ مأمورية غيره');

select throws_ok($$
  select public.end_my_mission((select request_id from pg_temp.me_req_ids where rtype='mission'), 'تقرير دخيل')
$$, '42501', null, 'الدخيل لا ينهي مأمورية غيره');

-- =====================================================================
-- وصول missionExecution في get_request_inbox و get_mobile_request_detail.
-- =====================================================================
do $set_emp2$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
end $set_emp2$;

select ok(
  (select count(*) > 0
   from public.get_request_inbox(100) b, jsonb_array_elements(b) item
   where item->>'id' = (select request_id::text from pg_temp.me_req_ids where rtype='mission')
     and item->'missionExecution'->>'status' = 'completed'),
  'get_request_inbox يرفق missionExecution بحالة completed');

select is(
  (select public.get_mobile_request_detail((select request_id from pg_temp.me_req_ids where rtype='mission'))
     -> 'missionExecution' ->> 'status'),
  'completed', 'get_mobile_request_detail يرفق missionExecution');

-- =====================================================================
-- الأمان: anon ممنوع، authenticated مسموح، وRLS مفعّل.
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon','public.start_my_mission(uuid)','EXECUTE'),
  false, 'anon لا ينفّذ start_my_mission (أُلغي التنفيذ)');
select is(pg_catalog.has_function_privilege('authenticated','public.start_my_mission(uuid)','EXECUTE'),
  true, 'authenticated ينفّذ start_my_mission');
select ok(
  (select relrowsecurity from pg_class where relname='mission_executions'),
  'RLS مفعّل على mission_executions');

-- =====================================================================
-- القافلة (convoy) تُدير التنفيذ نفسه.
-- =====================================================================
do $set_emp3$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
  insert into pg_temp.me_req_ids(request_id, rtype)
  select (public.submit_my_request('convoy','قافلة طبية','توزيع مساعدات إنسانية للقرية',
    '{"startDate":"2026-09-05","endDate":"2026-09-05","location":"قرية النور","startTime":"08:00"}'::jsonb)).id, 'convoy';
end $set_emp3$;

do $convoy_approve$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000004', true);
  perform public.decide_request((select request_id from pg_temp.me_req_ids where rtype='convoy'), 'approve', 'موافقة القافلة');
end $convoy_approve$;

do $convoy$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a1080000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a1080000-0000-4000-8000-000000000005', true);
  perform public.start_my_mission((select request_id from pg_temp.me_req_ids where rtype='convoy'));
  perform public.end_my_mission((select request_id from pg_temp.me_req_ids where rtype='convoy'), 'اكتملت القافلة بنجاح');
end $convoy$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.me_req_ids t on t.request_id=me.request_id where t.rtype='convoy'),
  'completed', 'القافلة اكتملت عبر نفس مسار التنفيذ');

select * from finish();
rollback;
