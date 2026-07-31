-- pgTAP test for migrations 0236 + 0239: employee-scoped selfie_path validation
-- inside finalize_verified_attendance.
--
-- 0235 (test 0087) covers the generic trigger layer (scheme/traversal/absolute).
-- This test covers what the trigger CANNOT: ownership scoping to the punching
-- employee's own folder <employee_id>/<yyyy>/<filename>. The selfie validation
-- runs after the service_role guard + event-type check but BEFORE the idempotency
-- INSERT, so a malformed path raises immediately without any seeded rows.
-- 0239 removed a broken chr(0) NUL check from 0236 that raised 54000 on every
-- non-empty path; this test asserts the corrected behaviour.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(17);

-- ── Function still exists with the same signature after CREATE OR REPLACE ──
select has_function(
  'public', 'finalize_verified_attendance',
  array['uuid','uuid','uuid','uuid','uuid','uuid','text','double precision','double precision','double precision','bigint','text','boolean'],
  '0236: finalizer signature unchanged');

select function_privs_are(
  'public', 'finalize_verified_attendance',
  array['uuid','uuid','uuid','uuid','uuid','uuid','text','double precision','double precision','double precision','bigint','text','boolean'],
  'authenticated', array[]::text[], '0236: authenticated still cannot call finalizer');

-- ── Static assertions: the scope + format checks are present in the body ──
select ok(
  position('invalid_selfie_path_scope' in pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  )) > 0,
  '0236: body enforces employee-folder scope');
select ok(
  position('invalid_selfie_path_format' in pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  )) > 0,
  '0236: body enforces structural format');
select ok(
  position('invalid_selfie_path_traversal' in pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  )) > 0,
  '0236: body rejects traversal');

-- ═══════════════════════════════════════════════════════════════════════════
-- Behavioural: call as service_role with crafted selfie paths. Selfie validation
-- fires before the idempotency INSERT, so we can assert the raised errcode
-- without seeding challenge/credential/device rows.
-- ═══════════════════════════════════════════════════════════════════════════
set local role service_role;
-- The finalizer reads request.jwt.claim.role for its own guard.
select set_config('request.jwt.claim.role', 'service_role', true);

-- Helper: build a call with a given selfie path against a fixed employee id.
-- Employee id used: 11111111-1111-1111-1111-111111111111
-- operation/correlation/challenge ids are arbitrary valid uuids; they are never
-- reached because the selfie check raises first.

-- ① Another employee's folder → scope violation (42501).
prepare foreign_folder as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '99999999-9999-9999-9999-999999999999/2026/secret.jpg', false);
select throws_ok('foreign_folder', '42501', null,
  '0236: selfie path in another employee''s folder is rejected (scope)');

-- ② Path traversal → 22023.
prepare traversal as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '11111111-1111-1111-1111-111111111111/2026/../../etc/passwd', false);
select throws_ok('traversal', '22023', null,
  '0236: selfie path with .. traversal is rejected');

-- ③ Absolute path → 22023.
prepare absolute_path as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '/etc/passwd', false);
select throws_ok('absolute_path', '22023', null,
  '0236: absolute selfie path is rejected');

-- ④ URL scheme → 22023.
prepare url_scheme as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    'http://evil.example.com/x.jpg', false);
select throws_ok('url_scheme', '22023', null,
  '0236: selfie path with URL scheme is rejected');

-- ⑤ Backslash → 22023.
prepare backslash as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    E'11111111-1111-1111-1111-111111111111\\2026\\x.jpg', false);
select throws_ok('backslash', '22023', null,
  '0236: selfie path with backslash is rejected');

-- ⑥ Wrong shape (extra segment) → 22023 (format).
prepare extra_segment as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '11111111-1111-1111-1111-111111111111/2026/sub/x.jpg', false);
select throws_ok('extra_segment', '22023', null,
  '0236: selfie path with extra path segment is rejected (format)');

-- ⑦ Non-digit year → 22023 (format).
prepare bad_year as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '11111111-1111-1111-1111-111111111111/20xx/x.jpg', false);
select throws_ok('bad_year', '22023', null,
  '0236: selfie path with non-digit year is rejected (format)');

-- ⑧ Empty string → 22023.
prepare empty_path as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '', false);
select throws_ok('empty_path', '22023', null,
  '0236: empty selfie path is rejected');

-- ⑧b Double slash (empty middle segment) → 22023 (format).
prepare double_slash as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '11111111-1111-1111-1111-111111111111//2026/x.jpg', false);
select throws_ok('double_slash', '22023', null,
  '0236: selfie path with double slash is rejected (format)');

-- ⑧c Trailing newline → 22023: confirms Postgres POSIX $ binds to true string
-- end, so a control char appended after a valid shape cannot slip through.
prepare trailing_newline as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    E'11111111-1111-1111-1111-111111111111/2026/x.jpg\n', false);
select throws_ok('trailing_newline', '22023', null,
  '0236: selfie path with trailing newline is rejected (format)');

-- ⑨ A validly-scoped path passes the selfie check → it does NOT raise a selfie
-- error. It proceeds to the idempotency INSERT, which fails on the FK to
-- webauthn_challenges/employees (dummy ids) with 23503. Reaching 23503 proves
-- the selfie gate was passed (a rejected path would raise 22023/42501 earlier).
prepare valid_scoped as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    '11111111-1111-1111-1111-111111111111/2026/selfie.jpg', false);
select throws_ok('valid_scoped', '23503', null,
  '0236: validly-scoped path passes selfie check and fails later (attempt FK)');

-- ⑩ NULL selfie path also passes the selfie check (same downstream FK failure).
prepare null_path as
  select public.finalize_verified_attendance(
    '00000000-0000-0000-0000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000004'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    'CHECK_IN', 24.7, 46.6, 10.0, 1,
    null, false);
select throws_ok('null_path', '23503', null,
  '0236: NULL selfie path is allowed (passes selfie check, fails on attempt FK)');

reset role;
select * from finish();
rollback;
