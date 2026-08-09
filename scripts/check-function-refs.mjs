#!/usr/bin/env node
/* فاحص مراجع الدوال — يكشف أعمدة/جداول غير موجودة تُشار إليها داخل دوال migrations.
 *
 * يكتشف بالضبط فئة الأعطال التي كسرت get_employee_360 ثلاث مرات:
 *   - مرجع عمود غير موجود: manager_rel.manager_employee_id، ed.job_title_id، ed.is_active
 *   - مرجع عمود قديم: tasks.assigned_to بدل assignee_employee_id
 *   - جدول غير موجود في FROM/JOIN
 *
 * المنهجية:
 *   - يُستخرج من كل migration تعريفات الدوال (AS $delim ... $delim).
 *   - عند تكرار تعريف لدالة بنفس التوقيع، تَعُدّ التعريف الأخير فقط (الواقع النهائي).
 *   - يُحلّل أسماء الاستعارة (alias) → جدول من جمل FROM/JOIN + جمل الفرعية (SELECT * FROM x) y.
 *   - يفحص مراجع alias.column مقابل سكيما فعلية مأخوذة من الـ DB المحلي (information_schema).
 *   - أسماء استعارة غير قابلة للحل (CTEs، subquery معقدة، متغيرات record) → تحذير لا خطأ.
 *
 * يُشغّل بـ: node scripts/check-function-refs.mjs
 * يتطلب حاوية supabase المحلية (docker) للحصول على السكيما؛ إن غابت يُتجاوز بتحذير.
 */
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname ?? process.cwd(), '..');
const MIGRATIONS_DIR = path.join(ROOT, 'supabase', 'migrations');
const SCHEMAS = ['public', 'auth', 'storage', 'cron'];
const FILE_RE = /^(\d{4})_([a-z0-9][a-z0-9_]*)\.sql$/i;

let errors = 0;
let warnings = 0;
let checkedFunctions = 0;

function fail(msg) { console.error(`✗ ${msg}`); errors += 1; }
function warn(msg) { console.warn(`⚠ ${msg}`); warnings += 1; }

/* ---------- الحصول على السكيما الفعلية من الـ DB المحلي ---------- */
function dumpSchema() {
  let containers = [];
  try {
    const out = execFileSync('docker', ['ps', '--filter', 'name=supabase_db', '--format', '{{.Names}}'], { encoding: 'utf8' });
    containers = out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch { /* docker غير متاح */ }
  if (containers.length === 0) {
    warn('حاوية supabase غير متاحة — تَجاوز فحص المراجع (شغّل الـ stack للتفعيل)');
    return null;
  }
  const container = containers[0];
  const cols = new Map(); // "schema.table" (منخفض) -> Set<column> (منخفض)
  const q = `select lower(quote_ident(n.nspname))||'.'||lower(quote_ident(c.relname)), lower(a.attname)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid
    where n.nspname in ('${SCHEMAS.join("','")}')
      and c.relkind in ('r','v','m','p')
      and a.attnum > 0 and not a.attisdropped`;
  try {
    const out = execFileSync(
      'docker',
      ['exec', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-t', '-A', '-F', '|', '-c', q],
      { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 },
    );
    for (const line of out.split('\n')) {
      const idx = line.indexOf('|');
      if (idx <= 0) continue;
      const table = line.slice(0, idx).trim().toLowerCase();
      const col = line.slice(idx + 1).trim().toLowerCase();
      if (!col) continue;
      if (!cols.has(table)) cols.set(table, new Set());
      cols.get(table).add(col);
    }
  } catch (e) {
    warn(`تعذّر قراءة السكيما الفعلية: ${e.message}`);
  }
  return { container, cols };
}

/* ---------- استخراج تعريفات الدوال من ملف migration ---------- */
function extractFunctions(content) {
  const funcs = [];
  const re = /\bcreate\s+(?:or\s+replace\s+)?function\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)\s*\([\s\S]*?\)\s+returns[\s\S]*?\bas\s+(\$[a-z_0-9]*\$)([\s\S]*?)\2/gi;
  let m;
  while ((m = re.exec(content)) !== null) {
    funcs.push({
      signature: m[1].toLowerCase(),
      body: m[3],
      offset: m.index,
    });
  }
  return funcs;
}

function lineOf(content, offset) {
  return content.slice(0, offset).split('\n').length;
}

/* ---------- استخراج خريطة alias → table داخل جسم دالة ---------- */
const SQL_KEYWORDS = new Set([
  'select','from','where','join','left','right','full','inner','outer','cross','natural','lateral',
  'on','using','group','having','order','by','limit','offset','fetch','for','union','all','except',
  'intersect','values','returning','set','as','and','or','not','null','is','in','like','between',
  'exists','case','when','then','else','end','distinct','window','filter','over','asc','desc',
]);

function extractAliases(body) {
  const aliases = new Map();       // alias -> table
  const ctes = new Set();          // أسماء CTEs — جداول افتراضية داخل الدالة
  const virtualAliases = new Set(); // أسماء استعارة جمل فرعية (غير محلولة لجدول)
  const ambiguous = new Set();     // أسماء استعارة لجداول مختلفة في نفس الدالة
  const setAlias = (a, t) => {
    const k = a.toLowerCase(), v = t.toLowerCase();
    if (aliases.has(k) && aliases.get(k) !== v) { ambiguous.add(k); aliases.delete(k); return; }
    aliases.set(k, v);
  };

  // أسماء CTEs: WITH [RECURSIVE] name [cols] AS ( ... ), name2 AS ( ... )
  const cteRe = /\bwith\s+(?:recursive\s+)?([a-z_][a-z0-9_]*)(?:\s*\([^)]*\))?\s+as\s*\(|,\s*([a-z_][a-z0-9_]*)(?:\s*\([^)]*\))?\s+as\s*\(/gi;
  let cm;
  while ((cm = cteRe.exec(body)) !== null) {
    const name = (cm[1] || cm[2] || '').toLowerCase();
    if (name) ctes.add(name);
  }

  // أعمدة إخراج جملة فرعية من قائمة SELECT (أسماء الأعمدة المركّبة/المحسوبة)
  function subqueryColumns(text) {
    const sel = /\bselect\b([\s\S]*?)\bfrom\b/i.exec(text);
    if (!sel) return null;
    const cols = new Set();
    for (const part of sel[1].split(',')) {
      const p = part.trim();
      if (!p) continue;
      const asM = /(?:as\s+)?([a-z_][a-z0-9_]*)\s*$/i.exec(p);
      if (asM) cols.add(asM[1].toLowerCase());
    }
    return cols.size > 0 ? cols : null;
  }
  // إيجاد ( المطابقة لـ ) عند closeIdx (وعي أقواس)
  function matchOpen(text, closeIdx) {
    let depth = 0;
    for (let i = closeIdx; i >= 0; i--) {
      if (text[i] === ')') depth += 1;
      else if (text[i] === '(') { depth -= 1; if (depth === 0) return i; }
    }
    return -1;
  }

  // أسماء استعارة الجمل الفرعية: ) alias يليه سطر جديد أو JOIN/WHERE...
  const virtualTables = new Map(); // alias -> Set(أعمدة) لجملة فرعية
  const subGuesses = new Map();    // alias -> تخمين جدول من داخل الجملة (يُستبدل بـ FROM/JOIN الصريح)
  const subAliasRe = /\)\s+(?:as\s+)?([a-z_][a-z0-9_]*)(?=\s*(?:[\r\n]|\b(?:join|left|right|full|inner|cross|where|group|having|union|limit|on)\b))/gi;
  let sa;
  while ((sa = subAliasRe.exec(body)) !== null) {
    const alias = sa[1].toLowerCase();
    if (SQL_KEYWORDS.has(alias)) continue;
    if (aliases.has(alias) || virtualTables.has(alias) || virtualAliases.has(alias)) continue;
    const open = matchOpen(body, sa.index);
    const inner = open >= 0 ? body.slice(open + 1, sa.index) : null;
    const cols = inner ? subqueryColumns(inner) : null;
    if (cols) { virtualTables.set(alias, cols); continue; }
    // بديل: فكّ `select *` / `select alias.*` — الجملة ترث أعمدة جدولها الداخلي
    if (inner) {
      const tjIn = /\b(?:from|join)\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)(?:\s+(?:as\s+)?([a-z_][a-z0-9_]*))?\b/gi;
      const froms = [];
      let tm;
      while ((tm = tjIn.exec(inner)) !== null) {
        froms.push({ table: tm[1], alias: (tm[2] || tm[1].split('.').pop()).toLowerCase() });
      }
      const selList = /\bselect\b([\s\S]*?)\bfrom\b/i.exec(inner);
      let target = null;
      if (selList) {
        const firstItem = selList[1].trim().split(',')[0];
        if (firstItem === '*') {
          target = froms[0] ? froms[0].table : null;
        } else {
          const qa = /^\s*([a-z_][a-z0-9_]*)\s*\.\s*\*\s*$/i.exec(firstItem);
          if (qa) {
            const fa = froms.find((f) => f.alias === qa[1].toLowerCase());
            target = fa ? fa.table : null;
          }
        }
      }
      if (target && !ctes.has(target.toLowerCase()) && !virtualTables.has(target.toLowerCase())) {
        subGuesses.set(alias, target.toLowerCase());
        continue;
      }
      const last = froms.length > 0 ? froms[froms.length - 1].table : null;
      if (last && !ctes.has(last.toLowerCase()) && !virtualTables.has(last.toLowerCase())) {
        subGuesses.set(alias, last.toLowerCase());
        continue;
      }
    }
    virtualAliases.add(alias);
  }

  // FROM/JOIN [schema.]table [as] alias
  const tjRe = /\b(from|join)\s+(lateral\s+)?((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)(?:\s+(?:as\s+)?([a-z_][a-z0-9_]*))?\b/gi;
  let t;
  while ((t = tjRe.exec(body)) !== null) {
    if (t[1] === 'from') {
      const prefix = body.slice(Math.max(0, t.index - 25), t.index);
      if (/(?:distinct|except)\s*$/i.test(prefix)) continue; // "is distinct from" — ليس مصدر جدول
    }
    const table = t[3];
    let alias = t[4];
    if (!alias || SQL_KEYWORDS.has(alias.toLowerCase())) {
      const after = body.slice(tjRe.lastIndex);
      if (/^\s*\(/.test(after)) continue; // FROM unnest(...) — دالة سطرية
      alias = table.split('.').pop();     // بدون alias صريح: اسم الجدول نفسه
    }
    setAlias(alias, table); // FROM/JOIN الصريح ملزم
  }
  // تخمينات الجمل الفرعية تُطبَّق فقط للأسماء غير المحلولة بعد؛
  // تعارض مع FROM/JOIN صريح لنفس الاسم = تصادم نطاق (نفس الاسم في جملتين مختلفتين) → غامض
  for (const [a, t] of subGuesses) {
    if (aliases.has(a)) {
      if (aliases.get(a) !== t && !ambiguous.has(a)) { ambiguous.add(a); aliases.delete(a); }
      continue;
    }
    if (!ambiguous.has(a)) setAlias(a, t);
  }
  return { aliases, ctes, virtualAliases, virtualTables, ambiguous };
}

/* ---------- جمع أسماء متغيرات record المعلنة ---------- */
function recordVars(body) {
  const vars = new Set();
  const decl = /\bdeclare\b([\s\S]*?)\bbegin\b/i.exec(body);
  if (decl) {
    const re = /^(\w+)\s+\w+/gm;
    let m;
    while ((m = re.exec(decl[1])) !== null) vars.add(m[1].toLowerCase());
  }
  // متغيرات حلقات FOR ... IN (سجلات/صفوف)
  const forRe = /\bfor\s+([a-z_][a-z0-9_]*)\s+in\b/gi;
  let fm;
  while ((fm = forRe.exec(body)) !== null) vars.add(fm[1].toLowerCase());
  return vars;
}

/* ---------- تجهيز جسم الدالة للتحليل ---------- */
function prepBody(body) {
  return body
    .replace(/--[^\n\r]*/g, ' ')       // تعليقات سطرية
    .replace(/\/\*[\s\S]*?\*\//g, ' ') // تعليقات كتلية
    .replace(/'[^']*'/g, "' '");       // قناع النصوص الحرفية (أذونات/مسارات GUC)
}

/* ---------- فحص مراجع alias.column ---------- */
function checkRefs(content, func, tableCols) {
  const body = prepBody(func.body);
  const { aliases, ctes, virtualAliases, virtualTables, ambiguous } = extractAliases(body);
  const records = recordVars(body);
  const unresolved = new Map(); // alias -> عدد المراجع

  const refRe = /([a-z_][a-z0-9_]*)\s*\.\s*([a-z_][a-z0-9_]*)/gi;
  let m;
  while ((m = refRe.exec(body)) !== null) {
    const left = m[1].toLowerCase();
    const right = m[2].toLowerCase();
    const after = body.slice(refRe.lastIndex);

    // استدعاء دالة schema.func( — ليس مرجع عمود
    if (/^\s*\(/.test(after)) continue;

    // متغير record: v_employee.updated_at
    if (left.startsWith('v_') || left === 'new' || left === 'old' || left === 'excluded' || records.has(left)) continue;

    // schema.table (مثل public.tasks) — ليس alias.column
    if (['public', 'auth', 'storage', 'cron', 'pg_temp', 'extensions', 'pg_catalog', 'information_schema'].includes(left)) continue;

    // جدول افتراضي معروف (CTE / جملة فرعية)
    if (ctes.has(left) || virtualAliases.has(left)) continue;

    const table = aliases.get(left);
    if (!table || ambiguous.has(left)) {
      unresolved.set(left, (unresolved.get(left) || 0) + 1);
      continue;
    }
    const tableKey = table.toLowerCase();
    // جملة فرعية ذات أعمدة محسوبة (مثلاً x.decision_id)
    if (virtualTables.has(tableKey)) {
      const vcols = virtualTables.get(tableKey);
      if (!vcols.has(right)) {
        fail(`${func.file}:${func.line} عمود غير موجود "${left}.${right}" في الجملة الفرعية "${tableKey}" (في ${func.signature})`);
      }
      continue;
    }
    if (ctes.has(tableKey)) continue; // جدول CTE افتراضي داخل الدالة
    if (tableKey.startsWith('pg_')) continue; // جداول كتالوج النظام (pg_catalog)
    const cols = tableCols.get(tableKey);
    if (!cols) {
      const qualified = table.includes('.');
      const msg = `جدول غير موجود "${table}" يُشار إليه عبر "${left}.${right}" (في ${func.signature})`;
      if (qualified) fail(`${func.file}:${func.line} ${msg}`);
      else warn(`${func.file}:${func.line} ${msg} (قد يكون CTE/منظر غير محلول)`);
      continue;
    }
    if (!cols.has(right)) {
      fail(`${func.file}:${func.line} عمود غير موجود "${left}.${right}" في الجدول "${table}" (في ${func.signature})`);
    }
  }

  for (const [a, n] of unresolved) {
    warn(`${func.file}:${func.line} استعارة غير قابلة للحل "${a}.*" (${n} مرجع) — راجع يدوياً`);
  }

  // فحص أعمدة INSERT INTO table(col,...)
  const insRe = /\binsert\s+into\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)\s*\(([^)]*)\)/gi;
  let im;
  while ((im = insRe.exec(body)) !== null) {
    const table = im[1].toLowerCase();
    const cols = tableCols.get(table);
    if (!cols) continue; // view/غير معروف
    for (const c of im[2].split(',').map((s) => s.trim().toLowerCase()).filter(Boolean)) {
      if (!cols.has(c)) fail(`${func.file}:${func.line} عمود غير موجود في INSERT INTO ${table}: "${c}" (في ${func.signature})`);
    }
  }
}

/* ---------- رئيسي ---------- */
function main() {
  if (!existsSync(MIGRATIONS_DIR)) { console.error(`✗ ${MIGRATIONS_DIR} غير موجود`); process.exit(1); }
  const schema = dumpSchema();
  if (!schema) { process.exit(0); }

  const files = readdirSync(MIGRATIONS_DIR, { withFileTypes: true })
    .filter((e) => e.isFile() && FILE_RE.test(e.name))
    .map((e) => e.name)
    .sort();

  // آخر تعريف لكل توقيع دالة (التعريفات الوسيطة تُستبدل لاحقاً)
  const finalDefs = new Map();
  for (const file of files) {
    const content = readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    for (const f of extractFunctions(content)) {
      f.file = file;
      f.line = lineOf(content, f.offset);
      finalDefs.set(f.signature, f); // الأخير يغلب
    }
  }

  for (const f of finalDefs.values()) {
    checkedFunctions += 1;
    checkRefs(readFileSync(path.join(MIGRATIONS_DIR, f.file), 'utf8'), f, schema.cols);
  }

  console.log(`✓ فحص مراجع الدوال: ${checkedFunctions} دالة نهائية، ${files.length} migration — ${errors === 0 ? 'بلا أخطاء مراجع' : errors + ' خطأ'}.`);
  if (warnings > 0) console.warn(`⚠ ${warnings} تحذير(ات) غير حاسمة.`);
  if (errors > 0) { console.error(`\n✗ فشل فحص المراجع: ${errors} خطأ.`); process.exit(1); }
}
main();
