-- Migration 0217: تشديد RLS على جداول النزاعات والشكاوى
-- ============================================================================
-- الهدف: ضمان تفعيل RLS بوضع FORCE على جميع جداول النزاعات، وتوحيد سياسات
-- القراءة (SELECT فقط) في مكان واحد. جميع عمليات الكتابة (INSERT/UPDATE/DELETE)
-- تتم حصرياً عبر دوال SECURITY DEFINER الموجودة.
--
-- الجداول المطلوبة غير الموجودة في المخطط الحالي — تم تخطيها:
--   dispute_case_participants, dispute_escalations, dispute_resolutions,
--   dispute_settlement_agreements, dispute_committee_members
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. dispute_cases — قضايا النزاعات
--    السياسة: SELECT عبر can_access_dispute — أطراف القضية + أعضاء اللجنة + full_access
-- ============================================================================

ALTER TABLE public.dispute_cases FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_cases_select ON public.dispute_cases;
DROP POLICY IF EXISTS dispute_cases_insert ON public.dispute_cases;
DROP POLICY IF EXISTS dispute_cases_update ON public.dispute_cases;
DROP POLICY IF EXISTS dispute_cases_delete ON public.dispute_cases;

CREATE POLICY dispute_cases_select
  ON public.dispute_cases
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_cases FROM authenticated;

-- ============================================================================
-- 2. dispute_sessions — جلسات التحقيق والاستماع
--    السياسة: SELECT عبر القضية الأم — من يرى القضية يرى جلساتها
-- ============================================================================

ALTER TABLE public.dispute_sessions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_sessions_select ON public.dispute_sessions;
DROP POLICY IF EXISTS dispute_sessions_write  ON public.dispute_sessions;

CREATE POLICY dispute_sessions_select
  ON public.dispute_sessions
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(case_id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_sessions FROM authenticated;

-- ============================================================================
-- 3. dispute_evidence — أدلة ومستندات النزاع
--    السياسة: SELECT مع مراعاة الحذف الناعم ومستوى الرؤية (visibility)
-- ============================================================================

ALTER TABLE public.dispute_evidence FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_evidence_select ON public.dispute_evidence;
DROP POLICY IF EXISTS dispute_evidence_write  ON public.dispute_evidence;

CREATE POLICY dispute_evidence_select
  ON public.dispute_evidence
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND (
      public.current_is_full_access()
      OR public.has_permission('disputes.case.read_all')
      OR submitted_by = public.current_employee_id()
      OR EXISTS (
        SELECT 1 FROM public.committee_members cm
        WHERE cm.case_id = dispute_evidence.case_id
          AND cm.employee_id = public.current_employee_id()
          AND cm.is_active
      )
      OR (visibility = 'parties' AND public.can_access_dispute(case_id))
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_evidence FROM authenticated;

-- ============================================================================
-- 4. dispute_decisions — قرارات اللجنة
--    السياسة: SELECT عبر القضية الأم
-- ============================================================================

ALTER TABLE public.dispute_decisions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_decisions_read ON public.dispute_decisions;

CREATE POLICY dispute_decisions_select
  ON public.dispute_decisions
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(case_id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_decisions FROM authenticated;

-- ============================================================================
-- 5. dispute_session_attendance — حضور أعضاء اللجنة في الجلسات
--    (الاسم المطلوب dispute_session_attendees — الجدول الفعلي dispute_session_attendance)
--    السياسة: SELECT عبر الجلسة → القضية الأم
-- ============================================================================

ALTER TABLE public.dispute_session_attendance FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_attendance_read ON public.dispute_session_attendance;

CREATE POLICY dispute_session_attendance_select
  ON public.dispute_session_attendance
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.dispute_sessions s
      WHERE s.id = session_id
        AND public.can_access_dispute(s.case_id)
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_session_attendance FROM authenticated;

-- ============================================================================
-- 6. committee_members — أعضاء لجان النزاع
--    (الاسم المطلوب dispute_committee_members — الجدول الفعلي committee_members)
--    السياسة: full_access + صلاحية إدارة اللجان + العضو يرى عضويته
-- ============================================================================

ALTER TABLE public.committee_members FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS committee_members_select ON public.committee_members;
DROP POLICY IF EXISTS committee_members_write  ON public.committee_members;

CREATE POLICY committee_members_select
  ON public.committee_members
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_permission('disputes.committee.manage')
    OR employee_id = public.current_employee_id()
    OR (
      case_id IS NOT NULL
      AND public.can_access_dispute(case_id)
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.committee_members FROM authenticated;

-- ============================================================================
-- 7. dispute_settlements — تسويات وإجراءات إصلاحية
--    (الاسم المطلوب dispute_settlement_agreements — الجدول الفعلي dispute_settlements)
--    السياسة: SELECT عبر القضية الأم — من يرى القضية يرى تسوياتها
-- ============================================================================

ALTER TABLE public.dispute_settlements FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_settlements_read ON public.dispute_settlements;

CREATE POLICY dispute_settlements_select
  ON public.dispute_settlements
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(case_id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_settlements FROM authenticated;

-- ============================================================================
-- 8. dispute_conflict_declarations — إقرارات تعارض المصالح
--    السياسة: SELECT عبر القضية الأم
-- ============================================================================

ALTER TABLE public.dispute_conflict_declarations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_conflicts_read ON public.dispute_conflict_declarations;

CREATE POLICY dispute_conflict_declarations_select
  ON public.dispute_conflict_declarations
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(case_id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_conflict_declarations FROM authenticated;

-- ============================================================================
-- 9. dispute_appeals — اعتراضات على قرارات اللجنة
--    السياسة: المعترض يرى اعتراضه + من يرى القضية يرى اعتراضاتها
-- ============================================================================

ALTER TABLE public.dispute_appeals FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_appeals_read ON public.dispute_appeals;

CREATE POLICY dispute_appeals_select
  ON public.dispute_appeals
  FOR SELECT TO authenticated
  USING (
    appellant_employee_id = public.current_employee_id()
    OR public.can_access_dispute(case_id)
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_appeals FROM authenticated;

-- ============================================================================
-- 10. dispute_actions — سجل إجراءات وأحداث القضية
--     السياسة: SELECT عبر القضية الأم
-- ============================================================================

ALTER TABLE public.dispute_actions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_actions_read ON public.dispute_actions;

CREATE POLICY dispute_actions_select
  ON public.dispute_actions
  FOR SELECT TO authenticated
  USING (public.can_access_dispute(case_id));

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_actions FROM authenticated;

-- ============================================================================
-- 11. dispute_parties — أطراف القضية (مقدّم الشكوى، المشتكى عليه، شهود)
--     السياسة: الطرف يرى سجله + مقدّم الشكوى يرى الأطراف + أعضاء اللجنة + full_access
-- ============================================================================

ALTER TABLE public.dispute_parties FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_parties_read ON public.dispute_parties;

CREATE POLICY dispute_parties_select
  ON public.dispute_parties
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_permission('disputes.case.read_all')
    OR employee_id = public.current_employee_id()
    OR EXISTS (
      SELECT 1 FROM public.dispute_cases c
      WHERE c.id = case_id
        AND c.actor_employee_id = public.current_employee_id()
    )
    OR EXISTS (
      SELECT 1 FROM public.committee_members cm
      WHERE cm.case_id = dispute_parties.case_id
        AND cm.employee_id = public.current_employee_id()
        AND cm.is_active
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_parties FROM authenticated;

-- ============================================================================
-- 12. dispute_statements — إفادات الأطراف وملاحظات اللجنة
--     السياسة: مراعاة مستوى الرؤية (visibility) لكل إفادة
-- ============================================================================

ALTER TABLE public.dispute_statements FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_statements_read ON public.dispute_statements;

CREATE POLICY dispute_statements_select
  ON public.dispute_statements
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_permission('disputes.case.read_all')
    OR submitted_by = public.current_employee_id()
    OR EXISTS (
      SELECT 1 FROM public.committee_members cm
      WHERE cm.case_id = dispute_statements.case_id
        AND cm.employee_id = public.current_employee_id()
        AND cm.is_active
    )
    OR (visibility = 'parties' AND public.can_access_dispute(case_id))
    OR (
      visibility = 'complainant'
      AND EXISTS (
        SELECT 1 FROM public.dispute_cases c
        WHERE c.id = case_id
          AND c.actor_employee_id = public.current_employee_id()
      )
    )
    OR (
      visibility = 'respondent'
      AND EXISTS (
        SELECT 1 FROM public.dispute_parties dp
        WHERE dp.case_id = dispute_statements.case_id
          AND dp.employee_id = public.current_employee_id()
          AND dp.party_type = 'respondent'
          AND dp.notified_at IS NOT NULL
      )
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_statements FROM authenticated;

-- ============================================================================
-- 13. dispute_session_participants — المشاركون في الجلسات (أطراف + ضيوف)
--     السياسة: المشارك يرى سجله + من يرى القضية عبر الجلسة
-- ============================================================================

ALTER TABLE public.dispute_session_participants FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_session_participants_read ON public.dispute_session_participants;

CREATE POLICY dispute_session_participants_select
  ON public.dispute_session_participants
  FOR SELECT TO authenticated
  USING (
    employee_id = public.current_employee_id()
    OR EXISTS (
      SELECT 1 FROM public.dispute_sessions s
      WHERE s.id = session_id
        AND public.can_access_dispute(s.case_id)
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_session_participants FROM authenticated;

-- ============================================================================
-- 14. dispute_decision_receipts — إيصالات استلام القرار
--     السياسة: الموظف يرى إيصاله + full_access + صلاحية قراءة القضايا
-- ============================================================================

ALTER TABLE public.dispute_decision_receipts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dispute_decision_receipts_read ON public.dispute_decision_receipts;

CREATE POLICY dispute_decision_receipts_select
  ON public.dispute_decision_receipts
  FOR SELECT TO authenticated
  USING (
    employee_id = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.has_permission('disputes.case.read_all')
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط
REVOKE INSERT, UPDATE, DELETE ON public.dispute_decision_receipts FROM authenticated;

-- ============================================================================
-- الجداول المطلوبة غير الموجودة — تم تخطيها:
--   dispute_case_participants  → لا يوجد (الأقرب: dispute_parties + dispute_session_participants)
--   dispute_escalations        → لا يوجد (التصعيد يُدار عبر dispute_cases.status + dispute_actions)
--   dispute_resolutions        → لا يوجد (القرارات في dispute_decisions)
--   dispute_settlement_agreements → لا يوجد (التسويات في dispute_settlements — تمت تغطيتها أعلاه)
-- ============================================================================

COMMIT;
