-- pgTAP test for migration 0248: hardening of the URL/path validators.
-- Covers the two bypasses found by adversarial review of 0235/0243:
--   ① leading-whitespace defeats the scheme guard  → non-blocklisted scheme smuggling
--   ② mixed slash/backslash prefix (/\ , \/) not caught → protocol-relative open redirect
-- Plus regression of the original safe/unsafe cases, on ALL THREE validators
-- (is_safe_url_or_path, is_safe_storage_path, is_safe_external_link).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(42);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① Leading-whitespace scheme smuggling — MUST be rejected after 0248
-- ═══════════════════════════════════════════════════════════════════════════
select ok(not public.is_safe_url_or_path(' chrome://settings'),
  '0248: leading-space chrome:// rejected (url_or_path)');
select ok(not public.is_safe_url_or_path(' intent://scan/#Intent;end'),
  '0248: leading-space intent:// rejected (url_or_path)');
select ok(not public.is_safe_url_or_path(' someunknownscheme:PAYLOAD'),
  '0248: leading-space unknown scheme rejected (url_or_path)');
select ok(not public.is_safe_url_or_path('  javascript:alert(1)'),
  '0248: leading-spaces javascript: still rejected (url_or_path)');
select ok(not public.is_safe_external_link(' chrome://settings'),
  '0248: leading-space chrome:// rejected (external_link)');
select ok(not public.is_safe_external_link(' jar:https://evil/x!/'),
  '0248: leading-space jar: rejected (external_link)');
select ok(not public.is_safe_storage_path(' chrome://x'),
  '0248: leading-space scheme rejected (storage_path)');

-- Tab/other whitespace variants: tab is a control char so already rejected.
select ok(not public.is_safe_url_or_path(E'\tchrome://x'),
  '0248: leading-tab (control char) rejected (url_or_path)');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② Mixed slash/backslash protocol-relative — MUST be rejected after 0248
-- ═══════════════════════════════════════════════════════════════════════════
select ok(not public.is_safe_url_or_path('/\evil.com/phish'),
  '0248: /\ prefix rejected (url_or_path)');
select ok(not public.is_safe_url_or_path('\/evil.com/phish'),
  '0248: \/ prefix rejected (url_or_path)');
select ok(not public.is_safe_url_or_path('/\evil.com'),
  '0248: /\ prefix no-path rejected (url_or_path)');
select ok(not public.is_safe_url_or_path('//attacker.example/p.js'),
  '0248: // protocol-relative still rejected (url_or_path)');
select ok(not public.is_safe_url_or_path('\\attacker.example\p'),
  '0248: \\ UNC still rejected (url_or_path)');
select ok(not public.is_safe_url_or_path(' /\evil.com'),
  '0248: leading-space + /\ rejected (url_or_path)');
select ok(not public.is_safe_external_link('/\evil.com/phish'),
  '0248: /\ prefix rejected (external_link)');
select ok(not public.is_safe_external_link('\/evil.com'),
  '0248: \/ prefix rejected (external_link)');
select ok(not public.is_safe_external_link('//evil.example'),
  '0248: // protocol-relative rejected (external_link)');
-- storage_path rejects any leading / or \ (single char is enough)
select ok(not public.is_safe_storage_path('/\evil.com'),
  '0248: /\ prefix rejected (storage_path)');
select ok(not public.is_safe_storage_path('\evil'),
  '0248: leading backslash rejected (storage_path)');

-- ═══════════════════════════════════════════════════════════════════════════
-- ③ Regression: legitimate values MUST still be accepted
-- ═══════════════════════════════════════════════════════════════════════════
select ok(public.is_safe_url_or_path(null), '0248: NULL accepted (url_or_path)');
select ok(public.is_safe_url_or_path(''), '0248: empty accepted (url_or_path)');
select ok(public.is_safe_url_or_path('https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/x.webp'),
  '0248: https supabase URL accepted (url_or_path)');
select ok(public.is_safe_url_or_path('admin/9f1c.webp'),
  '0248: relative path accepted (url_or_path)');
select ok(public.is_safe_url_or_path('reports/q1..q2/summary.pdf'),
  '0248: mid-segment dots accepted (not traversal) (url_or_path)');
select ok(public.is_safe_external_link('http://example.com/ref'),
  '0248: http external link accepted (external_link)');
select ok(public.is_safe_external_link('https://example.com/ref'),
  '0248: https external link accepted (external_link)');
select ok(public.is_safe_storage_path('9f1c/2024/selfie.jpg'),
  '0248: relative selfie path accepted (storage_path)');

-- ═══════════════════════════════════════════════════════════════════════════
-- ④ Regression: original 0087 dangerous cases still rejected
-- ═══════════════════════════════════════════════════════════════════════════
select ok(not public.is_safe_url_or_path('data:image/png;base64,AAAA'), '0248: data: rejected');
select ok(not public.is_safe_url_or_path('file:///etc/passwd'), '0248: file: rejected');
select ok(not public.is_safe_url_or_path('javascript:alert(1)'), '0248: javascript: rejected');
select ok(not public.is_safe_url_or_path('JavaScript:alert(1)'), '0248: JavaScript: case-insensitive rejected');
select ok(not public.is_safe_url_or_path('blob:https://x'), '0248: blob: rejected');
select ok(not public.is_safe_url_or_path('http://insecure.example.com/a.png'), '0248: http rejected (url_or_path https-only)');
select ok(not public.is_safe_url_or_path('../../secret/a.png'), '0248: traversal rejected (url_or_path)');
select ok(not public.is_safe_external_link('javascript:alert(1)'), '0248: javascript: rejected (external_link)');
select ok(not public.is_safe_external_link('data:text/html,x'), '0248: data: rejected (external_link)');
select ok(not public.is_safe_storage_path('data:image/png;base64,AAAA'), '0248: data: rejected (storage_path)');
select ok(not public.is_safe_storage_path('https://x.supabase.co/y.jpg'), '0248: https scheme rejected (storage_path)');
select ok(not public.is_safe_storage_path('/etc/passwd'), '0248: absolute rejected (storage_path)');
select ok(not public.is_safe_storage_path('a/../../b.jpg'), '0248: traversal rejected (storage_path)');

-- ═══════════════════════════════════════════════════════════════════════════
-- ⑤ Trigger end-to-end: employees.photo_url rejects a mixed-slash bypass
-- ═══════════════════════════════════════════════════════════════════════════
prepare bad_slash_employee as
  insert into public.employees (full_name_ar, employee_code, phone_e164, photo_url, status, is_active)
  values ('اختبار', 'TST-SLASH-1', '+201000000009', '/\evil.com/x.png', 'active', true);
select throws_ok('bad_slash_employee', '22023',
  null, '0248: employees insert with /\ photo_url rejected by trigger');

prepare good_slash_employee as
  insert into public.employees (full_name_ar, employee_code, phone_e164, photo_url, status, is_active)
  values ('اختبار', 'TST-SLASH-OK', '+201000000010',
          'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/ok.webp',
          'active', true);
select lives_ok('good_slash_employee',
  '0248: employees insert with https photo_url still succeeds');

select * from finish();
rollback;
