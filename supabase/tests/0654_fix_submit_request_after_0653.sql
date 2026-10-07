-- =====================================================================
-- 0654: تقديم الطلبات يعمل بعد كسر 0653
--   • موظف عادي يقدّم إذن تأخير ومأمورية بنجاح (كانا يفشلان بـ 42703).
--   • workflow_status يبقى 'submitted' (قيمة مسموحة) وخطوات سير العمل تُنشأ.
--   • سجل الطلب يبدأ بـ 'submit'، ومعتمد الخطوة النشطة يُشعَر.
--   • تخصيصات العيادات من 0653 باقية: المعتمد ثابت ولا تصعيد تلقائي.
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(15);

do $fixture$
declare
  v_le  uuid := 'f6540000-0000-4000-8000-000000000001';
  v_jt  uuid := 'f6540000-0000-4000-8000-000000000004';
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0654', 'كيان 0654');
  insert into public.departments(id, legal_entity_id, code, name) values
    ('f6540000-0000-4000-8000-00000000000a', v_le, 'D-0654-A',  'إدارة 0654'),
    ('f6540000-0000-4000-8000-00000000000c', v_le, 'D-0654-CL', 'عيادات 0654');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0654', 'وظيفة 0654');

  insert into auth.users(id, email, aud, role) values
    ('f6540000-0000-4000-8000-000000000020', 'mgr-0654@test.local', 'authenticated', 'authenticated'),
    ('f6540000-0000-4000-8000-000000000021', 'emp-0654@test.local', 'authenticated', 'authenticated'),
    ('f6540000-0000-4000-8000-000000000022', 'cln-0654@test.local', 'authenticated', 'authenticated');

  -- معتمد العيادات (0653) — موجود في الإنتاج؛ يُنشأ هنا إن لم يوجد محلياً
  insert into public.employees(id, employee_code, full_name_ar, status, is_active, hire_date, phone_e164)
  values ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c', 'E-0654-CM', 'معتمد العيادات 0654', 'active', true, current_date - 900, '+201000654009')
  on conflict (id) do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    ('f6540000-0000-4000-8000-000000000010', 'f6540000-0000-4000-8000-000000000020', 'E-0654-0', 'مدير 0654',  'f6540000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 900, '+201000654000'),
    ('f6540000-0000-4000-8000-000000000011', 'f6540000-0000-4000-8000-000000000021', 'E-0654-1', 'موظف 0654',  'f6540000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 500, '+201000654001'),
    ('f6540000-0000-4000-8000-000000000012', 'f6540000-0000-4000-8000-000000000022', 'E-0654-2', 'ممرض 0654',  'f6540000-0000-4000-8000-00000000000c', v_jt, 'active', true, current_date - 400, '+201000654002');

  update public.departments set manager_id = 'f6540000-0000-4000-8000-000000000010'
   where id = 'f6540000-0000-4000-8000-00000000000a';

  insert into public.profiles(id, employee_id, status) values
    ('f6540000-0000-4000-8000-000000000020', 'f6540000-0000-4000-8000-000000000010', 'active'),
    ('f6540000-0000-4000-8000-000000000021', 'f6540000-0000-4000-8000-000000000011', 'active'),
    ('f6540000-0000-4000-8000-000000000022', 'f6540000-0000-4000-8000-000000000012', 'active');
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- 1) البنية
-- =====================================================================
select is(has_function_privilege('authenticated', 'public._submit_request_for(uuid,text,uuid,uuid,text,text,jsonb)', 'EXECUTE'),
  false, '_submit_request_for داخلية — غير مكشوفة للعميل');
select is(has_function_privilege('anon', 'public.is_clinic_team_member(uuid)', 'EXECUTE'),
  false, 'is_clinic_team_member غير مكشوفة لـ anon');
select ok((select prosrc not like '%current_step_id%' from pg_proc where proname = '_submit_request_for'),
  'لا مرجع للعمود غير الموجود current_step_id');
select ok((select prosrc not like '%''in_progress''%' from pg_proc where proname = '_submit_request_for'),
  'لا قيمة workflow_status مرفوضة');

-- =====================================================================
-- 2) موظف عادي: إذن تأخير + مأمورية
-- =====================================================================
select pg_temp.act_as('f6540000-0000-4000-8000-000000000021');
set local role authenticated;

select lives_ok($$
  select public.submit_my_request('late_permit', 'إذن تأخير غداً', 'موعد طبي صباحاً',
    jsonb_build_object('permitDate', (now() at time zone 'Africa/Cairo')::date + 1, 'minutes', 60))
$$, 'تقديم إذن تأخير ينجح');

select lives_ok($$
  select public.submit_my_request('mission', 'مأمورية اليوم', 'زيارة جهة شريكة',
    jsonb_build_object('location', 'مقر الشريك'))
$$, 'تقديم مأمورية ينجح');

reset role;

select is((select count(*)::int from public.requests where employee_id = 'f6540000-0000-4000-8000-000000000011'),
  2, 'الطلبان محفوظان');
select is((select workflow_status from public.requests
            where employee_id = 'f6540000-0000-4000-8000-000000000011' and request_type = 'late_permit'),
  'submitted', 'workflow_status = submitted (قيمة مسموحة)');
select ok(exists (select 1 from public.request_steps s join public.requests r on r.id = s.request_id
                   where r.employee_id = 'f6540000-0000-4000-8000-000000000011' and s.status = 'active'),
  'خطوة الاعتماد الأولى نشطة');
select is((select count(*)::int from public.request_actions a join public.requests r on r.id = a.request_id
            where r.employee_id = 'f6540000-0000-4000-8000-000000000011' and a.action = 'submit'),
  2, 'سجل كل طلب يبدأ بـ submit');
select ok(exists (select 1 from public.notifications n
                   join public.requests r on r.id = n.entity_id
                   join public.request_steps s on s.request_id = r.id and s.status = 'active'
                   join public.employees ap on ap.id = coalesce(s.assignee_employee_id, r.manager_employee_id)
                  where r.employee_id = 'f6540000-0000-4000-8000-000000000011'
                    and n.recipient_employee_id = ap.id),
  'معتمد الخطوة النشطة يُشعَر');

-- =====================================================================
-- 3) طاقم العيادات (0653): المعتمد ثابت، بلا تصعيد، والمأموريات محظورة
-- =====================================================================
select pg_temp.act_as('f6540000-0000-4000-8000-000000000022');
set local role authenticated;

select lives_ok($$
  select public.submit_my_request('late_permit', 'إذن تأخير غداً', 'ظرف عائلي',
    jsonb_build_object('permitDate', (now() at time zone 'Africa/Cairo')::date + 1, 'minutes', 30))
$$, 'موظف العيادات يقدّم إذن تأخير');

select throws_ok($$
  select public.submit_my_request('mission', 'مأمورية', 'زيارة', '{}'::jsonb)
$$, '22023', null, 'المأموريات محظورة على طاقم العيادات (0653)');

reset role;

select is((select manager_employee_id from public.requests where employee_id = 'f6540000-0000-4000-8000-000000000012'),
  '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'معتمد طلب العيادات = معتمد العيادات');
select is((select escalation_deadline from public.requests where employee_id = 'f6540000-0000-4000-8000-000000000012'),
  null, 'لا تصعيد تلقائي لطلبات العيادات');

select * from finish();
rollback;
