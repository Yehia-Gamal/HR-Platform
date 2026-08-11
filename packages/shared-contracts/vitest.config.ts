import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    pool: 'forks',
    maxWorkers: 3,
    // NODE_OPTIONS لا ينتشر للـ worker المتفرّع — نمرّر الحد عبر execArgv.
    execArgv: ['--max-old-space-size=4096'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
