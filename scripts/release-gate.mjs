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

function sourceFiles(directory, extensions) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const fullPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...sourceFiles(fullPath, extensions));
    } else if (extensions.some((extension) => entry.name.endsWith(extension))) {
      files.push(fullPath);
    }
  }
  return files;
}

function firstMatches(files, pattern, { exclude = () => false, limit = 5 } = {}) {
  const matches = [];
  for (const file of files) {
    if (exclude(file)) continue;
    const lines = readFileSync(file, 'utf8').split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      pattern.lastIndex = 0;
      if (pattern.test(lines[index])) {
        matches.push(`${file}:${index + 1}`);
        if (matches.length >= limit) return matches;
      }
    }
  }
  return matches;
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
  // The admin suite is intentionally split into bounded shards for stability
  // on Windows. Give the complete four-shard run enough time to finish.
  run('npm run test', { timeout: 900_000 });
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
  const matches = firstMatches(sourceFiles(webSrc, ['.ts', '.tsx']), /console\.log\s*\(/, {
    exclude: (file) => /(?:^|[\\/])(?:__tests__|test)(?:[\\/])|\.(?:test|spec)\.[cm]?[jt]sx?$/.test(file),
  });
  if (matches.length > 0) {
    throw new Error(`وُجد console.log في:\n${matches.join('\n')}`);
  }
});

// 9. Migration filenames, sequence, and placeholder governance
check('Migration integrity', () => {
  run('node scripts/check-migrations-integrity.mjs');
});

// ━━━━━━━━━━━━━━━━━━━━ P1: الشروط المهمة ━━━━━━━━━━━━━━━━━━━━

console.log('\n── P1: الشروط المهمة ──\n');

// 10. Flutter analyze
check(
  'Flutter analyze',
  () => {
    run('flutter analyze --no-fatal-infos', {
      cwd: join(ROOT, 'apps', 'mobile_flutter'),
    });
  },
  STRICT,
);

// 11. Flutter tests
check(
  'اختبارات Flutter',
  () => {
    run('flutter test', { cwd: join(ROOT, 'apps', 'mobile_flutter') });
  },
  STRICT,
);

// 12. CODEOWNERS exists
check(
  'ملف CODEOWNERS موجود',
  () => {
    if (!existsSync(join(ROOT, '.github', 'CODEOWNERS'))) {
      throw new Error('ملف .github/CODEOWNERS غير موجود');
    }
  },
  STRICT,
);

// 13. Migration README up to date
check(
  'README الـ Migrations موجود',
  () => {
    if (!existsSync(join(ROOT, 'supabase', 'migrations', 'README.md'))) {
      throw new Error('supabase/migrations/README.md غير موجود');
    }
  },
  STRICT,
);

// 14. No TODO/FIXME/HACK in migrations
check(
  'لا TODO/FIXME في الـ Migrations',
  () => {
    const migrationsDir = join(ROOT, 'supabase', 'migrations');
    const matches = firstMatches(sourceFiles(migrationsDir, ['.sql']), /\b(?:TODO|FIXME|HACK|XXX)\b/i);
    if (matches.length > 0) {
      throw new Error(`وُجد TODO/FIXME:\n${matches.join('\n')}`);
    }
  },
  STRICT,
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
