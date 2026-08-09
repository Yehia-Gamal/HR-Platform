import type { AttendanceStatement, AttendanceStatementDay } from '@ahla/shared-contracts';
import type { ComponentType, ReactNode } from 'react';

// ─── ثوابت مشتركة ─────────────────────────────────────────────────
export const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/** حالات اليوم التي تُعرض بلون تحذيري. */
export const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

/** يبني تسمية ونبرة حالة اليوم من حقول اليوم. */
export function dayStatusMeta(d: AttendanceStatementDay): { label: string; tone: 'ok' | 'warn' | 'danger' | 'info' | 'neutral' } {
  if (d.isFuture) return { label: 'قادم', tone: 'neutral' };
  if (d.isAbsent) return { label: 'غائب دون إذن', tone: 'danger' };
  if (d.status && WARN_STATUSES.has(d.status)) return { label: d.status, tone: 'danger' };
  if (d.isOfficialHoliday) return { label: 'عطلة رسمية', tone: 'info' };
  if (d.hasLeave) return { label: 'إجازة', tone: 'info' };
  if (d.hasMission) return { label: 'مأمورية', tone: 'info' };
  if (d.hasConvoyFundi) return { label: 'قافلة/فاندي', tone: 'info' };
  if (d.isOpenShift) return { label: 'وردية مفتوحة', tone: 'warn' };
  if (d.isCompleted) return { label: 'حاضر', tone: 'ok' };
  if (d.status) return { label: d.status, tone: 'neutral' };
  return { label: '—', tone: 'neutral' };
}

export function attendanceRateParts(summary: AttendanceStatement['summary']) {
  const dueDays = summary.attendanceRateBasis?.dueDays ?? summary.scheduledDays;
  const presentInDue = summary.attendanceRateBasis?.presentInDue ?? summary.presentDays;
  return { dueDays, presentInDue };
}

export function hoursRateParts(summary: AttendanceStatement['summary']) {
  return {
    workedHours: (summary.hoursRateBasis?.workedMinutes ?? Math.round(summary.totalWorkHours * 60)) / 60,
    requiredHours: (summary.hoursRateBasis?.requiredMinutes ?? Math.round(summary.totalRequiredHours * 60)) / 60,
    deficitHours: (summary.hoursRateBasis?.deficitMinutes ?? summary.totalDeficitMinutes) / 60,
  };
}

// ─── دوال مساعدة ──────────────────────────────────────────────────
export function fmtTime(t: string | null) {
  return t ? t.slice(0, 5) : '—';
}

/** تنسيق عدد الساعات بصيغة عربية طويلة: 8.5 → "8 ساعة و 30 دقيقة" */
export function fmtHoursLong(hours: number | null | undefined): string {
  if (hours == null) return '—';
  const h = Math.floor(hours);
  const m = Math.round((hours - h) * 60);
  if (h === 0 && m === 0) return '0 دقيقة';
  if (h === 0) return `${m} دقيقة`;
  if (m === 0) return `${h} ساعة`;
  return `${h} ساعة و ${m} دقيقة`;
}

/** تنسيق عدد الدقائق بصيغة عربية طويلة: 125 → "ساعتان و 5 دقائق" */
export function fmtMinutesLong(totalMinutes: number | null | undefined): string {
  if (totalMinutes == null) return '—';
  const h = Math.floor(totalMinutes / 60);
  const m = Math.round(totalMinutes % 60);
  if (h === 0 && m === 0) return '0 دقيقة';
  if (h === 0) return `${m} دقيقة`;
  if (m === 0) return `${h} ساعة`;
  return `${h} ساعة و ${m} دقيقة`;
}

export type TagVariant = 'info' | 'warn' | 'success' | 'purple';

/** يبني قائمة العلامات (tags) لصف يوم واحد في جدول الحضور. */
export function buildDayTags(d: AttendanceStatementDay): { label: string; variant: TagVariant }[] {
  const tags: { label: string; variant: TagVariant }[] = [];
  if (d.isAbsent) tags.push({ label: 'غائب', variant: 'warn' });
  if (d.isOfficialHoliday) tags.push({ label: 'عطلة رسمية', variant: 'info' });
  if (d.hasLeave) tags.push({ label: 'إجازة', variant: 'purple' });
  if (d.hasMission) tags.push({ label: 'مأمورية', variant: 'info' });
  if (d.hasLatePermit) tags.push({ label: 'إذن حضور', variant: 'warn' });
  if (d.hasEarlyPermit) tags.push({ label: 'إذن انصراف', variant: 'warn' });
  if (!d.hasLatePermit && !d.hasEarlyPermit && d.hasPermit) tags.push({ label: 'إذن', variant: 'warn' });
  if (d.hasConvoyFundi) tags.push({ label: 'قافلة/فاندي', variant: 'purple' });
  if (d.missingCheckIn) tags.push({ label: 'نقص حضور', variant: 'warn' });
  if (d.missingCheckOut) tags.push({ label: 'نقص انصراف', variant: 'warn' });
  if (d.isOpenShift) tags.push({ label: 'بانتظار الانصراف', variant: 'info' });
  if (d.isFuture) tags.push({ label: 'قادم', variant: 'info' });
  if (d.hasCorrection) tags.push({ label: 'تصحيح', variant: 'info' });
  if (d.penalties > 0) tags.push({ label: `جزاء: ${d.penalties}`, variant: 'warn' });
  return tags;
}

// ─── مكونات مشتركة ────────────────────────────────────────────────

/** دائرة نسبة مئوية (حضور / التزام). */
export function AttendancePercentageRing({ percentage, label = 'حضور', available = true }: { percentage: number; label?: string; available?: boolean }) {
  const pct = Math.min(100, Math.max(0, percentage));
  if (!available) {
    return (
      <div className="stmt-ring">
        <svg width="100" height="100" viewBox="0 0 100 100" aria-hidden="true">
          <circle cx="50" cy="50" r="40" fill="none" strokeWidth="8" className="stroke-slate-200" />
        </svg>
        <div className="stmt-ring-center">
          <span className="text-sm font-black text-slate-400">غير متاح</span>
          <span className="stmt-ring-label">{label}</span>
        </div>
      </div>
    );
  }
  const color = pct >= 90 ? 'text-emerald-600' : pct >= 75 ? 'text-amber-500' : 'text-red-600';
  const bgColor = pct >= 90 ? 'stroke-emerald-100' : pct >= 75 ? 'stroke-amber-100' : 'stroke-red-100';
  const fgColor = pct >= 90 ? 'stroke-emerald-600' : pct >= 75 ? 'stroke-amber-500' : 'stroke-red-600';
  const r = 40;
  const circ = 2 * Math.PI * r;
  const offset = circ - (pct / 100) * circ;

  return (
    <div className="stmt-ring" role="img" aria-label={`${label}: ${pct.toFixed(0)}%`}>
      <svg width="100" height="100" viewBox="0 0 100 100" className="-rotate-90" aria-hidden="true">
        <circle cx="50" cy="50" r={r} fill="none" strokeWidth="8" className={bgColor} />
        <circle
          cx="50"
          cy="50"
          r={r}
          fill="none"
          strokeWidth="8"
          className={fgColor}
          strokeLinecap="round"
          strokeDasharray={circ}
          strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 0.6s ease' }}
        />
      </svg>
      <div className="stmt-ring-center">
        <span className={`stmt-ring-value ${color}`}>{pct.toFixed(0)}%</span>
        <span className="stmt-ring-label">{label}</span>
      </div>
    </div>
  );
}

/** علامة (tag) صغيرة ملوّنة للجدول. */
export function DayTag({ label, variant }: { label: string; variant: TagVariant }) {
  const styles = {
    info: 'bg-sky-50 text-sky-700 border-sky-200',
    warn: 'bg-amber-50 text-amber-700 border-amber-200',
    success: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    purple: 'bg-violet-50 text-violet-700 border-violet-200',
  };
  return <span className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-bold border print:text-[7px] print:px-1 ${styles[variant]}`}>{label}</span>;
}

/** عنصر إحصائية واحد (أيقونة + عنوان + قيمة). */
export function StatItem({ label, value, icon }: { label: string; value: string; icon: ReactNode }) {
  return (
    <div className="flex items-center gap-1.5">
      {icon}
      <span className="text-[var(--text-muted)]">{label}:</span>
      <span className="font-bold">{value}</span>
    </div>
  );
}

// ─── مكونات الكشف المشتركة (تُستخدم في القسم المضمّن وفي صفحة التقرير) ─────────

/** بطاقة إحصائية بنبرة لونية اختيارية — تتبنّى تصميم `stmt-stat` الموحّد. */
export function StatBox({
  label,
  value,
  hint,
  icon: Icon,
  tone,
}: {
  label: string;
  value: number | string;
  hint?: string;
  icon: ComponentType<{ className?: string }>;
  tone?: 'success' | 'warn' | 'danger';
}) {
  const toneClass = tone === 'success' ? 'stmt-stat--success' : tone === 'warn' ? 'stmt-stat--warn' : tone === 'danger' ? 'stmt-stat--danger' : '';
  return (
    <div className={`stmt-stat ${toneClass}`}>
      <div className="stmt-stat-head">
        <Icon className="size-4" aria-hidden="true" />
        <span>{label}</span>
      </div>
      <p className="stmt-stat-value">{value}</p>
      {hint ? <p className="stmt-stat-hint">{hint}</p> : null}
    </div>
  );
}

/** إحصائية سريعة في شريط مدمج — تتبنّى تصميم `quick-stat`. */
export function QuickStat({ label, value, icon }: { label: string; value: string; icon: ReactNode }) {
  return (
    <span className="quick-stat">
      {icon}
      {label}: <b>{value}</b>
    </span>
  );
}

/** كبسولة حالة اليوم بنبرة لونية — تتبنّى تصميم `status-pill`. */
export function StatusPill({ d }: { d: AttendanceStatement['days'][number] }) {
  const { label, tone } = dayStatusMeta(d);
  return <span className={`status-pill status-pill--${tone}`}>{label}</span>;
}

// ─── فلترة وترتيب الأيام ─────────────────────────────────────────

export type DayFilter = 'all' | 'present' | 'absent' | 'leave' | 'mission' | 'convoy' | 'open' | 'upcoming' | 'rest';
export type DaySort = 'date-asc' | 'date-desc' | 'status';

export const DAY_FILTERS: { key: DayFilter; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'present', label: 'حاضر' },
  { key: 'absent', label: 'غائب' },
  { key: 'leave', label: 'إجازة' },
  { key: 'mission', label: 'مأمورية' },
  { key: 'convoy', label: 'قافلة/فاندي' },
  { key: 'open', label: 'وردية مفتوحة' },
  { key: 'upcoming', label: 'قادمة' },
  { key: 'rest', label: 'راحة/عطلة' },
];

export const DAY_SORTS: { key: DaySort; label: string }[] = [
  { key: 'date-asc', label: 'الأقدم أولاً' },
  { key: 'date-desc', label: 'الأحدث أولاً' },
  { key: 'status', label: 'حسب الحالة' },
];

/** يفلتر الأيام حسب النوع المحدد + نص بحث اختياري. */
export function filterDays(days: AttendanceStatementDay[], filter: DayFilter, search: string): AttendanceStatementDay[] {
  const q = search.trim().toLowerCase();
  return days.filter((d) => {
    if (filter !== 'all') {
      switch (filter) {
        case 'present':
          if (!(d.isCompleted && !d.isFuture)) return false;
          break;
        case 'absent':
          if (!d.isAbsent) return false;
          break;
        case 'leave':
          if (!d.hasLeave) return false;
          break;
        case 'mission':
          if (!d.hasMission) return false;
          break;
        case 'convoy':
          if (!d.hasConvoyFundi) return false;
          break;
        case 'open':
          if (!d.isOpenShift) return false;
          break;
        case 'upcoming':
          if (!d.isFuture) return false;
          break;
        case 'rest':
          if (!(d.isOfficialHoliday || d.status === 'راحة أسبوعية' || d.status === 'عطلة رسمية')) return false;
          break;
      }
    }
    if (q) {
      const haystack = `${d.date} ${d.dayNameAr} ${d.status} ${d.shiftName} ${d.correctionNote ?? ''}`.toLowerCase();
      if (!haystack.includes(q)) return false;
    }
    return true;
  });
}

/** يرتّب الأيام حسب الخيار المحدد. */
export function sortDays(days: AttendanceStatementDay[], sort: DaySort): AttendanceStatementDay[] {
  const sorted = [...days];
  if (sort === 'date-desc') {
    sorted.sort((a, b) => b.date.localeCompare(a.date));
  } else if (sort === 'status') {
    sorted.sort((a, b) => {
      const sc = (a.status ?? '').localeCompare(b.status ?? '', 'ar');
      return sc !== 0 ? sc : a.date.localeCompare(b.date);
    });
  }
  return sorted;
}
