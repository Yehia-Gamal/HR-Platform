-- ═══════════════════════════════════════════════════════════════
-- 0519: تحسين update_association_project_admin للتحديث الجزئي
-- يسمح بتحديث حقل واحد فقط بدلاً من جميع الحقول
-- ═══════════════════════════════════════════════════════════════

create or replace function public.update_association_project_admin(
  p_project_id        uuid,
  p_name              text default null,
  p_description       text default null,
  p_department_id     uuid default null,
  p_owner_employee_id uuid default null,
  p_status            text default null,
  p_priority          text default null,
  p_progress          numeric default null,
  p_start_date        date default null,
  p_target_end_date   date default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  -- full-access: يعدل أي مشروع
  -- المالك: يعدل مشاريعه فقط إذا كانت draft/rejected
  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id
        and owner_employee_id = v_emp
        and approval_status in ('draft','rejected')
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
  end if;

  update public.association_projects set
    name              = coalesce(p_name, name),
    description       = coalesce(p_description, description),
    department_id     = coalesce(p_department_id, department_id),
    owner_employee_id = coalesce(p_owner_employee_id, owner_employee_id),
    status            = coalesce(p_status, status),
    priority          = coalesce(p_priority, priority),
    progress          = coalesce(p_progress, progress),
    start_date        = coalesce(p_start_date, start_date),
    target_end_date   = coalesce(p_target_end_date, target_end_date)
  where id = p_project_id;
end;
$$;

revoke all on function public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date) from public;
grant execute on function public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date) to authenticated;
