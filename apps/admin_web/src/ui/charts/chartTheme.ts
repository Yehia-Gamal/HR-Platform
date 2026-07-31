/**
 * إعدادات مشتركة للرسوم البيانية — ألوان، محاور، تلميحات، أسماء عربية.
 * تقرأ متغيرات CSS في وقت التشغيل لتتبع الثيم الفاتح/الداكن تلقائياً.
 */

export type ChartDataPoint = { name: string; value: number; [key: string]: unknown };

/** أسماء الأشهر بالعربية (يناير = 0) */
export const ARABIC_MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'] as const;

/** أسماء أيام الأسبوع بالعربية (الأحد = 0) */
export const ARABIC_DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'] as const;

/** أسماء مختصرة للأيام */
export const ARABIC_DAYS_SHORT = ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'] as const;

// ── ألوان ثابتة تعمل في الوضعين الفاتح والداكن ──────────────────────────
const FALLBACK_PALETTE = [
  '#3b82f6', // أزرق
  '#06b6d4', // سيان
  '#10b981', // أخضر
  '#f59e0b', // برتقالي
  '#ef4444', // أحمر
  '#8b5cf6', // بنفسجي
  '#ec4899', // وردي
  '#14b8a6', // تيل
] as const;

/** CSS variable names mapped to palette slots */
const CSS_VAR_SLOTS = ['--brand-primary', '--brand-accent', '--success', '--warning', '--danger', '--info'] as const;

function readCssVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/**
 * يقرأ ألوان السلاسل من متغيرات CSS في وقت التشغيل.
 * يعيد 8 ألوان تتوافق مع الثيم الحالي (فاتح/داكن).
 */
export function getChartColors(): string[] {
  if (typeof document === 'undefined') return [...FALLBACK_PALETTE];

  const fromVars = CSS_VAR_SLOTS.map((v) => readCssVar(v)).filter(Boolean);
  if (fromVars.length < CSS_VAR_SLOTS.length) return [...FALLBACK_PALETTE];

  // 6 من المتغيرات + لونان ثابتان يكملان السلسلة
  return [...fromVars, '#ec4899', '#14b8a6'];
}

// ── أنماط مشتركة ─────────────────────────────────────────────────────────

/** نمط التلميح المشترك (RTL + خط عربي) */
export const TOOLTIP_STYLE: React.CSSProperties = {
  direction: 'rtl',
  fontFamily: 'Cairo, Noto Sans Arabic, Segoe UI, Tahoma, system-ui, sans-serif',
  fontSize: '0.72rem',
  fontWeight: 700,
  borderRadius: '0.7rem',
  border: '1px solid var(--border)',
  background: 'var(--surface-raised)',
  color: 'var(--text-primary)',
  boxShadow: 'var(--shadow-card)',
  padding: '0.55rem 0.75rem',
};

/** نمط المحور المشترك — يخفي المحورين العلوي والأيمن */
export const AXIS_PROPS = {
  xAxis: {
    axisLine: false,
    tickLine: false,
    tick: {
      fill: 'var(--text-muted)',
      fontSize: 11,
      fontWeight: 700,
    },
  },
  yAxis: {
    axisLine: false,
    tickLine: false,
    tick: {
      fill: 'var(--text-muted)',
      fontSize: 11,
      fontWeight: 700,
    },
    width: 38,
  },
} as const;

/** نمط الشبكة الخلفية */
export const GRID_PROPS = {
  strokeDasharray: '4 4',
  stroke: 'var(--border)',
  vertical: false,
} as const;
