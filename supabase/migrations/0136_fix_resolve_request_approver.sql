-- 0136_fix_resolve_request_approver.sql
-- إصلاح: resolve_request_approver يشير إلى جدول role_assignments غير الموجود.
-- الجدول الصحيح هو user_roles (user_id → role_id) مع ربطه عبر employees.user_id.
-- لا تغيير في المنطق — فقط إصلاح مسار الجدول.

create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
  v_dept_id uuid;
  v_is_operations boolean := false;
  v_executive_employee_id uuid;
begin
  -- المدير المباشر (primary) من الهيكل الإداري
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= p_as_of
    and (effective_to is null or effective_to >= p_as_of)
  order by effective_from desc
  limit 1;

  -- منع الموافقة الذاتية: لو صار المدير هو المُقدِّم نفسه، اصعد لمديره
  if v_mgr is not null and v_mgr = p_employee_id then
    select manager_employee_id into v_mgr
    from public.manager_relations
    where employee_id = p_employee_id
      and relation_type = 'primary'
      and manager_employee_id <> p_employee_id
      and effective_from <= p_as_of
      and (effective_to is null or effective_to >= p_as_of)
    order by effective_from desc
    limit 1;
  end if;

  -- V17 §1.2: توجيه طلبات التشغيل للمدير التنفيذي
  -- نتحقق هل الموظف تابع لإدارة تشغيل (slug يبدأ بـ operations)
  select e.department_id into v_dept_id
  from public.employees e
  where e.id = p_employee_id and e.is_active and not e.is_deleted;

  if v_dept_id is not null then
    -- تحقق من شجرة الإدارات: هل الإدارة أو أحد أسلافها هي "operations"
    select exists(
      with recursive dept_tree as (
        select d.id, d.slug, d.parent_id
        from public.departments d where d.id = v_dept_id
        union all
        select p.id, p.slug, p.parent_id
        from public.departments p
        join dept_tree dt on dt.parent_id = p.id
      )
      select 1 from dept_tree where slug like 'operations%'
    ) into v_is_operations;
  end if;

  if v_is_operations then
    -- FIX: استخدام user_roles بدلاً من role_assignments غير الموجود
    select e.id into v_executive_employee_id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'executive'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id  -- لا يعتمد المدير التنفيذي طلبه لنفسه
    limit 1;

    if v_executive_employee_id is not null then
      v_mgr := v_executive_employee_id;
    end if;
  end if;

  return v_mgr;
end $$;

comment on function public.resolve_request_approver(uuid, date) is
  'V17 §1.2+§8: يحدد المدير المسؤول عن طلب الموظف — التشغيل يُوجَّه للمدير التنفيذي، مع منع الموافقة الذاتية. (0136: إصلاح ربط user_roles)';
