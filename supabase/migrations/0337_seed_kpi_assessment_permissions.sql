-- =====================================================================
-- 0337: إنشاء صلاحيتي تقييم الأداء المفقودتين وربطهما بالأدوار
-- ---------------------------------------------------------------------
-- لا يوجد أي migration سابق يُنشئ سطري الصلاحية:
--   performance.kpi.self_assess   (تقييم ذاتي)
--   performance.kpi.manager_assess (تقييم المدير)
-- كانتا موجودتين فقط في seed التطوير (supabase/seed/0001)، لذا فإن
-- منحهما في 0121 و0160 كان silent no-op (الشرط if v_perm_id is null)
-- فتبقى أدوار employee وdirect-manager بلا صلاحيات KPI الأساسية،
-- وكان اختبار 0036 يفشل بـ FORBIDDEN عند مرحلة المدير.
-- =====================================================================

begin;

-- 1) إنشاء الصلاحيتين إن لم تكونا موجودتين (idempotent)
insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
 ('performance.kpi.self_assess','performance','kpi_self_assessment','assess','تقييم الموظف الذاتي لأدائه','sensitive',true),
 ('performance.kpi.manager_assess','performance','kpi_manager_assessment','assess','تقييم المدير المباشر لأداء مرؤوسه','sensitive',true)
on conflict(code) do update set
 module=excluded.module,resource=excluded.resource,action=excluded.action,
 description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive,
 updated_at=now();

-- 2) منح التقييم الذاتي لدور الموظف (نطاق self — نفس قصد 0160)
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'self'
from public.roles r
cross join public.permissions p
where r.slug = 'employee'
  and p.code = 'performance.kpi.self_assess'
on conflict (role_id, permission_id, scope) do nothing;

-- 3) منح تقييم المدير للمدير المباشر (نطاق direct_reports — نفس قصد 0121)
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'direct_reports'
from public.roles r
cross join public.permissions p
where r.slug = 'direct-manager'
  and p.code = 'performance.kpi.manager_assess'
on conflict (role_id, permission_id, scope) do nothing;

-- 4) منح تقييم المدير لمدير القسم (نطاق department — مطابق لـ seed 0001)
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'department'
from public.roles r
cross join public.permissions p
where r.slug = 'department-manager'
  and p.code = 'performance.kpi.manager_assess'
on conflict (role_id, permission_id, scope) do nothing;

commit;
