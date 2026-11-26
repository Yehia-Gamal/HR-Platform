// @vitest-environment node
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = resolve(import.meta.dirname, '../../../../..');

function walkFiles(dir: string, extRe: RegExp): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (name === '__tests__' || name === 'node_modules' || name === 'build') continue;
      out.push(...walkFiles(full, extRe));
    } else if (extRe.test(name) && !/\.test\.[cm]?[jt]sx?$/.test(name)) {
      out.push(full);
    }
  }
  return out;
}

function collectDbPermissions(): Set<string> {
  const perms = new Set<string>();
  const dirs = [join(root, 'supabase', 'migrations'), join(root, 'supabase', 'seed')];
  const re = /'([a-z0-9_]+(?:\.[a-z0-9_]+)+)'/g;
  for (const dir of dirs) {
    for (const file of readdirSync(dir)) {
      if (!file.endsWith('.sql')) continue;
      const src = readFileSync(join(dir, file), 'utf8');
      for (const m of src.matchAll(re)) perms.add(m[1]);
    }
  }
  return perms;
}

describe('أكواد الصلاحيات في الواجهة والتطبيق', () => {
  it('كل كود صلاحية مستخدم في admin_web وmobile_flutter موجود في قاعدة البيانات', () => {
    const dbPerms = collectDbPermissions();
    const missing: string[] = [];

    const webFiles = walkFiles(join(root, 'apps', 'admin_web', 'src'), /\.(?:ts|tsx)$/);
    const webPatterns = [
      /hasPermission\([^,]+,\s*'([^']+)'\)/g,
      /hasAnyPermission\([^,]+,\s*(\[[^\]]+\]|'[^']+')\)/gs,
      /perm=\{?(\[[^\]]+\]|'[^']+'|"[^"]+")\}?/gs,
      /permission:\s*(\[[^\]]+\]|'[^']+')/gs,
    ];
    for (const file of webFiles) {
      const src = readFileSync(file, 'utf8');
      for (const pat of webPatterns) {
        for (const m of src.matchAll(pat)) {
          for (const strMatch of m[1].matchAll(/'([^']+)'|"([^"]+)"/g)) {
            const code = strMatch[1] || strMatch[2];
            if (code && code.includes('.') && !code.startsWith('auth.') && !dbPerms.has(code)) {
              missing.push(`web:${code} (${file.replace(root, '')})`);
            }
          }
        }
      }
    }

    const mobileFiles = walkFiles(join(root, 'apps', 'mobile_flutter', 'lib'), /\.dart$/);
    const mobilePat = /hasPermission\(\s*'([^']+)'/g;
    for (const file of mobileFiles) {
      const src = readFileSync(file, 'utf8');
      for (const m of src.matchAll(mobilePat)) {
        const code = m[1];
        if (!dbPerms.has(code)) {
          missing.push(`mobile:${code} (${file.replace(root, '')})`);
        }
      }
    }

    expect(missing).toEqual([]);
  });
});
