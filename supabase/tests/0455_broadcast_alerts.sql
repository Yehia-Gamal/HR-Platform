-- =====================================================================
-- 0455: التنبيه الشامل (broadcast alerts)
-- ---------------------------------------------------------------------
-- يثبت: الصلاحية ومنحها للتنفيذي وHR حصراً، جدول التنبيهات مع RLS،
-- الإرسال محمي بالصلاحية (42501 لغير المخوّل)، إبطال التنبيه السابق،
-- إشعار كل الموظفين النشطين بـ urgent، انتهاء الصلاحية يجعل الاستعلام
-- فارغاً، ورفض الرسائل القصيرة، وحجب anon.
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- =====================================================================
-- Fixture: كيان + إدارة + موظف HR مخوّل + موظف عادي.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'b4550000-0000-4000-8000-000000000001';
  v_dept uuid := 'b4550000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'BA-LE', 'كيان التنبيهات');
  insert into public.departments(id, legal_entity_id, code, name) values(v_dept, v_le, 'BA-D', 'إدارة التنبيهات');

  insert into auth.users(id, email, aud, role) values
    ('b4550000-0000-4000-8000-000000000004','ba-hr@test.local','authenticated','authenticated'),
    ('b4550000-0000-4000-8000-000000000005','ba-emp@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('b4550000-0000-4000-8000-000000000011','b4550000-0000-4000-8000-000000000004','BA-HR','مسؤول تنبيهات',v_dept,'active',true,'1988-01-01','2018-01-01'),
    ('b4550000-0000-4000-8000-000000000012','b4550000-0000-4000-8000-000000000005','BA-EMP','موظف تنبيهات',v_dept,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id, employee_id, status) values
    ('b4550000-0000-4000-8000-000000000004','b4550000-0000-4000-8000-000000000011','active'),
    ('b4550000-0000-4000-8000-000000000005','b4550000-0000-4000-8000-000000000012','active');

  insert into public.user_roles(user_id, role_id)
  select t.u, r.id from (values
    ('b4550000-0000-4000-8000-000000000004'::uuid,'hr-manager'),
    ('b4550000-0000-4000-8000-000000000005'::uuid,'employee')
  ) as t(u,slug) join public.roles r on r.slug=t.slug;

  create temp table pg_temp.ba_ids(alert_id uuid) on commit drop;
end $fixture$;

-- =====================================================================
-- البنية والمنح.
-- =====================================================================
select has_table('public','broadcast_alerts','جدول broadcast_alerts موجود');
select has_function('public','send_broadcast_alert',array['text'],'send_broadcast_alert(text) موجودة');
select has_function('public','get_active_broadcast_alert',array[]::text[],'get_active_broadcast_alert() موجودة');
select is(
  (select count(*)::int from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
   where p.code='alerts.broadcast.send' and rp.scope='organization'
     and r.slug in ('executive-director','hr-manager')),
  2, 'الصلاحية ممنوحة للتنفيذي وHR بنطاق organization');
select ok(
  (select relrowsecurity from pg_class where relname='broadcast_alerts'),
  'RLS مفعّل على broadcast_alerts');

-- =====================================================================
-- الحماية: anon ممنوع، والموظف العادي مرفوض.
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon','public.send_broadcast_alert(text)','EXECUTE'),
  false, 'anon لا ينفّذ send_broadcast_alert');
select is(pg_catalog.has_function_privilege('anon','public.get_active_broadcast_alert()','EXECUTE'),
  false, 'anon لا ينفّذ get_active_broadcast_alert');

do $set_emp$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"b4550000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','b4550000-0000-4000-8000-000000000005', true);
end $set_emp$;

select throws_ok($$
  select public.send_broadcast_alert('تجربة من موظف غير مخوّل')
$$, '42501', null, 'الموظف العادي بلا صلاحية التنبيه مرفوض');

-- =====================================================================
-- الإرسال المخوّل: نجاح + إبطال السابق + إشعارات urgent.
-- =====================================================================
do $set_hr$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"b4550000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','b4550000-0000-4000-8000-000000000004', true);
end $set_hr$;

select lives_ok($$
  insert into pg_temp.ba_ids(alert_id)
  select public.send_broadcast_alert('اجتماع طارئ فورًا في المقر الرئيسي')
$$, 'HR المخوّل يرسل تنبيهًا شاملاً');

select lives_ok($$
  insert into pg_temp.ba_ids(alert_id)
  select public.send_broadcast_alert('تحديث ثانٍ للتنبيه العاجل الآن')
$$, 'إرسال ثانٍ ينجح ويُبطل الأول');

select is(
  (select count(*)::int from public.broadcast_alerts where is_active),
  1, 'تنبيه نشط واحد فقط بعد الإرسالين');

select is(
  (select count(*)::int from public.notifications n
    join public.broadcast_alerts a on a.id = n.entity_id
   where a.is_active
     and n.category='general' and n.priority='urgent'),
  2, 'كل الموظفين النشطين (2) استلموا إشعار urgent عن التنبيه النشط');

select is(
  (select message from public.broadcast_alerts where is_active),
  'تحديث ثانٍ للتنبيه العاجل الآن', 'get عبر الجدول يعيد رسالة آخر تنبيه');

select is(
  (select public.get_active_broadcast_alert()->>'message'),
  'تحديث ثانٍ للتنبيه العاجل الآن', 'get_active_broadcast_alert يعيد التنبيه النشط');

-- =====================================================================
-- انتهاء الصلاحية + تحقق طول الرسالة.
-- =====================================================================
do $expire$
begin
  update public.broadcast_alerts set expires_at = now() - interval '1 minute' where is_active;
end $expire$;

select is(
  (select public.get_active_broadcast_alert()),
  null, 'تنبيه منتهي الصلاحية لا يظهر في الاستعلام');

select throws_ok($$
  select public.send_broadcast_alert('لا')
$$, '22023', null, 'الرسالة الأقصر من 3 أحرف مرفوضة');

select * from finish();
rollback;