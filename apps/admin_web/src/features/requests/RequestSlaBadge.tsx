import React from 'react';
import { Clock3, MessageCircle } from 'lucide-react';
import { shareRequestDetails } from '../../core/whatsappShare';

export type SlaLevel = 'fast' | 'warning' | 'breached';

export interface SlaInfo {
  level: SlaLevel;
  isPending: boolean;
  hours: number;
  label: string;
  tooltip: string;
  badgeClass: string;
}

export function calculateRequestSla({
  status,
  createdAt,
  decidedAt,
  activeStepName,
  assigneeName,
}: {
  status: string;
  createdAt: string;
  decidedAt?: string | null;
  activeStepName?: string | null;
  assigneeName?: string | null;
}): SlaInfo {
  const isPending = ['pending', 'escalated', 'submitted', 'returned'].includes(status);
  const start = new Date(createdAt).getTime();
  const end = !isPending && decidedAt ? new Date(decidedAt).getTime() : Date.now();
  const diffMs = Math.max(0, end - start);
  const hours = diffMs / 3_600_000;

  const target = activeStepName || assigneeName ? `لدى ${activeStepName || assigneeName}` : '';

  if (isPending) {
    if (hours < 2) {
      return {
        level: 'fast',
        isPending: true,
        hours,
        label: '🟢 سريع (< ساعتين)',
        tooltip: 'الطلب قيد الإجراء ضمن مهلة الاستجابة السريعة القياسية',
        badgeClass: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/20',
      };
    }
    if (hours <= 24) {
      const hStr = Math.round(hours);
      return {
        level: 'warning',
        isPending: true,
        hours,
        label: `🟡 معلق (${hStr}س)`,
        tooltip: `الطلب معلق منذ ${hStr} ساعة ${target}`.trim(),
        badgeClass: 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/20',
      };
    }
    const hStr = Math.round(hours);
    return {
      level: 'breached',
      isPending: true,
      hours,
      label: `🔴 متأخر (${hStr}س)`,
      tooltip: `تجاوز مهلة الـ SLA: معلق منذ ${hStr} ساعة ${target}`.trim(),
      badgeClass: 'bg-rose-500/15 text-rose-700 dark:text-rose-300 border-rose-500/30 animate-pulse',
    };
  }

  // الطلب منتهي (معتمد / مرفوض / مسحوب)
  if (hours < 2) {
    return {
      level: 'fast',
      isPending: false,
      hours,
      label: '⚡ أُنجز في < ساعتين',
      tooltip: 'تم البت في هذا الطلب بسرعة قياسية',
      badgeClass: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20',
    };
  }
  if (hours <= 24) {
    const hStr = Math.round(hours);
    return {
      level: 'warning',
      isPending: false,
      hours,
      label: `⏱️ أُنجز في ${hStr}س`,
      tooltip: `استغرق البت في الطلب ${hStr} ساعة`,
      badgeClass: 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    };
  }
  const hStr = Math.round(hours);
  return {
    level: 'breached',
    isPending: false,
    hours,
    label: `⌛ استغرق ${hStr}س`,
    tooltip: `استغرق البت في هذا الطلب ${hStr} ساعة`,
    badgeClass: 'bg-[var(--surface-muted)] text-[var(--text-muted)] border-[var(--border)]',
  };
}

export function RequestSlaBadge({
  status,
  createdAt,
  decidedAt,
  activeStepName,
  assigneeName,
  compact = false,
}: {
  status: string;
  createdAt: string;
  decidedAt?: string | null;
  activeStepName?: string | null;
  assigneeName?: string | null;
  compact?: boolean;
}) {
  const sla = calculateRequestSla({ status, createdAt, decidedAt, activeStepName, assigneeName });

  return (
    <span
      className={`inline-flex items-center gap-1 rounded-lg border px-2 py-0.5 font-bold transition-colors ${
        compact ? 'text-[10px]' : 'text-xs'
      } ${sla.badgeClass}`}
      title={sla.tooltip}
    >
      <Clock3 className={compact ? 'size-2.5' : 'size-3'} aria-hidden="true" />
      <span>{sla.label}</span>
    </span>
  );
}

export function RequestWhatsAppShareButton({
  number,
  typeLabel,
  employeeName,
  statusLabel,
  reason,
  currentStep,
  phone,
  size = 'md',
}: {
  number?: number | string | null;
  typeLabel: string;
  employeeName: string;
  statusLabel?: string | null;
  reason?: string | null;
  currentStep?: string | null;
  phone?: string | null;
  size?: 'sm' | 'md';
}) {
  const isSm = size === 'sm';
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        shareRequestDetails({ number, typeLabel, employeeName, statusLabel, reason, currentStep, phone });
      }}
      className={`inline-flex items-center gap-1.5 rounded-xl border border-emerald-500/20 bg-emerald-500/10 font-bold text-emerald-600 dark:text-emerald-400 hover:bg-emerald-500/20 transition-colors ${
        isSm ? 'px-2 py-1 text-[11px]' : 'px-3 py-1.5 text-xs'
      }`}
      title="مشاركة تفاصيل الطلب عبر الواتساب للمتابعة السريعة"
    >
      <MessageCircle className={isSm ? 'size-3' : 'size-3.5'} aria-hidden="true" />
      <span>واتساب</span>
    </button>
  );
}

/**
 * فحص ما إذا كان الطلب مقدماً بأثر رجعي (أي أن تاريخ حدوثه الفعلي يسبق تاريخ تقديمه).
 */
export function checkRetroactiveRequest(
  createdAt: string,
  payload?: Record<string, unknown> | null,
): { isRetroactive: boolean; daysDiff: number } {
  if (!payload || !createdAt) return { isRetroactive: false, daysDiff: 0 };
  const targetStr = (payload.startDate || payload.permitDate || payload.workDate || payload.date || payload.correctionDate) as
    | string
    | undefined;
  if (!targetStr || typeof targetStr !== 'string') return { isRetroactive: false, daysDiff: 0 };

  const targetDate = new Date(targetStr);
  const createdDate = new Date(createdAt);
  if (Number.isNaN(targetDate.getTime()) || Number.isNaN(createdDate.getTime())) {
    return { isRetroactive: false, daysDiff: 0 };
  }

  // مقارنة على مستوى الأيام التقويمية
  const targetDay = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime();
  const createdDay = new Date(createdDate.getFullYear(), createdDate.getMonth(), createdDate.getDate()).getTime();
  const diffDays = Math.floor((createdDay - targetDay) / (1000 * 60 * 60 * 24));

  return { isRetroactive: diffDays > 0, daysDiff: diffDays };
}

/**
 * شارة تمييز الطلب بأثر رجعي أمام المديرين والموارد البشرية.
 */
export function RetroactiveBadge({ daysDiff, compact }: { daysDiff: number; compact?: boolean }) {
  const label = daysDiff === 1 ? 'طلب بأثر رجعي (بعد بيوم)' : `طلب بأثر رجعي (بعد ${daysDiff} يوم)`;
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-lg border border-amber-500/30 bg-amber-500/10 font-bold text-amber-600 dark:text-amber-400 shrink-0 ${
        compact ? 'px-1.5 py-0.5 text-[10.5px]' : 'px-2 py-1 text-xs'
      }`}
      title={`قُدم هذا الطلب بعد موعد حدوثه الفعلي بـ ${daysDiff} يوم`}
    >
      <Clock3 className={compact ? 'size-2.5' : 'size-3'} />
      {label}
    </span>
  );
}

