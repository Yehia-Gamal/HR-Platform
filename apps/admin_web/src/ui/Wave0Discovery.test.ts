// V23 §15.1: Wave 0 Discovery + baselines — اكتمال مخرجات الاستكشاف.
// يتحقق من أن Wave 0 أنتج جميع المخرجات المطلوبة:
// 1. مصفوفة التتبع (TRACEABILITY.md)
// 2. 74 متطلب مُكتشف ومُعيَّن لوكلاء
// 3. اختبارات موجودة (pgTAP + Vitest)
// 4. CI/CD pipelines
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const root = path.resolve(__dirname, '../../../..');

describe('V23 §15.1: Wave 0 — Discovery + baselines', () => {
  it('§15.1.1: TRACEABILITY.md موجود', () => {
    expect(fs.existsSync(path.join(root, 'TRACEABILITY.md'))).toBe(true);
  });

  it('§15.1.2: CLAUDE.md موجود (دليل المشروع)', () => {
    expect(fs.existsSync(path.join(root, 'CLAUDE.md'))).toBe(true);
  });

  it('§15.1.3: مجلد اختبارات pgTAP موجود ويحتوي ≥48 ملف', () => {
    const testsDir = path.join(root, 'supabase', 'tests');
    expect(fs.existsSync(testsDir)).toBe(true);
    const sqlFiles = fs
      .readdirSync(testsDir)
      .filter((f) => f.endsWith('.sql'));
    expect(sqlFiles.length).toBeGreaterThanOrEqual(48);
  });

  it('§15.1.4: مجلد migrations يحتوي ≥116 migration', () => {
    const migsDir = path.join(root, 'supabase', 'migrations');
    expect(fs.existsSync(migsDir)).toBe(true);
    const sqlFiles = fs
      .readdirSync(migsDir)
      .filter((f) => f.endsWith('.sql'));
    expect(sqlFiles.length).toBeGreaterThanOrEqual(116);
  });

  it('§15.1.5: CI/CD workflows موجودة', () => {
    const workflowsDir = path.join(root, '.github', 'workflows');
    expect(fs.existsSync(workflowsDir)).toBe(true);
    const ymlFiles = fs
      .readdirSync(workflowsDir)
      .filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'));
    expect(ymlFiles.length).toBeGreaterThanOrEqual(1);
  });

  it('§15.1.6: 74 متطلب مُوثّق في مصفوفة التتبع', () => {
    const source = fs.readFileSync(
      path.join(root, 'TRACEABILITY.md'),
      'utf-8',
    );
    const requirementRows = source
      .split('\n')
      .filter((line) => /^\| \d+\.\d+ \|/.test(line));
    expect(requirementRows.length).toBeGreaterThanOrEqual(74);
  });

  it('§15.1.7: لا يوجد متطلب بحالة DISCOVERED (جميعها تجاوزت الاستكشاف)', () => {
    const source = fs.readFileSync(
      path.join(root, 'TRACEABILITY.md'),
      'utf-8',
    );
    const requirementRows = source
      .split('\n')
      .filter((line) => /^\| \d+\.\d+ \|/.test(line));
    const discoveredRows = requirementRows.filter((r) =>
      r.includes('DISCOVERED'),
    );
    expect(discoveredRows.length).toBe(0);
  });

  it('§15.1.8: Edge Functions موجودة', () => {
    const fnDir = path.join(root, 'supabase', 'functions');
    expect(fs.existsSync(fnDir)).toBe(true);
    const fns = fs
      .readdirSync(fnDir)
      .filter(
        (f) =>
          !f.startsWith('_') &&
          fs.statSync(path.join(fnDir, f)).isDirectory(),
      );
    expect(fns.length).toBeGreaterThanOrEqual(5);
  });

  it('§15.1.9: shared-contracts (Zod schemas) موجودة', () => {
    const contractsDir = path.join(root, 'packages', 'shared-contracts');
    expect(fs.existsSync(contractsDir)).toBe(true);
  });

  it('§15.1.10: Flutter mobile app موجود', () => {
    const flutterDir = path.join(root, 'apps', 'mobile_flutter');
    expect(fs.existsSync(flutterDir)).toBe(true);
    expect(
      fs.existsSync(path.join(flutterDir, 'pubspec.yaml')),
    ).toBe(true);
  });
});
