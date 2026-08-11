-- =====================================================================
-- 0368: اختبار تضييق سياسات RLS على الجداول الحساسة (migration 0368)
-- ─────────────────────────────────────────────────────────────────────
-- الهدف: التحقق من أن migration 0368 طبّق السياسات المقيدة صحيحاً على:
--   ① جداول الحوكمة والتدقيق (13 جدول): لا using(true) بعد الآن
--   ② جداول admin-only   (4 جداول): لا using(true) بعد الآن
--   ③ جداول إنهاء الخدمات (3 جداول): سياسة ALL مقيدة (employee_id / HR)
--   ④ جداول instapay    (2 جدول):  لا using(true)، مقيد بـ HR
--   ⑤ employee_penalties: موظف يرى بياناته فقط، HR يرى الكل، كتابة مباشرة محجوبة
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

-- ─── الجداول المتأثرة (نفلترها للموجود فعلاً) ──────────────────────

create temp table _tbl_gov (t text);
insert into _tbl_gov values
  ('ai_use_cases'),('audit_findings'),('automation_rules'),('automation_runs'),
  ('corrective_actions'),('data_assets'),('data_quality_rules'),
  ('engagement_campaigns'),('internal_audits'),('quality_cases'),
  ('service_catalog_items'),('service_requests'),('service_request_messages');

create temp table _tbl_adm (t text);
insert into _tbl_adm values
  ('notification_jobs'),('report_runs'),('scheduled_reports'),('generated_documents');

create temp table _tbl_off (t text);
insert into _tbl_off values
  ('offboarding_cases'),('offboarding_actions'),('offboarding_clearance_items');

create temp table _tbl_ins (t text);
insert into _tbl_ins values ('payroll_instapay_batches'),('payroll_instapay_items');

create temp table _ex_gov as
  select t from _tbl_gov where to_regclass(format('public.%I', t)) is not null;
create temp table _ex_adm as
  select t from _tbl_adm where to_regclass(format('public.%I', t)) is not null;
create temp table _ex_off as
  select t from _tbl_off where to_regclass(format('public.%I', t)) is not null;
create temp table _ex_ins as
  select t from _tbl_ins where to_regclass(format('public.%I', t)) is not null;

-- ─── الخطة الديناميكية ──────────────────────────────────────────────
-- لكل مجموعة: 1 assertion لكل جدول موجود
-- + 9 ثابتة: 3 بنيوية على employee_penalties + 6 سلوكية
select plan(
    (select count(*)::int from _ex_gov)   -- ① حوكمة
  + (select count(*)::int from _ex_adm)   -- ② admin-only
  + (select count(*)::int from _ex_off)   -- ③ offboarding
  + (select count(*)::int from _ex_ins)   -- ④ instapay
  + 9                                      -- ⑤ employee_penalties (ثابتة)
);

-- =====================================================================
-- ① جداول الحوكمة والتدقيق: لا سياسة SELECT/ALL بشرط using(true)
-- =====================================================================
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = g.t
      and cmd         in ('SELECT', 'ALL')
      and qual        = 'true'
  ),
  format('0368 حوكمة: %s — بدون سياسة SELECT/ALL using(true)', g.t)
)
from _ex_gov g;

-- =====================================================================
-- ② جداول admin-only: لا سياسة SELECT/ALL بشرط using(true)
-- =====================================================================
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = a.t
      and cmd         in ('SELECT', 'ALL')
      and qual        = 'true'
  ),
  format('0368 admin: %s — بدون سياسة SELECT/ALL using(true)', a.t)
)
from _ex_adm a;

-- =====================================================================
-- ③ جداول إنهاء الخدمات: سياسة ALL مقيدة موجودة (غير true)
-- =====================================================================
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = o.t
      and cmd         = 'ALL'
      and qual        is not null
      and qual        <> 'true'
  ),
  format('0368 offboarding: %s — توجد سياسة ALL مقيدة', o.t)
)
from _ex_off o;

-- =====================================================================
-- ④ جداول instapay: لا سياسة SELECT/ALL بشرط using(true)
-- =====================================================================
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = i.t
      and cmd         in ('SELECT', 'ALL')
      and qual        = 'true'
  ),
  format('0368 instapay: %s — بدون سياسة SELECT/ALL using(true)', i.t)
)
from _ex_ins i;

-- =====================================================================
-- ⑤ بنيوية ثابتة — employee_penalties (3 اختبارات)
-- =====================================================================

-- 5.1 RLS مُفعّل
select row_eq(
  $$select relrowsecurity from pg_class where relname = 'employee_penalties'$$,
  row(true),
  '0368 بنيوي: RLS مُفعّل على employee_penalties'
);

-- 5.2 لا سياسة using(true) على الجدول
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = 'employee_penalties'
      and cmd         in ('SELECT', 'ALL')
      and qual        = 'true'
  ),
  '0368 بنيوي: employee_penalties — بدون سياسة using(true)'
);

-- 5.3 سياسة FOR ALL تحوي قيد employee_id (self-service)
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = 'employee_penalties'
      and cmd         = 'ALL'
      and qual        like '%employee_id%'
  ),
  '0368 بنيوي: employee_penalties — سياسة ALL تقيّد بـ employee_id'
);

-- =====================================================================
-- Fixture (superuser — قبل أي تبديل دور)
-- =====================================================================
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

do $fix$
declare
  v_le    uuid := 'e368e368-0000-4000-8000-000000000000';
  v_dept  uuid := 'e368e368-0000-4000-8000-000000000010';
  v_ua    uuid := 'e368e368-0000-4000-8000-000000000001'; -- موظف عادي
  v_ub    uuid := 'e368e368-0000-4000-8000-000000000002'; -- HR specialist
  v_ea    uuid := 'e368e368-0000-4000-8000-000000000011';
  v_eb    uuid := 'e368e368-0000-4000-8000-000000000012';
  v_role_emp uuid;
  v_role_hr  uuid;
begin
  -- كيان قانوني + إدارة
  insert into public.legal_entities (id, code, name)
  values (v_le, 'E368-LE', 'كيان اختبار 0368');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'E368-D1', 'إدارة اختبار 0368');

  -- مستخدمو المصادقة
  insert into auth.users (id, email, aud, role) values
    (v_ua, 'e368-emp@test.local', 'authenticated', 'authenticated'),
    (v_ub, 'e368-hr@test.local',  'authenticated', 'authenticated');

  -- موظفون
  insert into public.employees
    (id, user_id, employee_code, full_name_ar, department_id, status, is_active)
  values
    (v_ea, v_ua, 'E368-001', 'موظف اختبار 0368-أ', v_dept, 'active', true),
    (v_eb, v_ub, 'E368-002', 'موظف اختبار 0368-ب', v_dept, 'active', true);

  -- ملفات التعريف
  insert into public.profiles (id, employee_id, status) values
    (v_ua, v_ea, 'active'),
    (v_ub, v_eb, 'active');

  -- أدوار
  select id into v_role_emp from public.roles where slug = 'employee';
  select id into v_role_hr  from public.roles where slug = 'hr-specialist';

  insert into public.user_roles (user_id, role_id) values
    (v_ua, v_role_emp),
    (v_ub, v_role_hr);

  -- عقوبات: واحدة لكل موظف
  insert into public.employee_penalties
    (employee_id, penalty_type, amount, reason, issued_by)
  values
    (v_ea, 'attendance', 10.00, 'مخالفة اختبار 0368 لموظف أ', v_eb),
    (v_eb, 'late',       15.00, 'مخالفة اختبار 0368 لموظف ب', v_ea);
end $fix$;

-- =====================================================================
-- سلوكي: الموظف العادي (3 اختبارات)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"e368e368-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'e368e368-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- 6.1 الموظف يرى عقوبته فقط (self-only)
select is(
  (select count(*)::int from public.employee_penalties),
  1,
  '0368 سلوكي: الموظف العادي يرى عقوبته الخاصة فقط (1 من 2)'
);

-- 6.2 الإدراج المباشر محجوب بـ WITH CHECK
select throws_ok(
  $$insert into public.employee_penalties
        (employee_id, penalty_type, amount, reason, issued_by)
      values
        ('e368e368-0000-4000-8000-000000000011',
         'attendance', 10.00, 'محاولة إدراج مباشرة',
         'e368e368-0000-4000-8000-000000000012')$$,
  '42501', null,
  '0368 سلوكي: الموظف العادي لا يستطيع إدراج عقوبة مباشرة (WITH CHECK)'
);

-- 6.3 جدول instapay مرئي بـ 0 سجلات (HR-only)
select is(
  (select count(*)::int from public.payroll_instapay_batches),
  0,
  '0368 سلوكي: الموظف العادي يرى 0 سجلات instapay (HR-only)'
);

-- =====================================================================
-- سلوكي: HR specialist (2 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"e368e368-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'e368e368-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

-- 7.1 HR يرى عقوبات كل الموظفين
select is(
  (select count(*)::int from public.employee_penalties),
  2,
  '0368 سلوكي: HR specialist يرى عقوبات كل الموظفين (2 سجل)'
);

-- 7.2 HR يملك صلاحية قراءة instapay (0 سجل لغياب fixture)
select is(
  (select count(*)::int from public.payroll_instapay_batches),
  0,
  '0368 سلوكي: HR يملك صلاحية instapay (0 سجل لغياب fixture — لا استثناء)'
);

-- =====================================================================
-- سلوكي: مجهول (anon) — محجوب (1 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

-- 8.1 مجهول مرفوض من employee_penalties
select throws_ok(
  $$select count(*) from public.employee_penalties$$,
  '42501', null,
  '0368 سلوكي: مجهول (anon) مرفوض من employee_penalties'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
