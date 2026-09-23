-- =====================================================================
-- 0550: المضاعفة تلقائية، التعليق قرار بشري (migration 0550)
-- ---------------------------------------------------------------------
-- قبل 0550: الكرون (بلا JWT) يستدعي auto_escalate_instant_penalties؛ أول صف
-- يبلغ مرحلة التعليق يرفضه حارسا employees/profiles بـ 42501، فيلتقطه
-- `when others → return 0` ويُلغي الدورة كاملة — بما فيها المضاعفات.
--
-- يثبت:
--   1) استدعاء الكرون (بلا JWT) لا يفشل
--   2) المضاعفة تُحفظ فعلاً (كانت تُلغى مع الدورة)
--   3) الكرون لا يعلّق أحداً — الصف يبقى doubled والموظف active
--   4) يُسجَّل instant_penalty.suspension_pending
--   5) مستخدم full-access يستدعي الدالة يحصل على التعليق الكامل كما صُمِّم
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(9);

-- =====================================================================
-- Fixture: مسؤول full-access (A) + موظف عادي (X) + غرامة غير مسددة عمرها 5 أيام
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f5500000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f5500000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f5500000-0000-4000-8000-000000000003';
  v_a      uuid := 'f5500000-0000-4000-8000-000000000011';
  v_x      uuid := 'f5500000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f5500000-0000-4000-8000-000000000021';
  v_role   uuid;
  v_date   date := current_date - 5;
begin
  -- is_employee_exempt_from_instant_penalty يُعفي الجمعة (isodow=5) والعطلات الرسمية،
  -- فيُلغي الغرامة بدل مضاعفتها. نختار يوم عمل مضموناً وإلا فشل الاختبار يوماً كل أسبوع.
  while extract(isodow from v_date)::integer = 5
     or exists (select 1 from public.public_holidays where holiday_date = v_date) loop
    v_date := v_date - 1;
  end loop;

  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0550', 'كيان 0550');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0550', 'إدارة 0550');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0550', 'وظيفة 0550');

  insert into auth.users(id, email, aud, role)
    values (v_user_a, 'admin-0550@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values
    (v_a, v_user_a, 'E-0550-A', 'مسؤول 0550', v_dept, v_jt, 'active', true, current_date - 500, '+201000005500'),
    (v_x, null,     'E-0550-X', 'موظف 0550',  v_dept, v_jt, 'active', true, current_date - 300, '+201000005501');

  insert into public.profiles(id, employee_id, status) values (v_user_a, v_a, 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0550', 'أدمن 0550', 'Admin 0550', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0550';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;

  -- غرامة غير مسددة من 5 أيام: تستحق المضاعفة ثم التعليق في نفس الدورة
  insert into public.instant_attendance_penalties(
    id, employee_id, work_date, late_minutes, original_amount, current_amount, status, escalation_level)
  values ('f5500000-0000-4000-8000-000000000031', v_x, v_date, 20, 20.00, 20.00,
          'pending_payment', 'initial');
end $fixture$;

-- =====================================================================
-- 1) استدعاء الكرون: بلا JWT إطلاقاً
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

select lives_ok(
  $rt$ select public.auto_escalate_instant_penalties() $rt$,
  'استدعاء الكرون (بلا JWT) لا يفشل');

select is(
  (select status from public.instant_attendance_penalties
    where id = 'f5500000-0000-4000-8000-000000000031'),
  'doubled',
  'المضاعفة حُفظت فعلاً (كانت تُلغى مع الدورة كلها قبل 0550)');

select is(
  (select current_amount from public.instant_attendance_penalties
    where id = 'f5500000-0000-4000-8000-000000000031'),
  500.00::numeric,
  'المبلغ المضاعف 500 ج.م');

select is(
  (select status from public.employees where id = 'f5500000-0000-4000-8000-000000000012'),
  'active',
  'الكرون لا يعلّق أحداً — التعليق قرار بشري');

select ok(exists(
  select 1 from public.audit_events
   where event_type = 'instant_penalty.suspension_pending'
     and target_id = 'f5500000-0000-4000-8000-000000000031'),
  'سُجِّل instant_penalty.suspension_pending للصف المستحق');

select ok(not exists(
  select 1 from public.audit_events
   where event_type = 'instant_penalty.escalation_failed'
     and occurred_at > now() - interval '1 minute'),
  'لا escalation_failed — الدورة لم تُلغَ بصمت');

-- =====================================================================
-- 2) مستخدم full-access يستدعيها: التعليق الكامل كما صُمِّم
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5500000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5500000-0000-4000-8000-000000000021', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;

select lives_ok(
  $rt$ select public.auto_escalate_instant_penalties() $rt$,
  'full-access يستدعي التصعيد');

select is(
  (select status from public.instant_attendance_penalties
    where id = 'f5500000-0000-4000-8000-000000000031'),
  'suspended',
  'full-access: الغرامة انتقلت إلى suspended');

select is(
  (select status from public.employees where id = 'f5500000-0000-4000-8000-000000000012'),
  'suspended',
  'full-access: الموظف عُلِّق فعلاً');

select * from finish();
rollback;
