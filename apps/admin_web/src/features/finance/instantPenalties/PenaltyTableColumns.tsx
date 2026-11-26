import {
  Ban,
  Calendar,
  CheckCircle2,
  Clock,
  Coins,
  Flame,
  MessageCircle,
  RotateCcw,
  ShieldAlert,
  XCircle,
} from 'lucide-react';
import type { DataTableColumn } from '../../../ui/DataTable';
import { isPhoneLikeCode } from '../../../ui/phoneDisplay';
import { StatusBadge } from '../../../ui/StatusBadge';
import { UserAvatar } from '../../../ui/UserAvatar';
import { INSTANT_PENALTY_STATUS_LABELS, type InstantPenalty } from '../useInstantPenalties';
import { fmtDateWithDay, fmtLateDisplay, formatCurrency } from './penaltyFormatters';

export type PenaltyTableRow = InstantPenalty & { photoUrl?: string | null };

/** أيقونة + لون حسب الحالة */
export function PenaltyStatusIcon({ status }: { status: string }) {
  switch (status) {
    case 'pending_payment':
      return <Clock className="size-4 text-amber-500" aria-hidden="true" />;
    case 'paid':
      return <CheckCircle2 className="size-4 text-emerald-500" aria-hidden="true" />;
    case 'doubled':
      return <ShieldAlert className="size-4 text-orange-500" aria-hidden="true" />;
    case 'suspended':
      return <Ban className="size-4 text-red-600" aria-hidden="true" />;
    case 'cancelled':
      return <XCircle className="size-4 text-[var(--text-muted)]" aria-hidden="true" />;
    default:
      return null;
  }
}

const EXEMPTION_NOTE_KEYWORDS = [
  'إلغاء بأثر رجعي',
  'إلغاء تلقائي',
  'إلغاء نهائي',
  'مأمورية',
  'إجازة',
  'قافلة',
  'فاندي',
  'المدير التنفيذي',
  'استثناء',
  'معفى',
];

function isExemptionNote(notes: string | null | undefined, includeFinal: boolean): boolean {
  if (!notes) return false;
  return EXEMPTION_NOTE_KEYWORDS.some((kw) => (includeFinal || kw !== 'إلغاء نهائي') && notes.includes(kw));
}

export interface BuildPenaltyColumnsParams {
  employeePhotoMap: Map<string, string | null>;
  confirmPending: boolean;
  liftPending: boolean;
  revertPending: boolean;
  cancelPending: boolean;
  onPaymentClick: (p: InstantPenalty) => void;
  onLiftClick: (p: InstantPenalty) => void;
  onRevertClick: (p: InstantPenalty) => void;
  onCancelClick: (p: InstantPenalty) => void;
  onWhatsAppClick: (p: InstantPenalty) => void;
}

export function buildPenaltyColumns({
  employeePhotoMap,
  confirmPending,
  liftPending,
  revertPending,
  cancelPending,
  onPaymentClick,
  onLiftClick,
  onRevertClick,
  onCancelClick,
  onWhatsAppClick,
}: BuildPenaltyColumnsParams): DataTableColumn<PenaltyTableRow>[] {
  return [
    {
      key: 'employeeName',
      header: 'الموظف والإدارة',
      sortable: true,
      render: (p) => {
        const photo = p.photoUrl ?? employeePhotoMap.get(p.employeeId);
        return (
          <div className="flex items-center gap-3 min-w-[180px]">
            <UserAvatar displayName={p.employeeName ?? ''} photoUrl={photo} size="md" announceName={false} />
            <div className="flex flex-col min-w-0">
              <span className="font-bold text-sm text-[var(--text-primary)] leading-snug truncate">{p.employeeName ?? '—'}</span>
              <div className="flex items-center gap-1.5 text-[11px] text-[var(--text-muted)] mt-0.5">
                {p.employeeCode && !isPhoneLikeCode(p.employeeCode) && (
                  <span className="font-mono bg-[var(--surface-muted)] px-1.5 py-0.5 rounded text-[10px] text-[var(--text-secondary)] border border-[var(--border-subtle)]">
                    <bdi dir="ltr">{p.employeeCode}</bdi>
                  </span>
                )}
                <span className="truncate">{p.departmentName ?? '—'}</span>
              </div>
              {p.status === 'suspended' && (
                <span className="inline-flex items-center gap-1 mt-1 w-fit rounded-full bg-red-100 dark:bg-red-950/60 px-2 py-0.5 text-[10px] font-black text-red-700 dark:text-red-300 border border-red-300 dark:border-red-800">
                  <Ban className="size-3" /> معلّق عن العمل
                </span>
              )}
            </div>
          </div>
        );
      },
    },
    {
      key: 'workDate',
      header: 'التاريخ',
      sortable: true,
      render: (p) => (
        <div className="flex items-center gap-1.5 text-xs whitespace-nowrap font-mono text-[var(--text-secondary)] font-medium">
          <Calendar className="size-3.5 text-primary/70 shrink-0" aria-hidden="true" />
          <span>{fmtDateWithDay(p.workDate)}</span>
        </div>
      ),
    },
    {
      key: 'lateMinutes',
      header: 'التأخير / السبب',
      sortable: true,
      render: (p) => {
        const isUnpunched = Boolean(p.notes && p.notes.includes('لم يسجل بصمة'));
        const isActualLate = Boolean(p.notes && p.notes.includes('تأخير حضور فعلي'));
        return (
          <div className="flex flex-col gap-1 min-w-[120px]">
            <span className="font-black font-mono text-sm text-amber-600 dark:text-amber-400 whitespace-nowrap">{fmtLateDisplay(p.lateMinutes)}</span>
            {isUnpunched && (
              <span className="inline-flex items-center gap-1.5 w-fit rounded-md bg-rose-500/10 border border-rose-500/25 px-2 py-0.5 text-[10px] font-bold text-rose-600 dark:text-rose-400 whitespace-nowrap shadow-2xs">
                <span className="size-1.5 rounded-full bg-rose-500 animate-pulse" />
                لم يسجل بصمة
              </span>
            )}
            {isActualLate && (
              <span className="inline-flex items-center gap-1 w-fit rounded-md bg-amber-500/10 border border-amber-500/25 px-1.5 py-0.5 text-[10px] font-bold text-amber-700 dark:text-amber-300 whitespace-nowrap">
                <Clock className="size-2.5 text-amber-500" aria-hidden="true" />
                تأخير حضور فعلي
              </span>
            )}
          </div>
        );
      },
    },
    {
      key: 'currentAmount',
      header: 'المبلغ المطلوب',
      sortable: true,
      render: (p) => {
        const isDoubled = p.currentAmount > p.originalAmount;
        return (
          <div className="flex flex-col gap-0.5 whitespace-nowrap min-w-[95px]">
            <div className="flex items-center gap-1.5">
              <span
                className={`font-black font-mono text-sm sm:text-base ${
                  p.status === 'paid'
                    ? 'text-emerald-600 dark:text-emerald-400'
                    : isDoubled
                      ? 'text-red-600 dark:text-red-400'
                      : 'text-amber-600 dark:text-amber-400'
                }`}
              >
                {formatCurrency(p.currentAmount)}
              </span>
              {isDoubled && (
                <span className="inline-flex items-center gap-0.5 text-[10px] font-bold text-red-600 dark:text-red-400 bg-red-500/10 px-1.5 py-0.5 rounded border border-red-500/20">
                  <Flame className="size-2.5" aria-hidden="true" /> مضاعف
                </span>
              )}
            </div>
            {isDoubled && <span className="text-[10px] text-[var(--text-muted)] font-mono">الأصلية: {formatCurrency(p.originalAmount)}</span>}
          </div>
        );
      },
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (p) => {
        if (p.awaitingCheckoutConfirmation) {
          return (
            <div
              className="flex flex-col gap-0.5"
              title="أتم الموظف 8 ساعات عمل بنجاح، وبانتظار تسجيل بصمة الانصراف بمقر العمل لإلغاء الغرامة نهائياً وتأكيد التواجد."
            >
              <span className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-[11px] font-bold bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30 whitespace-nowrap">
                <Clock className="size-3 text-amber-500 shrink-0" />
                مستوفي 8 س (بانتظار بصمة الانصراف)
              </span>
              {p.elapsedMinutesToday ? (
                <span className="text-[10px] text-[var(--text-muted)] font-mono">
                  {Math.floor(p.elapsedMinutesToday / 60)} س و {p.elapsedMinutesToday % 60} د بالعمل
                </span>
              ) : null}
            </div>
          );
        }

        const isExempt = p.status === 'cancelled' && isExemptionNote(p.notes, true);
        return (
          <div className="flex items-center gap-1.5 whitespace-nowrap" title={p.notes ?? undefined}>
            <PenaltyStatusIcon status={p.status} />
            <StatusBadge status={p.status} label={isExempt ? 'معفى (ملغاة)' : (INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status)} />
          </div>
        );
      },
    },
    {
      key: 'actions',
      header: 'الإجراءات',
      render: (p) => {
        if (p.status === 'paid') {
          return (
            <span className="inline-flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400 font-bold whitespace-nowrap bg-emerald-500/10 px-2.5 py-1 rounded-md border border-emerald-500/20">
              ✓ مدفوعة ومُزيلَة
            </span>
          );
        }
        if (p.status === 'cancelled') {
          const isExempt = isExemptionNote(p.notes, false);
          return (
            <span
              className={`inline-flex items-center gap-1 text-xs font-semibold whitespace-nowrap px-2.5 py-1 rounded-md ${
                isExempt ? 'bg-sky-500/10 text-sky-700 dark:text-sky-300 border border-sky-500/20' : 'bg-[var(--surface-muted)] text-[var(--text-muted)]'
              }`}
              title={p.notes ?? 'ملغاة'}
            >
              <XCircle className="size-3.5" aria-hidden="true" />
              {isExempt ? 'معفى من الغرامة' : 'ملغاة'}
            </span>
          );
        }
        return (
          <div className="flex items-center gap-1.5 whitespace-nowrap">
            <button
              type="button"
              className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 shadow-xs transition-all active:scale-95 disabled:opacity-50 whitespace-nowrap cursor-pointer"
              disabled={confirmPending}
              onClick={() => onPaymentClick(p)}
              title="استلام من الموظف وإيداع في صندوق الزمالة والتكافل"
            >
              <Coins className="size-3.5 text-amber-300" aria-hidden="true" />
              <span>استلام وإيداع بالصندوق</span>
            </button>
            {p.status === 'suspended' && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold bg-amber-500/10 hover:bg-amber-500/20 text-amber-700 dark:text-amber-300 border border-amber-500/30 transition-all whitespace-nowrap cursor-pointer"
                disabled={liftPending}
                onClick={() => onLiftClick(p)}
              >
                رفع التعليق
              </button>
            )}
            {(p.currentAmount > p.originalAmount || p.status === 'doubled' || p.status === 'suspended') && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold bg-indigo-50 hover:bg-indigo-100 text-indigo-700 dark:bg-indigo-950/40 dark:text-indigo-300 border border-indigo-300 dark:border-indigo-800 transition-all whitespace-nowrap cursor-pointer"
                disabled={revertPending}
                onClick={() => onRevertClick(p)}
                title={`إرجاع الغرامة إلى قيمتها الأصلية (${formatCurrency(p.originalAmount)}) بدون مضاعفة`}
              >
                <RotateCcw className="size-3.5 text-indigo-600 dark:text-indigo-400" aria-hidden="true" />
                <span>إرجاع للأصل ({formatCurrency(p.originalAmount)})</span>
              </button>
            )}
            {(p.status === 'pending_payment' || p.status === 'doubled') && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold text-[var(--danger)] hover:bg-[var(--danger)]/10 border border-transparent hover:border-[var(--danger)]/20 transition-all whitespace-nowrap cursor-pointer"
                disabled={cancelPending}
                onClick={() => onCancelClick(p)}
                title="إلغاء الغرامة"
              >
                <XCircle className="size-3.5" aria-hidden="true" />
                <span>إلغاء</span>
              </button>
            )}
            {(p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended') && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold bg-emerald-50 hover:bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800 transition-all whitespace-nowrap cursor-pointer"
                onClick={() => onWhatsAppClick(p)}
                title="إرسال تنبيه واتساب فوري للزميل (مجاناً 100%)"
              >
                <MessageCircle className="size-3.5 text-emerald-600" aria-hidden="true" />
                <span>واتساب</span>
              </button>
            )}
          </div>
        );
      },
    },
  ];
}
