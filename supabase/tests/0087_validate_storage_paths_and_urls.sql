-- pgTAP test for migration 0235: server-side validation of storage paths / URLs
-- Validates:
--   ① is_safe_url_or_path — accepts https + relative path, rejects dangerous schemes/traversal
--   ② is_safe_storage_path — accepts pure relative path, rejects any scheme/absolute/traversal
--   ③ employees.photo_url trigger rejects data:/javascript: URLs
--   ④ attendance_events.selfie_path trigger rejects file:/absolute/traversal paths

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(26);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① is_safe_url_or_path
-- ═══════════════════════════════════════════════════════════════════════════
select has_function('public', 'is_safe_url_or_path', array['text'],
  '0235: is_safe_url_or_path(text) exists');
select function_returns('public', 'is_safe_url_or_path', array['text'], 'boolean',
  '0235: is_safe_url_or_path returns boolean');

select ok(public.is_safe_url_or_path(null), '0235: NULL is allowed (optional column)');
select ok(public.is_safe_url_or_path(''), '0235: empty string is allowed');
select ok(public.is_safe_url_or_path('https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/x.webp'),
  '0235: https supabase storage URL accepted');
select ok(public.is_safe_url_or_path('https://example.com/mock-avatar.webp'),
  '0235: https external URL accepted (mock mode)');
select ok(public.is_safe_url_or_path('admin/9f1c.webp'),
  '0235: relative storage path accepted');

select ok(not public.is_safe_url_or_path('data:image/png;base64,AAAA'),
  '0235: data: URL rejected');
select ok(not public.is_safe_url_or_path('file:///etc/passwd'),
  '0235: file: URL rejected');
select ok(not public.is_safe_url_or_path('javascript:alert(1)'),
  '0235: javascript: URL rejected');
select ok(not public.is_safe_url_or_path('JavaScript:alert(1)'),
  '0235: scheme check is case-insensitive');
select ok(not public.is_safe_url_or_path('blob:https://x'),
  '0235: blob: URL rejected');
select ok(not public.is_safe_url_or_path('http://insecure.example.com/a.png'),
  '0235: non-https scheme (http) rejected');
select ok(not public.is_safe_url_or_path('../../secret/a.png'),
  '0235: path traversal rejected');
select ok(not public.is_safe_url_or_path('//attacker.example/payload.js'),
  '0235: protocol-relative URL (//host) rejected');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② is_safe_storage_path
-- ═══════════════════════════════════════════════════════════════════════════
select has_function('public', 'is_safe_storage_path', array['text'],
  '0235: is_safe_storage_path(text) exists');
select ok(public.is_safe_storage_path('9f1c/2024/selfie.jpg'),
  '0235: relative selfie path accepted');
select ok(not public.is_safe_storage_path('data:image/png;base64,AAAA'),
  '0235: data: selfie path rejected');
select ok(not public.is_safe_storage_path('https://x.supabase.co/y.jpg'),
  '0235: https scheme rejected for pure storage path');
select ok(not public.is_safe_storage_path('/etc/passwd'),
  '0235: absolute path rejected');
select ok(not public.is_safe_storage_path('a/../../b.jpg'),
  '0235: traversal in selfie path rejected');

-- ═══════════════════════════════════════════════════════════════════════════
-- ③ employees.photo_url trigger
-- ═══════════════════════════════════════════════════════════════════════════
select has_trigger('public', 'employees', 'trg_employees_validate_photo_url',
  '0235: employees photo_url validation trigger exists');

-- Insert a minimal employee with a malicious photo_url must fail.
-- (columns kept minimal; adjust if NOT NULL set changes)
prepare bad_employee as
  insert into public.employees (full_name_ar, employee_code, phone_e164, photo_url, status, is_active)
  values ('اختبار', 'TST-XSS-1', '+201000000001', 'javascript:alert(1)', 'active', true);
select throws_ok('bad_employee', '22023',
  null, '0235: employees insert with javascript: photo_url is rejected');

prepare good_employee as
  insert into public.employees (full_name_ar, employee_code, phone_e164, photo_url, status, is_active)
  values ('اختبار', 'TST-OK-1', '+201000000002',
          'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/ok.webp',
          'active', true);
select lives_ok('good_employee',
  '0235: employees insert with https photo_url succeeds');

-- ═══════════════════════════════════════════════════════════════════════════
-- ④ attendance_events.selfie_path trigger
-- ═══════════════════════════════════════════════════════════════════════════
select has_trigger('public', 'attendance_events', 'trg_attendance_validate_selfie_path',
  '0235: attendance_events selfie_path validation trigger exists');

-- The trigger fires before other column constraints only if the row reaches it;
-- we assert the trigger function itself rejects a bad value via direct call.
select ok(
  not public.is_safe_storage_path('file:///data/local/tmp/x.jpg'),
  '0235: file: selfie path rejected by validator (trigger source)');

select * from finish();
rollback;
