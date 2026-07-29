import { describe, it, expect } from 'vitest';
import { publicReleasePolicySchema } from '@ahla/shared-contracts';

const localPolicy = {
  action: 'none' as const,
  platform: 'web' as const,
  environment: 'development' as const,
  currentVersion: '1.0.0',
  currentBuild: 1,
  latestVersion: '1.0.0',
  latestBuild: 1,
  minSupportedVersion: '0.0.0',
  minSupportedBuild: 0,
  forceUpdate: false,
  maintenance: false,
  messageAr: null,
  storeUrl: null,
  checkedAt: new Date().toISOString(),
};

describe('useWebReleasePolicy — localPolicy schema validation', () => {
  it('localPolicy parses against publicReleasePolicySchema', () => {
    expect(() => publicReleasePolicySchema.parse(localPolicy)).not.toThrow();
  });

  it('action is a valid enum value', () => {
    const actions = ['none', 'update_available', 'update_required', 'maintenance', 'blocked'] as const;
    for (const action of actions) {
      expect(() => publicReleasePolicySchema.parse({ ...localPolicy, action })).not.toThrow();
    }
  });

  it('platform is web', () => {
    const parsed = publicReleasePolicySchema.parse(localPolicy);
    expect(parsed.platform).toBe('web');
  });

  it('environment is a valid enum value', () => {
    const environments = ['development', 'staging', 'production'] as const;
    for (const environment of environments) {
      expect(() => publicReleasePolicySchema.parse({ ...localPolicy, environment })).not.toThrow();
    }
  });

  it('version strings are non-empty', () => {
    const parsed = publicReleasePolicySchema.parse(localPolicy);
    expect(parsed.currentVersion.length).toBeGreaterThan(0);
    expect(parsed.latestVersion.length).toBeGreaterThan(0);
    expect(parsed.minSupportedVersion.length).toBeGreaterThan(0);
  });

  it('build numbers are non-negative integers', () => {
    const parsed = publicReleasePolicySchema.parse(localPolicy);
    expect(parsed.currentBuild).toBeGreaterThanOrEqual(0);
    expect(parsed.latestBuild).toBeGreaterThanOrEqual(0);
    expect(parsed.minSupportedBuild).toBeGreaterThanOrEqual(0);
  });

  it('forceUpdate and maintenance are booleans', () => {
    const parsed = publicReleasePolicySchema.parse(localPolicy);
    expect(typeof parsed.forceUpdate).toBe('boolean');
    expect(typeof parsed.maintenance).toBe('boolean');
  });

  it('messageAr and storeUrl are nullable', () => {
    expect(() =>
      publicReleasePolicySchema.parse({ ...localPolicy, messageAr: null, storeUrl: null }),
    ).not.toThrow();
  });

  it('checkedAt is a valid ISO timestamp', () => {
    const parsed = publicReleasePolicySchema.parse(localPolicy);
    expect(new Date(parsed.checkedAt).getTime()).not.toBeNaN();
  });

  it('schema rejects invalid action', () => {
    expect(() =>
      publicReleasePolicySchema.parse({ ...localPolicy, action: 'invalid' }),
    ).toThrow();
  });

  it('schema rejects invalid platform', () => {
    expect(() =>
      publicReleasePolicySchema.parse({ ...localPolicy, platform: 'desktop' }),
    ).toThrow();
  });

  it('schema rejects negative build number', () => {
    expect(() =>
      publicReleasePolicySchema.parse({ ...localPolicy, currentBuild: -1 }),
    ).toThrow();
  });
});
