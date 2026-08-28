import type { DisputeOperationsCatalog } from '@ahla/shared-contracts';

export type DisputeCase = DisputeOperationsCatalog['cases'][number];

export type Person = { id: string; name: string; department?: string | null };

export type RunFn = (task: () => Promise<unknown>, success: string) => Promise<void>;

// Explicit Commands interface (mirrors useDisputeCommands return type)
export type Commands = {
  acceptCase: {
    mutateAsync: (params: { p_case_id: string; p_assigned_to: string; p_quorum: number; p_due_at: string | null }) => Promise<unknown>;
    isPending: boolean;
  };
  transitionCase: {
    mutateAsync: (params: { p_case_id: string; p_action: string; p_reason: string | null; p_metadata: Record<string, unknown> }) => Promise<unknown>;
    isPending: boolean;
  };
  setCommittee: {
    mutateAsync: (params: { p_case_id: string; p_members: Array<{ employeeId: string; role: string }> }) => Promise<unknown>;
    isPending: boolean;
  };
  addStatement: {
    mutateAsync: (params: { p_case_id: string; p_statement_type: string; p_statement_text: string; p_visibility: string }) => Promise<unknown>;
    isPending: boolean;
  };
  scheduleSession: {
    mutateAsync: (params: {
      p_case_id: string;
      p_type: string;
      p_scheduled_at: string;
      p_ends_at: string | null;
      p_location: string | null;
      p_modality: string;
      p_participants: Array<{ employeeId: string; role: string }>;
    }) => Promise<unknown>;
    isPending: boolean;
  };
  finalizeSession: {
    mutateAsync: (params: {
      p_session_id: string;
      p_minutes: string;
      p_attendance: Array<{ committeeMemberId: string; status: string }>;
      p_outcome: string | null;
      p_minutes_data: Record<string, unknown>;
    }) => Promise<unknown>;
    isPending: boolean;
  };
  issueDecision: {
    mutateAsync: (params: {
      p_case_id: string;
      p_session_id: string;
      p_text: string;
      p_rationale: string;
      p_outcome: string;
      p_owner_id: string | null;
      p_due_at: string | null;
    }) => Promise<unknown>;
    isPending: boolean;
  };
  recordSettlement: {
    mutateAsync: (params: {
      p_case_id: string;
      p_type: string;
      p_from: string;
      p_to: string | null;
      p_text: string | null;
      p_publication_place: string | null;
      p_due_at: string | null;
    }) => Promise<unknown>;
    isPending: boolean;
  };
  completeAction: { mutateAsync: (params: { p_action_id: string; p_proof: string }) => Promise<unknown>; isPending: boolean };
  decideAppeal: { mutateAsync: (params: { p_appeal_id: string; p_resolution: string }) => Promise<unknown>; isPending: boolean };
  proposeAdminAction: { mutateAsync: (params: { p_case_id: string; p_proposed_action: string; p_detail: string }) => Promise<unknown>; isPending: boolean };
  decideAdminAction: {
    mutateAsync: (params: { p_case_id: string; p_decision: string; p_reason: string | null; p_approved_action: string | null }) => Promise<unknown>;
    isPending: boolean;
  };
  executeAdminAction: { mutateAsync: (params: { p_case_id: string; p_notes: string }) => Promise<unknown>; isPending: boolean };
};

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
