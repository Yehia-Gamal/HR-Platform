-- =====================================================================
-- 0537: اختبار نظام الطعون على الغرامات الفورية
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(18);

-- fixture
do $fixture$
declare
  v_le    uuid := 'f0537000-0000-4000-8000-000000000001';
  v_dept  uuid := 'f0537000-0000-4000-8000-000000000002';
  v_jt    uuid := 'f0537000-0000-4000-8000-000000000003';
  v_admin uuid := 'f0537000-0000-4000-8000-000000000011';
  v_emp   uuid := 'f0537000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f0537000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f0537000-0000-4000-8000-000000000022';
  v_role   uuid;
  v_penalty uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0537', 'كيان 0537');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0537', 'إدارة 0537');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0537', 'وظيفة 0537');
  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'admin-0537@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0537@test.local',  'authenticated', 'authenticated');
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    (v_admin, v_user_a, 'E-0537-A', 'مسؤول 0537', v_dept, v_jt, 'active', true, current_date - 500, '+201000005371'),
    (v_emp,   v_user_e, 'E-0537-B', 'موظف 0537',  v_dept, v_jt, 'active', true, current_date - 300, '+201000005372');
  insert into public.profiles(id, employee_id, status) values (v_user_a, v_admin, 'active'), (v_user_e, v_emp, 'active');
  insert into public.roles(id, slug, name_ar, name_en, is_full_access) values (gen_random_uuid(), 'admin-0537', 'أدمن 0537', 'Admin 0537', true) on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0537';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;
  v_penalty := public.generate_instant_penalty(v_emp, current_date, 25);
  perform set_config('app.t0537_admin', v_admin::text, false);
  perform set_config('app.t0537_emp', v_emp::text, false);
  perform set_config('app.t0537_user_a', v_user_a::text, false);
  perform set_config('app.t0537_user_e', v_user_e::text, false);
  perform set_config('app.t0537_penalty', v_penalty::text, false);
end $fixture$;

-- 1. البنية
select has_table('public', 'penalty_disputes', 'table exists');
select has_function('public', 'submit_penalty_dispute', array['uuid','text'], 'submit fn exists');
select has_function('public', 'review_penalty_dispute', array['uuid','text','text'], 'review fn exists');
select has_function('public', 'get_penalty_disputes', array['text'], 'get fn exists');
select ok((select relrowsecurity from pg_class where relname = 'penalty_disputes'), 'RLS enabled');

-- 2. إرسال طعن ناجح
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0537_user_e'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0537_user_e', true), true);

select lives_ok(
  format($ select public.submit_penalty_dispute(%L::uuid, 'كنت في مهمة رسمية') $, current_setting('app.t0537_penalty', true)::uuid),
  'employee submits dispute'
);

-- 3. طعن مكرر مرفوض
select throws_ok(
  format($ select public.submit_penalty_dispute(%L::uuid, 'سبب آخر') $, current_setting('app.t0537_penalty', true)::uuid),
  'duplicate dispute rejected'
);

-- 4. جلب الطعون
select is(
  (select count(*)::int from public.get_penalty_disputes(null)),
  1,
  'get_disputes returns one row'
);

-- 5. مراجعة الطعن - قبول
reset role;
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0537_user_a'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0537_user_a', true), true);

select lives_ok(
  format($ select public.review_penalty_dispute(
    (select id from public.penalty_disputes limit 1),
    'approved', 'مقبول') $),
  'admin approves dispute'
);

-- 6. الغرامة أصبحت ملغاة
select is(
  (select status from public.instant_attendance_penalties where id = current_setting('app.t0537_penalty', true)::uuid),
  'cancelled',
  'penalty cancelled after approval'
);

-- 7. لا يمكن مراجعة طعن تم مراجعته
select throws_ok(
  format($ select public.review_penalty_dispute(
    (select id from public.penalty_disputes limit 1),
    'rejected', 'مرفوض') $),
  'already reviewed dispute rejected'
);

-- 8. إنشاء غرامة أخرى + رفض
reset role;
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0537_user_e'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0537_user_e', true), true);

do $fix2$
declare v_p2 uuid;
begin
  v_p2 := public.generate_instant_penalty(current_setting('app.t0537_emp')::uuid, current_date - 1, 35);
  perform set_config('app.t0537_penalty2', v_p2::text, false);
end $fix2$;

select lives_ok(
  format($ select public.submit_penalty_dispute(%L::uuid, 'سبب ثاني') $, current_setting('app.t0537_penalty2', true)::uuid),
  'second dispute submitted'
);

reset role;
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0537_user_a'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0537_user_a', true), true);

select lives_ok(
  format($ select public.review_penalty_dispute(
    (select id from public.penalty_disputes where penalty_id = %L::uuid),
    'rejected', 'مرفوض') $, current_setting('app.t0537_penalty2', true)::uuid),
  'admin rejects dispute'
);

select is(
  (select status from public.penalty_disputes where penalty_id = current_setting('app.t0537_penalty2', true)::uuid),
  'rejected',
  'dispute status is rejected'
);

-- 9. penalties table still active (not cancelled)
select is(
  (select status from public.instant_attendance_penalties where id = current_setting('app.t0537_penalty2', true)::uuid),
  'pending_payment',
  'rejected dispute keeps penalty active'
);

select * from finish();
rollback;
