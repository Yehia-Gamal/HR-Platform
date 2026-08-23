-- 0452: إعادة رفع الطلبات المرفوضة بعد تعديلها
-- يثبت أن:
--   1) المالك يعدّل مأمورية مرفوضة ويعيد رفعها: pending/submitted + تصفير
--      القرار + خطوات جديدة (الأولى active) + نسخة سير جديدة + توثيق submit.
--   2) المدير المباشر يُشعَّر «طلب مُعدّل بانتظار مراجعتك».
--   3) غير المالك → FORBIDDEN؛ طلب pending أو معتمد → رفض؛ عنوان قصير → رفض.
--   4) canResubmit يظهر للمالك على المرفوض ولا يظهر للمدير ولا على pending.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(14);

-- ═════════════════════════════════════════════════════════════════════
-- Fixtures: مالك + مدير + تنفيذي + تعريف سير مأمورية بخطوتين
-- ═════════════════════════════════════════════════════════════════════
insert into auth.users (id, email, aud, role)
values
  ('04520000-0000-4000-8000-000000000001', 'tst-0452-owner@test.local', 'authenticated', 'authenticated'),
  ('04520000-0000-4000-8000-000000000002', 'tst-0452-mgr@test.local',  'authenticated', 'authenticated'),
  ('04520000-0000-4000-8000-000000000003', 'tst-0452-exec@test.local', 'authenticated', 'authenticated'),
  ('04520000-0000-4000-8000-000000000004', 'tst-0452-oth@test.local',  'authenticated', 'authenticated');

insert into public.employees (id, employee_code, full_name_ar, is_active, status)
values
  ('04520000-0000-4000-8000-000000000101', 'TST-0452-OWN',  'مالك اختبار 0452',   true, 'active'),
  ('04520000-0000-4000-8000-000000000102', 'TST-0452-MGR',  'مدير اختبار 0452',   true, 'active'),
  ('04520000-0000-4000-8000-000000000103', 'TST-0452-EXEC', 'تنفيذي اختبار 0452', true, 'active'),
  ('04520000-0000-4000-8000-000000000104', 'TST-0452-OTH',  'غريب اختبار 0452',   true, 'active');

insert into public.profiles (id, employee_id)
values
  ('04520000-0000-4000-8000-000000000001', '04520000-0000-4000-8000-000000000101'),
  ('04520000-0000-4000-8000-000000000002', '04520000-0000-4000-8000-000000000102'),
  ('04520000-0000-4000-8000-000000000003', '04520000-0000-4000-8000-000000000103'),
  ('04520000-0000-4000-8000-000000000004', '04520000-0000-4000-8000-000000000104');

insert into public.roles (slug, name_ar, is_system, is_full_access)
values ('executive-director', 'المدير التنفيذي', true, true)
on conflict (slug) do nothing;

insert into public.user_roles (user_id, role_id)
select '04520000-0000-4000-8000-000000000003', id
from public.roles where slug = 'executive-director'
on conflict do nothing;

insert into public.manager_relations (
  employee_id, manager_employee_id, relation_type, effective_from, effective_to
) values (
  '04520000-0000-4000-8000-000000000101',
  '04520000-0000-4000-8000-000000000102',
  'primary', current_date, null
);

-- نستخدم تعريف سير المأمورية الافتراضي الموجود (قيد فريد على default لكل نوع)

-- طلب مأمورية مرفوض (بخطوات قديمة + قرار)
insert into public.requests (
  id, request_type, employee_id, manager_employee_id, workflow_definition_id,
  status, workflow_status, title, reason, payload, decided_at, decided_by, current_step_order
)
select
  '04520000-0000-4000-8000-000000000201', 'mission',
  '04520000-0000-4000-8000-000000000101',
  '04520000-0000-4000-8000-000000000102',
  wd.id, 'rejected', 'completed', 'مأمورية قديمة', 'سبب قديم مرفوض',
  '{"startDate":"2026-09-01","endDate":"2026-09-02","location":"القاهرة"}'::jsonb,
  now(), '04520000-0000-4000-8000-000000000102', 2
from public.workflow_definitions wd
where wd.request_type = 'mission' and wd.is_default = true and wd.is_active = true
limit 1;

insert into public.request_steps (
  request_id, step_order, name_ar, step_type, assignee_employee_id, status
) values
  ('04520000-0000-4000-8000-000000000201', 1, 'المدير المباشر', 'approval',
   '04520000-0000-4000-8000-000000000102', 'rejected'),
  ('04520000-0000-4000-8000-000000000201', 2, 'خطوة قديمة', 'approval', null, 'pending');

insert into public.workflow_instances (
  definition_id, request_id, definition_version, status, current_step_order
)
select wd.id, '04520000-0000-4000-8000-000000000201', wd.version, 'running', 2
from public.workflow_definitions wd
where wd.request_type = 'mission' and wd.is_default = true and wd.is_active = true
limit 1
on conflict (request_id) do update set status = 'running', current_step_order = 2;

-- ═════════════════════════════════════════════════════════════════════
-- 1) المالك يعيد الرفع بنجاح
-- ═════════════════════════════════════════════════════════════════════
set local role = authenticated;
set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000001","role":"authenticated"}';

select ok(
  public.resubmit_my_request(
    '04520000-0000-4000-8000-000000000201',
    'مأمورية معدلة للأسكندرية',
    'سبب محدث بعد الرفض مع توضيح الهدف',
    '{"startDate":"2026-09-05","endDate":"2026-09-06","location":"الإسكندرية","startTime":"08:00","endTime":"14:00"}'::jsonb
  ) is not null,
  '(1) إعادة الرفع تنجح للمالك'
);

reset role;

select is(
  (select status || '/' || workflow_status from public.requests
    where id = '04520000-0000-4000-8000-000000000201'),
  'pending/submitted',
  '(2) الحالة pending/submitted بعد إعادة الرفع'
);

select is(
  (select count(*)::int from public.requests
    where id = '04520000-0000-4000-8000-000000000201'
      and decided_at is null and decided_by is null and escalated_at is null),
  1,
  '(3) حقول القرار صُفّرت'
);

select is(
  (select count(*)::int from public.request_steps
    where request_id = '04520000-0000-4000-8000-000000000201'),
  (select count(*)::int from public.workflow_steps ws
    join public.workflow_definitions wd on wd.id = ws.definition_id
    where wd.request_type = 'mission' and wd.is_default = true and wd.is_active = true
      and ws.is_active = true),
  '(4) خطوات جديدة مطابقة لتعريف المأمورية النشط'
);

select is(
  (select status from public.request_steps
    where request_id = '04520000-0000-4000-8000-000000000201' and step_order = 1),
  'active',
  '(5) الخطوة الأولى نشطة'
);

select is(
  (select count(*)::int from public.workflow_instances
    where request_id = '04520000-0000-4000-8000-000000000201' and status = 'running'
      and current_step_order = 1),
  1,
  '(6) نسخة السير أعيد فتحها running من الخطوة 1'
);

select is(
  (select count(*)::int from public.workflow_instances
    where request_id = '04520000-0000-4000-8000-000000000201'),
  1,
  '(7) نسخة واحدة فقط (قيد الفريد محفوظ)'
);

select is(
  (select count(*)::int from public.request_actions
    where request_id = '04520000-0000-4000-8000-000000000201'
      and action = 'submit' and from_status = 'rejected' and to_status = 'pending'),
  1,
  '(8) توثيق submit من rejected إلى pending'
);

select is(
  (select count(*)::int from public.notifications n
    join public.profiles p on p.id = n.recipient_user_id
    where p.employee_id = '04520000-0000-4000-8000-000000000102'
      and n.entity_type = 'request'
      and n.entity_id = '04520000-0000-4000-8000-000000000201'
      and n.metadata->>'resubmitted' = 'true'),
  1,
  '(9) المدير المباشر أُشعر بإعادة الرفع'
);

-- ═════════════════════════════════════════════════════════════════════
-- 2) الحمايات
-- ═════════════════════════════════════════════════════════════════════
set local role = authenticated;
set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000004","role":"authenticated"}';

select throws_ok(
  'SELECT public.resubmit_my_request(''04520000-0000-4000-8000-000000000201'', ''عنوان غريب اختبار'', ''سبب غريب اختبار'', ''{}''::jsonb)',
  '42501',
  NULL,
  '(10) غير المالك → FORBIDDEN'
);

set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000001","role":"authenticated"}';

-- إرجاع الطلب إلى rejected لاختبار مسارات التحقق (الاختبار 1 أعاده pending)
update public.requests set status = 'rejected', workflow_status = 'completed'
where id = '04520000-0000-4000-8000-000000000201';

select throws_ok(
  'SELECT public.resubmit_my_request(''04520000-0000-4000-8000-000000000201'', ''عن'', ''سبب قصير'', ''{}''::jsonb)',
  '22023',
  NULL,
  '(11) عنوان أقصر من 3 أحرف → رفض'
);

reset role;

-- طلب pending لا يُعاد رفعه
insert into public.requests (
  id, request_type, employee_id, status, workflow_status, title, reason, payload
) values (
  '04520000-0000-4000-8000-000000000202', 'mission',
  '04520000-0000-4000-8000-000000000101', 'pending', 'submitted',
  'مأمورية قيد المراجعة', 'سبب الطلب قيد المراجعة', '{}'::jsonb
);

set local role = authenticated;
set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000001","role":"authenticated"}';

select throws_ok(
  'SELECT public.resubmit_my_request(''04520000-0000-4000-8000-000000000202'', ''عنوان صحيح هنا'', ''سبب صحيح هنا'', ''{}''::jsonb)',
  '22023',
  NULL,
  '(12) طلب pending → ONLY_REJECTED_OR_RETURNED'
);

reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 3) canResubmit في التفاصيل
-- ═════════════════════════════════════════════════════════════════════
-- (الطلب 201 أصبح pending بعد إعادة الرفع — نرجعه rejected للفحص)
update public.requests set status = 'rejected', workflow_status = 'completed'
where id = '04520000-0000-4000-8000-000000000201';

set local role = authenticated;
set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  (public.get_mobile_request_detail('04520000-0000-4000-8000-000000000201')->>'canResubmit'),
  'true',
  '(13) canResubmit=true للمالك على المرفوض'
);

set local request.jwt.claims = '{"sub":"04520000-0000-4000-8000-000000000002","role":"authenticated"}';

select is(
  (public.get_mobile_request_detail('04520000-0000-4000-8000-000000000201')->>'canResubmit'),
  'false',
  '(14) canResubmit=false للمدير (ليس المالك)'
);

reset role;

select finish();
rollback;
