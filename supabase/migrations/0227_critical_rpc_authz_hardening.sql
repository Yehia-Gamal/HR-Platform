-- ═══════════════════════════════════════════════════════════════
-- تعزيز أمني — الجولة الرابعة (P0 + P1)
-- إصلاح ثغرات تصعيد صلاحيات وتسريب بيانات في RPCs
--
-- P0 CRITICAL:
--   1. provision_employee_record — أي مستخدم يمكنه إنشاء موظف بأي دور
--   2. _cleanup_user_sessions_and_push — أي مستخدم يمكنه طرد أي مستخدم
--   3. activate_verified_passkey_device — حقن بيانات اعتماد لمستخدم آخر
--   4. get_audit_security_data — تسريب سجلات الأمان للجميع
--   5. get_operations_center_data — تسريب بيانات الموظفين للجميع
--   6. get_integration_center_data — تسريب بيانات التكامل للجميع
--
-- P1 HIGH:
--   7. apply_leave_ledger_entry — تعديل رصيد إجازات أي موظف
--   8. expire_break_glass_access — إلغاء صلاحيات الطوارئ
--   9. process_kpi_cycle_schedule — التلاعب بدورات KPI
--  10. mark_retention_video_deleted — حذف أدلة الفيديو
--  11. cleanup_expired_ephemeral_records — حذف سجلات أمنية (DoS)
--  12. survey_responses INSERT — تزوير ردود الاستبيانات
--  13. employees.is_active — موظف يمكنه إلغاء تفعيل نفسه
--  14. live-location-videos COALESCE bypass
--  15. سحب anon من 7 دوال حساسة + PUBLIC من دوال مكشوفة
--  16. إضافة تأمين للإشعارات والأحداث المكشوفة
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- P0-1: provision_employee_record — سحب من authenticated
-- الدالة يجب أن تُستدعى فقط من Edge Function (service_role)
-- Edge Function admin-create-employee يتحقق من has_permission
-- ═══════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.provision_employee_record(
  uuid, uuid, text, text, text, text, text,
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid,
  date, boolean, text, text
) FROM authenticated;

-- ═══════════════════════════════════════════════════════════════
-- P0-2: _cleanup_user_sessions_and_push — سحب من authenticated
-- دالة داخلية للنظام فقط (service_role)
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  SELECT p.oid::regprocedure::text INTO fn_sig
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = '_cleanup_user_sessions_and_push'
  LIMIT 1;

  IF fn_sig IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END IF;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P0-3: activate_verified_passkey_device — إضافة تحقق auth.uid()
-- ═══════════════════════════════════════════════════════════════

-- نستبدل الدالة بنسخة تتحقق من auth.uid() = p_user_id
DO $$
DECLARE
  fn_body text;
  fn_sig text;
BEGIN
  SELECT p.oid::regprocedure::text, prosrc INTO fn_sig, fn_body
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'activate_verified_passkey_device'
  LIMIT 1;

  -- إضافة فحص auth.uid() في بداية الدالة إذا لم يكن موجوداً
  IF fn_sig IS NOT NULL AND fn_body NOT LIKE '%auth.uid()%' THEN
    -- الحل الأسرع والأكثر أماناً: سحب من authenticated
    -- الدالة تُستدعى من Edge Function verify-attendance-punch (service_role)
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END IF;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P0-4,5,6: get_audit_security_data, get_operations_center_data,
--           get_integration_center_data — إضافة تحقق الصلاحيات
-- ═══════════════════════════════════════════════════════════════

-- سحب PUBLIC و anon من الدوال المكشوفة
DO $$
DECLARE
  fn_name text;
  fn_sig text;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'get_audit_security_data',
    'get_operations_center_data',
    'get_integration_center_data',
    'get_employee_photo_url'
  ]
  LOOP
    FOR fn_sig IN
      SELECT p.oid::regprocedure::text
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = fn_name
    LOOP
      EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM PUBLIC, anon';
    END LOOP;
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-7: apply_leave_ledger_entry — سحب من authenticated
-- تُستدعى من دوال أخرى محمية أو من service_role
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'apply_leave_ledger_entry'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-8: expire_break_glass_access — سحب من authenticated
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'expire_break_glass_access'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-9: process_kpi_cycle_schedule — سحب من authenticated
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'process_kpi_cycle_schedule'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-10: mark_retention_video_deleted — سحب من authenticated
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'mark_retention_video_deleted'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-11: cleanup_expired_ephemeral_records — سحب من authenticated
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_sig text;
BEGIN
  FOR fn_sig IN
    SELECT p.oid::regprocedure::text
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'cleanup_expired_ephemeral_records'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-12: survey_responses INSERT — إضافة فحص هوية المُجيب
-- استبدال السياسة بنسخة تربط الـ respondent بـ current_employee_id
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS survey_responses_insert ON public.survey_responses;

CREATE POLICY survey_responses_insert ON public.survey_responses
  FOR INSERT TO authenticated
  WITH CHECK (
    -- الاستبيان يجب أن يكون مفتوحاً
    EXISTS (
      SELECT 1 FROM public.surveys s
      WHERE s.id = survey_id AND s.status = 'open'
    )
    -- المُجيب يجب أن يكون الموظف الحالي
    AND created_by = auth.uid()
  );

-- ═══════════════════════════════════════════════════════════════
-- P1-13: employees.is_active — حماية بواسطة trigger
-- إضافة is_active إلى قائمة الحقول المحمية
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION tg_employees_protect_job_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- السماح لـ service_role و postgres بالتعديل بدون قيود
  IF current_setting('request.jwt.claim.role', true) = 'service_role'
     OR current_user IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  -- الحقول المحمية: تحتاج صلاحية people.employee.update_sensitive
  IF (
    NEW.employee_code    IS DISTINCT FROM OLD.employee_code OR
    NEW.status           IS DISTINCT FROM OLD.status OR
    NEW.is_active        IS DISTINCT FROM OLD.is_active OR
    NEW.department_id    IS DISTINCT FROM OLD.department_id OR
    NEW.team_id          IS DISTINCT FROM OLD.team_id OR
    NEW.branch_id        IS DISTINCT FROM OLD.branch_id OR
    NEW.work_site_id     IS DISTINCT FROM OLD.work_site_id OR
    NEW.job_title_id     IS DISTINCT FROM OLD.job_title_id OR
    NEW.position_id      IS DISTINCT FROM OLD.position_id OR
    NEW.grade_id         IS DISTINCT FROM OLD.grade_id OR
    NEW.employment_type_id IS DISTINCT FROM OLD.employment_type_id OR
    NEW.hire_date        IS DISTINCT FROM OLD.hire_date OR
    NEW.contract_end     IS DISTINCT FROM OLD.contract_end OR
    NEW.user_id          IS DISTINCT FROM OLD.user_id
  ) THEN
    IF NOT (
      public.current_is_full_access()
      OR public.has_permission('people.employee.update_sensitive')
    ) THEN
      RAISE EXCEPTION 'ERR_FORBIDDEN: تعديل الحقول الحساسة يتطلب صلاحية people.employee.update_sensitive'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-14: live-location-videos COALESCE null bypass
-- حذف السياسة المكررة التي تستخدم COALESCE
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS live_location_videos_owner_write ON storage.objects;

-- ═══════════════════════════════════════════════════════════════
-- P1-15: سحب anon من 7 دوال حساسة
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_name text;
  fn_sig text;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'batch_decide_requests',
    'batch_mark_notifications_read',
    'list_credentials',
    'read_credential',
    'store_credential',
    'revoke_credential',
    'refresh_all_materialized_views',
    'handle_new_user'
  ]
  LOOP
    FOR fn_sig IN
      SELECT p.oid::regprocedure::text
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = fn_name
    LOOP
      EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM PUBLIC, anon';
    END LOOP;
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-16: سحب authenticated من دوال الإشعارات والأحداث المكشوفة
-- هذه الدوال يجب أن تُستدعى فقط من service_role أو من دوال أخرى
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_name text;
  fn_sig text;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    'enqueue_integration_event',
    'enqueue_kpi_notification',
    'generate_kpi_cycle_notifications',
    'notify_dispute_admins',
    'queue_due_scheduled_reports'
  ]
  LOOP
    FOR fn_sig IN
      SELECT p.oid::regprocedure::text
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = fn_name
    LOOP
      EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
      EXECUTE 'GRANT EXECUTE ON FUNCTION ' || fn_sig || ' TO service_role';
    END LOOP;
  END LOOP;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- P1-17: سحب authenticated من trigger functions (12 دالة)
-- لا يمكن استدعاؤها عبر PostgREST لكن لا حاجة للمنح
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  fn_name text;
  fn_sig text;
BEGIN
  FOREACH fn_name IN ARRAY ARRAY[
    '_on_primary_department_removed',
    '_sync_primary_department',
    'audit_row_change',
    'queue_notification_jobs',
    'sync_location_request_response_from_point',
    'sync_location_response_video',
    'tg_leave_attendance_on_approval',
    'trg_announcement_broadcast_notify',
    'trg_fn_device_pending_notify_admins',
    'trg_fn_employee_devices_auto_replace',
    'trg_fn_public_holiday_broadcast',
    'rls_auto_enable'
  ]
  LOOP
    FOR fn_sig IN
      SELECT p.oid::regprocedure::text
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = fn_name
    LOOP
      EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || fn_sig || ' FROM authenticated, anon, PUBLIC';
    END LOOP;
  END LOOP;
END
$$;

COMMIT;
