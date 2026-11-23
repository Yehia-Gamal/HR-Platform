import type { PublicReleasePolicy } from '@ahla/shared-contracts';
import { test as base } from '@playwright/test';

export { expect } from '@playwright/test';
export const backend = 'https://supabase.e2e.invalid';

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.route(`${backend}/rest/v1/rpc/get_public_release_policy`, (route) => {
      const request = route.request().postDataJSON();
      const policy: PublicReleasePolicy = {
        action: 'none',
        platform: 'web',
        environment: request.p_environment,
        currentVersion: request.p_current_version,
        currentBuild: request.p_current_build,
        latestVersion: request.p_current_version,
        latestBuild: request.p_current_build,
        minSupportedVersion: '0.0.0',
        minSupportedBuild: 0,
        forceUpdate: false,
        maintenance: false,
        messageAr: null,
        storeUrl: null,
        checkedAt: new Date().toISOString(),
      };
      return route.fulfill({ json: policy });
    });
    await use(page);
  },
});
