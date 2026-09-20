/* 0538_penalty_bulk_operations.sql — عمليات جماعية على الغرامات
   - bulk_confirm_penalty_payments: تأكيد دفع جماعي
   - bulk_cancel_penalties: إلغاء جماعي
*/
begin;

create or replace function public.bulk_confirm_penalty_payments(
  p_penalty_ids uuid[],
  p_notes text default null
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'غير مصرح';
  end if;

  foreach v_id in array p_penalty_ids loop
    begin
      perform public.confirm_instant_penalty_payment(v_id, p_notes);
      v_count := v_count + 1;
    exception when others then
      null;
    end;
  end loop;

  return v_count;
end;
$$;

create or replace function public.bulk_cancel_penalties(
  p_penalty_ids uuid[],
  p_reason text
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'غير مصرح';
  end if;

  foreach v_id in array p_penalty_ids loop
    begin
      perform public.cancel_instant_penalty(v_id, p_reason);
      v_count := v_count + 1;
    exception when others then
      null;
    end;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.bulk_confirm_penalty_payments(uuid[], text) to authenticated;
grant execute on function public.bulk_cancel_penalties(uuid[], text) to authenticated;

commit;
