import { describe, it, expect, vi } from 'vitest';
import {
  executiveMonthlyReportSchema,
  MOCK_EXECUTIVE_MONTHLY_REPORT,
} from '../useExecutiveMonthlyReport';

describe('useExecutiveMonthlyReport', () => {
  it('validates mock executive monthly report schema correctly', () => {
    const parsed = executiveMonthlyReportSchema.parse(MOCK_EXECUTIVE_MONTHLY_REPORT);
    expect(parsed.period.year).toBe(2026);
    expect(parsed.period.month).toBe(10);
    expect(parsed.attendance.active_employees_count).toBe(52);
    expect(parsed.attendance.attendance_rate).toBe(94.0);
    expect(parsed.departments.length).toBe(4);
    expect(parsed.requests.approved_count).toBe(98);
    expect(parsed.missions.auto_closed_count).toBe(3);
    expect(parsed.penalties.paid_amount).toBe(1450);
    expect(parsed.sla.avg_turnaround_hours).toBe(14.8);
  });

  it('rejects invalid executive report schemas', () => {
    const invalid = {
      ...MOCK_EXECUTIVE_MONTHLY_REPORT,
      attendance: {
        ...MOCK_EXECUTIVE_MONTHLY_REPORT.attendance,
        attendance_rate: 'invalid-string',
      },
    };
    expect(() => executiveMonthlyReportSchema.parse(invalid)).toThrow();
  });
});
