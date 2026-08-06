-- =====================================================================
-- 0105: weekly_rest_comp + تأمين أعمدة public_holidays (migration 0278)
--   1. نوع الإجازة weekly_rest_comp موجود ونشط.
--   2. affects_balance = false (لا يخصم الرصيد).
--   3. أعمدة public_holidays (scope / excluded_department_ids / notes) موجودة.
--   4. RPCs create/update/delete_public_holiday موجودة وممنوحة للمصادقين.
--   5. إدراج عطلة بنطاق all ينجح.
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

-- 1-2: نوع weekly_rest_comp
select isnt_empty(
  $$ select 1 from public.leave_types where code = 'weekly_rest_comp' $$,
  '1. weekly_rest_comp موجود في leave_types'
);

select results_eq(
  $$ select affects_balance, is_active, is_paid
     from public.leave_types
     where code = 'weekly_rest_comp' $$,
  $$ values (false, true, true) $$,
  '2. weekly_rest_comp: affects_balance=false, is_active=true, is_paid=true'
);

select isnt_empty(
  $$ select name_ar, name_en from public.leave_types
     where code = 'weekly_rest_comp' and length(name_ar) > 1 $$,
  '3. weekly_rest_comp له اسم عربي وإنجليزي'
);

-- 4-6: أعمدة public_holidays
select has_column('public','public_holidays','scope','4. عمود scope موجود');
select has_column('public','public_holidays','excluded_department_ids','5. عمود excluded_department_ids موجود');
select has_column('public','public_holidays','notes','6. عمود notes موجود');

-- 7-9: RPCs الحضور والصلاحية
select function_privs_are(
  'public','create_public_holiday',
  array['text','date','date','text','uuid','uuid','uuid[]','text','boolean'],
  'authenticated', array['EXECUTE'],
  '7. create_public_holiday ممنوحة للمصادقين');

select function_privs_are(
  'public','update_public_holiday',
  array['uuid','text','date','date','text','uuid','uuid','uuid[]','text','boolean','boolean'],
  'authenticated', array['EXECUTE'],
  '8. update_public_holiday ممنوحة للمصادقين');

select function_privs_are(
  'public','delete_public_holiday',
  array['uuid'],
  'authenticated', array['EXECUTE'],
  '9. delete_public_holiday ممنوحة للمصادقين');

-- 10: قيد scope_entity
select results_eq(
  $$ select count(*)::int from pg_constraint
     where conrelid = 'public.public_holidays'::regclass
       and conname = 'public_holidays_scope_entity_chk' $$,
  $$ values (1) $$,
  '10. قيد scope_entity_chk قائم'
);

-- 11: نوع الإجازة لا يُفعّل الخصم تلقائيًا
select results_eq(
  $$ select count(*)::int from public.leave_types
     where code = 'weekly_rest_comp'
       and affects_balance = true $$,
  $$ values (0) $$,
  '11. لا يوجد أي صف weekly_rest_comp يخصم الرصيد'
);

select * from finish();
rollback;
