-- =====================================================================
-- 0649: محتوى النزاعات لا يقرؤه إلا المخوّلون + قفل جداول التدقيق المُقسَّمة
-- ---------------------------------------------------------------------
-- كانت لكل جدول فرعي من جداول النزاعات سياسة `using (true)` متبقية تُلغي
-- السياسة المُحكمة (السياسات PERMISSIVE تُجمع بـ OR).
--
-- يثبت:
--   1) لا سياسة SELECT بـ `using (true)` على أي من الجداول الثمانية
--   2) موظف لا علاقة له بالنزاع لا يرى إفادة فيه (كان يراها)
--   3) مقدّم الإفادة ما زال يراها (السياسة المُحكمة سليمة)
--   4) audit_events_partitioned وأقسامه: RLS مفعّل و authenticated بلا صلاحيات
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

do $fixture$
declare
  v_le     uuid := 'f6490000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f6490000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f6490000-0000-4000-8000-000000000003';
  v_c      uuid := 'f6490000-0000-4000-8000-000000000011';  -- مقدّم الشكوى
  v_u      uuid := 'f6490000-0000-4000-8000-000000000012';  -- موظف لا علاقة له
  v_user_c uuid := 'f6490000-0000-4000-8000-000000000021';
  v_user_u uuid := 'f6490000-0000-4000-8000-000000000022';
  v_case   uuid := 'f6490000-0000-4000-8000-000000000031';
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0649', 'كيان 0649');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0649', 'إدارة 0649');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0649', 'وظيفة 0649');

  insert into auth.users(id, email, aud, role) values
    (v_user_c, 'c-0649@test.local', 'authenticated', 'authenticated'),
    (v_user_u, 'u-0649@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values
    (v_c, v_user_c, 'E-0649-C', 'مشتكٍ 0649',  v_dept, v_jt, 'active', true, current_date - 300, '+201000006490'),
    (v_u, v_user_u, 'E-0649-U', 'زميل 0649',   v_dept, v_jt, 'active', true, current_date - 300, '+201000006491');

  insert into public.profiles(id, employee_id, status) values
    (v_user_c, v_c, 'active'),
    (v_user_u, v_u, 'active');

  insert into public.dispute_cases(id, case_number, title, description, case_type, status, severity, actor_employee_id)
  values (v_case, 'T-0649', 'نزاع اختبار 0649', 'وصف كافٍ لنزاع الاختبار', 'verbal_abuse', 'submitted', 'normal', v_c);

  insert into public.dispute_statements(case_id, submitted_by, statement_type, statement_text, visibility)
  values (v_case, v_c, 'complainant', 'إفادة سرية للجنة فقط في نزاع الاختبار', 'committee_only');
end $fixture$;

-- =====================================================================
-- 1) لا سياسة قراءة مفتوحة على الجداول الثمانية
-- =====================================================================
select is(
  (select coalesce(string_agg(tablename || '.' || policyname, ', ' order by tablename), '')
     from pg_policies
    where schemaname = 'public'
      and tablename in ('dispute_statements','dispute_decisions','dispute_parties','dispute_appeals',
                        'dispute_actions','dispute_settlements','dispute_decision_receipts',
                        'dispute_session_participants')
      and cmd in ('SELECT','ALL')
      and permissive = 'PERMISSIVE'
      and qual = 'true'),
  '',
  'لا سياسة SELECT بـ using(true) على جداول النزاعات (كانت تُلغي السياسات المُحكمة)');

-- =====================================================================
-- 2) موظف لا علاقة له لا يرى الإفادة
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f6490000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f6490000-0000-4000-8000-000000000022', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from public.dispute_statements
    where case_id = 'f6490000-0000-4000-8000-000000000031'),
  0,
  'P0: موظف لا علاقة له بالنزاع لا يقرأ إفاداته (كان يقرؤها عبر using(true))');

select is(
  (select count(*)::int from public.dispute_cases where id = 'f6490000-0000-4000-8000-000000000031'),
  0,
  'وموظف لا علاقة له لا يرى القضية نفسها (can_access_dispute)');

reset role;

-- =====================================================================
-- 3) مقدّم الإفادة ما زال يراها
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f6490000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f6490000-0000-4000-8000-000000000021', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from public.dispute_statements
    where case_id = 'f6490000-0000-4000-8000-000000000031'),
  1,
  'مقدّم الإفادة ما زال يراها (السياسة المُحكمة سليمة)');

reset role;

-- =====================================================================
-- 4) جداول التدقيق المُقسَّمة مقفلة
-- =====================================================================
select is(
  (select count(*)::int
     from pg_class c
    where c.oid in (select 'public.audit_events_partitioned'::regclass
                    union select inhrelid from pg_inherits
                    where inhparent = 'public.audit_events_partitioned'::regclass)
      and not c.relrowsecurity),
  0,
  'audit_events_partitioned وكل أقسامه: RLS مفعّل');

select is(
  (select count(*)::int
     from pg_class c
    where c.oid in (select 'public.audit_events_partitioned'::regclass
                    union select inhrelid from pg_inherits
                    where inhparent = 'public.audit_events_partitioned'::regclass)
      and (has_table_privilege('authenticated', c.oid, 'SELECT')
           or has_table_privilege('authenticated', c.oid, 'INSERT'))),
  0,
  'authenticated بلا SELECT/INSERT على جداول التدقيق المُقسَّمة');

select is(
  (select count(*)::int
     from pg_class c
    where c.oid in (select 'public.audit_events_partitioned'::regclass
                    union select inhrelid from pg_inherits
                    where inhparent = 'public.audit_events_partitioned'::regclass)
      and has_table_privilege('anon', c.oid, 'SELECT')),
  0,
  'anon بلا SELECT على جداول التدقيق المُقسَّمة');

select * from finish();
rollback;
