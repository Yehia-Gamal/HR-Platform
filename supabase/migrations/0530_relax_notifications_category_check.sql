-- ═══════════════════════════════════════════════════════════════
-- 0530: توسيع قيد category في notifications ليشمل كل الفئات المستخدمة
--
-- الفئات الجديدة (معرّفة في notificationMeta.tsx) غير مستخدمة في SQL حالياً
-- لكن القييد كان سيمنع الإدراج إذا استُخدمت مستقبلاً.
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- حذف القيد القديم وإعادة إنشائه بالقائمة الكاملة
ALTER TABLE notifications
  DROP CONSTRAINT IF EXISTS notifications_category_check;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_category_check
  CHECK (category IN (
    -- القائمة الأصلية (0034)
    'general',
    'decision',
    'announcement',
    'survey',
    'request',
    'dispute',
    'recognition',
    'system',
    'kpi',
    'device',
    'attendance',
    'location',
    'security',
    'privacy',
    'documents',
    'service',
    'wellbeing',
    'offboarding',
    -- المُضاف في 0317
    'access',
    'workflow',
    'integration',
    'data',
    -- مُضاف الآن: فئات الواجهة الأمامية
    'daily_report',
    'daily_report_like',
    'daily_report_comment',
    'attendance_manager_notify'
  ));

COMMENT ON CONSTRAINT notifications_category_check ON notifications
  IS 'قائمة الفئات المسموح بها — مرّرت 0530 لتضمين فئات الواجهة الأمامية';

COMMIT;
