-- ═══════════════════════════════════════════════════════════════
-- 0552: إعادة قفل الدوال الخادمية أمام authenticated
--
-- (1) تعرّض قائم منذ 0209: تلك الـmigration سحبت PUBLIC/anon من كل دوال public
--     ثم **منحت authenticated على كلها** في حلقة ديناميكية. فأعادت فتح كل دالة
--     قُيِّدت عمداً قبلها. 0230 «restore_server_only_privileges» استعادت 9 فقط.
--     النتيجة: 21 دالة خادمية ظلّت قابلة للاستدعاء من أي موظف مسجّل عبر
--     supabase.rpc(...) — منها دوال بلا أي حارس داخلي:
--       • activate_verified_passkey_device — تُستدعى من passkey-register فقط بعد
--         التحقق التشفيري من شهادة WebAuthn؛ استدعاؤها مباشرة يسجّل اعتماداً
--         حيوياً دون إثبات امتلاك الجهاز.
--       • mark_retention_video_deleted — وسم فيديوهات أدلة الموقع كمحذوفة.
--       • enqueue_integration_event / queue_notification_jobs — حقن أحداث تكامل
--         خارجية وإشعارات دفع لأي أحد.
--
-- (2) 0551 (منشورة) كررت 0209 حرفياً: تمنح authenticated على **كل** دالة، فتعيد
--     فتح الـ54 المقيّدة عمداً. لا نعدّل migration منشورة (CLAUDE.md) — هذه
--     الـmigration تعيد القفل بالاسم بعدها، أياً كانت البيئة.
--
-- (3) فئة ثالثة: 5 دوال أنشأتها migrations بنيّة service_role فقط (grant لـ
--     service_role دون authenticated)، لكن امتيازات Supabase الافتراضية منحت
--     authenticated تلقائياً ولم تُسحب صراحةً قط. اثنتان بلا أي حارس داخلي:
--       • _submit_request_for(p_employee_id, …) — تقديم طلب باسم أي موظف آخر.
--       • archive_old_attendance_events(p_older_than_months, …) — العتبة مُعامِل،
--         فتمرير 0 يؤرشف سجلّ الحضور بالجملة.
--
-- تحقّقٌ قبل القفل (2026-09-23):
--   • صفر مستدعين من العميل (apps/ و packages/) لأي من الـ58.
--   • مستدعو Edge (passkey-register، retention-cleanup، scheduled-report-runner)
--     يستخدمون عميل service_role — نمنحه صراحةً أدناه.
--   • صفر اعتماد في سياق المستخدم: لا دالة SECURITY INVOKER ولا سياسة RLS ولا
--     view بـsecurity_invoker تستدعي أياً منها. pg_cron يعمل بصلاحية المالك.
--   • handle_new_user مستثناة عمداً (استثناء anon الموثّق في 0207/0209/0551).
--
-- الحلقة بالاسم: تغطي كل overload، وتتجاهل الدوال القديمة المحذوفة بلا خطأ.
-- ═══════════════════════════════════════════════════════════════

begin;

do $relock$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (array[
         -- ── أعاد 0209 فتحها ولم تُقفَل بعدها (التعرّض القائم) ──
         '_cleanup_user_sessions_and_push',
         'activate_verified_passkey_device',
         'cleanup_expired_ephemeral_records',
         'close_kpi_cycle_due',
         'enqueue_integration_event',
         'enqueue_kpi_notification',
         'ensure_leave_account',
         'expire_break_glass_access',
         'generate_kpi_cycle_notifications',
         'generate_punch_reminders',
         'list_retention_video_candidates',
         'mark_retention_video_deleted',
         'notify_dispute_admins',
         'nudge_notification_dispatcher',
         'process_dispute_sla',
         'process_kpi_cycle_schedule',
         'queue_due_scheduled_reports',
         'queue_notification_jobs',
         'resolve_stale_alerts',
         'sync_location_request_response_from_point',
         'sync_location_response_video',
         -- ── كانت مقفلة قبل 0551، وأعادت 0551 (المنشورة) فتحها ──
         '_build_attendance_statement',
         '_build_attendance_statement_v186',
         '_build_attendance_statement_v251',
         '_build_attendance_statement_v252',
         '_build_attendance_statement_v266',
         '_build_attendance_statement_v286',
         '_build_attendance_statement_v287',
         '_request_idempotency_key',
         'cancel_stale_location_push_jobs',
         'detect_and_raise_alerts',
         'effective_annual_entitlement',
         'employee_has_role',
         'finalize_missing_checkouts',
         'finalize_verified_attendance',
         'first_active_employee_for_role',
         'get_employee_integrity_summary',
         'is_management_descendant',
         'kpi_diag_run',
         'leave_request_units',
         'open_annual_leave_entitlement',
         'payroll_dsl_get_allowed_types',
         'payroll_evaluate_condition',
         'payroll_formula_interpreter',
         'payroll_tiered_tax_calculation',
         'payroll_validate_dsl_spec',
         'process_request_sla',
         'provision_employee_record',
         'purge_old_failed_notification_jobs',
         'record_attendance_event',
         'record_attendance_local_biometric',
         'run_monthly_leave_accrual',
         'verify_critical_cron_jobs',
         -- ── نيّتها service_role فقط لكن امتيازات Supabase الافتراضية (وتأكيد 0209)
         --    منحت authenticated تلقائياً عند الإنشاء، ولم تُسحب صراحةً قط ──
         '_admin_approve_request_immediately',
         '_submit_request_for',
         'archive_old_attendance_events',
         'refresh_executive_attendance_overview',
         'refresh_executive_attendance_snapshot'
       ])
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
    v_count := v_count + 1;
  end loop;

  raise notice '0552: أُعيد قفل % دالة خادمية (بما فيها كل overload).', v_count;
end $relock$;

commit;
