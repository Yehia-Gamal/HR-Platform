import { useMemo } from 'react';

// ─── الأنواع ──────────────────────────────────────────────────
/** بيانات يوم واحد في خريطة الحضور الحرارية. */
export interface AttendanceHeatmapDay {
  date: string;
  status: string;
}

/** تصنيف لوني خفيف للحالة — يحدد لون الخلية. */
type HeatTone = 'present' | 'late' | 'absent' | 'neutral';

interface HeatToneMeta {
  tone: HeatTone;
  /** لون الخلفية بدرجاته (Tailwind classes). */
  cell: string;
  /** نص الحالة المعروض في التلميح والوسيلة. */
  label: string;
}

// ─── تصنيف الحالة ──────────────────────────────────────────────
// الحالة نص حرّ (عربي أو إنجليزي) — نُرجّح عبر الكلمات المفتاحية.
const PRESENT_RE = /حاضر|present|checked[_-]?out|completed|on[_-]?time/i;
const LATE_RE = /متأخر|تأخير|late/i;
const ABSENT_RE = /غائب|absent/i;
const REST_RE = /راحة|عطلة|rest|holiday|weekend|قادم|upcoming|future|—/i;

function classifyStatus(status: string): HeatToneMeta {
  const s = status?.trim() ?? '';
  if (!s || REST_RE.test(s)) return { tone: 'neutral', cell: 'bg-slate-200 dark:bg-slate-700', label: s || '—' };
  if (ABSENT_RE.test(s)) return { tone: 'absent', cell: 'bg-red-500', label: s };
  if (LATE_RE.test(s)) return { tone: 'late', cell: 'bg-orange-400', label: s };
  if (PRESENT_RE.test(s)) return { tone: 'present', cell: 'bg-emerald-500', label: s };
  return { tone: 'neutral', cell: 'bg-slate-200 dark:bg-slate-700', label: s };
}

// ─── مولّد بيانات وهمية (Mock) ─────────────────────────────────
/** يُولّد 30 يومًا من بيانات حضور عشوائية للاختبار/التطوير. */
export function generateMockHeatmapData(days = 30): AttendanceHeatmapDay[] {
  // توزيع مرجّح: أغلب الأيام حضور، بعض التأخير، قليل من الغياب، وعطل نهاية الأسبوع.
  const pool: AttendanceHeatmapDay[] = [];
  const today = new Date();
  for (let i = 0; i < days; i++) {
    const d = new Date(today.getFullYear(), today.getMonth(), i + 1);
    const dow = d.getDay(); // 0=أحد ... 6=سبت
    const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(i + 1).padStart(2, '0')}`;
    let status: string;
    if (dow === 5 || dow === 6) {
      status = 'راحة أسبوعية';
    } else {
      const r = Math.random();
      if (r < 0.7) status = 'حاضر';
      else if (r < 0.85) status = 'متأخر';
      else if (r < 0.93) status = 'غائب';
      else status = 'راحة أسبوعية';
    }
    pool.push({ date, status });
  }
  return pool;
}

// ─── المكون ────────────────────────────────────────────────────
interface AttendanceHeatmapProps {
  data: AttendanceHeatmapDay[];
}

/**
 * خريطة حضور حرارية بأسلوب تقويم نصفياً (مثل مساهمات GitHub):
 * شبكة 7 أعمدة (أيام الأسبوع)، كل خلية يوم بلون يعكس الحالة.
 * أخضر=حاضر، برتقالي=متأخر، أحمر=غائب، رمادي=راحة/قادم.
 */
export function AttendanceHeatmap({ data }: AttendanceHeatmapProps) {
  // إحصاء الألوان لشريط ملخص علوي.
  const summary = useMemo(() => {
    const acc = { present: 0, late: 0, absent: 0, neutral: 0 };
    for (const d of data) acc[classifyStatus(d.status).tone]++;
    return acc;
  }, [data]);

  if (!data.length) return null;

  return (
    <section className="card p-5 print:hidden" aria-label="خريطة الحضور الشهرية">
      <header className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-black">خريطة الحضور الشهرية</h3>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-[var(--text-muted)]">
          <LegendDot className="bg-emerald-500" label={`حاضر (${summary.present})`} />
          <LegendDot className="bg-orange-400" label={`متأخر (${summary.late})`} />
          <LegendDot className="bg-red-500" label={`غائب (${summary.absent})`} />
          <LegendDot className="bg-slate-200 dark:bg-slate-700" label={`راحة/قادم (${summary.neutral})`} />
        </div>
      </header>

      {/* شبكة التقويم: 7 أعمدة تمثل أيام الأسبوع */}
      <ol
        className="grid grid-cols-7 gap-1.5"
        role="grid"
        aria-label="أيام الشهر"
      >
        {data.map((day) => {
          const meta = classifyStatus(day.status);
          return (
            <li
              key={day.date}
              role="gridcell"
              className={`group relative aspect-square rounded-sm ${meta.cell} transition-transform hover:scale-110 hover:ring-2 hover:ring-[var(--brand-primary)]/40`}
              title={`${day.date} — ${meta.label}`}
            >
              {/* رقم اليوم */}
              <span className="absolute inset-0 flex items-center justify-center text-[9px] font-bold text-white/90 mix-blend-luminosity pointer-events-none select-none">
                {Number(day.date.slice(-2))}
              </span>
              {/* تلميح مخصص عند المرور */}
              <span
                role="tooltip"
                className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded-md bg-[var(--surface-inverted,theme(colors.slate.900))] px-2 py-1 text-[10px] font-bold text-white shadow-lg group-hover:block"
              >
                {day.date} — {meta.label}
              </span>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

// ─── مكون مساعد ────────────────────────────────────────────────
function LegendDot({ className, label }: { className: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1">
      <span className={`inline-block size-2.5 rounded-sm ${className}`} aria-hidden="true" />
      <span>{label}</span>
    </span>
  );
}
