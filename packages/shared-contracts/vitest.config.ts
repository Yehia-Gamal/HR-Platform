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
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      reportsDirectory: './coverage',
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'src/index.ts', 'src/**/index.ts'],
      // عتبات محافظة تحت المستوى المُقاس (97/79/91/98) بهامش آمن كي لا
      // تكسر CI، لكنها تلتقط الانحدارات الحقيقية في التغطية.
      thresholds: {
        statements: 95,
        branches: 75,
        functions: 90,
        lines: 95,
      },
    },
  },
});
