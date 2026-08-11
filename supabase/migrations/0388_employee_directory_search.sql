-- مig 0388: دليل الموظفين الموحد — بحث خفيف متاح لجميع الموظفين
-- يُعيد الاسم + كود الموظف + الإدارة + المسمى الوظيفي + الصورة فقط، بلا بيانات حساسة.

create or replace function public.get_mobile_employee_directory(
  p_search text default null,
  p_limit  integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
begin
  -- متاح لأي موظف مفعّل في المنظمة
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    where e.is_active  = true
      and e.is_deleted = false
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
$$;

revoke all on function public.get_mobile_employee_directory(text, integer) from public;
grant execute on function public.get_mobile_employee_directory(text, integer) to authenticated;
