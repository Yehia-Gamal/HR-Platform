begin;
select plan(12);

select col_is_pk('public','webauthn_challenges','id','WebAuthn challenges have a primary key');
select has_column('public','webauthn_challenges','options_json','server options JSON is persisted');
select has_column('public','webauthn_challenges','relying_party_id','RP ID is persisted');
select has_column('public','passkey_credentials','webauthn_user_id','WebAuthn user ID is persisted');
select has_column('public','passkey_credentials','credential_device_type','credential device type is persisted');
select has_column('public','passkey_credentials','credential_backed_up','credential backup state is persisted');

select function_privs_are(
  'public','get_mobile_action_target',array['text','text'],'authenticated',array['EXECUTE'],
  'authenticated users can resolve only authorized action targets'
);
select function_privs_are(
  'public','get_mobile_request_detail',array['uuid'],'authenticated',array['EXECUTE'],
  'authenticated users can read authorized request details'
);

select ok(
  not has_table_privilege('authenticated','public.webauthn_challenges','INSERT'),
  'authenticated cannot create server challenges directly'
);
select ok(
  not has_table_privilege('authenticated','public.passkey_credentials','INSERT'),
  'authenticated cannot register passkeys directly'
);
select ok(
  not has_table_privilege('authenticated','public.passkey_credentials','UPDATE'),
  'authenticated cannot change passkey trust or counters directly'
);
select ok(
  not has_table_privilege('authenticated','public.passkey_credentials','DELETE'),
  'authenticated cannot delete passkeys directly'
);

select * from finish();
rollback;
