-- 0098: سير عمل الإجازة ثنائي الطبقات (leave_approval_v1 بعد 0416)
-- يثبت أن طلبات الإجازة تُنشأ وفق التعريف الافتراضي ثنائي الخطوات
-- (مدير مباشر 2س → أبو عمار operations-manager-1 4س)، وأن decide_request:
--   1) موافقة واحدة تُنهي الطلب (المدير المباشر يعتمد فيُكمل فوراً).
--   2) التصعيد المرحلي (process_request_sla) ينشّط الخطوة الثانية.
--   3) الصلاحية: مدير دائماً / أبو عمار step>=2 / HR غير مقيد (0441).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(58);

-- =====================================================================
-- 1. تعريف سير العمل leave_approval_v1 (بنية 0396)
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
  2, 'المهلة الافتراضية ساعتان (0436)'
);

select is(
  ((select config from public.workflow_definitions where code = 'leave_approval_v1')->'tierHours'->>'manager')::integer,
  2, 'tierHours.manager = 2 ساعات'
);

select is(
  ((select config from public.workflow_definitions where code = 'leave_approval_v1')->'tierHours'->>'operations')::integer,
  2, 'tierHours.operations = 2 ساعات (0436)'
);

select ok(
  ((select config from public.workflow_definitions where code = 'leave_approval_v1')->'tierHours'->>'hr') is null,
  'لا توجد طبقة HR في التعريف (مستويان فقط)'
);

-- =====================================================================
-- 2. خطوات التعريف: مدير مباشر → أوبريشن → HR
-- =====================================================================
select is(
  (select count(*)::integer
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1'),
  3, 'ثلاث خطوات في تعريف الإجازة'
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
  2, 'الخطوة 1: مهلة ساعتين'
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
  (select ws.approver_role_slug
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  'operations-manager-1', 'الخطوة 2: دور مدير التشغيل 1 (أبو عمار)'
);

select is(
  (select ws.sla_hours
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  2, 'الخطوة 2: مهلة ساعتين (0436)'
);

select is(
  (select ws.escalate_after_hours
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 2),
  2, 'الخطوة 2: تُصعَّد بعد ساعتين (0436)'
);

select is(
  (select ws.approver_role_slug
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 3),
  'hr-manager', 'الخطوة 3: دور hr-manager'
);

select is(
  (select ws.sla_hours
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 3),
  48, 'الخطوة 3: مهلة 48 ساعة'
);

select is(
  (select count(*)::integer
   from public.workflow_steps ws
   join public.workflow_definitions wd on wd.id = ws.definition_id
   where wd.code = 'leave_approval_v1' and ws.step_order = 3 and ws.is_active = true),
  0, 'لا خطوة HR فعّالة في التعريف'
);

-- =====================================================================
-- 3. decide_request — البنية والمنح والصلاحية المرحلية
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
    -- 0462: المسار الطبيعي فقط — مدير دائماً / أبو عمار step>=2 أو مهلة
    -- متجاوزة / full_access، وبلا أي تجاوز لـ HR.
    if v_src not ilike '%current_has_active_role%'
       or v_src not ilike '%operations-manager-1%'
       or v_src not ilike '%v_current_step >= 2%'
       or v_src not ilike '%(status = ''active'') desc%'
       or v_src ilike '%hr-manager%' then
      raise exception 'منطق الصلاحية المحدث (المسار الطبيعي — 0462، بلا تجاوز HR) غير موجود في decide_request';
    end if;
  end $t$$live$,
  'decide_request يحوي الصلاحية الطبيعية (مدير دائماً / أبو عمار step>=2 أو مهلة متجاوزة — بلا HR)'
);

-- =====================================================================
-- 4. بيانات الاختبار (كيان/إدارة/موظف/مدير/أوبريشن/HR)
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
    ('96000000-0000-4000-8000-000000000103', 'wf-ops@test.local', 'authenticated', 'authenticated'),
    ('96000000-0000-4000-8000-000000000104', 'wf-hr@test.local',  'authenticated', 'authenticated');

  insert into public.employees(
    id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date
  ) values
    ('96000000-0000-4000-8000-000000000201', '96000000-0000-4000-8000-000000000101',
     'V25-WF-EMP', 'موظف سير العمل V25', v_dept, 'active', true, current_date - 1000),
    ('96000000-0000-4000-8000-000000000202', '96000000-0000-4000-8000-000000000102',
     'V25-WF-MGR', 'مدير سير العمل V25',  v_dept, 'active', true, current_date - 1500),
    ('96000000-0000-4000-8000-000000000203', '96000000-0000-4000-8000-000000000103',
     'V25-WF-OPS', 'مسؤول عمليات V25',     v_dept, 'active', true, current_date - 1200),
    ('96000000-0000-4000-8000-000000000204', '96000000-0000-4000-8000-000000000104',
     'V25-WF-HR',  'موظف HR سير العمل V25', v_dept, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status) values
    ('96000000-0000-4000-8000-000000000101', '96000000-0000-4000-8000-000000000201', 'active'),
    ('96000000-0000-4000-8000-000000000102', '96000000-0000-4000-8000-000000000202', 'active'),
    ('96000000-0000-4000-8000-000000000103', '96000000-0000-4000-8000-000000000203', 'active'),
    ('96000000-0000-4000-8000-000000000104', '96000000-0000-4000-8000-000000000204', 'active');

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('96000000-0000-4000-8000-000000000201', '96000000-0000-4000-8000-000000000202', 'primary', current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select '96000000-0000-4000-8000-000000000103', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'operations-manager-1';
  insert into public.user_roles(user_id, role_id, effective_from)
    select '96000000-0000-4000-8000-000000000104', r.id, now() - interval '10 years'
    from public.roles r where r.slug = 'hr-manager';
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
-- 6. المسار السعيد: تقديم → اعتماد المدير → اكتمال فوري
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
    'اختبار ثلاث طبقات',
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
  2, 'تُنشأ خطوتان جاريتان عند التقديم (مدير ثم أبو عمار)'
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
  (select count(*)::integer from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 3),
  0, 'لا خطوة ثالثة (HR) عند التقديم'
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

-- المدير المباشر يعتمد — موافقة واحدة تُنهي الطلب
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
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'happy')),
  'approved', 'الطلب معتمد فوراً بموافقة واحدة'
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

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy') and step_order = 1),
  'approved', 'الخطوة 1 معتمدة'
);

select is(
  (select count(*)::integer from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'happy')
     and status = 'skipped' and step_order = 2),
  1, 'الخطوة 2 أُغلقت كـ skipped بعد اكتمال الطلب'
);

-- =====================================================================
-- 7. تصعيد المرحلة 2: انتهاء مهلة المدير → أوبريشن يعتمد
-- =====================================================================
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000101');
set local role authenticated;

do $emp2$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '96000000-0000-4000-8000-000000000202',
    'إجازة تصعيد أوبريشن V25',
    'اختبار تصعيد المرحلة الثانية',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('tier2', v_req.id);
end $emp2$;

-- انتهاء مهلة الخطوة 1 → التصعيد ينشّط الخطوة 2 للأوبريشن
reset role;
update public.request_steps set escalation_deadline = now() - interval '1 hour'
where request_id = (select id from wf_runtime where kind = 'tier2')
  and status in ('active', 'escalated');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  1, 'تصعيد المرحلة 2: معالج SLA يصعّد طلباً واحداً'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier2') and step_order = 1),
  'escalated', 'الخطوة 1 أصبحت escalated'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier2') and step_order = 2),
  'active', 'الخطوة 2 صارت نشطة'
);

select is(
  (select assignee_employee_id from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier2') and step_order = 2),
  '96000000-0000-4000-8000-000000000203', 'الخطوة 2 أُسندت لأول موظف عمليات فعّال'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'tier2')),
  'awaiting_operator', 'الطلب بانتظار قرار الأوبريشن'
);

-- الأوبريشن يعتمد (step >= 2)
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000103');
set local role authenticated;

select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'tier2'),
      'approve', 'اعتماد الأوبريشن بعد التصعيد'
    )
  $live$,
  'الأوبريشن يعتمد الطلب المصعَّد (المرحلة 2)'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'tier2')),
  'approved', 'الطلب معتمد بقرار الأوبريشن'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier2') and step_order = 2),
  'approved', 'الخطوة 2 سُجّلت كمعتمدة لقرار الأوبريشن'
);

-- =====================================================================
-- 8. بلا تجاوز HR (0462): محاولة HR في مرحلة أبو عمار تُرفض — المسار
--    الطبيعي وحده هو الفاعل.
-- =====================================================================
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000101');
set local role authenticated;

do $emp3$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '96000000-0000-4000-8000-000000000202',
    'إجازة اعتماد HR V25',
    'اختبار رفض HR في المرحلة الثانية',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('tier3', v_req.id);
end $emp3$;

-- التصعيد الأول: 1→2
reset role;
update public.request_steps set escalation_deadline = now() - interval '1 hour'
where request_id = (select id from wf_runtime where kind = 'tier3')
  and status in ('active', 'escalated');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  1, 'التصعيد الأول ينشّط الخطوة 2'
);

-- HR يحاول الاعتماد في مرحلة أبو عمار — مرفوض (0462 ألغى تجاوز 0441)
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000104');
set local role authenticated;
select throws_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'tier3'),
      'approve', 'محاولة اعتماد HR في مرحلة أبو عمار'
    )
  $live$,
  '42501',
  null,
  'HR لا يعتمد في مرحلة أبو عمار (المسار الطبيعي فقط — 0462)'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'tier3')),
  'pending', 'الطلب يبقى معلقاً بعد رفض محاولة HR'
);

-- إبعاد الطلب المرفوض محاولته عن نطاق معالج SLA كي لا يُحصى في الأقسام التالية
reset role;
update public.request_steps set escalation_deadline = now() + interval '10 years'
where request_id = (select id from wf_runtime where kind = 'tier3');

-- =====================================================================
-- 9. المرحلة النهائية بلا تدخل HR: انتهاء مهلة أبو عمار → تذكير دوري
-- =====================================================================
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000101');
set local role authenticated;

do $emp4$
declare v_req public.requests;
begin
  v_req := public.submit_request(
    'leave',
    null,
    '96000000-0000-4000-8000-000000000202',
    'إجازة تصعيد نهائي V25',
    'اختبار المرحلة النهائية',
    jsonb_build_object('leaveType', 'annual')
  );
  insert into wf_runtime values('tier4', v_req.id);
end $emp4$;

-- التصعيد الأول: 1→2
reset role;
update public.request_steps set escalation_deadline = now() - interval '1 hour'
where request_id = (select id from wf_runtime where kind = 'tier4')
  and status in ('active', 'escalated');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  1, 'التصعيد الأول ينشّط الخطوة 2 (المرحلة النهائية)'
);

-- لا تصعيد بعد الخطوة 2: انتهاء مهلة أبو عمار → تذكير دوري فقط
reset role;
update public.request_steps set escalation_deadline = null
where request_id = (select id from wf_runtime where kind = 'tier4') and step_order = 1;
update public.request_steps set escalation_deadline = now() - interval '1 hour'
where request_id = (select id from wf_runtime where kind = 'tier4')
  and step_order = 2 and status = 'active';
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(
  public.process_request_sla(10),
  0, 'انتهاء مهلة أبو عمار → تذكير دوري، لا تصعيد إضافي'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier4') and step_order = 2),
  'active', 'الخطوة 2 تبقى نشطة بعد التذكير'
);

select is(
  (select assignee_employee_id from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier4') and step_order = 2),
  '96000000-0000-4000-8000-000000000203', 'الخطوة 2 أُسندت لأبو عمار (أول موظف operations-manager-1)'
);

select is(
  (select workflow_status from public.requests
   where id = (select id from wf_runtime where kind = 'tier4')),
  'awaiting_operator', 'الطلب يبقى بانتظار أبو عمار (لا مرحلة ثالثة)'
);

-- أبو عمار يعتمد عند المرحلة النهائية
select pg_temp.act_as_0096('96000000-0000-4000-8000-000000000103');
set local role authenticated;
select lives_ok(
  $live$
    select public.decide_request(
      (select id from wf_runtime where kind = 'tier4'),
      'approve', 'اعتماد أبو عمار النهائي'
    )
  $live$,
  'أبو عمار يعتمد الطلب في المرحلة النهائية'
);

select is(
  (select status from public.requests
   where id = (select id from wf_runtime where kind = 'tier4')),
  'approved', 'الطلب معتمد بقرار أبو عمار'
);

select is(
  (select status from public.request_steps
   where request_id = (select id from wf_runtime where kind = 'tier4') and step_order = 2),
  'approved', 'الخطوة 2 سُجّلت كمعتمدة لقرار أبو عمار'
);

reset role;
select * from finish();
rollback;
