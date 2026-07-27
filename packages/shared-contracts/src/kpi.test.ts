import { describe, expect, it } from 'vitest';
import {
  kpiStageSchema,
  KPI_STAGE_ORDER,
  kpiWorkflowStatusSchema,
  kpiCriterionCodeSchema,
  KPI_CRITERIA_WEIGHTS,
  KPI_CRITERION_EVALUATOR,
  kpiScoreInputSchema,
  kpiComplianceInputSchema,
  kpiRatingBandSchema,
  kpiEvaluationSummarySchema,
} from './kpi.js';

describe('KPI contracts — V23 §8', () => {
  it('stage enum follows V23 order: self → parallel → hr → manager → final → secretary → executive → finalized → closed → archived', () => {
    expect(kpiStageSchema.parse('self')).toBe('self');
    expect(kpiStageSchema.parse('parallel_review')).toBe('parallel_review');
    expect(kpiStageSchema.parse('hr_review')).toBe('hr_review');
    expect(kpiStageSchema.parse('manager_review')).toBe('manager_review');
    expect(kpiStageSchema.parse('manager_final')).toBe('manager_final');
    expect(kpiStageSchema.parse('secretary_review')).toBe('secretary_review');
    expect(kpiStageSchema.parse('executive_review')).toBe('executive_review');
    expect(kpiStageSchema.parse('finalized')).toBe('finalized');
    expect(() => kpiStageSchema.parse('executive')).toThrow();
  });

  it('KPI_STAGE_ORDER matches the stage enum in V23 sequence', () => {
    expect(KPI_STAGE_ORDER[0]).toBe('self');
    expect(KPI_STAGE_ORDER[1]).toBe('parallel_review');
    expect(KPI_STAGE_ORDER[2]).toBe('hr_review');
    expect(KPI_STAGE_ORDER[3]).toBe('manager_review');
    expect(KPI_STAGE_ORDER[4]).toBe('manager_final');
    expect(KPI_STAGE_ORDER[5]).toBe('secretary_review');
    expect(KPI_STAGE_ORDER[6]).toBe('executive_review');
    expect(KPI_STAGE_ORDER[7]).toBe('finalized');
    expect(KPI_STAGE_ORDER).toHaveLength(10);
  });

  it('workflow statuses include SUBMITTED_TO_HR for V17 flow', () => {
    expect(kpiWorkflowStatusSchema.parse('SUBMITTED_TO_HR')).toBe('SUBMITTED_TO_HR');
    expect(kpiWorkflowStatusSchema.parse('INCLUDED_IN_MONTHLY_REPORT')).toBe('INCLUDED_IN_MONTHLY_REPORT');
    expect(kpiWorkflowStatusSchema.parse('RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL')).toBe('RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL');
    expect(() => kpiWorkflowStatusSchema.parse('SUBMITTED_TO_EXECUTIVE')).toThrow();
  });

  it('7 official criteria total exactly 100 points', () => {
    const codes = kpiCriterionCodeSchema.options;
    expect(codes).toHaveLength(7);
    const total = codes.reduce((sum, c) => sum + KPI_CRITERIA_WEIGHTS[c], 0);
    expect(total).toBe(100);
  });

  it('criteria weights match V17 §10.2 specification', () => {
    expect(KPI_CRITERIA_WEIGHTS.TARGET).toBe(40);
    expect(KPI_CRITERIA_WEIGHTS.EFFICIENCY).toBe(20);
    expect(KPI_CRITERIA_WEIGHTS.ATTENDANCE).toBe(20);
    expect(KPI_CRITERIA_WEIGHTS.CONDUCT).toBe(5);
    expect(KPI_CRITERIA_WEIGHTS.PRAYER).toBe(5);
    expect(KPI_CRITERIA_WEIGHTS.HALAQA).toBe(5);
    expect(KPI_CRITERIA_WEIGHTS.INITIATIVES).toBe(5);
  });

  it('V23 §8: HR owns attendance + prayer + halaqa (30); manager owns target + efficiency + conduct + initiatives (70)', () => {
    expect(KPI_CRITERION_EVALUATOR.ATTENDANCE).toBe('hr');
    expect(KPI_CRITERION_EVALUATOR.PRAYER).toBe('hr');
    expect(KPI_CRITERION_EVALUATOR.HALAQA).toBe('hr');
    expect(KPI_CRITERION_EVALUATOR.TARGET).toBe('manager');
    expect(KPI_CRITERION_EVALUATOR.EFFICIENCY).toBe('manager');
    expect(KPI_CRITERION_EVALUATOR.CONDUCT).toBe('manager');
    expect(KPI_CRITERION_EVALUATOR.INITIATIVES).toBe('manager');
  });

  it('score input validates range and criterion_id', () => {
    expect(() => kpiScoreInputSchema.parse({ criterion_id: 'bad', score: 5 })).toThrow();
    const valid = kpiScoreInputSchema.parse({
      criterion_id: '11111111-1111-4111-8111-111111111111',
      score: 32,
      note: 'ملاحظة',
    });
    expect(valid.score).toBe(32);
    expect(() => kpiScoreInputSchema.parse({
      criterion_id: '11111111-1111-4111-8111-111111111111',
      score: -1,
    })).toThrow();
  });

  it('compliance input validates PRAYER and HALAQA metrics', () => {
    const valid = kpiComplianceInputSchema.parse({
      evaluationId: '11111111-1111-4111-8111-111111111111',
      metric: 'PRAYER',
      totalDays: 10,
      attendedDays: 10,
    });
    expect(valid.metric).toBe('PRAYER');
    expect(valid.excusedDays).toBe(0);
    expect(() => kpiComplianceInputSchema.parse({
      evaluationId: '11111111-1111-4111-8111-111111111111',
      metric: 'UNKNOWN',
      totalDays: 5,
      attendedDays: 3,
    })).toThrow();
  });

  it('rating band schema validates min/max/label', () => {
    const band = kpiRatingBandSchema.parse({ min: 0, max: 60, label: 'ضعيف' });
    expect(band.label).toBe('ضعيف');
  });

  it('evaluation summary round-trips a finalized evaluation', () => {
    const summary = kpiEvaluationSummarySchema.parse({
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'موظف اختبار',
      employeeCode: 'EMP-001',
      cycleId: '33333333-3333-4333-8333-333333333333',
      periodMonth: '2026-07',
      currentStage: 'finalized',
      workflowStatus: 'INCLUDED_IN_MONTHLY_REPORT',
      locked: true,
      editable: null,
      finalScore: 83.75,
      finalRating: 'جيد جداً',
      finalBreakdown: { TARGET: 32, EFFICIENCY: 16, ATTENDANCE: 20, CONDUCT: 4, PRAYER: 5, HALAQA: 3.75, INITIATIVES: 3 },
      managerComment: 'أداء جيد',
      hrComment: 'التزام كامل',
      criteria: [{
        id: '44444444-4444-4444-8444-444444444444',
        code: 'TARGET',
        nameAr: 'الأهداف',
        description: null,
        maxScore: 40,
        evaluatorStage: 'manager',
        sourceType: 'manual',
        calculationMethod: null,
        requiresEvidence: false,
      }],
      scores: {
        '44444444-4444-4444-8444-444444444444': { self: 32, manager: 32, secretary: null, effective: 32 },
      },
    });
    expect(summary.finalScore).toBe(83.75);
    expect(summary.currentStage).toBe('finalized');
  });
});
