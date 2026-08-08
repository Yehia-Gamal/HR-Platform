-- 0114: صفحة التقارير اليومية العامة + الإعجابات والتعليقات (0324 — F5).
-- يغطي:
--   * أي موظف مسجّل يرى feed تقارير الجميع (بيانات الموظف/المسمى/المدير).
--   * toggle_daily_report_like: إعجاب → إشعار لصاحب التقرير، إلغاء → حذف.
--   * add_daily_report_comment → إشعار، رفض التعليق الفارغ.
--   * delete_daily_report_comment: صاحبه فقط (أو full-access).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(11);

do $fixture$
declare
  v_le    uuid := 'd2100000-0000-4000-8000-000000000001';
  v_dept  uuid := 'd2100000-0000-4000-8000-000000000002';
  v_jt    uuid := 'd2100000-0000-4000-8000-000000000003';
  v_auth  uuid := 'd2000000-0000-4000-8000-000000000001'; -- صاحب التقرير
  v_fan   uuid := 'd2000000-0000-4000-8000-000000000002'; -- يُعجب/يعلّق
  v_mgr   uuid := 'd2000000-0000-4000-8000-000000000003'; -- مدير صاحب التقرير
  v_user_a uuid := 'd1900000-0000-4000-8000-000000000001';
  v_user_f uuid := 'd1900000-0000-4000-8000-000000000002';
  v_user_m uuid := 'd1900000-0000-4000-8000-000000000003';
  v_report uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0114', 'كيان 0114');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0114', 'إدارة 0114');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0114', 'مهندس اختبار');

  insert into auth.users(id, email, aud, role)
    values
    (v_user_a, 'auth-0114@test.local', 'authenticated', 'authenticated'),
    (v_user_f, 'fan-0114@test.local',  'authenticated', 'authenticated'),
    (v_user_m, 'mgr-0114@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date)
    values
    (v_auth, v_user_a, 'E-0114-A', 'كاتب التقرير', v_dept, v_jt, 'active', true, current_date - 300),
    (v_fan,  v_user_f, 'E-0114-B', 'زميل معجب',    v_dept, v_jt, 'active', true, current_date - 200),
    (v_mgr,  v_user_m, 'E-0114-C', 'مدير الإدارة', v_dept, v_jt, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_a, v_auth, 'active'),
    (v_user_f, v_fan,  'active'),
    (v_user_m, v_mgr,  'active');

  insert into public.manager_relations(manager_employee_id, employee_id, relation_type)
    values (v_mgr, v_auth, 'primary');

  insert into public.daily_reports(employee_id, report_date, achievements, blockers, tomorrow_plan)
    values (v_auth, current_date, 'أنهيت المهمة', 'لا شيء', 'بدء التالي')
    returning id into v_report;

  perform set_config('app.t0114_report', v_report::text, false);
end $fixture$;

-- =====================================================================
-- جلسة الزميل: يرى feed الجميع ثم يُعجب ويعلّق
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1900000-0000-4000-8000-000000000002","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1900000-0000-4000-8000-000000000002',
  true);

-- 1) feed يظهر تقرير زميل آخر مع بيانات الموظف/المسمى/المدير
select is(
  (select jsonb_array_length(public.get_public_daily_reports_feed())),
  1,
  'feed يضم تقريراً واحداً لجميع الموظفين');

select is(
  (select it->>'employeeName'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2000000-0000-4000-8000-000000000001'),
  'كاتب التقرير',
  'feed يعرض اسم كاتب التقرير');

select is(
  (select it->>'jobTitle'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2000000-0000-4000-8000-000000000001'),
  'مهندس اختبار',
  'feed يعرض المسمى الوظيفي');

select is(
  (select it->>'managerName'
     from jsonb_array_elements(public.get_public_daily_reports_feed()) it
     where it->>'employeeId' = 'd2000000-0000-4000-8000-000000000001'),
  'مدير الإدارة',
  'feed يعرض مدير كاتب التقرير');

-- 2) إعجاب
select lives_ok(
  $q$ select public.toggle_daily_report_like(
    nullif(current_setting('app.t0114_report', true), '')::uuid) $q$,
  'إعجاب التقرير يُنفذ بنجاح');

select is(
  (select (public.toggle_daily_report_like(
    nullif(current_setting('app.t0114_report', true), '')::uuid))->>'count'),
  '0',
  'إعادة التبديل تلغي الإعجاب (count يعود 0)');

-- 3) تعليق + إشعار + رفض الفارغ
select lives_ok(
  $q$ select public.add_daily_report_comment(
    nullif(current_setting('app.t0114_report', true), '')::uuid, 'عمل رائع') $q$,
  'التعليق يُنفذ بنجاح');

select throws_ok(
  $q$ select public.add_daily_report_comment(
    nullif(current_setting('app.t0114_report', true), '')::uuid, '   ') $q$,
  '22023',
  null,
  'التعليق الفارغ مرفوض');

-- 4) الزميل يعلّق مرة أخرى ثم يحذف تعليقه
select is(
  (select count(*)::text from public.daily_report_comments
    where report_id = nullif(current_setting('app.t0114_report', true), '')::uuid),
  '1',
  'تعليق واحد مسجل على التقرير');

reset role;

-- 5) إشعار لصاحب التقرير عند الإعجاب/التعليق (يُفحص بعد reset role بسبب RLS)
select is(
  (select count(*)::text from public.notifications
    where recipient_employee_id = 'd2000000-0000-4000-8000-000000000001'
      and metadata->>'event' in ('daily_report_like','daily_report_comment')),
  '2',
  'صاحب التقرير استُشعر بالإعجاب والتعليق');

-- 6) حذف تعليق ليس لصاحبه → مرفوض
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1900000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1900000-0000-4000-8000-000000000001',
  true);

select throws_ok(
  $q$ select public.delete_daily_report_comment(
    (select id from public.daily_report_comments
      where report_id = nullif(current_setting('app.t0114_report', true), '')::uuid limit 1)) $q$,
  '42501',
  null,
  'صاحب التقرير (ليس كاتب التعليق) لا يحذف تعليق الزميل');

reset role;

select * from finish();
rollback;
