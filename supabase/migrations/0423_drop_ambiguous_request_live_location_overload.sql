-- 0423: إزالة overload الغامض request_live_location(uuid,text,text,text)
-- ══════════════════════════════════════════════════════════════════════
-- نسخة 0417 المطبقة على remote أضافت overload رابعاً (p_purpose) فوق
-- التوقيع الثلاثي request_live_location(uuid,text,text) — والنص الموجود
-- محلياً (0417 المعدَّل M) يحذفه لكنه لم يُدفع بعد. الـ overload الرباعي
-- بمعاملات DEFAULT يجعل كل استدعاء بثلاث معاملات (ما يرسله الموبايل:
-- p_employee_id, p_mode, p_reason) يطابق كلا النموذجين فيرفض Postgres بـ:
--   function public.request_live_location(uuid, unknown, unknown) is not unique
-- نفس نمط خطأ submit_my_request الذي أصلحه 0422.
-- الحذف يعيد التوقيع الثلاثي الوحيد (نفس توقيع 0338) بلا تغيير سلوكي.

begin;

drop function if exists public.request_live_location(uuid, text, text, text);

commit;