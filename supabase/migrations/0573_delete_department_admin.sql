-- 0573: حذف إدارة نهائياً عبر RPC آمن (delete_department_admin)
-- ===========================================================================
-- لا يوجد مسار حذف للإدارات حالياً (فقط التعطيل is_active=false) وتراكمت
-- إدارات مكررة/بلا استخدام. تُحذف الإدارة فقط إذا لم تكن مرتبطة بأي إشارة
-- حية؛ وإلا يُرفض الحذف برسالة عربية تذكر السبب بالتفصيل.
-- جداول ذات ON DELETE CASCADE (فرق، خطط القوى العاملة، لقطات سعة، إسنادات
-- متعددة) تُفحص قبل الحذف كي لا تُحذف ضمناً. جداول ON DELETE SET NULL
-- (الموظف الأساسي، انتقالات الموظفين، المشاريع، الملف الشخصي...) تُترك كما
-- هي — تُصفَّر أشارتها فقط بعد الحذف الناجح.
-- نفس صلاحيات upsert_department_admin: full-access أو إدارة الأقسام/الوحدات.

create or replace function public.delete_department_admin(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_blockers text[] := array[]::text[];
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('organization.department.manage')
    or public.has_permission('organization.unit.manage')
  ) then
    raise exception 'إدارة الأقسام مرفوضة' using errcode = '42501';
  end if;

  select d.name into v_name from public.departments d where d.id = p_id;
  if v_name is null then
    raise exception 'الإدارة غير موجودة' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.departments c where c.parent_id = p_id) then
    v_blockers := v_blockers || 'إدارات فرعية';
  end if;
  if exists (select 1 from public.employees e where e.department_id = p_id and not e.is_deleted) then
    v_blockers := v_blockers || 'موظفون مسندون';
  end if;
  if exists (select 1 from public.employee_departments ed where ed.department_id = p_id) then
    v_blockers := v_blockers || 'إسنادات متعددة للموظفين';
  end if;
  if exists (select 1 from public.positions p where p.department_id = p_id) then
    v_blockers := v_blockers || 'مناصب مرتبطة';
  end if;
  if exists (select 1 from public.teams t where t.department_id = p_id) then
    v_blockers := v_blockers || 'فرق';
  end if;
  if exists (select 1 from public.job_requisitions j where j.department_id = p_id) then
    v_blockers := v_blockers || 'طلبات توظيف';
  end if;
  if exists (select 1 from public.association_projects ap where ap.department_id = p_id) then
    v_blockers := v_blockers || 'مشروعات';
  end if;
  if exists (select 1 from public.workforce_plans wp where wp.department_id = p_id) then
    v_blockers := v_blockers || 'خطط القوى العاملة';
  end if;
  if exists (select 1 from public.capacity_snapshots cs where cs.department_id = p_id) then
    v_blockers := v_blockers || 'لقطات السعة';
  end if;

  if array_length(v_blockers, 1) > 0 then
    raise exception 'لا يمكن حذف الإدارة «%» لأنها مرتبطة بـ: %',
      v_name, array_to_string(v_blockers, '، ') using errcode = '23514';
  end if;

  delete from public.departments where id = p_id;
end;
$$;

revoke execute on function public.delete_department_admin(uuid) from public, anon;
grant execute on function public.delete_department_admin(uuid) to authenticated;
