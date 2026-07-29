import { describe, it, expect } from 'vitest';
import { kpiEvaluationSummarySchema } from '@ahla/shared-contracts';
import { mockKpiEvaluations } from '../mock/domainMocks';

describe('usePerformance — mock data schema validation', () => {
  it('parses all mock KPI evaluations against kpiEvaluationSummarySchema', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    expect(parsed).toHaveLength(mockKpiEvaluations.length);
  });

  it('contains exactly 3 evaluations', () => {
    expect(mockKpiEvaluations).toHaveLength(3);
  });

  it('all IDs are valid UUIDs', () => {
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      expect(kpi.id).toMatch(uuidRe);
      expect(kpi.employeeId).toMatch(uuidRe);
      expect(kpi.cycleId).toMatch(uuidRe);
    }
  });

  it('employeeCode follows EMP-NNN format', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      if (kpi.employeeCode) {
        expect(kpi.employeeCode).toMatch(/^EMP-\d{3}$/);
      }
    }
  });

  it('locked is always boolean', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      expect(typeof kpi.locked).toBe('boolean');
    }
  });

  it('finalScore is null or a non-negative number', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      if (kpi.finalScore !== null) {
        expect(kpi.finalScore).toBeGreaterThanOrEqual(0);
      }
    }
  });

  it('third evaluation has a finalScore', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    expect(parsed[2].finalScore).toBe(88);
    expect(parsed[2].finalRating).toBe('ممتاز');
  });

  it('criteria is an array', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      expect(Array.isArray(kpi.criteria)).toBe(true);
    }
  });

  it('periodMonth is a valid date string', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      const date = new Date(kpi.periodMonth);
      expect(date.getTime()).not.toBeNaN();
    }
  });

  it('currentStage is a valid stage value', () => {
    const parsed = kpiEvaluationSummarySchema.array().parse(mockKpiEvaluations);
    for (const kpi of parsed) {
      expect(typeof kpi.currentStage).toBe('string');
      expect(kpi.currentStage.length).toBeGreaterThan(0);
    }
  });
});
