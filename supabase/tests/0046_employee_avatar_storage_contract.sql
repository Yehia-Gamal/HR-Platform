begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(13);

-- Seed the people.employee.create permission if not already present
-- (this code is used in policies but the permission row may not exist yet).
insert into public.permissions(code,module,resource,action)
values ('people.employee.create','people','employee','create')
on conflict(code) do nothing;

insert into auth.users(id,email,aud,role) values
 ('95000000-0000-4000-8000-000000000001','avatar-employee@test.local','authenticated','authenticated'),
 ('95000000-0000-4000-8000-000000000002','avatar-hr@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('96000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','AVATAR-EMP','موظف اختبار الصورة','active',true),
 ('96000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000002','AVATAR-HR','مسؤول اختبار الصورة','active',true);

insert into public.profiles(id,employee_id,status) values
 ('95000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001','active'),
 ('95000000-0000-4000-8000-000000000002','96000000-0000-4000-8000-000000000002','active');

insert into public.user_roles(user_id,role_id,effective_from)
select x.user_id,r.id,now()
from (values
 ('95000000-0000-4000-8000-000000000001'::uuid,'employee'),
 ('95000000-0000-4000-8000-000000000002'::uuid,'hr-manager')
) x(user_id,slug)
join public.roles r on r.slug=x.slug;

-- Grant people.employee.create to hr-manager (the 0121 seed silently skips
-- when the permission row is absent; we ensure the grant here).
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'organization'
from public.roles r
join public.permissions p on p.code='people.employee.create'
where r.slug='hr-manager'
on conflict(role_id,permission_id,scope) do nothing;

select is((select public from storage.buckets where id='employee-avatars'),true,'employee avatar bucket is public');
select is((select file_size_limit from storage.buckets where id='employee-avatars'),5242880::bigint,'employee avatar bucket limits files to 5 MiB');
select ok((select allowed_mime_types @> array['image/jpeg','image/png','image/webp'] from storage.buckets where id='employee-avatars'),'employee avatar bucket allows the approved image formats');
select ok(exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='employee_avatars_select' and roles @> array['authenticated']::name[]),'authenticated-only avatar read policy remains installed');

select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',true);
set local role authenticated;

select lives_ok(
 $$insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('employee-avatars','95000000-0000-4000-8000-000000000001/avatar.png','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','{"mimetype":"image/png","size":1024}'::jsonb)$$,
 'employee uploads an avatar only inside the own auth folder');
select throws_ok(
 $$insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('employee-avatars','95000000-0000-4000-8000-000000000099/forbidden.png','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001','{"mimetype":"image/png","size":1024}'::jsonb)$$,
 '42501',null,'employee cannot upload into another auth folder');
select throws_ok(
 $$update storage.objects set name='95000000-0000-4000-8000-000000000099/moved.png' where bucket_id='employee-avatars' and name='95000000-0000-4000-8000-000000000001/avatar.png'$$,
 '42501',null,'employee cannot move an avatar into another auth folder');
select ok(
 exists(
   select 1 from pg_policies
   where schemaname='storage' and tablename='objects'
     and policyname='employee_avatars_manage_delete'
     and cmd='DELETE'
     and qual like '%foldername%auth.uid%'
 ),
 'avatar delete policy is restricted to the own auth folder or a manager');

reset role;
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select ok(public.has_permission('people.employee.create'),'HR fixture owns employee creation permission');
select lives_ok(
 $$insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('employee-avatars','admin/managed.webp','95000000-0000-4000-8000-000000000002','95000000-0000-4000-8000-000000000002','{"mimetype":"image/webp","size":1024}'::jsonb)$$,
 'HR uploads a managed employee avatar under the admin folder');

reset role;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select throws_ok(
 $$insert into storage.objects(bucket_id,name,metadata) values('employee-avatars','anonymous/avatar.png','{"mimetype":"image/png","size":1024}'::jsonb)$$,
 '42501',null,'anonymous users cannot upload employee avatars');
select is((select count(*)::integer from storage.objects where bucket_id='employee-avatars' and name='admin/managed.webp'),1,'anonymous can read a public avatar');

reset role;
select is((select count(*)::integer from storage.objects where bucket_id='employee-avatars' and name='admin/managed.webp'),1,'managed avatar insert exists for trusted server access');

select * from finish();
rollback;
