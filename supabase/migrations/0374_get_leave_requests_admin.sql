-- ============================================================================
-- 0374: get_leave_requests_admin — عرض إداري شامل لطلبات الإجازات
-- ============================================================================
-- يتيح لـ HR وfull_access مراجعة جميع طلبات الإجازات مع فلاتر متعددة.
-- يعيد jsonb {total, rows} ليدعم الـ pagination من الويب.
-- ============================================================================

begin;

create or replace function public.get_leave_requests_admin(
  p_year         integer default null,
  p_status       text    default null,
  p_leave_type   text    default null,
  p_employee_id  uuid    default null,
  p_limit        integer default 50,
  p_offset       integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_year  integer;
  v_total bigint;
  v_rows  jsonb;
begin
  if not (
    current_is_full_access()
    or has_permission('requests.leave.balance.read')
    or has_permission('requests.request.read')
  ) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Africa/Cairo')::integer);

  -- العد الكلي قبل الـ pagination
  select count(*)
    into v_total
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    join public.employees e on e.id = lr.employee_id
     and coalesce(e.is_deleted, false) = false
    join public.leave_types lt on lt.id = lr.leave_type_id
   where extract(year from lr.start_date)::integer = v_year
     and (p_status      is null or r.status = p_status)
     and (p_leave_type  is null or lt.code  = p_leave_type)
     and (p_employee_id is null or e.id     = p_employee_id);

  -- جلب الصفحة المطلوبة
  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'requestId',     r.id,
        'requestNumber', r.request_number,
        'status',        r.status,
        'createdAt',     r.created_at,
        'employeeId',    e.id,
        'employeeCode',  e.employee_code,
        'employeeName',  coalesce(e.full_name_ar, e.full_name_en),
        'leaveTypeId',   lt.id,
        'leaveTypeCode', lt.code,
        'leaveTypeName', lt.name_ar,
        'isPaid',        lt.is_paid,
        'startDate',     lr.start_date,
        'endDate',       lr.end_date,
        'daysCount',     lr.days_count,
        'hoursCount',    lr.hours_count,
        'durationUnit',  coalesce(lr.duration_unit, 'day'),
        'isHalfDay',     coalesce(lr.is_half_day, false),
        'reason',        r.reason,
        'handoverNotes', lr.handover_notes,
        'attachmentUrl', lr.attachment_url
      ) as row_data,
      r.created_at
        from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        join public.employees e on e.id = lr.employee_id
         and coalesce(e.is_deleted, false) = false
        join public.leave_types lt on lt.id = lr.leave_type_id
       where extract(year from lr.start_date)::integer = v_year
         and (p_status      is null or r.status = p_status)
         and (p_leave_type  is null or lt.code  = p_leave_type)
         and (p_employee_id is null or e.id     = p_employee_id)
       order by r.created_at desc
       limit p_limit offset p_offset
    ) sub;

  return jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;

revoke execute on function public.get_leave_requests_admin(integer, text, text, uuid, integer, integer) from anon;
grant  execute on function public.get_leave_requests_admin(integer, text, text, uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
