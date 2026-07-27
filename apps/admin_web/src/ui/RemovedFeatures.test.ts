// V23 §13: التحقق من حذف الميزات المطلوب إزالتها.
// يفحص أن المسارات (routes) المحذوفة لا تظهر في ملف التوجيه الرئيسي
// ولا في قائمة التنقل الجانبية.
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const appSource = fs.readFileSync(
  path.resolve(__dirname, '../app/App.tsx'),
  'utf-8',
);

const shellSource = fs.readFileSync(
  path.resolve(__dirname, '../features/workspaces/WorkspaceShell.tsx'),
  'utf-8',
);

// استخراج سمات path من عناصر Route فقط (لتجنب التطابق مع نصوص أخرى)
const routePaths = [...appSource.matchAll(/path=["']([^"']+)["']/g)].map(
  (m) => m[1],
);

describe('V23 §13: الميزات المحذوفة', () => {
  it('§13.1: مسار الخصوصية المستقلة غير موجود في التوجيه', () => {
    const hasPrivacyRoute = routePaths.some((p) =>
      /\bprivacy\b/i.test(p),
    );
    expect(hasPrivacyRoute).toBe(false);
  });

  it('§13.4: مسار العهد غير موجود في التوجيه', () => {
    const hasCustodyRoute = routePaths.some((p) =>
      /\bcustody\b/i.test(p),
    );
    expect(hasCustodyRoute).toBe(false);
  });

  it('§13.5: مسار نهاية العقد غير موجود في التوجيه', () => {
    const hasContractEndRoute = routePaths.some((p) =>
      /\bcontract[_-]?end\b/i.test(p),
    );
    expect(hasContractEndRoute).toBe(false);
  });

  it('§13.9: لا يوجد مسار تقارير مكرر (reports يظهر مرة واحدة لكل workspace)', () => {
    // مسارات reports المتوقعة: "reports" (HR) و "reports/scheduler" (Admin)
    const reportPaths = routePaths.filter((p) => /^reports/.test(p));
    // يجب ألا تتكرر نفس القيمة
    const unique = new Set(reportPaths);
    expect(reportPaths.length).toBe(unique.size);
  });

  it('§13.1/4/5: الميزات المحذوفة ليست في قائمة التنقل الجانبية', () => {
    // التنقل الجانبي يعرّف العناصر كـ objects مع label و to
    // نتحقق أن لا عنصر يشير لمسار محذوف
    const navTargets = [
      ...shellSource.matchAll(/to:\s*['"]([^'"]+)['"]/g),
    ].map((m) => m[1]);

    expect(navTargets.some((t) => /privacy/i.test(t))).toBe(false);
    expect(navTargets.some((t) => /custody/i.test(t))).toBe(false);
    expect(navTargets.some((t) => /contract[_-]?end/i.test(t))).toBe(false);
  });
});
