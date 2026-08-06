import type { OnboardingAdminCatalog } from '@ahla/shared-contracts';
import { useOnboardingAdminCatalog, useOnboardingCommands } from '../management/useAdminOperations';

/**
 * نموذج دورة حياة الموظف في النظام الحالي.
 * مرحلة التهيئة (onboarding) هي المرحلة المدعومة عبر RPCs
 * get_onboarding_admin_catalog / create_onboarding_journey_admin / transition_onboarding_task_admin.
 * تُضاف مراحل أخرى (تجربة/تثبيت/خروج) عند توفر RPCs مستقبلية.
 */
export const LIFECYCLE_STAGES = ['onboarding', 'probation', 'active', 'exit'] as const;
export type LifecycleStage = (typeof LIFECYCLE_STAGES)[number];

export const JOURNEY_STATUS_LABELS: Record<string, string> = {
  not_started: 'لم تبدأ',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتملة',
};

export const TASK_STATUS_ORDER = ['pending', 'in_progress', 'completed', 'skipped'] as const;

export const TASK_STATUS_LABELS: Record<string, string> = {
  pending: 'قيد الانتظار',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتملة',
  skipped: 'تم تجاوزها',
};

export type LifecycleCatalog = OnboardingAdminCatalog;

export function useLifecycleCatalog() {
  return useOnboardingAdminCatalog();
}

export function useLifecycleCommands() {
  return useOnboardingCommands();
}
