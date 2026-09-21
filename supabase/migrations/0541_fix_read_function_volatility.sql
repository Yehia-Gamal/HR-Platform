-- =====================================================================
-- 0541: تصحيح فولاتيليتي الدوال القارئة (VOLATILE → STABLE)
--
-- PostgREST يستبعد الدوال VOLATILE ذات الأرجومينتات الافتراضية
-- من Schema Cache → خطأ 400 "Could not find the function".
-- الحل: نحدّث Volatility إلى STABLE للدوال القارئة فقط.
-- =====================================================================

begin;

-- 1) get_fellowship_fund_summary() — zero-arg, STABLE required for PostgREST GET
create or replace function public.get_fellowship_fund_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_total_inflow numeric(12,2) := 0.00;
  v_total_outflow numeric(12,2) := 0.00;
  v_current_balance numeric(12,2) := 0.00;
  v_inflow_count integer := 0;
  v_outflow_count integer := 0;
  v_month_start timestamptz := date_trunc('month', now() at time zone 'Africa/Cairo');
  v_monthly_inflow numeric(12,2) := 0.00;
  v_monthly_outflow numeric(12,2) := 0.00;
  v_category_breakdown jsonb;
  v_recent_transactions jsonb;
begin
  select
    coalesce(sum(case when transaction_type = 'inflow' then amount else 0 end), 0),
    coalesce(sum(case when transaction_type = 'outflow' then amount else 0 end), 0),
    count(case when transaction_type = 'inflow' then 1 end),
    count(case when transaction_type = 'outflow' then 1 end),
    coalesce(sum(case when transaction_type = 'inflow' and created_at >= v_month_start then amount else 0 end), 0),
    coalesce(sum(case when transaction_type = 'outflow' and created_at >= v_month_start then amount else 0 end), 0)
  into
    v_total_inflow,
    v_total_outflow,
    v_inflow_count,
    v_outflow_count,
    v_monthly_inflow,
    v_monthly_outflow
  from public.fellowship_fund_transactions;

  v_current_balance := v_total_inflow - v_total_outflow;

  select coalesce(jsonb_agg(jsonb_build_object(
    'category', cat.category,
    'type', cat.transaction_type,
    'totalAmount', cat.total_amount,
    'count', cat.tx_count
  )), '[]'::jsonb)
  into v_category_breakdown
  from (
    select
      category,
      transaction_type,
      sum(amount) as total_amount,
      count(*) as tx_count
    from public.fellowship_fund_transactions
    group by category, transaction_type
    order by sum(amount) desc
  ) cat;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'transactionType', t.transaction_type,
    'amount', t.amount,
    'sourceType', t.source_type,
    'category', t.category,
    'reason', t.reason,
    'employeeName', t.employee_name,
    'performerName', t.performer_name,
    'balanceAfter', t.balance_after,
    'createdAt', t.created_at
  ) order by t.created_at desc), '[]'::jsonb)
  into v_recent_transactions
  from (
    select * from public.fellowship_fund_transactions
    order by created_at desc
    limit 5
  ) t;

  return jsonb_build_object(
    'currentBalance', v_current_balance,
    'totalInflows', v_total_inflow,
    'totalOutflows', v_total_outflow,
    'inflowsCount', v_inflow_count,
    'outflowsCount', v_outflow_count,
    'monthlyInflows', v_monthly_inflow,
    'monthlyOutflows', v_monthly_outflow,
    'categoryBreakdown', v_category_breakdown,
    'recentTransactions', v_recent_transactions
  );
end;
$function$;

grant execute on function public.get_fellowship_fund_summary() to authenticated;

-- 2) get_fellowship_fund_transactions(p_limit, p_offset, p_type, p_search)
create or replace function public.get_fellowship_fund_transactions(
  p_limit integer default 50,
  p_offset integer default 0,
  p_type text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'transactionType', t.transaction_type,
      'amount', t.amount,
      'sourceType', t.source_type,
      'instantPenaltyId', t.instant_penalty_id,
      'employeeId', t.employee_id,
      'employeeName', t.employee_name,
      'performedBy', t.performed_by,
      'performerName', t.performer_name,
      'category', t.category,
      'reason', t.reason,
      'balanceAfter', t.balance_after,
      'notes', t.notes,
      'createdAt', t.created_at
    ) order by t.created_at desc)
    from public.fellowship_fund_transactions t
    where (p_type is null or p_type = 'all' or t.transaction_type = p_type)
      and (
        p_search is null
        or p_search = ''
        or t.employee_name ilike '%' || p_search || '%'
        or t.reason ilike '%' || p_search || '%'
        or t.category ilike '%' || p_search || '%'
        or coalesce(t.performer_name, '') ilike '%' || p_search || '%'
      )
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$function$;

grant execute on function public.get_fellowship_fund_transactions(integer, integer, text, text) to authenticated;

-- 3) get_instant_penalties(p_employee_id, p_status, p_date_from, p_date_to, p_limit, p_offset)
create or replace function public.get_instant_penalties(
  p_employee_id uuid default null::uuid,
  p_status text default null::text,
  p_date_from date default null::date,
  p_date_to date default null::date,
  p_limit integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is not null and not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'payroll.run.manage', 'payroll.run.approve', 'people.employee.read', 'attendance.record.read'
    ])
    or (p_employee_id is not null and p_employee_id = public.current_employee_id())
    or (p_employee_id is not null and exists (
      select 1 from public.profiles where id = auth.uid() and employee_id = p_employee_id
    ))
  ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'employeeId', p.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'departmentName', d.name,
      'workDate', p.work_date,
      'lateMinutes', p.late_minutes,
      'originalAmount', p.original_amount,
      'currentAmount', p.current_amount,
      'currency', p.currency,
      'status', p.status,
      'escalationLevel', p.escalation_level,
      'paidAt', p.paid_at,
      'confirmedBy', p.confirmed_by,
      'suspendedAt', p.suspended_at,
      'suspensionLiftedAt', p.suspension_lifted_at,
      'notes', p.notes,
      'createdAt', p.created_at,
      'excuseStatus', coalesce(p.excuse_status, 'none'),
      'excuseText', p.excuse_text,
      'excuseAttachmentUrl', p.excuse_attachment_url,
      'excuseSubmittedAt', p.excuse_submitted_at,
      'excuseReviewedAt', p.excuse_reviewed_at,
      'excuseNotes', p.excuse_notes,
      'paymentMethod', coalesce(p.payment_method, 'cash'),
      'receiptAttachmentUrl', p.receipt_attachment_url,
      'receiptSubmittedAt', p.receipt_submitted_at,
      'receiptReferenceNumber', p.receipt_reference_number
    ) order by p.work_date desc, p.created_at desc)
    from public.instant_attendance_penalties p
    join public.employees e on e.id = p.employee_id
    left join public.departments d on d.id = e.department_id
    where (p_employee_id is null or p.employee_id = p_employee_id)
      and (p_status is null or p.status = p_status)
      and (p_date_from is null or p.work_date >= p_date_from)
      and (p_date_to is null or p.work_date <= p_date_to)
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$function$;

grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated, anon;

commit;
