import { useMemo } from 'react';
import { Link } from 'react-router';
import { AlertTriangle, Ban, CheckCircle2, Clock, Coins, ShieldAlert, XCircle } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { useInstantPenalties, INSTANT_PENALTY_STATUS_LABELS } from './useInstantPenalties';
import { useFellowshipFundSummary } from './useFellowshipFund';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

function StatusIcon({ status }: { status: string }) {
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

export function MyInstantPenaltiesPage() {
  const auth = useAuth();
  const employeeId = auth.access?.employeeId;
  const penalties = useInstantPenalties(employeeId ? { employeeId } : {});
  const fundSummary = useFellowshipFundSummary();

  const rows = useMemo(() => penalties.data ?? [], [penalties.data]);

  const stats = useMemo(() => {
    const pending = rows.filter((p) => p.status === 'pending_payment');
    const doubled = rows.filter((p) => p.status === 'doubled');
    const suspended = rows.filter((p) => p.status === 'suspended');
    const paid = rows.filter((p) => p.status === 'paid');
    return {
      pendingCount: pending.length,
      pendingAmount: pending.reduce((s, p) => s + (p.currentAmount ?? 0), 0),
      doubledCount: doubled.length,
      doubledAmount: doubled.reduce((s, p) => s + (p.currentAmount ?? 0), 0),
      suspendedCount: suspended.length,
      paidCount: paid.length,
      totalPaid: paid.reduce((s, p) => s + (p.originalAmount ?? 0), 0),
    };
  }, [rows]);

  if (!employeeId) {
    return <ErrorState description="لم يتم العثور على ملف الموظف الحالي" />;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="حسابي"
        title="غرامات الحضور والانصراف"
        description="عرض غراماتك الفورية وحالتها. عند السداد للـ HR ستُزال الغرامة تلقائياً وفتح حسابك إن كنت معلّقاً."
      />

      {/* ─── بطاقة ملخص الموظف ────────────────────────────────────── */}
      <div className="relative overflow-hidden rounded-3xl border-2 border-amber-500/20 bg-gradient-to-br from-gray-900 via-amber-950/30 to-gray-950 p-6 md:p-8 text-white shadow-[0_0_40px_rgba(245,158,11,0.1)]">
        <div className="absolute -right-20 -top-20 h-64 w-64 rounded-full bg-amber-500/10 blur-3xl pointer-events-none" />
        <div className="absolute -left-20 -bottom-20 h-64 w-64 rounded-full bg-red-500/10 blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div className="space-y-3">
            <div className="inline-flex items-center gap-2 rounded-full border border-amber-500/30 bg-amber-500/10 px-3.5 py-1 text-xs font-bold text-amber-400">
              <AlertTriangle className="w-3.5 h-3.5" />
              <span>ملخص الغرامات الفورية</span>
            </div>
            <p className="text-xs text-white/60 max-w-lg leading-relaxed">
              الحضور يبدأ 10:00 ص — أول 15 دقيقة سماح بدون خصم. بعد ذلك: 20 ج.م (حتى 10:30) | 50 ج.م (حتى 11:00) | 150 ج.م (حتى 12:00). عدم السداد يُضاعف
              الغرامة لـ 500 ج.م ثم يُعلّق حسابك.
            </p>
          </div>

          <div className="grid grid-cols-3 gap-3 w-full md:w-auto shrink-0">
            <div className="rounded-2xl border border-amber-500/20 bg-black/40 p-4 backdrop-blur-sm text-center">
              <p className="text-2xl font-black font-mono text-amber-300">{stats.pendingCount}</p>
              <p className="text-[10px] text-white/50 mt-1">بانتظار الدفع</p>
              {stats.pendingAmount > 0 && <p className="text-[11px] font-bold text-amber-400 mt-0.5">{formatCurrency(stats.pendingAmount)}</p>}
            </div>
            <div className="rounded-2xl border border-red-500/20 bg-black/40 p-4 backdrop-blur-sm text-center">
              <p className="text-2xl font-black font-mono text-red-300">{stats.doubledCount + stats.suspendedCount}</p>
              <p className="text-[10px] text-white/50 mt-1">مضاعفة/معلّقة</p>
              {stats.doubledAmount > 0 && <p className="text-[11px] font-bold text-red-400 mt-0.5">{formatCurrency(stats.doubledAmount)}</p>}
            </div>
            <div className="rounded-2xl border border-emerald-500/20 bg-black/40 p-4 backdrop-blur-sm text-center">
              <p className="text-2xl font-black font-mono text-emerald-300">{stats.paidCount}</p>
              <p className="text-[10px] text-white/50 mt-1">مدفوعة</p>
              {stats.totalPaid > 0 && <p className="text-[11px] font-bold text-emerald-400 mt-0.5">{formatCurrency(stats.totalPaid)}</p>}
            </div>
          </div>
        </div>
      </div>

      {/* ─── تنبيه التعليق ──────────────────────────────────────────── */}
      {stats.suspendedCount > 0 && (
        <div className="rounded-2xl border-2 border-red-300 dark:border-red-700 bg-red-50/80 dark:bg-red-950/30 p-5">
          <div className="flex items-start gap-3">
            <Ban className="size-6 text-red-600 shrink-0 mt-0.5" />
            <div>
              <h3 className="font-black text-red-700 dark:text-red-400 text-sm">تم تعليق حسابك عن العمل</h3>
              <p className="text-xs text-red-600 dark:text-red-400/80 mt-1 leading-relaxed">
                حسابك مغلق على السيستم لعدم سداد غرامة مضاعفة (500 ج.م). يجب التوجه للـ HR وسداد المبلغ لإعادة فتح حسابك ومباشرة العمل.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* ─── تنبيه تصعيد ──────────────────────────────────────────── */}
      {stats.doubledCount > 0 && stats.suspendedCount === 0 && (
        <div className="rounded-2xl border border-orange-300 dark:border-orange-700 bg-orange-50/80 dark:bg-orange-950/30 p-5">
          <div className="flex items-start gap-3">
            <ShieldAlert className="size-5 text-orange-600 shrink-0 mt-0.5" />
            <div>
              <h3 className="font-black text-orange-700 dark:text-orange-400 text-sm">غرامات مضاعفة — السداد فوراً</h3>
              <p className="text-xs text-orange-600 dark:text-orange-400/80 mt-1 leading-relaxed">
                غراماتك تمت مضاعفتها إلى 500 ج.م لعدم السداد في الوقت المحدد. السداد المتأخر سيؤدي لتعليق حسابك عن العمل.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* ─── بطاقة صندوق الزمالة ───────────────────────────────────── */}
      {fundSummary.data && (
        <div className="rounded-2xl border border-emerald-200 dark:border-emerald-800/30 bg-emerald-50/50 dark:bg-emerald-950/15 p-4 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="rounded-xl bg-emerald-100 dark:bg-emerald-900/30 p-3 shrink-0">
              <Coins className="size-5 text-emerald-600 dark:text-emerald-400" />
            </div>
            <div>
              <h4 className="text-xs font-bold text-emerald-700 dark:text-emerald-400">صندوق الزمالة والتكافل (الخزنة التشاركية)</h4>
              <p className="text-[11px] text-emerald-600/80 dark:text-emerald-400/60 mt-0.5">
                جميع غرامات الحضور المدفوعة تُودع بالكامل في صندوق الزمالة لدعم الزملاء — الرصيد المتاح حالياً:{' '}
                <strong className="font-mono">{formatCurrency(fundSummary.data.currentBalance)}</strong>
              </p>
            </div>
          </div>
          <Link
            to="/admin/fellowship-fund"
            className="btn-primary text-xs !py-1.5 !px-3 bg-emerald-600 hover:bg-emerald-700 text-white shrink-0 whitespace-nowrap"
          >
            فتح سجل الخزنة والحركات ↗
          </Link>
        </div>
      )}

      {/* ─── قائمة الغرامات ────────────────────────────────────────── */}
      {penalties.isError ? (
        <ErrorState description={safeErrorMessage(penalties.error)} onRetry={() => void penalties.refetch()} />
      ) : penalties.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل غراماتك…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد غرامات فورية" description="ممتاز! لم تُسجَّل أي غرامات تأخير على حسابك. استمر في الحضور في الوقت المحدد (10:00 ص)." />
      ) : (
        <div className="space-y-3">
          {rows.map((p) => (
            <article
              key={p.id}
              className={`rounded-2xl border p-5 transition-all ${
                p.status === 'suspended'
                  ? 'border-red-300 dark:border-red-800 bg-red-50/50 dark:bg-red-950/20 shadow-lg shadow-red-500/5'
                  : p.status === 'doubled'
                    ? 'border-orange-200 dark:border-orange-700 bg-orange-50/30 dark:bg-orange-950/10'
                    : p.status === 'paid'
                      ? 'border-emerald-200 dark:border-emerald-700 bg-emerald-50/30 dark:bg-emerald-950/10'
                      : 'border-[var(--border)] bg-[var(--surface-base)]'
              }`}
            >
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                <div className="flex items-center gap-3">
                  <StatusIcon status={p.status} />
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-black text-sm">{dateFormatter.format(new Date(p.workDate + 'T00:00:00'))}</h3>
                      {p.status === 'suspended' && (
                        <span className="rounded-full bg-red-100 dark:bg-red-950/50 px-2 py-0.5 text-[10px] font-black text-red-700 dark:text-red-300">
                          معلّق
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-[var(--text-muted)] mt-0.5">
                      {p.lateMinutes >= 240 || p.notes?.includes('لم يسجل بصمة') ? (
                        <span className="inline-flex items-center gap-1 text-red-500 dark:text-red-400 font-semibold">
                          لم يسجل بصمة — غرامة أصلية {formatCurrency(p.originalAmount)}
                        </span>
                      ) : (
                        `تأخير ${p.lateMinutes} دقيقة — غرامة أصلية ${formatCurrency(p.originalAmount)}`
                      )}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <span
                    className={`text-lg font-black font-mono ${
                      p.status === 'paid'
                        ? 'text-emerald-600 dark:text-emerald-400'
                        : p.status === 'cancelled'
                          ? 'text-[var(--text-muted)] line-through'
                          : 'text-[var(--danger)]'
                    }`}
                  >
                    {formatCurrency(p.currentAmount)}
                  </span>
                  <StatusBadge status={p.status} label={INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status} />
                </div>
              </div>

              {p.notes && <p className="mt-2 text-[11px] text-[var(--text-muted)] border-t border-[var(--border)] pt-2">ملاحظات: {p.notes}</p>}
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
