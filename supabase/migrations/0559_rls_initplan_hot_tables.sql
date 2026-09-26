-- =====================================================================
-- 0559: أداء RLS على الجداول الكبيرة — حساب دوال الصلاحية مرة لكل استعلام
--
-- القواعد كانت تستدعي current_is_full_access() و has_permission('…') و
-- auth.uid() لكل صف. كل منها دالة SECURITY DEFINER تستعلم user_roles/roles،
-- فتُنفَّذ آلاف المرات في استعلام واحد. قياس فعلي على الإنتاج: عدّ ما يراه
-- مستخدم واحد في الجداول الثمانية أدناه استغرق 20–90 ثانية (بل تجاوز
-- statement_timeout=8s لدور authenticated في notification_delivery_log).
--
-- الإصلاح: لفّ الاستدعاءات التي لا تعتمد على قيم الصف في ( SELECT … ) فيحسبها
-- المخطط مرة واحدة (InitPlan) — النمط الذي يوصي به Supabase. النتيجة مطابقة
-- رياضياً؛ الاستدعاءات التي تأخذ أعمدة الصف (EXISTS، can_access_employee…) لم تُمس.
--
-- التحقق قبل الكتابة (معاملة مُلغاة على الإنتاج، مستخدمون حقيقيون من كل فئة
-- دور): 48 مقارنة لعدد الصفوف المرئية قبل/بعد — 0 فروق. الزمن: 702ث → 12.7ث.
--
-- النطاق مقصود على الجداول ذات الحجم (notifications 9.9k، notification_delivery_log
-- 11.5k، notification_jobs 9.9k، audit_events 23k، audit_logs 7k، security_events
-- 5.6k، cron_health_log 9k، request_actions 3k). بقية القواعد (549 على جداول صغيرة)
-- بنفس النمط؛ تُعالَج لاحقاً مع تشغيل pgTAP كامل.
-- ALTER POLICY يغيّر التعبير فقط: الاسم والأدوار والأمر ونوع السماح كما هي.
-- =====================================================================

begin;

alter policy "audit_events_select" on public."audit_events" using ((( SELECT current_is_full_access()) OR ( SELECT has_any_permission(ARRAY['audit.event.view'::text, 'audit.view'::text]))));

alter policy "audit_logs_select" on public."audit_logs" using ((( SELECT current_is_full_access()) OR ( SELECT has_any_permission(ARRAY['audit.log.view'::text, 'audit.view'::text]))));

alter policy "full_access_read_cron_health" on public."cron_health_log" using (( SELECT current_is_full_access()));

alter policy "notif_delivery_select" on public."notification_delivery_log" using (((recipient_user_id = ( SELECT auth.uid())) OR ( SELECT current_is_full_access()) OR ( SELECT has_permission('comms.notification.admin'::text))));

alter policy "notif_delivery_write" on public."notification_delivery_log" using ((( SELECT current_is_full_access()) OR ( SELECT has_permission('comms.notification.admin'::text)))) with check ((( SELECT current_is_full_access()) OR ( SELECT has_permission('comms.notification.admin'::text))));

alter policy "notification_jobs_admin" on public."notification_jobs" using (( SELECT current_is_full_access())) with check (( SELECT current_is_full_access()));

alter policy "notification_jobs_no_client" on public."notification_jobs" using ((( SELECT current_is_full_access()) OR ( SELECT has_permission('system.notifications.monitor'::text))));

alter policy "notification_jobs_restricted_read" on public."notification_jobs" using ((( SELECT current_is_full_access()) OR current_has_active_role(ARRAY['hr-manager'::text, 'hr-specialist'::text])));

alter policy "notifications_delete" on public."notifications" using ((recipient_user_id = ( SELECT auth.uid())));

alter policy "notifications_insert" on public."notifications" with check ((( SELECT current_is_full_access()) OR ( SELECT has_permission('comms.notification.send'::text))));

alter policy "notifications_select" on public."notifications" using (((recipient_user_id = ( SELECT auth.uid())) OR ( SELECT current_is_full_access())));

alter policy "notifications_update" on public."notifications" using ((recipient_user_id = ( SELECT auth.uid()))) with check ((recipient_user_id = ( SELECT auth.uid())));

alter policy "request_actions_select" on public."request_actions" using (((actor_employee_id = ( SELECT current_employee_id())) OR (EXISTS ( SELECT 1
   FROM requests r
  WHERE ((r.id = request_actions.request_id) AND ((r.employee_id = ( SELECT current_employee_id())) OR (r.manager_employee_id = ( SELECT current_employee_id())) OR can_access_employee(r.employee_id, 'requests.read'::text)))))));

alter policy "security_events_select" on public."security_events" using ((( SELECT current_is_full_access()) OR ( SELECT has_any_permission(ARRAY['security.event.view'::text, 'audit.view'::text]))));

alter policy "security_events_write" on public."security_events" using ((( SELECT current_is_full_access()) OR ( SELECT has_permission('security.event.manage'::text)))) with check ((( SELECT current_is_full_access()) OR ( SELECT has_permission('security.event.manage'::text))));

commit;
