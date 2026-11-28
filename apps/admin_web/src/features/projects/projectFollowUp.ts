import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { LED_URGENCY, PRIORITY_ORDER, activityDays, isOnBoard } from './projectLedStatus';

export const FOLLOW_UP = {
  deadline: { label: 'تجاوز الموعد', filter: 'تجاوزت موعدها', nextAction: 'راجع الموعد المتفق عليه وحدّد خطة لاستكمال العمل.' },
  blocked: { label: 'خطوات متعثرة', filter: 'بها خطوات متعثرة', nextAction: 'راجع الخطوات المتعثرة وحدّد ما يلزم لاستئنافها.' },
  late: { label: 'خطوات متأخرة', filter: 'بها خطوات متأخرة', nextAction: 'تابع الخطوات التي تجاوزت مواعيدها مع المسؤولين عنها.' },
  paused: { label: 'متوقف', filter: 'متوقفة', nextAction: 'راجع سبب التوقف وما يلزم لاستئناف العمل.' },
  inactive: { label: 'بلا نشاط حديث', filter: 'بلا نشاط حديث', nextAction: 'راجع آخر نشاط وسجّل المستجدات أو سبب التأخر.' },
  plan: { label: 'بلا خطوات مسجّلة', filter: 'بلا خطوات مسجّلة', nextAction: 'حدّد الخطوة التالية ومن يتولاها وموعدها.' },
  closure: { label: 'اكتمال النطاق بحاجة إلى مراجعة', filter: 'بانتظار مراجعة النطاق', nextAction: 'راجع نطاق العمل وأضف أي أعمال متبقية قبل تسجيل الاكتمال.' },
} as const;

export type FollowUpReason = keyof typeof FOLLOW_UP;
export type FollowUpFilter = 'all' | FollowUpReason;
const REASON_ORDER = Object.keys(FOLLOW_UP) as FollowUpReason[];

export function projectFollowUpReasons(project: AssociationProjectListItem): FollowUpReason[] {
  if (!isOnBoard(project) || project.status === 'completed' || project.status === 'cancelled') return [];
  const reasons: FollowUpReason[] = [];
  if (project.isOverdue) reasons.push('deadline');
  if (project.blockedSteps > 0) reasons.push('blocked');
  if (project.overdueSteps > 0) reasons.push('late');
  if (project.status === 'on_hold') reasons.push('paused');
  else if (project.ledStatus === 'critical' || project.ledStatus === 'halted') reasons.push('inactive');
  if (project.totalSteps === 0) reasons.push('plan');
  else if (project.completedSteps >= project.totalSteps) reasons.push('closure');
  return reasons;
}

export function compareProjectFollowUp(a: AssociationProjectListItem, b: AssociationProjectListItem): number {
  const first = (project: AssociationProjectListItem) => {
    const [reason] = projectFollowUpReasons(project);
    return reason ? REASON_ORDER.indexOf(reason) : REASON_ORDER.length;
  };
  return first(a) - first(b)
    || LED_URGENCY[a.ledStatus] - LED_URGENCY[b.ledStatus]
    || PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]
    || (activityDays(b) ?? 9999) - (activityDays(a) ?? 9999);
}
