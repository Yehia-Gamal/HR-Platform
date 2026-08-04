import { defineConfig, devices } from '@playwright/test';
import { fileURLToPath } from 'node:url';

const webRoot = fileURLToPath(new URL('.', import.meta.url));
const playwrightPort = process.env.PLAYWRIGHT_PORT || '4173';
const playwrightUrl = `http://127.0.0.1:${playwrightPort}`;

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
  reporter: process.env.CI ? 'github' : 'html',
  timeout: 30_000,

  use: {
    baseURL: process.env.BASE_URL || playwrightUrl,
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
    command: `npm run dev -- --host 127.0.0.1 --port ${playwrightPort} --strictPort`,
    url: playwrightUrl,
    cwd: webRoot,
    reuseExistingServer: false,
    timeout: 120_000,
    env: {
      VITE_ENABLE_DEV_MOCKS: 'true',
      VITE_APP_ENVIRONMENT: 'development',
    },
  },
});
