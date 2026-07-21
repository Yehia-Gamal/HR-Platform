// Arabic labels for the official KPI workflow states (kpi_evaluations.workflow_status).
// Keep in sync with the CHECK constraint in migration 0058_official_kpi_governance.sql.
export const kpiWorkflowStatusLabel: Record<string, string> = {
  NOT_STARTED: 'لم تبدأ',
  EMPLOYEE_INPUT_IN_PROGRESS: 'الموظف يُدخل بياناته',
  HR_DATA_PENDING: 'بانتظار تجهيز بيانات HR',
  SESSION_SCHEDULED: 'الجلسة مجدولة',
  SESSION_COMPLETED: 'تمت الجلسة',
  MANAGER_EVALUATION_IN_PROGRESS: 'تقييم المدير جارٍ',
  HR_EVALUATION_IN_PROGRESS: 'تقييم HR جارٍ',
  EMPLOYEE_ACKNOWLEDGEMENT_PENDING: 'بانتظار اطلاع الموظف',
  EMPLOYEE_ACKNOWLEDGED: 'أقرّ الموظف بالاطلاع',
  FINAL_REVIEW: 'قيد المراجعة النهائية',
  SENT_TO_EXECUTIVE_DIRECTOR: 'مُرسل للمدير التنفيذي',
  RETURNED_FOR_REVISION: 'أُعيد للتصحيح',
  APPROVED: 'معتمد',
  CLOSED: 'مؤرشف',
  OVERDUE: 'متأخر عن الموعد',
};

export const kpiWorkflowStatusText = (value?: string | null): string =>
  (value && kpiWorkflowStatusLabel[value]) || value || '';
