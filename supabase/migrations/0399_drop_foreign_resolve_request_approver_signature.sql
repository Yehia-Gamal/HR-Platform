-- migration: 0399
-- description: إزالة توقيع resolve_request_approver(integer,text) الأجنبي (0385) — معطوب في مخططنا وغير مستخدم
--
-- تنسيق تعارض التواقيع مع 0385:
-- - 0354 (وما قبلها) تعرّف نسخة النظام الحقيقية: resolve_request_approver(uuid,date) → uuid.
--   يستدعيها كل كود النظام (0061, 0134, 0318, 0325, 0333, 0355, 0362) واختبارات (0038, 0056, 0354).
-- - 0385 أنشأت توقيعاً ثانياً (integer,text) → integer مكتوباً على مخطط آخر:
--   employees.id من نوع integer، وجدول employee_roles غير موجود، وpermissions.slug بدل code.
--   لا يستدعيه أي كود في المستودع، ووجوده يسبب غموضاً في استدعاءات الـ literals النصية
--   (اختبار 0354 كان يحتاج كاستات صريحة ::uuid, ::date).
-- الحل المنسَّق: حذف التوقيع الأجنبي عبر 0399 (بعد 0387 التي أدارت صلاحياته لحظة وجوده).
-- أي بناء نظيف يطبق: 0385 (إنشاء) → 0387 (REVOKE/GRANT) → 0399 (حذف) بترتيب عددي سليم.

begin;

drop function if exists public.resolve_request_approver(integer, text);

-- نسخة النظام (uuid,date) تبقى سليمة
do $$
begin
  if to_regprocedure('public.resolve_request_approver(uuid,date)') is null then
    raise exception 'resolve_request_approver(uuid, date) مفقودة بعد الحذف';
  end if;
end $$;

commit;
