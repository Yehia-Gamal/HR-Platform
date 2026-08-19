-- 0438: أدوات الإجازات والتكليفات — get_leave_types_admin + admin_create_leave_request + grant_weekly_rest_credit_bulk
-- يثبت أن:
--   1) get_leave_types_admin تعرض الأنواع النشطة فقط بترتيب sort_order.
--   2) admin_create_leave_request تحرس بالصلاحية (FORBIDDEN بدونها)،
--      ترفض الرجوع بأثر رجعي/النوع غير المعروف/الموظف غير النشط،
--      تنشئ الطلب بمسار الموافقة المعتاد (المدير من resolve_request_approver)،
--      تُنشئ صف leave_requests (فيُفعَّل حجز الرصيد عبر التريغر)،
--      وتنفّذ العارضة فورياً (approved + skipped + request_actions + audit).
--   3) grant_weekly_rest_credit_bulk تمنح بدل راحة لعدة موظفين دفعة واحدة،
--      تتجاوز غير النشطين، idempotent عبر source_key، وتتحقق من المدخلات.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(24);

-- ═════════════════════════════════════════════════════════════════════
-- Fixture: أشخاص + أقسام (غير operations) + أدوار وصلاحيات
-- ═════════════════════════════════════════════════════════════════════
do $fixture$
declare
  v_perm_id uuid;
  v_role_id uuid;
begin
  insert into auth.users (id, email, aud, role) values
    ('04380000-0000-4000-8000-000000000001', '0438-emp@test.local', 'authenticated', 'authenticated'),
    ('04380000-0000-4000-8000-000000000002', '0438-mgr@test.local', 'authenticated', 'authenticated'),
    ('04380000-0000-4000-8000-000000000003', '0438-hr@test.local',  'authenticated', 'authenticated');

  insert into public.legal_entities (id, code, name)
  values ('04380000-0000-4000-8000-000000000010', '0438-LE', 'كيان اختبار 0438');

  insert into public.departments (id, legal_entity_id, code, name, slug)
  values ('04380000-0000-4000-8000-000000000011', '04380000-0000-4000-8000-000000000010',
          '0438-DEPT', 'قسم اختبار 0438', 'general');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active)
  values
    ('04380000-0000-4000-8000-000000000101', '04380000-0000-4000-8000-000000000001',
     '0438-001', 'موظف اختبار 0438', '04380000-0000-4000-8000-000000000011', 'active', true),
    ('04380000-0000-4000-8000-000000000102', '04380000-0000-4000-8000-000000000002',
     '0438-002', 'مدير اختبار 0438',  '04380000-0000-4000-8000-000000000011', 'active', true),
    ('04380000-0000-4000-8000-000000000103', '04380000-0000-4000-8000-000000000003',
     '0438-003', 'HR اختبار 0438',     '04380000-0000-4000-8000-000000000011', 'active', true),
    ('04380000-0000-4000-8000-000000000104', null,
     '0438-004', 'موظف غير نشط 0438', '04380000-0000-4000-8000-000000000011', 'archived', false);

  insert into public.profiles (id, employee_id, status)
  values
    ('04380000-0000-4000-8000-000000000001', '04380000-0000-4000-8000-000000000101', 'active'),
    ('04380000-0000-4000-8000-000000000002', '04380000-0000-4000-8000-000000000102', 'active'),
    ('04380000-0000-4000-8000-000000000003', '04380000-0000-4000-8000-000000000103', 'active');

  insert into public.manager_relations (
    employee_id, manager_employee_id, relation_type, effective_from, effective_to
  ) values (
    '04380000-0000-4000-8000-000000000101',
    '04380000-0000-4000-8000-000000000102',
    'primary', current_date, null
  );

  insert into public.roles (slug, name_ar, is_system, is_full_access)
  values
    ('employee', 'موظف', true, false),
    ('hr-manager', 'مدير موارد بشرية', true, false)
  on conflict (slug) do nothing;

  insert into public.permissions (code, module, resource, action)
  values ('requests.leave.balance.adjust', 'requests', 'leave', 'balance-adjust')
  on conflict (code) do nothing;

  select id into v_role_id from public.roles where slug = 'hr-manager';
  select id into v_perm_id from public.permissions where code = 'requests.leave.balance.adjust';
  insert into public.role_permissions (role_id, permission_id, scope)
  values (v_role_id, v_perm_id, 'organization')
  on conflict (role_id, permission_id, scope) do nothing;

  insert into public.user_roles (user_id, role_id)
  select '04380000-0000-4000-8000-000000000003', id from public.roles where slug = 'hr-manager'
  on conflict do nothing;

  -- أرصدة افتتاحية كافية: سنوية 30 + عارضة 5 (حجز التريغر يعمل على affects_balance).
  select id into v_perm_id from public.leave_types where code = 'annual';
  select id into v_role_id from public.leave_types where code = 'casual';
  perform public.apply_leave_ledger_entry(
    '04380000-0000-4000-8000-000000000101', v_perm_id, 2030, 'opening', 30,
    '0438-test:opening:annual:2030', null, 'افتتاحي سنوية');
  perform public.apply_leave_ledger_entry(
    '04380000-0000-4000-8000-000000000101', v_role_id, 2030, 'opening', 5,
    '0438-test:opening:casual:2030', null, 'افتتاحي عارضة');
end $fixture$;

-- ═════════════════════════════════════════════════════════════════════
-- 1) get_leave_types_admin — الأنواع النشطة فقط بالترتيب
-- ═════════════════════════════════════════════════════════════════════
select is(
  (select count(*)::int from public.get_leave_types_admin()),
  (select count(*)::int from public.leave_types where is_active = true),
  '(1) get_leave_types_admin ترجع الأنواع النشطة فقط'
);

select is(
  (select min(sort_order)::int from public.get_leave_types_admin() g
    join public.leave_types lt on lt.id = g.id),
  (select min(sort_order)::int from public.leave_types where is_active = true),
  '(2) النوع الأول في الكتالوج هو الأقل sort_order'
);

select is(
  (select count(*)::int from public.get_leave_types_admin()
    where code = 'weekly_rest_comp' and affects_balance = false),
  1,
  '(3) بدل الراحة الأسبوعي ظاهر في الكتالوج بلا أثر على الرصيد'
);

-- ═════════════════════════════════════════════════════════════════════
-- 2) admin_create_leave_request — البوابة + التحقق من المدخلات
-- ═════════════════════════════════════════════════════════════════════
-- Persona: الموظف العادي (بدون صلاحية) — ممنوع
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"04380000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '04380000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000101', 'annual',
    '2030-06-01', '2030-06-03', 'اختبار البوابة')$$,
  '42501', 'FORBIDDEN',
  '(4) الموظف بدون صلاحية يُرفض بـ FORBIDDEN'
);

select throws_ok(
  $$select public.grant_weekly_rest_credit_bulk(
    array['04380000-0000-4000-8000-000000000101'::uuid], '2030-06-06', 1)$$,
  '42501', 'FORBIDDEN',
  '(5) المنح الجماعي بدون صلاحية يُرفض بـ FORBIDDEN'
);

-- Persona: HR (requests.leave.balance.adjust @ organization) — مسموح
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"04380000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '04380000-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.admin_create_leave_request(
    null::uuid, 'annual', '2030-06-01', '2030-06-03', 'بدون موظف')$$,
  '22023', 'EMPLOYEE_REQUIRED',
  '(6) موظف مفقود → EMPLOYEE_REQUIRED'
);

select throws_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000104', 'annual',
    '2030-06-01', '2030-06-03', 'موظف غير نشط')$$,
  'P0002', 'EMPLOYEE_NOT_FOUND',
  '(7) موظف غير نشط → EMPLOYEE_NOT_FOUND'
);

select throws_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000101', 'annual',
    '2000-06-01', '2000-06-03', 'بأثر رجعي')$$,
  '22023', 'retroactive leave requests are not allowed',
  '(8) طلب بأثر رجعي يُرفض'
);

select throws_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000101', 'unknown_type',
    '2030-06-01', '2030-06-03', 'نوع غير معروف')$$,
  '22023', 'unsupported leave type',
  '(9) نوع إجازة غير معروف يُرفض'
);

-- ═════════════════════════════════════════════════════════════════════
-- 3) admin_create_leave_request — إنشاء سنوية: مسار الموافقة المعتاد
-- ═════════════════════════════════════════════════════════════════════
select lives_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000101', 'annual',
    '2030-06-01', '2030-06-03', 'إجازة سنوية اختبارية')$$,
  '(10) إنشاء إجازة سنوية بدل الموظف ينجح'
);

select is(
  (select count(*)::int from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-01' and lr.end_date = '2030-06-03'
      and lr.days_count = 3),
  1,
  '(11) صف leave_requests أُنشئ بالأيام الصحيحة (3)'
);

select is(
  (select r.workflow_status from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-01'),
  'submitted',
  '(12) الطلب دخل مسار الموافقة (submitted)'
);

select is(
  (select r.manager_employee_id from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-01'),
  '04380000-0000-4000-8000-000000000102',
  '(13) المدير المسؤول = المدير المباشر من الهيكل'
);

select is(
  (select count(*)::int from public.leave_ledger_entries
    where employee_id = '04380000-0000-4000-8000-000000000101'
      and entry_type = 'reserve'
      and source_key like 'leave:reserve:%'),
  1,
  '(14) حجز الرصيد السنوي فُعّل عبر تريغر leave_requests'
);

-- ═════════════════════════════════════════════════════════════════════
-- 4) admin_create_leave_request — عارضة: تنفيذ فوري بلا موافقة
-- ═════════════════════════════════════════════════════════════════════
select lives_ok(
  $$select public.admin_create_leave_request(
    '04380000-0000-4000-8000-000000000101', 'casual',
    '2030-06-10', '2030-06-10', 'إجازة عارضة — تنفيذ مباشر')$$,
  '(15) إنشاء عارضة بدل الموظف ينجح'
);

select is(
  (select r.status from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-10'),
  'approved',
  '(16) العارضة نُفذت فورياً (approved)'
);

select is(
  (select r.workflow_status from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-10'),
  'completed',
  '(17) سير العمل اكتمل (completed)'
);

select is(
  (select count(*)::int from public.request_actions ra
    join public.requests r on r.id = ra.request_id
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = '04380000-0000-4000-8000-000000000101'
      and lr.start_date = '2030-06-10' and ra.action = 'system'),
  1,
  '(18) سُجل إجراء التنفيذ المباشر في request_actions'
);

select is(
  (select count(*)::int from public.audit_events
    where event_type like 'leave.%' and target_table = 'requests'),
  3,
  '(19) سُجلت أحداث تدقيق للطلبات الإدارية (2 إنشاء + 1 تنفيذ فوري)'
);

-- ═════════════════════════════════════════════════════════════════════
-- 5) grant_weekly_rest_credit_bulk — منح جماعي + idempotency + تحقق
-- ═════════════════════════════════════════════════════════════════════
select is(
  (select public.grant_weekly_rest_credit_bulk(
    array[
      '04380000-0000-4000-8000-000000000101'::uuid,
      '04380000-0000-4000-8000-000000000104'::uuid
    ],
    '2030-06-14', 2)),
  1,
  '(20) المنح الجماعي يعيد عدد النشطين الممنوحين فقط (يتجاوز غير النشط)'
);

select is(
  (select count(*)::int from public.leave_ledger_entries
    where employee_id = '04380000-0000-4000-8000-000000000101'
      and entry_type = 'credit'
      and source_key like 'weekly-rest:manual:%2030-06-1%'),
  2,
  '(21) قيدا رصيد أُنشئا (يومان × موظف نشط واحد)'
);

select is(
  (select count(*)::int from public.leave_ledger_entries
    where employee_id = '04380000-0000-4000-8000-000000000104'
      and entry_type = 'credit'),
  0,
  '(22) الموظف غير النشط لم يُمنح شيئاً'
);

select lives_ok(
  $$select public.grant_weekly_rest_credit_bulk(
    array['04380000-0000-4000-8000-000000000101'::uuid],
    '2030-06-14', 2)$$,
  '(23) إعادة المنح لنفس الأيام لا تفشل'
);

select is(
  (select count(*)::int from public.leave_ledger_entries
    where employee_id = '04380000-0000-4000-8000-000000000101'
      and entry_type = 'credit'
      and source_key like 'weekly-rest:manual:%2030-06-1%'),
  2,
  '(24) لا تكرار: القيود نفسها بلا ازدواج (idempotent عبر source_key)'
);

select finish();
rollback;