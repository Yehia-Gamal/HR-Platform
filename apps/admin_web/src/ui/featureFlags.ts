/**
 * نظام Feature Flags — V23 §13
 * تُستخدم للتحكم التدريجي في إظهار/إخفاء الصفحات.
 * عند الحاجة لتفعيل صفحة، غيّر القيمة إلى true.
 */
export const FEATURE_FLAGS = {
  learning: true,
  lifecycle: true,
  documents: true,
  governance: true,
  helpdesk: true,
  peopleFinance: true,
} as const;

export type FeatureFlagKey = keyof typeof FEATURE_FLAGS;

export function isFeatureEnabled(flag: FeatureFlagKey): boolean {
  return FEATURE_FLAGS[flag];
}
