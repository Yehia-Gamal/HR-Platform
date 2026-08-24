-- ============================================================================
-- اختبار 0468: جهاز نشط واحد لكل موظف
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

-- ─── Fixture ───
insert into public.legal_entities (id, code, name)
values ('cccc0000-0000-4000-8000-000000004680', 'T468-LE', 'كيان 0468');
insert into public.departments (id, legal_entity_id, code, name)
values ('cccc0000-0000-4000-8000-00000000468a', 'cccc0000-0000-4000-8000-000000004680', 'T468-D', 'قسم 0468');

insert into auth.users (id, email, aud, role) values
  ('dddd0000-0000-4000-8000-000000004680', 't468@test.local', 'authenticated', 'authenticated');
insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active)
values ('eeee0000-0000-4000-8000-000000004680', 'dddd0000-0000-4000-8000-000000004680', 'T468-001',
        'موظف الاختبار 0468', 'cccc0000-0000-4000-8000-00000000468a', 'active', true);
insert into public.profiles (id, employee_id, status)
values ('dddd0000-0000-4000-8000-000000004680', 'eeee0000-0000-4000-8000-000000004680', 'active');

-- ─── 1) إدراج جهاز أول active ───
insert into public.employee_devices (employee_id, device_identifier_hash, device_name, platform, status, registered_at)
values ('eeee0000-0000-4000-8000-000000004680', 'hash-468-first', 'هاتف أول', 'android', 'active', now() - interval '2 days');

select is(
  (select count(*) from public.employee_devices
   where employee_id = 'eeee0000-0000-4000-8000-000000004680' and status = 'active'),
  1::bigint, 'جهاز أول نشط واحد');

-- ─── 2) إدراج جهاز ثانٍ active مباشرة (مسار قديم) — الزناد يستبدل الأول ───
insert into public.employee_devices (employee_id, device_identifier_hash, device_name, platform, status, registered_at)
values ('eeee0000-0000-4000-8000-000000004680', 'hash-468-second', 'هاتف ثانٍ', 'android', 'active', now());

select is(
  (select count(*) from public.employee_devices
   where employee_id = 'eeee0000-0000-4000-8000-000000004680' and status = 'active'),
  1::bigint, 'بعد إدراج ثانٍ active: لا يزال نشطاً واحداً فقط');

select is(
  (select device_name from public.employee_devices
   where employee_id = 'eeee0000-0000-4000-8000-000000004680' and status = 'active'),
  'هاتف ثانٍ', 'النشط هو الأحدث');

-- ─── 3) مسار UPDATE: ترقية جهاز pending إلى active يستبدل النشط ───
insert into public.employee_devices (employee_id, device_identifier_hash, device_name, platform, status, registered_at)
values ('eeee0000-0000-4000-8000-000000004680', 'hash-468-third', 'هاتف ثالث', 'android', 'pending', now());

update public.employee_devices set status = 'active'
where device_identifier_hash = 'hash-468-third';

select is(
  (select count(*) from public.employee_devices
   where employee_id = 'eeee0000-0000-4000-8000-000000004680' and status = 'active'),
  1::bigint, 'بعد ترقية pending عبر UPDATE: نشط واحد فقط');

select is(
  (select device_name from public.employee_devices
   where employee_id = 'eeee0000-0000-4000-8000-000000004680' and status = 'active'),
  'هاتف ثالث', 'النشط بعد UPDATE هو المُرقّى');

select * from finish();
rollback;
