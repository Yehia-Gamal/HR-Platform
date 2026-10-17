-- Migration 0668: الشفافية الكاملة لغرامات التأخير الفورية وصندوق الزمالة والتكافل
-- ==============================================================================
-- بطلب الإدارة:
-- 1) جعل سجل غرامات التأخير الفورية مرئياً لجميع منسوبي الجمعية لتعزيز الانضباط
--    والشفافية الاجتماعية (معرفة من تأخر، دقائق التأخير، قيمة الغرامة، وموقف السداد).
--    مع بقاء نصوص ومرفقات الأعذار الشخصية خاصة بصاحب الشأن والإدارة فقط.
-- 2) جعل أسماء المسددين في صندوق الزمالة والتكافل ظاهرة للجميع في سجل حركات الصندوق
--    لترسيخ مبدأ التكافل الاجتماعي واعتزازاً بمن يساهم أو يسدد في الصندوق.
-- ==============================================================================

begin;

-- 1) دالة جلب غرامات الحضور والانصراف الفورية (شفافة لجميع الموظفين المسجلين)
CREATE OR REPLACE FUNCTION public.get_instant_penalties(
  p_employee_id uuid DEFAULT NULL::uuid,
  p_status text DEFAULT NULL::text,
  p_date_from date DEFAULT NULL::date,
  p_date_to date DEFAULT NULL::date,
  p_limit integer DEFAULT NULL::integer,
  p_offset integer DEFAULT 0
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_is_admin_or_hr boolean;
  v_me uuid;
begin
  if auth.uid() is null then
    raise exception 'غير مسموح: يجب تسجيل الدخول' using errcode = '42501';
  end if;

  v_is_admin_or_hr := public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage', 'attendance.day.override'])
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director']);
  v_me := public.current_employee_id();

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
        'excuseText',             case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_text end,
        'excuseAttachmentUrl',    case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_attachment_url end,
        'excuseSubmittedAt',      t.excuse_submitted_at,
        'excuseReviewedAt',       t.excuse_reviewed_at,
        'excuseNotes',            case when (v_is_admin_or_hr or t.employee_id = v_me) then t.excuse_notes end,
        'paymentMethod',          t.payment_method,
        'receiptAttachmentUrl',   case when (v_is_admin_or_hr or t.employee_id = v_me) then t.receipt_attachment_url end,
        'receiptSubmittedAt',     t.receipt_submitted_at,
        'receiptReferenceNumber', t.receipt_reference_number,
        'cancelledReason',        t.cancelled_reason
      )
      order by t.work_date desc, t.created_at desc
    )
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
      where (p_employee_id is null or p.employee_id = p_employee_id)
        and (p_status is null or p.status = p_status)
        and (p_date_from is null or p.work_date >= p_date_from)
        and (p_date_to is null or p.work_date <= p_date_to)
      order by p.work_date desc, p.created_at desc
      limit case when p_limit is null then null else greatest(1, p_limit) end
      offset greatest(0, coalesce(p_offset, 0))
    ) t
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from public, anon;
grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated, service_role;

-- 2) دالة حركات صندوق الزمالة والتكافل (أسماء المسددين والمودعين ظاهرة بشفافية للجميع)
CREATE OR REPLACE FUNCTION public.get_fellowship_fund_transactions(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_type text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'غير مسموح: يجب تسجيل الدخول' using errcode = '42501';
  end if;

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
        or (t.employee_name ilike '%' || p_search || '%')
        or t.reason ilike '%' || p_search || '%'
        or t.category ilike '%' || p_search || '%'
        or (coalesce(t.performer_name, '') ilike '%' || p_search || '%')
      )
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_fellowship_fund_transactions(integer, integer, text, text) from public, anon;
grant execute on function public.get_fellowship_fund_transactions(integer, integer, text, text) to authenticated, service_role;

comment on function public.get_instant_penalties is
  'جلب غرامات الحضور والانصراف الفورية بشفافية لجميع منسوبي الجمعية، مع حصر تفاصيل ومرفقات الأعذار الطبية/الشخصية للإدارة وصاحب الشأن فقط.';

comment on function public.get_fellowship_fund_transactions is
  'جلب حركات صندوق الزمالة والتكافل بشفافية تامة مع إظهار اسم الزميل المسدد أو المتبرع لتعزيز التكافل الاجتماعي والانضباط.';

commit;
