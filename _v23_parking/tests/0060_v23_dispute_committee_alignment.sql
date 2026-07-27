-- 0060: V23 dispute committee alignment tests
-- Agent 07 — لجنة المشكلات والجزاءات
--
-- Tests:
-- 1. word_count helper
-- 2. submit_my_dispute_v23 RPC exists
-- 3. word validation (too short, too long, just right)
-- 4. no removed fields (priority always normal, no incident_location)
-- 5. no auto-submit (confirmation required)
-- 6. no execution before approval (already tested in 0054 but reinforced)
-- 7. employee can cancel before acceptance only
-- 8. resolved_friendly status transition
-- 9. committee scope: employee cannot drive workflow
-- 10. full V23 happy path: submit → accept → review → resolve_friendly → close

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(24);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure: V23 RPC and helper exist
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'word_count', array['text'],
  'word_count helper function exists'
);
select has_function(
  'public', 'submit_my_dispute_v23', array['text','text','text','jsonb','jsonb','boolean','boolean'],
  'submit_my_dispute_v23 RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. word_count validation
-- ═══════════════════════════════════════════════════════════════════════════════

select is(public.word_count(''), 0, 'word_count: empty string = 0');
select is(public.word_count('كلمة واحدة فقط'), 3, 'word_count: 3 Arabic words');
select is(public.word_count('one two three four five'), 5, 'word_count: 5 English words');
select is(public.word_count('   مسافات   متعددة   بين   الكلمات   '), 4, 'word_count: handles multiple spaces');

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. resolved_friendly status in CHECK constraint
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$do $t$ declare v_chk text; begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='dispute_cases' and c.conname='dispute_cases_status_check';
    if v_chk not ilike '%resolved_friendly%' then
      raise exception 'resolved_friendly not in status CHECK';
    end if;
  end $t$$$$,
  'status CHECK includes resolved_friendly'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'b6600000-0000-4000-8000-000000000001';
  v_dept   uuid := 'b6600000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V23-DSP-LE', 'كيان نزاعات V23')
  on conflict(id) do nothing;
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-DSP-D', 'إدارة نزاعات V23')
  on conflict(id) do nothing;

  -- 3 users: employee, respondent, admin (full-access)
  insert into auth.users(id, email, aud, role) values
    ('b6600000-0000-4000-8000-000000000101', 'v23dsp-emp@test.local',   'authenticated', 'authenticated'),
    ('b6600000-0000-4000-8000-000000000102', 'v23dsp-resp@test.local',  'authenticated', 'authenticated'),
    ('b6600000-0000-4000-8000-000000000103', 'v23dsp-admin@test.local', 'authenticated', 'authenticated')
  on conflict(id) do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('b6600000-0000-4000-8000-000000000201', 'b6600000-0000-4000-8000-000000000101', 'V23-001', 'موظف اختبار V23',   v_dept, 'active', true, false),
    ('b6600000-0000-4000-8000-000000000202', 'b6600000-0000-4000-8000-000000000102', 'V23-002', 'الطرف الآخر V23',    v_dept, 'active', true, false),
    ('b6600000-0000-4000-8000-000000000203', 'b6600000-0000-4000-8000-000000000103', 'V23-003', 'مدير النظام V23',    v_dept, 'active', true, false)
  on conflict(id) do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('b6600000-0000-4000-8000-000000000101', 'b6600000-0000-4000-8000-000000000201', 'active'),
    ('b6600000-0000-4000-8000-000000000102', 'b6600000-0000-4000-8000-000000000202', 'active'),
    ('b6600000-0000-4000-8000-000000000103', 'b6600000-0000-4000-8000-000000000203', 'active')
  on conflict(id) do nothing;

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'b6600000-0000-4000-8000-000000000103', id from public.roles where slug='admin'
  on conflict do nothing;

  -- employee = employee role
  insert into public.user_roles(user_id, role_id)
  select 'b6600000-0000-4000-8000-000000000101', id from public.roles where slug='employee'
  on conflict do nothing;
end
$fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. V23 word count validation: description too short (< 3 words)
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6600000-0000-4000-8000-000000000101');
set local role authenticated;

select throws_ok(
  $$select public.submit_my_dispute_v23(
    'عنوان صالح للمشكلة',
    'كلمتان فقط',
    'employee_conflict',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, true, true)$$,
  '22023', null,
  'V23: description with < 3 words is rejected'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. V23 word count validation: description too long (> 300 words)
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.submit_my_dispute_v23(
    'عنوان صالح للمشكلة',
    'كلمة ' || repeat('أخرى ', 301),
    'employee_conflict',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, true, true)$$,
  '22023', null,
  'V23: description with > 300 words is rejected'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. V23 confirmation required (no auto-submit)
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.submit_my_dispute_v23(
    'عنوان صالح للمشكلة',
    'هذا وصف كافٍ يتجاوز ثلاث كلمات بشكل واضح ومؤكد',
    'employee_conflict',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, false, true)$$,
  '22023', null,
  'V23: truth confirmation required (no auto-submit)'
);

select throws_ok(
  $$select public.submit_my_dispute_v23(
    'عنوان صالح للمشكلة',
    'هذا وصف كافٍ يتجاوز ثلاث كلمات بشكل واضح ومؤكد',
    'employee_conflict',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, true, false)$$,
  '22023', null,
  'V23: confidentiality confirmation required'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. V23 happy path: simplified intake
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.submit_my_dispute_v23(
    'مشكلة تتعلق بتوزيع المهام في الفريق',
    'حدث خلاف بين أعضاء الفريق حول توزيع المهام اليومية ويؤثر على سير العمل بشكل ملموس.',
    'employee_conflict',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, true, true)$$,
  'V23: simplified intake succeeds with valid data'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. V23: no priority field — always normal
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select severity from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
  'normal',
  'V23: priority is always normal from employee form (no priority field)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. V23: no incident_location stored
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select incident_location from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
  null::text,
  'V23: incident_location is null (removed from employee form)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. Employee cannot drive workflow
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.transition_dispute_case(
    (select id from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
    'accept', 'محاولة غير مخولة')$$,
  '42501', null,
  'V23: employee cannot accept own case (committee scope)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. Employee can cancel before acceptance
-- ═══════════════════════════════════════════════════════════════════════════════

-- First create another case to cancel (we keep the first for further workflow tests)
select lives_ok(
  $$select public.submit_my_dispute_v23(
    'مشكلة للإلغاء قبل القبول',
    'وصف كافٍ يتجاوز ثلاث كلمات بشكل واضح لغرض اختبار الإلغاء',
    'misunderstanding',
    '[{"employeeId":"b6600000-0000-4000-8000-000000000202","type":"respondent"}]'::jsonb,
    '[]'::jsonb, true, true)$$,
  'V23: second case created for cancel test'
);

select lives_ok(
  $$select public.cancel_my_dispute(
    (select id from public.dispute_cases where title = 'مشكلة للإلغاء قبل القبول'),
    'قررت عدم المتابعة والحل بنفسي')$$,
  'V23: employee can cancel before acceptance'
);

select is(
  (select status from public.dispute_cases where title = 'مشكلة للإلغاء قبل القبول'),
  'cancelled_by_employee',
  'V23: cancelled case status is cancelled_by_employee'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12. Admin: accept → resolve_friendly → close (full path)
-- ═══════════════════════════════════════════════════════════════════════════════

reset role;
select pg_temp.act_as('b6600000-0000-4000-8000-000000000103');
set local role authenticated;

select lives_ok(
  $$select public.transition_dispute_case(
    (select id from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
    'accept', 'قبول المشكلة للدراسة')$$,
  'V23: admin accepts case'
);

select lives_ok(
  $$select public.transition_dispute_case(
    (select id from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
    'start_review', 'بدء المراجعة')$$,
  'V23: admin starts review'
);

select lives_ok(
  $$select public.transition_dispute_case(
    (select id from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
    'resolve_friendly', 'تم التوصل لحل ودي بين الأطراف')$$,
  'V23: resolve_friendly transition succeeds'
);

select is(
  (select status from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
  'resolved_friendly',
  'V23: case status is resolved_friendly'
);

select lives_ok(
  $$select public.transition_dispute_case(
    (select id from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
    'close', 'إغلاق بعد الحل الودي')$$,
  'V23: close after friendly resolution'
);

select is(
  (select status from public.dispute_cases where title = 'مشكلة تتعلق بتوزيع المهام في الفريق'),
  'closed',
  'V23: case is closed after friendly resolution path'
);

reset role;
select * from finish();
rollback;
