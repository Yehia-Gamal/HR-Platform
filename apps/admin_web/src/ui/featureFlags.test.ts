import { describe, expect, it } from 'vitest';
import { FEATURE_FLAGS, isFeatureEnabled } from './featureFlags';
import type { FeatureFlagKey } from './featureFlags';

describe('featureFlags', () => {
  it('يحتوي على 13 علم', () => {
    expect(Object.keys(FEATURE_FLAGS)).toHaveLength(13);
  });

  it('علم learning مفعّل وبقية الأعلام معطّلة', () => {
    expect(FEATURE_FLAGS.learning).toBe(true);
    for (const key of Object.keys(FEATURE_FLAGS) as FeatureFlagKey[]) {
      if (key === 'learning') continue;
      expect(FEATURE_FLAGS[key]).toBe(false);
    }
  });

  it('isFeatureEnabled يعيد قيمة العلم الصحيحة', () => {
    expect(isFeatureEnabled('learning')).toBe(true);
    expect(isFeatureEnabled('documents')).toBe(false);
    expect(isFeatureEnabled('peopleFinance')).toBe(false);
    expect(isFeatureEnabled('salaries')).toBe(false);
  });

  it('يحتوي على الأعلام المتوقعة', () => {
    const expectedKeys: FeatureFlagKey[] = [
      'learning',
      'documents',
      'lifecycle',
      'governance',
      'helpdesk',
      'peopleFinance',
      'privacy',
      'training',
      'custody',
      'contractEnd',
      'salaries',
      'riskGovernance',
      'duplicateReports',
    ];
    expect(Object.keys(FEATURE_FLAGS).sort()).toEqual(expectedKeys.sort());
  });
});
