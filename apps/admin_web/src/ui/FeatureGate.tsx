import type { ReactNode } from 'react';
import { isFeatureEnabled, type FeatureFlagKey } from './featureFlags';

/** يعرض المحتوى فقط إذا كان الـ Feature Flag مفعّلًا */
export function FeatureGate({ feature, children, fallback = null }: {
  feature: FeatureFlagKey;
  children: ReactNode;
  fallback?: ReactNode;
}) {
  return <>{isFeatureEnabled(feature) ? children : fallback}</>;
}
