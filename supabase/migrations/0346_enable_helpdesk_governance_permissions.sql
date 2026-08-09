-- ============================================================================
-- 0346 — تفعيل صلاحيات مكتب الخدمات والحوكمة للأدوار التشغيلية
-- ============================================================================
-- الفجوة: صلاحيات tickets.read / tickets.write مربوطة بدور employee فقط
-- (نطاق self من seed التطوير) و risks.read/risks.write مربوطة بـ operations-manager
-- فقط — فلا يملك hr-manager/executive-secretary صلاحية رؤية كل التذاكر ولا
-- إدارة سجل المخاطر رغم أن صفحات مكتب الخدمات والحوكمة تتطلب ذلك.
--
-- الحل: منح أدوار الإدارة صلاحيات المؤسسة:
--   • hr-manager, hr-specialist, executive-secretary, admin → tickets.read (organization)
--   • hr-manager, executive-secretary, admin → tickets.write (organization)
--   • hr-manager, executive-secretary, operations-manager, admin → risks.read (organization)
--   • hr-manager, executive-secretary, admin → risks.write (organization)
--   • governance.data.manage → hr-manager, executive-secretary (organization)
-- جميعها idempotent عبر on conflict (role_id, permission_id, scope) do nothing.
-- ============================================================================

begin;

-- 1) tickets.read — مؤسسة
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager','hr-specialist','executive-secretary','admin')
  and p.code = 'tickets.read'
on conflict (role_id, permission_id, scope) do nothing;

-- 2) tickets.write — مؤسسة
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager','executive-secretary','admin')
  and p.code = 'tickets.write'
on conflict (role_id, permission_id, scope) do nothing;

-- 3) risks.read — مؤسسة
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager','executive-secretary','operations-manager','admin')
  and p.code = 'risks.read'
on conflict (role_id, permission_id, scope) do nothing;

-- 4) risks.write — مؤسسة
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager','executive-secretary','admin')
  and p.code = 'risks.write'
on conflict (role_id, permission_id, scope) do nothing;

-- 5) governance.data.manage — مؤسسة
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug in ('hr-manager','executive-secretary','admin')
  and p.code = 'governance.data.manage'
on conflict (role_id, permission_id, scope) do nothing;

notify pgrst, 'reload schema';

commit;
