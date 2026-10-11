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
