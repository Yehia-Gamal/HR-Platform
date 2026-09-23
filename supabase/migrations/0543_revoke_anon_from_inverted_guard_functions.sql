-- ═══════════════════════════════════════════════════════════════
-- 0543: تحصين الدوال ذات «الحارس المقلوب» بسحب anon/public صراحةً
--
-- الخلفية (تكملة 0542):
--   11 دالة SECURITY DEFINER تحمل النمط:
--       if auth.uid() is not null and not ( ...فحوص الصلاحية... ) then
--         raise exception 'غير مسموح';
--       end if;
--   عند غياب الجلسة يقصُر التقييم قبل فحوص الصلاحية فلا يُرفع استثناء.
--
-- وهذا **مقصود** هنا: أربع منها مجدولة عبر pg_cron وتعمل بلا auth.uid()
--   • auto_notify_late_attendance          (0405: يوميًا 09:30 القاهرة)
--   • generate_weekly_executive_summary    (0406: كل أحد 08:00)
--   • auto_escalate_instant_penalties      (0511: '0 5 * * *')
--   • auto_generate_instant_penalties      (0511: '*/30 8-11 * * *')
-- فلو رفضنا «غياب الجلسة» لتوقفت هذه المهام. لذلك لا نمسّ منطق الحارس.
--
-- ولا يمكن التمييز داخل الدالة بين anon و service_role:
--   `current_user` داخل SECURITY DEFINER يساوي **مالك الدالة** لا المستدعي —
--   وثّق ذلك مؤلف 0483 نصاً. فأي حارس مبني على current_user لا يُطلق أبداً.
--
-- ⇒ الدفاع الفعّال الوحيد هو طبقة المنح: ما دام دور anon بلا EXECUTE فلن يصل
--   أي طلب مجهول إلى هذه الدوال عبر PostgREST مهما كان الحارس متساهلاً.
--   جميعها اليوم ممنوحة لـ authenticated فقط (لا ثغرة حيّة)، لكن السحب الصريح
--   يمنع تكرار انحدار 0536/0541 حيث أُعيد منح anon لـ get_instant_penalties
--   بعد أن سحبته 0511 — وهو ما حوّل فخاً كامناً إلى تسريب فعلي.
--
-- لا تغيير في أجسام الدوال ولا في سلوك أي مسار قائم.
-- ═══════════════════════════════════════════════════════════════

begin;

revoke execute on function public.check_invite_rate_limit(uuid)                        from anon, public;
revoke execute on function public.auto_notify_late_attendance()                        from anon, public;
revoke execute on function public.generate_weekly_executive_summary()                  from anon, public;
revoke execute on function public.generate_instant_penalty(uuid, date, integer, text)  from anon, public;
revoke execute on function public.auto_escalate_instant_penalties()                    from anon, public;
revoke execute on function public.auto_generate_instant_penalties()                    from anon, public;
revoke execute on function public.trigger_check_instant_penalties_now()                from anon, public;
revoke execute on function public.confirm_instant_penalty_payment(uuid, text)          from anon, public;
revoke execute on function public.lift_instant_penalty_suspension(uuid, text)          from anon, public;
revoke execute on function public.cancel_instant_penalty(uuid, text)                   from anon, public;
revoke execute on function public.review_instant_penalty_excuse(uuid, text, text)      from anon, public;

-- وتأكيد سحب anon من دوال 0542 (لو أعاد أحد منحها بينهما)
revoke execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from anon, public;
revoke execute on function public.is_employee_attendance_exempt(uuid)                  from anon, public;
revoke execute on function public.is_employee_penalty_exempt(uuid)                     from anon, public;

commit;
