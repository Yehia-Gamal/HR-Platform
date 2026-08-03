-- 0098: V25 — سير عمل إجازة بخطوتين (مدير → HR) + تجاوز المدير بعد 12 ساعة
-- يثبت أن طلبات الإجازة تُنشأ وفق تعريف leave_approval_v1 (خطوة المدير المباشر
-- بمهلة 12 ساعة ثم HR)، وأن decide_request:
--   1) ينتقل بين الخطوات بالترتيب: approved step1 → active step2 → approved.
--   2) يسمح لـ HR باعتماد الخطوة الأولى بعد انتهاء مهلة المدير وإكمال الطلب مباشرة
--      (تجاوز — الخطوة الثانية اعتماد تلقائي موثّق).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(43);

-- =====================================================================
-- 1. تعريف سير العمل leave_approval_v1 (هيكلة البذر من 0253)
-- =====================================================================
select ok(
  exists(select 1 from public.workflow_definitions where code = 'leave_approval_v1'),
  'تعريف leave_approval_v1 مبدوء'
);

select is(
  (select version from public.workflow_definitions where code = 'leave_approval_v1'),
  1, 'version = 1'
);

select is(
  (select request_type from public.workflow_definitions where code = 'leave_approval_v1'),
  'leave', 'request_type = leave'
);

select ok(
  (select is_active from public.workflow_definitions where code = 'leave_approval_v1'),
  'التعريف مفعّل'
);

select ok(
  (select is_default from public.workflow_definitions where code = 'leave_approval_v1'),
  'التعريف افتراضي للإجازات'
);

select ok(
  (select auto_escalate from public.workflow_definitions where code = 'leave_approval_v1'),
  'التصعيد التلقائي مفعّل'
);

select is(
  (select default_due_hours from public.workflow_definitions where code = 'leave_approval_v1'),
  12, 'المهلة الافتراضية 12 ساعة'
);

select is(
  (select config->>'bypassRole' from public.workflow_definitions where code = 'leave_approval_v1'),
  'hr-manager', 'config.bypassRole = hr-manager'
);

select is(
  ((select config from public.workflow_definitions where code = 'leave_approval_v1')->>'bypassAfterHours')::integer,
  12, 'config.bypassAfterHours = 12'
);

-- =====================================================================
-- 2. خطوات التعريف: المدير المباشر ثم HR
-- =====================================================================
select is(
  (select count(*)::integer
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1'),
  2, 'خطوتان في تعريف الإجازة'
);

select is(
  (select ws.approver_type
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  'direct_manager', 'الخطوة 1: المدير المباشر'
);

select is(
  (select ws.sla_hours
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  12, 'الخطوة 1: مهلة 12 ساعة'
);

select is(
  (select ws.approver_permission
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  'requests.approve', 'الخطوة 1: صلاحية الموافقة على الطلبات'
);

select ok(
  (select not ws.is_optional
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  'الخطوة 1 إلزامية'
);

select ok(
  (select ws.allow_delegate
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 1),
  'الخطوة 1 تسمح بالتفويض'
);

select is(
  (select ws.approver_type
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  'role', 'الخطوة 2: اعتماد حسب الدور'
);

select is(
  (select ws.approver_role_slug
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  'hr-manager', 'الخطوة 2: دور hr-manager'
);

select is(
  (select ws.approver_permission
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  'requests.approve', 'الخطوة 2: صلاحية الموافقة على الطلبات'
);

-- =====================================================================
-- 3. decide_request — البنية والمنح ومنطق التجاوز
-- =====================================================================
select has_function(
  'public', 'decide_request', array['uuid','text','text'],
  'decide_request RPC موجود'
);

select ok(
  has_function_privilege('authenticated', p.oid, 'EXECUTE'),
  'authenticated يستطيع تنفيذ decide_request'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='decide_request' limit 1;

select ok(
  not has_function_privilege('anon', p.oid, 'EXECUTE'),
  'anon لا يستطيع تنفيذ decide_request'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='decide_request' limit 1;

select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='decide_request' and pronamespace='public'::regnamespace;
    if v_src not ilike '%current_has_active_role%'
       or v_src not ilike '%due_at < now()%'
       or v_src not ilike '%hr-specialist%' then
      raise exception 'منطق تجاوز مهلة المدير (bypass) غير موجود في decide_request';
    end if;
  end $t$$live$,
  'decide_request يحوي منطق تجاوز المدير بعد انتهاء المهلة'
);

-- =====================================================================
-- 4. بيانات الاختبار (كيان/إدارة/موظف/مدير/HR + دور hr-manager فعّال)
-- =====================================================================
do $fixture$
declare
  v_entity uuid := '96000000-0000-4000-8000-000000000000';
  v_dept   uuid := '96000000-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, 'V25-WF-LE', 'كيان سير العمل V25');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, 'V25-WF-D', 'إدارة سير العمل V25');

  insert into auth.users(id, email, aud, role) values
    ('96000000-0000-4000-8000-000000000101', 'wf-emp@test.local', 'authenticated', 'authenticated'),
    ('96000000-0000-4000-8000-000000000102', 'wf-mgr@test.local', 'authenticated', 'authenticated'),
    ('96000000-0000-4000-8000-000000000103', 'wf-hr@test.local',  'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('96000000-0000-4000-8000-000000000201', '96000000-0000-4000-8000-000000000101',
     'V25-WF-EMP', 'موظف سير العمل V25', v_dept, 'active', true, current_date - 1000),
    ('96000000-0000-4000-8000-000000000202', '96000000-0000-4000-8000-000000000102',
     'V25-WF-MGR', 'مدير سير العمل V25',  v_dept, 'active', true, current_date - 1500),
    ('96000000-0000-4000-8000-000000000203', '96000000-0000-4000-8000-000000000103',
     'V25-WF-HR',  'موظف HR سير العمل V25', v_dept, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status) values
    ('96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000201', 'active'),
    ('96000000-0000-4000-8000-000000000102', '96000000-0000-4000-8000-000000000202', 'active'),
    ('96000000-0000-4000-8000-000000000103', '96000000-0000-4000-8000-000000000203', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('96000000-0000-4000-8000-000000000201', '96000000-0000-4000-8000-000000000202', 'primary', current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select '96000000-0000-4000-8000-000000000103', r.id, now()
    from public.roles r
    where r.slug = 'hr-manager';
end
$fixture$;

-- =====================================================================
-- 5. دوال مساعدة لتبديل سياق المصادقة
-- =====================================================================
create or replace function pg_temp.act_as_0096(p_user uuid) returns void
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
-- 6. المسار السعيد: تقديم → المدير → HR
-- =====================================================================
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000101');
set local role authenticated;

do $emp$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '96000000-0000-4000-8000-000000000202',
    'إجازة سير عمل V25',
    'اختبار خطوتين',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('happy', v_req.id);
end $emp$;

select ok(
  (select workflow_definition_id is not null
   from public.requests where id = (select id from wf_runtime where kind = 'happy')),
  'submit_request يلتقط التعريف الافتراضي للإجازات'
);

select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy')),
  2, 'تُنشأ خطوتان جاريتان عند التقديم'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 1),
  'active', 'الخطوة 1 نشطة عند التقديم'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 2),
  'pending', 'الخطوة 2 معلّقة عند التقديم'
);

select is(
  (select current_step_order from public.workflow_instances
   where request_id = (select id from wf_runtime where kind = 'happy')),
  1, 'نسخة سير العمل الجارية عند الخطوة 1'
);

select throws_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'happy'),
      'approve', 'محاولة ذاتية'
    )
  $live$,
  '42501',
  null,
  'الموظف لا يعتمد طلبه (منع الموافقة الذاتية)'
);

-- المدير المباشر يعتمد الخطوة 1
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000102');

select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'happy'),
      'approve', 'موافقة المدير المباشر'
    )
  $live$,
  'المدير المباشر يعتمد الخطوة 1'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 1),
  'approved', 'الخطوة 1 معتمدة'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 2),
  'active', 'الخطوة 2 صارت نشطة'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'happy')),
  'in_review', 'الطلب قيد المراجعة بعد اعتماد المدير'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'happy')),
  'pending', 'الطلب ما زال معلّقاً حتى إتمام الخطوات'
);

-- HR يعتمد الخطوة 2
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000103');

select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'happy'),
      'approve', 'اعتماد HR النهائي'
    )
  $live$,
  'HR يعتمد الخطوة 2'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'happy')),
  'approved', 'الطلب معتمد بعد الخطوة 2'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'happy')),
  'completed', 'سير العمل مكتمل'
);

select is(
  (select status from public.workflow_instances
   where request_id = (select id from wf_runtime where kind = 'happy')),
  'completed', 'نسخة سير العمل اكتملت'
);

-- =====================================================================
-- 7. تجاوز المدير: HR يعتمد الخطوة 1 المنتهية فيُكمل الطلب مباشرة
-- =====================================================================
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000101');

do $emp2$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '96000000-0000-4000-8000-000000000202',
    'إجازة تجاوز V25',
    'اختبار تجاوز مهلة المدير',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('bypass', v_req.id);
end $emp2$;

select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'bypass')),
  2, 'طلب التجاوز يُنشأ بخطوتين أيضاً'
);

-- انتهاء مهلة الخطوة 1 (12 ساعة مرت دون رد المدير)
reset role;
update public.request_steps
   set due_at = now() - interval '1 hour'
 where request_id = (select id from wf_runtime where kind = 'bypass')
   and step_order = 1;

-- HR يقرر على الخطوة 1 المنتهية → تجاوز مباشر
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000103');
set local role authenticated;

select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'bypass'),
      'approve', 'تجاوز مهلة المدير'
    )
  $live$,
  'HR يعتمد الخطوة 1 بعد انتهاء المهلة (تجاوز)'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'bypass')),
  'approved', 'الطلب اكتمل مباشرة بالتجاوز'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'bypass') and step_order = 2),
  'approved', 'الخطوة 2 اعتماد تلقائي ضمن التجاوز'
);

select is(
  (select comment from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'bypass') and step_order = 2),
  'اعتماد تلقائي — تجاوز مهلة المدير',
  'تعليق الخطوة 2 يوثّق التجاوز'
);

select ok(
  exists(
    select 1 from public.request_actions
    where request_id = (select id from wf_runtime where kind = 'bypass')
      and request_step_id is not null
      and comment = 'اعتماد تلقائي — تجاوز مهلة المدير'
  ),
  'إجراء تدقيق يسجّل الاعتماد التلقائي للخطوة 2'
);

reset role;
select * from finish();
rollback;
