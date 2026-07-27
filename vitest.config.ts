import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: 'admin-web',
          root: './apps/admin_web',
          environment: 'jsdom',
          setupFiles: ['./src/test/setup.ts'],
          css: true,
          include: ['src/**/*.test.{ts,tsx}'],
        },
      },
      {
        test: {
          name: 'shared-contracts',
          root: './packages/shared-contracts',
          include: ['src/**/*.test.ts'],
        },
      },
    ],
  },
});
