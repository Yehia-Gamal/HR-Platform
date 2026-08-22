// حراس ضد BOM: PowerShell 5.1 يكتب UTF-8 مع BOM عبر Set-Content -Encoding UTF8
// فيكسر Deno وnode/vitest على Linux ("expected value at line 1 column 1").
// يفحص كل ملفات JSON وlock في المستودع (باستثناء المجلدات المولّدة).
import { readdir, readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const excludedDirs = new Set([
  '.git', 'node_modules', 'dist', 'build', '.dart_tool', '.idea', '.vscode',
  '.claude', 'android', 'ios',
]);
const checkedExtensions = new Set(['.json', '.lock']);

const offenders = [];

async function walk(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!excludedDirs.has(entry.name)) await walk(join(directory, entry.name));
      continue;
    }
    if (!checkedExtensions.has(extname(entry.name))) continue;
    const bytes = await readFile(join(directory, entry.name));
    if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
      offenders.push(entry.name);
    }
  }
}

await walk(root);
if (offenders.length) {
  console.error('BOM detected in (breaks Deno/node on Linux):');
  for (const f of offenders) console.error(`- ${f}`);
  console.error('Fix: [System.IO.File]::WriteAllText(path, raw) — لا تستخدم Set-Content -Encoding UTF8');
  process.exit(1);
}
console.log('BOM check passed: no UTF-8 BOM in json/lock files.');
