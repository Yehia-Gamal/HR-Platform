import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 4173 },
  build: {
    // رفع حد تحذير حجم الـ chunk لتقليل الضجيج على الحزم الكبيرة.
    chunkSizeWarningLimit: 800,
    rollupOptions: {
      output: {
        // تقسيم حزم البائعين الكبيرة إلى chunks منفصلة لتحسين التخزين المؤقت
        // وتقليل حجم الحزمة الرئيسية. الدالة تُرجع اسم الـ chunk أو undefined
        // (الذي يُتبعه rolldown تلقائيًا ضمن entry/chunk عام).
        manualChunks(id) {
          if (id.includes('@supabase')) return 'supabase';
          if (id.includes('@tanstack')) return 'query';
          if (id.includes('recharts') || id.includes('d3-') || id.includes('chart.js')) return 'charts';
          if (id.includes('react-router') || /node_modules\/(?:react|react-dom|scheduler)\//.test(id)) return 'react-vendor';
          if (id.includes('lucide-react')) return 'icons';
          if (id.includes('leaflet') || id.includes('react-leaflet')) return 'maps';
          if (id.includes('@sentry')) return 'sentry';
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
    pool: 'forks',
    // على أجهزة محدودة الموارد، إنشاء عدد كبير من الـ workers دفعةً واحدة يسبب
    // انتهاء مهلة بدء الـ worker (Timeout waiting for worker to respond) رغم نجاح
    // كل الاختبارات — نستخدم forks (بدء أكثر موثوقية من threads تحت ضغط الذاكرة)
    // مع تقييد التزامن، ونمنح البدء/الإنهاء مهلة أطول للاستقرار.
    // Vitest 4: maxWorkers أصبح خيارًا علويًا بدل poolOptions.
    maxWorkers: 3,
    // على هذا الجهاز، ملفات jsdom (~68) تستنفد كومة V8 الافتراضية وتُسقط الـ worker
    // بخطأ "Committing semi space failed / heap out of memory" (ليس فشل اختبار).
    // NODE_OPTIONS لا ينتشر عبر npm→vitest→worker المتفرّع، فنمرّر الحد عبر execArgv.
    execArgv: ['--max-old-space-size=4096'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    teardownTimeout: 30_000,
    include: ['src/**/*.test.{ts,tsx}'],
    exclude: ['e2e/**', 'node_modules/**', '**/.claude/worktrees/**'],
    server: { deps: { inline: ['react-router'] } },
  },
});
