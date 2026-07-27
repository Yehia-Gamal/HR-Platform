import { defineWorkspace } from 'vitest/config';

export default defineWorkspace([
  {
    extends: './apps/admin_web/vite.config.ts',
    test: {
      name: 'admin-web',
      root: './apps/admin_web',
      include: ['src/**/*.test.{ts,tsx}'],
      exclude: ['**/node_modules/**', '**/.claude/**', '**/e2e/**'],
    },
  },
  {
    test: {
      name: 'shared-contracts',
      root: './packages/shared-contracts',
      include: ['src/**/*.test.ts'],
      exclude: ['**/node_modules/**', '**/.claude/**'],
    },
  },
]);
