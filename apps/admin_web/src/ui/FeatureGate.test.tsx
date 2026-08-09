import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { FeatureGate } from './FeatureGate';
import { FEATURE_FLAGS, isFeatureEnabled } from './featureFlags';
import type { FeatureFlagKey } from './featureFlags';

const UNKNOWN_FLAG = 'not_a_real_flag' as FeatureFlagKey;

describe('featureFlags', () => {
  it('has all expected flag keys', () => {
    expect(FEATURE_FLAGS).toHaveProperty('learning');
    expect(FEATURE_FLAGS).toHaveProperty('documents');
    expect(FEATURE_FLAGS).toHaveProperty('lifecycle');
    expect(FEATURE_FLAGS).toHaveProperty('governance');
    expect(FEATURE_FLAGS).toHaveProperty('helpdesk');
    expect(FEATURE_FLAGS).toHaveProperty('peopleFinance');
  });

  it('returns true for enabled features, false for unknown ones', () => {
    expect(isFeatureEnabled('learning')).toBe(true);
    expect(isFeatureEnabled('lifecycle')).toBe(true);
    expect(isFeatureEnabled('documents')).toBe(true);
    expect(isFeatureEnabled('governance')).toBe(true);
    expect(isFeatureEnabled('helpdesk')).toBe(true);
    expect(isFeatureEnabled('peopleFinance')).toBe(true);
    expect(isFeatureEnabled(UNKNOWN_FLAG)).toBeFalsy();
  });
});

describe('FeatureGate', () => {
  it('renders nothing when feature is disabled', () => {
    const { container } = render(
      <FeatureGate feature={UNKNOWN_FLAG}>
        <p>محتوى مخفي</p>
      </FeatureGate>,
    );
    expect(container.textContent).toBe('');
  });

  it('renders fallback when feature is disabled and fallback provided', () => {
    render(
      <FeatureGate feature={UNKNOWN_FLAG} fallback={<p>قريبًا</p>}>
        <p>محتوى مخفي</p>
      </FeatureGate>,
    );
    expect(screen.getByText('قريبًا')).toBeDefined();
    expect(screen.queryByText('محتوى مخفي')).toBeNull();
  });

  it('renders children when feature is enabled', () => {
    render(
      <FeatureGate feature="helpdesk">
        <p>محتوى ظاهر</p>
      </FeatureGate>,
    );
    expect(screen.getByText('محتوى ظاهر')).toBeDefined();
  });
});
