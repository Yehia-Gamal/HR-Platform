import { defineConfig, devices } from '@playwright/test';
import { fileURLToPath } from 'node:url';

const webRoot = fileURLToPath(new URL('.', import.meta.url));
const playwrightPort = process.env.PLAYWRIGHT_PORT || '4173';
const playwrightUrl = `http://127.0.0.1:${playwrightPort}`;
const browserChannel = process.env.PLAYWRIGHT_CHROMIUM_CHANNEL;

/**
 * Playwright E2E configuration — أحلى شباب HR
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['html', { open: 'never' }]],
  timeout: 60_000,

  use: {
    baseURL: playwrightUrl,
    channel: browserChannel,
    serviceWorkers: 'block',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    locale: 'ar',
    timezoneId: 'Africa/Cairo',
  },

  projects: [
    {
      name: 'chromium-desktop',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 7'] },
    },
  ],

  /* Start the same isolated test server locally and in CI. */
  webServer: {
    command: `npm run build --workspace @ahla/shared-contracts && npm exec -- vite build --outDir dist-e2e && npm run preview -- --outDir dist-e2e --host 127.0.0.1 --port ${playwrightPort} --strictPort`,
    url: playwrightUrl,
    cwd: webRoot,
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      VITE_SUPABASE_URL: 'https://supabase.e2e.invalid',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'e2e-publishable-key',
      VITE_SENTRY_DSN: '',
    },
  },
});
