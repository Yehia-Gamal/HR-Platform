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

for (let index = 0; index < migrations.length; index += 1) {
  const expected = String(index + 1).padStart(4, '0');
  if (!migrations[index].startsWith(expected)) {
    throw new Error(`Migration sequence gap: expected ${expected}, found ${migrations[index]}`);
  }
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
