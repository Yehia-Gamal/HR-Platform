-- =====================================================================
-- 0526: تحصين سير موافقات مشاريع الجمعية (migration 0526) + 0525
-- ---------------------------------------------------------------------
-- يثبت إغلاق ثغرة P0 التي أدخلتها 0518:
--   • projects_insert_auth ... with check (true)
--   • projects_owner_update بلا قيد على الحالة أو أعمدة الاعتماد
--   كانتا تسمحان لأي موظف باعتماد مشروعه بنفسه عبر PostgREST المباشر،
--   متجاوزاً فحص current_is_full_access() داخل approve_project().
--
-- ويثبت كذلك:
--   • إعادة تثبيت search_path على دوال SECURITY DEFINER (أزالتها 0522)
--   • إعادة STABLE إلى get_association_projects
--   • عدّادات الخطوات في get_association_project_detail (يفرضها عقد Zod)
--   • تفويض create_association_project_admin (كانت بلا أي فحص)
--   • 0525: العارضة الرجعية لا تُعتمد ذاتياً
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(32);

-- =====================================================================
-- Fixture: كيان + إدارة + وظيفة + مسؤول full-access + موظف عادي + مشروع
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f5240000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f5240000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f5240000-0000-4000-8000-000000000003';
  v_admin  uuid := 'f5240000-0000-4000-8000-000000000011';
  v_emp    uuid := 'f5240000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f5240000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f5240000-0000-4000-8000-000000000022';
  v_proj   uuid := 'f5240000-0000-4000-8000-000000000031';
  v_role   uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0524', 'كيان 0524');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0524', 'إدارة 0524');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0524', 'وظيفة 0524');

  insert into auth.users(id, email, aud, role)
    values
    (v_user_a, 'admin-0524@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0524@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
    values
    (v_admin, v_user_a, 'E-0524-A', 'مسؤول 0524', v_dept, v_jt, 'active', true, current_date - 500, '+201000000524'),
    (v_emp,   v_user_e, 'E-0524-B', 'موظف 0524',  v_dept, v_jt, 'active', true, current_date - 300, '+201000000525');

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_a, v_admin, 'active'),
    (v_user_e, v_emp,   'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0524', 'أدمن 0524', 'Admin 0524', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0524';
  insert into public.user_roles(user_id, role_id)
    values (v_user_a, v_role)
    on conflict do nothing;

  -- مشروع مملوك للموظف العادي وحالته draft
  insert into public.association_projects(
    id, code, name, description, department_id, owner_employee_id,
    status, approval_status, priority, progress)
    values (v_proj, 'PRJ-0524', 'مشروع 0524', 'وصف', v_dept, v_emp,
            'planned', 'draft', 'medium', 0);

  insert into public.association_project_steps(project_id, title, sort_order, status)
    values (v_proj, 'خطوة منجزة', 1, 'done'),
           (v_proj, 'خطوة معلقة', 2, 'pending');
end $fixture$;

-- =====================================================================
-- 1) البنية: الجداول + RLS مفعّل
-- =====================================================================
select has_table('public', 'association_projects', 'جدول association_projects موجود');

select ok((select relrowsecurity from pg_class where relname = 'association_projects'),
  'RLS مفعّل على association_projects');
select ok((select relrowsecurity from pg_class where relname = 'association_project_steps'),
  'RLS مفعّل على association_project_steps');
select ok((select relrowsecurity from pg_class where relname = 'association_project_updates'),
  'RLS مفعّل على association_project_updates');

-- =====================================================================
-- 2) P0: سياسات الكتابة المباشرة التي أدخلتها 0518 محذوفة
-- =====================================================================
select ok(not exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_projects'
    and policyname = 'projects_insert_auth'),
  'P0: projects_insert_auth (with check true) محذوفة');

select ok(not exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_projects'
    and policyname = 'projects_owner_update'),
  'P0: projects_owner_update (بلا قيد حالة) محذوفة');

select ok(not exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_project_updates'
    and policyname = 'updates_owner_insert'),
  'P0: updates_owner_insert محذوفة');

select ok(not exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_project_steps'
    and policyname in ('steps_owner_insert','steps_owner_update','steps_owner_delete')),
  'P0: سياسات كتابة الخطوات المباشرة محذوفة');

-- القراءة تبقى متاحة للمالك، وfull-access يبقى كاملاً
select ok(exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_projects'
    and policyname = 'projects_owner_read'),
  'قراءة المالك باقية (projects_owner_read)');

select ok(exists(
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'association_projects'
    and policyname = 'projects_full_access'),
  'سياسة full-access باقية');

-- =====================================================================
-- 3) تحصين دوال SECURITY DEFINER: search_path مثبّت (أزالته 0522)
-- =====================================================================
select ok(
  (select proconfig::text like '%search_path%'
     from pg_proc where oid = 'public.get_association_projects()'::regprocedure),
  'get_association_projects: search_path مثبّت');

select ok(
  (select proconfig::text like '%search_path%'
     from pg_proc where oid = 'public.get_association_project_detail(uuid)'::regprocedure),
  'get_association_project_detail: search_path مثبّت');

select ok(
  (select proconfig::text like '%search_path%'
     from pg_proc
     where oid = 'public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date)'::regprocedure),
  'create_association_project_admin: search_path مثبّت');

-- STABLE أُعيدت بعد أن أسقطتها 0521/0522
select is(
  (select provolatile::text from pg_proc where oid = 'public.get_association_projects()'::regprocedure),
  's', 'get_association_projects: STABLE');

-- =====================================================================
-- 4) صلاحيات التنفيذ: anon ممنوع
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon', 'public.get_association_projects()', 'EXECUTE'),
  false, 'anon لا ينفّذ get_association_projects');
select is(pg_catalog.has_function_privilege('anon', 'public.get_association_project_detail(uuid)', 'EXECUTE'),
  false, 'anon لا ينفّذ get_association_project_detail');

-- =====================================================================
-- 5) وقت التشغيل: الموظف العادي لا يستطيع الاعتماد الذاتي
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5240000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f5240000-0000-4000-8000-000000000022', true);
end $$;
set local role authenticated;

-- يقرأ مشروعه
select is((select count(*)::int from public.association_projects
           where id = 'f5240000-0000-4000-8000-000000000031'), 1,
  'المالك يقرأ مشروعه');

-- P0 الأساسي: تحديث مباشر لحالة الاعتماد لا يمرّ (لا سياسة UPDATE)
update public.association_projects
  set approval_status = 'approved'
  where id = 'f5240000-0000-4000-8000-000000000031';

reset role;
select is(
  (select approval_status from public.association_projects
    where id = 'f5240000-0000-4000-8000-000000000031'),
  'draft',
  'P0: المالك لا يستطيع ضبط approval_status=approved مباشرة');

-- إدراج مباشر لمشروع مُعتمد مسبقاً مرفوض
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5240000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f5240000-0000-4000-8000-000000000022', true);
end $$;
set local role authenticated;

select throws_ok($$
  insert into public.association_projects(
    code, name, department_id, owner_employee_id, status, approval_status, priority, progress)
  values ('PRJ-0524-X', 'مشروع مُهرَّب', 'f5240000-0000-4000-8000-000000000002',
          'f5240000-0000-4000-8000-000000000012', 'planned', 'approved', 'medium', 0)
$$, '42501',
  'P0: إدراج مباشر لمشروع approved مرفوض بـ RLS');

-- approve_project لغير full-access مرفوضة
select throws_ok($$
  select public.approve_project('f5240000-0000-4000-8000-000000000031')
$$, '42501',
  'approve_project لغير full-access مرفوضة');

-- create_association_project_admin: إسناد لموظف آخر مرفوض
select throws_ok($$
  select public.create_association_project_admin(
    'PRJ-0524-Y', 'مشروع باسم غيري', 'وصف',
    'f5240000-0000-4000-8000-000000000002',
    'f5240000-0000-4000-8000-000000000011',
    'medium', null, null)
$$, '42501',
  'create_association_project_admin: لا يملك الإسناد لموظف آخر');

-- create_association_project_admin: لنفسه ينجح ويبدأ draft
select lives_ok($$
  select public.create_association_project_admin(
    'PRJ-0524-Z', 'مشروعي', 'وصف',
    'f5240000-0000-4000-8000-000000000002',
    'f5240000-0000-4000-8000-000000000012',
    'medium', null, null)
$$, 'create_association_project_admin: الموظف ينشئ مشروعه');

reset role;
select is(
  (select approval_status from public.association_projects where code = 'PRJ-0524-Z'),
  'draft',
  'المشروع الجديد يبدأ draft لا approved');

-- =====================================================================
-- 6) عقد لوحة التفاصيل: عدّادات الخطوات موجودة (كان يكسر Zod)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5240000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f5240000-0000-4000-8000-000000000021', true);
end $$;

select ok(
  (public.get_association_project_detail('f5240000-0000-4000-8000-000000000031')
    -> 'project') ? 'totalSteps',
  'تفاصيل المشروع تُرجع totalSteps');

select ok(
  (public.get_association_project_detail('f5240000-0000-4000-8000-000000000031')
    -> 'project') ?& array['totalSteps','completedSteps','remainingSteps','blockedSteps'],
  'تفاصيل المشروع تُرجع عدّادات الخطوات الأربعة');

select is(
  ((public.get_association_project_detail('f5240000-0000-4000-8000-000000000031')
    -> 'project' ->> 'completedSteps'))::int,
  1, 'completedSteps يحسب الخطوات المنجزة فعلاً');

-- =====================================================================
-- 7) انحدار 42803 — ORDER BY يجب أن يبقى داخل jsonb_agg
--    طاردت 0521→0528 هذا العطل تحت عنوان «ذاكرة مخطط PostgREST».
--    استدعاء فعلي للدالة هو الحارس: `order by` خارج التجميعة يرفع 42803.
-- =====================================================================
select lives_ok(
  $rt$ select public.get_association_projects() $rt$,
  'get_association_projects تُنفَّذ بلا 42803 (ORDER BY داخل jsonb_agg)');

select ok(
  jsonb_typeof(public.get_association_projects() -> 'projects') = 'array',
  'get_association_projects تُرجع مصفوفة projects فعلية');

select lives_ok(
  $rt$ select public.get_association_project_detail('f5240000-0000-4000-8000-000000000031') $rt$,
  'get_association_project_detail تُنفَّذ بلا أخطاء وقت تشغيل');

-- =====================================================================
-- 8) 0525: العارضة الرجعية لا تُعتمد ذاتياً
-- =====================================================================
select ok(
  (select prosrc from pg_proc
    where oid = 'public.submit_my_request(text,text,text,jsonb,uuid)'::regprocedure)
    like '%v_leave_type = ''casual'' and v_start_date >= v_today%',
  '0525: التنفيذ المباشر للعارضة مقيّد بـ start_date >= اليوم');

select ok(
  (select prosrc from pg_proc
    where oid = 'public.submit_my_request(text,text,text,jsonb,uuid)'::regprocedure)
    not like '%''immediate'', (v_leave_type = ''casual''))%',
  '0525: علم immediate لم يعد يُمنح للعارضة الرجعية');

-- الرجعية نفسها تبقى مسموحة داخل الشهر الحالي (سلوك 0520 المطلوب)
select ok(
  (select prosrc from pg_proc
    where oid = 'public.submit_my_request(text,text,text,jsonb,uuid)'::regprocedure)
    like '%لا يمكن تقديم إجازة عن أشهر سابقة%',
  '0525: حارس الأشهر السابقة باقٍ (الرجعية داخل الشهر فقط)');

select * from finish();
rollback;
