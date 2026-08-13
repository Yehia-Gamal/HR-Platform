import { describe, expect, it } from 'vitest';
import {
  LEAVE_TYPE_COLORS,
  LEAVE_TYPE_LABELS,
  leaveAdminResponseSchema,
  leaveAdminRowSchema,
  leaveStatusSchema,
} from './leaves.js';

const validRow = {
  requestId: '11111111-1111-4111-8111-111111111111',
  requestNumber: 42,
  status: 'approved',
  createdAt: '2026-01-01T00:00:00Z',
  employeeId: '22222222-2222-4222-8222-222222222222',
  employeeCode: 'EMP-001',
  employeeName: 'أحمد محمود',
  leaveTypeId: '33333333-3333-4333-8333-333333333333',
  leaveTypeCode: 'annual',
  leaveTypeName: 'إجازة سنوية',
  isPaid: true,
  startDate: '2026-02-01',
  endDate: '2026-02-03',
  daysCount: 3,
  hoursCount: null,
  reason: null,
  handoverNotes: null,
  attachmentUrl: null,
};

describe('leaves contracts', () => {
  it('يقبل صفاً إدارياً صالحاً ويطبّق الافتراضيات', () => {
    const row = leaveAdminRowSchema.parse(validRow);
    expect(row.durationUnit).toBe('day'); // default
    expect(row.isHalfDay).toBe(false); // default
    expect(row.status).toBe('approved');
  });

  it('يقبل استجابة إدارية كاملة (total + rows)', () => {
    const res = leaveAdminResponseSchema.parse({ total: 1, rows: [validRow] });
    expect(res.total).toBe(1);
    expect(res.rows).toHaveLength(1);
  });

  it('يرفض حالة إجازة غير معروفة', () => {
    expect(() => leaveAdminRowSchema.parse({ ...validRow, status: 'unknown' })).toThrow();
  });

  it('يرفض نوع إجازة خارج المجموعة (leaveTypeCode)', () => {
    expect(() => leaveAdminRowSchema.parse({ ...validRow, leaveTypeCode: 'maternity' })).toThrow();
  });

  it('يرفض معرّف طلب غير UUID', () => {
    expect(() => leaveAdminRowSchema.parse({ ...validRow, requestId: 'not-a-uuid' })).toThrow();
  });

  it('يرفض حقلاً إلزامياً مفقوداً', () => {
    const { daysCount, ...missing } = validRow;
    expect(() => leaveAdminRowSchema.parse(missing)).toThrow();
  });

  it('leaveStatusSchema: يطابق قيم الحالات المعروفة', () => {
    expect(leaveStatusSchema.parse('draft')).toBe('draft');
    expect(leaveStatusSchema.parse('escalated')).toBe('escalated');
    expect(() => leaveStatusSchema.parse('done')).toThrow();
  });

  it('LEAVE_TYPE_LABELS / COLORS تغطي أنواع الإجازات', () => {
    for (const code of ['annual', 'casual', 'sick', 'unpaid'] as const) {
      expect(LEAVE_TYPE_LABELS[code]).toBeTruthy();
      expect(LEAVE_TYPE_COLORS[code]).toBeTruthy();
    }
  });
});
