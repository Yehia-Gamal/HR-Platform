import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { FeatureGate } from './FeatureGate';
import { FEATURE_FLAGS, isFeatureEnabled } from './featureFlags';

describe('featureFlags', () => {
  it('has all expected flag keys', () => {
    expect(FEATURE_FLAGS).toHaveProperty('learning');
    expect(FEATURE_FLAGS).toHaveProperty('documents');
    expect(FEATURE_FLAGS).toHaveProperty('lifecycle');
    expect(FEATURE_FLAGS).toHaveProperty('governance');
    expect(FEATURE_FLAGS).toHaveProperty('helpdesk');
    expect(FEATURE_FLAGS).toHaveProperty('peopleFinance');
  });

  it('returns false for all disabled flags', () => {
    for (const key of Object.keys(FEATURE_FLAGS) as Array<keyof typeof FEATURE_FLAGS>) {
      expect(isFeatureEnabled(key)).toBe(false);
    }
  });
});

describe('FeatureGate', () => {
  it('renders nothing when feature is disabled', () => {
    const { container } = render(
      <FeatureGate feature="learning">
        <p>محتوى مخفي</p>
      </FeatureGate>,
    );
    expect(container.textContent).toBe('');
  });

  it('renders fallback when feature is disabled and fallback provided', () => {
    render(
      <FeatureGate feature="learning" fallback={<p>قريبًا</p>}>
        <p>محتوى مخفي</p>
      </FeatureGate>,
    );
    expect(screen.getByText('قريبًا')).toBeDefined();
    expect(screen.queryByText('محتوى مخفي')).toBeNull();
  });
});
