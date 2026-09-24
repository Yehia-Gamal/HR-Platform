-- =====================================================================
-- 0553: مشاريع الجمعية — سير عمل الإدارات + لمبة التنبيه الثلاثية
-- ---------------------------------------------------------------------
-- يثبت:
--   • نطاق الإدارة: الزميل في نفس الإدارة ومدير الإدارة يديران المشروع،
--     والموظف من إدارة أخرى لا يراه ولا يلمسه.
--   • الإنشاء لإدارتك فقط؛ الاعتماد للمدير التنفيذي فقط (+ إشعارات).
--   • اللمبة: active / halted / critical / completed / stale.
--   • التقدم يُشتق من الخطوات + completed_at + planned→active تلقائياً.
--   • كرون التعثّر يُشعر مرة واحدة فقط لكل انقطاع.
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(45);

-- =====================================================================
-- Fixture
--   A: إدارة المشروع — admin (full-access) + emp1 (مالك) + emp2 (زميل)
--   B: إدارة أخرى — emp3 (غريب)، ومديرها emp4 (خارج كل الإدارات)
-- =====================================================================
do $fixture$
declare
  v_le    uuid := 'f5530000-0000-4000-8000-000000000001';
  v_deptA uuid := 'f5530000-0000-4000-8000-000000000002';
  v_deptB uuid := 'f5530000-0000-4000-8000-000000000003';
  v_jt    uuid := 'f5530000-0000-4000-8000-000000000004';
  v_role  uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0553', 'كيان 0553');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_deptA, v_le, 'D-0553-A', 'إدارة أ'),
           (v_deptB, v_le, 'D-0553-B', 'إدارة ب');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0553', 'وظيفة 0553');

  insert into auth.users(id, email, aud, role) values
    ('f5530000-0000-4000-8000-000000000020', 'admin-0553@test.local', 'authenticated', 'authenticated'),
    ('f5530000-0000-4000-8000-000000000021', 'emp1-0553@test.local',  'authenticated', 'authenticated'),
    ('f5530000-0000-4000-8000-000000000022', 'emp2-0553@test.local',  'authenticated', 'authenticated'),
    ('f5530000-0000-4000-8000-000000000023', 'emp3-0553@test.local',  'authenticated', 'authenticated'),
    ('f5530000-0000-4000-8000-000000000024', 'emp4-0553@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    ('f5530000-0000-4000-8000-000000000010', 'f5530000-0000-4000-8000-000000000020', 'E-0553-0', 'مدير تنفيذي 0553', v_deptA, v_jt, 'active', true, current_date - 900, '+201000005530'),
    ('f5530000-0000-4000-8000-000000000011', 'f5530000-0000-4000-8000-000000000021', 'E-0553-1', 'مالك 0553',        v_deptA, v_jt, 'active', true, current_date - 500, '+201000005531'),
    ('f5530000-0000-4000-8000-000000000012', 'f5530000-0000-4000-8000-000000000022', 'E-0553-2', 'زميل 0553',        v_deptA, v_jt, 'active', true, current_date - 400, '+201000005532'),
    ('f5530000-0000-4000-8000-000000000013', 'f5530000-0000-4000-8000-000000000023', 'E-0553-3', 'غريب 0553',        v_deptB, v_jt, 'active', true, current_date - 300, '+201000005533'),
    ('f5530000-0000-4000-8000-000000000014', 'f5530000-0000-4000-8000-000000000024', 'E-0553-4', 'مدير إدارة ب',     null,    v_jt, 'active', true, current_date - 200, '+201000005534');

  update public.departments set manager_id = 'f5530000-0000-4000-8000-000000000014' where id = v_deptB;

  insert into public.profiles(id, employee_id, status) values
    ('f5530000-0000-4000-8000-000000000020', 'f5530000-0000-4000-8000-000000000010', 'active'),
    ('f5530000-0000-4000-8000-000000000021', 'f5530000-0000-4000-8000-000000000011', 'active'),
    ('f5530000-0000-4000-8000-000000000022', 'f5530000-0000-4000-8000-000000000012', 'active'),
    ('f5530000-0000-4000-8000-000000000023', 'f5530000-0000-4000-8000-000000000013', 'active'),
    ('f5530000-0000-4000-8000-000000000024', 'f5530000-0000-4000-8000-000000000014', 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0553', 'أدمن 0553', 'Admin 0553', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0553';
  insert into public.user_roles(user_id, role_id)
    values ('f5530000-0000-4000-8000-000000000020', v_role) on conflict do nothing;
end $fixture$;

-- مبدّل الهوية: يضبط claims الـ JWT للمستخدم المطلوب (يُستدعى دائماً قبل set local role)
create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- 1) البنية والصلاحيات
-- =====================================================================
select has_table('public', 'association_project_settings', 'جدول إعدادات اللمبة موجود');
select is((select warning_days from public.association_project_settings), 7,  'حد التنبيه الافتراضي 7 أيام');
select is((select critical_days from public.association_project_settings), 14, 'حد التدخل الافتراضي 14 يوماً');
select has_column('public', 'association_projects', 'last_activity_at', 'عمود last_activity_at موجود');

select is(has_function_privilege('authenticated', 'public._association_project_can_manage(uuid)', 'EXECUTE'),
  false, 'الدوال المساعدة الداخلية غير مكشوفة للعميل');
select is(has_function_privilege('authenticated', 'public.notify_stalled_association_projects()', 'EXECUTE'),
  false, 'كرون التعثّر غير قابل للاستدعاء من العميل');
select is(has_function_privilege('anon', 'public.set_project_step_status(uuid,text)', 'EXECUTE'),
  false, 'anon لا ينفّذ set_project_step_status');
select is(has_function_privilege('authenticated', 'public.set_project_step_status(uuid,text)', 'EXECUTE'),
  true, 'authenticated ينفّذ set_project_step_status');
select is(
  (select provolatile::text from pg_proc where oid = 'public.get_association_projects()'::regprocedure),
  's', 'get_association_projects: STABLE');

-- =====================================================================
-- 2) قاعدة اللمبة
-- =====================================================================
select is(public._association_project_led('active',   'approved', now() - interval '2 days',  7, 14), 'active',    'نشاط حديث = أخضر');
select is(public._association_project_led('active',   'approved', now() - interval '8 days',  7, 14), 'halted',    '8 أيام بلا نشاط = أحمر ثابت');
select is(public._association_project_led('active',   'approved', now() - interval '15 days', 7, 14), 'critical',  '15 يوماً بلا نشاط = أحمر يومض');
select is(public._association_project_led('on_hold',  'approved', now(),                      7, 14), 'halted',    'متوقف صراحةً = أحمر ثابت');
select is(public._association_project_led('active',   'approved', null,                       7, 14), 'critical',  'معتمد بلا أي نشاط = يحتاج تدخل');
select is(public._association_project_led('completed','approved', now() - interval '90 days', 7, 14), 'completed', 'المكتمل لا يُحسب متعثّراً');
select is(public._association_project_led('cancelled','approved', now(),                      7, 14), 'stale',     'الملغى مطفأ');
select is(public._association_project_led('planned',  'pending_approval', null,               7, 14), 'pending',   'بانتظار الاعتماد');

-- =====================================================================
-- 3) الإنشاء: لإدارتك فقط
-- =====================================================================
select pg_temp.act_as('f5530000-0000-4000-8000-000000000021');
set local role authenticated;

select lives_ok($$
  select public.create_association_project_admin('PRJ-0553-A', 'مشروع إدارة أ', 'وصف',
    'f5530000-0000-4000-8000-000000000002', null, 'high', null, null)
$$, 'الموظف ينشئ مشروعاً لإدارته');

select throws_ok($$
  select public.create_association_project_admin('PRJ-0553-X', 'مشروع لإدارة غيري', null,
    'f5530000-0000-4000-8000-000000000003', null, 'medium', null, null)
$$, '42501', null, 'لا ينشئ مشروعاً لإدارة أخرى');

select throws_ok($$
  select public.create_association_project_admin('PRJ-0553-A', 'كود مكرر', null,
    'f5530000-0000-4000-8000-000000000002', null, 'medium', null, null)
$$, '23505', null, 'الكود المكرر يُرفض برسالة واضحة');

reset role;
select is((select approval_status from public.association_projects where code = 'PRJ-0553-A'),
  'draft', 'مشروع الإدارة يبدأ مسودة');

-- مدير الإدارة ينشئ لإدارته ولو لم يكن عضواً فيها
select pg_temp.act_as('f5530000-0000-4000-8000-000000000024');
set local role authenticated;
select lives_ok($$
  select public.create_association_project_admin(null, 'مشروع مدير ب', null,
    'f5530000-0000-4000-8000-000000000003', null, 'low', null, null)
$$, 'مدير الإدارة ينشئ مشروعاً لإدارته (بكود تلقائي)');
reset role;
select ok((select code like 'PRJ-%' from public.association_projects where name = 'مشروع مدير ب'),
  'الكود التلقائي يُولَّد عند تركه فارغاً');

-- =====================================================================
-- 4) نطاق الإدارة: الزميل يدير، الغريب لا يرى
-- =====================================================================
select pg_temp.act_as('f5530000-0000-4000-8000-000000000022');
set local role authenticated;

select lives_ok($$
  select public.upsert_project_step_admin(
    (select id from public.association_projects where code = 'PRJ-0553-A'),
    null, 'دراسة', null, null, 'pending', null, null)
$$, 'الزميل في نفس الإدارة يضيف خطوة');

select lives_ok($$
  select public.upsert_project_step_admin(
    (select id from public.association_projects where code = 'PRJ-0553-A'),
    null, 'تنفيذ', null, null, 'pending', null, null)
$$, 'الزميل يضيف خطوة ثانية');

select lives_ok($$ select public.submit_project_for_approval(
    (select id from public.association_projects where code = 'PRJ-0553-A')) $$,
  'الزميل يرسل مشروع الإدارة للاعتماد');

select throws_ok($$ select public.approve_project(
    (select id from public.association_projects where code = 'PRJ-0553-A')) $$,
  '42501', null, 'الإدارة لا تعتمد مشروعها بنفسها');

reset role;
select pg_temp.act_as('f5530000-0000-4000-8000-000000000023');
set local role authenticated;

select ok(not exists(
    select 1 from jsonb_array_elements(public.get_association_projects() -> 'projects') x
    where x ->> 'code' = 'PRJ-0553-A'),
  'موظف إدارة أخرى لا يرى المشروع في القائمة');

select throws_ok($$ select public.get_association_project_detail(
    (select id from public.association_projects where code = 'PRJ-0553-A')) $$,
  '42501', null, 'موظف إدارة أخرى لا يفتح التفاصيل');

select throws_ok($$
  select public.upsert_project_step_admin(
    (select id from public.association_projects where code = 'PRJ-0553-A'),
    null, 'خطوة دخيلة', null, null, 'pending', null, null)
$$, '42501', null, 'موظف إدارة أخرى لا يضيف خطوات');

reset role;
select ok(exists(
    select 1 from public.notifications
    where recipient_user_id = 'f5530000-0000-4000-8000-000000000020'
      and entity_type = 'association_project' and metadata ->> 'kind' = 'project_submitted'),
  'المدير التنفيذي يُشعَر بطلب الاعتماد');

-- =====================================================================
-- 5) الاعتماد + التقدم المشتق من الخطوات
-- =====================================================================
select pg_temp.act_as('f5530000-0000-4000-8000-000000000020');
set local role authenticated;
select lives_ok($$ select public.approve_project(
    (select id from public.association_projects where code = 'PRJ-0553-A')) $$,
  'المدير التنفيذي يعتمد المشروع');

reset role;
select pg_temp.act_as('f5530000-0000-4000-8000-000000000021');
set local role authenticated;
select lives_ok($$ select public.set_project_step_status(
    (select s.id from public.association_project_steps s
       join public.association_projects p on p.id = s.project_id
      where p.code = 'PRJ-0553-A' and s.title = 'دراسة'), 'done') $$,
  'المالك يعلّم خطوة كمكتملة');
reset role;

select is((select progress from public.association_projects where code = 'PRJ-0553-A'),
  50.00::numeric, 'التقدم = 1 من 2 خطوة = 50%');
select is((select status from public.association_projects where code = 'PRJ-0553-A'),
  'active', 'بدء التنفيذ يحوّل المشروع من مخطط إلى نشط');
select ok((select completed_at is not null from public.association_project_steps where title = 'دراسة'
             and project_id = (select id from public.association_projects where code = 'PRJ-0553-A')),
  'completed_at يُسجَّل عند اكتمال الخطوة');
select ok(exists(
    select 1 from public.notifications
    where recipient_user_id = 'f5530000-0000-4000-8000-000000000021'
      and metadata ->> 'kind' = 'project_approved'),
  'المالك يُشعَر بالاعتماد');

-- =====================================================================
-- 6) التعثّر: اللمبة + كرون الإشعار مرة واحدة
-- =====================================================================
update public.association_projects set last_activity_at = now() - interval '20 days'
 where code = 'PRJ-0553-A';

select pg_temp.act_as('f5530000-0000-4000-8000-000000000020');
select is(
  (select x ->> 'ledStatus' from jsonb_array_elements(public.get_association_projects() -> 'projects') x
    where x ->> 'code' = 'PRJ-0553-A'),
  'critical', '20 يوماً بلا نشاط = يحتاج تدخل المدير التنفيذي');

select ok(public.notify_stalled_association_projects() >= 1, 'الكرون يلتقط المشروع المتعثّر');
select is(public.notify_stalled_association_projects(), 0, 'لا يتكرر الإشعار لنفس الانقطاع');

-- تحديث من الإدارة يُطفئ الأحمر
select pg_temp.act_as('f5530000-0000-4000-8000-000000000022');
set local role authenticated;
select lives_ok($$ select public.add_project_update_admin(
    (select id from public.association_projects where code = 'PRJ-0553-A'), 'استُؤنف العمل', null, null) $$,
  'الزميل يضيف تحديثاً');
select is(
  (select x ->> 'ledStatus' from jsonb_array_elements(public.get_association_projects() -> 'projects') x
    where x ->> 'code' = 'PRJ-0553-A'),
  'active', 'التحديث يعيد اللمبة للأخضر');

-- =====================================================================
-- 7) الإعدادات والحذف
-- =====================================================================
select throws_ok($$ select public.set_association_project_settings(3, 5) $$,
  '42501', null, 'الإدارة لا تغيّر حدود اللمبة');
select throws_ok($$ select public.delete_association_project(
    (select id from public.association_projects where code = 'PRJ-0553-A')) $$,
  '42501', null, 'الإدارة لا تحذف مشروعاً معتمداً');

reset role;
select pg_temp.act_as('f5530000-0000-4000-8000-000000000020');
set local role authenticated;
select throws_ok($$ select public.set_association_project_settings(5, 5) $$,
  '22023', null, 'حد التدخل يجب أن يتجاوز حد التنبيه');

reset role;

select * from finish();
rollback;
