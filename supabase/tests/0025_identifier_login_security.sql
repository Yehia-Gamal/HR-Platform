begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

select has_table('public','login_auth_attempts','identifier login attempt ledger exists');
select has_column('public','login_auth_attempts','identifier_hash','identifier hash column exists');
select has_column('public','login_auth_attempts','ip_hash','IP hash column exists');
select ok((select relrowsecurity from pg_class where oid = 'public.login_auth_attempts'::regclass),'login attempt ledger has RLS enabled');
select is(
  (select count(*)::integer from pg_policies where schemaname='public' and tablename='login_auth_attempts'),
  0,
  'no client RLS policy exposes login attempt ledger'
);
select ok(has_table_privilege('anon','public.login_auth_attempts','SELECT') is false,'anon cannot read login attempts');
select ok(has_table_privilege('authenticated','public.login_auth_attempts','SELECT') is false,'authenticated users cannot read login attempts');

select * from finish();
rollback;
