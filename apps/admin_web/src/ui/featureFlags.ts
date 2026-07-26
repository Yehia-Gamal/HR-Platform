/**
 * نظام Feature Flags — V23 §13
 * تُستخدم للتحكم التدريجي في إظهار/إخفاء الصفحات الملغاة.
 * عند الحاجة لتفعيل صفحة، غيّر القيمة إلى true.
 */
export const FEATURE_FLAGS = {
  learning: false,
  documents: false,
  lifecycle: false,
  governance: false,
  helpdesk: false,
  peopleFinance: false,
  privacy: false,
  training: false,
  custody: false,
  contractEnd: false,
  salaries: false,
  riskGovernance: false,
  duplicateReports: false,
} as const;

export type FeatureFlagKey = keyof typeof FEATURE_FLAGS;

export function isFeatureEnabled(flag: FeatureFlagKey): boolean {
  return FEATURE_FLAGS[flag];
}
