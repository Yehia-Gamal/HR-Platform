import { describe, expect, it } from 'vitest';
import {
  disputeCaseStatusSchema,
  adminActionTypeSchema,
  executiveDecisionSchema,
  disputeAdminActionSchema,
  proposeAdminActionInputSchema,
  executiveDecisionInputSchema,
  executeActionInputSchema,
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
