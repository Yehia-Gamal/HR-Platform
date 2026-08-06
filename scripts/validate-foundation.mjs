import { readFile, readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const required = [
  'apps/admin_web/src/main.tsx',
  'apps/mobile_flutter/lib/main.dart',
  'packages/shared-contracts/src/access.ts',
  'supabase/migrations/0013_foundation_access_and_provisioning.sql',
  'supabase/functions/admin-create-employee/index.ts',
  'supabase/tests/0002_foundation_contracts.sql',
];

for (const relative of required) {
  const info = await stat(join(root, relative));
  if (!info.isFile()) throw new Error(`Missing required file: ${relative}`);
}

const migrations = (await readdir(join(root, 'supabase/migrations')))
  .filter((name) => /^\d{4}_.+\.sql$/.test(name))
  .sort();

// فجوات مقصودة موثقة (مطابقة لـ check-migrations-integrity.mjs):
// 0267 → أعيد ترقيمه إلى 0277؛ 0279 → رقم متخطى احتياطيًا.
const ACCEPTABLE_GAPS = new Set([267, 279]);

let expected = 1;
for (const file of migrations) {
  while (ACCEPTABLE_GAPS.has(expected)) expected += 1;
  const prefix = String(expected).padStart(4, '0');
  if (!file.startsWith(prefix)) {
    throw new Error(`Migration sequence gap: expected ${prefix}, found ${file}`);
  }
  expected += 1;
}

const appFiles = [
  ...(await readdir(join(root, 'apps/admin_web/src'), { recursive: true }))
    .filter((name) => /\.(ts|tsx)$/.test(name))
    .map((name) => join(root, 'apps/admin_web/src', name)),
];
for (const path of appFiles) {
  const source = await readFile(path, 'utf8');
  if (/SERVICE_ROLE|service_role_key/i.test(source)) {
    throw new Error(`Service-role reference found in client app: ${path}`);
  }
}

console.log(`Foundation structure valid: ${migrations.length} sequential migrations.`);
