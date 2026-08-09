import { describe, it, expect } from 'vitest';
import { employeePenaltySchema } from '@ahla/shared-contracts';

const validPenalty = {
  id: '11111111-1111-4111-8111-111111111111',
  employeeId: '22222222-2222-4222-8222-222222222222',
  employeeCode: 'EMP-001',
  employeeName: 'أحمد',
  departmentName: 'المالية',
  penaltyType: 'تأخير',
  amount: 500,
  currency: 'EGP',
  reason: 'تأخر متكرر',
  evidenceRef: null,
  status: 'issued' as const,
  payrollRunId: null,
  issuedBy: null,
  issuedAt: '2026-01-01T00:00:00+00:00',
  waivedBy: null,
  waivedAt: null,
  waiveReason: null,
};

describe('employeePenaltySchema', () => {
  it('parses a valid penalty record', () => {
    const parsed = employeePenaltySchema.parse(validPenalty);
    expect(parsed.amount).toBe(500);
    expect(parsed.status).toBe('issued');
    expect(parsed.employeeName).toBe('أحمد');
  });

  it('rejects invalid status value', () => {
    expect(() => employeePenaltySchema.parse({ ...validPenalty, status: 'pending' })).toThrow();
  });

  it('rejects non-uuid id', () => {
    expect(() => employeePenaltySchema.parse({ ...validPenalty, id: 'p1' })).toThrow();
  });

  it('allows null for nullable fields', () => {
    const parsed = employeePenaltySchema.parse({
      ...validPenalty,
      employeeCode: null,
      departmentName: null,
      issuedAt: null,
      issuedBy: null,
    });
    expect(parsed.employeeCode).toBeNull();
    expect(parsed.departmentName).toBeNull();
  });
});
