begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(4);

-- Test 1: helper function exists
select has_function(
  'public', '_request_idempotency_key',
  ARRAY['uuid','text','date','date'],
  '_request_idempotency_key helper should exist'
);

-- Test 2: function is immutable (deterministic)
select is(
  (select provolatile::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='_request_idempotency_key'),
  'i'::text,
  '_request_idempotency_key should be IMMUTABLE'
);

-- Test 3: same inputs produce same UUID
select is(
  public._request_idempotency_key('00000001-0000-0000-0000-000000000001'::uuid, 'leave', '2026-09-01'::date, '2026-09-03'::date),
  public._request_idempotency_key('00000001-0000-0000-0000-000000000001'::uuid, 'leave', '2026-09-01'::date, '2026-09-03'::date),
  'same inputs should produce same idempotency key'
);

-- Test 4: different inputs produce different UUIDs
select isnt(
  public._request_idempotency_key('00000001-0000-0000-0000-000000000001'::uuid, 'leave', '2026-09-01'::date, '2026-09-03'::date),
  public._request_idempotency_key('00000001-0000-0000-0000-000000000001'::uuid, 'leave', '2026-09-01'::date, '2026-09-04'::date),
  'different end dates should produce different keys'
);

select finish();
rollback;
