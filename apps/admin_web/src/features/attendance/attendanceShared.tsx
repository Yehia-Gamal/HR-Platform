import type { AttendanceStatement, AttendanceStatementDay } from '@ahla/shared-contracts';
import type { ReactNode } from 'react';

// ─── ثوابت مشتركة ─────────────────────────────────────────────────
export const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/** حالات اليوم التي تُعرض بلون تحذيري. */
export const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

/** يقسم نص الحالة العربي متعدد الكلمات إلى سطور (يحافظ على المعنى). */
export function splitStatusLines(status: string): string[] {
  const trimmed = status.trim();
  if (!trimmed) return ['—'];
  const words = trimmed.split(/\s+/);
  if (words.length <= 2) return [trimmed];
  // "غائب دون إذن" → ["غائب", "دون إذن"] — يبقي "إذن" مع "دون".
  if (words.length === 3 && words[1] === 'دون') return [words[0], `${words[1]} ${words[2]}`];
  const mid = Math.ceil(words.length / 2);
  return [words.slice(0, mid).join(' '), words.slice(mid).join(' ')];
}

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
