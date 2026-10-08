-- =====================================================================
-- 0572: صمت إشعارات موظفي العيادات + رؤية متبادلة مقفلة
-- ---------------------------------------------------------------------
-- يثبت: عزل بالدور (clinic-staff) حتى في قسم غير معزول، مصيدة
-- الإشعارات (منع كامل عدا نتيجة طلباته هو)، استثناءات الدور
-- (HR/تنفيذي/مدير العيادات)، حظر طلبات الموقع والحضور والبث،
-- فلتر can_access بعد أي scope، أسماء الأقسام تبقى بلا أعداد مخفية،
-- وتفكيك مسار medical_leave_v1 عن العزل بالدور. كل شيء rollback.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(27);

-- =====================================================================
-- Fixture: كيان + قسمان + موظفون بأدوار متنوعة.
-- ملاحظة: موظف العيادات (1502) في قسم غير معزول — العزل بالدور فقط.
-- =====================================================================
do $fixture$
declare
  v_le  uuid := 'd5720000-0000-4000-8000-000000000001';
  v_d2  uuid := 'd5720000-0000-4000-8000-000000000002'; -- قسم عادي
  v_d9  uuid := 'd5720000-0000-4000-8000-000000000009'; -- قسم آخر
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'D572-LE', 'كيان 0572');
  insert into public.departments(id, legal_entity_id, code, name, is_isolated) values
    (v_d2, v_le, 'D572-NRM', 'قسم عادي', false),
    (v_d9, v_le, 'D572-OTH', 'قسم آخر', false);

  insert into auth.users(id, email, aud, role) values
    ('d5720000-0000-4000-8000-000000000501','u572-01@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000502','u572-02@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000503','u572-03@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000504','u572-04@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000505','u572-05@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000506','u572-06@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000507','u572-07@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000508','u572-08@test.local','authenticated','authenticated'),
    ('d5720000-0000-4000-8000-000000000510','u572-10@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('d5720000-0000-4000-8000-000000001501','d5720000-0000-4000-8000-000000000501','D572-01','موظف عادي 572',v_d2,'active',true,current_date - 900),
    ('d5720000-0000-4000-8000-000000001502','d5720000-0000-4000-8000-000000000502','D572-02','موظف عيادة 572',v_d2,'active',true,current_date - 800),
    ('d5720000-0000-4000-8000-000000001503','d5720000-0000-4000-8000-000000000503','D572-03','مدير عيادات 572',v_d2,'active',true,current_date - 700),
    ('d5720000-0000-4000-8000-000000001504','d5720000-0000-4000-8000-000000000504','D572-04','مسؤول موارد 572',v_d9,'active',true,current_date - 600),
    ('d5720000-0000-4000-8000-000000001505','d5720000-0000-4000-8000-000000000505','D572-05','زميل عادي 572',v_d2,'active',true,current_date - 500),
    ('d5720000-0000-4000-8000-000000001506','d5720000-0000-4000-8000-000000000506','D572-06','تنفيذي 572',v_d9,'active',true,current_date - 400),
    ('d5720000-0000-4000-8000-000000001507','d5720000-0000-4000-8000-000000000507','D572-07','مدير قسم آخر 572',v_d9,'active',true,current_date - 300),
    ('d5720000-0000-4000-8000-000000001508','d5720000-0000-4000-8000-000000000508','D572-08','مشاهد محدَّد 572',v_d9,'active',true,current_date - 200),
    ('d5720000-0000-4000-8000-000000001510','d5720000-0000-4000-8000-000000000510','D572-10','مدير عيادات آخر 572',v_d9,'active',true,current_date - 100);

  insert into public.profiles(id, employee_id, status)
    select u, e, 'active' from (values
      ('d5720000-0000-4000-8000-000000000501'::uuid,'d5720000-0000-4000-8000-000000001501'::uuid),
      ('d5720000-0000-4000-8000-000000000502'::uuid,'d5720000-0000-4000-8000-000000001502'::uuid),
      ('d5720000-0000-4000-8000-000000000503'::uuid,'d5720000-0000-4000-8000-000000001503'::uuid),
      ('d5720000-0000-4000-8000-000000000504'::uuid,'d5720000-0000-4000-8000-000000001504'::uuid),
      ('d5720000-0000-4000-8000-000000000505'::uuid,'d5720000-0000-4000-8000-000000001505'::uuid),
      ('d5720000-0000-4000-8000-000000000506'::uuid,'d5720000-0000-4000-8000-000000001506'::uuid),
      ('d5720000-0000-4000-8000-000000000507'::uuid,'d5720000-0000-4000-8000-000000001507'::uuid),
      ('d5720000-0000-4000-8000-000000000508'::uuid,'d5720000-0000-4000-8000-000000001508'::uuid),
      ('d5720000-0000-4000-8000-000000000510'::uuid,'d5720000-0000-4000-8000-000000001510'::uuid)
    ) t(u,e);

  -- الإشراف: مدير العيادات (1503) مدير مباشر لموظفي العيادة والزميل العادي.
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('d5720000-0000-4000-8000-000000001502','d5720000-0000-4000-8000-000000001503','primary',current_date),
    ('d5720000-0000-4000-8000-000000001505','d5720000-0000-4000-8000-000000001503','primary',current_date);

  -- دور مخصص: scope محدد لموظفين — لإثبات أن أي scope لا يكسر العزل.
  insert into public.roles(slug, name_ar, name_en, description, is_system, is_full_access)
    values ('iso-0572-sel', 'مشاهد 0572', 'ISO 0572 Viewer', 'دور اختبار 0572', true, false);
  insert into public.role_permissions(role_id, permission_id, scope)
    select r.id, p.id, 'selected_employees'
      from public.roles r join public.permissions p on p.code = 'people.employee.read'
     where r.slug = 'iso-0572-sel'
     on conflict do nothing;

  insert into public.user_roles(user_id, role_id, effective_from)
    select t.u, r.id, now() - interval '1 year'
    from (values
      ('d5720000-0000-4000-8000-000000000501'::uuid,'employee'),
      ('d5720000-0000-4000-8000-000000000502'::uuid,'clinic-staff'),
      ('d5720000-0000-4000-8000-000000000503'::uuid,'clinics-manager'),
      ('d5720000-0000-4000-8000-000000000504'::uuid,'hr-manager'),
      ('d5720000-0000-4000-8000-000000000505'::uuid,'employee'),
      ('d5720000-0000-4000-8000-000000000506'::uuid,'executive'),
      ('d5720000-0000-4000-8000-000000000507'::uuid,'department-manager'),
      ('d5720000-0000-4000-8000-000000000510'::uuid,'clinics-manager')
    ) t(u,slug) join public.roles r on r.slug=t.slug;

  insert into public.user_roles(user_id, role_id, effective_from, scope_override)
    select 'd5720000-0000-4000-8000-000000000508', r.id, now() - interval '1 year',
           jsonb_build_object('employee_ids', array[
             'd5720000-0000-4000-8000-000000001502',
             'd5720000-0000-4000-8000-000000001501'])
      from public.roles r where r.slug = 'iso-0572-sel';

  -- مدير العيادات الحقيقي (0617): طلبات موقع طاقم العيادات تُحوَّل له.
  insert into auth.users(id, email, aud, role) values
    ('3e950d11-b5b4-4652-9ecf-919c434222fc','u572-cmgr@test.local','authenticated','authenticated')
    on conflict (id) do nothing;
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c','3e950d11-b5b4-4652-9ecf-919c434222fc','D572-CM','مدير العيادات الرئيسي 572',v_d9,'active',true,current_date - 1100)
    on conflict (id) do nothing;
  insert into public.profiles(id, employee_id, status) values
    ('3e950d11-b5b4-4652-9ecf-919c434222fc','4120ce3a-8999-453e-8d9d-acd8f3b5f04c','active')
    on conflict (id) do nothing;
  insert into public.user_roles(user_id, role_id, effective_from)
    select '3e950d11-b5b4-4652-9ecf-919c434222fc', r.id, now() - interval '1 year'
      from public.roles r where r.slug = 'clinics-manager'
    on conflict do nothing;

  -- دليل الموقع يتطلب live_location.request (0017/0444): يُمنح هنا
  -- لـ clinics-manager — نموذج الدور direct-manager منحها عند إنشاء الدور
  -- فقط (0474 على conflict do nothing) وبقيت فجوة بعده؛ الاختبار يثبت
  -- محتوى الدليل لا توزيع الصلاحيات.
  insert into public.role_permissions(role_id, permission_id, scope)
    select cr.id, p.id, tp.scope
      from public.roles cr
      join public.permissions p on p.code = 'live_location.request'
      join public.roles tr on tr.slug = 'direct-manager'
      join public.role_permissions tp on tp.role_id = tr.id and tp.permission_id = p.id
     where cr.slug = 'clinics-manager'
    on conflict do nothing;

  -- كتالوج الهيكل (0025) وشجرة الموبايل يتطلبان organization.org_chart.read —
  -- يُمنح لـ department-manager هنا (نموذج دوره لم يشمل صلاحيات الهيكل)؛
  -- الاختباران يثبتان فلترة العيادات من المحتوى لا توزيع الصلاحيات.
  insert into public.role_permissions(role_id, permission_id)
    select r.id, p.id
      from public.roles r, public.permissions p
     where r.slug = 'department-manager'
       and p.code = 'organization.org_chart.read'
    on conflict do nothing;
end $fixture$;

create or replace function pg_temp.act_as_0572(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- 1) المساعدات: عزل بالدور حتى في قسم غير معزول.
-- =====================================================================
select is(
  (select public.is_employee_isolated('d5720000-0000-4000-8000-000000001502'::uuid)),
  true, 'موظف العيادات معزول بالدور رغم أن قسمه غير معزول');
select is(
  (select public.is_employee_isolated('d5720000-0000-4000-8000-000000001501'::uuid)),
  false, 'الموظف العادي غير معزول');
select is(
  (select public.employee_blocks_inbound_alerts('d5720000-0000-4000-8000-000000001502'::uuid)),
  true, 'موظف العيادات يحجب الإشعارات الواردة');
select is(
  (select public.employee_blocks_inbound_alerts('d5720000-0000-4000-8000-000000001501'::uuid)),
  false, 'الموظف العادي لا يحجب شيئاً');

-- =====================================================================
-- 2) مصيدة الإشعارات: منع كامل عدا نتيجة طلباته هو.
-- =====================================================================
insert into public.notifications(recipient_user_id, recipient_employee_id, title, body, category, priority, entity_type)
values ('d5720000-0000-4000-8000-000000000502','d5720000-0000-4000-8000-000000001502',
        'إعلان شامل', 'اختبار المنع', 'announcement', 'normal', 'announcement');
select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = 'd5720000-0000-4000-8000-000000001502'),
  0, 'إشعار عام لموظف العيادات مرفوض قبل الكتابة');

insert into public.notifications(recipient_user_id, recipient_employee_id, title, body, category, priority, entity_type)
values ('d5720000-0000-4000-8000-000000000501','d5720000-0000-4000-8000-000000001501',
        'إعلان عام', 'اختبار السماح', 'announcement', 'normal', 'announcement');
select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = 'd5720000-0000-4000-8000-000000001501'
      -- محفّز تعيين الأدوار (0164/0171) أضاف «تم منحك دوراً» مع الإدراج؛
      -- نحصر العدّ على الإعلان نفسه وهو المقصود بالسماح.
      and entity_type = 'announcement'),
  1, 'إشعار الموظف العادي يمر كالمعتاد');

do $mkreq$
declare v_req uuid;
begin
  insert into public.requests(employee_id, request_type, manager_employee_id, title, status, workflow_status)
  values ('d5720000-0000-4000-8000-000000001502', 'leave',
          'd5720000-0000-4000-8000-000000001503', 'إجازة موظف العيادة', 'pending', 'submitted')
  returning id into v_req;

  insert into public.notifications(recipient_user_id, recipient_employee_id, title, body, category, priority, entity_type, entity_id)
  values ('d5720000-0000-4000-8000-000000000502','d5720000-0000-4000-8000-000000001502',
          'تمت الموافقة على طلبك', 'نتيجة طلبك', 'request', 'high', 'request', v_req);
end $mkreq$;
select is(
  (select count(*)::int from public.notifications
    where recipient_employee_id = 'd5720000-0000-4000-8000-000000001502'
      and entity_type = 'request'),
  1, 'نتيجة طلبه هو تمر للمستلم (الاستثناء الوحيد)');

-- =====================================================================
-- 3) الرؤية المتبادلة واستثناءات الدور.
-- =====================================================================
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000504');
select is(
  (select public.can_view_isolated_employee('d5720000-0000-4000-8000-000000001502'::uuid)),
  true, 'HR يرى موظف العيادات (استثناء دور صريح)');
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000510');
select is(
  (select public.can_view_isolated_employee('d5720000-0000-4000-8000-000000001502'::uuid)),
  true, 'مدير عيادات بلا علاقة إشراف يرى موظف العيادات (استثناء الدور)');
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000501');
select is(
  (select public.can_view_isolated_employee('d5720000-0000-4000-8000-000000001502'::uuid)),
  false, 'الموظف العادي لا يرى موظف العيادات');
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000502');
select is(
  (select public.can_see_directory_entry(
     'd5720000-0000-4000-8000-000000001502'::uuid,
     'd5720000-0000-4000-8000-000000001501'::uuid)),
  false, 'موظف العيادات لا يظهر له عام الفريق');
select is(
  (select public.can_see_directory_entry(
     'd5720000-0000-4000-8000-000000001502'::uuid,
     'd5720000-0000-4000-8000-000000001503'::uuid)),
  true, 'موظف العيادات يرى مديره المباشر فقط');

-- =====================================================================
-- 4) can_access: أي scope لا يكسر العزل.
-- =====================================================================
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000508');
select is(
  (select public.can_access_employee(
     'd5720000-0000-4000-8000-000000001502'::uuid, 'people.employee.read')),
  false, 'scope محدَّد للموظف لا يتجاوز عزل الهدف غير المرئي له');
select is(
  (select public.can_access_employee(
     'd5720000-0000-4000-8000-000000001501'::uuid, 'people.employee.read')),
  true, 'والمستخدم نفسه scope يعمل للموظف غير المعزول');

-- =====================================================================
-- 5) حظر طلبات الموقع والحضور.
-- =====================================================================
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000506');
-- 0617: الطلب لم يعد مرفوضاً — يُحوَّل لمدير العيادات ولا يطال الموظفة.
select lives_ok(
  $$select public.request_live_location('d5720000-0000-4000-8000-000000001502', 'snapshot', 'اختبار')$$,
  'طلب موقع موظفة العيادات يمر بعد التحويل لمدير العيادات');
-- ملاحظة: requested_by يخزّن معرّف الموظف (1506) لا معرّف المستخدم (0506).
select is(
  (select r.employee_id from public.live_location_requests r
    where r.requested_by = 'd5720000-0000-4000-8000-000000001506'
    order by r.requested_at desc limit 1),
  '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
  'الطلب يُوجَّه لمدير العيادات لا لموظفة العيادات نفسها');
select is(
  (select r.metadata->>'originalTargetEmployeeId' from public.live_location_requests r
    where r.requested_by = 'd5720000-0000-4000-8000-000000001506'
    order by r.requested_at desc limit 1),
  'd5720000-0000-4000-8000-000000001502',
  'الهدف الأصلي محفوظ في البيانات الوصفية');

select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000502');
select throws_ok(
  $$select public.get_attendance_day_roster(current_date::date, null::uuid, null::uuid, null::uuid)$$,
  '42501', null,
  'موظف العيادات لا يفتح دفتر حضور الآخرين');

select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000503');
select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_location_directory(null, 100)) x
     where x->>'id' = 'd5720000-0000-4000-8000-000000001505'),
  'دليل الموقع يعرض المرؤوس غير المعزول');
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_location_directory(null, 100)) x
     where x->>'id' = 'd5720000-0000-4000-8000-000000001502'),
  'دليل الموقع يستبعد موظف العيادات مطلقاً حتى لمديره');

-- =====================================================================
-- 6) تنبيه البث الشامل.
-- =====================================================================
insert into public.broadcast_alerts(id, message, created_by, expires_at, is_active)
values ('d5720000-0000-4000-8000-000000000701', 'تنبيه بث تجريبي 0572',
        'd5720000-0000-4000-8000-000000001501', now() + interval '1 hour', true);

select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000502');
select is(
  (select public.get_active_broadcast_alert()),
  null::jsonb, 'موظف العيادات لا يرى تنبيه البث');
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000501');
select ok(
  (select public.get_active_broadcast_alert()) is not null,
  'الموظف العادي يرى تنبيه البث');

-- =====================================================================
-- 7) كتالوج الهيكل: الأسماء تبقى، والموظفون والأعداد مصفّاة.
-- =====================================================================
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000507');
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      (select public.get_organization_admin_catalog())->'employees') x
     where x->>'id' = 'd5720000-0000-4000-8000-000000001502'),
  'الكتالوج لا يعرض موظف العيادات لغير المرئين له');
select is(
  (select (d->>'employeeCount')::int
     from jsonb_array_elements(
       (select public.get_organization_admin_catalog())->'departments') d
    where d->>'id' = 'd5720000-0000-4000-8000-000000000002'),
  3, 'عدد موظفي القسم لا يحوي موظف العيادات (3 من 4)');
select ok(
  exists (
    select 1 from jsonb_array_elements(
      (select public.get_organization_admin_catalog())->'departments') d
     where d->>'id' = 'd5720000-0000-4000-8000-000000000002'),
  'اسم القسم يبقى ظاهراً في الكتالوج');

-- =====================================================================
-- 8) شجرة الموبايل: بوابة + فلتر.
-- =====================================================================
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000502');
select throws_ok(
  $$select public.get_mobile_org_chart()$$,
  '42501', null,
  'موظف العيادات لا يفتح شجرة الهيكل');
select pg_temp.act_as_0572('d5720000-0000-4000-8000-000000000507');
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      (select public.get_mobile_org_chart())->'employees') x
     where x->>'id' = 'd5720000-0000-4000-8000-000000001502'),
  'شجرة الموبايل تحذف موظف العيادات عن غير المرئين له');

rollback;
