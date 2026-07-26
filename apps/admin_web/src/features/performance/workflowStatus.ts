// Arabic labels for the official KPI workflow states (kpi_evaluations.workflow_status).
// Keep in sync with the CHECK constraint in migration 0058 + V23 migration 0163.
export const kpiWorkflowStatusLabel: Record<string, string> = {
  DRAFT: 'مسودة قبل فتح الدورة',
  OPEN_FOR_SELF_EVALUATION: 'مفتوح للتقييم الذاتي',
  SUBMITTED_TO_DIRECT_MANAGER: 'أُرسل إلى المدير المباشر',
  MANAGER_REVIEW: 'قيد مراجعة المدير المباشر',
  HR_REVIEW: 'قيد مراجعة الموارد البشرية',
  RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL: 'عاد إلى المدير للاعتماد النهائي',
  MANAGER_APPROVED: 'اعتمده المدير المباشر',
  INCLUDED_IN_MONTHLY_REPORT: 'مدرج في التقرير الشهري',
  CYCLE_CLOSED: 'أُغلقت الدورة',
  ARCHIVED: 'مؤرشف',
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
  // V23: حالات المسار المتوازي
  PARALLEL_REVIEW_IN_PROGRESS: 'مراجعة HR والمدير جارية بالتوازي',
  HR_COMPLETED: 'أنهى HR مراجعته — بانتظار المدير',
  MANAGER_COMPLETED: 'أنهى المدير مراجعته — بانتظار HR',
  SECRETARY_REVIEW: 'قيد مراجعة السكرتير التنفيذي',
  EXECUTIVE_REVIEW: 'بانتظار إقرار المدير التنفيذي',
  EXECUTIVE_ACKNOWLEDGED: 'أقرّ المدير التنفيذي',
  RETURNED_BY_EXECUTIVE: 'أعاده المدير التنفيذي للمراجعة',
};

export const kpiWorkflowStatusText = (value?: string | null): string =>
  (value && kpiWorkflowStatusLabel[value]) || value || '';
