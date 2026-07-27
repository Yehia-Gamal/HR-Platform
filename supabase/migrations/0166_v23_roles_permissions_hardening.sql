-- =====================================================================
-- V23 وكيل 01 — تقوية الأدوار والصلاحيات
-- 1) is_capability: عضوية اللجنة قدرة إضافية وليست دوراً تنظيمياً بديلاً
-- 2) current_is_hr_only(): فحص مستخدم HR بدون full-access
-- 3) rpc_assign_role: تقييد HR لمنح أدوار الموظف/المدير/التشغيل فقط + تدقيق
-- 4) rpc_revoke_role: تدقيق كل عملية سحب دور
-- =====================================================================

-- =====================================================================
-- 1) roles.is_capability — القدرة الإضافية (مثل عضوية اللجنة)
-- =====================================================================
alter table public.roles add column if not exists is_capability boolean not null default false;

comment on column public.roles.is_capability is
  'V23: قدرة إضافية تُمنح فوق الدور التنظيمي (مثل عضوية لجنة المشكلات) دون أن تحل محله.';

update public.roles set is_capability = true
where slug in ('committee-member','committee-chair','committee-secretary')
  and not is_capability;

-- =====================================================================
-- 2) current_is_hr_only() — HR بدون full-access
-- =====================================================================
create or replace function public.current_is_hr_only()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select not public.current_is_full_access()
    and public.current_has_active_role(array['hr-manager','hr-specialist']);
$$;

revoke execute on function public.current_is_hr_only() from public;
grant execute on function public.current_is_hr_only() to authenticated;

comment on function public.current_is_hr_only() is
  'V23: يعيد true إذا كان المستخدم HR فقط (بدون full-access). يُستخدم لتقييد منح الأدوار العليا.';

-- =====================================================================
-- 3) rpc_assign_role — V23: تقييد HR + تدقيق
-- =====================================================================
create or replace function public.rpc_assign_role(
  p_user_id uuid, p_role_id uuid, p_scope_override jsonb default null,
  p_effective_from timestamptz default now(), p_effective_to timestamptz default null
)
returns public.user_roles
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_row public.user_roles; v_role public.roles;
begin
  -- فحص التخويل الأساسي
  if not (public.current_is_full_access() or public.has_permission('access.role.assign')) then
    raise exception 'not authorized to assign roles' using errcode = '42501';
  end if;

  select * into v_role from public.roles where id = p_role_id;
  if v_role is null then
    raise exception 'role not found' using errcode = '42501';
  end if;

  -- منح full-access محصور بـsuper-admin فقط
  if v_role.is_full_access and not public.current_is_super_admin() then
    raise exception 'only super-admin may assign a full-access role' using errcode = '42501';
  end if;

  -- منع منح النفس دوراً أعلى
  if p_user_id = auth.uid() and v_role.is_full_access then
    raise exception 'cannot self-grant full access' using errcode = '42501';
  end if;

  -- V23: مستخدمو HR محدودون بأدوار الموظف/المدير/التشغيل فقط
  -- Main Admin وحده يمنح الأدوار العليا وعضوية اللجنة
  if public.current_is_hr_only() then
    if v_role.slug = any(array[
      'admin','super-admin','super_admin','system-admin','technical-lead',
      'executive-director','executive','executive-secretary',
      'hr-manager','hr-specialist',
      'committee-member','committee-chair','committee-secretary'
    ]) or v_role.is_full_access or v_role.is_system then
      raise exception 'HR may only assign employee, manager, or operations roles'
        using errcode = '42501';
    end if;
  end if;

  insert into public.user_roles (user_id, role_id, scope_override, effective_from, effective_to, granted_by)
  values (p_user_id, p_role_id, p_scope_override, p_effective_from, p_effective_to, auth.uid())
  on conflict (user_id, role_id) do update
    set scope_override = excluded.scope_override,
        effective_from = excluded.effective_from,
        effective_to   = excluded.effective_to,
        granted_by     = auth.uid()
  returning * into v_row;

  -- V23: تدقيق كل عملية إسناد دور
  perform public.log_audit_event(
    'access.role.assigned',
    'access',
    'notice',
    'user_roles',
    p_role_id,
    'تم إسناد دور «' || coalesce(v_role.name_ar, v_role.slug) || '»',
    'Role "' || v_role.slug || '" assigned',
    jsonb_build_object(
      'role_slug', v_role.slug,
      'role_id', p_role_id,
      'target_user_id', p_user_id,
      'is_capability', coalesce(v_role.is_capability, false)
    )
  );

  return v_row;
end;
$$;

-- =====================================================================
-- 4) rpc_revoke_role — V23: تدقيق
-- =====================================================================
create or replace function public.rpc_revoke_role(p_user_id uuid, p_role_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.remove')) then
    raise exception 'not authorized to revoke roles' using errcode = '42501';
  end if;

  select * into v_role from public.roles where id = p_role_id;

  delete from public.user_roles where user_id = p_user_id and role_id = p_role_id;

  -- V23: تدقيق كل عملية سحب دور
  if v_role.id is not null then
    perform public.log_audit_event(
      'access.role.revoked',
      'access',
      'notice',
      'user_roles',
      p_role_id,
      'تم سحب دور «' || coalesce(v_role.name_ar, v_role.slug) || '»',
      'Role "' || v_role.slug || '" revoked',
      jsonb_build_object(
        'role_slug', v_role.slug,
        'role_id', p_role_id,
        'target_user_id', p_user_id
      )
    );
  end if;
end;
$$;

-- =====================================================================
-- 5) Grants — الأصلية تبقى (نفس التوقيع)، إضافة current_is_hr_only
-- =====================================================================
-- rpc_assign_role و rpc_revoke_role يحتفظان بنفس التوقيع → الـgrants القائمة فعّالة.
-- current_is_hr_only() هي الدالة الجديدة الوحيدة.
