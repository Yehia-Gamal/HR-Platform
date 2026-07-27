import { describe, expect, it } from 'vitest';
import {
  disputeCaseStatusSchema,
  adminActionTypeSchema,
  executiveDecisionSchema,
  disputeAdminActionSchema,
  proposeAdminActionInputSchema,
  executiveDecisionInputSchema,
  executeActionInputSchema,
  createDisputeInputSchema,
} from './disputes.js';

const uuid = '11111111-1111-4111-8111-111111111111';
const now = '2026-07-20T10:00:00.000Z';

describe('dispute admin-action contracts — V17 §14', () => {
  it('case status enum covers the full lifecycle', () => {
    expect(disputeCaseStatusSchema.parse('open')).toBe('open');
    expect(disputeCaseStatusSchema.parse('executed')).toBe('executed');
    expect(disputeCaseStatusSchema.parse('archived')).toBe('archived');
    expect(() => disputeCaseStatusSchema.parse('deleted')).toThrow();
  });

  it('admin action types include all V17 disciplinary options', () => {
    expect(adminActionTypeSchema.parse('verbal_warning')).toBe('verbal_warning');
    expect(adminActionTypeSchema.parse('termination')).toBe('termination');
    expect(adminActionTypeSchema.parse('no_action')).toBe('no_action');
    expect(() => adminActionTypeSchema.parse('exile')).toThrow();
  });

  it('executive decision enum covers approve/modify/reject/defer', () => {
    expect(executiveDecisionSchema.parse('approved')).toBe('approved');
    expect(executiveDecisionSchema.parse('modified')).toBe('modified');
    expect(executiveDecisionSchema.parse('rejected')).toBe('rejected');
    expect(executiveDecisionSchema.parse('deferred')).toBe('deferred');
    expect(executiveDecisionSchema.options).toHaveLength(4);
  });

  it('full admin action round-trips a decided + executed case', () => {
    const action = disputeAdminActionSchema.parse({
      proposedAction: 'written_warning',
      proposedActionDetail: 'تأخر متكرر بدون عذر مقبول',
      proposedAt: now,
      proposedBy: uuid,
      executiveDecision: 'modified',
      executiveDecisionReason: 'تخفيف الإجراء لأول مخالفة',
      executiveDecisionAt: now,
      executiveDecisionBy: uuid,
      approvedAction: 'verbal_warning',
      approvedActionDetail: 'إنذار شفهي مع تنبيه',
      executedAt: now,
      executedBy: uuid,
      executionNotes: 'تم إبلاغ الموظف',
    });
    expect(action.proposedAction).toBe('written_warning');
    expect(action.approvedAction).toBe('verbal_warning');
    expect(action.executiveDecision).toBe('modified');
  });

  it('propose input requires action type and detail', () => {
    const input = proposeAdminActionInputSchema.parse({
      caseId: uuid,
      proposedAction: 'salary_deduction',
      detail: 'خصم يوم واحد',
    });
    expect(input.proposedAction).toBe('salary_deduction');
    expect(() => proposeAdminActionInputSchema.parse({
      caseId: uuid,
      proposedAction: 'salary_deduction',
      detail: 'ab', // أقل من 3 أحرف
    })).toThrow();
  });

  it('executive decision input requires reason', () => {
    const input = executiveDecisionInputSchema.parse({
      caseId: uuid,
      decision: 'approved',
      reason: 'موافقة على الإجراء المقترح',
    });
    expect(input.decision).toBe('approved');
  });

  it('executive decision with modification requires modifiedAction', () => {
    const input = executiveDecisionInputSchema.parse({
      caseId: uuid,
      decision: 'modified',
      reason: 'تعديل الإجراء',
      modifiedAction: 'training_requirement',
      modifiedActionDetail: 'دورة تدريبية إلزامية',
    });
    expect(input.modifiedAction).toBe('training_requirement');
  });

  it('execute action input requires notes', () => {
    expect(() => executeActionInputSchema.parse({
      caseId: uuid,
      notes: 'ab',
    })).toThrow();
    const valid = executeActionInputSchema.parse({
      caseId: uuid,
      notes: 'تم تنفيذ الإجراء وإبلاغ الموظف',
    });
    expect(valid.notes).toContain('تم تنفيذ');
  });
});

describe('create dispute input — V23 §16', () => {
  it('accepts a valid dispute submission matching submit_my_dispute_v23 RPC', () => {
    const input = createDisputeInputSchema.parse({
      title: 'مشكلة تأخر رواتب',
      description: 'تأخر صرف الرواتب لمدة أسبوعين بدون إخطار مسبق',
      caseType: 'financial',
      parties: [uuid],
      witnesses: [],
      truthConfirmed: true,
      confidentialityAccepted: true,
    });
    expect(input.title).toBe('مشكلة تأخر رواتب');
    expect(input.caseType).toBe('financial');
    expect(input.parties).toHaveLength(1);
    expect(input.truthConfirmed).toBe(true);
  });

  it('defaults parties and witnesses to empty arrays', () => {
    const input = createDisputeInputSchema.parse({
      title: 'شكوى سلوكية',
      description: 'سلوك غير لائق في بيئة العمل يتطلب تدخل اللجنة',
      caseType: 'behavioral',
      truthConfirmed: true,
      confidentialityAccepted: false,
    });
    expect(input.parties).toEqual([]);
    expect(input.witnesses).toEqual([]);
  });

  it('rejects title shorter than 3 characters', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'ab',
      description: 'وصف كافٍ للمشكلة المطروحة أمام اللجنة',
      caseType: 'other',
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });

  it('rejects description shorter than 10 characters', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'عنوان كافٍ',
      description: 'قصير',
      caseType: 'other',
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });

  it('rejects invalid UUID in parties array', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'عنوان كافٍ',
      description: 'وصف كافٍ للمشكلة المطروحة أمام اللجنة',
      caseType: 'other',
      parties: ['not-a-uuid'],
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });
});

describe('create dispute input — V23 §16', () => {
  const uuid2 = '22222222-2222-4222-8222-222222222222';

  it('accepts a valid dispute submission with parties and witnesses', () => {
    const input = createDisputeInputSchema.parse({
      title: 'مشكلة إدارية',
      description: 'وصف تفصيلي للمشكلة الإدارية التي وقعت',
      caseType: 'administrative',
      parties: [uuid, uuid2],
      witnesses: [uuid2],
      truthConfirmed: true,
      confidentialityAccepted: true,
    });
    expect(input.title).toBe('مشكلة إدارية');
    expect(input.parties).toHaveLength(2);
    expect(input.witnesses).toHaveLength(1);
    expect(input.truthConfirmed).toBe(true);
  });

  it('defaults parties and witnesses to empty arrays', () => {
    const input = createDisputeInputSchema.parse({
      title: 'شكوى سلوكية',
      description: 'حدث موقف يستدعي التحقيق والمراجعة',
      caseType: 'behavioral',
      truthConfirmed: true,
      confidentialityAccepted: false,
    });
    expect(input.parties).toEqual([]);
    expect(input.witnesses).toEqual([]);
  });

  it('rejects title shorter than 3 chars', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'ab',
      description: 'وصف كافٍ للمشكلة المطروحة',
      caseType: 'other',
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });

  it('rejects description shorter than 10 chars', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'عنوان كافٍ',
      description: 'قصير',
      caseType: 'other',
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });

  it('rejects invalid UUID in parties array', () => {
    expect(() => createDisputeInputSchema.parse({
      title: 'عنوان كافٍ',
      description: 'وصف كافٍ للمشكلة المطروحة',
      caseType: 'other',
      parties: ['not-a-uuid'],
      truthConfirmed: true,
      confidentialityAccepted: true,
    })).toThrow();
  });
});
