-- 0056_v17_operations_request_routing: V17 §1.2 — توجيه طلبات التشغيل للمدير التنفيذي.
-- يغطي: وجود resolve_request_approver، CHECK constraint على أنواع الطلبات (V17)،
-- التوجيه إلى executive للتشغيل، التوجيه للمدير المباشر لغير التشغيل،
-- منع الموافقة الذاتية، رفض الأنواع القديمة عبر submit_request/submit_my_request.
-- (Migration 0134 + 0136 — إصلاح ربط user_roles بدلاً من role_assignments)

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- ════════════════════════════════════════════════════════════════════════════════
-- 1. الدوال موجودة
-- ════════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'resolve_request_approver', array['uuid','date'],
  'resolve_request_approver(uuid, date) exists'
);

select has_function(
  'public', 'submit_request', array['text','uuid','uuid','text','text','jsonb'],
  'submit_request(text,uuid,uuid,text,text,jsonb) exists'
);

select has_function(
  'public', 'submit_my_request', array['text','text','text','jsonb','uuid'],
  'submit_my_request(text,text,text,jsonb,uuid) exists'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 2. CHECK constraint — 6 أنواع V17 فقط
-- ════════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='requests' and c.conname='requests_request_type_check';
    if v_chk is null then
      raise exception 'requests_request_type_check constraint not found';
    end if;
    -- الأنواع الستة V17 موجودة
    if v_chk not ilike '%leave%'                then raise exception 'CHECK missing leave'; end if;
    if v_chk not ilike '%mission%'              then raise exception 'CHECK missing mission'; end if;
    if v_chk not ilike '%convoy%'               then raise exception 'CHECK missing convoy'; end if;
    if v_chk not ilike '%late_permit%'          then raise exception 'CHECK missing late_permit'; end if;
    if v_chk not ilike '%early_permit%'         then raise exception 'CHECK missing early_permit'; end if;
    if v_chk not ilike '%attendance_correction%' then raise exception 'CHECK missing attendance_correction'; end if;
    -- الأنواع القديمة محذوفة
    if v_chk ilike '%attendance_permit%' then raise exception 'CHECK still allows old attendance_permit'; end if;
    if v_chk ilike '%generic%'           then raise exception 'CHECK still allows old generic'; end if;
  end $t$$live$,
  'requests_request_type_check يحتوي على 6 أنواع V17 ويستبعد الأنواع القديمة'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- Fixtures — بيانات الاختبار (UUID prefix: a5600000)
-- ════════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity  uuid := 'a5600000-0000-4000-8000-000000000001';
  v_dept_ops uuid := 'a5600000-0000-4000-8000-000000000010';
  v_dept_fin uuid := 'a5600000-0000-4000-8000-000000000011';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-REQ-LE', 'كيان طلبات V17');

  -- قسم تشغيل (slug يبدأ بـ operations) وقسم مالية عادي
  insert into public.departments(id, legal_entity_id, code, name, slug) values
    (v_dept_ops, v_entity, 'operations-main', 'إدارة التشغيل', 'operations-main'),
    (v_dept_fin, v_entity, 'V17-FIN', 'إدارة المالية', 'v17-fin');

  -- 4 مستخدمين: مدير (يمثّل admin)، موظف تشغيل، موظف مالية، تنفيذي
  insert into auth.users(id, email, aud, role) values
    ('a5600000-0000-4000-8000-000000000101', 'v17req-adm@test.local',  'authenticated', 'authenticated'),
    ('a5600000-0000-4000-8000-000000000102', 'v17req-ops@test.local',  'authenticated', 'authenticated'),
    ('a5600000-0000-4000-8000-000000000103', 'v17req-fin@test.local',  'authenticated', 'authenticated'),
    ('a5600000-0000-4000-8000-000000000104', 'v17req-exe@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a5600000-0000-4000-8000-000000000201', 'a5600000-0000-4000-8000-000000000101', 'RQ-ADM', 'مدير الاختبار',    v_dept_fin, 'active', true, false),
    ('a5600000-0000-4000-8000-000000000202', 'a5600000-0000-4000-8000-000000000102', 'RQ-OPS', 'موظف التشغيل',    v_dept_ops, 'active', true, false),
    ('a5600000-0000-4000-8000-000000000203', 'a5600000-0000-4000-8000-000000000103', 'RQ-FIN', 'موظف المالية',    v_dept_fin, 'active', true, false),
    ('a5600000-0000-4000-8000-000000000204', 'a5600000-0000-4000-8000-000000000104', 'RQ-EXE', 'المدير التنفيذي', v_dept_fin, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a5600000-0000-4000-8000-000000000101', 'a5600000-0000-4000-8000-000000000201', 'active'),
    ('a5600000-0000-4000-8000-000000000102', 'a5600000-0000-4000-8000-000000000202', 'active'),
    ('a5600000-0000-4000-8000-000000000103', 'a5600000-0000-4000-8000-000000000203', 'active'),
    ('a5600000-0000-4000-8000-000000000104', 'a5600000-0000-4000-8000-000000000204', 'active');

  -- الأدوار: المدير → employee، التشغيل → employee، المالية → employee، التنفيذي → executive
  insert into public.user_roles(user_id, role_id)
  select 'a5600000-0000-4000-8000-000000000101', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'a5600000-0000-4000-8000-000000000102', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'a5600000-0000-4000-8000-000000000103', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'a5600000-0000-4000-8000-000000000104', id from public.roles where slug='executive';

  -- علاقات الإدارة: كلا الموظفين يتبعان المدير (primary)
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('a5600000-0000-4000-8000-000000000202', 'a5600000-0000-4000-8000-000000000201', 'primary', '2026-01-01'),
    ('a5600000-0000-4000-8000-000000000203', 'a5600000-0000-4000-8000-000000000201', 'primary', '2026-01-01');
end
$fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ════════════════════════════════════════════════════════════════════════════════
-- 3. resolve_request_approver — موظف مالية (غير تشغيل) → المدير المباشر
-- ════════════════════════════════════════════════════════════════════════════════

select is(
  public.resolve_request_approver('a5600000-0000-4000-8000-000000000203'::uuid, '2026-07-01'::date),
  'a5600000-0000-4000-8000-000000000201'::uuid,
  'موظف المالية → المدير المباشر (لا يذهب للتنفيذي)'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 4. resolve_request_approver — موظف تشغيل → التنفيذي (V17 §1.2)
-- ════════════════════════════════════════════════════════════════════════════════

select is(
  public.resolve_request_approver('a5600000-0000-4000-8000-000000000202'::uuid, '2026-07-01'::date),
  'a5600000-0000-4000-8000-000000000204'::uuid,
  'موظف التشغيل → المدير التنفيذي (V17 §1.2 routing)'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 5. resolve_request_approver — موظف بلا manager_relation → null
-- ════════════════════════════════════════════════════════════════════════════════

select is(
  public.resolve_request_approver('a5600000-0000-4000-8000-000000000204'::uuid, '2026-07-01'::date),
  null::uuid,
  'موظف بلا علاقة إدارة → null'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 6-8. submit_request: 3 أنواع V17 جديدة مقبولة
-- ════════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a5600000-0000-4000-8000-000000000103');
set local role authenticated;

select lives_ok(
  $$select public.submit_request(
    'late_permit', null,
    'a5600000-0000-4000-8000-000000000201',
    'إذن تأخير', 'موعد طبي',
    '{"permitDate":"2026-08-01","minutes":30}'::jsonb
  )$$,
  'submit_request يقبل النوع V17: late_permit'
);

select lives_ok(
  $$select public.submit_request(
    'early_permit', null,
    'a5600000-0000-4000-8000-000000000201',
    'إذن انصراف', 'اجتماع خارجي',
    '{"permitDate":"2026-08-02","minutes":60}'::jsonb
  )$$,
  'submit_request يقبل النوع V17: early_permit'
);

select lives_ok(
  $$select public.submit_request(
    'attendance_correction', null,
    'a5600000-0000-4000-8000-000000000201',
    'تصحيح حضور', 'نسيت تسجيل الحضور',
    '{"correctionDate":"2026-07-20","correctionType":"check_in","correctedTime":"08:30"}'::jsonb
  )$$,
  'submit_request يقبل النوع V17: attendance_correction'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 9-10. submit_request: الأنواع القديمة مرفوضة
-- ════════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.submit_request(
    'attendance_permit', null,
    'a5600000-0000-4000-8000-000000000201',
    'إذن حضور قديم', 'سبب', '{}'::jsonb
  )$$,
  '22023', null,
  'submit_request يرفض النوع القديم attendance_permit'
);

select throws_ok(
  $$select public.submit_request(
    'generic', null,
    'a5600000-0000-4000-8000-000000000201',
    'طلب عام قديم', 'سبب', '{}'::jsonb
  )$$,
  '22023', null,
  'submit_request يرفض النوع القديم generic'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 11. submit_request: منع الموافقة الذاتية
-- ════════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.submit_request(
    'late_permit', null,
    'a5600000-0000-4000-8000-000000000203',
    'إذن لنفسي', 'سبب',
    '{"permitDate":"2026-08-05","minutes":15}'::jsonb
  )$$,
  '42501', null,
  'submit_request يمنع الموافقة الذاتية (manager = requester)'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 12. submit_my_request: موظف مالية → ينجح (يستخدم resolve_request_approver تلقائياً)
-- ════════════════════════════════════════════════════════════════════════════════

select lives_ok(
  format($$select public.submit_my_request(
    'late_permit',
    'إذن تأخير تلقائي',
    'موعد شخصي',
    '{"permitDate":"%s","minutes":45}'::jsonb
  )$$, to_char((now() at time zone 'Africa/Cairo')::date + 1, 'YYYY-MM-DD')),
  'submit_my_request late_permit ينجح لموظف مالية'
);

-- ════════════════════════════════════════════════════════════════════════════════
-- 13-14. submit_my_request: الأنواع القديمة مرفوضة
-- ════════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.submit_my_request(
    'attendance_permit',
    'إذن حضور قديم',
    'سبب ما',
    '{}'::jsonb
  )$$,
  '22023', null,
  'submit_my_request يرفض النوع القديم attendance_permit'
);

select throws_ok(
  $$select public.submit_my_request(
    'generic',
    'طلب عام قديم',
    'سبب ما',
    '{}'::jsonb
  )$$,
  '22023', null,
  'submit_my_request يرفض النوع القديم generic'
);

reset role;
select * from finish();
rollback;
