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
};

export function computeLedStatus(status: string, lastUpdateAt: string | null): LedStatus {
  if (status === 'completed' || status === 'cancelled') return 'stale';
  if (status === 'on_hold') return 'halted';
  if (!lastUpdateAt) return 'stale';
  const diff = Date.now() - new Date(lastUpdateAt).getTime();
  const days = diff / (1000 * 60 * 60 * 24);
  if (days > 30) return 'stale';
  if (days > 14) return 'halted';
  return 'active';
}

export function ledCardClass(led: LedStatus): string {
  const base = 'relative rounded-xl border-2 transition-all duration-300 hover:scale-[1.02] cursor-pointer';
  switch (led) {
    case 'active':
      return `${base} border-emerald-400 bg-gradient-to-br from-emerald-50/80 to-white dark:from-emerald-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(16,185,129,0.3)]`;
    case 'halted':
      return `${base} border-red-400 bg-gradient-to-br from-red-50/80 to-white dark:from-red-950/30 dark:to-gray-900 hover:shadow-[0_0_20px_6px_rgba(239,68,68,0.3)]`;
    case 'stale':
      return `${base} border-gray-300 dark:border-gray-700 bg-gray-50/50 dark:bg-gray-800/30 opacity-60 hover:opacity-80`;
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
