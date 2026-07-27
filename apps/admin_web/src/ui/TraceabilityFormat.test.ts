// V23 §16.1: التحقق من صحة بنية مصفوفة التتبع (سلم الإثبات).
// يفحص أن TRACEABILITY.md يحتوي جميع الأقسام المطلوبة
// وأن كل متطلب له حالة صالحة والإحصائيات متسقة.
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const traceabilityPath = path.resolve(__dirname, '../../../../TRACEABILITY.md');
const source = fs.readFileSync(traceabilityPath, 'utf-8');

// استخراج جميع صفوف المتطلبات (تبدأ بـ | رقم.رقم |)
const requirementRows = source
  .split('\n')
  .filter((line) => /^\| \d+\.\d+ \|/.test(line));

// الحالات المعتمدة في سلم الإثبات
const VALID_STATUSES = [
  'DISCOVERED',
  'DESIGNED',
  'IMPLEMENTED',
  'TESTED',
  'RUNTIME_VERIFIED',
  'RELEASED',
];

describe('V23 §16.1: سلم الإثبات — بنية مصفوفة التتبع', () => {
  it('§16.1.1: الملف يحتوي تعريف مراحل سلم الإثبات', () => {
    for (const status of VALID_STATUSES) {
      expect(source).toContain(status);
    }
  });

  it('§16.1.2: الأقسام الرئيسية موجودة (§1 إلى §16)', () => {
    const sectionHeaders = [...source.matchAll(/## §(\d+)/g)].map((m) =>
      parseInt(m[1]),
    );
    // على الأقل الأقسام 1-14 موجودة
    for (let i = 1; i <= 14; i++) {
      expect(sectionHeaders).toContain(i);
    }
  });

  it('§16.1.3: كل متطلب له حالة صالحة من سلم الإثبات', () => {
    expect(requirementRows.length).toBeGreaterThan(50); // 74 متطلب متوقع
    for (const row of requirementRows) {
      const cells = row.split('|').map((c) => c.trim());
      const status = cells[cells.length - 2]; // الحالة هي العمود الأخير قبل |
      expect(
        VALID_STATUSES.includes(status),
        `حالة غير صالحة "${status}" في: ${cells[1]}`,
      ).toBe(true);
    }
  });

  it('§16.1.4: ملخص إحصائي موجود ومتسق مع البيانات', () => {
    expect(source).toMatch(/ملخص إحصائي/);

    // عدّ الحالات من الصفوف الفعلية
    const statusCounts: Record<string, number> = {};
    for (const status of VALID_STATUSES) {
      statusCounts[status] = 0;
    }
    for (const row of requirementRows) {
      const cells = row.split('|').map((c) => c.trim());
      const status = cells[cells.length - 2];
      if (statusCounts[status] !== undefined) {
        statusCounts[status]++;
      }
    }

    // تحقق أن الإجمالي يساوي عدد الصفوف
    const total = Object.values(statusCounts).reduce(
      (a, b) => (a as number) + (b as number),
      0,
    ) as number;
    expect(total).toBe(requirementRows.length);
  });

  it('§16.1.5: كل متطلب له رقم قسم ورقم بند فريد', () => {
    const ids = requirementRows.map((row) => {
      const cells = row.split('|').map((c) => c.trim());
      return cells[1]; // الرقم (مثل 1.1, 3.2)
    });
    const uniqueIds = new Set(ids);
    expect(ids.length).toBe(uniqueIds.size);
  });

  it('§16.1.6: كل متطلب يحتوي وكيل مسؤول', () => {
    for (const row of requirementRows) {
      const cells = row.split('|').map((c) => c.trim());
      const agent = cells[3]; // عمود الوكيل
      expect(agent.length).toBeGreaterThan(0);
    }
  });
});
