-- Migration 0216: تشديد RLS على الجداول المالية/التعويضات
-- ============================================================================
-- الهدف: إزالة سياسات FOR ALL المفتوحة واستبدالها بسياسات SELECT فقط.
-- جميع عمليات INSERT/UPDATE/DELETE تتم حصرياً عبر دوال SECURITY DEFINER.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. employee_compensation — تعويضات الموظفين
--    السياسة الحالية: employee_compensation_payroll_admin (FOR ALL, من 0050)
--    الجديد: SELECT فقط — full_access أو صلاحية مالية مع نطاق الموظف
-- ============================================================================

ALTER TABLE public.employee_compensation FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_compensation_payroll_admin ON public.employee_compensation;

CREATE POLICY employee_compensation_select
  ON public.employee_compensation
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.can_access_employee(employee_id, 'payroll.structure.manage')
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

-- ============================================================================
-- 2. employee_loans — سلف وقروض الموظفين
--    السياسة الحالية: employee_loans_payroll_admin (FOR ALL, من 0050)
--    الجديد: SELECT فقط — full_access أو صلاحية مالية مع نطاق الموظف
-- ============================================================================

ALTER TABLE public.employee_loans FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_loans_payroll_admin ON public.employee_loans;

CREATE POLICY employee_loans_select
  ON public.employee_loans
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.can_access_employee(employee_id, 'payroll.structure.manage')
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

-- ============================================================================
-- 3. payroll_runs — دورات مسير الرواتب
--    السياسة الحالية: payroll_runs_manage (FOR ALL, من 0036)
--    الجديد: SELECT فقط — full_access أو صلاحيات إدارة/اعتماد المسير
-- ============================================================================

ALTER TABLE public.payroll_runs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payroll_runs_manage ON public.payroll_runs;

CREATE POLICY payroll_runs_select
  ON public.payroll_runs
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_any_permission(ARRAY['payroll.run.manage', 'payroll.run.approve'])
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

-- ============================================================================
-- 4. payslips — كشوف الرواتب
--    السياسات الحالية: payslips_read (SELECT, من 0036) + payslips_manage (FOR ALL, من 0036)
--    الجديد: إزالة FOR ALL، إبقاء SELECT مع إضافة قراءة السجل الشخصي
-- ============================================================================

ALTER TABLE public.payslips FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payslips_manage ON public.payslips;
DROP POLICY IF EXISTS payslips_read   ON public.payslips;

CREATE POLICY payslips_select
  ON public.payslips
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_any_permission(ARRAY['payroll.run.manage', 'payroll.run.approve'])
    OR (public.has_permission('payroll.payslip.read')
        AND public.can_access_employee(employee_id))
    OR employee_id = public.current_employee_id()
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

-- ============================================================================
-- 5. salary_components — مكونات الراتب (جدول مرجعي)
--    السياسة الحالية: salary_components_payroll_admin (FOR ALL, من 0036 loop)
--    الجديد: SELECT فقط — full_access حصرياً
-- ============================================================================

ALTER TABLE public.salary_components FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS salary_components_payroll_admin ON public.salary_components;

CREATE POLICY salary_components_select
  ON public.salary_components
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

-- ============================================================================
-- 6. payroll_entries — لا يوجد جدول بهذا الاسم في المخطط الحالي
--    (الإدخالات المفصّلة موجودة في payslip_lines)
-- ============================================================================

-- ============================================================================
-- 7. تشديد الجداول المرتبطة: loan_installments + payslip_lines
--    هذه الجداول ترث بيانات حساسة من الجداول الأصلية — نزيل FOR ALL منها أيضاً
-- ============================================================================

-- loan_installments: أقساط القروض
ALTER TABLE public.loan_installments FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS loan_installments_payroll_admin ON public.loan_installments;

CREATE POLICY loan_installments_select
  ON public.loan_installments
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR EXISTS (
      SELECT 1 FROM public.employee_loans l
      WHERE l.id = loan_id
        AND public.can_access_employee(l.employee_id, 'payroll.structure.manage')
    )
  );

-- payslip_lines: بنود كشف الراتب
ALTER TABLE public.payslip_lines FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payslip_lines_manage ON public.payslip_lines;
DROP POLICY IF EXISTS payslip_lines_read   ON public.payslip_lines;

CREATE POLICY payslip_lines_select
  ON public.payslip_lines
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.payslips p
      WHERE p.id = payslip_id
        AND (
          public.current_is_full_access()
          OR public.has_any_permission(ARRAY['payroll.run.manage', 'payroll.run.approve'])
          OR p.employee_id = public.current_employee_id()
        )
    )
  );

-- لا سياسات INSERT/UPDATE/DELETE — التعديل عبر SECURITY DEFINER RPCs فقط

COMMIT;
