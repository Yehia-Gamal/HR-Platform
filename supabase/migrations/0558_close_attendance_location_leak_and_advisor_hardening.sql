-- =====================================================================
-- 0558: إغلاق تسريب مواقع الموظفين عبر العروض المادية + تحصينات من Supabase Advisors
--
-- 1) [تسريب خصوصية] mv_executive_attendance_snapshot و _overview (عروض مادية)
--    كانت قابلة للقراءة مباشرة لأي مستخدم مسجَّل (authenticated) عبر REST —
--    والعروض المادية لا تدعم RLS. فيها لكل موظف: خط العرض والطول والعنوان
--    الحي، أوقات البصمة، التأخير، الإجازة، المدير. أي موظف بأدنى صلاحية
--    كان يستطيع رؤية موقع زملائه لحظياً.
--    القراءة المشروعة تتم فقط عبر get_executive_attendance_overview(_fast)
--    (SECURITY DEFINER، مالكها postgres، تشترط reports.attendance.read أو
--    live_location.request أو full-access) — فسحب SELECT المباشر لا يكسر شيئاً.
-- 2) v_employee_status_audit: عرض SECURITY DEFINER (خطأ في Advisor) يكشف حالة
--    حسابات كل الموظفين (موقوف/منتهٍ…) لأي مستخدم مسجَّل. غير مستخدم في
--    أي كود؛ يُحصر في المالك ويُحوَّل إلى security_invoker.
-- 3) get_public_daily_reports_feed: منحة anon زائدة (الدالة ترفض أي طلب بلا
--    جلسة أصلاً) — تُسحب دفاعاً في العمق.
-- 4) فهرس مكرر على mission_executions(employee_id).
-- 5) 24 دالة INVOKER بلا search_path مثبّت: يُثبَّت على نفس القيمة الافتراضية
--    الحالية (public, extensions) + pg_temp — بلا أي تغيير سلوكي.
-- =====================================================================

begin;

-- ─── 1) العروض المادية: القراءة عبر الدوال المحمية فقط ───
revoke select on public.mv_executive_attendance_snapshot from public, anon, authenticated;
revoke select on public.mv_executive_attendance_overview from public, anon, authenticated;

-- ─── 2) عرض حالة الحسابات ───
revoke select on public.v_employee_status_audit from public, anon, authenticated;
alter view public.v_employee_status_audit set (security_invoker = true);

-- ─── 3) منحة anon الزائدة ───
revoke execute on function public.get_public_daily_reports_feed(integer, date) from public, anon;
grant execute on function public.get_public_daily_reports_feed(integer, date) to authenticated, service_role;

-- ─── 4) الفهرس المكرر (يبقى ix_mission_executions_employee المطابق) ───
drop index if exists public.mission_executions_employee_idx;

-- ─── 5) تثبيت search_path ───
do $pin$
begin
  alter function public._fmt_minutes_ar(integer) set search_path = public, extensions, pg_temp;
  alter function public._fmt_time_12h(time without time zone) set search_path = public, extensions, pg_temp;
  alter function public.admin_handle_security_event(uuid) set search_path = public, extensions, pg_temp;
  alter function public.admin_toggle_integration(uuid,boolean) set search_path = public, extensions, pg_temp;
  alter function public.calc_instant_penalty_amount(integer) set search_path = public, extensions, pg_temp;
  alter function public.create_public_holiday(text,date,date,text,uuid,uuid,uuid[],text,boolean) set search_path = public, extensions, pg_temp;
  alter function public.delete_public_holiday(uuid) set search_path = public, extensions, pg_temp;
  alter function public.discipline_action_type_label(text) set search_path = public, extensions, pg_temp;
  alter function public.escape_ilike(text) set search_path = public, extensions, pg_temp;
  alter function public.get_organization_lookups() set search_path = public, extensions, pg_temp;
  alter function public.is_safe_external_link(text) set search_path = public, extensions, pg_temp;
  alter function public.is_safe_storage_path(text) set search_path = public, extensions, pg_temp;
  alter function public.is_safe_url_or_path(text) set search_path = public, extensions, pg_temp;
  alter function public.normalize_phone_e164(text) set search_path = public, extensions, pg_temp;
  alter function public.request_type_label(text) set search_path = public, extensions, pg_temp;
  alter function public.reverse_exact_mojibake(text) set search_path = public, extensions, pg_temp;
  alter function public.reverse_latin1_segments(text) set search_path = public, extensions, pg_temp;
  alter function public.reverse_win1252_segments(text) set search_path = public, extensions, pg_temp;
  alter function public.tg_announcements_validate_banner_url() set search_path = public, extensions, pg_temp;
  alter function public.tg_attendance_validate_selfie_path() set search_path = public, extensions, pg_temp;
  alter function public.tg_employees_validate_photo_url() set search_path = public, extensions, pg_temp;
  alter function public.tg_kpi_evidence_validate_urls() set search_path = public, extensions, pg_temp;
  alter function public.update_public_holiday(uuid,text,date,date,text,uuid,uuid,uuid[],text,boolean,boolean) set search_path = public, extensions, pg_temp;
  alter function public.word_count(text) set search_path = public, extensions, pg_temp;
end $pin$;

notify pgrst, 'reload schema';

commit;
