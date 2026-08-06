import { describe, expect, it } from 'vitest';
import { createEmployeeInputSchema, createEmployeeResultSchema } from './employee.js';

const base = {
  fullNameAr: 'أحمد يوسف',
  email: 'ahmed@example.com',
  phoneE164: '01154869616',
  roleSlug: 'employee',
  initialPassword: 'StrongP@ss1',
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

  it('defaults sendInvite to false when omitted', () => {
    expect(createEmployeeInputSchema.parse(base).sendInvite).toBe(false);
  });
});

describe('createEmployeeInputSchema — initialPassword', () => {
  it('is optional — omission allowed (server generates temporary password)', () => {
    const { initialPassword: _omit, ...rest } = base;
    const parsed = createEmployeeInputSchema.parse(rest);
    expect(parsed.initialPassword).toBeUndefined();
  });

  it('rejects raw empty string (clients must normalize to undefined)', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: '' })).toThrow();
  });

  it('enforces min 8 / max 15', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Abc123' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'A1'.repeat(9) })).toThrow();
  });

  it('requires upper + lower + digit', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'strongpassword1' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'STRONGPASSWORD1' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Strongpassword' })).toThrow();
  });

  it('rejects identifier leakage (phone/email/code/name parts)', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Ahmed11Strong' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: '01154869616Q' })).toThrow();
  });

  it('rejects common words and keyboard sequences', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Password1' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Qwerty12A' })).toThrow();
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

  it('exposes a generated temporary password when returned', () => {
    const result = createEmployeeResultSchema.parse({
      employeeId: '11111111-1111-4111-8111-111111111111',
      userId: '22222222-2222-4222-8222-222222222222',
      invitationSent: true,
      temporaryPassword: 'S0meTemp!9',
    });
    expect(result.temporaryPassword).toBe('S0meTemp!9');
  });

  it('rejects a non-uuid employeeId', () => {
    expect(() => createEmployeeResultSchema.parse({ employeeId: 'x', userId: 'y', invitationSent: false })).toThrow();
  });
});
