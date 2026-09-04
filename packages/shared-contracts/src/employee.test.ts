import { describe, expect, it } from 'vitest';
import { adminSetPasswordInputSchema, createEmployeeInputSchema, createEmployeeResultSchema, employee360Schema } from './employee.js';

const base = {
  fullNameAr: 'أحمد يوسف',
  email: 'ahmed@example.com',
  phoneE164: '01154869616',
  roleSlug: 'employee',
  initialPassword: 'StrongP@ss2026',
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

  it('accepts a strong 12+ char password with a symbol', () => {
    expect(createEmployeeInputSchema.parse({ ...base, initialPassword: 'B!tterF!sh2026X' }).initialPassword).toBe('B!tterF!sh2026X');
  });

  it('enforces min 6 / max 72', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Ab1!' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'A1'.repeat(37) })).toThrow();
  });

  it('requires upper + lower + digit', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'strongpassword1' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'STRONGPASSWORD1' })).toThrow();
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'Strongpassword' })).toThrow();
  });

  it('accepts an 8-character password with upper, lower, and digit', () => {
    expect(createEmployeeInputSchema.parse({ ...base, initialPassword: 'kP4x9m2A' }).initialPassword).toBe('kP4x9m2A');
  });

  it('rejects 5+ repeated characters in a row', () => {
    expect(() => createEmployeeInputSchema.parse({ ...base, initialPassword: 'AAAAABbbb1$A' })).toThrow();
    expect(createEmployeeInputSchema.parse({ ...base, initialPassword: 'AAAABbxyz91$' }).initialPassword).toBe('AAAABbxyz91$');
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

describe('adminSetPasswordInputSchema', () => {
  it('defaults mustChangePassword to false', () => {
    const parsed = adminSetPasswordInputSchema.parse({
      employeeId: '11111111-1111-4111-8111-111111111111',
      password: 'kP4x9m2A',
    });
    expect(parsed.mustChangePassword).toBe(false);
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
      temporaryPassword: 'S0meTemp!2026',
    });
    expect(result.temporaryPassword).toBe('S0meTemp!2026');
  });

  it('rejects a non-uuid employeeId', () => {
    expect(() => createEmployeeResultSchema.parse({ employeeId: 'x', userId: 'y', invitationSent: false })).toThrow();
  });
});

describe('employee360Schema', () => {
  it('tolerates a null lastUpdatedAt (legacy rows with null updated_at)', () => {
    const parsed = employee360Schema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeCode: 'TEST-001',
      fullNameAr: 'موظف تجريبي',
      fullNameEn: null,
      phoneE164: null,
      photoUrl: null,
      status: 'active',
      isActive: true,
      hireDate: '2024-01-15',
      contractEnd: null,
      probationEnd: null,
      jobTitle: null,
      position: null,
      grade: null,
      department: null,
      team: null,
      branch: null,
      workSite: null,
      managerName: null,
      accountStatus: null,
      roles: [],
      directReports: 0,
      attendance30: { present: 0, lateDays: 0, absent: 0, workMinutes: 0 },
      requestCounts: { pending: 0, approved: 0, rejected: 0 },
      latestKpi: null,
      documents: [],
      assets: [],
      recentRequests: [],
      recentTasks: [],
      lastUpdatedAt: null,
    });
    expect(parsed.employeeCode).toBe('TEST-001');
    expect(parsed.lastUpdatedAt).toBeNull();
  });

  it('rejects a non-conformant UUID in id', () => {
    expect(() =>
      employee360Schema.parse({
        id: '11111111-2222-3333-4444-555555555555',
        employeeCode: 'TEST-001',
        fullNameAr: 'موظف تجريبي',
        fullNameEn: null,
        phoneE164: null,
        photoUrl: null,
        status: 'active',
        isActive: true,
        hireDate: '2024-01-15',
        contractEnd: null,
        probationEnd: null,
        jobTitle: null,
        position: null,
        grade: null,
        department: null,
        team: null,
        branch: null,
        workSite: null,
        managerName: null,
        accountStatus: null,
        roles: [],
        directReports: 0,
        attendance30: { present: 0, lateDays: 0, absent: 0, workMinutes: 0 },
        requestCounts: { pending: 0, approved: 0, rejected: 0 },
        latestKpi: null,
        documents: [],
        assets: [],
        recentRequests: [],
        recentTasks: [],
        lastUpdatedAt: '2026-01-01T00:00:00.000Z',
      }),
    ).toThrow();
  });
});
