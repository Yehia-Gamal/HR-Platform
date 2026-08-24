-- =====================================================================
-- 0465: اختبار إصلاح طوفان التصعيد
-- ---------------------------------------------------------------------
-- يثبت: (1) أول تجاوز لمهلة الخطوة 1 يصعّد ويفعّل الخطوة 2 ويشعّر مرة،
-- (2) التشغيل الثاني المباشر للـ cron لا يعالج شيئاً (الخنق 24س)،
-- (3) إشعار واحد فقط لأبو عمار وفعل تصعيد واحد مسجّل.
-- كل شيء ضمن معاملة تُلغى.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

do $fixture$
declare
  v_le   uuid := 'b4650000-0000-4000-8000-000000000001';
  v_dept uuid := 'b4650000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities(id, code, name) values(v_le,'F465-LE','كيان 0465');
  insert into public.departments(id, legal_entity_id, code, name) values(v_dept,v_le,'F465-D','إدارة 0465');

  insert into auth.users(id,email,aud,role) values
    ('b4650000-0000-4000-8000-000000000101','f465-emp@test.local','authenticated','authenticated'),
    ('b4650000-0000-4000-8000-000000000102','f465-mgr@test.local','authenticated','authenticated'),
    ('b4650000-0000-4000-8000-000000000103','f465-ops@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('b4650000-0000-4000-8000-000000000201','b4650000-0000-4000-8000-000000000101','F465-E','موظف 0465',v_dept,'active',true,current_date-100),
    ('b4650000-0000-4000-8000-000000000202','b4650000-0000-4000-8000-000000000102','F465-M','مدير 0465',v_dept,'active',true,current_date-200),
    ('b4650000-0000-4000-8000-000000000203','b4650000-0000-4000-8000-000000000103','F465-O','أبو عمار 0465',v_dept,'active',true,current_date-300);

  insert into public.profiles(id,employee_id,status) values
    ('b4650000-0000-4000-8000-000000000101','b4650000-0000-4000-8000-000000000201','active'),
    ('b4650000-0000-4000-8000-000000000102','b4650000-0000-4000-8000-000000000202','active'),
    ('b4650000-0000-4000-8000-000000000103','b4650000-0000-4000-8000-000000000203','active');

  insert into public.manager_relations(employee_id,manager_employee_id,relation_type)
  values('b4650000-0000-4000-8000-000000000201','b4650000-0000-4000-8000-000000000202','primary',current_date);

  insert into public.user_roles(user_id, role_id)
  select 'b4650000-0000-4000-8000-000000000103', id from public.roles where slug='operations-manager-1';

  -- طلب بخطوتين: خطوة 1 نشطة انتهت مهلتها، خطوة 2 معلّقة
  insert into public.requests(id,request_type,employee_id,manager_employee_id,status,workflow_status,title)
  values('b4650000-0000-4000-8000-000000000301','mission',
         'b4650000-0000-4000-8000-000000000201','b4650000-0000-4000-8000-000000000202',
         'pending','submitted','مأمورية اختبار الطوفان');

  insert into public.request_steps(id,request_id,step_order,name_ar,step_type,status,assignee_employee_id,sla_hours,due_at,escalation_deadline)
  values('b4650000-0000-4000-8000-000000000311','b4650000-0000-4000-8000-000000000301',1,'المدير المباشر','approval','active',
         'b4650000-0000-4000-8000-000000000202',2, now()-interval '10 minutes', now()-interval '10 minutes');
  insert into public.request_steps(id,request_id,step_order,name_ar,step_type,status,assignee_role_slug,sla_hours)
  values('b4650000-0000-4000-8000-000000000312','b4650000-0000-4000-8000-000000000301',2,'مدير عمليات 1','approval','pending',
         'operations-manager-1',48);
end $fixture$;

select set_config('request.jwt.claims','{"role":"service_role"}',true);

-- ① التشغيل الأول: يصعّد طلباً واحداً
select is(public.process_request_sla(50), 1, '① أول تشغيل يعالج الطلب الواحد');

select is((select status from public.request_steps where id='b4650000-0000-4000-8000-000000000311'),
          'escalated','① الخطوة 1 صارت escalated');

select is((select status from public.request_steps where id='b4650000-0000-4000-8000-000000000312'),
          'active','① الخطوة 2 نشطة لأبو عمار');

-- ② الخنق: مهلة الخطوة 1 أصبحت مستقبلاً (+24س) وليست في الماضي
select ok(
  (select escalation_deadline from public.request_steps where id='b4650000-0000-4000-8000-000000000311') > now(),
  '② مهلة الخطوة 1 خُنقت إلى المستقبل (لا إعادة اختيار فورية)');

-- ③ التشغيل الثاني الفوري: لا يعالج شيئاً — هذا ما كان يولّد الطوفان قبل 0465
select is(public.process_request_sla(50), 0, '③ التشغيل الثاني الفوري لا يعالج شيئاً (الخنق يعمل)');

-- ④ إشعار واحد فقط لأبو عمار وفعل تصعيد واحد
select is((select count(*)::int from public.notifications
           where recipient_employee_id='b4650000-0000-4000-8000-000000000203'
             and entity_id='b4650000-0000-4000-8000-000000000301'),
          1, '④ إشعار تصعيد واحد فقط لأبو عمار');

select is((select count(*)::int from public.request_actions
           where request_id='b4650000-0000-4000-8000-000000000301' and action='escalate'),
          1, '④ فعل تصعيد واحد فقط في السجل');

select * from finish();
rollback;
