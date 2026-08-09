-- 0352: قاعدة المعرفة — تصنيفات مُدارة + RPC كتالوج + صلاحيات
-- تغطية: جدول knowledge_categories، ربط category_id، RLS، صلاحية knowledge.manage،
-- RPC get_knowledge_catalog (بحث server-side)، RPC upsert/delete_knowledge_category.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(23);
insert into auth.users(id,email,aud,role) values
 ('83500000-0000-4000-8000-000000000001','kno-hr@test.local','authenticated','authenticated'),
 ('83500000-0000-4000-8000-000000000002','kno-emp@test.local','authenticated','authenticated'),
 ('83500000-0000-4000-8000-000000000003','kno-admin@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('84500000-0000-4000-8000-000000000001','83500000-0000-4000-8000-000000000001','KNO-HR','مسؤول HR للاختبار','active',true),
 ('84500000-0000-4000-8000-000000000002','83500000-0000-4000-8000-000000000002','KNO-EMP','موظف المعرفة للاختبار','active',true),
 ('84500000-0000-4000-8000-000000000003','83500000-0000-4000-8000-000000000003','KNO-ADM','أدمن للاختبار','active',true);

insert into public.profiles(id,employee_id,status)
select user_id,id,'active' from public.employees
where id between '84500000-0000-4000-8000-000000000001' and '84500000-0000-4000-8000-000000000003';

insert into public.user_roles(user_id,role_id,effective_from)
select x.user_id,r.id,now()
from (values
 ('83500000-0000-4000-8000-000000000001'::uuid,'hr-manager'),
 ('83500000-0000-4000-8000-000000000002'::uuid,'employee'),
 ('83500000-0000-4000-8000-000000000003'::uuid,'admin')
) x(user_id,slug) join public.roles r on r.slug=x.slug;

-- 1) بنية الجداول
select has_table('public','knowledge_categories','جدول التصنيفات موجود');
select has_column('public','knowledge_categories','slug','عمود slug');
select has_column('public','knowledge_categories','name','عمود name');
select has_column('public','knowledge_categories','is_active','عمود is_active');
select has_column('public','knowledge_articles','category_id','مقالة معرفة لها category_id');
select col_is_null('public','knowledge_articles','category_id','category_id قابلة للفارغ');

-- 2) RLS مفعلة
select ok(
  (select relrowsecurity from pg_class where oid = 'public.knowledge_categories'::regclass),
  'RLS مفعلة على التصنيفات'
);

-- 3) الصلاحية knowledge.manage موجودة وممنوحة
select ok(
  exists(select 1 from public.permissions where code = 'knowledge.manage'),
  'الصلاحية knowledge.manage موجودة في كتالوج الصلاحيات'
);
select ok(
  exists(
    select 1 from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'hr-manager' and p.code = 'knowledge.manage'
  ),
  'hr-manager يملك knowledge.manage'
);
select ok(
  exists(
    select 1 from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.slug = 'system-admin' and p.code = 'knowledge.manage'
  ),
  'system-admin يملك knowledge.manage'
);

-- 4) الفهرس trigram للبحث
select has_index('public','knowledge_articles','idx_knowledge_articles_search_trgm','فهرس البحث trigram موجود');

-- 5) الدوال
select has_function('public','get_knowledge_catalog',array['text','uuid','text','int','int'],'دالة كتالوج المعرفة موجودة');
select has_function('public','upsert_knowledge_category',array['uuid','text','text','text','boolean'],'دالة إنشاء/تعديل التصنيف موجودة');
select has_function('public','delete_knowledge_category',array['uuid'],'دالة حذف التصنيف موجودة');

-- 6) بيانات تجريبية (كمسؤول postgres ثم نفحص عبر الأدوار)
insert into public.knowledge_categories (id,slug,name,is_active) values
 ('85500000-0000-4000-8000-000000000001','procedures','إجراءات',true);
insert into public.knowledge_articles (id,title,category_id,is_published) values
 ('85500000-0000-4000-8000-000000000002','مقال منشور','85500000-0000-4000-8000-000000000001',true),
 ('85500000-0000-4000-8000-000000000003','مقال مسودة','85500000-0000-4000-8000-000000000001',false);

-- 7) RLS: الموظف العادي يقرأ المنشور فقط
set local role authenticated;
select set_config('request.jwt.claim.sub','83500000-0000-4000-8000-000000000002',true);
select results_eq(
  'select count(*)::int from public.knowledge_articles where is_published = false',
  array[0::int],
  'الموظف العادي لا يرى المسودات عبر RLS'
);
select results_eq(
  'select count(*)::int from public.knowledge_articles where is_published = true',
  array[1::int],
  'الموظف العادي يرى المقالات المنشورة'
);
reset role;
select set_config('request.jwt.claim.sub',null,true);

-- 8) RPC الكتالوج: مدير HR يرى المسودات ويحصل على manage=true
select set_config('request.jwt.claim.sub','83500000-0000-4000-8000-000000000001',true);
select is(
  (public.get_knowledge_catalog(p_query => 'منشور', p_status => 'published'))->>'manage',
  'true',
  'مدير HR يحصل على manage=true في الكتالوج'
);
select is(
  (select jsonb_array_length(public.get_knowledge_catalog(p_status => 'draft')->'articles')),
  1,
  'الكتالوج يرجع المسودات للمدير'
);

-- 9) upsert/delete التصنيفات كمدير HR
select lives_ok(
  'select public.upsert_knowledge_category(p_slug => ''policies'', p_name => ''سياسات'')',
  'مدير HR يستطيع إنشاء تصنيف'
);
select lives_ok(
  'select public.upsert_knowledge_category(p_id => ''85500000-0000-4000-8000-000000000001'', p_slug => ''procedures'', p_name => ''إجراءات محدثة'')',
  'مدير HR يستطيع تعديل تصنيف'
);
select lives_ok(
  'select public.delete_knowledge_category(''85500000-0000-4000-8000-000000000001'')',
  'مدير HR يستطيع حذف تصنيف'
);

-- 10) الموظف العادي مرفوض من إدارة التصنيفات (FORBIDDEN)
reset role;
select set_config('request.jwt.claim.sub',null,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','83500000-0000-4000-8000-000000000002',true);
select throws_ok(
  'select public.upsert_knowledge_category(p_slug => ''x'', p_name => ''x'')',
  'FORBIDDEN',
  'موظف عادي لا يستطيع إنشاء تصنيف'
);
select throws_ok(
  'select public.delete_knowledge_category(''85500000-0000-4000-8000-000000000001'')',
  'FORBIDDEN',
  'موظف عادي لا يستطيع حذف تصنيف'
);

rollback;
