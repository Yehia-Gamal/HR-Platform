import type { AttendanceStatement } from '@ahla/shared-contracts';
import { describe, expect, it } from 'vitest';
import { arDays, fmtPct, getDisplayNote, rateText, statementRates } from './attendanceShared';

const summary = (over: Partial<AttendanceStatement['summary']>) =>
  ({
    attendanceRate: 0,
    hoursComplianceRate: 0,
    hoursComplianceAvailable: false,
    totalRequiredHours: 0,
    isAttendanceExempt: false,
    scheduledDays: 26,
    presentDays: 0,
    ...over,
  }) as AttendanceStatement['summary'];

describe('statementRates', () => {
  it('يعتمد أساس الخادم للمستحق والمحضور', () => {
    const r = statementRates(
      summary({
        attendanceRate: 80,
        attendanceRateBasis: { presentInDue: 20, dueDays: 25, presentDays: 18, absentDays: 5, openShiftDays: 0, upcomingDays: 0, excludedLeaveDays: 2 },
      }),
    );
    expect(r.attendance).toMatchObject({ available: true, pct: 80, present: 20, due: 25, excludedLeave: 2 });
  });

  it('المعفى: النسب غير متاحة ويُعرض «معفى»', () => {
    const r = statementRates(summary({ isAttendanceExempt: true, hoursComplianceAvailable: true, totalRequiredHours: 8 }));
    expect(r.exempt).toBe(true);
    expect(r.attendance.available).toBe(false);
    expect(r.hours.available).toBe(false);
    expect(rateText(r.attendance, r.exempt)).toBe('معفى');
  });

  it('بلا أيام مستحقة: «غير متاح» لا 0%', () => {
    const r = statementRates(
      summary({ attendanceRateBasis: { presentInDue: 0, dueDays: 0, presentDays: 0, absentDays: 0, openShiftDays: 0, upcomingDays: 0 } }),
    );
    expect(rateText(r.attendance, r.exempt)).toBe('غير متاح');
  });
});

describe('fmtPct / arDays', () => {
  it('لا تُقرَّب 99.6% إلى 100%', () => {
    expect(fmtPct(99.6)).toBe('99%');
    expect(fmtPct(100)).toBe('100%');
    expect(fmtPct(52.38)).toBe('52%');
  });

  it('صيغ العدد العربية للأيام', () => {
    expect(arDays(1)).toBe('يوم واحد');
    expect(arDays(2)).toBe('يومين');
    expect(arDays(3)).toBe('3 أيام');
    expect(arDays(10)).toBe('10 أيام');
    expect(arDays(11)).toBe('11 يومًا');
  });
});

describe('getDisplayNote (إخفاء كلمة تعديل إداري مع إظهار التعديل الفعلي)', () => {
  it('العبارات العامة تلغى تماماً ولا تظهر', () => {
    expect(getDisplayNote('تعديل إداري معتمد')).toBeNull();
    expect(getDisplayNote('تعديل اداري معتمد')).toBeNull();
    expect(getDisplayNote('تعديل إداري')).toBeNull();
    expect(getDisplayNote('تعديل اداري')).toBeNull();
    expect(getDisplayNote('تصحيح إداري')).toBeNull();
    expect(getDisplayNote('استثناء إداري')).toBeNull();
    expect(getDisplayNote('تعديل معتمد')).toBeNull();
    expect(getDisplayNote('دوام كامل معتمد')).toBeNull();
  });

  it('يزيل كلمة تعديل إداري ويُبقي سبب التعديل بوضوح', () => {
    expect(getDisplayNote('تعديل إداري: سبب التأخير عطل كهربائي')).toBe('سبب التأخير عطل كهربائي');
    expect(getDisplayNote('[تعديل إداري] عطل في المترو')).toBe('عطل في المترو');
    expect(getDisplayNote('تصحيح إداري - إذن شفهي من المشرف')).toBe('إذن شفهي من المشرف');
    expect(getDisplayNote('تعديل اداري: حضور مؤتمر الإغاثة')).toBe('حضور مؤتمر الإغاثة');
    expect(getDisplayNote('إذن مسبق بتعديل إداري')).toBe('إذن مسبق');
  });

  it('الملاحظات العادية تبقى كما هي', () => {
    expect(getDisplayNote('عطل في جهاز البصمة')).toBe('عطل في جهاز البصمة');
    expect(getDisplayNote('حضور دورة تدريبية')).toBe('حضور دورة تدريبية');
  });
});
