-- Migration: get_mobile_org_chart — returns employee hierarchy for mobile org chart.
-- Shows all active employees grouped by department with manager relationships.

create or replace function public.get_mobile_org_chart()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_result  jsonb;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  with dept_tree as (
    select d.id, d.name, d.parent_id, d.manager_id,
           0 as depth, array[d.id] as path
    from departments d
    where d.parent_id is null
    union all
    select c.id, c.name, c.parent_id, c.manager_id,
           t.depth + 1, t.path || c.id
    from departments c
    join dept_tree t on c.parent_id = t.id
    where not c.id = any(t.path)
  ),
  emp_data as (
    select
      e.id,
      e.full_name_ar,
      e.employee_code,
      coalesce(jt.name_ar, jt.name_en, '') as job_title,
      e.photo_url,
      e.department_id,
      coalesce(d.name, '') as department_name,
      d.manager_id as dept_manager_id,
      e.is_active,
      e.status
    from employees e
    left join job_titles jt on jt.id = e.job_title_id
    left join departments d on d.id = e.department_id
    where e.is_active = true
      and e.is_deleted = false
      and e.status in ('active', 'probation_failed', 'onboarding')
  )
  select jsonb_build_object(
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dt.id,
        'name', dt.name,
        'parentId', dt.parent_id,
        'managerId', dt.manager_id,
        'depth', dt.depth
      ) order by dt.path)
      from dept_tree dt
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id,
        'fullNameAr', ed.full_name_ar,
        'employeeCode', ed.employee_code,
        'jobTitle', ed.job_title,
        'photoUrl', ed.photo_url,
        'departmentId', ed.department_id,
        'departmentName', ed.department_name,
        'isDeptManager', ed.dept_manager_id = ed.id
      ) order by (ed.dept_manager_id = ed.id) desc, ed.full_name_ar)
      from emp_data ed
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

comment on function public.get_mobile_org_chart() is
  'يعيد الهيكل التنظيمي الكامل: الإدارات وموظفيها مع صور ومسميات.';

revoke execute on function public.get_mobile_org_chart() from public;
grant execute on function public.get_mobile_org_chart() to authenticated;
