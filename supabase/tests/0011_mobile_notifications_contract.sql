begin;
select plan(3);

select has_function('public','get_my_notifications',array['integer']);
select function_privs_are(
  'public','get_my_notifications',array['integer'],'authenticated',array['EXECUTE'],
  'authenticated can read owner-scoped mobile notifications'
);
select function_privs_are(
  'public','mark_my_notifications_read',array['uuid[]'],'authenticated',array['EXECUTE'],
  'authenticated can mark owner notifications read'
);

select * from finish();
rollback;
