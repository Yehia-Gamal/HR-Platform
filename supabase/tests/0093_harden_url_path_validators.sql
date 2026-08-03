-- 0093: Leading whitespace, mixed slash and traversal bypass regression tests.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

select ok(public.is_safe_url_or_path('https://example.com/a.webp'),'https URL allowed');
select ok(public.is_safe_url_or_path('folder/a.webp'),'relative URL path allowed');
select ok(not public.is_safe_url_or_path(' chrome:settings'),'leading-space scheme denied');
select ok(not public.is_safe_url_or_path(' intent://scan'),'leading-space intent denied');
select ok(not public.is_safe_url_or_path('/\\evil.example/a'),'mixed slash URL denied');
select ok(not public.is_safe_url_or_path('\\/evil.example/a'),'mixed reverse slash URL denied');
select ok(not public.is_safe_url_or_path('a/../secret'),'forward traversal denied');
select ok(not public.is_safe_url_or_path('a\\..\\secret'),'backslash traversal denied');
select ok(not public.is_safe_url_or_path('a/..\\secret'),'mixed traversal denied');

select ok(public.is_safe_storage_path('employee/a.webp'),'relative storage path allowed');
select ok(not public.is_safe_storage_path(' https://example.com/a.webp'),'leading-space scheme denied for storage');
select ok(not public.is_safe_storage_path(' C:\\temp\\a.webp'),'leading-space drive scheme denied');
select ok(not public.is_safe_storage_path('/absolute/a.webp'),'absolute forward path denied');
select ok(not public.is_safe_storage_path('\\absolute\\a.webp'),'absolute backslash path denied');
select ok(not public.is_safe_storage_path('/\\evil.example/a'),'mixed absolute path denied');
select ok(not public.is_safe_storage_path('a/../secret'),'forward storage traversal denied');
select ok(not public.is_safe_storage_path('a\\..\\secret'),'backslash storage traversal denied');
select ok(not public.is_safe_storage_path('a\\../secret'),'mixed storage traversal denied');

select * from finish();
rollback;
