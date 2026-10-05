-- 0642: الغرامات الفورية وصندوق الزمالة — نطاق الاطلاع، خصوصية الأسماء،
--       دالة الجدولة، وإلغاء بلا تكرار الملاحظات
-- ===========================================================================
-- 1) get_instant_penalties: كان أي موظف يرى غرامات المنظمة كلها بأسماء أصحابها
--    (has_any_permission يتجاهل النطاق، و«موظف» يملك attendance.record.read
--    بنطاق «نفسه»). الآن: الكل للوصول الكامل والمالية وHR والإدارة التنفيذية،
--    وغيرهم من يملك ملفه فقط (نفسه، والمدير فريقه المباشر). + cancelledReason.
-- 2) get_fellowship_fund_summary / get_fellowship_fund_transactions: بلا أي فحص.
--    الآن تتطلب جلسة؛ الأرقام والحركات للجميع، والأسماء للإدارة والمالية وHR.
-- 3) auto_escalate_instant_penalties: دالة جدولة (cron كـ postgres) بلا فحص
--    صلاحية وكانت قابلة للاستدعاء من أي موظف ← service_role فقط.
-- 4) cancel_instant_penalty: إلغاء الملغاة كان يلفّ الملاحظات من جديد (20
--    غرامة بملاحظات متداخلة) ← لا يُعاد إلغاء الملغاة، والسبب في
--    cancelled_reason ويُلحق بالملاحظات مرة واحدة.
-- استبدال كنوني كامل من الأجسام الحية بهذه التغييرات فقط.
-- ===========================================================================

begin;

CREATE OR REPLACE FUNCTION public.get_instant_penalties(p_employee_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT NULL::integer, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_all boolean;
begin
  -- تتطلب جلسة مستخدم. لا استثناء لـ«غياب الجلسة»:
  --   • لا يستدعيها أي عامل خادمي — الويب فقط (useInstantPenalties.ts).
  --   • و current_user داخل SECURITY DEFINER يساوي *مالك الدالة* لا المستدعي،
  --     فلا يصلح للتمييز بين anon و service_role (وثّق ذلك مؤلف 0483 نفسه).
  --     أي فحص على current_user هنا لا يُطلق أبداً — لذا نرفض غياب الجلسة مباشرة.
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 0642: كان الشرط has_any_permission(... 'attendance.record.read' ...) يتجاهل
  -- النطاق — دور «موظف» يملك attendance.record.read بنطاق «نفسه» فكان أي موظف
  -- يرى غرامات المنظمة كلها بأسماء أصحابها. الآن: الكل للوصول الكامل والمالية
  -- وHR والإدارة التنفيذية؛ وغيرهم يرى من يملك ملفه فقط (نفسه، والمدير فريقه).
  v_all := public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage'])
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director']);

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',                     t.id,
        'employeeId',             t.employee_id,
        'employeeName',           t.employee_name,
        'employeeCode',           t.employee_code,
        'departmentName',         t.department_name,
        'workDate',               t.work_date,
        'lateMinutes',            t.late_minutes,
        'originalAmount',         t.original_amount,
        'currentAmount',          t.current_amount,
        'currency',               t.currency,
        'status',                 t.status,
        'escalationLevel',        t.escalation_level,
        'paidAt',                 t.paid_at,
        'confirmedBy',            t.confirmed_by,
        'suspendedAt',            t.suspended_at,
        'suspensionLiftedAt',     t.suspension_lifted_at,
        'notes',                  t.notes,
        'createdAt',              t.created_at,
        'excuseStatus',           t.excuse_status,
        'excuseText',             t.excuse_text,
        'excuseAttachmentUrl',    t.excuse_attachment_url,
        'excuseSubmittedAt',      t.excuse_submitted_at,
        'excuseReviewedAt',       t.excuse_reviewed_at,
        'excuseNotes',            t.excuse_notes,
        'paymentMethod',          t.payment_method,
        'receiptAttachmentUrl',   t.receipt_attachment_url,
        'receiptSubmittedAt',     t.receipt_submitted_at,
        'receiptReferenceNumber', t.receipt_reference_number,
        'cancelledReason',        t.cancelled_reason
      )
      order by t.work_date desc, t.created_at desc
    )
    -- الترقيم داخل استعلام فرعي: limit/offset على استعلام تجميعي بلا أثر.
    from (
      select
        p.id,
        p.employee_id,
        e.full_name_ar                        as employee_name,
        e.employee_code,
        d.name                                as department_name,
        p.work_date,
        p.late_minutes,
        p.original_amount,
        p.current_amount,
        p.currency,
        p.status,
        p.escalation_level,
        p.paid_at,
        p.confirmed_by,
        p.suspended_at,
        p.suspension_lifted_at,
        p.notes,
        p.created_at,
        coalesce(p.excuse_status, 'none')     as excuse_status,
        p.excuse_text,
        p.excuse_attachment_url,
        p.excuse_submitted_at,
        p.excuse_reviewed_at,
        p.excuse_notes,
        coalesce(p.payment_method, 'cash')    as payment_method,
        p.receipt_attachment_url,
        p.receipt_submitted_at,
        p.receipt_reference_number,
        p.cancelled_reason
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      where (v_all or public.can_access_employee(p.employee_id, 'people.employee.read'))
        and (p_employee_id is null or p.employee_id = p_employee_id)
        and (p_status is null or p.status = p_status)
        and (p_date_from is null or p.work_date >= p_date_from)
        and (p_date_to is null or p.work_date <= p_date_to)
      order by p.work_date desc, p.created_at desc
      -- LIMIT NULL في PostgreSQL = بلا تقييد. الاستدعاءات القائمة (الويب لا
      -- يمرّر p_limit) تبقى كما هي تماماً، ومن يمرّر قيمة يحصل على تقييد فعلي.
      limit case when p_limit is null then null else greatest(1, p_limit) end
      offset greatest(0, coalesce(p_offset, 0))
    ) t
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from public, anon;
grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_fellowship_fund_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_names boolean;
  v_me uuid;
begin
  -- 0642: كانت بلا أي فحص. الأرقام للجميع (شفافية الصندوق)، وأسماء من سدّد أو
  -- نفّذ الحركة للإدارة والمالية وHR فقط (الموظف يرى اسمه في حركاته).
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  v_names := public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage'])
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director']);
  v_me := public.current_employee_id();

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
    'employeeName', case when v_names or t.employee_id = v_me then t.employee_name end,
    'performerName', case when v_names then t.performer_name end,
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

revoke all on function public.get_fellowship_fund_summary() from public, anon;
grant execute on function public.get_fellowship_fund_summary() to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_fellowship_fund_transactions(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_type text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_names boolean;
  v_me uuid;
begin
  -- 0642: كانت بلا أي فحص (أسماء من سدّد غرامته لكل موظف). الحركات والمبالغ
  -- للجميع، والأسماء للإدارة والمالية وHR فقط (والموظف يرى اسمه في حركاته).
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  v_names := public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage'])
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director']);
  v_me := public.current_employee_id();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'transactionType', t.transaction_type,
      'amount', t.amount,
      'sourceType', t.source_type,
      'instantPenaltyId', t.instant_penalty_id,
      'employeeId', case when v_names or t.employee_id = v_me then t.employee_id end,
      'employeeName', case when v_names or t.employee_id = v_me then t.employee_name end,
      'performedBy', case when v_names then t.performed_by end,
      'performerName', case when v_names then t.performer_name end,
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
        or (v_names and t.employee_name ilike '%' || p_search || '%')
        or t.reason ilike '%' || p_search || '%'
        or t.category ilike '%' || p_search || '%'
        or (v_names and coalesce(t.performer_name, '') ilike '%' || p_search || '%')
      )
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_fellowship_fund_transactions(integer, integer, text, text) from public, anon;
grant execute on function public.get_fellowship_fund_transactions(integer, integer, text, text) to authenticated, service_role;

revoke all on function public.auto_escalate_instant_penalties() from public, anon, authenticated;
grant execute on function public.auto_escalate_instant_penalties() to service_role;

CREATE OR REPLACE FUNCTION public.cancel_instant_penalty(p_penalty_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_was_suspended boolean;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin')
       )
     ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'سبب الإلغاء مطلوب (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  if v_me is null then
    select id into v_me from public.employees where is_active = true and is_deleted = false order by created_at limit 1;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  -- 0642: إلغاء غرامة ملغاة كان يلفّ الملاحظات مرة أخرى («تم الإلغاء… (تم الإلغاء… (…)))»)
  if v_row.status = 'cancelled' then
    return jsonb_build_object(
      'success', true,
      'id', v_row.id,
      'penaltyId', v_row.id,
      'status', 'cancelled',
      'currentAmount', v_row.current_amount,
      'wasSuspended', false,
      'alreadyCancelled', true,
      'message', 'الغرامة ملغاة بالفعل'
    );
  end if;

  if v_row.status = 'paid' then
    raise exception 'لا يمكن إلغاء غرامة تم دفعها وتوريدها لصندوق الزمالة' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء إداري: ' || trim(p_reason),
         notes = coalesce(notes || ' | ', '') || 'إلغاء إداري: ' || trim(p_reason),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  if v_was_suspended then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', 'cancelled',
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended,
    'message', 'تم إلغاء الغرامة بنجاح'
  );
end;
$function$;

revoke all on function public.cancel_instant_penalty(uuid, text) from public, anon;
grant execute on function public.cancel_instant_penalty(uuid, text) to authenticated, service_role;

commit;
