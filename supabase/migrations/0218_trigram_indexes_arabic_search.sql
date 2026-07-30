-- =====================================================================
-- 0218 — فهارس Trigram للبحث العربي + فهارس أداء إضافية
-- =====================================================================
--
-- pg_trgm مفعّل مسبقاً — نضيف فهارس GIN trigram فقط.
-- جميع الفهارس تستخدم IF NOT EXISTS للأمان عند إعادة التشغيل.
-- ملاحظة: أُزيل CONCURRENTLY لأن Management API (db push --linked)
-- لا يدعمها. الجداول صغيرة فالقفل لحظي.
-- =====================================================================

-- 1) فهرس trigram على اسم الموظف بالعربية — للبحث بـ ILIKE
CREATE INDEX IF NOT EXISTS idx_employees_name_trgm
  ON public.employees USING gin (full_name_ar gin_trgm_ops);

-- 2) فهرس trigram على كود الموظف — للبحث بـ ILIKE
--    (يوجد فهرس btree فريد ux_employees_employee_code لكنه لا يخدم ILIKE)
CREATE INDEX IF NOT EXISTS idx_employees_code_trgm
  ON public.employees USING gin (employee_code gin_trgm_ops);

-- 3) audit_events.actor_user_id — فهرس btree موجود مسبقاً (ix_audit_events_actor)
--    لا حاجة لإعادة إنشائه.

-- 4) فهرس btree على audit_events.created_at — لاستعلامات النطاق الزمني
--    (ix_audit_events_occurred يغطي occurred_at فقط، created_at بدون فهرس)
CREATE INDEX IF NOT EXISTS idx_audit_events_created_at
  ON public.audit_events (created_at DESC);

-- 5) attendance_events(employee_id, event_at) — فهرس مركب موجود مسبقاً (idx_att_events_emp_day)
--    لا حاجة لإعادة إنشائه.

-- 6) فهرس مركب على notifications(recipient_user_id, created_at) — لجلب إشعارات المستخدم مرتبة زمنياً
--    (ix_notifications_recipient يغطي recipient_user_id فقط بدون ترتيب زمني)
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (recipient_user_id, created_at DESC);
