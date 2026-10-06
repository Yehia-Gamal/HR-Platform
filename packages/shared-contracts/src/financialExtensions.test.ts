import { describe, expect, it } from 'vitest';
import {
  addEmployeePenaltySchema,
  auditTrailItemSchema,
  auditTrailPageSchema,
  cancelInstantPenaltyResultSchema,
  employeePenaltySchema,
  generateInstapayBatchSchema,
  instapayBatchSchema,
  instapayItemSchema,
  instantPenaltySchema,
  pendingPenaltyEmployeeSchema,
  generateInstantPenaltyResultSchema,
  confirmInstantPenaltyPaymentResultSchema,
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

  it('instantPenaltySchema يفرض بنية الغرامة الفورية مع حالات التصعيد', () => {
    const penalty = instantPenaltySchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'أحمد محمود',
      employeeCode: 'EMP-101',
      departmentName: 'المبيعات',
      workDate: '2026-09-19',
      lateMinutes: 25,
      originalAmount: 20,
      currentAmount: 20,
      currency: 'EGP',
      status: 'pending_payment',
      escalationLevel: 'initial',
      paidAt: null,
      confirmedBy: null,
      suspendedAt: null,
      suspensionLiftedAt: null,
      notes: null,
      createdAt: '2026-09-19T10:25:00.000Z',
    });
    expect(penalty.lateMinutes).toBe(25);
    expect(penalty.currentAmount).toBe(20);
    expect(penalty.status).toBe('pending_payment');
  });

  it('pendingPenaltyEmployeeSchema يفرض بيانات الموظف المطالب بالغرامة', () => {
    const pendingEmp = pendingPenaltyEmployeeSchema.parse({
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'محمد علي',
      employeeCode: 'EMP-102',
      departmentName: 'العمليات',
      pendingCount: 1,
      totalAmount: 500,
      isSuspended: true,
      latestDate: '2026-09-18',
    });
    expect(pendingEmp.isSuspended).toBe(true);
    expect(pendingEmp.totalAmount).toBe(500);
  });

  it('generateInstantPenaltyResultSchema يدعم فترة السماح بدون غرامة', () => {
    const graceResult = generateInstantPenaltyResultSchema.parse({
      id: null,
      alreadyExists: false,
      isGracePeriod: true,
      amount: 0,
      message: 'التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة',
    });
    expect(graceResult.isGracePeriod).toBe(true);
    expect(graceResult.id).toBeNull();
  });

  it('generateInstantPenaltyResultSchema يدعم حالة الإعفاء (مأمورية / إجازة / قافلة / فاندي)', () => {
    const exemptResult = generateInstantPenaltyResultSchema.parse({
      id: null,
      alreadyExists: false,
      isExempt: true,
      amount: 0,
      message: 'الموظف معفى من غرامات الحضور والانصراف: مأمورية عمل رسمية (المعادي)',
    });
    expect(exemptResult.isExempt).toBe(true);
    expect(exemptResult.id).toBeNull();
    expect(exemptResult.amount).toBe(0);
  });

  it('confirmInstantPenaltyPaymentResultSchema يوثق نتيجة الدفع ورفع التعليق', () => {
    const confirmResult = confirmInstantPenaltyPaymentResultSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      status: 'paid',
      paidAt: '2026-09-19T12:00:00.000Z',
      currentAmount: 500,
      wasSuspended: true,
    });
    expect(confirmResult.status).toBe('paid');
    expect(confirmResult.wasSuspended).toBe(true);
  });

  it('cancelInstantPenaltyResultSchema يوثق نتيجة الإلغاء', () => {
    const cancelResult = cancelInstantPenaltyResultSchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      status: 'cancelled',
      currentAmount: 200,
      wasSuspended: false,
    });
    expect(cancelResult.status).toBe('cancelled');
    expect(cancelResult.currentAmount).toBe(200);
    expect(cancelResult.wasSuspended).toBe(false);
  });

  it('instantPenaltySchema يقبل الحالة الملغاة', () => {
    const penalty = instantPenaltySchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'أحمد',
      employeeCode: 'E-001',
      departmentName: 'إدارة',
      workDate: '2026-09-19',
      lateMinutes: 25,
      originalAmount: 20,
      currentAmount: 20,
      currency: 'EGP',
      status: 'cancelled',
      escalationLevel: 'initial',
      paidAt: null,
      confirmedBy: null,
      suspendedAt: null,
      suspensionLiftedAt: null,
      notes: 'إلغاء: خطأ في التسجيل',
      createdAt: '2026-09-19T10:25:00.000Z',
    });
    expect(penalty.status).toBe('cancelled');
  });
});
