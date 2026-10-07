-- ═══════════════════════════════════════════════════════════════
-- 0659: التقييم الذاتي لكل من له تقييم شهري — لا لدور «موظف» وحده
--
-- performance.kpi.self_assess مُنح لدور employee فقط (0160 / 0337). من يحمل
-- دورًا إداريًا وحده (direct-manager / department-manager / clinics-manager /
-- hr-specialist / operations-* / executive…) تُنشأ له تقييمات شهرية تبدأ من
-- مرحلة «ذاتي»، لكن:
--   • التطبيق يخفي زر «بدء التقييم الذاتي» (يشترط الصلاحية)،
--   • و advance_kpi_stage(…, 'self') يرفض الإرسال بـ FORBIDDEN (0483).
-- فيبقى التقييم «متأخرًا عن الموعد» بلا مخرج ولا يصل إلى مرحلة المدير.
-- ظهر في بيانات الإنتاج لمدير مباشر بدور direct-manager وحده (2026-10-07).
--
-- آمن: النطاق 'self'، و advance_kpi_stage يتحقق أن التقييم يخص صاحبه
-- (employee_id = current_employee_id()) — فالمنح لا يتيح تقييم أي شخص آخر.
-- الأدوار ذات الوصول الكامل لا تحتاجه، وأدوار اللجنة (committee-*) إضافية
-- فوق دور أساسي لحاملها.
-- ═══════════════════════════════════════════════════════════════

begin;

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'self'
  from public.roles r
  join public.permissions p on p.code = 'performance.kpi.self_assess'
 where not coalesce(r.is_full_access, false)
   and r.slug not like 'committee-%'
on conflict (role_id, permission_id, scope) do nothing;

commit;
