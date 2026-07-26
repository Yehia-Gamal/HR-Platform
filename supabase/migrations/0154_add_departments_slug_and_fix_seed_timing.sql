-- 0154: إضافة عمود slug لجدول الإدارات + إصلاح توقيت بذر الصلاحيات.
-- ============================================================================
-- خلفية:
--   1) Migration 0134 و 0136 تستخدم d.slug في resolve_request_approver
--      لكن جدول departments لا يحوي عمود slug — يسبب خطأ runtime.
--   2) Migration 0133 تمنح posts.publish لـ hr-specialist
--      لكن الدور لا يُنشأ حتى 0138 — المنح يفشل صامتاً.
-- ============================================================================

-- ── 1) إضافة عمود slug للإدارات ──

alter table public.departments add column if not exists slug text;

comment on column public.departments.slug is 'معرّف نصي فريد للإدارة — يُستخدم في توجيه الطلبات (operations%) وربط منطقي.';

-- فهرس فريد جزئي (slug فريد حيث ليس null)
create unique index if not exists idx_departments_slug_unique
  on public.departments (slug) where slug is not null;

-- ── 2) بذر slug للإدارات التشغيلية الموجودة ──

update public.departments set slug = 'operations-1' where code = 'OPS1' and slug is null;
update public.departments set slug = 'operations-2' where code = 'OPS2' and slug is null;
update public.departments set slug = 'hr' where code = 'HR' and slug is null;
update public.departments set slug = 'exec-sec' where code = 'EXEC_SEC' and slug is null;

-- ── 3) إصلاح توقيت بذر صلاحية posts.publish لـ hr-specialist ──
-- Migration 0133 حاولت المنح لكن الدور لم يكن موجوداً بعد (أُنشئ في 0138).

insert into public.role_permissions (role_id, permission_id, scope, requires_reason)
select r.id, p.id, 'organization', false
from public.roles r
join public.permissions p on p.code = 'posts.publish'
where r.slug = 'hr-specialist'
on conflict (role_id, permission_id, scope) do nothing;
