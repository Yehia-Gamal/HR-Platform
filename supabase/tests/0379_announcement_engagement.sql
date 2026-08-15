begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(21);

select has_table('public','announcement_views','announcement views table exists');
select has_table('public','announcement_reactions','announcement reactions table exists');
select has_function('public','record_announcement_view',array['uuid'],'record view RPC exists');
select has_function('public','toggle_announcement_reaction',array['uuid','text'],'reaction RPC exists');
select has_function('public','get_announcement_engagement',array['uuid'],'engagement roster RPC exists');
select has_trigger('public','notifications','trg_notifications_nudge_dispatcher','notifications wake dispatcher');
select has_trigger('public','request_steps','trg_request_step_activated_notify','next approver notification trigger exists');
select has_trigger('public','requests','trg_casual_leave_auto_approved_notify','casual leave notification trigger exists');

insert into public.legal_entities(id,code,name) values
('35800000-0000-4000-8000-000000000001','LE-358','كيان اختبار التفاعل');
insert into public.departments(id,legal_entity_id,code,name) values
('35800000-0000-4000-8000-000000000002','35800000-0000-4000-8000-000000000001','D-358','إدارة الاختبار');
insert into auth.users(id,email,aud,role) values
('35800000-0000-4000-8000-000000000011','publisher358@test.local','authenticated','authenticated'),
('35800000-0000-4000-8000-000000000012','viewer358@test.local','authenticated','authenticated');
insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active) values
('35800000-0000-4000-8000-000000000021','35800000-0000-4000-8000-000000000011','E358-P','ناشر الاختبار','35800000-0000-4000-8000-000000000002','active',true),
('35800000-0000-4000-8000-000000000022','35800000-0000-4000-8000-000000000012','E358-V','مشاهد الاختبار','35800000-0000-4000-8000-000000000002','active',true);
insert into public.profiles(id,employee_id,status) values
('35800000-0000-4000-8000-000000000011','35800000-0000-4000-8000-000000000021','active'),
('35800000-0000-4000-8000-000000000012','35800000-0000-4000-8000-000000000022','active');
insert into public.user_roles(user_id,role_id)
select '35800000-0000-4000-8000-000000000011',id from public.roles where is_full_access limit 1;
insert into public.announcements(id,title,body,category,priority,status,target_type,published_at,created_by)
values('35800000-0000-4000-8000-000000000031','إعلان اختبار التفاعل','هذا محتوى إعلان اختبار التفاعل الكامل.','general','normal','published','all',now(),'35800000-0000-4000-8000-000000000011');
delete from public.notifications where entity_id='35800000-0000-4000-8000-000000000031';

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',json_build_object('sub',p_user::text,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',p_user::text,true);
end $$;

select pg_temp.act_as('35800000-0000-4000-8000-000000000012');
set local role authenticated;
select lives_ok($$select public.record_announcement_view('35800000-0000-4000-8000-000000000031')$$,'viewer records first view');
select lives_ok($$select public.record_announcement_view('35800000-0000-4000-8000-000000000031')$$,'viewer records repeated view');
select is((select count(*)::integer from public.announcement_views where announcement_id='35800000-0000-4000-8000-000000000031'),1,'one viewer row per employee');
select is((select view_count from public.announcement_views where announcement_id='35800000-0000-4000-8000-000000000031'),2,'repeat open increments view count');
select lives_ok($$select public.toggle_announcement_reaction('35800000-0000-4000-8000-000000000031','like')$$,'viewer reacts');
reset role;

select is((select count(*)::integer from public.announcement_reactions where announcement_id='35800000-0000-4000-8000-000000000031'),1,'reaction stored');
select is((select count(*)::integer from public.notifications where recipient_employee_id='35800000-0000-4000-8000-000000000021' and metadata->>'kind'='announcement_reaction'),1,'publisher notified about reaction');

select pg_temp.act_as('35800000-0000-4000-8000-000000000011');
set local role authenticated;
select is((public.get_announcement_engagement('35800000-0000-4000-8000-000000000031')->>'viewerCount')::integer,1,'publisher sees viewer count');
select is((public.get_announcement_engagement('35800000-0000-4000-8000-000000000031')->'viewers'->0->>'name'),'مشاهد الاختبار','publisher sees viewer name');
reset role;

select pg_temp.act_as('35800000-0000-4000-8000-000000000012');
set local role authenticated;
select is((public.get_announcement_engagement('35800000-0000-4000-8000-000000000031')->>'viewerCount')::integer,1,'ordinary employee sees viewer count (0425 relax guard)');
select is((public.get_announcement_engagement('35800000-0000-4000-8000-000000000031')->'viewers'->0->>'name'),'مشاهد الاختبار','ordinary employee sees viewer name (0425 relax guard)');
select lives_ok($$select public.toggle_announcement_reaction('35800000-0000-4000-8000-000000000031','like')$$,'same reaction toggles off');
reset role;
select is((select count(*)::integer from public.announcement_reactions where announcement_id='35800000-0000-4000-8000-000000000031'),0,'toggle removes reaction');

select * from finish();
rollback;
