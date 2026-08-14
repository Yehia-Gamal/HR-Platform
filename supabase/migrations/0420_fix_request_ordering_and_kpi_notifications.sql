-- 0420: إصلاح ترتيب الإجراءات (أحدث أولاً) في الموبايل + تصحيح إشعارات KPI
-- ══════════════════════════════════════════════════════════════════════
-- 1. ترتيب الطلبات/الإجازات في الموبايل: الآن الأحدث أولاً (DESC) في كل صفحات.
-- 2. ملاحظة KPI: الدالة الأصلية generate_kpi_cycle_notifications(p_at timestamptz)
--    في 0058/0111 ترسل بالفعل إشعاراً منفصلاً لكل موظف (loop over kpi_evaluations
--    مع kpi_notification_receipts للتكرار) — لا يوجد "بث جماعي" لإصلاحه.
--
-- كانت نسخة سابقة من هذا الملف تضيف overload جديدة generate_kpi_cycle_notifications(p_cycle_id uuid)
-- بمراجع أعمدة غير موجودة (kpi_cycles.title, kpi_evaluations.status/rating,
-- kpi_cycles.closed_at) — ما كان سيكسر التطبيق عند أول استدعاء، ويجعل استدعاءات
-- الحرف الواحد غامضة (42725). لا يوجد أي مستدعي لهذا التوقيع، لذا نُزيله نهائياً
-- ونبقي التوقيع الرسمي (p_at timestamptz) كما هو.

begin;

drop function if exists public.generate_kpi_cycle_notifications(uuid);

commit;
