-- =====================================================================
-- 0552: الدوال الخادمية مقفلة أمام authenticated، وسطح anon محصور بالاستثناءات
-- ---------------------------------------------------------------------
-- تكرّر في هذا المستودع نمط «مسح شامل يمنح authenticated على كل دالة»:
-- 0209 فعلته (فاحتاج 0230 لإصلاحه جزئياً)، ثم كررته 0551 المنشورة. ومنح anon
-- عاد ثلاث مرات (0536، 0541، 0547). هذا الاختبار يُسقط الـCI عند أي تكرار.
--
-- فحوص صلاحيات بحتة بالاسم (تغطي كل overload دون الحاجة للتوقيع).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(17);

-- يُرجع true إن كان الدور يملك EXECUTE على أي overload بهذا الاسم
create or replace function pg_temp.can_exec(p_role text, p_fn text)
returns boolean language sql stable as $$
  select coalesce(bool_or(has_function_privilege(p_role, p.oid, 'EXECUTE')), false)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = p_fn
$$;

-- =====================================================================
-- 1) لا دالة من الـ58 قابلة للتنفيذ من authenticated (شامل)
-- =====================================================================
select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        '_cleanup_user_sessions_and_push','activate_verified_passkey_device','cleanup_expired_ephemeral_records',
        'close_kpi_cycle_due','enqueue_integration_event','enqueue_kpi_notification','ensure_leave_account',
        'expire_break_glass_access','generate_kpi_cycle_notifications','generate_punch_reminders',
        'list_retention_video_candidates','mark_retention_video_deleted','notify_dispute_admins',
        'nudge_notification_dispatcher','process_dispute_sla','process_kpi_cycle_schedule',
        'queue_due_scheduled_reports','queue_notification_jobs','resolve_stale_alerts',
        'sync_location_request_response_from_point','sync_location_response_video',
        '_build_attendance_statement','_build_attendance_statement_v186','_build_attendance_statement_v251',
        '_build_attendance_statement_v252','_build_attendance_statement_v266','_build_attendance_statement_v286',
        '_build_attendance_statement_v287','_request_idempotency_key','cancel_stale_location_push_jobs',
        'detect_and_raise_alerts','effective_annual_entitlement','employee_has_role','finalize_missing_checkouts',
        'finalize_verified_attendance','first_active_employee_for_role','get_employee_integrity_summary',
        'is_management_descendant','kpi_diag_run','leave_request_units','open_annual_leave_entitlement',
        'payroll_dsl_get_allowed_types','payroll_evaluate_condition','payroll_formula_interpreter',
        'payroll_tiered_tax_calculation','payroll_validate_dsl_spec','process_request_sla',
        'provision_employee_record','purge_old_failed_notification_jobs','record_attendance_event',
        'record_attendance_local_biometric','run_monthly_leave_accrual','verify_critical_cron_jobs',
        '_admin_approve_request_immediately','_submit_request_for','archive_old_attendance_events',
        'refresh_executive_attendance_overview','refresh_executive_attendance_snapshot'])
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0,
  'صفر دوال خادمية (من 58، بكل overload) قابلة للتنفيذ من authenticated');

-- =====================================================================
-- 2) الأخطر بالاسم — كانت بلا أي حارس داخلي
-- =====================================================================
select is(pg_temp.can_exec('authenticated','activate_verified_passkey_device'), false,
  'P0: الموظف لا يفعّل جهازاً حيوياً دون تحقق WebAuthn');
select is(pg_temp.can_exec('authenticated','record_attendance_local_biometric'), false,
  'P0: الموظف لا يسجّل حضوراً حيوياً مباشرة');
select is(pg_temp.can_exec('authenticated','record_attendance_event'), false,
  'P0: الموظف لا يسجّل حدث حضور مباشرة (كل overload)');
select is(pg_temp.can_exec('authenticated','mark_retention_video_deleted'), false,
  'الموظف لا يَسِم فيديوهات الأدلة كمحذوفة');
select is(pg_temp.can_exec('authenticated','enqueue_integration_event'), false,
  'الموظف لا يحقن أحداث تكامل خارجية');
select is(pg_temp.can_exec('authenticated','queue_notification_jobs'), false,
  'الموظف لا يطلق إشعارات دفع جماعية');
select is(pg_temp.can_exec('authenticated','_submit_request_for'), false,
  'P0: الموظف لا يقدّم طلباً باسم موظف آخر');
select is(pg_temp.can_exec('authenticated','archive_old_attendance_events'), false,
  'P0: الموظف لا يؤرشف سجلّ الحضور');
select is(pg_temp.can_exec('authenticated','kpi_diag_run'), false,
  'kpi_diag_run خادمية فقط (0373) — لا تُعاد فتحها');

-- =====================================================================
-- 3) مستدعو Edge (service_role) ما زالوا يعملون
-- =====================================================================
select is(pg_temp.can_exec('service_role','activate_verified_passkey_device'), true,
  'service_role (passkey-register) ينفّذ activate_verified_passkey_device');
select is(pg_temp.can_exec('service_role','mark_retention_video_deleted'), true,
  'service_role (retention-cleanup) ينفّذ mark_retention_video_deleted');
select is(pg_temp.can_exec('service_role','queue_due_scheduled_reports'), true,
  'service_role (scheduled-report-runner) ينفّذ queue_due_scheduled_reports');

-- =====================================================================
-- 4) إعادة القفل لم تسحب وصولاً مشروعاً من العميل
-- =====================================================================
select is(pg_temp.can_exec('authenticated','get_instant_penalties'), true,
  'authenticated ما زال ينفّذ get_instant_penalties');
select is(pg_temp.can_exec('authenticated','submit_my_request'), true,
  'authenticated ما زال ينفّذ submit_my_request');
select is(pg_temp.can_exec('authenticated','get_association_projects'), true,
  'authenticated ما زال ينفّذ get_association_projects');

-- =====================================================================
-- 5) سطح anon محصور بالاستثناءات الموثّقة (0207/0209/0551)
--    يُسقط الـCI عند تكرار انحدار منح anon (0536، 0541، 0547)
-- =====================================================================
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('anon', p.oid, 'EXECUTE')
      and p.proname not in ('handle_new_user','activate_employee_after_first_login','get_public_release_policy')
      and p.proname not like 'get\_public\_%'
      and not exists (select 1 from pg_depend d join pg_extension e on d.refobjid = e.oid
                       where d.objid = p.oid and d.deptype = 'e')),
  '',
  'لا دالة قابلة للتنفيذ من anon خارج قائمة الاستثناءات الموثّقة');

select * from finish();
rollback;
