import type { AssociationProjectListItem, ProjectLedStatus } from '@ahla/shared-contracts';

/** وصف كل حالة للمبة: العنوان القصير + شرح ما تعنيه للمدير التنفيذي. */
export const LED_META: Record<ProjectLedStatus, { label: string; hint: string; tone: string }> = {
  active: { label: 'يعمل بانتظام', hint: 'نشاط حديث على المشروع', tone: 'var(--success)' },
  halted: { label: 'متوقف', hint: 'متوقف أو بلا تحديث منذ فترة', tone: 'var(--danger)' },
  critical: { label: 'يحتاج تدخلك', hint: 'بلا أي تحديث لفترة طويلة — يحتاج تدخل المدير التنفيذي', tone: 'var(--danger)' },
  completed: { label: 'مكتمل', hint: 'تم تنفيذ المشروع', tone: '#3b82f6' },
  stale: { label: 'ملغى', hint: 'تم إلغاء المشروع', tone: 'var(--text-disabled)' },
  pending: { label: 'بانتظار الاعتماد', hint: 'أرسلته الإدارة وينتظر قرار المدير التنفيذي', tone: 'var(--warning)' },
  rejected: { label: 'أُعيد للتعديل', hint: 'رُفض ويحتاج تعديلاً من الإدارة', tone: 'var(--danger)' },
  draft: { label: 'مسودة', hint: 'لم يُرسل للاعتماد بعد', tone: 'var(--text-muted)' },
};

/** ترتيب «الأحوج للتدخل» على اللوحة الرئيسية. */
export const LED_URGENCY: Record<ProjectLedStatus, number> = {
  critical: 0,
  halted: 1,
  active: 2,
  pending: 3,
  rejected: 4,
  draft: 5,
  completed: 6,
  stale: 7,
};

export const STATUS_LABELS: Record<AssociationProjectListItem['status'], string> = {
  planned: 'لم يبدأ',
  active: 'قيد التنفيذ',
  on_hold: 'متوقف',
  completed: 'مكتمل',
  cancelled: 'ملغى',
};

export const PRIORITY_LABELS: Record<AssociationProjectListItem['priority'], string> = {
  low: 'منخفضة',
  medium: 'متوسطة',
  high: 'عالية',
  critical: 'حرجة',
};

export const PRIORITY_ORDER: Record<AssociationProjectListItem['priority'], number> = { critical: 0, high: 1, medium: 2, low: 3 };

export const APPROVAL_LABELS: Record<AssociationProjectListItem['approvalStatus'], string> = {
  draft: 'مسودة',
  pending_approval: 'بانتظار الاعتماد',
  approved: 'معتمد',
  rejected: 'أُعيد للتعديل',
};

export const STEP_STATUS_LABELS: Record<string, string> = {
  pending: 'لم تبدأ',
  in_progress: 'جارية',
  done: 'تمت',
  blocked: 'متعثرة',
};

/** «منذ 3 أيام» — لآخر نشاط. */
export function daysAgoLabel(days: number | null | undefined): string {
  if (days == null) return 'لا يوجد نشاط بعد';
  if (days <= 0) return 'اليوم';
  if (days === 1) return 'أمس';
  if (days === 2) return 'منذ يومين';
  if (days <= 10) return `منذ ${days} أيام`;
  return `منذ ${days} يوماً`;
}

/** أيام منذ تاريخ ISO — احتياط عند غياب daysSinceActivity من الخادم. */
export function daysSince(iso: string | null | undefined): number | null {
  if (!iso) return null;
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000));
}

export function activityDays(p: Pick<AssociationProjectListItem, 'daysSinceActivity' | 'lastActivityAt' | 'lastUpdateAt'>): number | null {
  return p.daysSinceActivity ?? daysSince(p.lastActivityAt ?? p.lastUpdateAt);
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('ar-EG', { year: 'numeric', month: 'short', day: 'numeric' });
}

export function isOnBoard(p: AssociationProjectListItem): boolean {
  return p.approvalStatus === 'approved';
}
