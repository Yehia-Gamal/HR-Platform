-- 0057: V17 §18 — نشر المنشورات الرسمية (migration 0133).
-- إضافة posts.publish + publisher_channel + publish_announcement RPC.
-- اختبارات: وجود الصلاحية، العمود، الدالة، مسار النشر السعيد،
-- رفض القناة الخاطئة، رفض غير المسودة، رفض غير المخوّل، وRLS.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

-- ══════════════════════════════════════════════════════════════════════════════════
-- 1. التحقق من البنية — الصلاحية، العمود، الدالة
-- ══════════════════════════════════════════════════════════════════════════════════

-- 1. صلاحية posts.publish موجودة في جدول permissions
select ok(
  (select exists(select 1 from public.permissions where code = 'posts.publish')),
  'صلاحية posts.publish موجودة في جدول permissions'
);

-- 2. عمود publisher_channel موجود على جدول announcements
select has_column(
  'announcements', 'publisher_channel',
  'عمود publisher_channel موجود على جدول announcements'
);

-- 3. دالة publish_announcement موجودة
select has_function(
  'public', 'publish_announcement', array['uuid','text'],
  'دالة publish_announcement(uuid, text) موجودة'
);

-- ══════════════════════════════════════════════════════════════════════════════════
-- البيانات التجريبية (Fixtures)
-- ══════════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a5700000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a5700000-0000-4000-8000-000000000010';
begin
  -- الكيان القانوني والقسم
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-PUB-LE', 'كيان نشر V17');
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V17-PUB-D', 'إدارة نشر V17');

  -- 3 مستخدمين: admin (full-access)، hr-specialist (لديه posts.publish)، employee (بدون صلاحية نشر)
  insert into auth.users(id, email, aud, role) values
    ('a5700000-0000-4000-8000-000000000101', 'v17pub-admin@test.local',  'authenticated', 'authenticated'),
    ('a5700000-0000-4000-8000-000000000102', 'v17pub-hr@test.local',     'authenticated', 'authenticated'),
    ('a5700000-0000-4000-8000-000000000103', 'v17pub-emp@test.local',    'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a5700000-0000-4000-8000-000000000201', 'a5700000-0000-4000-8000-000000000101', 'PB-ADM', 'مدير النشر',    v_dept, 'active', true, false),
    ('a5700000-0000-4000-8000-000000000202', 'a5700000-0000-4000-8000-000000000102', 'PB-HR',  'أخصائي HR',     v_dept, 'active', true, false),
    ('a5700000-0000-4000-8000-000000000203', 'a5700000-0000-4000-8000-000000000103', 'PB-EMP', 'موظف عادي',     v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a5700000-0000-4000-8000-000000000101', 'a5700000-0000-4000-8000-000000000201', 'active'),
    ('a5700000-0000-4000-8000-000000000102', 'a5700000-0000-4000-8000-000000000202', 'active'),
    ('a5700000-0000-4000-8000-000000000103', 'a5700000-0000-4000-8000-000000000203', 'active');

  -- admin = full-access
  insert into public.user_roles(user_id, role_id)
  select 'a5700000-0000-4000-8000-000000000101', id from public.roles where slug = 'admin';

  -- hr-specialist = لديه posts.publish
  insert into public.user_roles(user_id, role_id)
  select 'a5700000-0000-4000-8000-000000000102', id from public.roles where slug = 'hr-specialist';

  -- employee = بدون صلاحية نشر
  insert into public.user_roles(user_id, role_id)
  select 'a5700000-0000-4000-8000-000000000103', id from public.roles where slug = 'employee';

  -- إعلان مسودة للاختبار (901)
  insert into public.announcements(id, title, body, status, created_by)
  values(
    'a5700000-0000-4000-8000-000000000901',
    'إعلان اختبار المسودة',
    'هذا إعلان تجريبي في حالة مسودة',
    'draft',
    'a5700000-0000-4000-8000-000000000101'
  );

  -- إعلان منشور مسبقاً (902) — لاختبار رفض غير المسودة
  insert into public.announcements(id, title, body, status, published_at, created_by)
  values(
    'a5700000-0000-4000-8000-000000000902',
    'إعلان منشور مسبقاً',
    'هذا الإعلان منشور بالفعل',
    'published',
    now(),
    'a5700000-0000-4000-8000-000000000101'
  );
end
$fixture$;

-- دالة مساعدة لتغيير هوية المستخدم الحالي
create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ══════════════════════════════════════════════════════════════════════════════════
-- 4. publish_announcement: مسار النشر السعيد — admin (full-access)
-- ══════════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a5700000-0000-4000-8000-000000000101');
set local role authenticated;

-- 4. publish_announcement ينجح للمستخدم ذي full-access
select lives_ok(
  $$select public.publish_announcement('a5700000-0000-4000-8000-000000000901')$$,
  'publish_announcement ينجح للمستخدم ذي full-access'
);

-- 5. بعد النشر: الحالة = published
select is(
  (select status from public.announcements where id = 'a5700000-0000-4000-8000-000000000901'),
  'published',
  'الحالة تتحول إلى published بعد النشر'
);

-- 6. بعد النشر: publisher_channel = web (الافتراضي)
select is(
  (select publisher_channel from public.announcements where id = 'a5700000-0000-4000-8000-000000000901'),
  'web',
  'publisher_channel = web عند النشر بدون تحديد القناة'
);

-- ══════════════════════════════════════════════════════════════════════════════════
-- 7. إعادة الإعلان إلى مسودة لاختبارات إضافية
-- ══════════════════════════════════════════════════════════════════════════════════

reset role;
update public.announcements
  set status = 'draft', publisher_channel = null, published_at = null
where id = 'a5700000-0000-4000-8000-000000000901';

-- ══════════════════════════════════════════════════════════════════════════════════
-- 8. publish_announcement: قناة mobile تعمل
-- ══════════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a5700000-0000-4000-8000-000000000101');
set local role authenticated;

select lives_ok(
  $$select public.publish_announcement('a5700000-0000-4000-8000-000000000901', 'mobile')$$,
  'publish_announcement ينجح مع القناة mobile'
);

select is(
  (select publisher_channel from public.announcements where id = 'a5700000-0000-4000-8000-000000000901'),
  'mobile',
  'publisher_channel = mobile بعد النشر عبر القناة mobile'
);

-- ══════════════════════════════════════════════════════════════════════════════════
-- 9. publish_announcement: رفض القناة غير الصالحة
-- ══════════════════════════════════════════════════════════════════════════════════

-- إعادة الإعلان إلى مسودة مباشرةً كـ superuser قبل الاختبار
reset role;
update public.announcements
  set status = 'draft', publisher_channel = null, published_at = null
where id = 'a5700000-0000-4000-8000-000000000901';

select pg_temp.act_as('a5700000-0000-4000-8000-000000000101');
set local role authenticated;

select throws_ok(
  $$select public.publish_announcement('a5700000-0000-4000-8000-000000000901', 'sms')$$,
  '22023', null,
  'publish_announcement يرفض القناة غير الصالحة (sms)'
);

-- ══════════════════════════════════════════════════════════════════════════════════
-- 10. publish_announcement: رفض إعلان منشور مسبقاً (ليس مسودة)
-- ══════════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.publish_announcement('a5700000-0000-4000-8000-000000000902')$$,
  'P0002', null,
  'publish_announcement يرفض الإعلان المنشور مسبقاً (ليس مسودة)'
);

-- ══════════════════════════════════════════════════════════════════════════════════
-- 11–14. اختبارات RLS
-- ══════════════════════════════════════════════════════════════════════════════════

-- 11. RLS: الموظف يستطيع قراءة الإعلانات المنشورة
select pg_temp.act_as('a5700000-0000-4000-8000-000000000103');
set local role authenticated;

select ok(
  (select count(*)::int > 0
   from public.announcements
   where id = 'a5700000-0000-4000-8000-000000000902'
     and status = 'published'),
  'RLS: الموظف يستطيع قراءة الإعلانات المنشورة'
);

-- 12. RLS: الموظف لا يستطيع إدراج إعلانات
select throws_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values('إعلان غير مصرح به', 'محتوى', 'draft',
           'a5700000-0000-4000-8000-000000000103')$$,
  '42501', null,
  'RLS: الموظف لا يستطيع إدراج إعلانات (بدون صلاحية نشر)'
);

-- 13. RLS: أخصائي HR يستطيع إدراج إعلانات (لديه posts.publish)
select pg_temp.act_as('a5700000-0000-4000-8000-000000000102');
set local role authenticated;

select lives_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values('إعلان مسودة من HR', 'محتوى الإعلان التجريبي',
           'draft', 'a5700000-0000-4000-8000-000000000102')$$,
  'RLS: أخصائي HR يستطيع إدراج إعلانات (لديه posts.publish)'
);

-- 14. RLS: أخصائي HR يستطيع تحديث الإعلانات
select lives_ok(
  $$update public.announcements
      set title = 'إعلان مسودة من HR — معدّل'
    where created_by = 'a5700000-0000-4000-8000-000000000102'
      and status = 'draft'$$,
  'RLS: أخصائي HR يستطيع تحديث الإعلانات'
);

reset role;
select * from finish();
rollback;
