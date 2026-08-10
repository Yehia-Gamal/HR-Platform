-- ══════════════════════════════════════════════════════════════════════
-- 0368: تقييد kpi_diag_run على service_role فقط (P0 — تسريب تشخيصي)
--
-- المشكلة: public.kpi_diag_run هي SECURITY DEFINER ومنوحة لـ authenticated
--   (0288 و 0290). الدالة لا تحتوي أي فحص صلاحية داخلي، لذا يستطيع
--   أي موظف مسجّل استدعاؤها مباشرةً عبر PostgREST والحصول على:
--     • قائمة دوال KPI الموجودة في الـ schema (وحالة منحها)
--     • UUIDs القالب الرسمي والسياسة النشطة
--     • نصوص الخطأ الداخلية (SQL state + stack context) من الدوال الإدارية
--
--   التعليق في 0288 صريح: "The function is a self-contained diagnostic only;
--   nothing in app code calls it." — إذن لا حاجة لـ authenticated إطلاقاً.
--
-- الإصلاح: سحب EXECUTE من public و anon و authenticated؛ إبقاء service_role
--   فقط حتى تبقى الأداة متاحة للمطوّرين عبر Supabase dashboard / CI.
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

REVOKE ALL ON FUNCTION public.kpi_diag_run(date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.kpi_diag_run(date) TO service_role;

COMMIT;
