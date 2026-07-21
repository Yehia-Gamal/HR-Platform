#!/usr/bin/env node
// Data-migration dry-run validator (plan P3).
// Validates import CSVs offline — no database connection, no writes.
// Produces a per-record rejection report and a summary, per the migration rules:
//   - duplicate detection by employee_code / email / phone
//   - manager must exist in the same import (or be flagged for pre-check)
//   - role slug must be one of the seeded system roles
//   - required fields and format checks (dates, E.164 phone, email)
//
// Usage:
//   node data-migration/validate-import.mjs <employees.csv> [departments.csv]
//
// Exit codes: 0 = all records valid, 1 = rejections found, 2 = usage/file error.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';

const VALID_ROLE_SLUGS = new Set([
  'admin', 'employee', 'operations-officer', 'operations-manager',
  'direct-manager', 'department-manager', 'hr-specialist', 'hr-manager',
  'executive-secretary', 'executive-director', 'committee-member',
  'committee-chair', 'system-admin',
]);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const E164_RE = /^\+[1-9]\d{6,14}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseCsv(text) {
  // Simple CSV parser: handles quoted fields with commas and escaped quotes.
  const rows = [];
  let row = [], field = '', inQuotes = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 1; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i += 1;
      row.push(field); field = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length > 0) { row.push(field); rows.push(row); }
  const [header, ...records] = rows;
  return records.map((r) => Object.fromEntries(header.map((h, i) => [h.trim(), (r[i] ?? '').trim()])));
}

function fail(message) { console.error(message); process.exit(2); }

const [, , employeesPath, departmentsPath] = process.argv;
if (!employeesPath) fail('Usage: node data-migration/validate-import.mjs <employees.csv> [departments.csv]');
if (!existsSync(employeesPath)) fail(`File not found: ${employeesPath}`);

const employees = parseCsv(readFileSync(resolve(employeesPath), 'utf8'));
const departments = departmentsPath && existsSync(departmentsPath)
  ? parseCsv(readFileSync(resolve(departmentsPath), 'utf8'))
  : null;

const departmentCodes = departments ? new Set(departments.map((d) => d.department_code)) : null;
const seenCodes = new Map();
const seenEmails = new Map();
const seenPhones = new Map();
const allCodes = new Set(employees.map((e) => e.employee_code).filter(Boolean));

const rejections = [];

employees.forEach((rec, index) => {
  const line = index + 2; // header is line 1
  const errors = [];
  const code = rec.employee_code;

  // Required fields
  if (!code) errors.push('employee_code مفقود');
  if (!rec.full_name_ar || rec.full_name_ar.length < 2) errors.push('full_name_ar مفقود أو قصير');
  if (!rec.role_slug) errors.push('role_slug مفقود');

  // Duplicates (by code / email / phone)
  if (code) {
    if (seenCodes.has(code)) errors.push(`employee_code مكرر (سطر ${seenCodes.get(code)})`);
    else seenCodes.set(code, line);
  }
  if (rec.email) {
    if (!EMAIL_RE.test(rec.email)) errors.push('بريد إلكتروني غير صالح');
    const key = rec.email.toLowerCase();
    if (seenEmails.has(key)) errors.push(`البريد مكرر (سطر ${seenEmails.get(key)})`);
    else seenEmails.set(key, line);
  }
  if (rec.phone_e164) {
    if (!E164_RE.test(rec.phone_e164)) errors.push('هاتف ليس بصيغة E.164 (+XXXXXXXXXXX)');
    if (seenPhones.has(rec.phone_e164)) errors.push(`الهاتف مكرر (سطر ${seenPhones.get(rec.phone_e164)})`);
    else seenPhones.set(rec.phone_e164, line);
  }

  // Role slug must be a seeded system role
  if (rec.role_slug && !VALID_ROLE_SLUGS.has(rec.role_slug)) {
    errors.push(`role_slug غير معروف: ${rec.role_slug}`);
  }

  // Manager must exist within the same import (rule: never create a missing manager)
  if (rec.manager_employee_code) {
    if (rec.manager_employee_code === code) errors.push('الموظف مديرًا لنفسه');
    else if (!allCodes.has(rec.manager_employee_code)) {
      errors.push(`المدير ${rec.manager_employee_code} غير موجود في ملف الاستيراد — تحقق منه في النظام قبل الاستيراد`);
    }
  }

  // Department must exist in departments file when provided
  if (rec.department_code && departmentCodes && !departmentCodes.has(rec.department_code)) {
    errors.push(`department_code غير معرّف في ملف الإدارات: ${rec.department_code}`);
  }

  // Date format
  if (rec.hire_date && !DATE_RE.test(rec.hire_date)) errors.push('hire_date ليس بصيغة YYYY-MM-DD');

  if (errors.length > 0) rejections.push({ line, employee_code: code || '(بدون كود)', errors });
});

// Departments validation (hierarchy + duplicates)
if (departments) {
  const seenDept = new Map();
  departments.forEach((rec, index) => {
    const line = index + 2;
    const errors = [];
    if (!rec.department_code) errors.push('department_code مفقود');
    else if (seenDept.has(rec.department_code)) errors.push(`department_code مكرر (سطر ${seenDept.get(rec.department_code)})`);
    else seenDept.set(rec.department_code, line);
    if (!rec.name_ar) errors.push('name_ar مفقود');
    if (rec.parent_department_code) {
      if (rec.parent_department_code === rec.department_code) errors.push('الإدارة أصل لنفسها');
      else if (!departmentCodes.has(rec.parent_department_code)) errors.push(`الإدارة الأم غير موجودة: ${rec.parent_department_code}`);
    }
    if (errors.length > 0) rejections.push({ line, employee_code: `[dept] ${rec.department_code || '?'}`, errors });
  });
}

// Report
const summary = {
  generatedAt: new Date().toISOString(),
  employeesFile: employeesPath,
  departmentsFile: departmentsPath ?? null,
  totalEmployees: employees.length,
  totalDepartments: departments ? departments.length : null,
  accepted: employees.length - rejections.filter((r) => !String(r.employee_code).startsWith('[dept]')).length,
  rejected: rejections.length,
  rejections,
};

const reportPath = join(dirname(resolve(employeesPath)), 'dry_run_report.json');
writeFileSync(reportPath, JSON.stringify(summary, null, 2), 'utf8');

console.log(`Dry run: ${summary.totalEmployees} employees, ${summary.rejected} rejection(s).`);
for (const r of rejections) console.log(`  line ${r.line} [${r.employee_code}]: ${r.errors.join(' | ')}`);
console.log(`Report: ${reportPath}`);
process.exit(rejections.length > 0 ? 1 : 0);
