-- 0157: إصلاح توقيت بذر الصلاحيات — إنشاء + منح الصلاحيات المفقودة.
-- ============================================================================
-- خلفية:
--   Migration 0138 تحاول منح performance.kpi.read و performance.kpi.hr_review
--   لـ hr-specialist، لكنها تفشل صامتاً لأن هذه الصلاحيات لم تُنشأ بعد
--   (موجودة فقط في seed). كذلك performance.cycle.manage يجب أن تُمنح
--   لـ executive-secretary لكنها غير مُنشأة وقت تشغيل 0138.
-- ============================================================================

-- ── 1) إنشاء الصلاحيات المفقودة (موجودة في seed فقط) ──

insert into public.permissions (code, module, resource, action)
values
  ('performance.kpi.read',       'performance', 'kpi',   'read'),
  ('performance.kpi.hr_review',  'performance', 'kpi',   'hr_review'),
  ('performance.cycle.manage',   'performance', 'cycle', 'manage')
on conflict (code) do nothing;

-- ── 2) منح performance.kpi.read + performance.kpi.hr_review لـ hr-specialist ──
--    (0138 حاولت لكن تخطّت لعدم وجود الصلاحيات)

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
join public.permissions p on p.code = 'performance.kpi.read'
where r.slug = 'hr-specialist'
on conflict (role_id, permission_id, scope) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
join public.permissions p on p.code = 'performance.kpi.hr_review'
where r.slug = 'hr-specialist'
on conflict (role_id, permission_id, scope) do nothing;

-- ── 3) منح performance.cycle.manage لـ executive-secretary ──
--    إدارة دورات الأداء مسؤولية السكرتير التنفيذي.

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
from public.roles r
join public.permissions p on p.code = 'performance.cycle.manage'
where r.slug = 'executive-secretary'
on conflict (role_id, permission_id, scope) do nothing;
