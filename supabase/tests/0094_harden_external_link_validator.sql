-- 0094: Leading whitespace and mixed slash/backslash external-link regressions.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

select ok(public.is_safe_external_link(null), 'NULL external link allowed');
select ok(public.is_safe_external_link(''), 'empty external link allowed');
select ok(public.is_safe_external_link('https://example.com/evidence'), 'https link allowed');
select ok(public.is_safe_external_link('http://intranet/evidence'), 'http link allowed');
select ok(public.is_safe_external_link('evidence/reference'), 'relative link allowed');
select ok(not public.is_safe_external_link(' chrome:settings'), 'leading-space scheme denied');
select ok(not public.is_safe_external_link(' intent://scan'), 'leading-space intent denied');
select ok(not public.is_safe_external_link('/\\evil.example/a'), 'mixed slash link denied');
select ok(not public.is_safe_external_link('\\/evil.example/a'), 'mixed reverse slash link denied');
select ok(not public.is_safe_external_link('a/../secret'), 'forward traversal denied');
select ok(not public.is_safe_external_link('a\\..\\secret'), 'backslash traversal denied');
select ok(not public.is_safe_external_link('a/..\\secret'), 'mixed traversal denied');
select ok(not public.is_safe_external_link(' javascript:alert(1)'), 'dangerous scheme denied');
select ok(not public.is_safe_external_link('https://example.com/' || chr(10) || 'next'), 'control character denied');

select * from finish();
rollback;
