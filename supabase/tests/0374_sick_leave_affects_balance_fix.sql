begin;
select plan(3);

-- Test 1: sick leave has affects_balance = false
select is(
  (select affects_balance from public.leave_types where slug = 'sick'),
  false,
  'sick leave affects_balance should be false (unlimited — no ledger deduction)'
);

-- Test 2: annual leave still has affects_balance = true
select is(
  (select affects_balance from public.leave_types where slug = 'annual'),
  true,
  'annual leave should still deduct from balance'
);

-- Test 3: casual leave still has affects_balance = true
select is(
  (select affects_balance from public.leave_types where slug = 'casual'),
  true,
  'casual leave should still deduct from balance'
);

select finish();
rollback;
