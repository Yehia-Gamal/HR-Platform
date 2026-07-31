import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 4173 },
  build: {
    rolldownOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('@supabase')) return 'supabase';
          if (id.includes('@tanstack')) return 'query';
          if (id.includes('react') || id.includes('react-router')) return 'react-vendor';
          if (id.includes('lucide-react')) return 'icons';
          if (id.includes('node_modules')) return 'vendor';
          return undefined;
        },
      },
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    css: true,
    // pool 'threads' غير المحدود يُفرط في استهلاك موارد هذا الجهاز فيسقط العامل
    // (worker timeout / semi-space OOM) ويتخطى ملفات اختبار بصمت. الحل: forks
    // مع عدد عمّال محدود + رفع كومة V8 صراحةً عبر execArgv (خيار علوي في Vitest 4،
    // إذ NODE_OPTIONS لا يتوارث عبر npm→vitest→worker).
    pool: 'forks',
    maxWorkers: 2,
    execArgv: ['--max-old-space-size=3072'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    teardownTimeout: 30_000,
    exclude: ['e2e/**', 'node_modules/**', '**/.claude/worktrees/**'],
    server: { deps: { inline: ['react-router-dom', 'react-router'] } },
  },
});
