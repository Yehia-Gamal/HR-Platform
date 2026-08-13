-- Migration 0394: إصلاح RLS الجداول المالية — عقد الاختبار 0084
-- ================================================================================
-- Migration 0349 أنشأ سياسة {t}_read من نوع FOR ALL بـ USING(self_or_finance)
-- على الجداول المالية، مما سمح للموظف بالكتابة المباشرة (إدراج/تعديل) وللجداول
-- بلا عمود employee_id (payroll_runs, loan_installments, payslip_lines) بقيت
-- بسياسة USING(true) من الحلقة العامة — أي أن أي authenticated يقرأ كل الصفوف.
--
-- العقد (0084):
--   * الموظف يقرأ تعويضه وكشف راتبه فقط (self-service قراءة بلا كتابة).
--   * الموظف لا يقرأ payroll_runs / employee_loans / loan_installments.
--   * الموظف لا يقرأ إلا بنود كشف راتبه.
--   * الكتابة المباشرة ممنوعة على الموظف (تتم عبر سياسات _admin أو RPCs).
--
-- الحل: استبدال سياسات _read بـ FOR SELECT فقط، مع إبقاء سياسات _admin
-- (full-access / hr-manager / hr-specialist) كما هي للكتابة.

BEGIN;

-- employee_compensation: قراءة ذاتية للتعويض + للفرق المالية. SELECT فقط.
drop policy if exists employee_compensation_read on public.employee_compensation;
create policy employee_compensation_read on public.employee_compensation
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- employee_loans: قراءة للفرق المالية فقط (لا self وفق عقد 0084). SELECT فقط.
drop policy if exists employee_loans_read on public.employee_loans;
create policy employee_loans_read on public.employee_loans
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- loan_installments: قراءة للفرق المالية فقط. SELECT فقط.
drop policy if exists loan_installments_read on public.loan_installments;
create policy loan_installments_read on public.loan_installments
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- payroll_runs: قراءة للفرق المالية فقط. SELECT فقط.
drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- payslips: قراءة ذاتية للكشف + للفرق المالية. SELECT فقط.
drop policy if exists payslips_read on public.payslips;
create policy payslips_read on public.payslips
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- payslip_lines: قراءة بنود كشف الموظف الذاتي فقط + للفرق المالية. SELECT فقط.
drop policy if exists payslip_lines_read on public.payslip_lines;
create policy payslip_lines_read on public.payslip_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.payslips ps
      where ps.id = payslip_id
        and ps.employee_id = public.current_employee_id()
    )
    or public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

-- payroll_instapay_batches / items: مالية — لم تشملها 0359 فبقيت USING(true).
drop policy if exists payroll_instapay_batches_read on public.payroll_instapay_batches;
create policy payroll_instapay_batches_read on public.payroll_instapay_batches
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

drop policy if exists payroll_instapay_items_read on public.payroll_instapay_items;
create policy payroll_instapay_items_read on public.payroll_instapay_items
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  );

NOTIFY pgrst, 'Reload schema';

COMMIT;
