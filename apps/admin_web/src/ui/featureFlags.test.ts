import { describe, expect, it } from 'vitest';
import { FEATURE_FLAGS, isFeatureEnabled } from './featureFlags';
import type { FeatureFlagKey } from './featureFlags';

describe('featureFlags', () => {
  it('يحتوي على 6 أعلام', () => {
    expect(Object.keys(FEATURE_FLAGS)).toHaveLength(6);
  });

  it('learning و lifecycle و documents مفعّلان وبقية الأعلام معطّلة', () => {
    expect(FEATURE_FLAGS.learning).toBe(true);
    expect(FEATURE_FLAGS.lifecycle).toBe(true);
    expect(FEATURE_FLAGS.documents).toBe(true);
    for (const key of Object.keys(FEATURE_FLAGS) as FeatureFlagKey[]) {
      if (key === 'learning' || key === 'lifecycle' || key === 'documents') continue;
      expect(FEATURE_FLAGS[key]).toBe(false);
    }
  });

  it('isFeatureEnabled يعيد قيمة العلم الصحيحة', () => {
    expect(isFeatureEnabled('learning')).toBe(true);
    expect(isFeatureEnabled('lifecycle')).toBe(true);
    expect(isFeatureEnabled('documents')).toBe(true);
    expect(isFeatureEnabled('peopleFinance')).toBe(false);
  });

  it('يحتوي على الأعلام المتوقعة', () => {
    const expectedKeys: FeatureFlagKey[] = [
      'learning',
      'lifecycle',
      'documents',
      'governance',
      'helpdesk',
      'peopleFinance',
    ];
    expect(Object.keys(FEATURE_FLAGS).sort()).toEqual(expectedKeys.sort());
  });
});
