#!/usr/bin/env node

/**
 * Release Gate — أحلى شباب HR
 *
 * يتحقق من جميع شروط الإصدار قبل النشر.
 * Usage: node scripts/release-gate.mjs [--strict]
 *
 * Exit codes:
 *   0 = كل الشروط الإلزامية تحققت
 *   1 = فشل شرط إلزامي واحد أو أكثر
 */

import { execSync } from 'node:child_process';
import { readdirSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const STRICT = process.argv.includes('--strict');
const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Z]:)/, '$1');

let passed = 0;
let failed = 0;
let warned = 0;

function check(name, fn, required = true) {
  try {
    const result = fn();
    if (result === true || result === undefined) {
      console.log(`✅ ${name}`);
      passed++;
    } else {
      throw new Error(String(result));
    }
  } catch (err) {
    if (required) {
      console.error(`❌ [P0] ${name}: ${err.message}`);
      failed++;
    } else {
      console.warn(`⚠️  [P1] ${name}: ${err.message}`);
      warned++;
    }
  }
}

function run(cmd, opts = {}) {
  return execSync(cmd, {
    cwd: ROOT,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
    timeout: 300_000,
    ...opts,
  }).trim();
}

console.log('╔══════════════════════════════════════════════╗');
console.log('║   Release Gate — أحلى شباب HR              ║');
console.log('╚══════════════════════════════════════════════╝');
console.log();

// ━━━━━━━━━━━━━━━━━━━━ P0: الشروط الإلزامية ━━━━━━━━━━━━━━━━━━━━

console.log('── P0: الشروط الإلزامية ──\n');

// 1. تكرار أرقام Migrations
check('لا تكرار في أرقام Migrations', () => {
  const migrationsDir = join(ROOT, 'supabase', 'migrations');
  const files = readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const numbers = files.map((f) => f.substring(0, 4));
  const dupes = numbers.filter((n, i) => numbers.indexOf(n) !== i);
  if (dupes.length > 0) {
    throw new Error(`أرقام مكررة: ${[...new Set(dupes)].join(', ')}`);
  }
});

// 2. TypeScript typecheck
check('TypeScript typecheck', () => {
  run('npm run typecheck');
});

// 3. Web tests
check('اختبارات الويب (Vitest)', () => {
  run('npm run test');
});

// 4. Build
check('بناء الإنتاج (Vite build)', () => {
  run('npm run build');
});

// 5. Secret scan
check('فحص الأسرار', () => {
  run('npm run check:secrets');
});

// 6. Foundation validation
check('التحقق من الهيكل الأساسي', () => {
  run('node scripts/validate-foundation.mjs');
});

// 7. Dart source validation
check('التحقق من مصادر Dart', () => {
  run('npm run check:dart-source');
});

// 8. No console.log in production
check('لا console.log في كود الإنتاج', () => {
  const webSrc = join(ROOT, 'apps', 'admin_web', 'src');
  try {
    const result = run(
      `grep -rn "console\\.log" "${webSrc}" --include="*.ts" --include="*.tsx" | grep -v ".test." | grep -v "test/" | grep -v "node_modules" | head -5`
    );
    if (result) {
      throw new Error(`وُجد console.log في:\n${result}`);
    }
  } catch (e) {
    // grep returns exit code 1 when no matches — that's success
    if (e.status === 1) return true;
    throw e;
  }
});

// ━━━━━━━━━━━━━━━━━━━━ P1: الشروط المهمة ━━━━━━━━━━━━━━━━━━━━

console.log('\n── P1: الشروط المهمة ──\n');

// 9. Flutter analyze
check(
  'Flutter analyze',
  () => {
    run('flutter analyze --no-fatal-infos', {
      cwd: join(ROOT, 'apps', 'mobile_flutter'),
    });
  },
  STRICT
);

// 10. Flutter tests
check(
  'اختبارات Flutter',
  () => {
    run('flutter test', { cwd: join(ROOT, 'apps', 'mobile_flutter') });
  },
  STRICT
);

// 11. CODEOWNERS exists
check(
  'ملف CODEOWNERS موجود',
  () => {
    if (!existsSync(join(ROOT, '.github', 'CODEOWNERS'))) {
      throw new Error('ملف .github/CODEOWNERS غير موجود');
    }
  },
  STRICT
);

// 12. Migration README up to date
check(
  'README الـ Migrations موجود',
  () => {
    if (!existsSync(join(ROOT, 'supabase', 'migrations', 'README.md'))) {
      throw new Error('supabase/migrations/README.md غير موجود');
    }
  },
  STRICT
);

// 13. No TODO/FIXME/HACK in migrations
check(
  'لا TODO/FIXME في الـ Migrations',
  () => {
    const migrationsDir = join(ROOT, 'supabase', 'migrations');
    try {
      const result = run(
        `grep -rn "TODO\\|FIXME\\|HACK\\|XXX" "${migrationsDir}" --include="*.sql" | head -5`
      );
      if (result) {
        throw new Error(`وُجد TODO/FIXME:\n${result}`);
      }
    } catch (e) {
      if (e.status === 1) return true;
      throw e;
    }
  },
  STRICT
);

// ━━━━━━━━━━━━━━━━━━━━ النتيجة ━━━━━━━━━━━━━━━━━━━━

console.log('\n══════════════════════════════════════════════');
console.log(`✅ نجح: ${passed}   ❌ فشل: ${failed}   ⚠️ تحذير: ${warned}`);

if (failed > 0) {
  console.error('\n🔴 بوابة الإصدار: لم تتحقق الشروط الإلزامية');
  process.exit(1);
} else if (warned > 0) {
  console.warn('\n🟡 بوابة الإصدار: شروط إلزامية متحققة، لكن توجد تحذيرات');
  process.exit(0);
} else {
  console.log('\n🟢 بوابة الإصدار: جميع الشروط متحققة');
  process.exit(0);
}
