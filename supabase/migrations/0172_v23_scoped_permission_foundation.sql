-- =====================================================================
-- 0172: V23 §3 — has_scoped_permission() الأساس لترحيل RLS التدريجي
--
-- المرجع: V22 §1A.3 — ترحيل RLS تدريجيًا
-- الخطوة الأولى: إنشاء has_scoped_permission() واختبارها دون ربط.
--
-- التصميم:
--   1) has_scoped_permission(p_permission_slug, p_scope_type, p_scope_id)
--      — يتحقق من صلاحية المستخدم ضمن نطاق محدد (إدارة/فرع/فريق)
--   2) has_any_scoped_permission(p_slugs[], p_scope_type, p_scope_id)
--      — نسخة بأكثر من صلاحية
--   3) current_employee_scope() — يُعيد نطاق الموظف الحالي
--   4) Feature flag: scoped_rls_enabled (معطل افتراضيًا)
--
-- التراجع: DROP FUNCTION has_scoped_permission, has_any_scoped_permission,
--   current_employee_scope; DELETE setting scoped_rls_enabled
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- 1) Feature flag — معطل افتراضيًا حتى يُفعّل بعد Shadow testing
-- ═══════════════════════════════════════════════════════════════════════
insert into public.settings (scope, category, key, value, value_type, description)
values (
  'organization', 'security', 'scoped_rls_enabled', 'false'::jsonb, 'boolean',
  'V23: تفعيل نظام الصلاحيات المحددة النطاق (has_scoped_permission). معطل حتى اكتمال Shadow testing.'
)
on conflict (scope, scope_id, category, key) do nothing;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) current_employee_scope() — نطاق الموظف الحالي
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
       'manager_id', e.manager_id,
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

comment on function public.current_employee_scope() is
  'V23 §3: يُعيد نطاق الموظف الحالي (إدارة/فرع/فريق/مدير) لاستخدامه في RLS المحدد النطاق.';

revoke execute on function public.current_employee_scope() from public;
grant execute on function public.current_employee_scope() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) has_scoped_permission() — التحقق من صلاحية ضمن نطاق
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.has_scoped_permission(
  p_permission_slug text,
  p_scope_type text default null,  -- 'department' | 'branch' | 'team' | null (global)
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
      -- يملك الصلاحية إذا كانت الإدارة في قائمة إداراته
      return (v_scope->'departments') @> to_jsonb(p_scope_id);
    when 'branch' then
      return (v_scope->>'branch_id')::uuid = p_scope_id;
    when 'team' then
      return (v_scope->>'team_id')::uuid = p_scope_id;
    when 'subordinate' then
      -- يملك الصلاحية إذا كان الهدف أحد مرؤوسيه
      return exists (
        select 1 from public.employees e
        where e.id = p_scope_id
          and e.manager_id = (v_scope->>'employee_id')::uuid
          and e.is_active = true
      );
    else
      return false;
  end case;
end;
$$;

comment on function public.has_scoped_permission(text, text, uuid) is
  'V23 §3: فحص صلاحية ضمن نطاق محدد (إدارة/فرع/فريق/مرؤوس). الأساس لترحيل RLS التدريجي.';

revoke execute on function public.has_scoped_permission(text, text, uuid) from public;
grant execute on function public.has_scoped_permission(text, text, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) has_any_scoped_permission() — نسخة بأكثر من صلاحية
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.has_any_scoped_permission(
  p_permission_slugs text[],
  p_scope_type text default null,
  p_scope_id uuid default null
)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from unnest(p_permission_slugs) s(slug)
    where public.has_scoped_permission(s.slug, p_scope_type, p_scope_id)
  );
$$;

comment on function public.has_any_scoped_permission(text[], text, uuid) is
  'V23 §3: فحص أي صلاحية من قائمة ضمن نطاق. يُعيد true إذا تحققت واحدة على الأقل.';

revoke execute on function public.has_any_scoped_permission(text[], text, uuid) from public;
grant execute on function public.has_any_scoped_permission(text[], text, uuid) to authenticated;
