-- Migration 0055: P3 audit remediation — LEDGER-02.
-- ============================================================================
-- LEDGER-02 [P3] — Cancelling/expiring an ALREADY-APPROVED leave request must
-- refund consumed_units, not release a (now-zero) reservation.
--
-- tg_leave_settle_on_request_decision (0026:183) emits 'consume' on approval
-- (moving units reserved -> consumed) and 'release' on
-- rejected/cancelled/withdrawn/expired. But 'release' only decrements
-- reserved_units (greatest(0, ...)), which is already zero after consumption, so
-- a post-approval reversal left consumed_units permanently inflated (the
-- employee's available balance stayed reduced for leave never taken).
--
-- Fix: branch on the PRIOR status. Reversal FROM 'approved' emits 'refund'
-- (decrements consumed_units); reversal from a still-pending state keeps
-- 'release'. Function body is otherwise identical to 0026.
-- ============================================================================

begin;

create or replace function public.tg_leave_settle_on_request_decision()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lr public.leave_requests; v_affects boolean; v_units numeric; v_year integer;
begin
  if new.request_type <> 'leave' or old.status = new.status then return new; end if;
  select * into v_lr from public.leave_requests where request_id=new.id;
  if not found then return new; end if;
  select affects_balance into v_affects from public.leave_types where id=v_lr.leave_type_id;
  if not coalesce(v_affects,false) then return new; end if;
  v_units := case when v_lr.duration_unit='hour' then coalesce(v_lr.hours_count,0) else coalesce(v_lr.days_count,0) end;
  v_year := extract(year from v_lr.start_date)::integer;
  if new.status='approved' then
    perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'consume',v_units,'leave:consume:'||new.id,new.id,'خصم الرصيد بعد الاعتماد');
  elsif new.status in ('rejected','cancelled','withdrawn','expired') then
    -- LEDGER-02: a reversal FROM 'approved' refunds consumed units; a reversal
    -- from a still-pending (reserved) state releases the reservation.
    if old.status='approved' then
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'refund',v_units,'leave:refund:'||new.id||':'||new.status,new.id,'استرداد الرصيد بعد إلغاء طلب معتمد ('||new.status||')');
    else
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'release',v_units,'leave:release:'||new.id||':'||new.status,new.id,'تحرير الحجز بعد '||new.status);
    end if;
  end if;
  return new;
end $$;

commit;
