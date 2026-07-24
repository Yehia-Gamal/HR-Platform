import { describe, expect, it } from 'vitest';
import { createEmployeeInputSchema, createEmployeeResultSchema } from './employee.js';

const base = {
  fullNameAr: 'أحمد يوسف',
  email: 'ahmed@example.com',
  phoneE164: '01154869616',
  roleSlug: 'employee',
};

describe('createEmployeeInputSchema — phone', () => {
  it('accepts a local Egyptian number (01…)', () => {
    expect(createEmployeeInputSchema.parse(base).phoneE164).toBe('01154869616');
  });

  it('accepts a full E.164 number (+20…)', () => {
    const parsed = createEmployeeInputSchema.parse({ ...base, phoneE164: '+201154869616' });
    expect(parsed.phoneE164).toBe('+201154869616');
  });

  it('rejects too-short local numbers', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, phoneE164: '0115486' })).toThrow();
  });

  it('rejects a number with letters', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, phoneE164: '011ABCD9616' })).toThrow();
  });

  it('rejects an E.164 number missing the + prefix', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, phoneE164: '201154869616' })).toThrow();
  });
});

describe('createEmployeeInputSchema — fields', () => {
  it('employeeCode is optional and honours min(2)/max(50)', () => {
    expect(createEmployeeInputSchema.parse(base).employeeCode).toBeUndefined();
    expect(createEmployeeInputSchema.parse({ ...base, employeeCode: 'EMP-001' }).employeeCode).toBe('EMP-001');
    expect(() => createEmployeeInputSchema.parse({ ...base, employeeCode: 'E' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, employeeCode: 'x'.repeat(51) })).toThrow();
  });

  it('requires a valid email', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, email: 'not-an-email' })).toThrow();
  });

  it('requires fullNameAr of at least 3 chars', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, fullNameAr: 'أ' })).toThrow();
  });

  it('accepts valid UUIDs and null for optional org fields', () => {
    const uuid = '11111111-1111-4111-8111-111111111111';
    expect(createEmployeeInputSchema.parse({ ...base, branchId: uuid }).branchId).toBe(uuid);
    expect(createEmployeeInputSchema.parse({ ...base, branchId: null }).branchId).toBeNull();
    expect(() => createEmployeeInputSchema.parse({ ...base, branchId: 'not-a-uuid' })).toThrow();
  });

  it('defaults sendInvite to true when omitted', () => {
    expect(createEmployeeInputSchema.parse(base).sendInvite).toBe(true);
  });
});

describe('createEmployeeResultSchema', () => {
  it('validates a well-formed result', () => {
    const result = createEmployeeResultSchema.parse({
      employeeId: '11111111-1111-4111-8111-111111111111',
      userId: '22222222-2222-4222-8222-222222222222',
      invitationSent: true,
    });
    expect(result.invitationSent).toBe(true);
  });

  it('rejects a non-uuid employeeId', () => {
    expect(() => createEmployeeResultSchema.parse({ employeeId: 'x', userId: 'y', invitationSent: false })).toThrow();
  });
});
