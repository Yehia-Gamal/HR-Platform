-- Migration 0715: Return photo_url in get_instant_penalties RPC
-- Ensures employee avatars render in the instant penalties tables and dialogs.

create or replace function public.get_instant_penalties(
  p_employee_id uuid default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_is_admin_or_hr boolean;
  v_me uuid;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
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
        'photoUrl',               t.photo_url,
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
        'cancelledReason',        t.cancelled_reason,
        'awaitingCheckoutConfirmation', t.awaiting_checkout_confirmation,
        'elapsedMinutesToday',    t.elapsed_minutes_today
      )
      order by t.work_date desc, t.created_at desc
    )
    from (
      select
        p.id,
        p.employee_id,
        e.full_name_ar                        as employee_name,
        e.employee_code,
        e.photo_url,
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
        p.cancelled_reason,
        (
          p.status in ('pending_payment', 'doubled')
          and ad.first_check_in is not null
          and ad.last_check_out is null
          and p.work_date = v_today
          and floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', ad.first_check_in))) / 60) >= 480
        ) as awaiting_checkout_confirmation,
        case
          when ad.first_check_in is not null and ad.last_check_out is null and p.work_date = v_today then
            floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', ad.first_check_in))) / 60)::integer
          else coalesce(ad.work_minutes, 0)
        end as elapsed_minutes_today
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      left join public.attendance_daily ad on ad.employee_id = p.employee_id and ad.work_date = p.work_date
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
$$;

revoke all on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from public, anon;
grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated, service_role;

