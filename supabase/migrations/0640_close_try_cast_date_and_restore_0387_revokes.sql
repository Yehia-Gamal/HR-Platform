-- ============================================================================
-- 0640: إغلاق try_cast_date عن PUBLIC/anon/authenticated + إعادة سحب ما أعادته
--        0503/0505 من عقدي 0387
-- ============================================================================
-- 1) try_cast_date(text) أنشئت في 0586 بـ ACL افتراضي (PUBLIC execute) وأُضيف لها
--    grant لـ authenticated — ما يخالف عقدين منشورين:
--      - 0551 اختبار 9: أي دالة في public متاحة لـ PUBLIC عدا الاستثناءات الثلاثة.
--      - 0552 اختبار 17: لا دالة قابلة للتنفيذ من anon خارج الاستثناءات.
--    0637 وثّقتها كاستثناء «دالة بسيطة تُستدعى من دوال أخرى»، لكن الاستثناء لم
--    يُسجَّل في هذين الاختبارين. جميع المستدعين (7 دوال) SECURITY DEFINER
--    (validate/اللوحات/العيادات) → التنفيذ بصلاحية المالك ولا يحتاج أي grant.
--    إغلاقها آمن: دالة مساعدة تحويل نص→تاريخ بلا أي وصول لبيانات.
--
-- 2) 0387 سحبت EXECUTE من authenticated على apply_leave_ledger_entry
--    وresolve_request_approver، لكن 0503 (سطر 334) و0505 (سطر 161) أعاداها.
--    كل المستدعين الداخليين SECURITY DEFINER (submit_my_request /
--    resubmit_my_request / _submit_request_for / المحفّزات / adjust_leave_balance
--    / grant_weekly_rest_credit...) → لا أحد يحتاج grant لـ authenticated.
--    لا استدعاء مباشر من تطبيق الويب أو الموبايل (grep صفر).
--    نبقي service_role كما هو (0387 اختبار 2 + استخدامات Edge).

begin;

-- ─── 1) try_cast_date — إغلاق النافذة ──────────────────────────────────────
revoke execute on function public.try_cast_date(text)
  from public, anon, authenticated;

-- ─── 2) عودة عقد 0387 ──────────────────────────────────────────────────────
revoke execute on function public.apply_leave_ledger_entry(
  uuid, uuid, integer, text, numeric, text, uuid, text, jsonb
) from authenticated;

revoke execute on function public.resolve_request_approver(uuid, date)
  from authenticated;

-- ─── 3) generate_punch_reminders — عقد 0552 (اختبار 1) يدرجها ضمن 58 دالة
--        خادمية (cron فقط). 0568 أعادت grant لـ authenticated دون استهلاك في
--        الويب/الموبايل (grep صفر)؛ بوابة 0585 الداخلية تكفي لمن يملك
--        comms.notification.send لاحقاً — يُعاد الـ grant عند الحاجة مع تحديث الاختبار.
revoke execute on function public.generate_punch_reminders(integer)
  from authenticated;

commit;

comment on function public.try_cast_date(text) is
  '0640: مساعدة تحويل نص→تاريخ — مغلقة على public/anon/authenticated (0551#9، 0552#17)؛ مستدعياتها كلها definer.';
