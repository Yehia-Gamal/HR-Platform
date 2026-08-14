-- 0422: حذف النموذج القديم submit_my_request(text,text,text,jsonb) نهائياً
-- ══════════════════════════════════════════════════════════════════════
-- السبب الجذري لخطأ "لا يسجل طلب الإجازة/المأمورية": النموذج القديم
--   submit_my_request(text, text, text, jsonb)
-- ما زال موجوداً في قاعدة البيانات البعيدة رغم أن 0400 حذفه (أُعيد إنشاؤه
-- خارج ملفات migrations، بمصدر CRLF). ووجود النموذجين معاً يجعل أي استدعاء
-- بمعاملات 4 يطابق كلا النموذجين فيرفض Postgres بـ:
--   function public.submit_my_request(text, text, text, jsonb) is not unique
-- النموذج الحديث (0401) ذو الخمس معاملات يقبل المكالمات القديمة بفضل
-- DEFAULT '{}' على p_payload و DEFAULT null على p_idempotency_key، لذا
-- الحذف يعيد التوافق التام بلا أي تغيير سلوكي (نفس منطق 0400).

begin;

drop function if exists public.submit_my_request(text, text, text, jsonb);

commit;
