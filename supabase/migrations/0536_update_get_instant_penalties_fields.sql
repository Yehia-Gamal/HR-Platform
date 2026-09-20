-- =====================================================================
-- 0536: تحديث get_instant_penalties لإرجاع حقول التظلمات وإيصالات السداد
-- =====================================================================

begin;

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
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- السماح للمديرين أو الموظف نفسه باستعراض غراماته (والسماح لـ service_role / الكرون / auth.uid() is null)
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
