import { describe, expect, it } from 'vitest';
import { FEATURE_FLAGS, isFeatureEnabled } from './featureFlags';
import type { FeatureFlagKey } from './featureFlags';

describe('featureFlags', () => {
  it('يحتوي على 4 أعلام', () => {
    expect(Object.keys(FEATURE_FLAGS)).toHaveLength(4);
  });

  it('lifecycle و documents و peopleFinance و governance مفعّلون', () => {
    expect(FEATURE_FLAGS.lifecycle).toBe(true);
    expect(FEATURE_FLAGS.documents).toBe(true);
    expect(FEATURE_FLAGS.peopleFinance).toBe(true);
    expect(FEATURE_FLAGS.governance).toBe(true);
    for (const key of Object.keys(FEATURE_FLAGS) as FeatureFlagKey[]) {
      if (key === 'lifecycle' || key === 'documents' || key === 'peopleFinance' || key === 'governance') continue;
      expect(FEATURE_FLAGS[key]).toBe(false);
    }
  });

  it('isFeatureEnabled يعيد قيمة العلم الصحيحة', () => {
    expect(isFeatureEnabled('lifecycle')).toBe(true);
    expect(isFeatureEnabled('documents')).toBe(true);
    expect(isFeatureEnabled('peopleFinance')).toBe(true);
    expect(isFeatureEnabled('governance')).toBe(true);
  });

  it('يحتوي على الأعلام المتوقعة', () => {
    const expectedKeys: FeatureFlagKey[] = ['lifecycle', 'documents', 'governance', 'peopleFinance'];
    expect(Object.keys(FEATURE_FLAGS).sort()).toEqual(expectedKeys.sort());
  });
});
