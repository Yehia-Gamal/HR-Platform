-- =====================================================================
-- 0645: مشاريع الجمعية — فريق المشروع (قائد + أعضاء) وإدارات متعددة
-- ---------------------------------------------------------------------
-- يثبت:
--   • مشروع بلا إدارة: فريق أشخاص بقائد واحد، والمنشئ ينضم تلقائياً.
--   • قائد واحد فقط دائماً، وowner_employee_id = القائد.
--   • النطاق: الفريق + موظفو الإدارات المرتبطة يرون ويديرون، والغريب لا.
--   • تعديل الفريق للقائد/المنشئ/مدير إدارة مرتبطة فقط، والعضو لا.
--   • بعد الاعتماد: الاسم والوصف مقفلان، والفريق قابل للتعديل.
--   • المكلَّف من نطاق المشروع فقط ويُشعَر، ويُفك تكليفه عند خروجه.
--   • الدالة القديمة create_association_project_admin تكتب الفريق والإدارة.
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(48);

-- =====================================================================
-- Fixture
--   A: emp1 + emp2 ، B: emp3 ومديرها emp4 (بلا إدارة) ، C: emp5
--   admin: full-access
-- =====================================================================
do $fixture$
declare
  v_le    uuid := 'f6440000-0000-4000-8000-000000000001';
  v_jt    uuid := 'f6440000-0000-4000-8000-000000000004';
  v_role  uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0645', 'كيان 0645');
  insert into public.departments(id, legal_entity_id, code, name) values
    ('f6440000-0000-4000-8000-00000000000a', v_le, 'D-0645-A', 'إدارة 0645 أ'),
    ('f6440000-0000-4000-8000-00000000000b', v_le, 'D-0645-B', 'إدارة 0645 ب'),
    ('f6440000-0000-4000-8000-00000000000c', v_le, 'D-0645-C', 'إدارة 0645 ج');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0645', 'وظيفة 0645');

  insert into auth.users(id, email, aud, role) values
    ('f6440000-0000-4000-8000-000000000020', 'admin-0645@test.local', 'authenticated', 'authenticated'),
    ('f6440000-0000-4000-8000-000000000021', 'emp1-0645@test.local',  'authenticated', 'authenticated'),
    ('f6440000-0000-4000-8000-000000000022', 'emp2-0645@test.local',  'authenticated', 'authenticated'),
    ('f6440000-0000-4000-8000-000000000023', 'emp3-0645@test.local',  'authenticated', 'authenticated'),
    ('f6440000-0000-4000-8000-000000000024', 'emp4-0645@test.local',  'authenticated', 'authenticated'),
    ('f6440000-0000-4000-8000-000000000025', 'emp5-0645@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    ('f6440000-0000-4000-8000-000000000010', 'f6440000-0000-4000-8000-000000000020', 'E-0645-0', 'مدير تنفيذي 0645', 'f6440000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 900, '+201000006450'),
    ('f6440000-0000-4000-8000-000000000011', 'f6440000-0000-4000-8000-000000000021', 'E-0645-1', 'أحمد 0645',  'f6440000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 500, '+201000006451'),
    ('f6440000-0000-4000-8000-000000000012', 'f6440000-0000-4000-8000-000000000022', 'E-0645-2', 'بسمة 0645',  'f6440000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 400, '+201000006452'),
    ('f6440000-0000-4000-8000-000000000013', 'f6440000-0000-4000-8000-000000000023', 'E-0645-3', 'جمال 0645',  'f6440000-0000-4000-8000-00000000000b', v_jt, 'active', true, current_date - 300, '+201000006453'),
    ('f6440000-0000-4000-8000-000000000014', 'f6440000-0000-4000-8000-000000000024', 'E-0645-4', 'دينا 0645',  null,                                   v_jt, 'active', true, current_date - 200, '+201000006454'),
    ('f6440000-0000-4000-8000-000000000015', 'f6440000-0000-4000-8000-000000000025', 'E-0645-5', 'هاني 0645',  'f6440000-0000-4000-8000-00000000000c', v_jt, 'active', true, current_date - 100, '+201000006455');

  update public.departments set manager_id = 'f6440000-0000-4000-8000-000000000014'
   where id = 'f6440000-0000-4000-8000-00000000000b';

  insert into public.profiles(id, employee_id, status) values
    ('f6440000-0000-4000-8000-000000000020', 'f6440000-0000-4000-8000-000000000010', 'active'),
    ('f6440000-0000-4000-8000-000000000021', 'f6440000-0000-4000-8000-000000000011', 'active'),
    ('f6440000-0000-4000-8000-000000000022', 'f6440000-0000-4000-8000-000000000012', 'active'),
    ('f6440000-0000-4000-8000-000000000023', 'f6440000-0000-4000-8000-000000000013', 'active'),
    ('f6440000-0000-4000-8000-000000000024', 'f6440000-0000-4000-8000-000000000014', 'active'),
    ('f6440000-0000-4000-8000-000000000025', 'f6440000-0000-4000-8000-000000000015', 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0645', 'أدمن 0645', 'Admin 0645', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0645';
  insert into public.user_roles(user_id, role_id)
    values ('f6440000-0000-4000-8000-000000000020', v_role) on conflict do nothing;
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- المشروع كما يراه المستخدم الحالي في القائمة (null إن لم يره)
create or replace function pg_temp.seen(p_name text) returns jsonb
language sql stable as $f$
  select x from jsonb_array_elements(public.get_association_projects() -> 'projects') x
   where x ->> 'name' = p_name limit 1
$f$;

-- المعرّف يُحفظ في إعداد الجلسة لأن authenticated لا يقرأ الجدول مباشرة.
create or replace function pg_temp.pid(p_name text) returns uuid
language sql stable as $f$
  select nullif(current_setting('t0645.p1', true), '')::uuid
$f$;

-- =====================================================================
-- 1) البنية والصلاحيات
-- =====================================================================
select has_table('public', 'association_project_members', 'جدول فريق المشروع موجود');
select has_table('public', 'association_project_departments', 'جدول إدارات المشروع موجود');
select col_is_null('public', 'association_projects', 'department_id', 'الإدارة لم تعد إجبارية');
select ok(not exists (
    select 1 from public.association_projects p
    where (select count(*) from public.association_project_members m
            where m.project_id = p.id and m.is_leader) <> 1),
  'كل مشروع قائم له قائد واحد بالضبط بعد الترحيل');
select is(has_function_privilege('authenticated', 'public._association_project_set_team(uuid,uuid,uuid[],uuid[])', 'EXECUTE'),
  false, 'مزامنة الفريق داخلية غير مكشوفة');
select is(has_table_privilege('authenticated', 'public.association_project_members', 'SELECT'),
  false, 'جدول الفريق غير مقروء مباشرة للعميل');
select is(has_function_privilege('anon', 'public.save_association_project(uuid,text,text,text,date,date,uuid,uuid[],uuid[],text)', 'EXECUTE'),
  false, 'anon لا ينفّذ save_association_project');
select is(has_function_privilege('authenticated', 'public.get_association_project_pickers()', 'EXECUTE'),
  true, 'authenticated يقرأ قائمة اختيار الفريق');

-- =====================================================================
-- 2) مشروع أشخاص بلا إدارة: جمال (ب) ينشئه بقيادة أحمد وعضوية بسمة
-- =====================================================================
select pg_temp.act_as('f6440000-0000-4000-8000-000000000023');
set local role authenticated;

select lives_ok($$
  select public.save_association_project(null, 'مشروع فريق 0645', 'بلا إدارة', 'high', null, null,
    'f6440000-0000-4000-8000-000000000011',
    array['f6440000-0000-4000-8000-000000000012']::uuid[], '{}'::uuid[])
$$, 'موظف ينشئ مشروعاً بفريق أشخاص بلا أي إدارة');

select throws_ok($$
  select public.save_association_project(null, 'قائد غير موجود', null, 'medium', null, null,
    'f6440000-0000-4000-8000-0000000000ff', '{}'::uuid[], '{}'::uuid[])
$$, '22023', null, 'قائد غير موجود يُرفض');

select is(pg_temp.seen('مشروع فريق 0645') ->> 'myRole', 'member', 'المنشئ يُضاف للفريق تلقائياً');
select is(pg_temp.seen('مشروع فريق 0645') ->> 'leaderName', 'أحمد 0645', 'القائد يظهر في القائمة');
select is(jsonb_array_length(pg_temp.seen('مشروع فريق 0645') -> 'members'), 3, 'الفريق = القائد + بسمة + المنشئ');
select is(pg_temp.seen('مشروع فريق 0645') ->> 'departmentName', null, 'لا إدارة = departmentName فارغ');
select is(pg_temp.seen('مشروع فريق 0645') ->> 'approvalStatus', 'draft', 'مشروع غير المدير التنفيذي يبدأ مسودة');
select ok((pg_temp.seen('مشروع فريق 0645') ->> 'canEdit')::boolean, 'المنشئ يعدّل مشروعه');

reset role;
select set_config('t0645.p1', (select id::text from public.association_projects where name = 'مشروع فريق 0645'), false);
select is((select owner_employee_id from public.association_projects where name = 'مشروع فريق 0645'),
  'f6440000-0000-4000-8000-000000000011'::uuid, 'owner_employee_id = القائد');
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6440000-0000-4000-8000-000000000021'
                     and metadata ->> 'kind' = 'project_team_added' and title = 'أصبحت قائد مشروع'),
  'القائد يُشعَر بقيادته');
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6440000-0000-4000-8000-000000000022'
                     and metadata ->> 'kind' = 'project_team_added'),
  'العضو يُشعَر بإضافته');
select ok(not exists (select 1 from public.notifications
                       where recipient_user_id = 'f6440000-0000-4000-8000-000000000023'
                         and metadata ->> 'kind' = 'project_team_added'),
  'المنشئ لا يُشعَر بما فعله بنفسه');

-- =====================================================================
-- 3) النطاق: هاني (ج) غريب — والعضو لا يعدّل الفريق
-- =====================================================================
select pg_temp.act_as('f6440000-0000-4000-8000-000000000025');
set local role authenticated;
select is(pg_temp.seen('مشروع فريق 0645'), null, 'الغريب لا يرى المشروع');
select throws_ok($$ select public.get_association_project_detail(pg_temp.pid('مشروع فريق 0645')) $$,
  '42501', null, 'الغريب لا يفتح التفاصيل');
reset role;

select pg_temp.act_as('f6440000-0000-4000-8000-000000000022');
set local role authenticated;
select is(pg_temp.seen('مشروع فريق 0645') ->> 'canEdit', 'false', 'العضو لا يعدّل بيانات المشروع');
select lives_ok($$ select public.upsert_project_step_admin(pg_temp.pid('مشروع فريق 0645'),
    null, 'تجهيز', null, null, 'pending', null, null) $$,
  'العضو يضيف خطوات');
select throws_ok($$
  select public.save_association_project(pg_temp.pid('مشروع فريق 0645'), 'مشروع فريق 0645', 'بلا إدارة', 'high', null, null,
    'f6440000-0000-4000-8000-000000000012', '{}'::uuid[], '{}'::uuid[])
$$, '42501', null, 'العضو لا يغيّر القائد ولا الفريق');
reset role;

-- =====================================================================
-- 4) القائد: يربط إدارة ج + يسلّم القيادة لبسمة — قائد واحد دائماً
-- =====================================================================
select pg_temp.act_as('f6440000-0000-4000-8000-000000000021');
set local role authenticated;
select lives_ok($$
  select public.save_association_project(pg_temp.pid('مشروع فريق 0645'), 'مشروع فريق 0645', 'بلا إدارة', 'high', null, null,
    'f6440000-0000-4000-8000-000000000012',
    array['f6440000-0000-4000-8000-000000000011', 'f6440000-0000-4000-8000-000000000013']::uuid[],
    array['f6440000-0000-4000-8000-00000000000c']::uuid[])
$$, 'القائد يسلّم القيادة ويربط إدارة');
reset role;

select is((select count(*)::int from public.association_project_members
            where project_id = pg_temp.pid('مشروع فريق 0645') and is_leader), 1, 'قائد واحد فقط');
select is((select owner_employee_id from public.association_projects where name = 'مشروع فريق 0645'),
  'f6440000-0000-4000-8000-000000000012'::uuid, 'owner_employee_id يتبع القائد الجديد');
select is((select department_id from public.association_projects where name = 'مشروع فريق 0645'),
  'f6440000-0000-4000-8000-00000000000c'::uuid, 'department_id = أول إدارة مرتبطة');

-- موظف الإدارة المرتبطة يرى ويدير — ويُكلَّف
select pg_temp.act_as('f6440000-0000-4000-8000-000000000025');
set local role authenticated;
select is(pg_temp.seen('مشروع فريق 0645') ->> 'myRole', 'dept_staff', 'موظف الإدارة المرتبطة يرى المشروع');
reset role;

select pg_temp.act_as('f6440000-0000-4000-8000-000000000022');
set local role authenticated;
select lives_ok($$ select public.upsert_project_step_admin(pg_temp.pid('مشروع فريق 0645'),
    null, 'توزيع', null, null, 'pending', current_date + 7, 'f6440000-0000-4000-8000-000000000015') $$,
  'التكليف لموظف من إدارة مرتبطة');
select throws_ok($$ select public.upsert_project_step_admin(pg_temp.pid('مشروع فريق 0645'),
    null, 'دخيلة', null, null, 'pending', null, 'f6440000-0000-4000-8000-000000000014') $$,
  '22023', null, 'لا تكليف لموظف خارج نطاق المشروع');
reset role;
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6440000-0000-4000-8000-000000000025'
                     and metadata ->> 'kind' = 'project_step_assigned'),
  'المكلَّف يُشعَر بمهمته');

-- فك الإدارة → يخرج هاني من النطاق وتُفك مهمته غير المنجزة
select pg_temp.act_as('f6440000-0000-4000-8000-000000000022');
set local role authenticated;
select lives_ok($$
  select public.save_association_project(pg_temp.pid('مشروع فريق 0645'), 'مشروع فريق 0645', 'بلا إدارة', 'high', null, null,
    'f6440000-0000-4000-8000-000000000012',
    array['f6440000-0000-4000-8000-000000000011', 'f6440000-0000-4000-8000-000000000013']::uuid[], '{}'::uuid[])
$$, 'القائدة الجديدة تفك ربط الإدارة');
reset role;
select is((select assignee_employee_id from public.association_project_steps
            where project_id = pg_temp.pid('مشروع فريق 0645') and title = 'توزيع'),
  null, 'مهمة من خرج من النطاق تُفك');

-- =====================================================================
-- 5) بعد الاعتماد: الاسم مقفل، الفريق يتعدّل
-- =====================================================================
select pg_temp.act_as('f6440000-0000-4000-8000-000000000021');
set local role authenticated;
select lives_ok($$ select public.submit_project_for_approval(pg_temp.pid('مشروع فريق 0645')) $$,
  'العضو يرسل المشروع للاعتماد');
reset role;

select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6440000-0000-4000-8000-000000000020'
                     and metadata ->> 'kind' = 'project_submitted'
                     and body like '%مشروع فريق 0645%'),
  'المدير التنفيذي يُشعَر بمشروع بلا إدارة');

select pg_temp.act_as('f6440000-0000-4000-8000-000000000020');
set local role authenticated;
select lives_ok($$ select public.approve_project(pg_temp.pid('مشروع فريق 0645')) $$, 'الاعتماد');
reset role;

select pg_temp.act_as('f6440000-0000-4000-8000-000000000022');
set local role authenticated;
select throws_ok($$
  select public.save_association_project(pg_temp.pid('مشروع فريق 0645'), 'اسم جديد', 'بلا إدارة', 'high', null, null,
    'f6440000-0000-4000-8000-000000000012', '{}'::uuid[], '{}'::uuid[])
$$, '42501', null, 'الاسم مقفل بعد الاعتماد');
select lives_ok($$
  select public.save_association_project(pg_temp.pid('مشروع فريق 0645'), 'مشروع فريق 0645', 'بلا إدارة', 'critical', null, current_date + 30,
    'f6440000-0000-4000-8000-000000000012',
    array['f6440000-0000-4000-8000-000000000011']::uuid[], '{}'::uuid[])
$$, 'الفريق والأولوية والموعد قابلة للتعديل بعد الاعتماد');
select throws_ok($$ select public.delete_association_project(pg_temp.pid('مشروع فريق 0645')) $$,
  '42501', null, 'القائد لا يحذف مشروعاً معتمداً');
reset role;

-- جمال (المنشئ) أُخرج من الفريق لكنه ما زال يرى المشروع
select pg_temp.act_as('f6440000-0000-4000-8000-000000000023');
set local role authenticated;
select is(pg_temp.seen('مشروع فريق 0645') ->> 'myRole', 'creator', 'المنشئ يبقى يرى مشروعه بعد خروجه من الفريق');
reset role;

-- =====================================================================
-- 6) الدالة القديمة + التعثّر + قائمة الاختيار
-- =====================================================================
select pg_temp.act_as('f6440000-0000-4000-8000-000000000024');
set local role authenticated;
select lives_ok($$ select public.create_association_project_admin(null, 'مشروع قديم 0645', null,
    'f6440000-0000-4000-8000-00000000000b', null, 'low', null, null) $$,
  'النسخة القديمة من التطبيق ما زالت تنشئ مشروع إدارة');
select is(pg_temp.seen('مشروع قديم 0645') ->> 'leaderId', 'f6440000-0000-4000-8000-000000000014',
  'الدالة القديمة: المنشئ قائد');
select is(pg_temp.seen('مشروع قديم 0645') -> 'departments' -> 0 ->> 'name', 'إدارة 0645 ب',
  'الدالة القديمة: الإدارة مرتبطة');
select ok(not ((public.get_association_project_pickers() -> 'employees' -> 0) ? 'phone_e164'),
  'قائمة الاختيار بلا بيانات تواصل');
reset role;

update public.association_projects set last_activity_at = now() - interval '30 days'
 where name = 'مشروع فريق 0645';
select ok(public.notify_stalled_association_projects() >= 1, 'كرون التعثّر يلتقط مشروعاً بلا إدارة');
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6440000-0000-4000-8000-000000000022'
                     and metadata ->> 'kind' = 'project_stalled'),
  'قائد المشروع يُنبَّه بالتعثّر');

select * from finish();
rollback;
