-- =====================================================================
-- 0482: إعادة تطبيق عزل الإدارة الطبية في دليل الموظفين
-- ---------------------------------------------------------------------
-- 0478 (مسح رسائل الخطأ العربية) أعاد تعريف get_mobile_employee_directory
-- بدون فلتر العزل الذي أضافه 0474، فأظهرت الاختبارات أعضاء الإدارة الطبية
-- المعزولة في دليل الموظفين للمستخدمين غير المخوّلين.
-- هذه الـ migration تُعيد تعريف الدالة بذات النسخة الكنونية من 0478
-- مع إعادة إدراج شرط `can_see_directory_entry` فقط (إضافة تلغي نفسها إذا
-- أُعيد تعريف الدالة لاحقاً بفلتر العزل).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_mobile_employee_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name,
      'statusToday',  case
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
        when exists (
          select 1 from public.missions m join public.requests r on r.id = m.request_id
          where m.employee_id = e.id and r.status = 'approved'
            and v_today between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
          where c.employee_id = e.id and r.status = 'approved'
            and v_today between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
          where wp.employee_id = e.id and wa.status = 'APPROVED' and coalesce(wa.counts_as_work_day,true)
            and v_today between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id and r.status = 'approved'
            and v_today between lr.start_date and lr.end_date
        ) then 'on_leave'
        else 'absent'
      end
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    where e.is_active  = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and public.can_see_directory_entry(public.current_employee_id(), e.id)  -- 0474/0482: عزل الإدارة الطبية في الدليل
      and (
        v_search is null
        or e.full_name_ar  ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%'
        or jt.name         ilike '%' || v_search || '%'
        or d.name          ilike '%' || v_search || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$function$;

commit;