-- Migration 0002: Permissions, Roles & authorization functions
-- المصدر الوحيد لدوال التخويل. كل migration لاحقة تستخدم هذه الدوال ولا تعيد تعريفها.

-- =========================================================
-- 1) جداول الصلاحيات والأدوار (RBAC + ABAC)
-- =========================================================

-- كتالوج الصلاحيات: module.resource.action
create table if not exists public.permissions (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,            -- e.g. people.employee.read
  module       text not null,                   -- people, attendance, payroll ...
  resource     text not null,
  action       text not null,
  description  text,
  risk_level   text not null default 'normal' check (risk_level in ('normal','sensitive','critical')),
  is_sensitive boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz
);
comment on table public.permissions is 'كتالوج الصلاحيات المركزي بصيغة module.resource.action.';

-- الأدوار (Role Templates قابلة للنسخ)
create table if not exists public.roles (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,            -- admin, hr-manager, employee ...
  name_ar      text not null,
  name_en      text,
  description  text,
  color        text,
  icon         text,
  is_system    boolean not null default false,  -- أدوار محمية لا تُحذف
  is_full_access boolean not null default false,-- true فقط لـ admin/super-admin
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  created_by   uuid references auth.users(id)
);
comment on table public.roles is 'قوالب الأدوار. is_full_access=true حصراً لـ admin/super-admin.';

-- ربط الأدوار بالصلاحيات + النطاق (ABAC)
create table if not exists public.role_permissions (
  id             uuid primary key default gen_random_uuid(),
  role_id        uuid not null references public.roles(id) on delete cascade,
  permission_id  uuid not null references public.permissions(id) on delete cascade,
  scope          text not null default 'self'
                 check (scope in ('self','direct_reports','management_descendants',
                        'selected_employees','team','department','selected_departments',
                        'branch','selected_branches','organization','assigned_cases',
                        'workflow_inbox','records_created_by_user','archive_readonly')),
  requires_mfa   boolean not null default false,
  requires_reason boolean not null default false,
  effective_from timestamptz,
  effective_to   timestamptz,
  created_at     timestamptz not null default now(),
  unique (role_id, permission_id, scope)
);
comment on table public.role_permissions is 'صلاحيات كل دور مع النطاق وقيود MFA/السبب وتاريخ السريان.';

-- إسناد الأدوار للمستخدمين (متعدد الأدوار)
create table if not exists public.user_roles (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  role_id        uuid not null references public.roles(id) on delete cascade,
  scope_override jsonb,                          -- إدارات/فروع/موظفون محددون
  effective_from timestamptz not null default now(),
  effective_to   timestamptz,
  granted_by     uuid references auth.users(id),
  created_at     timestamptz not null default now(),
  unique (user_id, role_id)
);
comment on table public.user_roles is 'إسناد الأدوار للمستخدمين مع تجاوز نطاق وتاريخ سريان.';

create index if not exists idx_user_roles_user on public.user_roles(user_id);
create index if not exists idx_role_permissions_role on public.role_permissions(role_id);

-- =========================================================
-- 2) دوال التخويل (SECURITY DEFINER, stable)
-- =========================================================

-- الأدوار الفعّالة للمستخدم الحالي
create or replace function public.current_role_ids()
returns uuid[]
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(array_agg(ur.role_id), '{}')
  from public.user_roles ur
  where ur.user_id = auth.uid()
    and (ur.effective_from is null or ur.effective_from <= now())
    and (ur.effective_to   is null or ur.effective_to   >  now());
$$;

-- هل المستخدم full-access؟ (admin/super-admin فقط — HR/التنفيذي ليسا full-access)
create or replace function public.current_is_full_access()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.roles r
    where r.id = any (public.current_role_ids())
      and r.is_full_access = true
  );
$$;

-- هل يملك المستخدم صلاحية معينة (بأي نطاق فعّال)؟
create or replace function public.has_permission(p_code text)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.current_is_full_access() or exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id = rp.permission_id
    where rp.role_id = any (public.current_role_ids())
      and p.code = p_code
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
  );
$$;

-- هل يملك أياً من مجموعة صلاحيات؟
create or replace function public.has_any_permission(p_codes text[])
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.current_is_full_access() or exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id = rp.permission_id
    where rp.role_id = any (public.current_role_ids())
      and p.code = any (p_codes)
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
  );
$$;

-- معرّف الموظف المرتبط بالمستخدم الحالي.
-- نسخة مؤقتة آمنة: جدول profiles لا يُنشأ إلا في 0004، لذا نتعامل مع غيابه بإرجاع NULL
-- بدل فشل هذه الـmigration. تُستبدَل بالتنفيذ الحقيقي في نهاية 0004.
create or replace function public.current_employee_id()
returns uuid
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_emp uuid;
begin
  begin
    select p.employee_id into v_emp from public.profiles p where p.id = auth.uid();
  exception when undefined_table then
    return null;
  end;
  return v_emp;
end;
$$;

-- هل يستطيع المستخدم الوصول لموظف معيّن؟ (ذات/مدير مباشر/full-access)
-- ملاحظة: تُكمَّل منطقياً في 0004 بعد إنشاء employees/manager_relations؛ هنا نسخة آمنة افتراضية.
create or replace function public.can_access_employee(p_employee_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_me uuid;
begin
  if public.current_is_full_access() then return true; end if;
  begin v_me := public.current_employee_id(); exception when others then v_me := null; end;
  if v_me is not null and v_me = p_employee_id then return true; end if;
  -- علاقة مدير مباشر (إن وُجد الجدول)
  begin
    if exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = p_employee_id
        and mr.manager_employee_id = v_me
        and (mr.effective_to is null or mr.effective_to > now())
    ) then return true; end if;
  exception when undefined_table then null;
  end;
  return false;
end;
$$;

-- =========================================================
-- 3) RLS على جداول الصلاحيات
-- =========================================================
alter table public.permissions      enable row level security;
alter table public.roles            enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles        enable row level security;

-- قراءة الكتالوج والأدوار لأي مستخدم مصادَق (للعرض)؛ الكتابة full-access أو access.role.*
-- القراءة للعرض متاحة للمصادَقين؛ الكتابة ممنوعة مباشرةً على كل جداول الأدوار.
-- تُدار الأدوار والإسناد حصراً عبر RPCs الآمنة أدناه (منع تصعيد الصلاحيات).
create policy permissions_read on public.permissions for select to authenticated using (true);
-- لا سياسة كتابة على permissions: الكتالوج يُبذَر عبر seed/service_role فقط.

create policy roles_read on public.roles for select to authenticated using (true);
-- لا سياسة كتابة على roles: عبر rpc_upsert_role فقط.

create policy role_perms_read on public.role_permissions for select to authenticated using (true);
-- لا سياسة كتابة على role_permissions: عبر rpc_set_role_permissions فقط.

-- إسناد الأدوار: يقرأ المستخدم إسناده، والمخوّل يقرأ الكل. لا كتابة مباشرة — عبر rpc_assign_role فقط.
create policy user_roles_read on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.has_permission('access.role.assign'));

-- =========================================================
-- 4b) RPCs آمنة لإدارة الأدوار (تمنع التصعيد وحماية الأدوار النظامية)
-- =========================================================

-- هل المستخدم الحالي super-admin؟ (منح full-access محصور به)
create or replace function public.current_is_super_admin()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.roles r
    where r.id = any (public.current_role_ids())
      and r.slug in ('admin','super-admin','super_admin')
      and r.is_full_access = true
  );
$$;

-- إنشاء/تعديل دور. is_full_access/is_system لا يُضبطان إلا من super-admin.
create or replace function public.rpc_upsert_role(
  p_id uuid, p_slug text, p_name_ar text, p_name_en text,
  p_description text, p_color text, p_icon text,
  p_is_full_access boolean default false
)
returns public.roles
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_row public.roles; v_existing public.roles;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['access.role.create','access.role.update'])) then
    raise exception 'not authorized to manage roles' using errcode = '42501';
  end if;

  -- منح full-access محصور بـsuper-admin فقط
  if p_is_full_access and not public.current_is_super_admin() then
    raise exception 'only super-admin may grant full access' using errcode = '42501';
  end if;

  if p_id is not null then
    select * into v_existing from public.roles where id = p_id;
    -- منع تعديل الأدوار النظامية من غير super-admin
    if v_existing.is_system and not public.current_is_super_admin() then
      raise exception 'system roles are protected' using errcode = '42501';
    end if;
    update public.roles set
      slug = coalesce(p_slug, slug),
      name_ar = coalesce(p_name_ar, name_ar),
      name_en = p_name_en,
      description = p_description,
      color = p_color, icon = p_icon,
      -- is_full_access يتغيّر فقط بواسطة super-admin؛ خلاف ذلك يبقى كما هو
      is_full_access = case when public.current_is_super_admin() then p_is_full_access else is_full_access end,
      updated_at = now()
    where id = p_id returning * into v_row;
  else
    insert into public.roles (slug, name_ar, name_en, description, color, icon, is_system, is_full_access, created_by)
    values (p_slug, p_name_ar, p_name_en, p_description, p_color, p_icon, false,
            case when public.current_is_super_admin() then p_is_full_access else false end, auth.uid())
    returning * into v_row;
  end if;
  return v_row;
end;
$$;

-- ضبط صلاحيات دور (استبدال كامل). لا يُسمح لغير super-admin بلمس دور نظامي/full-access.
create or replace function public.rpc_set_role_permissions(p_role_id uuid, p_items jsonb)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_role public.roles; v_count int := 0; v_item jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.update')) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  select * into v_role from public.roles where id = p_role_id;
  if v_role.is_system and not public.current_is_super_admin() then
    raise exception 'system roles are protected' using errcode = '42501';
  end if;
  delete from public.role_permissions where role_id = p_role_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.role_permissions (role_id, permission_id, scope, requires_mfa, requires_reason)
    values (p_role_id,
            (v_item->>'permission_id')::uuid,
            coalesce(v_item->>'scope','self'),
            coalesce((v_item->>'requires_mfa')::boolean,false),
            coalesce((v_item->>'requires_reason')::boolean,false));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- إسناد/سحب دور لمستخدم. إسناد دور full-access محصور بـsuper-admin ومنع منح النفس.
create or replace function public.rpc_assign_role(
  p_user_id uuid, p_role_id uuid, p_scope_override jsonb default null,
  p_effective_from timestamptz default now(), p_effective_to timestamptz default null
)
returns public.user_roles
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_row public.user_roles; v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.assign')) then
    raise exception 'not authorized to assign roles' using errcode = '42501';
  end if;
  select * into v_role from public.roles where id = p_role_id;
  if v_role.is_full_access and not public.current_is_super_admin() then
    raise exception 'only super-admin may assign a full-access role' using errcode = '42501';
  end if;
  -- منع منح النفس دوراً أعلى (super-admin يُدار خارج التطبيق/seed)
  if p_user_id = auth.uid() and v_role.is_full_access then
    raise exception 'cannot self-grant full access' using errcode = '42501';
  end if;
  insert into public.user_roles (user_id, role_id, scope_override, effective_from, effective_to, granted_by)
  values (p_user_id, p_role_id, p_scope_override, p_effective_from, p_effective_to, auth.uid())
  on conflict (user_id, role_id) do update
    set scope_override = excluded.scope_override,
        effective_from = excluded.effective_from,
        effective_to   = excluded.effective_to,
        granted_by     = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.rpc_revoke_role(p_user_id uuid, p_role_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.remove')) then
    raise exception 'not authorized to revoke roles' using errcode = '42501';
  end if;
  delete from public.user_roles where user_id = p_user_id and role_id = p_role_id;
end;
$$;

-- =========================================================
-- 4) grants على الدوال (revoke من public ثم grant للمصادَقين)
-- =========================================================
revoke execute on function public.current_role_ids()       from public;
revoke execute on function public.current_is_full_access()  from public;
revoke execute on function public.current_is_super_admin()  from public;
revoke execute on function public.has_permission(text)      from public;
revoke execute on function public.has_any_permission(text[])from public;
revoke execute on function public.current_employee_id()     from public;
revoke execute on function public.can_access_employee(uuid) from public;

grant execute on function public.current_role_ids()        to authenticated;
grant execute on function public.current_is_full_access()   to authenticated;
grant execute on function public.current_is_super_admin()   to authenticated;
grant execute on function public.has_permission(text)       to authenticated;
grant execute on function public.has_any_permission(text[]) to authenticated;
grant execute on function public.current_employee_id()      to authenticated;
grant execute on function public.can_access_employee(uuid)  to authenticated;

-- RPCs إدارة الأدوار
revoke execute on function public.rpc_upsert_role(uuid,text,text,text,text,text,text,boolean) from public;
revoke execute on function public.rpc_set_role_permissions(uuid,jsonb) from public;
revoke execute on function public.rpc_assign_role(uuid,uuid,jsonb,timestamptz,timestamptz) from public;
revoke execute on function public.rpc_revoke_role(uuid,uuid) from public;
grant execute on function public.rpc_upsert_role(uuid,text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.rpc_set_role_permissions(uuid,jsonb) to authenticated;
grant execute on function public.rpc_assign_role(uuid,uuid,jsonb,timestamptz,timestamptz) to authenticated;
grant execute on function public.rpc_revoke_role(uuid,uuid) to authenticated;

-- =========================================================
-- 5) بذرة أدنى: دور admin (full-access) + employee
-- =========================================================
insert into public.roles (slug, name_ar, name_en, is_system, is_full_access)
values ('admin','مدير النظام','System Admin', true, true)
on conflict (slug) do nothing;

insert into public.roles (slug, name_ar, name_en, is_system, is_full_access)
values ('employee','موظف','Employee', true, false)
on conflict (slug) do nothing;
-- باقي القوالب (hr-manager, direct-manager, executive, executive-secretary,
-- department-manager, operations-manager, committee-member/chair, payroll-officer)
-- تُبذَر في seed/ مع صلاحياتها ونطاقاتها.
