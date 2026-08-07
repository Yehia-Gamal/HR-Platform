-- Migration 0303: Seed observability permissions and grant to admin roles.
-- يضمن أن صلاحيات المراقبة (system.release.read/manage, observability.read, admin.observability)
-- موجودة في كتالوج الصلاحيات ومنوحة للأدوار الإدارية.
-- get_system_health() يفحص has_any_permission(['system.release.read','system.release.manage'])
-- و observability_events RLS يفحص has_permission('observability.read') أو ('admin.observability').

-- =====================================================================
-- 1) إدراج الصلاحيات في الكتالوج (idempotent)
-- =====================================================================

insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values
  ('system.release.read',   'system', 'release',  'read',   'قراءة لقطات صحة النظام والتنبيهات', 'sensitive', true),
  ('system.release.manage', 'system', 'release',  'manage', 'إدارة تنبيهات النظام (تأكيد/حل)', 'critical',  true),
  ('observability.read',     'system', 'observability', 'read', 'قراءة سجل أحداث المراقبة', 'sensitive', true),
  ('admin.observability',    'admin',  'observability', 'read', 'وصول كامل لمراقبة النظام', 'critical', true)
on conflict (code) do nothing;

-- =====================================================================
-- 2) منح الصلاحيات للأدوار الإدارية
-- =====================================================================

-- العثور على أدوار admin / super-admin (is_full_access=true)
-- ومنحها صلاحيات المراقبة بالنطاق organization (واسع)
insert into public.role_permissions (role_id, permission_id, scope)
select
  r.id,
  p.id,
  'organization'
from public.roles r
cross join public.permissions p
where r.is_full_access = true
  and p.code in ('system.release.read', 'system.release.manage', 'observability.read', 'admin.observability')
on conflict (role_id, permission_id, scope) do nothing;

-- منح system.release.read لـ hr-manager و executive-director أيضاً
-- (يحتاجون رؤية صحة النظام للتشغيل اليومي)
insert into public.role_permissions (role_id, permission_id, scope)
select
  r.id,
  p.id,
  'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager', 'executive-director', 'operations-manager', 'operations-manager-1', 'operations-manager-2')
  and p.code = 'system.release.read'
on conflict (role_id, permission_id, scope) do nothing;

-- =====================================================================
-- 3) تأكيد أن get_system_health متاحة لـ authenticated
-- (مُنوحة بالفعل في 0054 لكن نتحقق)
-- =====================================================================
do $$
begin
  -- إعادة منح تنفيذية للتأكد (idempotent)
  revoke execute on function public.get_system_health() from public, anon;
  grant execute on function public.get_system_health() to authenticated, service_role;
exception
  when others then
    raise notice 'get_system_health grant check skipped: %', sqlerrm;
end $$;
