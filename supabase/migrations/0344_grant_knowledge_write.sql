-- Migration 0344: Grant knowledge.write to administrative roles
-- ================================================================================
-- المشكلة: ميزة قاعدة المعرفة (Knowledge) لها RLS تستخدم has_permission('knowledge.write')
-- لكن الصلاحية لا تُمنح لأي دور — فالأدوار الإدارية (hr-manager، system-admin)
-- تستطيع القراءة (منشور) لكن لا تستطيع إنشاء/تعديل/حذف المقالات.
-- أدوار full-access (admin، executive-secretary) تعمل عبر current_is_full_access()
-- ويحصلون على '*' في get_my_access_context، فلا يحتاجون منحاً صريحاً.
--
-- الإصلاح: منح knowledge.write للأدوار الإدارية بالنطاق organization.

BEGIN;

insert into public.role_permissions (role_id, permission_id, scope)
select
  r.id,
  p.id,
  'organization'
from public.roles r
cross join public.permissions p
where p.code = 'knowledge.write'
  and r.slug in ('hr-manager', 'system-admin', 'hr-specialist', 'executive-director')
on conflict (role_id, permission_id, scope) do nothing;

-- إضافة knowledge.write إلى كتالوج الصلاحيات لو لم تكن موجودة (idempotent)
-- (تُضاف أصلاً في seed/0002 لكن نضمن وجودها في أي قاعدة أُُنشئت دون seed)
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values ('knowledge.write', 'knowledge', 'write', 'write', 'إنشاء وتحرير وحذف مقالات قاعدة المعرفة', 'normal', false)
on conflict (code) do nothing;

NOTIFY pgrst, 'Reload schema';

COMMIT;
