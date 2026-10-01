import { describe, it, expect } from 'vitest';
import { fmtTime, pctColor, esc } from './exportAttendancePDF';

describe('fmtTime', () => {
  it('returns "—" for null', () => {
    expect(fmtTime(null)).toBe('—');
  });

  it('formats "08:30:00" as 12h morning "08:30 ص"', () => {
    expect(fmtTime('08:30:00')).toBe('08:30 ص');
  });

  it('formats "14:15" as 12h afternoon "02:15 م"', () => {
    expect(fmtTime('14:15')).toBe('02:15 م');
  });

  it('formats midnight "00:10" as "12:10 ص" and noon "12:00" as "12:00 م"', () => {
    expect(fmtTime('00:10')).toBe('12:10 ص');
    expect(fmtTime('12:00')).toBe('12:00 م');
  });
});

describe('pctColor', () => {
  it('returns green (#059669) for 100', () => {
    expect(pctColor(100)).toBe('#059669');
  });

  it('returns green (#059669) for 95', () => {
    expect(pctColor(95)).toBe('#059669');
  });

  it('returns green (#059669) for 90', () => {
    expect(pctColor(90)).toBe('#059669');
  });

  it('returns amber (#f59e0b) for 89', () => {
    expect(pctColor(89)).toBe('#f59e0b');
  });

  it('returns amber (#f59e0b) for 80', () => {
    expect(pctColor(80)).toBe('#f59e0b');
  });

  it('returns amber (#f59e0b) for 75', () => {
    expect(pctColor(75)).toBe('#f59e0b');
  });

  it('returns red (#dc2626) for 74', () => {
    expect(pctColor(74)).toBe('#dc2626');
  });

  it('returns red (#dc2626) for 50', () => {
    expect(pctColor(50)).toBe('#dc2626');
  });

  it('returns red (#dc2626) for 0', () => {
    expect(pctColor(0)).toBe('#dc2626');
  });
});

describe('esc', () => {
  it('escapes & to &amp;', () => {
    expect(esc('a&b')).toBe('a&amp;b');
  });

  it('escapes < to &lt;', () => {
    expect(esc('a<b')).toBe('a&lt;b');
  });

  it('escapes > to &gt;', () => {
    expect(esc('a>b')).toBe('a&gt;b');
  });

  it('escapes " to &quot;', () => {
    expect(esc('a"b')).toBe('a&quot;b');
  });

  it('handles null → empty string', () => {
    expect(esc(null)).toBe('');
  });

  it('handles undefined → empty string', () => {
    expect(esc(undefined)).toBe('');
  });

  it('handles numbers → string representation', () => {
    expect(esc(42)).toBe('42');
  });

  it('handles combined escaping', () => {
    expect(esc('<script>"alert(1)"</script>')).toBe('&lt;script&gt;&quot;alert(1)&quot;&lt;/script&gt;');
  });
});

describe('attendanceDocumentShell', () => {
  it('includes interactive action bar with PDF button and without HTML button', async () => {
    const { attendanceDocumentShell } = await import('./exportAttendancePDF');
    const html = attendanceDocumentShell('كشف حضور تجريبي', '<div>محتوى تجريبي</div>', true);

    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('dir="rtl"');
    expect(html).toContain('action-bar no-print');
    expect(html).toContain('تحميل وحفظ كملف PDF');
    expect(html).toContain('طباعة');
    expect(html).not.toContain('تنزيل ملف (HTML)');
    expect(html).toContain('saveAsPdf()');
    expect(html).not.toContain('downloadHtml()');
    expect(html).toContain('كشف حضور تجريبي');
    expect(html).toContain('محتوى تجريبي');
  });

  it('hides action bar in print media stylesheet', async () => {
    const { attendanceDocumentShell } = await import('./exportAttendancePDF');
    const html = attendanceDocumentShell('كشف حضور', '<div>محتوى</div>', false);

    expect(html).toContain('.no-print, .action-bar { display: none !important; }');
  });
});

describe('buildStatementBodyHtml — نسب وبيانات الكشف (0582)', () => {
  const load = async () => {
    const { mockAttendanceStatement } = await import('../mock/domainMocks');
    const { buildStatementBodyHtml } = await import('./exportAttendancePDF');
    return { base: structuredClone(mockAttendanceStatement), buildStatementBodyHtml };
  };

  it('يعرض النسبة وأساسها واستبعاد الإجازات بصيغة عربية سليمة', async () => {
    const { base, buildStatementBodyHtml } = await load();
    base.summary.attendanceRate = 100;
    base.summary.attendanceRateBasis = {
      presentInDue: 23,
      dueDays: 23,
      presentDays: 20,
      absentDays: 0,
      openShiftDays: 0,
      upcomingDays: 0,
      excludedLeaveDays: 3,
    };
    const html = buildStatementBodyHtml(base);
    expect(html).toContain('100%');
    expect(html).toContain('23 من 23 يوم عمل مستحق');
    expect(html).toContain('بعد استبعاد 3 أيام إجازة');
  });

  it('المعفى من البصمة: «معفى» بدل 0% ولا لون أحمر', async () => {
    const { base, buildStatementBodyHtml } = await load();
    base.summary.isAttendanceExempt = true;
    base.summary.attendanceRate = 0;
    const html = buildStatementBodyHtml(base);
    expect(html).toContain('معفى من البصمة — لا تُحتسب له نسبة');
    expect(html).not.toMatch(/color:#dc2626">0%/);
  });

  it('يعرض دقائق التأخير في الجدول وعدد أيامه في الملخص', async () => {
    const { base, buildStatementBodyHtml } = await load();
    base.days[0] = { ...base.days[0], lateMinutes: 42 };
    base.summary.lateDays = 1;
    base.summary.totalLateMinutes = 42;
    const html = buildStatementBodyHtml(base);
    expect(html).toContain('<td class="num late">42 د</td>');
    expect(html).toContain('42 دقيقة');
  });

  it('وردية واحدة طوال الشهر: تُعرض في بيانات الموظف لا كعمود مكرر', async () => {
    const { base, buildStatementBodyHtml } = await load();
    base.days = base.days.map((d) => ({ ...d, shiftName: 'الدوام الرسمي (10 ص – 6 م)' }));
    const html = buildStatementBodyHtml(base);
    expect(html).toContain('<label>الوردية</label>');
    expect(html).not.toContain('<th>الوردية</th>');
  });

  it('يوم ماضٍ بلا انصراف لا يكرّر «نقص انصراف» بجوار حالته', async () => {
    const { base, buildStatementBodyHtml } = await load();
    base.days[0] = { ...base.days[0], checkOut: null, missingCheckOut: true, status: 'حضور ناقص — لم يسجل الانصراف' };
    const html = buildStatementBodyHtml(base);
    expect(html).toContain('<tr class="warn">');
    expect(html).not.toContain('نقص انصراف');
  });
});
