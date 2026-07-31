// V23 §14.2: التحقق من وجود واكتمال قائمة USING(true) المعتمدة.
// يفحص أن الوثيقة موجودة وتحتوي الجداول المرجعية المتوقعة
// وأن كل جدول مصنّف حسب مستوى الخطر.
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const allowlistPath = path.resolve(__dirname, '../../../../docs/USING_TRUE_ALLOWLIST.md');
const allowlistExists = fs.existsSync(allowlistPath);
const allowlistSource = allowlistExists ? fs.readFileSync(allowlistPath, 'utf-8') : '';

describe('V23 §14.2: USING(true) allowlist موثقة', () => {
  it('§14.2.1: ملف القائمة المعتمدة موجود', () => {
    expect(allowlistExists).toBe(true);
  });

  it('§14.2.2: القائمة تحتوي عنوان المراجعة وتاريخها', () => {
    expect(allowlistSource).toContain('USING(true)');
    expect(allowlistSource).toMatch(/تاريخ المراجعة/);
  });

  it('§14.2.3: الجداول المرجعية الأساسية مذكورة في القائمة', () => {
    // الجداول المرجعية التي يجب أن تكون في القائمة (حسب CLAUDE.md)
    const expectedTables = ['roles', 'permissions', 'role_permissions', 'kpi_criteria', 'leave_types', 'departments', 'job_titles', 'legal_entities'];
    for (const table of expectedTables) {
      expect(allowlistSource).toContain(`\`${table}\``);
    }
  });

  it('§14.2.4: كل جدول مصنّف حسب مستوى الخطر (LOW/MEDIUM/HIGH)', () => {
    // كل صف في الجدول يجب أن يحتوي تصنيف خطر
    const tableRows = allowlistSource.split('\n').filter((line) => line.startsWith('|') && line.includes('`') && !line.includes('---'));
    const dataRows = tableRows.filter((line) => !line.includes('الجدول') && !line.includes('المستوى'));
    // كل صف بيانات يحتوي تصنيف خطر
    for (const row of dataRows) {
      expect(row).toMatch(/LOW|MEDIUM|HIGH/);
    }
  });

  it('§14.2.5: لا يوجد جدول حساس في القائمة', () => {
    // الجداول الحساسة التي يجب ألا تستخدم USING(true)
    const sensitiveTables = ['employees', 'attendance_daily', 'kpi_evaluations', 'dispute_cases', 'leave_requests', 'audit_log'];
    // نتحقق أن هذه الجداول غير مدرجة كـ USING(true)
    const allowlistTableNames = [...allowlistSource.matchAll(/\| `(\w+)` \|/g)].map((m) => m[1]);
    for (const table of sensitiveTables) {
      expect(allowlistTableNames).not.toContain(table);
    }
  });

  it('§14.2.6: القائمة تحتوي ملخص المخاطر والتوصيات', () => {
    expect(allowlistSource).toMatch(/ملخص المخاطر/);
    expect(allowlistSource).toMatch(/التوصيات/);
    expect(allowlistSource).toMatch(/القرار/);
  });
});
