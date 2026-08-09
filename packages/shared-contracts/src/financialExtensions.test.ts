import { describe, expect, it } from 'vitest';
import {
  addEmployeePenaltySchema,
  auditTrailItemSchema,
  auditTrailPageSchema,
  employeePenaltySchema,
  generateInstapayBatchSchema,
  instapayBatchSchema,
  instapayItemSchema,
  systemSettingSchema,
} from './financialExtensions';

describe('financialExtensions contracts', () => {
  it('employeePenaltySchema يفرض بنية المخالفة', () => {
    const parsed = employeePenaltySchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeCode: 'EMP-001',
      employeeName: 'أحمد',
      departmentName: 'الإدارة العامة',
      penaltyType: 'late',
      amount: 250,
      currency: 'EGP',
      reason: 'تأخير متكرر',
      evidenceRef: null,
      status: 'issued',
      payrollRunId: null,
      issuedBy: null,
      issuedAt: '2026-08-08T10:00:00.000Z',
      waivedBy: null,
      waivedAt: null,
      waiveReason: null,
    });
    expect(parsed.amount).toBe(250);
    expect(parsed.status).toBe('issued');
  });

  it('employeePenaltySchema يرفض الحالة غير المعروفة', () => {
    const base = {
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'أحمد',
      penaltyType: 'late',
      amount: 250,
      currency: 'EGP',
      reason: 'سبب',
      status: 'unknown_status',
      issuedAt: '2026-08-08T10:00:00.000Z',
    };
    expect(() => employeePenaltySchema.parse(base)).toThrow();
  });

  it('addEmployeePenaltySchema يطابق نتيجة RPC', () => {
    const parsed = addEmployeePenaltySchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      amount: 500,
      penaltyType: 'absence',
      status: 'issued',
      issuedAt: '2026-08-08T10:00:00.000Z',
    });
    expect(parsed.penaltyType).toBe('absence');
  });

  it('instapayBatchSchema يفرض عناصر الدفعة', () => {
    const parsed = instapayBatchSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      payrollRunId: '22222222-2222-4222-8222-222222222222',
      periodMonth: '2026-08',
      batchReference: 'IP-20260808-ABCDEF12',
      totalAmount: 12000,
      itemCount: 2,
      status: 'generated',
      sentAt: null,
      completedAt: null,
      createdAt: '2026-08-08T10:00:00.000Z',
      items: [
        {
          id: '33333333-3333-4333-8333-333333333333',
          employeeId: '44444444-4444-4444-8444-444444444444',
          employeeName: 'محمد',
          mobileE164: '+201012345678',
          amount: 6000,
          status: 'pending',
          paidAt: null,
        },
      ],
    });
    expect(parsed.items).toHaveLength(1);
    expect(parsed.items[0]?.mobileE164).toBe('+201012345678');
  });

  it('instapayItemSchema يقبل الحالات المعروفة فقط', () => {
    const base = {
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: null,
      mobileE164: null,
      amount: 100,
      paidAt: null,
    };
    expect(instapayItemSchema.safeParse({ ...base, status: 'paid' }).success).toBe(true);
    expect(instapayItemSchema.safeParse({ ...base, status: 'weird' }).success).toBe(false);
  });

  it('generateInstapayBatchSchema يطابق نتيجة RPC', () => {
    const parsed = generateInstapayBatchSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      reference: 'IP-20260808-ABCDEF12',
      totalAmount: 12000,
      itemCount: 3,
      status: 'generated',
    });
    expect(parsed.reference).toMatch(/^IP-/);
  });

  it('auditTrailItemSchema يفرض عناصر سجل التدقيق', () => {
    const parsed = auditTrailItemSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      eventType: 'penalty.issued',
      category: 'financial',
      severity: 'warning',
      actorUserId: null,
      actorEmployeeId: null,
      actorName: 'سكرتير تنفيذي',
      targetTable: 'employee_penalties',
      targetId: '22222222-2222-4222-8222-222222222222',
      summaryAr: 'إصدار مخالفة مالية',
      metadata: { amount: 250 },
      occurredAt: '2026-08-08T10:00:00.000Z',
    });
    expect(parsed.eventType).toBe('penalty.issued');
  });

  it('auditTrailPageSchema يغلف total + items', () => {
    const parsed = auditTrailPageSchema.parse({
      total: 1,
      items: [],
    });
    expect(parsed.total).toBe(1);
  });

  it('systemSettingSchema يفرض إعداد النظام', () => {
    const parsed = systemSettingSchema.parse({
      key: 'leave_approval_escalation_hours',
      value: 24,
      valueType: 'number',
      groupName: 'requests',
      labelAr: 'مهلة التصعيد',
      description: 'عدد الساعات',
      isSecret: false,
      isEditable: true,
    });
    expect(parsed.key).toBe('leave_approval_escalation_hours');
    expect(parsed.valueType).toBe('number');
  });
});
