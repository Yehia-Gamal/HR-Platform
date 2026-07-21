begin;
select plan(24);

select has_table('public','app_release_policies','release policy table exists');
select has_table('public','managed_devices','managed devices table exists');
select has_table('public','access_review_campaigns','access review campaigns table exists');
select has_table('public','access_review_items','access review items table exists');
select has_table('public','break_glass_requests','break glass table exists');
select has_table('public','privacy_requests','privacy requests table exists');
select has_table('public','integration_outbox','integration outbox table exists');
select has_function('public','get_public_release_policy',array['text','text','text','integer','text'],'public release policy RPC exists');
select has_function('public','register_my_device',array['text','text','text','text','text','text','integer','text','boolean','boolean','jsonb'],'device registration RPC exists');
select has_function('public','get_release_governance_overview',array[]::text[],'governance overview RPC exists');
select has_function('public','create_access_review_campaign',array['text','text','timestamp with time zone'],'access review RPC exists');
select has_function('public','decide_access_review_item',array['uuid','text','text'],'access decision RPC exists');
select has_function('public','request_break_glass',array['uuid','uuid','integer','text'],'break glass request RPC exists');
select has_function('public','approve_break_glass',array['uuid','text'],'break glass approval RPC exists');
select has_function('public','submit_privacy_request',array['text','text'],'privacy submission RPC exists');
select has_function('public','enqueue_integration_event',array['uuid','text','text','uuid','text','jsonb','jsonb','text'],'integration enqueue RPC exists');
select ok((select relrowsecurity from pg_class where oid = 'public.app_release_policies'::regclass),'release policies RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.managed_devices'::regclass),'managed devices RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.privacy_requests'::regclass),'privacy requests RLS enabled');
select is((select count(*)::integer from public.app_release_policies),9,'default policies seeded for three platforms and environments');
select ok(exists(
  select 1 from public.permissions where code = 'system.release.manage'
),'release management permission seeded');
select ok(exists(
  select 1
  from public.role_permissions rp
  join public.roles r on r.id = rp.role_id
  join public.permissions p on p.id = rp.permission_id
  where r.slug = 'system-admin' and p.code = 'access.review.manage' and rp.scope = 'organization'
),'system admin receives access review management');
select ok(exists(
  select 1
  from public.role_permissions rp
  join public.roles r on r.id = rp.role_id
  join public.permissions p on p.id = rp.permission_id
  where r.slug = 'executive-secretary' and p.code = 'system.release.read' and rp.scope = 'organization'
),'executive secretary receives release read only');
select ok(exists(
  select 1
  from public.role_permissions rp
  join public.roles r on r.id = rp.role_id
  join public.permissions p on p.id = rp.permission_id
  where r.slug = 'hr-manager' and p.code = 'privacy.request.manage' and rp.scope = 'organization'
),'HR manager receives privacy request management');

select * from finish();
rollback;
