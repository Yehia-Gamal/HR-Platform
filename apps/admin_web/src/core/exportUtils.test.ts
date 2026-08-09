import { describe, expect, it } from 'vitest';
import { toCsv, type ExportColumn } from './exportUtils';

interface Row {
  name: string;
  amount: number;
  note: string | null;
}

const columns: ExportColumn<Row>[] = [
  { key: 'name', header: 'الاسم', get: (r) => r.name },
  { key: 'amount', header: 'المبلغ', get: (r) => r.amount },
  { key: 'note', header: 'ملاحظة', get: (r) => r.note },
];

describe('toCsv', () => {
  it('يبدأ بـ BOM لدعم العربية في Excel', () => {
    const csv = toCsv(columns, [{ name: 'أحمد', amount: 100, note: null }]);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
  });

  it('يكتب الترويسة والسجلات', () => {
    const csv = toCsv(columns, [
      { name: 'أحمد', amount: 100, note: null },
      { name: 'محمد', amount: 200, note: 'خصم' },
    ]);
    const withoutBom = csv.slice(1);
    const lines = withoutBom.split('\n');
    expect(lines[0]).toBe('الاسم,المبلغ,ملاحظة');
    expect(lines[1]).toBe('أحمد,100,');
    expect(lines[2]).toBe('محمد,200,خصم');
  });

  it('يضع القيم التي تحتوي فاصلة أو اقتباس بين علامتي اقتباس', () => {
    const csv = toCsv(columns, [{ name: 'أحمد "الخطيب"', amount: 100, note: 'سبب, إضافي' }]);
    expect(csv).toContain('"أحمد ""الخطيب"""');
    expect(csv).toContain('"سبب, إضافي"');
  });

  it('يحوّل null والقيم الفارغة إلى خلية فارغة', () => {
    const csv = toCsv(columns, [{ name: '', amount: 0, note: null }]);
    const lines = csv.slice(1).split('\n');
    expect(lines[1]).toBe(',0,');
  });
});
