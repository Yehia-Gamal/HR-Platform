-- =====================================================================
-- 0336: إصلاح is_full_access لدور executive-secretary
-- ---------------------------------------------------------------------
-- Migration 0058 رفعت executive-secretary إلى is_full_access=true،
-- لكن هذا الـ UPDATE نفّذ قبل إنشاء الدور (يُنشأ لاحقاً في 0121
-- بقيمة false عبر ON CONFLICT DO NOTHING) — فبقي false بالخطأ.
-- الاختبارات 0035/0096 (والاختبارات القائمة على full-access) كانت
-- تفشل. هذا الإصلاح يعيد القصد الأصلي: السكرتير التنفيذي هو الأدمن
-- الرئيسي للجمعية بصلاحية كاملة.
-- =====================================================================

update public.roles
   set is_full_access = true,
       description = 'السكرتير التنفيذي — الأدمن الرئيسي للنظام بصلاحية كاملة (إصلاح 0336)',
       updated_at = now()
 where slug = 'executive-secretary'
   and is_full_access = false;

-- إعادة منح صلاحيات المراقبة للأدوار ذات الصلاحية الكاملة
-- (نفس منطق 0327 — السكرتير التنفيذي يدخل المجموعة الآن).
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
cross join public.permissions p
where r.slug = 'executive-secretary'
  and p.code in ('system.release.read', 'system.release.manage', 'observability.read', 'admin.observability')
on conflict (role_id, permission_id, scope) do nothing;
