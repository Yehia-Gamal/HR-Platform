-- 0159: إصلاح دالة is_official_holiday — الانضمام عبر departments للحصول على legal_entity_id.
-- ============================================================================
-- خلفية:
--   Migration 0132 افترضت أن جدول employees يحتوي على legal_entity_id مباشرة.
--   الحقيقة: employees → departments → legal_entities هو المسار الصحيح.
-- ============================================================================

create or replace function public.is_official_holiday(
  p_date          date,
  p_employee_id   uuid default null
) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_dept_id   uuid;
  v_entity_id uuid;
begin
  -- استخراج إدارة وجهة الموظف عبر الانضمام بجدول departments
  if p_employee_id is not null then
    select e.department_id, d.legal_entity_id
      into v_dept_id, v_entity_id
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where e.id = p_employee_id and e.is_active and not e.is_deleted;
  end if;

  return exists(
    select 1 from public.public_holidays h
    where h.is_active
      and p_date >= h.holiday_date
      and p_date <= coalesce(h.end_date, h.holiday_date)
      -- نطاق العطلة
      and (
        h.scope = 'all'
        or (h.scope = 'legal_entity' and h.legal_entity_id = v_entity_id)
        or (h.scope = 'department'   and h.department_id = v_dept_id)
      )
      -- استثناءات الإدارات
      and (
        h.excluded_department_ids = '{}'
        or v_dept_id is null
        or not (v_dept_id = any(h.excluded_department_ids))
      )
  );
end;
$$;
