import { describe, it, expect } from 'vitest';
import { attendanceStatementSchema, attendanceStatementDaySchema } from '@ahla/shared-contracts';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const mockDay = {
  date: '2026-06-01',
  dayNameAr: 'الأحد',
  checkIn: '08:05:00',
  checkOut: '16:30:00',
  shiftName: 'الدوام الرسمي',
  workHours: 8.42,
  requiredHours: 8,
  lateMinutes: 5,
  earlyLeaveMinutes: 0,
  overtimeMinutes: 25,
  status: 'present',
  isAbsent: false,
  isOfficialHoliday: false,
  hasLeave: false,
  hasLatePermit: false,
  hasEarlyPermit: false,
  hasPermit: false,
  hasMission: false,
  hasConvoyFundi: false,
  missingCheckIn: false,
  missingCheckOut: false,
  hasCorrection: false,
  correctionNote: null,
  notes: null,
  penalties: 0,
};

const mockStatement = {
  employee: {
    id: '20000000-0000-4000-8000-000000000001',
    employeeCode: 'EMP-001',
    fullNameAr: 'أحمد محمد حسن',
    jobTitle: 'مطور برمجيات',
    department: 'تقنية المعلومات',
    manager: 'سعيد عبدالله',
    branch: 'الفرع الرئيسي',
    hireDate: '2024-01-15',
  },
  period: {
    year: 2026,
    month: 6,
    startDate: '2026-06-01',
    endDate: '2026-06-30',
    generatedAt: '2026-07-01T08:00:00Z',
  },
  days: [mockDay],
  summary: {
    totalDays: 30,
    scheduledDays: 22,
    dueScheduledDays: 22,
    upcomingDays: 0,
    presentDays: 20,
    absentDays: 1,
    openShiftDays: 0,
    completedPresenceDays: 20,
    leaveDays: 1,
    permitCount: 2,
    missionDays: 0,
    convoyFundiDays: 0,
    holidayDays: 0,
    restDays: 8,
    totalWorkHours: 168,
    totalRequiredHours: 176,
    averageWorkHours: 8.4,
    totalLateMinutes: 45,
    totalEarlyLeaveMinutes: 10,
    totalOvertimeMinutes: 120,
    missingCheckInCount: 0,
    missingCheckOutCount: 1,
    correctionCount: 0,
    attendanceRate: 90.91,
    hoursComplianceRate: 95.45,
    hoursComplianceAvailable: true,
  },
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('useMonthlyStatement — attendanceStatementSchema validation', () => {
  it('attendanceStatementDaySchema parses mockDay', () => {
    expect(() => attendanceStatementDaySchema.parse(mockDay)).not.toThrow();
  });

  it('attendanceStatementSchema parses full mockStatement', () => {
    expect(() => attendanceStatementSchema.parse(mockStatement)).not.toThrow();
  });

  it('employee.id is a valid UUID', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    expect(parsed.employee.id).toMatch(uuidRegex);
  });

  it('period.year and period.month are valid', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    expect(parsed.period.year).toBeGreaterThan(2000);
    expect(parsed.period.month).toBeGreaterThanOrEqual(1);
    expect(parsed.period.month).toBeLessThanOrEqual(12);
  });

  it('days is an array', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    expect(Array.isArray(parsed.days)).toBe(true);
  });

  it('summary numeric fields are non-negative', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    const { summary } = parsed;
    expect(summary.totalDays).toBeGreaterThanOrEqual(0);
    expect(summary.scheduledDays).toBeGreaterThanOrEqual(0);
    expect(summary.dueScheduledDays).toBeGreaterThanOrEqual(0);
    expect(summary.upcomingDays).toBeGreaterThanOrEqual(0);
    expect(summary.presentDays).toBeGreaterThanOrEqual(0);
    expect(summary.absentDays).toBeGreaterThanOrEqual(0);
    expect(summary.leaveDays).toBeGreaterThanOrEqual(0);
    expect(summary.permitCount).toBeGreaterThanOrEqual(0);
    expect(summary.missionDays).toBeGreaterThanOrEqual(0);
    expect(summary.convoyFundiDays).toBeGreaterThanOrEqual(0);
    expect(summary.holidayDays).toBeGreaterThanOrEqual(0);
    expect(summary.restDays).toBeGreaterThanOrEqual(0);
    expect(summary.totalWorkHours).toBeGreaterThanOrEqual(0);
    expect(summary.totalRequiredHours).toBeGreaterThanOrEqual(0);
    expect(summary.averageWorkHours).toBeGreaterThanOrEqual(0);
    expect(summary.totalLateMinutes).toBeGreaterThanOrEqual(0);
    expect(summary.totalEarlyLeaveMinutes).toBeGreaterThanOrEqual(0);
    expect(summary.totalOvertimeMinutes).toBeGreaterThanOrEqual(0);
    expect(summary.missingCheckInCount).toBeGreaterThanOrEqual(0);
    expect(summary.missingCheckOutCount).toBeGreaterThanOrEqual(0);
    expect(summary.correctionCount).toBeGreaterThanOrEqual(0);
  });

  it('presentDays + absentDays <= scheduledDays', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    const { presentDays, absentDays, scheduledDays } = parsed.summary;
    expect(presentDays + absentDays).toBeLessThanOrEqual(scheduledDays);
  });

  it('attendanceRate is between 0 and 100', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    expect(parsed.summary.attendanceRate).toBeGreaterThanOrEqual(0);
    expect(parsed.summary.attendanceRate).toBeLessThanOrEqual(100);
  });

  it('current-month rate uses due days and keeps future days separate', () => {
    const current = attendanceStatementSchema.parse({
      ...mockStatement,
      summary: {
        ...mockStatement.summary,
        scheduledDays: 27,
        dueScheduledDays: 3,
        upcomingDays: 24,
        presentDays: 2,
        absentDays: 1,
        openShiftDays: 1,
        completedPresenceDays: 1,
        attendanceRate: 66.67,
      },
    });
    expect(current.summary.attendanceRate).toBe(66.67);
    expect(current.summary.upcomingDays).toBe(24);
    expect(current.summary.openShiftDays).toBe(1);
  });

  it('hoursComplianceRate is between 0 and 100', () => {
    const parsed = attendanceStatementSchema.parse(mockStatement);
    expect(parsed.summary.hoursComplianceRate).toBeGreaterThanOrEqual(0);
    expect(parsed.summary.hoursComplianceRate).toBeLessThanOrEqual(100);
  });

  it('day boolean fields default correctly', () => {
    const minimalDay = {
      date: '2026-06-02',
      dayNameAr: 'الاثنين',
      checkIn: '08:00:00',
      checkOut: '16:00:00',
      shiftName: 'الدوام الرسمي',
      workHours: 8,
      requiredHours: 8,
      lateMinutes: 0,
      earlyLeaveMinutes: 0,
      overtimeMinutes: 0,
      status: 'present',
      correctionNote: null,
    };
    const parsed = attendanceStatementDaySchema.parse(minimalDay);
    expect(parsed.isAbsent).toBe(false);
    expect(parsed.isOfficialHoliday).toBe(false);
    expect(parsed.hasLeave).toBe(false);
    expect(parsed.hasLatePermit).toBe(false);
    expect(parsed.hasEarlyPermit).toBe(false);
    expect(parsed.hasPermit).toBe(false);
    expect(parsed.hasMission).toBe(false);
    expect(parsed.hasConvoyFundi).toBe(false);
    expect(parsed.missingCheckIn).toBe(false);
    expect(parsed.missingCheckOut).toBe(false);
    expect(parsed.hasCorrection).toBe(false);
    expect(parsed.notes).toBeNull();
    expect(parsed.penalties).toBe(0);
    expect(parsed.isFuture).toBe(false);
    expect(parsed.isOpenShift).toBe(false);
  });

  it('checkIn and checkOut are nullable', () => {
    const dayWithNullTimes = { ...mockDay, checkIn: null, checkOut: null };
    const parsed = attendanceStatementDaySchema.parse(dayWithNullTimes);
    expect(parsed.checkIn).toBeNull();
    expect(parsed.checkOut).toBeNull();
  });

  it('employee.hireDate is nullable', () => {
    const statementWithNullHireDate = {
      ...mockStatement,
      employee: { ...mockStatement.employee, hireDate: null },
    };
    const parsed = attendanceStatementSchema.parse(statementWithNullHireDate);
    expect(parsed.employee.hireDate).toBeNull();
  });
});
