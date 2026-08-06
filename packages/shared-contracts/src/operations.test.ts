import { describe, expect, it } from 'vitest';
import {
  kpiEvaluationFormSchema,
  kpiEvaluationSummarySchema,
  leaveTypeCodeSchema,
  workAssignmentSchema,
  workAssignmentTypeSchema,
  attendanceStatementDaySchema,
  attendanceStatementSchema,
  attendanceRosterCategorySchema,
  attendanceRosterPageSchema,
  attendanceRosterSortSchema,
} from './operations.js';

describe('leave and work-assignment contracts', () => {
  it('exposes the four legal leave codes and excludes maternity/childcare', () => {
    expect(leaveTypeCodeSchema.options).toEqual(['annual', 'casual', 'sick', 'unpaid']);
    expect(() => leaveTypeCodeSchema.parse('maternity')).toThrow();
    expect(() => leaveTypeCodeSchema.parse('childcare')).toThrow();
  });

  it('models the three work-assignment types', () => {
    expect(workAssignmentTypeSchema.options).toEqual(['MISSION', 'CONVOY', 'FUNDRAISING']);
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

describe('attendance statement contracts — V23 §14', () => {
  const baseDay = {
    date: '2026-07-20', dayNameAr: 'الأحد',
    checkIn: '10:02', checkOut: '18:05', shiftName: 'الدوام الرسمي',
    workHours: 8, requiredHours: 8, lateMinutes: 2, earlyLeaveMinutes: 0,
    overtimeMinutes: 5, status: 'present', hasLeave: false, hasPermit: false,
    hasMission: false, hasConvoyFundi: false, missingCheckIn: false,
    missingCheckOut: false, hasCorrection: false, correctionNote: null,
  };

  it('day schema defaults V23 fields when omitted', () => {
    const day = attendanceStatementDaySchema.parse(baseDay);
    expect(day.isAbsent).toBe(false);
    expect(day.isOfficialHoliday).toBe(false);
    expect(day.hasLatePermit).toBe(false);
    expect(day.hasEarlyPermit).toBe(false);
    expect(day.notes).toBeNull();
    expect(day.penalties).toBe(0);
  });

  it('day schema accepts V23 permit split and penalties', () => {
    const day = attendanceStatementDaySchema.parse({
      ...baseDay,
      isAbsent: false,
      isOfficialHoliday: false,
      hasLatePermit: true,
      hasEarlyPermit: false,
      hasPermit: true,
      notes: 'إذن حضور ساعة',
      penalties: 1,
    });
    expect(day.hasLatePermit).toBe(true);
    expect(day.hasEarlyPermit).toBe(false);
    expect(day.notes).toBe('إذن حضور ساعة');
    expect(day.penalties).toBe(1);
  });

  it('statement summary includes V23 rate fields with defaults', () => {
    const stmt = attendanceStatementSchema.parse({
      employee: {
        id: '30000000-0000-4000-8000-000000000001',
        employeeCode: 'E001', fullNameAr: 'موظف', jobTitle: 'مسؤول',
        department: 'الإدارة', manager: 'مدير', branch: 'الرئيسية', hireDate: null,
      },
      period: { year: 2026, month: 7, startDate: '2026-07-01', endDate: '2026-07-31', generatedAt: new Date().toISOString() },
      days: [baseDay],
      summary: {
        totalDays: 31, scheduledDays: 22, presentDays: 20, absentDays: 2,
        leaveDays: 0, permitCount: 1, missionDays: 0, convoyFundiDays: 0,
        holidayDays: 4, restDays: 5, totalWorkHours: 160, averageWorkHours: 8,
        totalLateMinutes: 30, totalEarlyLeaveMinutes: 0, totalOvertimeMinutes: 10,
        missingCheckInCount: 0, missingCheckOutCount: 1, correctionCount: 0,
      },
    });
    expect(stmt.summary.totalRequiredHours).toBe(0);
    expect(stmt.summary.attendanceRate).toBe(0);
    expect(stmt.summary.hoursComplianceRate).toBe(0);
  });

  it('statement summary accepts explicit V23 rate values', () => {
    const stmt = attendanceStatementSchema.parse({
      employee: {
        id: '30000000-0000-4000-8000-000000000001',
        employeeCode: 'E001', fullNameAr: 'موظف', jobTitle: 'مسؤول',
        department: 'الإدارة', manager: 'مدير', branch: 'الرئيسية', hireDate: null,
      },
      period: { year: 2026, month: 7, startDate: '2026-07-01', endDate: '2026-07-31', generatedAt: new Date().toISOString() },
      days: [],
      summary: {
        totalDays: 31, scheduledDays: 22, presentDays: 21, absentDays: 1,
        leaveDays: 0, permitCount: 0, missionDays: 0, convoyFundiDays: 0,
        holidayDays: 4, restDays: 5, totalWorkHours: 168, totalRequiredHours: 176,
        averageWorkHours: 8, totalLateMinutes: 15, totalEarlyLeaveMinutes: 0,
        totalOvertimeMinutes: 5, missingCheckInCount: 0, missingCheckOutCount: 0,
        correctionCount: 0, attendanceRate: 95.45, hoursComplianceRate: 95.45,
      },
    });
    expect(stmt.summary.totalRequiredHours).toBe(176);
    expect(stmt.summary.attendanceRate).toBe(95.45);
    expect(stmt.summary.hoursComplianceRate).toBe(95.45);
  });
});

describe('attendance statement contracts — V23 §14', () => {
  const baseDay = {
    date: '2026-07-01', dayNameAr: 'الأربعاء',
    checkIn: '10:02', checkOut: '18:05', shiftName: 'الوردية الصباحية',
    workHours: 8, requiredHours: 8, lateMinutes: 2, earlyLeaveMinutes: 0,
    overtimeMinutes: 5, status: 'present',
    hasLeave: false, hasPermit: false, hasMission: false,
    hasConvoyFundi: false, missingCheckIn: false, missingCheckOut: false,
    hasCorrection: false, correctionNote: null,
  };

  it('day schema defaults V23 fields when omitted', () => {
    const day = attendanceStatementDaySchema.parse(baseDay);
    expect(day.isAbsent).toBe(false);
    expect(day.isOfficialHoliday).toBe(false);
    expect(day.hasLatePermit).toBe(false);
    expect(day.hasEarlyPermit).toBe(false);
    expect(day.notes).toBeNull();
    expect(day.penalties).toBe(0);
  });

  it('day schema accepts V23 fields explicitly', () => {
    const day = attendanceStatementDaySchema.parse({
      ...baseDay,
      isAbsent: true,
      isOfficialHoliday: false,
      hasLatePermit: true,
      hasEarlyPermit: false,
      notes: 'تأخر بسبب ازدحام',
      penalties: 0.5,
    });
    expect(day.isAbsent).toBe(true);
    expect(day.hasLatePermit).toBe(true);
    expect(day.notes).toBe('تأخر بسبب ازدحام');
    expect(day.penalties).toBe(0.5);
  });

  it('summary schema includes V23 rate fields with defaults', () => {
    const stmt = attendanceStatementSchema.parse({
      employee: {
        id: '30000000-0000-4000-8000-000000000001',
        employeeCode: 'E001', fullNameAr: 'موظف', jobTitle: 'مطور',
        department: 'التقنية', manager: 'مدير', branch: 'الرئيسي',
        hireDate: '2025-01-01',
      },
      period: {
        year: 2026, month: 7,
        startDate: '2026-07-01', endDate: '2026-07-31',
        generatedAt: new Date().toISOString(),
      },
      days: [],
      summary: {
        totalDays: 31, scheduledDays: 22, presentDays: 20,
        absentDays: 2, leaveDays: 0, permitCount: 1,
        missionDays: 0, convoyFundiDays: 0, holidayDays: 4,
        restDays: 5, totalWorkHours: 160, averageWorkHours: 8,
        totalLateMinutes: 15, totalEarlyLeaveMinutes: 0,
        totalOvertimeMinutes: 30, missingCheckInCount: 0,
        missingCheckOutCount: 1, correctionCount: 0,
      },
    });
    expect(stmt.summary.totalRequiredHours).toBe(0);
    expect(stmt.summary.attendanceRate).toBe(0);
    expect(stmt.summary.hoursComplianceRate).toBe(0);
  });

  it('summary schema accepts explicit V23 rate values', () => {
    const stmt = attendanceStatementSchema.parse({
      employee: {
        id: '30000000-0000-4000-8000-000000000001',
        employeeCode: 'E002', fullNameAr: 'موظف ب', jobTitle: 'محاسب',
        department: 'المالية', manager: 'المدير', branch: 'الرئيسي',
        hireDate: null,
      },
      period: {
        year: 2026, month: 7,
        startDate: '2026-07-01', endDate: '2026-07-31',
        generatedAt: new Date().toISOString(),
      },
      days: [],
      summary: {
        totalDays: 31, scheduledDays: 22, presentDays: 22,
        absentDays: 0, leaveDays: 0, permitCount: 0,
        missionDays: 0, convoyFundiDays: 0, holidayDays: 4,
        restDays: 5, totalWorkHours: 176, totalRequiredHours: 176,
        averageWorkHours: 8, totalLateMinutes: 0,
        totalEarlyLeaveMinutes: 0, totalOvertimeMinutes: 0,
        missingCheckInCount: 0, missingCheckOutCount: 0,
        correctionCount: 0,
        attendanceRate: 100,
        hoursComplianceRate: 100,
      },
    });
    expect(stmt.summary.totalRequiredHours).toBe(176);
    expect(stmt.summary.attendanceRate).toBe(100);
    expect(stmt.summary.hoursComplianceRate).toBe(100);
  });

  it('rejects attendanceRate above 100', () => {
    expect(() => attendanceStatementSchema.parse({
      employee: {
        id: '30000000-0000-4000-8000-000000000001',
        employeeCode: null, fullNameAr: 'x', jobTitle: 'x',
        department: 'x', manager: 'x', branch: 'x', hireDate: null,
      },
      period: { year: 2026, month: 7, startDate: '2026-07-01', endDate: '2026-07-31', generatedAt: new Date().toISOString() },
      days: [],
      summary: {
        totalDays: 31, scheduledDays: 22, presentDays: 22, absentDays: 0,
        leaveDays: 0, permitCount: 0, missionDays: 0, convoyFundiDays: 0,
        holidayDays: 0, restDays: 0, totalWorkHours: 0, averageWorkHours: 0,
        totalLateMinutes: 0, totalEarlyLeaveMinutes: 0, totalOvertimeMinutes: 0,
        missingCheckInCount: 0, missingCheckOutCount: 0, correctionCount: 0,
        attendanceRate: 150,
        hoursComplianceRate: 50,
      },
    })).toThrow();
  });
});

describe('attendance drill-down contracts (0294)', () => {
  it('exposes the nine roster categories in the documented order', () => {
    expect(attendanceRosterCategorySchema.options).toEqual([
      'scheduled',
      'present',
      'late',
      'absent',
      'unexcused_absent',
      'incomplete',
      'pending_review',
      'location_requests',
      'location_responded',
    ]);
    expect(() => attendanceRosterCategorySchema.parse('unknown')).toThrow();
  });

  it('exposes the four sort keys and both directions', () => {
    expect(attendanceRosterSortSchema.options).toEqual(['name', 'check_in', 'late', 'status']);
    expect(() => attendanceRosterSortSchema.parse('date')).toThrow();
  });

  it('parses a paginated page with rich items', () => {
    const now = new Date().toISOString();
    const page = attendanceRosterPageSchema.parse({
      items: [
        {
          employeeId: '30000000-0000-4000-8000-000000000001',
          employeeName: 'أحمد محمود',
          employeeCode: 'EMP-104',
          photoUrl: null,
          departmentId: null,
          departmentName: 'الحسابات',
          branchId: null,
          branchName: null,
          jobTitle: 'محاسب أول',
          managerId: null,
          managerName: null,
          status: 'late',
          lateMinutes: 25,
          firstCheckIn: now,
          lastCheckOut: null,
          shiftName: 'صباحية',
          shiftStartAt: '09:00:00',
          shiftEndAt: '17:00:00',
          requiresReview: false,
          reviewReason: null,
          hasApprovedLeave: false,
          leaveCode: null,
          leaveIsPaid: null,
          hasMission: false,
          locationRequestStatus: null,
          locationRequestedAt: null,
          locationRespondedAt: null,
        },
      ],
      total: 1,
      limit: 25,
      offset: 0,
    });
    const first = page.items[0];
    expect(first?.lateMinutes).toBe(25);
    expect(first?.shiftStartAt).toBe('09:00:00');
    expect(page.total).toBe(1);
  });
});
