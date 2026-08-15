-- =====================================================================
-- 0428: رصيد بدل الراحة الأسبوعية (migration 0428)
--   1. القيد يقبل entry_type 'credit'
--   2. العمل يوم الجمعة (بصمة دخول) → رصيد تلقائي +1
--   3. idempotency: تحديث نفس اليوم لا يضاعف الرصيد
--   4. تحديث عمود آخر (work_minutes) لا يضاعف الرصيد
--   5. جمعة بلا حضور فعلي → لا رصيد
--   6. سبت (غير جمعة) مع حضور → لا رصيد
--   7. reserve أكبر من الرصيد → INSUFFICIENT_LEAVE_BALANCE
--   8. reserve ضمن الرصيد → نجاح، الرصيد المتاح ينخفض
--   9. consume بعد reserve → محجوز=0، مستهلك=1
--  10. refund بعد consume → مستهلك=0، الرصيد يعود
--  11. weekly_rest_credit_available يعكس الرصيد المكتسب
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

-- 1. القيد يقبل entry_type 'credit'
select ok(
  (select pg_get_constraintdef(oid) like '%credit%'
   from pg_constraint
   where conname = 'leave_ledger_entries_entry_type_check'),
  '1. القيد leave_ledger_entries_entry_type_check يقبل credit'
);

-- إعداد: موظفان للاختبار (جدول employees فارغ في reset نظيف)
insert into public.employees (id, employee_code, full_name_ar)
values
  ('e9000000-0000-4000-8000-000000000428', 'T-0428-A', 'موظف اختبار بدل الراحة أ'),
  ('e9000000-0000-4000-8000-000000000429', 'T-0428-B', 'موظف اختبار بدل الراحة ب');

-- 2. العمل يوم الجمعة (2026-11-27) مع بصمة دخول → رصيد تلقائي +1
do $$
declare v_emp uuid := (select id from public.employees where employee_code = 'T-0428-A');
begin
  insert into public.attendance_daily (employee_id, work_date, first_check_in, status)
  values (v_emp, '2026-11-27', now(), 'present')
  on conflict (employee_id, work_date) do update
    set first_check_in = now(), last_check_out = now(), status = 'present';
end $$;

select results_eq(
  $$ select coalesce(sum(units), 0)
     from public.leave_ledger_entries
     where source_key = 'weekly-rest:credit:' ||
       (select id::text from public.employees where employee_code = 'T-0428-A') || ':2026-11-27' $$,
  $$ values (1::numeric) $$,
  '2. عمل الجمعة يمنح رصيد بدل راحة +1 تلقائياً'
);

-- 3. idempotency: تحديث نفس اليوم (status) لا يضاعف الرصيد
do $$
declare v_emp uuid := (select id from public.employees where employee_code = 'T-0428-A');
begin
  update public.attendance_daily
  set status = 'late', last_check_out = now()
  where employee_id = v_emp and work_date = '2026-11-27';
end $$;

select results_eq(
  $$ select count(*)
     from public.leave_ledger_entries
     where source_key = 'weekly-rest:credit:' ||
       (select id::text from public.employees where employee_code = 'T-0428-A') || ':2026-11-27' $$,
  $$ values (1::bigint) $$,
  '3. تحديث نفس اليوم لا يضاعف الرصيد (idempotent)'
);

-- 4. تحديث عمود آخر (work_minutes) لا يضاعف الرصيد
do $$
declare v_emp uuid := (select id from public.employees where employee_code = 'T-0428-A');
begin
  update public.attendance_daily
  set work_minutes = 480
  where employee_id = v_emp and work_date = '2026-11-27';
end $$;

select results_eq(
  $$ select count(*)
     from public.leave_ledger_entries
     where source_key = 'weekly-rest:credit:' ||
       (select id::text from public.employees where employee_code = 'T-0428-A') || ':2026-11-27' $$,
  $$ values (1::bigint) $$,
  '4. تحديث work_minutes لا يضاعف الرصيد'
);

-- 5. جمعة بلا حضور فعلي → لا رصيد
do $$
declare v_emp uuid := (select id from public.employees where employee_code = 'T-0428-B');
begin
  insert into public.attendance_daily (employee_id, work_date, status)
  values (v_emp, '2026-11-27', 'absent')
  on conflict (employee_id, work_date) do update
    set first_check_in = null, last_check_out = null, status = 'absent';
end $$;

select results_eq(
  $$ select count(*)
     from public.leave_ledger_entries
     where source_key = 'weekly-rest:credit:' ||
       (select id::text from public.employees where employee_code = 'T-0428-B') || ':2026-11-27' $$,
  $$ values (0::bigint) $$,
  '5. جمعة بلا حضور فعلي (absent) لا تمنح رصيداً'
);

-- 6. سبت (2026-11-28) مع حضور → لا رصيد
do $$
declare v_emp uuid := (select id from public.employees where employee_code = 'T-0428-A');
begin
  insert into public.attendance_daily (employee_id, work_date, first_check_in, status)
  values (v_emp, '2026-11-28', now(), 'present')
  on conflict (employee_id, work_date) do update
    set first_check_in = now(), status = 'present';
end $$;

select results_eq(
  $$ select count(*)
     from public.leave_ledger_entries
     where source_key like 'weekly-rest:credit:' ||
       (select id::text from public.employees where employee_code = 'T-0428-A') || ':2026-11-28%' $$,
  $$ values (0::bigint) $$,
  '6. العمل يوم السبت لا يمنح رصيد بدل راحة'
);

-- 7. reserve أكبر من الرصيد → INSUFFICIENT_LEAVE_BALANCE
select throws_like(
  $$ select public.apply_leave_ledger_entry(
       (select id from public.employees where employee_code = 'T-0428-A'),
       (select id from public.leave_types where code = 'weekly_rest_comp'),
       2026, 'reserve', 2, 'test:wr:reserve:x'
     ) $$,
  '%INSUFFICIENT_LEAVE_BALANCE%',
  '7. reserve بـ2 والرصيد 1 → INSUFFICIENT_LEAVE_BALANCE'
);

-- 8. reserve ضمن الرصيد → نجاح والرصيد المتاح ينخفض
select isnt_empty(
  $$ select public.apply_leave_ledger_entry(
       (select id from public.employees where employee_code = 'T-0428-A'),
       (select id from public.leave_types where code = 'weekly_rest_comp'),
       2026, 'reserve', 1, 'test:wr:reserve:1'
     ) $$,
  '8. reserve بـ1 ضمن الرصيد → نجاح'
);

select results_eq(
  $$ select reserved_units
     from public.leave_balance_accounts a
     join public.leave_types lt on lt.id = a.leave_type_id
     where a.employee_id = (select id from public.employees where employee_code = 'T-0428-A')
       and lt.code = 'weekly_rest_comp' and a.balance_year = 2026 $$,
  $$ values (1::numeric) $$,
  '8b. المحجوز = 1 بعد reserve'
);

-- 9. consume بعد reserve → محجوز=0، مستهلك=1
select isnt_empty(
  $$ select public.apply_leave_ledger_entry(
       (select id from public.employees where employee_code = 'T-0428-A'),
       (select id from public.leave_types where code = 'weekly_rest_comp'),
       2026, 'consume', 1, 'test:wr:consume:1'
     ) $$,
  '9. consume بعد reserve → نجاح'
);

select results_eq(
  $$ select reserved_units || ',' || consumed_units
     from public.leave_balance_accounts a
     join public.leave_types lt on lt.id = a.leave_type_id
     where a.employee_id = (select id from public.employees where employee_code = 'T-0428-A')
       and lt.code = 'weekly_rest_comp' and a.balance_year = 2026 $$,
  $$ values ('0.00,1.00') $$,
  '9b. بعد consume: محجوز=0، مستهلك=1'
);

-- 10. refund بعد consume → مستهلك=0، الرصيد يعود
select isnt_empty(
  $$ select public.apply_leave_ledger_entry(
       (select id from public.employees where employee_code = 'T-0428-A'),
       (select id from public.leave_types where code = 'weekly_rest_comp'),
       2026, 'refund', 1, 'test:wr:refund:1'
     ) $$,
  '10. refund بعد consume → نجاح'
);

select results_eq(
  $$ select public.weekly_rest_credit_available(
       (select id from public.employees where employee_code = 'T-0428-A'), 2026) $$,
  $$ values (1::numeric) $$,
  '10b. الرصيد المكتسب يعود إلى 1 بعد refund'
);

-- 11. weekly_rest_credit_available = 0 لموظف بلا رصيد
select results_eq(
  $$ select public.weekly_rest_credit_available(
       (select id from public.employees where employee_code = 'T-0428-B'), 2026) $$,
  $$ values (0::numeric) $$,
  '11. weekly_rest_credit_available = 0 لموظف بلا رصيد'
);

select * from finish();
rollback;