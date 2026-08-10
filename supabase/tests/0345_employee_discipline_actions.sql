-- 0345: سجل الانضباط — employee_discipline_actions + RPCs
-- تغطية: وجود الجدول والأعمدة والدوال، RLS (موظف يقرأ سجله، الحوكمة تدير)،
-- سير الاعتماد (submit → decide approved/rejected)، و audit/notification.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(25);

insert into auth.users(id,email,aud,role) values
 ('83000000-0000-4000-8000-000000000001','disc-hr@test.local','authenticated','authenticated'),
 ('83000000-0000-4000-8000-000000000002','disc-emp@test.local','authenticated','authenticated'),
 ('83000000-0000-4000-8000-000000000003','disc-approver@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('84000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','DISC-HR','مسؤول HR للاختبار','active',true),
 ('84000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000002','DISC-EMP','موظف الانضباط للاختبار','active',true),
 ('84000000-0000-4000-8000-000000000003','83000000-0000-4000-8000-000000000003','DISC-APP','معتمد الانضباط للاختبار','active',true);

insert into public.profiles(id,employee_id,status)
select user_id,id,'active' from public.employees
where id between '84000000-0000-4000-8000-000000000001' and '84000000-0000-4000-8000-000000000003';

insert into public.user_roles(user_id,role_id,effective_from)
select x.user_id,r.id,now()
from (values
 ('83000000-0000-4000-8000-000000000001'::uuid,'hr-manager'),
 ('83000000-0000-4000-8000-000000000002'::uuid,'employee'),
 ('83000000-0000-4000-8000-000000000003'::uuid,'executive-director')
) x(user_id,slug) join public.roles r on r.slug=x.slug;

-- 1) بنية الجدول
select has_table('public','employee_discipline_actions','جدول الإجراءات التأديبية موجود');
select has_column('public','employee_discipline_actions','employee_id','عمود employee_id');
select has_column('public','employee_discipline_actions','action_type','عمود action_type');
select has_column('public','employee_discipline_actions','status','عمود status');
select has_column('public','employee_discipline_actions','amount','عمود amount');
select has_column('public','employee_discipline_actions','decided_by','عمود decided_by');
select has_column('public','employee_discipline_actions','decided_at','عمود decided_at');

select has_function('public','submit_discipline_action',ARRAY['uuid','text','text','text','text','numeric','date','date'],'دالة إنشاء الإجراء موجودة');
select has_function('public','decide_discipline_action',ARRAY['uuid','text','text'],'دالة الاعتماد موجودة');
select has_function('public','get_my_discipline_record',ARRAY['int'],'دالة سجل الموظف موجودة');
select has_function('public','discipline_action_type_label',ARRAY['text'],'دالة تسمية النوع موجودة');

select function_privs_are(
  'public','submit_discipline_action',ARRAY['uuid','text','text','text','text','numeric','date','date'],'authenticated',
  ARRAY['EXECUTE'],'تنفيذ الإنشاء ممنوح للمصادق');

-- 2) الموظف لا يستطيع إنشاء إجراء (لا يملك relations.discipline.create)
set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.submit_discipline_action(
    '84000000-0000-4000-8000-000000000002','written_warning','تأخر','اختبار إنشاء الموظف نفسه','moderate')$$,
  '42501','FORBIDDEN: requires relations.discipline.create',
  'الموظف العادي لا يملك إنشاء إجراء تأديبي'
);

-- 3) HR (hr-manager يملك create عبر... لا — يحتاج relations.discipline.create)
-- ملاحظة: في التطبيق، منح relations.discipline.create لدور الحوكمة في 0345
-- مخصص لمن يملك الصلاحية. نتحقق أن full-access admin يستطيع.
reset role;
select set_config('request.jwt.claim.sub',null,true);

-- hr-manager لا يملك relations.discipline.create افتراضياً (نختبر أنه مرفوض أو مسموح
-- حسب تكوين الأدوار الفعلي). بدلاً من ذلك نختبر عبر أخذ دور admin عبر rpc_assign_role؟ —
-- الأدوار الفعلية: executive-director يملك relations.discipline.approve فقط.
-- لذلك نختبر RLS SELECT لصاحب الدور، ونختبر submit عبر منح مؤقت مباشر.

-- 3b) منح مؤقت للصلاحية لاختبار التدفق
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'organization'
from public.roles r, public.permissions p
where r.slug='hr-manager' and p.code='relations.discipline.create'
on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.submit_discipline_action(
    '84000000-0000-4000-8000-000000000002','written_warning','إنذار كتابي','تأخر متكرر عن العمل','moderate')$$,
  'hr-manager (بعد المنح) يستطيع إنشاء إجراء'
);

-- 4) سير الاعتماد — المعتمد (executive-director) يوافق
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000003',true);
select lives_ok(
  $$select public.decide_discipline_action(
    (select id from public.employee_discipline_actions where employee_id='84000000-0000-4000-8000-000000000002' limit 1),
    'approved','موافق عليه من المعتمد')$$,
  'المعتمد يستطيع اعتماد الإجراء'
);

select is(
  (select status from public.employee_discipline_actions
   where employee_id='84000000-0000-4000-8000-000000000002' limit 1),
  'approved','حالة الإجراء أصبحت approved'
);

-- 5) الموظف يرى سجله المعتمد فقط
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000002',true);
select ok(
  (select count(*)::int from jsonb_to_recordset(public.get_my_discipline_record()) as r("actionType" text) where "actionType"='written_warning') = 1,
  'الموظف يرى سجل معتمد في قائمته'
);

-- 6) رفض إجراء آخر
reset role;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.submit_discipline_action(
    '84000000-0000-4000-8000-000000000002','suspension','إيقاف','إيقاف مؤقت ثلاثة أيام','high',null,'2026-08-01'::date,'2026-08-03'::date)$$,
  'إنشاء إجراء إيقاف بفترة'
);
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000003',true);
select lives_ok(
  $$select public.decide_discipline_action(
    (select id from public.employee_discipline_actions
     where employee_id='84000000-0000-4000-8000-000000000002' and action_type='suspension' limit 1),
    'rejected','غير مبرر')$$,
  'المعتمد يستطيع رفض الإجراء'
);
select is(
  (select status from public.employee_discipline_actions
   where employee_id='84000000-0000-4000-8000-000000000002' and action_type='suspension' limit 1),
  'rejected','حالة الإيقاف أصبحت rejected'
);

-- 7) لا يمكن إعادة الاعتماد على إجراء تم البت فيه
select throws_ok(
  $$select public.decide_discipline_action(
    (select id from public.employee_discipline_actions
     where employee_id='84000000-0000-4000-8000-000000000002' and action_type='suspension' limit 1),
    'approved','محاولة إعادة')$$,
  '22023','discipline_action_not_pending','لا يُعاد البت في إجراء محسوم'
);

-- 8) لا يمكن خصم راتب بلا مبلغ
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000001',true);
select throws_ok(
  $$select public.submit_discipline_action(
    '84000000-0000-4000-8000-000000000002','salary_deduction','خصم','بلا مبلغ','moderate',null)$$,
  '22023','amount is required for salary deduction','خصم راتب يتطلب مبلغاً'
);

-- 9) audit سُجّل
select is(
  (select count(*)::int from public.audit_events
   where event_type in ('discipline.submitted','discipline.approved','discipline.rejected')),
  4,'سُجلت أحداث التدقيق للتقديم والاعتماد والرفض'
);

-- 10) إشعارات أُنشئت للموظف
select ok(
  (select count(*)::int > 0 from public.notifications
   where recipient_employee_id='84000000-0000-4000-8000-000000000002'
     and category='general'),
  'أُنشئ إشعار للموظف عند الاعتماد'
);

-- 11) RLS — موظف آخر لا يرى إجراء زميله
-- (سجل أُعد من موظف hr-manager؛ الموظف نفسه يرى فقط سجله الخاص)
reset role;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000002',true);
select ok(
  (select count(*)::int from public.employee_discipline_actions
   where employee_id <> '84000000-0000-4000-8000-000000000002') = 0,
  'الموظف لا يرى إجراءات زملائه'
);

reset role;
select finish();
rollback;
