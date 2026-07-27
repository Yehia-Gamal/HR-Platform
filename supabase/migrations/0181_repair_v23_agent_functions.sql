-- =====================================================================
-- 0181: إصلاح دوال V23 المُطبقة بكود خاطئ (0171–0173)
--
-- المشاكل الأصلية:
--   0171: get_escalation_hours() تشير لـ employee_roles (غير موجود)
--   0172: current_employee_scope() + has_scoped_permission() تشير لـ employees.manager_id (غير موجود)
--   0173: assign_employee_department — overload قديم (5 params) يسبب تضارب مع الجديد (9 params)
--
-- الإصلاحات مُطبقة محلياً على الملفات الأصلية لكن staging طُبقت عليه
-- النسخ القديمة. هذه المهاجرة تُعيد تعريف الدوال بالكود الصحيح.
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- 1) إصلاح get_escalation_hours (من 0171)
--    employee_roles → user_roles + profiles
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_escalation_hours(p_manager_id uuid)
returns integer
language sql stable security definer set search_path = public, pg_temp
as $$
  select case
    when exists (
      select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        join public.profiles p on p.id = ur.user_id
      where p.employee_id = p_manager_id
        and p.status = 'active'
        and r.slug = 'executive-director'
    )
    then coalesce(
      (select (value #>> '{}')::int from public.settings
       where scope = 'organization' and category = 'leave'
         and key = 'leave_escalation_hours_executive'),
      6
    )
    else coalesce(
      (select (value #>> '{}')::int from public.settings
       where scope = 'organization' and category = 'leave'
         and key = 'leave_escalation_hours_other'),
      12
    )
  end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) إصلاح current_employee_scope (من 0172)
--    employees.manager_id → manager_relations subquery
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.current_employee_scope()
returns jsonb
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    (select jsonb_build_object(
       'employee_id', e.id,
       'department_id', e.department_id,
       'branch_id', e.branch_id,
       'team_id', e.team_id,
       'manager_id', (select mr.manager_employee_id from public.manager_relations mr
                      where mr.employee_id = e.id and mr.relation_type = 'primary'
                        and (mr.effective_to is null or mr.effective_to >= current_date)
                      limit 1),
       'departments', coalesce(
         (select jsonb_agg(ed.department_id)
          from public.employee_departments ed
          where ed.employee_id = e.id), '[]'::jsonb
       )
     )
     from public.profiles p
     join public.employees e on e.id = p.employee_id
     where p.id = auth.uid() and p.status = 'active'
     limit 1
    ),
    '{}'::jsonb
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) إصلاح has_scoped_permission (من 0172)
--    subordinate case: employees.manager_id → manager_relations
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.has_scoped_permission(
  p_permission_slug text,
  p_scope_type text default null,
  p_scope_id uuid default null
)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_has_base boolean;
  v_scope jsonb;
begin
  -- full-access يمر دائمًا
  if public.current_is_full_access() then
    return true;
  end if;

  -- تحقق من الصلاحية الأساسية (بدون نطاق)
  v_has_base := public.has_permission(p_permission_slug);
  if not v_has_base then
    return false;
  end if;

  -- إذا لم يُحدد نطاق، الصلاحية الأساسية كافية
  if p_scope_type is null or p_scope_id is null then
    return true;
  end if;

  -- جلب نطاق الموظف الحالي
  v_scope := public.current_employee_scope();
  if v_scope = '{}'::jsonb then
    return false;
  end if;

  -- التحقق من النطاق حسب النوع
  case p_scope_type
    when 'department' then
      return (v_scope->'departments') @> to_jsonb(p_scope_id);
    when 'branch' then
      return (v_scope->>'branch_id')::uuid = p_scope_id;
    when 'team' then
      return (v_scope->>'team_id')::uuid = p_scope_id;
    when 'subordinate' then
      -- يملك الصلاحية إذا كان الهدف أحد مرؤوسيه
      return exists (
        select 1 from public.manager_relations mr
        join public.employees e on e.id = mr.employee_id
        where mr.employee_id = p_scope_id
          and mr.manager_employee_id = (v_scope->>'employee_id')::uuid
          and mr.relation_type = 'primary'
          and (mr.effective_to is null or mr.effective_to >= current_date)
          and e.is_active = true
      );
    else
      return false;
  end case;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) حذف overload قديم لـ assign_employee_department (من 0156)
--    يمنع تضارب التوقيعات مع النسخة الجديدة ذات 9 params (0173)
-- ═══════════════════════════════════════════════════════════════════════
drop function if exists public.assign_employee_department(uuid, uuid, text, boolean, text);
