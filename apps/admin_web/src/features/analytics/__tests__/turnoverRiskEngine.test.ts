import { describe, expect, it } from 'vitest';
import { calculateTurnoverRisk, type EmployeeTurnoverMetrics } from '../turnoverRiskEngine';

describe('calculateTurnoverRisk', () => {
  it('returns low risk for stable employees with zero absences and good performance', () => {
    const metrics: EmployeeTurnoverMetrics = {
      employeeId: 'emp-1',
      fullName: 'أحمد علي',
      unexcusedAbsencesLast60Days: 0,
      latePunchesLast30Days: 0,
      weekendAdjacentAbsences: 0,
      currentKpiScore: 92,
      previousKpiScore: 90,
      activeDisputesCount: 0,
      warningsLast90Days: 0,
      daysSinceLastAnnualLeave: 60,
      overtimeHoursLastMonth: 5,
      monthsInRole: 6,
    };

    const assessment = calculateTurnoverRisk(metrics);
    expect(assessment.riskLevel).toBe('low');
    expect(assessment.overallScore).toBeLessThan(25);
  });

  it('detects high or critical risk when employee has multiple unexcused absences, kpi drop, and active disputes', () => {
    const metrics: EmployeeTurnoverMetrics = {
      employeeId: 'emp-2',
      fullName: 'محمود حسن',
      unexcusedAbsencesLast60Days: 4,
      latePunchesLast30Days: 8,
      weekendAdjacentAbsences: 3,
      currentKpiScore: 55,
      previousKpiScore: 85,
      activeDisputesCount: 2,
      warningsLast90Days: 1,
      daysSinceLastAnnualLeave: 300,
      overtimeHoursLastMonth: 45,
      monthsInRole: 18,
    };

    const assessment = calculateTurnoverRisk(metrics);
    expect(['high', 'critical']).toContain(assessment.riskLevel);
    expect(assessment.overallScore).toBeGreaterThanOrEqual(50);
    expect(assessment.topFactors.length).toBeGreaterThan(0);
    expect(assessment.recommendedAction).toContain('تدخل');
  });
});
