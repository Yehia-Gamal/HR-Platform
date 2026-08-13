-- 0111: V25.3 — لا يوجد تجاوز زمني (72 ساعة) لصلاحية HR.
-- يثبت أن انتهاء مهلة الخطوة وحده لا يفتح باب الاعتماد لـ HR؛ الصلاحية
-- مرحلية بصرامة: HR لا يعتمد إلا عندما تكون الخطوة 3 (hr-manager) هي
-- النشطة فعلاً، وذلك بعد تصعيد process_request_sla فقط (1→2 ثم 2→3).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(25);

-- =====================================================================
-- 1. تعريف سير العمل leave_approval_v1 (HR = الخطوة 3)
-- =====================================================================
select ok(
  exists(select 1 from public.workflow_definitions where code = 'leave_approval_v1'),
  'تعريف leave_approval_v1 متاح'
);

select is(
  (select count(*)::integer
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1'),
  3, 'ثلاث خطوات في سير الإجازة'
);

select is(
  (select ws.approver_type
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  'direct_manager', 'الخطوة 1: المدير المباشر'
);

select is(
  (select ws.approver_role_slug
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 3),
  'hr-manager', 'الخطوة 3: hr-manager'
);

-- =====================================================================
-- 2. decide_request — الصلاحية المرحلية (HR من الخطوة 3 فما فوق)
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='decide_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%v_current_step >= 3%'
       or v_src not ilike '%hr-specialist%'
       or v_src not ilike '%(status = ''active'') desc%' then
      raise exception 'منطق الصلاحية المرحلية (HR من الخطوة 3) غير موجود في decide_request';
    end if;
  end $t$$live$,
  'decide_request يقصّر HR على الخطوة 3 فما فوق'
);

-- =====================================================================
-- 3. بيانات الاختبار (كيان/إدارة/موظف/مدير/أوبريشن/HR)
-- =====================================================================
do $fixture$
declare
  v_entity uuid := '97000000-0000-4000-8000-000000000000';
  v_dept   uuid := '97000000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, 'V25-0111-LE', 'كيان 0111 V25');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, 'V25-0111-D', 'إدارة 0111 V25');

  insert into auth.users(id, email, aud, role) values
    ('97000000-0000-4000-8000-000000000101', 'o111-emp@test.local', 'authenticated', 'authenticated'),
    ('97000000-0000-4000-8000-000000000102', 'o111-mgr@test.local', 'authenticated', 'authenticated'),
    ('97000000-0000-4000-8000-000000000103', 'o111-ops@test.local', 'authenticated', 'authenticated'),
    ('97000000-0000-4000-8000-000000000104', 'o111-hr@test.local',  'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('97000000-0000-4000-8000-000000000201', '97000000-0000-4000-8000-000000000101',
     'V25-0111-EMP', 'موظف 0111 V25', v_dept, 'active', true, current_date - 1000),
    ('97000000-0000-4000-8000-000000000202', '97000000-0000-4000-8000-000000000102',
     'V25-0111-MGR', 'مدير 0111 V25',  v_dept, 'active', true, current_date - 1500),
    ('97000000-0000-4000-8000-000000000203', '97000000-0000-4000-8000-000000000103',
     'V25-0111-OPS', 'مسؤول عمليات 0111', v_dept, 'active', true, current_date - 1200),
    ('97000000-0000-4000-8000-000000000204', '97000000-0000-4000-8000-000000000104',
     'V25-0111-HR',  'موظف HR 0111',   v_dept, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status) values
    ('97000000-0000-4000-8000-000000000101', '97000000-0000-4000-8000-000000000201', 'active'),
    ('97000000-0000-4000-8000-000000000102', '97000000-0000-4000-8000-000000000202', 'active'),
    ('97000000-0000-4000-8000-000000000103', '97000000-0000-4000-8000-000000000203', 'active'),
    ('97000000-0000-4000-8000-000000000104', '97000000-0000-4000-8000-000000000204', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('97000000-0000-4000-8000-000000000201', '97000000-0000-4000-8000-000000000202', 'primary', current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select '97000000-0000-4000-8000-000000000103', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-officer';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '97000000-0000-4000-8000-000000000104', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'hr-manager';
end
$fixture$;

-- =====================================================================
-- 4. دوال مساعدة لتبديل سياق المصادقة
-- =====================================================================
create or replace function pg_temp.act_as_0111(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

create temporary table wf_runtime(kind text primary key, id uuid);
grant select, insert, update on wf_runtime to authenticated;

-- =====================================================================
-- 5. التقديم: الخطوة 1 نشطة
-- =====================================================================
select pg_temp.act_as_0111('97000000-0000-4000-8000-000000000101');
set local role authenticated;

do $emp$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '97000000-0000-4000-8000-000000000202',
    'إجازة منع التجاوز الزمني 0111',
    'اختبار منع تجاوز HR الزمني',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('hr_bypass', v_req.id);
end $emp$;

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 1),
  'active', 'الخطوة 1 نشطة عند التقديم'
);

-- =====================================================================
-- 6. انتهاء المهلة وحده لا يفتح باب HR (لا تجاوز زمني)
-- =====================================================================
reset role;
update public.request_steps set escalation_deadline = now() - interval '1 day'
where request_id = (select id from wf_runtime where kind = 'hr_bypass')
  and status in ('active', 'escalated');

select pg_temp.act_as_0111('97000000-0000-4000-8000-000000000104');
set local role authenticated;
select throws_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'hr_bypass'),
      'approve', 'محاولة HR بعد انتهاء مهلة المدير'
    )
  $live$,
  '42501',
  null,
  'انتهاء مهلة الخطوة 1 وحده لا يخوّل HR (لا تجاوز زمني — الخطوة 1 ما زالت نشطة)'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'pending', 'الطلب يبقى pending بعد رفض المحاولة الزمنية'
);

-- =====================================================================
-- 7. التصعيد 1→2: HR ما زال مرفوضاً في مرحلة الأوبريشن
-- =====================================================================
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  1, 'التصعيد الأول ينشّط الخطوة 2'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 2),
  'active', 'الخطوة 2 صارت نشطة للأوبريشن'
);

select is(
  (select assignee_employee_id from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 2),
  '97000000-0000-4000-8000-000000000203', 'الخطوة 2 أُسندت لأول موظف عمليات فعّال'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'awaiting_operator', 'الطلب بانتظار قرار الأوبريشن'
);

select pg_temp.act_as_0111('97000000-0000-4000-8000-000000000104');
set local role authenticated;
select throws_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'hr_bypass'),
      'approve', 'محاولة HR في مرحلة الأوبريشن'
    )
  $live$,
  '42501',
  null,
  'HR لا يعتمد في الخطوة 2 (يُقيَّد للخطوة 3 فما فوق) حتى بعد تصعيد مهلة المدير'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'pending', 'الطلب يبقى pending بعد رفض HR في المرحلة الثانية'
);

-- =====================================================================
-- 8. التصعيد 2→3: HR يظهر عند الخطوة 3 فقط ثم يعتمد
-- =====================================================================
reset role;
update public.request_steps set escalation_deadline = null
where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 1;
update public.request_steps set escalation_deadline = now() - interval '1 hour'
where request_id = (select id from wf_runtime where kind = 'hr_bypass')
  and step_order = 2 and status = 'active';
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  1, 'التصعيد الثاني ينشّط الخطوة 3 لـ HR'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 3),
  'active', 'الخطوة 3 صارت نشطة'
);

select is(
  (select assignee_employee_id from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 3),
  '97000000-0000-4000-8000-000000000204', 'الخطوة 3 أُسندت لأول موظف HR فعّال'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'escalated', 'الطلب في حالة مُصعَّد بعد وصوله لمرحلة HR'
);

-- HR يعتمد عند الخطوة 3 فقط
select pg_temp.act_as_0111('97000000-0000-4000-8000-000000000104');
set local role authenticated;
select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'hr_bypass'),
      'approve', 'اعتماد HR عند الخطوة 3'
    )
  $live$,
  'HR يعتمد الطلب عند وصوله الخطوة 3 (الطريق الوحيد المشروع)'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'approved', 'الطلب معتمد بقرار HR'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass') and step_order = 3),
  'approved', 'الخطوة 3 سُجّلت كمعتمدة لقرار HR'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'hr_bypass')),
  'completed', 'سير العمل اكتمل بعد القرار'
);

select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'hr_bypass')
     and status = 'approved'),
  1, 'خطوة واحدة فقط سُجّلت معتمدة (الخطوة 3)'
);

-- لا إجراء منسوب للمدير المباشر (لم يعتمد ولم يصعّد بواسطته)
select ok(
  not exists (
    select 1 from public.request_actions
    where request_id = (select id from wf_runtime where kind = 'hr_bypass')
      and actor_employee_id = '97000000-0000-4000-8000-000000000202'
  ),
  'لا إجراء منسوب للمدير المباشر على الطلب'
);

-- إشعار القرار صدر لمقدم الطلب (يُفحص بعد reset role لأن RLS للإشعارات
-- تسمح فقط للمُستلم أو full-access)
reset role;
select ok(
  exists (
    select 1 from public.notifications n
    where n.recipient_employee_id = '97000000-0000-4000-8000-000000000201'
      and n.category = 'request'
  ),
  'إشعار القرار صدر لمقدم الطلب'
);

select * from finish();
rollback;
