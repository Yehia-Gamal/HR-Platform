-- ═══════════════════════════════════════════════════════════════
-- 0637: سحب anon من دوال SECURITY DEFINER بلا حارس جلسة
--
-- الخلفية — تكملة تدقيق 0542/0543/0558:
--   فحص حيّ على الإنتاج: أي دور يستطيع تشغيل أي دالة في public؟
--   (select ... from pg_proc where has_function_privilege('anon', oid, 'EXECUTE'))
--   أعطى 126 دالة؛ أغلبها امتدادات (citext / pgcrypto / pg_trgm) بامتياز افتراضي.
--   بينها 7 دوال تطبيق SECURITY DEFINER، موزّعة هكذا:
--
--   • محمية بحارس يرفع استثناء عند غياب الجلسة  ⇒ لا تستغلّ من anon أصلاً:
--       - activate_employee_after_first_login()   if auth.uid() is null then raise
--       - get_mobile_employees(...)               if auth.uid() is null then raise 42501
--   • مقصودة علنًا:
--       - get_public_release_policy(...)          سياسة الإصدار للموبايل غير المسجّل
--   • دالة trigger يُشغّلها صندوق auth فقط:
--       - handle_new_user()
--   • **بلا أي حارس جلسة** ⇒ تسريب فعلي لـ anon (هذه هي المشكلة):
--       - check_employee_penalty_exemption_v2(uuid, date)
--       - is_employee_exempt_from_instant_penalty(uuid, date)
--       - calculate_paired_work_minutes(uuid, tstz, tstz)
--       - is_employee_split_shift(uuid)
--       - match_flexible_shift(tstz)
--
--   هذه الأربع/الخمس تأخذ أي معرّف موظف وتُرجع بياناته دون أن تسأل عن الجلسة:
--     • اسم القسم والفرع وحالة الموظف ونشاطه
--     • أسباع الإعفاء الدائمة ومعايرها
--     • طلبات الإجازات/المآذير/القوافل المقبولة والمعلّقة مع تواريخها
--     • عناوين مهام العمل المسندة
--     • حالة اليوم في attendance_daily
--     • دقائق الدفع الفعلي من attendance_events
--   وكل ذلك عبر POST /rest/v1/rpc/<name> بلا أي token.
--
-- لماذا طبقة المنح لا الحارس:
--   current_user داخل SECURITY DEFINER = مالك الدالة لا المستدعي (وُثّق في 0483)،
--   فأي حارس مبني على current_user لا يُطلق أبداً. والطريقة الوحيدة للتفرقة
--   بين anon و service_role هي منع anon من الوصول أصلاً — وهو ما فعله 0543.
--
-- لماذا revoke من PUBLIC أيضاً:
--   الدوال ذات علامة `-:EXECUTE` في pg_acl تملك منحاً افتراضياً لـ PUBLIC،
--   فيكفي سحب anon صراحةً ليبقى مفعّلاً عبر PUBLIC. السحب من PUBLIC لا يمسّ
--   authenticated / postgres / service_role لأن لكل منها منحاً مباشراً صريحاً
--   (تحقّقت من pg_acl قبل كتابة هذا الملف)، ثم نعيد grant صراحةً تفاديًا.
--
-- ما لم نمسّه — ولماذا:
--   • activate_employee_after_first_login(): تحرس نفسها بـ auth.uid() is null،
--     وتُستدعى من PasswordSetupPage (ويب) و set_password_page (موبايل) بعد
--     exchangeCodeForSession — أي جلسة قائمة أصلاً. سحب anon هنا يبدّل رسالة
--     الخطأ من P0001 إلى 401 دون أي كسب أمني، فلا نخاطر بمسار إعادة التعيين.
--   • get_my_instant_penalties() / get_my_notifications(int,int): ليست
--     SECURITY DEFINER، فتُنفَّذ بهوية anon وتُحاط بـ RLS = صفر صفوف.
--   • try_cast_date(text): دالة أداة نصية بلا بيانات.
--
-- لا تغيير في جسم أي دالة ولا في سلوك أي مسار مصادَق عليه.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ── 1) الدوال الخمس بلا حارس جلسة ───────────────────────────────
revoke execute on function public.check_employee_penalty_exemption_v2(uuid, date)
  from anon, public;
revoke execute on function public.is_employee_exempt_from_instant_penalty(uuid, date)
  from anon, public;
revoke execute on function public.calculate_paired_work_minutes(uuid, timestamp with time zone, timestamp with time zone)
  from anon, public;
revoke execute on function public.is_employee_split_shift(uuid)
  from anon, public;
revoke execute on function public.match_flexible_shift(timestamp with time zone)
  from anon, public;

-- ── 2) دالة كتالوج الموظفين — محمية بحارس لكن السحب الصريح يمنع
--       انحدار 0536/0541 حيث أُعيد منح anon بعد سحبه ──────────────
revoke execute on function public.get_mobile_employees(text, uuid, text, integer, integer)
  from anon, public;

-- ── 3) دالة trigger — لا يُستدعى إلا من محرّك auth ───────────────
revoke execute on function public.handle_new_user() from anon, public;

-- ── 4) استعادة المنح الصريحة لأصحابها (idempotent) ───────────────
--       service_role / postgres يحتفظان بمنحهما المباشرين دون تغيير.
grant execute on function public.check_employee_penalty_exemption_v2(uuid, date)
  to authenticated, service_role, postgres;
grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date)
  to authenticated, service_role, postgres;
grant execute on function public.calculate_paired_work_minutes(uuid, timestamp with time zone, timestamp with time zone)
  to authenticated, service_role, postgres;
grant execute on function public.is_employee_split_shift(uuid)
  to authenticated, service_role, postgres;
grant execute on function public.match_flexible_shift(timestamp with time zone)
  to authenticated, service_role, postgres;
grant execute on function public.get_mobile_employees(text, uuid, text, integer, integer)
  to authenticated, service_role, postgres;

commit;

-- إعادة تحميل مخطط PostgREST كي يتوقف anon عن رؤية هذه الدوال فوراً
notify pgrst, 'reload schema';
