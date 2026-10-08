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
  if (d.hasConvoyFundi) {
    if (d.status?.includes('فاندي')) return { label: 'فاندي (ترفيهي)', tone: 'info' };
    return { label: 'قافلة مساعدات', tone: 'info' };
  }
  if (d.isOpenShift) return { label: 'وردية مفتوحة', tone: 'warn' };
  if (d.missingCheckOut) return { label: 'لم يسجل الانصراف', tone: 'warn' };
  if (d.isCompleted) return { label: 'حاضر', tone: 'ok' };
  if (d.status) return { label: d.status, tone: 'neutral' };
  return { label: '—', tone: 'neutral' };
}

export function attendanceRateParts(summary: AttendanceStatement['summary']) {
  const dueDays = summary.attendanceRateBasis?.dueDays ?? summary.scheduledDays;
  const presentInDue = summary.attendanceRateBasis?.presentInDue ?? summary.presentDays;
  return { dueDays, presentInDue };
}

/**
 * نسب الكشف كما تُعرض في الصفحة والملفات (مصدر واحد للثلاثة):
 * المعفى من البصمة لا تُعرض له نسبة، وغياب المقام يعني «غير متاح» لا 0% بالأحمر.
 */
export function statementRates(summary: AttendanceStatement['summary']) {
  const { dueDays, presentInDue } = attendanceRateParts(summary);
  const exempt = summary.isAttendanceExempt ?? false;
  return {
    exempt,
    attendance: {
      available: !exempt && dueDays > 0,
      pct: summary.attendanceRate ?? (dueDays > 0 ? (presentInDue / dueDays) * 100 : 0),
      present: presentInDue,
      due: dueDays,
      excludedLeave: summary.attendanceRateBasis?.excludedLeaveDays ?? 0,
      excludedPending: summary.attendanceRateBasis?.excludedPendingDays ?? 0,
      offsite: summary.attendanceRateBasis?.offsiteDays ?? 0,
    },
    hours: {
      available: !exempt && (summary.hoursComplianceAvailable || summary.totalRequiredHours > 0),
      pct: summary.hoursComplianceRate ?? 0,
    },
  };
}

/** عدد الأيام بصيغة عربية سليمة: يوم واحد، يومين، 3 أيام، 11 يومًا. */
export function arDays(n: number): string {
  if (n === 1) return 'يوم واحد';
  if (n === 2) return 'يومين';
  const mod = n % 100;
  return mod >= 3 && mod <= 10 ? `${n} أيام` : `${n} يومًا`;
}

/** نص النسبة: لا تُقرَّب 99.6% إلى 100% (توحي بحضور كامل لم يحدث). */
export function fmtPct(pct: number): string {
  return `${pct >= 99.5 && pct < 100 ? 99 : Math.round(pct)}%`;
}

/** نص خانة النسبة: «معفى» للمعفى من البصمة، «غير متاح» إن لم يوجد مقام. */
export function rateText(rate: { available: boolean; pct: number }, exempt: boolean): string {
  if (exempt) return 'معفى';
  return rate.available ? fmtPct(rate.pct) : 'غير متاح';
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
  if (!t) return '—';
  const m = /^(\d{1,2}):(\d{2})/.exec(t);
  if (!m) return t;
  let h = parseInt(m[1], 10);
  const min = m[2];
  if (Number.isNaN(h)) return t;
  // 0449: عرض بنظام 12 ساعة مع ص/م (العرف العربي)
  const period = h < 12 ? 'ص' : 'م';
  h = h % 12 === 0 ? 12 : h % 12;
  return `${String(h).padStart(2, '0')}:${min} ${period}`;
}

/** تمييز العدد بالعربية: 1 ساعة واحدة، 2 ساعتان، 3–10 ساعات، 11+ ساعة. */
function arCount(n: number, one: string, two: string, few: string, many: string): string {
  if (n === 1) return one;
  if (n === 2) return two;
  const mod = n % 100;
  return mod >= 3 && mod <= 10 ? `${n} ${few}` : `${n} ${many}`;
}

const arHours = (n: number) => arCount(n, 'ساعة واحدة', 'ساعتان', 'ساعات', 'ساعة');
const arMinutes = (n: number) => arCount(n, 'دقيقة واحدة', 'دقيقتان', 'دقائق', 'دقيقة');

function arDuration(h: number, m: number): string {
  if (h === 0 && m === 0) return '0 دقيقة';
  if (h === 0) return arMinutes(m);
  if (m === 0) return arHours(h);
  return `${arHours(h)} و ${arMinutes(m)}`;
}

/** تنسيق عدد الساعات بصيغة عربية طويلة: 8.5 → "8 ساعات و 30 دقيقة" */
export function fmtHoursLong(hours: number | null | undefined): string {
  if (hours == null) return '—';
  const total = Math.round(hours * 60);
  return arDuration(Math.floor(total / 60), total % 60);
}

/** تنسيق عدد الدقائق بصيغة عربية طويلة: 125 → "ساعتان و 5 دقائق" */
export function fmtMinutesLong(totalMinutes: number | null | undefined): string {
  if (totalMinutes == null) return '—';
  const total = Math.round(totalMinutes);
  return arDuration(Math.floor(total / 60), total % 60);
}

/** تنسيق عدد الدقائق بصيغة موجزة للجداول والبطاقات: 125 → "2 س و 5 د" */
export function fmtMinutesCompact(totalMinutes: number | null | undefined): string {
  if (totalMinutes == null || totalMinutes <= 0) return '—';
  const h = Math.floor(totalMinutes / 60);
  const m = Math.round(totalMinutes % 60);
  if (h === 0) return `${m} د`;
  if (m === 0) return `${h} س`;
  return `${h} س و ${m} د`;
}

export type TagVariant = 'info' | 'warn' | 'success' | 'purple';

export function buildDayTags(d: AttendanceStatementDay): { label: string; variant: TagVariant }[] {
  const tags: { label: string; variant: TagVariant }[] = [];
  if (d.hasLatePermit) tags.push({ label: 'إذن حضور', variant: 'warn' });
  if (d.hasEarlyPermit) tags.push({ label: 'إذن انصراف', variant: 'warn' });
  if (!d.hasLatePermit && !d.hasEarlyPermit && d.hasPermit) tags.push({ label: 'إذن', variant: 'warn' });
  if (d.missingCheckIn) tags.push({ label: 'نقص حضور', variant: 'warn' });
  if (d.missingCheckOut) tags.push({ label: 'نقص انصراف', variant: 'warn' });
  if (d.penalties > 0) tags.push({ label: `جزاء: ${d.penalties}`, variant: 'warn' });
  return tags;
}

const SUPPRESSED_GENERIC_NOTES = new Set([
  'تعديل ساعات وحضور معتمد',
  'تعديل إداري معتمد',
  'تعديل اداري معتمد',
  'تعديل إداري',
  'تعديل اداري',
  'تصحيح إداري',
  'تصحيح اداري',
  'استثناء إداري',
  'استثناء اداري',
  'تعديل معتمد',
  'تصحيح معتمد',
  'معتمد',
  'إجازة معتمدة إدارياً',
  'إجازة معتمدة اداريا',
  'مأمورية عمل معتمدة',
  'قافلة عمل معتمدة',
  'فاندي معتمد',
  'عطلة رسمية معتمدة',
  'راحة أسبوعية معتمدة',
  'تأكيد غياب إداري',
  'تأكيد غياب اداري',
  // أسباب جاهزة في محرر اليوم (ويب وموبايل) تصف عملية التعديل نفسها لا اليوم
  'تعديل ساعات العمل المعتمدة',
  'تصحيح وقت الحضور والانصراف',
  'إضافة بصمة منسية',
  'دوام كامل معتمد',
  'تأكيد غياب بدون إذن',
  'غياب غير مبرر',
  'طلب تحديد يوم معتمد',
  // كلمة عامة بلا مضمون يكتبها البعض سبباً لطلب التصحيح
  'تصحيح',
  'تعديل',
]);

/**
 * فلترة الملاحظات: إخفاء كلمة «تعديل إداري» تماماً وعرض نص التعديل الفعلي فقط إن وُجد.
 * إن كان النص مجرد عبارة روتينية عامة (مثل "تعديل إداري معتمد") يُلغى، وإن كان يحتوي
 * سبباً حقيقياً (مثل "تعديل إداري: عطل بالمترو") يُعرض ("عطل بالمترو") بدون كلمة تعديل إداري.
 */
export function getDisplayNote(note: string | null | undefined): string | null {
  if (!note) return null;
  let text = note.trim();
  if (!text) return null;

  // 1. إزالة الأقواس والوسوم مثل [تعديل إداري] أو [تصحيح] أو [استثناء إداري]
  text = text.replace(/\[\s*(?:(?:ب|و|ل|ِ)?\s*)?(تعديل|تصحيح|استثناء)\s*(إداري|اداري)?\s*\]/giu, '').trim();

  // 2. إزالة بادئة «تعديل إداري:» أو «تصحيح إداري - » أو «تعديل إداري» مع أي حرف جر سابق
  text = text.replace(/^(?:ب|و|ل|ِ|عبر|وفق|بناءً على|بناء على)?\s*(تعديل|تصحيح|استثناء)\s*(إداري|اداري)?\s*[:：\-–—]\s*/iu, '').trim();

  // 3. إزالة أي ظهور لكلمة «تعديل إداري» أو «تعديل اداري» أو «تصحيح إداري» أو «بتعديل إداري»
  text = text.replace(/(?:ب|و|ل|ِ|عبر|وفق|بناءً على|بناء على)?\s*(تعديل|تصحيح|استثناء)\s*(إداري|اداري)/giu, '').trim();

  // 4. إزالة الفواصل والنقاط الزائدة وحروف الجر المعلقة من البداية والنهاية
  text = text
    .replace(/^[:：\-–—,.،\s]+/u, '')
    .replace(/[:：\-–—,.،\s]+$/u, '')
    .trim();
  text = text.replace(/\s+(?:ب|و|ل|ِ)\s*$/u, '').trim();
  text = text.replace(/\s{2,}/g, ' ');

  if (!text) return null;

  // 5. التحقق مما إذا كان النص المتبقي مجرد عبارة عامة لا تفيد شيئاً
  if (SUPPRESSED_GENERIC_NOTES.has(text)) {
    return null;
  }

  return text;
}

// ─── مكونات مشتركة ────────────────────────────────────────────────

/** دائرة نسبة مئوية (حضور / التزام). */
export function AttendancePercentageRing({
  percentage,
  label = 'حضور',
  available = true,
  unavailableText = 'غير متاح',
}: {
  percentage: number;
  label?: string;
  available?: boolean;
  /** «معفى» للمعفى من البصمة بدل «غير متاح». */
  unavailableText?: string;
}) {
  const pct = Math.min(100, Math.max(0, percentage));
  if (!available) {
    return (
      <div className="stmt-ring">
        <svg width="100" height="100" viewBox="0 0 100 100" aria-hidden="true">
          <circle cx="50" cy="50" r="40" fill="none" strokeWidth="8" className="stroke-slate-200" />
        </svg>
        <div className="stmt-ring-center">
          <span className="text-sm font-black text-[var(--text-disabled)]">{unavailableText}</span>
          <span className="stmt-ring-label">{label}</span>
        </div>
      </div>
    );
  }
  const color = pct >= 90 ? 'text-[var(--success)]' : pct >= 75 ? 'text-[var(--warning)]' : 'text-[var(--danger)]';
  const bgColor = pct >= 90 ? 'stroke-emerald-100' : pct >= 75 ? 'stroke-amber-100' : 'stroke-red-100';
  const fgColor = pct >= 90 ? 'stroke-emerald-600' : pct >= 75 ? 'stroke-amber-500' : 'stroke-red-600';
  const r = 40;
  const circ = 2 * Math.PI * r;
  const offset = circ - (pct / 100) * circ;

  return (
    <div className="stmt-ring" role="img" aria-label={`${label}: ${fmtPct(pct)}`}>
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
        <span className={`stmt-ring-value ${color}`}>{fmtPct(pct)}</span>
        <span className="stmt-ring-label">{label}</span>
      </div>
    </div>
  );
}

/** علامة (tag) صغيرة ملوّنة للجدول. */
export function DayTag({ label, variant }: { label: string; variant: TagVariant }) {
  const styles = {
    info: 'bg-[var(--brand-accent-soft)] text-[var(--brand-accent)] border-[var(--brand-accent)]',
    warn: 'bg-[var(--warning-soft)] text-[var(--warning)] border-[var(--warning)]',
    success: 'bg-[var(--success-soft)] text-[var(--success)] border-[var(--success)]',
    purple: 'bg-[var(--info-soft)] text-[var(--info)] border-[var(--info)]',
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

export type DayFilter = 'all' | 'present' | 'absent' | 'leave' | 'mission' | 'convoy' | 'fundi' | 'open' | 'upcoming' | 'rest';
export type DaySort = 'date-asc' | 'date-desc' | 'status';

export const DAY_FILTERS: { key: DayFilter; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'present', label: 'حاضر' },
  { key: 'absent', label: 'غائب' },
  { key: 'leave', label: 'إجازة' },
  { key: 'mission', label: 'مأمورية' },
  { key: 'convoy', label: 'قافلة' },
  { key: 'fundi', label: 'فاندي' },
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
          if (!((d.status?.includes('قافلة') || d.hasConvoyFundi) && !d.status?.includes('فاندي'))) return false;
          break;
        case 'fundi':
          if (!d.status?.includes('فاندي')) return false;
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
