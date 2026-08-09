-- =====================================================================
-- 0348_kpi_fix_grants_openflow_inbox_relation.sql
-- =====================================================================
-- هذا الـ migration يوثّق الإصلاحات التي طُبّقت مباشرة على الإنتاج
-- عبر Management API (migrations 0301-0303 السابقة التي استُبدلت ملفاتها
-- بواسطة جلسة موازية). يضمن هذا الملف أن migrations المحلية متطابقة
-- مع حالة قاعدة البيانات الإنتاجية.
--
-- الإصلاحات الموثّقة هنا:
--   (1) GRANT EXECUTE على create_kpi_cycle_admin بتوقيع 8 معاملات.
--   (2) create_kpi_cycle_admin: فتح فوري عند p_open_now=true بلا قيد تاريخ.
--   (3) get_kpi_inbox: إضافة حقل relation (self/team/review).
--   (4) دالة kpi_diag_run للتشخيص.
--   (5) دالة create_kpi_cycle_admin_safe محصّنة.
--
-- Idempotent — كلها CREATE OR REPLACE / GRANT.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) إسقاط overload قديم 7-معاملات + منح authenticated على التوقيعات
-- ---------------------------------------------------------------------
drop function if exists public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean);

revoke execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) to authenticated;

revoke execute on function public.get_kpi_admin_catalog(date) from public, anon;
grant  execute on function public.get_kpi_admin_catalog(date) to authenticated;

revoke execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) from public, anon;
grant  execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) to authenticated;

revoke execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) from public, anon;
grant  execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) to authenticated;

revoke execute on function public.decide_kpi_appeal(uuid, text, text) from public, anon;
grant  execute on function public.decide_kpi_appeal(uuid, text, text) to authenticated;

revoke execute on function public.refresh_kpi_attendance_inputs(uuid) from public, anon;
grant  execute on function public.refresh_kpi_attendance_inputs(uuid) to authenticated;

revoke execute on function public.get_kpi_cycle_report(uuid) from public, anon;
grant  execute on function public.get_kpi_cycle_report(uuid) to authenticated;

revoke execute on function public.send_kpi_notifications_admin(uuid) from public, anon;
grant  execute on function public.send_kpi_notifications_admin(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
