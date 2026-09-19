import type { LedStatus } from './types';

export const LED_COLORS: Record<LedStatus, { bg: string; glow: string; ring: string; label: string }> = {
  active: {
    bg: 'bg-emerald-500',
    glow: 'shadow-lg shadow-emerald-500/50',
    ring: 'ring-emerald-400',
    label: 'نشط — قيد التحديث',
  },
  halted: {
    bg: 'bg-red-500',
    glow: 'shadow-lg shadow-red-500/50',
    ring: 'ring-red-400',
    label: 'متوقف — يحتاج متابعة',
  },
  stale: {
    bg: 'bg-gray-600 dark:bg-gray-700',
    glow: '',
    ring: 'ring-gray-500',
    label: 'مطفأ — لا تحديثات',
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
  const base = 'relative rounded-xl border-2 transition-all duration-300 hover:scale-[1.02]';
  switch (led) {
    case 'active':
      return `${base} border-emerald-400 bg-emerald-50/50 dark:bg-emerald-950/20`;
    case 'halted':
      return `${base} border-red-400 bg-red-50/50 dark:bg-red-950/20`;
    case 'stale':
      return `${base} border-gray-300 bg-gray-50/50 dark:bg-gray-800/30 opacity-70`;
  }
}
