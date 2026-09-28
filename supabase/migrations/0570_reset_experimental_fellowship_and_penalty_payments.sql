-- =====================================================================
-- 0570: تصفير وإلغاء المدفوعات وحركات صندوق الزمالة التجريبية السابقة
-- =====================================================================

create or replace function public.reset_experimental_fellowship_and_penalty_payments()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_cleared_tx integer := 0;
  v_cleared_penalties integer := 0;
begin
  -- التحقق من الصلاحيات الإدارية
  if auth.uid() is not null then
    if not (
      public.current_is_full_access()
      or public.has_any_permission(array['payroll.run.manage', 'finance.manage'])
    ) then
      raise exception 'غير مصرح لك بتصفير الحركات المالية وصندوق الزمالة' using errcode = '42501';
    end if;
  elsif current_user not in ('postgres', 'service_role') then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1) حذف كافة الحركات التجريبية من صندوق الزمالة والتكافل
  delete from public.fellowship_fund_transactions;
  get diagnostics v_cleared_tx = row_count;

  -- 2) تصفير وإلغاء أي غرامات سُددت تجريبياً سابقاً وإعادتها لحالة ملغاة تجريبياً
  update public.instant_attendance_penalties
     set status = 'cancelled',
         notes = coalesce(notes || ' | ', '') || 'تصفير وإلغاء السداد التجريبي السابق',
         paid_at = null,
         confirmed_by = null,
         receipt_reference_number = null,
         receipt_attachment_url = null,
         updated_at = now()
   where status = 'paid';
  get diagnostics v_cleared_penalties = row_count;

  -- 3) تسجيل عملية التدقيق الإداري
  perform public.log_audit_event(
    'fellowship_fund.experimental_reset',
    'financial',
    'warning',
    'fellowship_fund_transactions',
    null,
    'تصفير رصيد صندوق الزمالة وإلغاء السدادات التجريبية السابقة بطلب الإدارة',
    null,
    jsonb_build_object(
      'cleared_transactions', v_cleared_tx,
      'cleared_penalties', v_cleared_penalties,
      'reset_by', auth.uid(),
      'reset_at', now()
    )
  );

  return jsonb_build_object(
    'success', true,
    'clearedTransactions', v_cleared_tx,
    'clearedPenalties', v_cleared_penalties,
    'message', format('تم بنجاح تصفير رصيد صندوق الزمالة (حذف %s حركة) وإلغاء %s سداد تجريبي سابق.', v_cleared_tx, v_cleared_penalties)
  );
end;
$$;

revoke all on function public.reset_experimental_fellowship_and_penalty_payments() from public, anon;
grant execute on function public.reset_experimental_fellowship_and_penalty_payments() to authenticated, service_role;
