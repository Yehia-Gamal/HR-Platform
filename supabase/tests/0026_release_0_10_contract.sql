begin;
select plan(4);

select is(
  (select count(*)::integer from public.app_release_policies where latest_version = '0.10.0' and latest_build = 10),
  9,
  'all platform and environment policies point to 0.10.0 build 10'
);
select is(
  (select min_supported_build from public.app_release_policies where platform='android' and environment='staging'),
  10,
  'staging requires build 10'
);
select is(
  (select min_supported_build from public.app_release_policies where platform='android' and environment='production'),
  9,
  'production still permits build 9 during optional rollout'
);
select is(
  (select count(*)::integer from public.app_release_policies where force_update),
  0,
  '0.10 release does not force update before device verification'
);

select * from finish();
rollback;
