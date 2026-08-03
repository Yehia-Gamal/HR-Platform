-- ═══════════════════════════════════════════════════════════════════════
-- 0254: تشديد سياسة القراءة على employee_departments (RLS)
-- ═══════════════════════════════════════════════════════════════════════
-- سياسة SELECT أُنشئت في 0156 بـ using(true): أي مستخدم authenticated كان
-- يقرأ أقسام كل الموظفين — يكشف بنية التنظيم والتوظيف دون أي صلاحية.
-- الجدول يُقرأ من الواجهة فقط عبر get_employee_departments (محروس منذ 0245)،
-- وجميع القراءات الأخرى داخل دوال SECURITY DEFINER تتجاوز RLS، فتشديد
-- السياسة آمن ولا يكسر أي مستهلك.
--
-- القاعدة مطابقة لحارس get_employee_departments (0245):
--   صاحب السجل  OR  full-access  OR  HR  OR  can_access_employee(employee_id)
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

DROP POLICY IF EXISTS employee_departments_select ON public.employee_departments;

CREATE POLICY employee_departments_select ON public.employee_departments
  FOR SELECT TO authenticated
  USING (
    employee_id = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.current_is_hr_only()
    OR public.can_access_employee(employee_id)
  );

COMMIT;
