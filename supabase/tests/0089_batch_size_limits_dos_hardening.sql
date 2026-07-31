-- 0089: حدّ أقصى لحجم الدُفعات (0238) — إثبات أن دوال SECURITY DEFINER التي تكرّر
-- مصفوفات المستدعي ترفض الحمولات المتجاوزة للحدّ بخطأ ERR_BATCH_TOO_LARGE،
-- بينما تقبل الحمولات ضمن الحدّ. حماية من حجب الخدمة (DoS).
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- =====================================================================
-- ① وجود الدوال الثلاث عشرة الحيّة بعد الترحيل (توقيعات دقيقة).
-- =====================================================================
select has_function('public','rpc_set_role_permissions',array['uuid','jsonb'],
  '0238: rpc_set_role_permissions(uuid,jsonb) موجودة');
select has_function('public','batch_decide_requests',array['uuid[]','text','text'],
  '0238: batch_decide_requests(uuid[],text,text) موجودة');
select has_function('public','batch_mark_notifications_read',array['uuid[]'],
  '0238: batch_mark_notifications_read(uuid[]) موجودة');
select has_function('public','create_work_assignment',
  array['text','text','timestamptz','timestamptz','uuid[]','text','text','uuid','boolean','timestamptz','jsonb'],
  '0238: create_work_assignment(...) موجودة');
select has_function('public','publish_roster_admin',
  array['text','date','date','uuid','uuid','uuid','jsonb','text'],
  '0238: publish_roster_admin(...) موجودة');
select has_function('public','create_onboarding_journey_admin',
  array['uuid','timestamptz','date','jsonb'],
  '0238: create_onboarding_journey_admin(...) موجودة');
select has_function('public','start_offboarding_case',
  array['uuid','text','text','date','date','uuid','jsonb'],
  '0238: start_offboarding_case(...) موجودة');
select has_function('public','set_dispute_committee',array['uuid','jsonb'],
  '0238: set_dispute_committee(uuid,jsonb) موجودة');
select has_function('public','schedule_dispute_session_v2',
  array['uuid','text','timestamptz','timestamptz','text','text','jsonb'],
  '0238: schedule_dispute_session_v2(...) موجودة');
select has_function('public','finalize_dispute_session_v2',
  array['uuid','text','jsonb','text','jsonb'],
  '0238: finalize_dispute_session_v2(...) موجودة');
select has_function('public','schedule_interview_admin',
  array['uuid','text','timestamptz','text','uuid[]','uuid'],
  '0238: schedule_interview_admin(...) موجودة');
select has_function('public','has_any_scoped_permission',
  array['text[]','text','uuid'],
  '0238: has_any_scoped_permission(text[],text,uuid) موجودة');

-- =====================================================================
-- ② has_any_scoped_permission — وحدة نقية (لا تحتاج fixture):
--    مصفوفة > 100 عنصر تُرفض؛ مصفوفة ضمن الحدّ لا ترفع خطأ الحجم.
-- =====================================================================
-- 101 شريحة صلاحية وهمية → يجب أن ترفع ERR_BATCH_TOO_LARGE قبل أي فحص.
select throws_ok($$
  select public.has_any_scoped_permission(
    (select array_agg('perm.'||g::text) from generate_series(1,101) g),
    null, null)
$$, '22023', 'ERR_BATCH_TOO_LARGE', '0238: has_any_scoped_permission يرفض > 100 شريحة');

-- مصفوفة ضمن الحدّ (100) لا ترفع خطأ الحجم (قد تُعيد false — المهم لا ERR_BATCH_TOO_LARGE).
select lives_ok($$
  select public.has_any_scoped_permission(
    (select array_agg('perm.'||g::text) from generate_series(1,100) g),
    null, null)
$$, '0238: has_any_scoped_permission يقبل 100 شريحة (ضمن الحدّ)');

-- =====================================================================
-- ③ create_work_assignment — إثبات سلوكي للحدّ (سقف 500).
--    Fixture مصغّر: كيان + إدارة + مدير بصلاحية تنظيمية واسعة + موظف واحد.
--    نمرّر مصفوفة مشاركين > 500 (نكرّر معرّف موظف صالح) → ERR_BATCH_TOO_LARGE.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'dddddddd-0089-4000-8000-000000000000';
  v_dept uuid := 'dddddddd-0089-4000-8000-000000000001';
begin
  insert into public.legal_entities(id,code,name) values(v_le,'BS-LE','كيان حدّ الدفعة');
  insert into public.departments(id,legal_entity_id,code,name) values(v_dept,v_le,'BS-D','إدارة الحدّ');

  insert into auth.users(id,email,aud,role) values
    ('44444444-0089-4000-8000-000000000001','bs-mgr@test.local','authenticated','authenticated'),
    ('44444444-0089-4000-8000-000000000002','bs-emp@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('55555555-0089-4000-8000-000000000001','44444444-0089-4000-8000-000000000001','BS-MGR','مدير الحدّ',v_dept,'active',true,'1980-01-01','2015-01-01'),
    ('55555555-0089-4000-8000-000000000002','44444444-0089-4000-8000-000000000002','BS-EMP','موظف الحدّ',v_dept,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id,employee_id,status) values
    ('44444444-0089-4000-8000-000000000001','55555555-0089-4000-8000-000000000001','active'),
    ('44444444-0089-4000-8000-000000000002','55555555-0089-4000-8000-000000000002','active');

  -- المدير full-access ليتجاوز فحص can_access_employee ويصل مباشرة إلى حارس الحدّ.
  insert into public.user_roles(user_id,role_id)
  select '44444444-0089-4000-8000-000000000001'::uuid, r.id
    from public.roles r where r.is_full_access = true
    limit 1;
end $fixture$;

do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0089-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','44444444-0089-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- 501 مشارك (تكرار معرّف موظف صالح) → يجب رفضه بحارس الحدّ.
select throws_ok($$
  select public.create_work_assignment(
    'MISSION','تكليف بحمولة ضخمة',
    '2026-08-01 10:00:00+02','2026-08-01 14:00:00+02',
    (select array_agg('55555555-0089-4000-8000-000000000002'::uuid) from generate_series(1,501) g),
    'اختبار الحدّ','مكان', null, false, null, '{}'::jsonb)
$$, '22023', 'ERR_BATCH_TOO_LARGE',
  '0238: create_work_assignment يرفض > 500 مشارك بخطأ ERR_BATCH_TOO_LARGE');

-- مشارك واحد (ضمن الحدّ) لا يرفع خطأ الحجم — يُثبت أن الحارس لا يكسر الاستخدام العادي.
select lives_ok($$
  select public.create_work_assignment(
    'MISSION','تكليف عادي ضمن الحدّ',
    '2026-08-02 10:00:00+02','2026-08-02 14:00:00+02',
    array['55555555-0089-4000-8000-000000000002']::uuid[],
    'استخدام عادي','مكان', null, false, null, '{}'::jsonb)
$$, '0238: create_work_assignment يقبل حمولة ضمن الحدّ');

reset role;

-- =====================================================================
-- ④ batch_mark_notifications_read — وحدة سلوكية (owner-scoped، سقف 500).
--    > 500 معرّف → ERR_BATCH_TOO_LARGE قبل أي UPDATE.
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0089-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','44444444-0089-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok($$
  select public.batch_mark_notifications_read(
    (select array_agg(gen_random_uuid()) from generate_series(1,501) g))
$$, '22023', 'ERR_BATCH_TOO_LARGE',
  '0238: batch_mark_notifications_read يرفض > 500 معرّف');

-- مصفوفة صغيرة (معرّفات غير موجودة) لا ترفع خطأ الحجم وتُعيد 0.
select is(
  (select public.batch_mark_notifications_read(array[gen_random_uuid(),gen_random_uuid()])),
  0, '0238: batch_mark_notifications_read يقبل حمولة صغيرة ويُعيد 0');

reset role;

select * from finish();
rollback;
