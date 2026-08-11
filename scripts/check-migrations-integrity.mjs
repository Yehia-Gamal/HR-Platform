#!/usr/bin/env node
/* فاحص سلامة migrations — يكشف التكرار والفجوات والplaceholder غير الموثق. */
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

const MIGRATIONS_DIR = path.resolve(process.cwd(), 'supabase', 'migrations');
const PARKING_DIRS = [
  path.resolve(process.cwd(), 'supabase', 'migrations', '_v23_parking'),
  path.resolve(process.cwd(), '_v23_parking'),
];
const REGISTRY_FILE = path.resolve(process.cwd(), 'MIGRATION_REGISTRY.md');

const ACCEPTABLE_GAPS = new Set([
  // 0267 → أُعيد ترقيمه إلى 0277 (fix_deep_link_action_routing) ضمن إعادة
  // ترتيب سلسلة الحضور/العمليات؛ محتواه موجود في 0277.
  267,
  // 0279 → رقم مُتخطَّى مقصودًا بين 0278 و0280 (مساحة احتياطية).
  279,
  // 0314 → seed صلاحيات المراقبة؛ نُقل إلى 0322 ثم إلى 0327 ضمن إعادة الترتيب.
  //         التنفيذ الفعلي في 0327، و0322 صار placeholder بلا عمليات.
  314,
]);
const BRIDGE_FILENAMES = new Set([
  '0119_bridge_placeholder.sql',
  '0122_bridge_placeholder.sql',
  '0194_placeholder.sql',
  '0219_placeholder_sequence_fix.sql',
  '0231_bridge_placeholder.sql',
  '0232_bridge_placeholder.sql',
  // 0270-0276 → جسور ترقيم أثناء إعادة هيكلة سلسلة الحضور (تُملأ تباعًا).
  '0270_bridge_placeholder.sql',
  '0271_bridge_placeholder.sql',
  '0272_bridge_placeholder.sql',
  '0273_bridge_placeholder.sql',
  '0274_bridge_placeholder.sql',
  '0275_bridge_placeholder.sql',
  '0276_bridge_placeholder.sql',
  // 0297-0300 → جسور ترقيم أثناء أعمال الدمج (deep-link + attendance fixes).
  '0297_bridge_placeholder.sql',
  '0298_bridge_placeholder.sql',
  '0299_bridge_placeholder.sql',
  '0300_bridge_placeholder.sql',
  // 0302, 0304 → جسور احتياطية بين 0301/0303 و 0303/0305 أثناء إعادة ترتيب KPI/storage.
  '0302_bridge_placeholder.sql',
  '0304_bridge_placeholder.sql',
  // 0365 → جسر بين 0364 (account semantics) و 0366 (delegation).
  '0365_bridge_placeholder.sql',
  // 0370 → جسر بين 0369 (excused_absent fix) و 0371 (device_auto_accept)
  //         نتيجة إعادة ترقيم migrations متعارضة من جلسات متوازية.
  '0370_bridge_placeholder.sql',
  // 0377 → كان مكرراً مع 0357_device_auto_accept_registration، حُذف وأُضيف placeholder للحفاظ على التسلسل.
  '0377_placeholder.sql',
]);

const FILE_RE = /^(\d{4})_([a-z0-9][a-z0-9_]*)\.sql$/i;

function fail(msg, code = 'MIGRATION_INTEGRITY') {
  console.error(`✗ [${code}] ${msg}`);
  process.exitCode = 1;
}

function main() {
  if (!existsSync(MIGRATIONS_DIR)) {
    fail(`مجلد migrations غير موجود: ${MIGRATIONS_DIR}`);
    process.exit(1);
  }

  const entries = readdirSync(MIGRATIONS_DIR, { withFileTypes: true });
  const sqlFiles = entries.filter((e) => e.isFile() && e.name.endsWith('.sql')).map((e) => e.name).sort();

  let errors = 0;
  const seenNumbers = new Map();
  const numbers = [];

  for (const file of sqlFiles) {
    const match = FILE_RE.exec(file);
    if (!match) {
      fail(`اسم ملف غير مkíف: "${file}" — يجب NNNN_snake_case.sql`);
      errors += 1;
      continue;
    }
    const num = parseInt(match[1], 10);
    numbers.push(num);

    if (seenNumbers.has(num)) {
      fail(`تكرار رقم migration ${match[1]}:\n  - ${seenNumbers.get(num)}\n  - ${file}\nالحل: انقل الأحدث إلى _v23_parking/ وأعد ترقيمه عبر Integration Lead.`, 'DUPLICATE_MIGRATION');
      errors += 1;
    } else {
      seenNumbers.set(num, file);
    }

    if (file.includes('placeholder') && !BRIDGE_FILENAMES.has(file)) {
      fail(`ملف placeholder غير متوقع: ${file} — إما املأه أو احذفه، أو وثّقه جسر ترقيم في BRIDGE_FILENAMES`, 'PLACEHOLDER');
      errors += 1;
    }
  }

  const sorted = [...new Set(numbers)].sort((a, b) => a - b);
  if (sorted.length > 0) {
    const minNum = sorted[0];
    const maxNum = sorted[sorted.length - 1];
    for (let n = minNum; n <= maxNum; n += 1) {
      if (!seenNumbers.has(n) && !ACCEPTABLE_GAPS.has(n)) {
        fail(`فجوة في التسلسل: لا يوجد migration ${String(n).padStart(4, '0')}`, 'GAP');
        errors += 1;
      }
    }
  }

  for (const park of PARKING_DIRS) {
    if (existsSync(park)) {
      const parked = readdirSync(park).filter((f) => f.endsWith('.sql'));
      if (parked.length > 0) {
        console.warn(`⚠ [PARKING] ${parked.length} ملف(ات) معلقة في ${path.relative(process.cwd(), park)}: ${parked.join(', ')}`);
      }
    }
  }

  if (!existsSync(REGISTRY_FILE)) {
    fail(`MIGRATION_REGISTRY.md غير موجود`);
    errors += 1;
  }

  if (errors > 0) {
    console.error(`\n✗ فشل فحص سلامة migrations: ${errors} خطأ.`);
    process.exit(1);
  }
  console.log(`✓ سلامة migrations: ${sqlFiles.length} ملف، أرقام ${String(sorted[0]).padStart(4, '0')}–${String(sorted[sorted.length-1]).padStart(4, '0')}، بلا تكرار أو فجوات.`);
}
main();
