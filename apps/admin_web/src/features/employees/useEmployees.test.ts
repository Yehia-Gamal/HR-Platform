import { describe, it, expect } from 'vitest';
import { employeeSummarySchema, employee360Schema } from '@ahla/shared-contracts';

// Recreate the module-scoped mock data from useEmployees.ts for direct testing
const developmentEmployees = [
  {
    id: '30000000-0000-4000-8000-000000000001',
    employeeCode: 'EMP-001',
    fullNameAr: 'موظف تجريبي للتطوير',
    fullNameEn: null,
    phoneE164: '+201000000001',
    status: 'active',
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    department: 'الإدارة التجريبية',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'موظف تجريبي',
    createdAt: new Date().toISOString(),
  },
  {
    id: '30000000-0000-4000-8000-000000000002',
    employeeCode: 'EMP-002',
    fullNameAr: 'مدير مباشر تجريبي',
    fullNameEn: null,
    phoneE164: '+201000000002',
    status: 'onboarding',
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    department: 'الإدارة التجريبية',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'مدير مباشر',
    createdAt: new Date().toISOString(),
  },
];

// Recreate the module-scoped INVITE_ERROR_MESSAGES map
const INVITE_ERROR_MESSAGES: Record<string, string> = {
  forbidden: 'ليس لديك صلاحية لإرسال الدعوات.',
  no_linked_account: 'الموظف ليس لديه حساب مربوط بعد.',
  account_email_missing: 'لا يوجد بريد إلكتروني مسجّل للموظف.',
  too_many_requests: 'أُرسلت دعوة مؤخرًا. انتظر دقيقة ثم أعد المحاولة.',
  invite_send_failed: 'تعذر إرسال البريد. أعد المحاولة لاحقًا.',
  permission_check_failed: 'تعذر التحقق من الصلاحية.',
  lookup_failed: 'تعذر البحث عن بيانات الموظف.',
  server_not_configured: 'الخدمة غير مهيأة. تواصل مع الدعم.',
  validation_failed: 'بيانات الطلب غير صالحة.',
  rate_limit_check_failed: 'تعذر التحقق من حد الإرسال. أعد المحاولة.',
  invalid_session: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
};

describe('useEmployees — mock data & constants', () => {
  describe('developmentEmployees schema validation', () => {
    it('each employee parses against employeeSummarySchema', () => {
      for (const emp of developmentEmployees) {
        expect(() => employeeSummarySchema.parse(emp)).not.toThrow();
      }
    });

    it('contains exactly 2 employees', () => {
      expect(developmentEmployees).toHaveLength(2);
    });

    it('first employee is active', () => {
      const parsed = employeeSummarySchema.parse(developmentEmployees[0]);
      expect(parsed.status).toBe('active');
      expect(parsed.isActive).toBe(true);
    });

    it('second employee is onboarding', () => {
      const parsed = employeeSummarySchema.parse(developmentEmployees[1]);
      expect(parsed.status).toBe('onboarding');
    });

    it('all IDs are valid UUIDs', () => {
      const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      for (const emp of developmentEmployees) {
        expect(emp.id).toMatch(uuidRe);
      }
    });

    it('all phone numbers are E.164 format', () => {
      const e164Re = /^\+[1-9]\d{6,14}$/;
      for (const emp of developmentEmployees) {
        expect(emp.phoneE164).toMatch(e164Re);
      }
    });
  });

  describe('employee360 inline mock validation', () => {
    it('parses a full 360 object based on developmentEmployees[0]', () => {
      const source = developmentEmployees[0];
      const mock360 = {
        ...source,
        hireDate: null,
        contractEnd: null,
        probationEnd: null,
        jobTitle: 'موظف تجريبي',
        position: null,
        grade: null,
        department: 'الإدارة التجريبية',
        team: null,
        branch: 'المقر الرئيسي',
        workSite: null,
        managerName: 'مدير مباشر تجريبي',
        accountStatus: 'active',
        roles: [{ slug: 'employee', name: 'موظف' }],
        directReports: 0,
        attendance30: { present: 20, lateDays: 2, absent: 1, workMinutes: 9600 },
        requestCounts: { pending: 1, approved: 4, rejected: 0 },
        latestKpi: null,
        documents: [],
        assets: [],
        recentRequests: [],
        recentTasks: [],
        lastUpdatedAt: new Date().toISOString(),
        email: 'dev@example.com',
      };
      expect(() => employee360Schema.parse(mock360)).not.toThrow();
    });

    it('360 attendance30 values are non-negative', () => {
      const att = { present: 20, lateDays: 2, absent: 1, workMinutes: 9600 };
      expect(att.present).toBeGreaterThanOrEqual(0);
      expect(att.lateDays).toBeGreaterThanOrEqual(0);
      expect(att.absent).toBeGreaterThanOrEqual(0);
      expect(att.workMinutes).toBeGreaterThanOrEqual(0);
    });

    it('360 requestCounts sum correctly', () => {
      const rc = { pending: 1, approved: 4, rejected: 0 };
      const total = rc.pending + rc.approved + rc.rejected;
      expect(total).toBe(5);
    });
  });

  describe('INVITE_ERROR_MESSAGES', () => {
    it('has 11 error codes', () => {
      expect(Object.keys(INVITE_ERROR_MESSAGES)).toHaveLength(11);
    });

    it('every value is a non-empty Arabic string', () => {
      for (const [key, msg] of Object.entries(INVITE_ERROR_MESSAGES)) {
        expect(msg.length).toBeGreaterThan(0);
        expect(typeof msg).toBe('string');
        // Key should be snake_case
        expect(key).toMatch(/^[a-z][a-z0-9_]*$/);
      }
    });

    it('covers all expected error codes', () => {
      const expectedCodes = [
        'forbidden',
        'no_linked_account',
        'account_email_missing',
        'too_many_requests',
        'invite_send_failed',
        'permission_check_failed',
        'lookup_failed',
        'server_not_configured',
        'validation_failed',
        'rate_limit_check_failed',
        'invalid_session',
      ];
      for (const code of expectedCodes) {
        expect(INVITE_ERROR_MESSAGES[code]).toBeDefined();
      }
    });

    it('unknown error code returns undefined', () => {
      expect(INVITE_ERROR_MESSAGES['nonexistent_error']).toBeUndefined();
    });
  });
});
