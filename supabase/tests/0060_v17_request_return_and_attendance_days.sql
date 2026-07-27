-- 0060: V17 §4.2+§4.3 — اختبار إجراء "إعادة" (return) وتصفية p_days.
-- يغطي:
--   1) قيد CHECK على requests.status يشمل 'returned'
--   2) decide_request يقبل 'return' ويعيد الطلب بحالة 'returned'
--   3) decide_request يرفض 'return' بدون تعليق (return_requires_comment)
--   4) get_my_attendance_history يقبل 3 معاملات (p_limit, p_before, p_days)
--   5) get_my_attendance_history مع p_days يصفّي الأحداث القديمة

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. قيد CHECK — requests.status يشمل 'returned'
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='requests' and c.conname='requests_status_check';
    if v_chk is null then
      raise exception 'requests_status_check constraint not found';
    end if;
    if v_chk not ilike '%returned%' then
      raise exception 'returned not in status CHECK';
    end if;
  end $t$$live$,
  'requests_status_check يشمل returned'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. الدوال موجودة بالتوقيع الصحيح
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'decide_request', array['uuid','text','text'],
  'decide_request(uuid,text,text) exists'
);

select has_function(
  'public', 'get_my_attendance_history', array['integer','timestamp with time zone','integer'],
  'get_my_attendance_history(int,timestamptz,int) — 3 params with p_days'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures — UUID prefix: a0600000
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a0600000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a0600000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-RET-LE', 'كيان اختبار الإعادة');

  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V17-RET-D', 'إدارة اختبار الإعادة');

  -- 3 مستخدمين: موظف، مدير، مدير تنفيذي
  insert into auth.users(id, email, aud, role) values
    ('a0600000-0000-4000-8000-000000000101', 'v17ret-emp@test.local',  'authenticated', 'authenticated'),
    ('a0600000-0000-4000-8000-000000000102', 'v17ret-mgr@test.local',  'authenticated', 'authenticated'),
    ('a0600000-0000-4000-8000-000000000103', 'v17ret-exec@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a0600000-0000-4000-8000-000000000201', 'a0600000-0000-4000-8000-000000000101', 'RET-EMP', 'موظف الاختبار',      v_dept, 'active', true, false),
    ('a0600000-0000-4000-8000-000000000202', 'a0600000-0000-4000-8000-000000000102', 'RET-MGR', 'مدير الاختبار',       v_dept, 'active', true, false),
    ('a0600000-0000-4000-8000-000000000203', 'a0600000-0000-4000-8000-000000000103', 'RET-EXE', 'المدير التنفيذي',     v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a0600000-0000-4000-8000-000000000101', 'a0600000-0000-4000-8000-000000000201', 'active'),
    ('a0600000-0000-4000-8000-000000000102', 'a0600000-0000-4000-8000-000000000202', 'active'),
    ('a0600000-0000-4000-8000-000000000103', 'a0600000-0000-4000-8000-000000000203', 'active');

  -- الأدوار: employee, direct-manager, executive
  insert into public.user_roles(user_id, role_id)
  select 'a0600000-0000-4000-8000-000000000101', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'a0600000-0000-4000-8000-000000000102', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'a0600000-0000-4000-8000-000000000102', id from public.roles where slug='direct-manager';
  insert into public.user_roles(user_id, role_id)
  select 'a0600000-0000-4000-8000-000000000103', id from public.roles where slug='executive';

  -- علاقات الإدارة
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('a0600000-0000-4000-8000-000000000201', 'a0600000-0000-4000-8000-000000000202', 'primary', '2026-01-01');

  -- أحداث حضور: حدث قديم (90 يوم) وحدث حديث (5 أيام)
  insert into public.attendance_events(id, employee_id, event_type, event_at, status, source) values
    ('a0600000-0000-4000-8000-000000000301', 'a0600000-0000-4000-8000-000000000201', 'CHECK_IN',  now() - interval '90 days', 'accepted',  'mobile'),
    ('a0600000-0000-4000-8000-000000000302', 'a0600000-0000-4000-8000-000000000201', 'CHECK_IN',  now() - interval '5 days',  'accepted',  'mobile'),
    ('a0600000-0000-4000-8000-000000000303', 'a0600000-0000-4000-8000-000000000201', 'CHECK_OUT', now() - interval '5 days' + interval '8 hours', 'accepted', 'mobile');
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
-- 3. decide_request: إعادة بدون تعليق → خطأ return_requires_comment
-- ═══════════════════════════════════════════════════════════════════════════════

-- أنشئ طلب pending (legacy/no-step)
do $$
begin
  insert into public.requests(id, request_type, employee_id, manager_employee_id, title, reason, status, workflow_status, created_by)
  values(
    'a0600000-0000-4000-8000-000000000401',
    'leave',
    'a0600000-0000-4000-8000-000000000201',
    'a0600000-0000-4000-8000-000000000202',
    'طلب اختبار الإعادة بدون تعليق', 'سبب', 'pending', 'submitted',
    'a0600000-0000-4000-8000-000000000101'
  );
end $$;

select pg_temp.act_as('a0600000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $$select public.decide_request(
    'a0600000-0000-4000-8000-000000000401'::uuid,
    'return',
    null
  )$$,
  '22023',
  'return_requires_comment',
  'decide_request يرفض return بدون تعليق'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. decide_request: إعادة بدون تعليق (نص فارغ) → خطأ أيضاً
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.decide_request(
    'a0600000-0000-4000-8000-000000000401'::uuid,
    'return',
    '   '
  )$$,
  '22023',
  'return_requires_comment',
  'decide_request يرفض return بتعليق فارغ'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. decide_request: إعادة بتعليق → ينجح وحالة الطلب returned
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.decide_request(
    'a0600000-0000-4000-8000-000000000401'::uuid,
    'return',
    'يرجى تعديل التواريخ وإعادة الإرسال'
  )$$,
  'decide_request يقبل return بتعليق صحيح'
);

select is(
  (select status from public.requests where id = 'a0600000-0000-4000-8000-000000000401'),
  'returned',
  'حالة الطلب بعد الإعادة = returned'
);

select is(
  (select workflow_status from public.requests where id = 'a0600000-0000-4000-8000-000000000401'),
  'completed',
  'workflow_status بعد الإعادة = completed'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. decide_request: إعادة طلب ليس pending → خطأ
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.decide_request(
    'a0600000-0000-4000-8000-000000000401'::uuid,
    'return',
    'محاولة إعادة طلب منتهي'
  )$$,
  '22023', null,
  'decide_request يرفض إعادة طلب ليس pending'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. decide_request: منع الموظف من اتخاذ قرار على طلبه (self-approval)
-- ═══════════════════════════════════════════════════════════════════════════════

-- إدراج كـ superuser لتجاوز RLS (لا يوجد سياسة INSERT مفتوحة)
reset role;
do $$
begin
  insert into public.requests(id, request_type, employee_id, manager_employee_id, title, reason, status, workflow_status, created_by)
  values(
    'a0600000-0000-4000-8000-000000000402',
    'mission',
    'a0600000-0000-4000-8000-000000000202',
    'a0600000-0000-4000-8000-000000000203',
    'طلب المدير نفسه', 'سبب اختبار', 'pending', 'submitted',
    'a0600000-0000-4000-8000-000000000102'
  );
end $$;

-- إعادة سياق المدير للاختبار التالي
select pg_temp.act_as('a0600000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $$select public.decide_request(
    'a0600000-0000-4000-8000-000000000402'::uuid,
    'return',
    'محاولة إعادة طلبي'
  )$$,
  '42501', null,
  'decide_request يمنع الإعادة الذاتية (self-approval)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. request_actions: تسجيل إجراء return في سجل التدقيق
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  exists(
    select 1 from public.request_actions
    where request_id = 'a0600000-0000-4000-8000-000000000401'
      and action = 'return'
      and comment = 'يرجى تعديل التواريخ وإعادة الإرسال'
  ),
  'request_actions يحتوي سجل return بالتعليق الصحيح'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9-11. get_my_attendance_history مع p_days
-- ═══════════════════════════════════════════════════════════════════════════════

-- التبديل لمستخدم الموظف
reset role;
select pg_temp.act_as('a0600000-0000-4000-8000-000000000101');
set local role authenticated;

-- بدون p_days: يُرجع كل الأحداث (3)
select is(
  jsonb_array_length(public.get_my_attendance_history(100, null, null)),
  3,
  'بدون p_days → كل الأحداث (3)'
);

-- مع p_days=30: يصفّي الحدث القديم (90 يوم) → حدثان فقط
select is(
  jsonb_array_length(public.get_my_attendance_history(100, null, 30)),
  2,
  'p_days=30 → حدثان فقط (الحديثان)'
);

-- مع p_days=1: لا أحداث في آخر يوم
select is(
  jsonb_array_length(public.get_my_attendance_history(100, null, 1)),
  0,
  'p_days=1 → لا أحداث (كلها أقدم من يوم)'
);

reset role;
select * from finish();
rollback;
