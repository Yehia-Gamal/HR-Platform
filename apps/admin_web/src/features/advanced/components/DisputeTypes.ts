import type { DisputeOperationsCatalog } from '@ahla/shared-contracts';

export type DisputeCase = DisputeOperationsCatalog['cases'][number];

export type Person = { id: string; name: string; department?: string | null };

export type RunFn = (task: () => Promise<unknown>, success: string) => Promise<void>;

export const terminalStatuses = new Set(['closed', 'rejected', 'cancelled_by_employee']);

export const caseTypes: Record<string, string> = {
  employee_conflict: 'خلاف بين موظفين',
  inappropriate_conduct: 'سوء تعامل أو أسلوب غير لائق',
  verbal_abuse: 'رفع صوت أو إساءة لفظية',
  management_chain: 'عدم احترام التسلسل الإداري',
  direct_manager: 'مشكلة مع مدير مباشر',
  department_conflict: 'مشكلة بين إدارتين',
  misunderstanding: 'سوء تفاهم',
  work_environment: 'بيئة العمل',
  donor_beneficiary: 'مشكلة مع متبرع أو مستفيد',
  administrative_violation: 'مخالفة إدارية',
  agreement_breach: 'عدم تنفيذ اتفاق سابق',
  other: 'مشكلة أخرى',
};

export const transitionLabels: Record<string, string> = {
  request_more_information: 'طلب استكمال بيانات',
  reject: 'رفض شكلي',
  start_review: 'بدء/استئناف المراجعة',
  request_respondent_statement: 'طلب إفادة الطرف الآخر',
  request_witness_statement: 'طلب إفادة شاهد',
  start_deliberation: 'بدء المداولة',
  escalate: 'تصعيد للمدير التنفيذي',
  return_to_committee: 'إعادة إلى اللجنة',
  close: 'إغلاق بعد التنفيذ',
  reopen: 'إعادة فتح',
  extend_review: 'تمديد مهلة المراجعة 24 ساعة',
  change_priority: 'تغيير الأولوية',
};

export function formatDate(value?: string | null, withTime = true) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-EG', withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' }).format(new Date(value));
}

export function remainingLabel(value?: string | null) {
  if (!value) return 'لا توجد مهلة';
  const hours = Math.ceil((new Date(value).getTime() - Date.now()) / 3_600_000);
  if (hours < 0) return `متأخرة ${Math.abs(hours)} س`;
  if (hours === 0) return 'أقل من ساعة';
  return `متبقي ${hours} س`;
}

export function actionsFor(item: DisputeCase) {
  const result: string[] = [];
  if (['submitted', 'needs_more_information'].includes(item.status)) result.push('request_more_information', 'reject', 'extend_review');
  if (['accepted', 'reopened', 'returned_to_committee'].includes(item.status)) result.push('start_review');
  if (['accepted', 'under_review', 'waiting_for_respondent', 'waiting_for_witness'].includes(item.status)) {
    result.push('request_respondent_statement', 'request_witness_statement', 'start_deliberation');
  }
  if (!terminalStatuses.has(item.status) && item.status !== 'escalated_to_executive') result.push('escalate');
  if (item.status === 'escalated_to_executive') result.push('return_to_committee');
  if (['decision_issued', 'settlement_pending', 'executed'].includes(item.status)) result.push('close');
  if (['closed', 'rejected'].includes(item.status)) result.push('reopen');
  if (!terminalStatuses.has(item.status)) result.push('change_priority');
  return [...new Set(result)];
}
