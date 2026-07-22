import { describe, expect, it } from 'vitest';
import {
  kpiEvaluationFormSchema,
  kpiEvaluationSummarySchema,
  leaveTypeCode,
  workAssignmentSchema,
  workAssignmentType,
} from './operations.js';

describe('leave and work-assignment contracts', () => {
  it('exposes the four legal leave codes and excludes maternity/childcare', () => {
    expect(leaveTypeCode.options).toEqual(['annual', 'casual', 'sick', 'unpaid']);
    expect(() => leaveTypeCode.parse('maternity')).toThrow();
    expect(() => leaveTypeCode.parse('childcare')).toThrow();
  });

  it('models the three work-assignment types', () => {
    expect(workAssignmentType.options).toEqual(['MISSION', 'CONVOY', 'FUNDRAISING']);
  });

  it('parses a fundraising assignment with a financial target', () => {
    const asg = workAssignmentSchema.parse({
      id: '55000000-0000-4000-8000-000000000001', assignmentNumber: 1,
      assignmentType: 'FUNDRAISING', title: 'حملة فاندي', description: null, status: 'APPROVED',
      createdByEmployeeId: null, responsibleEmployeeId: null,
      startAt: new Date().toISOString(), endAt: new Date().toISOString(), isFullDay: true,
      location: null, countsAsWorkDay: true, needsReport: false, reportDueAt: null,
      targetAmount: 50000, achievedAmount: null, createdAt: new Date().toISOString(),
    });
    expect(asg.assignmentType).toBe('FUNDRAISING');
    expect(asg.targetAmount).toBe(50000);
  });
});

describe('official KPI contracts', () => {
  it('accepts the HR and employee acknowledgement workflow stages', () => {
    expect(kpiEvaluationSummarySchema.shape.currentStage.parse('hr_review')).toBe('hr_review');
    expect(kpiEvaluationSummarySchema.shape.currentStage.parse('manager_final')).toBe('manager_final');
  });

  it('parses server-authored attendance and the seven official components', () => {
    const codes = ['TARGET', 'EFFICIENCY', 'ATTENDANCE', 'CONDUCT', 'PRAYER', 'HALAQA', 'INITIATIVES'];
    const form = kpiEvaluationFormSchema.parse({
      id: '42000000-0000-4000-8000-000000000001', employeeId: '30000000-0000-4000-8000-000000000001', employeeName: 'موظف', employeeCode: null,
      periodMonth: '2026-07-01', currentStage: 'hr_review', workflowStatus: 'HR_REVIEW', editableStage: 'hr_review', locked: false, finalScore: null, finalRating: null,
      criteria: codes.map((code, index) => ({ id: `41000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`, code, name: code, description: null, sectionCode: code, weight: code === 'TARGET' ? 40 : 10, maxScore: code === 'TARGET' ? 40 : 10, sortOrder: index, sourceType: code === 'ATTENDANCE' ? 'attendance' : 'manual', evaluatorStage: code === 'ATTENDANCE' ? 'hr' : 'manager', calculationMethod: code === 'ATTENDANCE' ? 'attendance' : 'manual', editable: false, effectiveScore: code === 'ATTENDANCE' ? 18 : null, stageScores: {} })),
      goals: [], session: null, compliance: [], attendance: { periodStart: '2026-07-01', periodEnd: '2026-07-25', lateCount: 1, earlyLeaveCount: 0, unexcusedAbsenceCount: 0, shortagePenalty: 1, missingPunchCount: 0, score: 18, hasPendingItems: false, calculatedAt: new Date().toISOString() },
      cycle: { id: '43000000-0000-4000-8000-000000000001', status: 'open', scheduledOpenAt: new Date().toISOString(), deadlineAt: new Date().toISOString(), extendedUntil: null, effectiveDeadline: new Date().toISOString() },
      validationErrors: [], lastUpdatedAt: new Date().toISOString(),
    });
    expect(form.criteria.map((item) => item.code)).toEqual(codes);
    expect(form.attendance?.score).toBe(18);
  });
});
