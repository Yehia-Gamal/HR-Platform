#!/usr/bin/env node
/* مولّد manifest — SHA-256 لكل migration (مكافح إعادة الكتابة). */
import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const MIGRATIONS_DIR = path.join(ROOT, 'supabase', 'migrations');
const OUT_DIR = path.join(ROOT, 'supabase', '.temp');
const OUT_FILE = path.join(OUT_DIR, 'migrations-manifest.json');

const FILE_RE = /^(\d{4})_([a-z0-9][a-z0-9_]*)\.sql$/i;

function sha256(buf) { return createHash('sha256').update(buf).digest('hex'); }

function main() {
  if (!existsSync(MIGRATIONS_DIR)) { console.error(`✗ ${MIGRATIONS_DIR} غير موجود`); process.exit(1); }
  if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });
  const files = readdirSync(MIGRATIONS_DIR, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.sql')).map((e) => e.name).sort();
  const manifest = { generated_at: new Date().toISOString(), count: files.length, migrations: [] };
  for (const file of files) {
    const match = FILE_RE.exec(file);
    if (!match) { console.warn(`⚠ تخطّي: ${file}`); continue; }
    const content = readFileSync(path.join(MIGRATIONS_DIR, file));
    manifest.migrations.push({
      sequence: parseInt(match[1], 10), name: match[2], file,
      sha256: sha256(content), bytes: content.byteLength,
    });
  }
  writeFileSync(OUT_FILE, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(`✓ تم توليد manifest: ${OUT_FILE} (${files.length} ملف)`);
}
main();
