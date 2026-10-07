-- =====================================================================
-- 0603: RPC get_my_instant_penalties()
-- =====================================================================
-- دالة آمنة ومحددة لجلب غرامات الحضور الفورية الخاصة بالموظف الحالي فقط
-- (حتى لو كان الموظف مديراً أو يملك صلاحيات استعراض الموظفين الآخرين)
-- تضمن عدم تسريب غرامات الزملاء للوحة الغرامات الشخصية للموظف.

create or replace function public.get_my_instant_penalties()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
begin
  v_employee_id := public.current_employee_id();
  if v_employee_id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      json_build_object(
        'id', p.id,
        'employee_id', p.employee_id,
        'work_date', p.work_date,
        'late_minutes', p.late_minutes,
        'original_amount', p.original_amount,
        'current_amount', p.current_amount,
        'currency', p.currency,
        'status', p.status,
        'escalation_level', p.escalation_level,
        'paid_at', p.paid_at,
        'confirmed_by', p.confirmed_by,
        'suspended_at', p.suspended_at,
        'suspension_lifted_at', p.suspension_lifted_at,
        'suspension_lifted_by', p.suspension_lifted_by,
        'created_at', p.created_at,
        'updated_at', p.updated_at,
        'notes', p.notes,
        'excuse_status', p.excuse_status,
        'excuse_text', p.excuse_text,
        'excuse_attachment_url', p.excuse_attachment_url,
        'excuse_submitted_at', p.excuse_submitted_at,
        'excuse_reviewed_by', p.excuse_reviewed_by,
        'excuse_reviewed_at', p.excuse_reviewed_at,
        'excuse_notes', p.excuse_notes,
        'payment_method', p.payment_method,
        'receipt_attachment_url', p.receipt_attachment_url,
        'receipt_submitted_at', p.receipt_submitted_at,
        'receipt_reference_number', p.receipt_reference_number,
        'cancelled_reason', p.cancelled_reason
      )
      order by p.work_date desc, p.created_at desc
    )
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_my_instant_penalties() from public;
grant execute on function public.get_my_instant_penalties() to authenticated;
