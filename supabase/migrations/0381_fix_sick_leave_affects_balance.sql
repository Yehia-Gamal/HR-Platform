-- migration: 0376
-- description: fix sick leave affects_balance — align with unlimited design intent

begin;

-- sick leave was made unlimited in 0326 (no max, monthly accrual only)
-- but affects_balance=true still triggers INSUFFICIENT_LEAVE_BALANCE for new employees
-- fix: set affects_balance=false so reserve/consume skip balance check
update public.leave_types
set affects_balance = false
where code = 'sick';

-- also add a guard comment: this means sick leave does NOT deduct from any ledger
-- employees can take any number of sick days; HR can audit via leave_requests directly

commit;
