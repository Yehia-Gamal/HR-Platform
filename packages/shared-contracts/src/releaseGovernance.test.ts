import { describe, expect, it } from 'vitest';
import { publicReleasePolicySchema, releaseGovernanceCatalogSchema } from './releaseGovernance.js';

const id = '10000000-0000-4000-8000-000000000001';

describe('release governance contracts', () => {
  it('parses a forced update policy', () => {
    const value = publicReleasePolicySchema.parse({
      action: 'update_required', platform: 'android', environment: 'production',
      currentVersion: '0.8.0', currentBuild: 8, latestVersion: '0.9.0', latestBuild: 9,
      minSupportedVersion: '0.9.0', minSupportedBuild: 9, forceUpdate: true,
      maintenance: false, messageAr: 'حدث التطبيق', storeUrl: null, checkedAt: new Date().toISOString(),
    });
    expect(value.action).toBe('update_required');
  });

  it('parses an empty governance catalog', () => {
    const value = releaseGovernanceCatalogSchema.parse({
      policies: [], devices: [], accessReviews: [], reviewItems: [], breakGlass: [], privacyRequests: [],
      outbox: { pending: 0, failed: 0, delivered: 0, oldestPendingAt: null }, roles: [], users: [], lastUpdatedAt: new Date().toISOString(),
    });
    expect(value.outbox.pending).toBe(0);
  });
});
