-- 0425: مشاهدات التقارير اليومية + "من شاهد ومن تفاعل" للجميع.
-- يغطي:
--   * جدول daily_report_views و RLS.
--   * record_daily_reports_views(uuid[]): تسجيل جماعي، تجاهل ids غير الموجودة،
--     وتزايد view_count عند إعادة الفتح.
--   * توسيع get_public_daily_reports_feed بحقول viewersCount/viewers/likers.
--   * get_daily_report_engagement: قائمة كاملة للمشاهدين والمعجبين.
--   * تخفيف حارس get_announcement_engagement: موظف عادي يرى من شاهد/تفاعل.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(19);

do $fixture$
declare
  v_le    uuid := 'd2300000-0000-4000-8000-000000000001';
  v_dept  uuid := 'd2300000-0000-4000-8000-000000000002';
  v_jt    uuid := 'd2300000-0000-4000-8000-000000000003';
  v_u_author uuid := 'd2500000-0000-4000-8000-000000000001';
  v_u_viewer uuid := 'd2500000-0000-4000-8000-000000000002';
  v_u_pub    uuid := 'd2500000-0000-4000-8000-000000000011';
  v_author uuid := 'd2400000-0000-4000-8000-000000000001';
  v_viewer uuid := 'd2400000-0000-4000-8000-000000000002';
  v_pub    uuid := 'd2400000-0000-4000-8000-000000000011';
  v_report uuid;
  v_announce uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0425', 'كيان 0425');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0425', 'إدارة 0425');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0425', 'مهندس اختبار');

  insert into auth.users(id, email, aud, role)
    values
    (v_u_author, 'auth-0425-a@test.local', 'authenticated', 'authenticated'),
    (v_u_viewer, 'viewer-0425@test.local', 'authenticated', 'authenticated'),
    (v_u_pub,    'pub-0425@test.local',    'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date)
    values
    (v_author, v_u_author, 'E-0425-A', 'كاتب التقرير', v_dept, v_jt, 'active', true, current_date - 300),
    (v_viewer, v_u_viewer, 'E-0425-B', 'مشاهد التقرير', v_dept, v_jt, 'active', true, current_date - 200),
    (v_pub,    v_u_pub,    'E-0425-P', 'ناشر الإعلان',  v_dept, v_jt, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status)
    values
    (v_u_author, v_author, 'active'),
    (v_u_viewer, v_viewer, 'active'),
    (v_u_pub,    v_pub,    'active');

  insert into public.user_roles(user_id, role_id)
  select v_u_pub, id from public.roles where is_full_access limit 1;

  insert into public.daily_reports(employee_id, report_date, achievements, blockers, tomorrow_plan)
    values (v_author, current_date, 'أنهيت المهمة', 'لا شيء', 'بدء التالي')
    returning id into v_report;

  insert into public.announcements(id, title, body, category, priority, status,
    target_type, published_at, created_by)
    values (gen_random_uuid(), 'إعلان 0425', 'محتوى إعلان اختبار المشاهدات.', 'general',
      'normal', 'published', 'all', now(), v_u_pub)
    returning id into v_announce;

  perform set_config('app.t0425_report', v_report::text, false);
  perform set_config('app.t0425_announce', v_announce::text, false);
end $fixture$;

-- =====================================================================
-- 1) البنية
-- =====================================================================
select has_table('public', 'daily_report_views', 'جدول daily_report_views موجود');
select has_function('public', 'record_daily_reports_views', array['uuid[]'],
  'record_daily_reports_views(uuid[]) موجودة');
select has_function('public', 'get_daily_report_engagement', array['uuid'],
  'get_daily_report_engagement(uuid) موجودة');

-- =====================================================================
-- 2) جلسة المشاهد: يسجل المشاهدة ويعجب بالتقرير
-- =====================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d2500000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub',
  'd2500000-0000-4000-8000-000000000002', true);

-- feed قبل أي مشاهدة: viewersCount صفر مع بقاء بقية الحقول
select is(
  (select it->>'viewersCount'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2400000-0000-4000-8000-000000000001'),
  '0',
  'feed يعرض viewersCount = 0 قبل أول مشاهدة');

-- تسجيل جماعي: تقرير حقيقي + معرّف غير موجود → يُسجل الموجود فقط
select is(
  (select (public.record_daily_reports_views(array[
      nullif(current_setting('app.t0425_report', true), '')::uuid,
      'd2200000-0000-4000-8000-000000000099'::uuid]))->>'recorded'),
  '1',
  'record_daily_reports_views يتجاهل معرّف غير موجود ويسجل الموجود');

-- إعادة الفتح تزيد view_count ولا تنشئ صفاً جديداً
select is(
  (select (public.record_daily_reports_views(array[
      nullif(current_setting('app.t0425_report', true), '')::uuid]))->>'recorded'),
  '1',
  'إعادة التسجيل لا تنشئ صفاً جديداً');

select is(
  (select view_count::text from public.daily_report_views
    where report_id = nullif(current_setting('app.t0425_report', true), '')::uuid
      and employee_id = 'd2400000-0000-4000-8000-000000000002'),
  '2',
  'إعادة الفتح تزيد view_count إلى 2');

-- feed بعد المشاهدة: العداد والاسم الأول للمشاهد
select is(
  (select it->>'viewersCount'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2400000-0000-4000-8000-000000000001'),
  '1',
  'feed يعرض viewersCount = 1 بعد المشاهدة');

select is(
  (select it->'viewers'->0->>'name'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2400000-0000-4000-8000-000000000001'),
  'مشاهد التقرير',
  'feed يعرض اسم أول مشاهد');

-- engagement: القائمة الكاملة مع عدد المشاهدات لكل موظف
select is(
  (select (public.get_daily_report_engagement(
    nullif(current_setting('app.t0425_report', true), '')::uuid))->>'viewersCount'),
  '1',
  'engagement يعرض عدد المشاهدين');

select is(
  (select (public.get_daily_report_engagement(
    nullif(current_setting('app.t0425_report', true), '')::uuid))
      ->'viewers'->0->>'viewCount'),
  '2',
  'engagement يعرض viewCount لكل مشاهد');

-- إعجاب من المشاهد → يظهر في engagement وفي feed
select lives_ok(
  $q$ select public.toggle_daily_report_like(
    nullif(current_setting('app.t0425_report', true), '')::uuid) $q$,
  'إعجاب المشاهد بالتقرير يُنفذ');

select is(
  (select (public.get_daily_report_engagement(
    nullif(current_setting('app.t0425_report', true), '')::uuid))->>'likersCount'),
  '1',
  'engagement يعرض عدد المعجبين بعد الإعجاب');

select is(
  (select it->'likers'->0->>'name'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2400000-0000-4000-8000-000000000001'),
  'مشاهد التقرير',
  'feed يعرض اسم أول معجب');

-- تقرير غير موجود → P0002
select throws_ok(
  $q$ select public.get_daily_report_engagement(
    'd2200000-0000-4000-8000-000000000099'::uuid) $q$,
  'P0002',
  null,
  'engagement لتقرير غير موجود مرفوض');

-- =====================================================================
-- 3) الإعلانات: موظف عادي يرى من شاهد ومن تفاعل
-- =====================================================================
select lives_ok(
  $q$ select public.record_announcement_view(
    nullif(current_setting('app.t0425_announce', true), '')::uuid) $q$,
  'المشاهد يسجل مشاهدة الإعلان');

select is(
  (select (public.get_announcement_engagement(
    nullif(current_setting('app.t0425_announce', true), '')::uuid))->>'viewerCount'),
  '1',
  'موظف عادي يرى عدد مشاهدات الإعلان');

select is(
  (select (public.get_announcement_engagement(
    nullif(current_setting('app.t0425_announce', true), '')::uuid))
      ->'viewers'->0->>'name'),
  'مشاهد التقرير',
  'موظف عادي يرى اسم مشاهد الإعلان');

select throws_ok(
  $q$ select public.get_announcement_engagement(
    'd2200000-0000-4000-8000-000000000088'::uuid) $q$,
  'P0002',
  null,
  'engagement لإعلان غير موجود مرفوض');

reset role;

select * from finish();
rollback;