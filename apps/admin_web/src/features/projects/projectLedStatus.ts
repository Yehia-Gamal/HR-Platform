import type { LedStatus } from './types';

export const LED_COLORS: Record<LedStatus, { bg: string; glow: string; ring: string; label: string; borderDot: string }> = {
  active: {
    bg: 'bg-emerald-500',
    glow: 'shadow-[0_0_12px_4px_rgba(16,185,129,0.5)]',
    ring: 'ring-emerald-400',
    label: 'نشط',
    borderDot: 'border-emerald-400',
  },
  halted: {
    bg: 'bg-red-500',
    glow: 'shadow-[0_0_12px_4px_rgba(239,68,68,0.5)]',
    ring: 'ring-red-400',
    label: 'متوقف',
    borderDot: 'border-red-400',
  },
  stale: {
    bg: 'bg-gray-500 dark:bg-gray-600',
    glow: '',
    ring: 'ring-gray-400',
    label: 'مطفأ',
    borderDot: 'border-gray-400',
  },
  pending: {
    bg: 'bg-amber-500',
    glow: 'shadow-[0_0_12px_4px_rgba(245,158,11,0.5)]',
    ring: 'ring-amber-400',
    label: 'بانتظار الموافقة',
    borderDot: 'border-amber-400',
  },
  rejected: {
    bg: 'bg-rose-600',
    glow: 'shadow-[0_0_12px_4px_rgba(225,29,72,0.5)]',
    ring: 'ring-rose-500',
    label: 'مرفوض',
    borderDot: 'border-rose-500',
  },
  draft: {
    bg: 'bg-slate-400 dark:bg-slate-500',
    glow: '',
    ring: 'ring-slate-400',
    label: 'مسودة',
    borderDot: 'border-slate-400',
  },
};

export function ledCardClass(led: LedStatus): string {
  const base = 'relative rounded-xl border-2 transition-all duration-300 hover:scale-[1.02] cursor-pointer';
  switch (led) {
    case 'active':
      return `${base} border-emerald-400 bg-gradient-to-br from-emerald-50/80 to-white dark:from-emerald-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(16,185,129,0.3)]`;
    case 'halted':
      return `${base} border-red-400 bg-gradient-to-br from-red-50/80 to-white dark:from-red-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(239,68,68,0.3)]`;
    case 'stale':
      return `${base} border-gray-300 dark:border-gray-700 bg-gray-50/50 dark:bg-gray-800/30 opacity-60 hover:opacity-80`;
    case 'pending':
      return `${base} border-amber-400 bg-gradient-to-br from-amber-50/80 to-white dark:from-amber-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(245,158,11,0.3)]`;
    case 'rejected':
      return `${base} border-rose-400 bg-gradient-to-br from-rose-50/80 to-white dark:from-rose-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(225,29,72,0.3)]`;
    case 'draft':
      return `${base} border-slate-300 dark:border-slate-600 bg-slate-50/50 dark:bg-slate-800/30 opacity-70 hover:opacity-90`;
  }
}

export function daysSince(dateStr: string | null): string {
  if (!dateStr) return '';
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86_400_000);
  if (days === 0) return 'اليوم';
  if (days === 1) return 'أمس';
  if (days < 7) return `منذ ${days} أيام`;
  if (days < 30) return `منذ ${Math.floor(days / 7)} أسابيع`;
  return `منذ ${Math.floor(days / 30)} أشهر`;
}

export const APPROVAL_LABELS: Record<string, string> = {
  draft: 'مسودة',
  pending_approval: 'بانتظار الموافقة',
  approved: 'معتمد',
  rejected: 'مرفوض',
};

export const APPROVAL_COLORS: Record<string, string> = {
  draft: 'bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300',
  pending_approval: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  approved: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400',
  rejected: 'bg-rose-100 text-rose-700 dark:bg-rose-900/30 dark:text-rose-400',
};
