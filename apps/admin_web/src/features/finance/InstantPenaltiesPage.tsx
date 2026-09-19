import { cairoTodayIso } from '../../core/cairoTime';
import { useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import {
  AlertTriangle,
  ArrowRight,
  Ban,
  CheckCircle2,
  Clock,
  Clock3,
  Coins,
  ExternalLink,
  Eye,
  FileSpreadsheet,
  Flame,
  HeartHandshake,
  Layers,
  Printer,
  RefreshCw,
  ShieldAlert,
  Sparkles,
  SunMedium,
  Users,
  X,
  XCircle,
  Zap,
} from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { InputDialog } from '../../ui/InputDialog';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useEmployees } from '../employees/useEmployees';
import { useFellowshipFundSummary } from './useFellowshipFund';
import {
  INSTANT_PENALTY_ESCALATION_LABELS,
  INSTANT_PENALTY_STATUS_LABELS,
  useCancelInstantPenalty,
  useConfirmInstantPenaltyPayment,
  useGenerateInstantPenalty,
  useInstantPenalties,
  useLiftInstantPenaltySuspension,
  usePendingPenaltyEmployees,
  useTriggerCheckPenaltiesNow,
} from './useInstantPenalties';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

/** أيقونة + لون حسب الحالة */
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
      return <XCircle className="size-4 text-gray-400" aria-hidden="true" />;
    default:
      return null;
  }
}

export function InstantPenaltiesPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedTier, setSelectedTier] = useState<
    'all' | 'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended'
  >('all');
  const [activeModalTier, setActiveModalTier] = useState<
    'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended' | 'total' | null
  >(null);

  const penalties = useInstantPenalties(statusFilter === 'all' ? {} : { status: statusFilter });
  const pendingEmployees = usePendingPenaltyEmployees();
  const fundSummary = useFellowshipFundSummary();
  const confirmPayment = useConfirmInstantPenaltyPayment();
  const generatePenalty = useGenerateInstantPenalty();
  const cancelPenalty = useCancelInstantPenalty();
  const liftSuspension = useLiftInstantPenaltySuspension();
  const triggerCheck = useTriggerCheckPenaltiesNow();
  const { data: employees } = useEmployees();

  const [checkFeedback, setCheckFeedback] = useState<string | null>(null);

  const [formOpen, setFormOpen] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [lateMinutes, setLateMinutes] = useState('');
  const [workDate, setWorkDate] = useState(cairoTodayIso());

  const [paymentDialogOpen, setPaymentDialogOpen] = useState(false);
  const [paymentTarget, setPaymentTarget] = useState<{ id: string; name: string; msg: string } | null>(null);
  const [paymentNotes, setPaymentNotes] = useState('');

  const [liftDialogOpen, setLiftDialogOpen] = useState(false);
  const [liftTarget, setLiftTarget] = useState<{ id: string; name: string } | null>(null);
  const [liftReason, setLiftReason] = useState('');

  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [cancelTarget, setCancelTarget] = useState<{ id: string; name: string } | null>(null);
  const [cancelReason, setCancelReason] = useState('');

  // ─── تفنيط وإحصائيات شرائح الغرامات ──────────────────────────────────

  const tierStats = useMemo(() => {
    const items = penalties.data ?? [];
    const pendingList = items.filter((p) => p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended');

    const tier20 = items.filter((p) =>
      p.status !== 'cancelled' &&
      (p.currentAmount === 20 || (p.originalAmount === 20 && p.escalationLevel === 'initial'))
    );
    const tier50 = items.filter((p) =>
      p.status !== 'cancelled' &&
      (p.currentAmount === 50 || (p.originalAmount === 50 && p.escalationLevel === 'initial'))
    );
    const tier150 = items.filter((p) =>
      p.status !== 'cancelled' &&
      (p.currentAmount === 150 || (p.originalAmount === 150 && p.escalationLevel === 'initial'))
    );
    const tier500 = items.filter((p) =>
      p.status === 'doubled' || p.escalationLevel === 'doubled' || p.currentAmount === 500
    );
    const suspended = items.filter((p) => p.status === 'suspended');

    return {
      pending: {
        count: pendingList.length,
        total: pendingList.reduce((s, p) => s + p.currentAmount, 0),
        items: pendingList,
      },
      tier20: {
        count: tier20.length,
        total: tier20.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier20.filter((p) => p.status === 'pending_payment').length,
        items: tier20,
      },
      tier50: {
        count: tier50.length,
        total: tier50.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier50.filter((p) => p.status === 'pending_payment').length,
        items: tier50,
      },
      tier150: {
        count: tier150.length,
        total: tier150.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier150.filter((p) => p.status === 'pending_payment').length,
        items: tier150,
      },
      tier500: {
        count: tier500.length,
        total: tier500.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier500.filter((p) => p.status === 'doubled' || p.status === 'pending_payment').length,
        items: tier500,
      },
      suspended: {
        count: suspended.length,
        total: suspended.reduce((s, p) => s + p.currentAmount, 0),
        items: suspended,
      },
    };
  }, [penalties.data]);

  // ─── بيانات الجدول ─────────────────────────────────────────────────

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    let items = penalties.data ?? [];

    if (selectedTier === 'pending') {
      items = items.filter((p) => p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended');
    } else if (selectedTier === 'tier-20') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 20 || (p.originalAmount === 20 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-50') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 50 || (p.originalAmount === 50 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-150') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 150 || (p.originalAmount === 150 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-500') {
      items = items.filter((p) => p.status === 'doubled' || p.escalationLevel === 'doubled' || p.currentAmount === 500);
    } else if (selectedTier === 'suspended') {
      items = items.filter((p) => p.status === 'suspended');
    }

    return q
      ? items.filter(
          (p) =>
            (p.employeeName ?? '').toLowerCase().includes(q) ||
            (p.employeeCode ?? '').toLowerCase().includes(q) ||
            (p.departmentName ?? '').toLowerCase().includes(q),
        )
      : items;
  }, [penalties.data, search, selectedTier]);

  // ─── إحصائيات سريعة ───────────────────────────────────────────────

  const stats = useMemo(() => {
    const pending = pendingEmployees.data ?? [];
    const suspendedCount = pending.filter((e) => e.isSuspended).length;
    const pendingCount = pending.length;
    const totalOwed = pending.reduce((s, e) => s + e.totalAmount, 0);
    return { suspendedCount, pendingCount, totalOwed };
  }, [pendingEmployees.data]);

  // ─── أعمدة الجدول ─────────────────────────────────────────────────

  const columns: DataTableColumn<(typeof rows)[number]>[] = [
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (p) => (
        <div className="min-w-[140px]">
          <span className="font-bold block leading-tight">{p.employeeName ?? '—'}</span>
          <span className="text-[11px] text-[var(--text-muted)] block">{p.departmentName ?? '—'}</span>
          {p.status === 'suspended' && <span className="inline-block mt-1 rounded-full bg-red-100 px-1.5 py-0.5 text-[10px] font-black text-red-700">معلّق</span>}
        </div>
      ),
    },
    { key: 'workDate', header: 'التاريخ', sortable: true, render: (p) => <span className="whitespace-nowrap">{dateFormatter.format(new Date(p.workDate + 'T00:00:00'))}</span> },
    {
      key: 'lateMinutes',
      header: 'التأخير',
      sortable: true,
      render: (p) => (
        <div className="flex flex-col gap-0.5">
          <span className="font-bold text-amber-600 whitespace-nowrap">
            {p.lateMinutes} <span className="text-xs font-normal">دقيقة</span>
          </span>
          {p.notes && p.notes.includes('لم يسجل بصمة') ? (
            <span className="inline-block w-fit rounded bg-rose-50 dark:bg-rose-950/40 px-1.5 py-0.5 text-[10px] font-bold text-rose-600 dark:text-rose-400 border border-rose-200 dark:border-rose-900/40">
              لم يبصم
            </span>
          ) : p.notes && p.notes.includes('تأخير حضور فعلي') ? (
            <span className="inline-block w-fit rounded bg-amber-50 dark:bg-amber-950/40 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-400">
              تأخير فعلي
            </span>
          ) : null}
        </div>
      ),
    },
    {
      key: 'originalAmount',
      header: 'الأصلية',
      render: (p) => <span className="text-[var(--text-muted)] whitespace-nowrap">{formatCurrency(p.originalAmount)}</span>,
    },
    {
      key: 'currentAmount',
      header: 'المطلوب',
      sortable: true,
      render: (p) => (
        <span className={`font-black whitespace-nowrap ${p.status === 'paid' ? 'text-emerald-600' : 'text-[var(--danger)]'}`}>
          {formatCurrency(p.currentAmount)}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (p) => (
        <div className="flex items-center gap-1.5 whitespace-nowrap">
          <StatusIcon status={p.status} />
          <StatusBadge status={p.status} label={INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status} />
        </div>
      ),
    },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (p) => {
        if (p.status === 'paid') {
          return <span className="text-xs text-emerald-600 font-bold whitespace-nowrap">✓ مدفوعة ومُزيلَة</span>;
        }
        if (p.status === 'cancelled') {
          return <span className="text-xs text-gray-400 font-bold">ملغاة</span>;
        }
        return (
          <div className="flex flex-wrap items-center gap-1.5">
            <button
              type="button"
              className="btn-primary text-[11px] leading-tight !min-h-0 !py-1.5 !px-2.5 bg-emerald-600 hover:bg-emerald-700 text-white font-bold whitespace-nowrap"
              disabled={confirmPayment.isPending}
              onClick={() => {
                const confirmMsg =
                  p.status === 'suspended'
                    ? `هل تم استلام 500 ج.م من الزميل ${p.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`
                    : `تأكيد استلام ${formatCurrency(p.currentAmount)} من الزميل ${p.employeeName ?? 'الموظف'} وإيداعها في صندوق الزمالة والتكافل؟`;
                setPaymentTarget({ id: p.id, name: p.employeeName ?? 'الموظف', msg: confirmMsg });
                setPaymentNotes('');
                setPaymentDialogOpen(true);
              }}
              title="استلام من الموظف وإيداع في صندوق الزمالة"
            >
              <Coins className="size-3 text-amber-300" aria-hidden="true" />
              <span>استلام من الموظف وإيداع بالصندوق</span>
            </button>
            {p.status === 'suspended' && (
              <button
                type="button"
                className="btn-secondary text-[11px] !min-h-0 !py-1.5 !px-2.5"
                disabled={liftSuspension.isPending}
                onClick={() => {
                  setLiftTarget({ id: p.id, name: p.employeeName ?? '' });
                  setLiftReason('');
                  setLiftDialogOpen(true);
                }}
              >
                رفع التعليق
              </button>
            )}
            {(p.status === 'pending_payment' || p.status === 'doubled') && (
              <button
                type="button"
                className="btn-secondary text-[11px] !min-h-0 !py-1.5 !px-2.5 text-[var(--danger)]"
                disabled={cancelPenalty.isPending}
                onClick={() => {
                  setCancelTarget({ id: p.id, name: p.employeeName ?? '' });
                  setCancelReason('');
                  setCancelDialogOpen(true);
                }}
              >
                <XCircle className="size-3" aria-hidden="true" />
                إلغاء
              </button>
            )}
          </div>
        );
      },
    },
  ];

  // ─── فلاتر ─────────────────────────────────────────────────────────

  const dirty = Boolean(search.trim() || statusFilter !== 'all' || selectedTier !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
    setSelectedTier('all');
  };

  // ─── إنشاء غرامة يدوية ────────────────────────────────────────────

  const submitPenalty = async (ev: FormEvent) => {
    ev.preventDefault();
    if (!employeeId) return;
    const mins = Number(lateMinutes);
    if (!Number.isFinite(mins) || mins <= 0) return;
    await generatePenalty.mutateAsync({
      employeeId,
      workDate,
      lateMinutes: mins,
    });
    setFormOpen(false);
    setEmployeeId('');
    setLateMinutes('');
    setWorkDate(cairoTodayIso());
  };

  // ─── تصدير ─────────────────────────────────────────────────────────

  const handleCsvExport = () => {
    const cols: ExportColumn<(typeof rows)[number]>[] = [
      { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
      { key: 'code', header: 'الكود', get: (p) => p.employeeCode },
      { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
      { key: 'date', header: 'التاريخ', get: (p) => p.workDate },
      { key: 'lateMinutes', header: 'التأخير (دقيقة)', get: (p) => p.lateMinutes },
      { key: 'originalAmount', header: 'الغرامة الأصلية', get: (p) => p.originalAmount },
      { key: 'currentAmount', header: 'المبلغ المطلوب', get: (p) => p.currentAmount },
      { key: 'escalation', header: 'التصعيد', get: (p) => INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel },
      { key: 'status', header: 'الحالة', get: (p) => INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status },
    ];
    downloadCsv(`instant-penalties-${cairoTodayIso()}.csv`, toCsv(cols, rows));
  };

  const handlePdfExport = () => {
    printReport(
      [
        {
          title: 'الغرامات الفورية للتأخير',
          subtitle: `${rows.length} غرامة`,
          table: {
            headers: ['الموظف', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب', 'التصعيد', 'الحالة'],
            rows: rows.map((p) => [
              p.employeeName ?? '—',
              p.departmentName ?? '—',
              p.workDate,
              p.lateMinutes + ' دقيقة',
              formatCurrency(p.originalAmount),
              formatCurrency(p.currentAmount),
              INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel,
              INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status,
            ]),
          },
        },
      ],
      'الغرامات الفورية',
    );
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="الغرامات الفورية للتأخير"
        description="الحضور يبدأ 10:00 ص — أول 15 دقيقة سماح بدون خصم. بعدها: 20 ج.م (حتى 10:30) | 50 ج.م (حتى 11:00) | 150 ج.م (حتى 12:00). عدم السداد يُضاعف لـ 500 ج.م ثم يُعلّق حسابك."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              className="btn-secondary flex items-center gap-1.5 text-xs sm:text-sm font-medium"
              onClick={async () => {
                try {
                  const res = await triggerCheck.mutateAsync();
                  setCheckFeedback(res.message);
                  setTimeout(() => setCheckFeedback(null), 8000);
                } catch (err) {
                  setCheckFeedback('حدث خطأ أثناء الفحص: ' + safeErrorMessage(err));
                }
              }}
              disabled={triggerCheck.isPending}
              title="فحص فوري وتطبيق الخصومات على من لم يبصم حتى الآن وتحديث الشرائح"
            >
              <RefreshCw className={`size-4 ${triggerCheck.isPending ? 'animate-spin text-primary' : ''}`} aria-hidden="true" />
              <span>{triggerCheck.isPending ? 'جارٍ الفحص والتطبيق...' : 'فحص وتطبيق الخصومات التلقائية الآن'}</span>
            </button>
            <button type="button" className="btn-primary" onClick={() => setFormOpen((v) => !v)} disabled={generatePenalty.isPending}>
              <Zap className="size-4" aria-hidden="true" />
              <span>إنشاء غرامة يدوياً</span>
            </button>
          </div>
        }
      />

      {/* ─── رسالة تأكيد الفحص التلقائي ────────────────────────────── */}
      {checkFeedback && (
        <div className="rounded-xl border border-blue-500/30 bg-blue-500/10 p-3.5 text-sm text-blue-800 dark:text-blue-300 flex items-center gap-2.5">
          <Sparkles className="size-4 shrink-0 text-blue-500" />
          <span className="font-medium">{checkFeedback}</span>
        </div>
      )}

      {/* ─── رابط لصندوق الزمالة والتكافل ──────────────────────────── */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-3 rounded-2xl border border-emerald-500/30 bg-gradient-to-r from-emerald-950/20 via-emerald-900/10 to-transparent p-4">
        <div className="flex items-center gap-3">
          <div className="grid size-10 place-items-center rounded-xl bg-emerald-500/20 text-emerald-400">
            <Coins className="size-5 animate-pulse text-amber-400" />
          </div>
          <div>
            <h3 className="font-bold text-sm text-[var(--text-primary)] flex items-center gap-2">
              <span>صندوق الزمالة والتكافل</span>
              <span className="text-xs font-normal text-[var(--text-muted)]">(تُورّد إليه كافة الغرامات تلقائياً)</span>
            </h3>
            <p className="text-xs text-[var(--text-muted)]">
              الرصيد المتاح حالياً بالصندوق:{' '}
              <span className="font-bold font-mono text-emerald-600 dark:text-emerald-400">
                {(fundSummary.data?.currentBalance ?? 0).toLocaleString('ar-EG')} ج.م
              </span>
            </p>
          </div>
        </div>
        <Link to="/admin/fellowship-fund" className="btn-primary text-xs flex items-center gap-1.5 bg-emerald-600 hover:bg-emerald-700 text-white">
          <HeartHandshake className="size-4" />
          <span>فتح صندوق الزمالة وسجل الحركات</span>
        </Link>
      </div>

      {/* ─── إحصائيات سريعة قابلة للنقر للدخول والتصفية ──────────────── */}
      {(stats.pendingCount > 0 || stats.suspendedCount > 0 || stats.totalOwed > 0) && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-black text-[var(--text-primary)] flex items-center gap-2">
              <Layers className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
              <span>نظرة عامة على المستحقات (انقر على أي خانة للتصفية والدخول لمحتواها)</span>
            </h2>
            {selectedTier !== 'all' && (
              <button
                type="button"
                className="text-xs text-[var(--danger)] hover:underline flex items-center gap-1 font-bold"
                onClick={() => setSelectedTier('all')}
              >
                <X className="size-3" />
                <span>إلغاء التصفية ({selectedTier})</span>
              </button>
            )}
          </div>

          <div className="grid gap-3 sm:grid-cols-3">
            {/* بطاقة المطالبين بالدفع */}
            <div
              role="button"
              tabIndex={0}
              onClick={() => setSelectedTier((prev) => (prev === 'pending' ? 'all' : 'pending'))}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'pending' ? 'all' : 'pending')); }}
              className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
                selectedTier === 'pending'
                  ? 'ring-2 ring-amber-500 ring-offset-2 dark:ring-offset-slate-900 bg-amber-50/40 dark:bg-amber-950/30 border-amber-500/50'
                  : 'hover:border-amber-500/40'
              }`}
              title="انقر لتصفية الجدول أو عرض كشف الموظفين المطالبين"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-xl bg-amber-100 dark:bg-amber-900/30 p-2.5 text-amber-600 dark:text-amber-400 group-hover:scale-110 transition-transform">
                    <AlertTriangle className="size-5" aria-hidden="true" />
                  </div>
                  <div>
                    <div className="flex items-baseline gap-2">
                      <p className="text-2xl font-black text-amber-600 dark:text-amber-400">{stats.pendingCount}</p>
                      <span className="text-xs text-[var(--text-muted)]">موظف</span>
                    </div>
                    <p className="text-xs font-bold text-[var(--text-secondary)]">موظف مطالب بالدفع</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="btn-secondary !py-1 !px-2 text-[11px] font-bold text-amber-700 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/40"
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveModalTier('pending');
                  }}
                  title="عرض تفاصيل الموظفين المطالبين بالدفع"
                >
                  <span>كشف الموظفين ↗</span>
                </button>
              </div>
              <div className="mt-2.5 flex items-center justify-between pt-2 border-t border-amber-200/50 dark:border-amber-900/40 text-[11px] text-[var(--text-muted)]">
                <span>إجمالي المستحق: <strong className="text-amber-700 dark:text-amber-300">{formatCurrency(stats.totalOwed)}</strong></span>
                <span className="text-amber-600 font-medium group-hover:underline">
                  {selectedTier === 'pending' ? '✓ التصفية نشطة' : 'انقر للتصفية ←'}
                </span>
              </div>
            </div>

            {/* بطاقة الموظفين المعلقين عن العمل */}
            <div
              role="button"
              tabIndex={0}
              onClick={() => setSelectedTier((prev) => (prev === 'suspended' ? 'all' : 'suspended'))}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'suspended' ? 'all' : 'suspended')); }}
              className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
                selectedTier === 'suspended'
                  ? 'ring-2 ring-red-500 ring-offset-2 dark:ring-offset-slate-900 bg-red-50/40 dark:bg-red-950/30 border-red-500/50'
                  : 'hover:border-red-500/40'
              }`}
              title="انقر لتصفية الجدول أو عرض تفاصيل الموظفين المعلقين"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-xl bg-red-100 dark:bg-red-900/30 p-2.5 text-red-600 dark:text-red-400 group-hover:scale-110 transition-transform">
                    <Ban className="size-5" aria-hidden="true" />
                  </div>
                  <div>
                    <div className="flex items-baseline gap-2">
                      <p className="text-2xl font-black text-red-600 dark:text-red-400">{stats.suspendedCount}</p>
                      <span className="text-xs text-[var(--text-muted)]">موظف</span>
                    </div>
                    <p className="text-xs font-bold text-[var(--text-secondary)]">موظف معلّق عن العمل (مغلق السيستم)</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="btn-secondary !py-1 !px-2 text-[11px] font-bold text-red-700 dark:text-red-300 hover:bg-red-100 dark:hover:bg-red-900/40"
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveModalTier('suspended');
                  }}
                  title="عرض تفاصيل الموظفين المعلقين"
                >
                  <span>كشف المعلقين ↗</span>
                </button>
              </div>
              <div className="mt-2.5 flex items-center justify-between pt-2 border-t border-red-200/50 dark:border-red-900/40 text-[11px] text-[var(--text-muted)]">
                <span>إيقاف الحساب تلقائياً (اليوم 3)</span>
                <span className="text-red-600 font-medium group-hover:underline">
                  {selectedTier === 'suspended' ? '✓ التصفية نشطة' : 'انقر للتصفية ←'}
                </span>
              </div>
            </div>

            {/* بطاقة إجمالي المستحق */}
            <div
              role="button"
              tabIndex={0}
              onClick={() => setActiveModalTier('total')}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setActiveModalTier('total'); }}
              className="card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 hover:border-orange-500/40"
              title="انقر لفتح ملخص وتفنيط المستحقات بالتفصيل"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-xl bg-orange-100 dark:bg-orange-900/30 p-2.5 text-orange-600 dark:text-orange-400 group-hover:scale-110 transition-transform">
                    <ShieldAlert className="size-5" aria-hidden="true" />
                  </div>
                  <div>
                    <p className="text-2xl font-black text-orange-600 dark:text-orange-400">{formatCurrency(stats.totalOwed)}</p>
                    <p className="text-xs font-bold text-[var(--text-secondary)]">إجمالي المستحق</p>
                  </div>
                </div>
                <button
                  type="button"
                  className="btn-secondary !py-1 !px-2 text-[11px] font-bold text-orange-700 dark:text-orange-300 hover:bg-orange-100 dark:hover:bg-orange-900/40"
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveModalTier('total');
                  }}
                  title="عرض تفنيط المبالغ المستحقة"
                >
                  <span>تفنيط المبالغ ↗</span>
                </button>
              </div>
              <div className="mt-2.5 flex items-center justify-between pt-2 border-t border-orange-200/50 dark:border-orange-900/40 text-[11px] text-[var(--text-muted)]">
                <span>تُورّد بالكامل لصندوق الزمالة</span>
                <span className="text-orange-600 font-medium group-hover:underline">عرض التفاصيل ↗</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ─── صناديق شرائح الغرامات (20 ج.م / 50 ج.م / 150 ج.م / 500 ج.م) ── */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-black text-[var(--text-primary)] flex items-center gap-2">
            <Coins className="size-4 text-emerald-500" aria-hidden="true" />
            <span>صناديق شرائح الغرامات والتأخير (اضغط على أي صندوق للدخول وتصفية محتواه)</span>
          </h2>
          <span className="text-xs text-[var(--text-muted)]">
            فترة السماح 10:00 - 10:15 ص (بدون خصم)
          </span>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {/* صندوق 20 ج.م */}
          <div
            role="button"
            tabIndex={0}
            onClick={() => setSelectedTier((prev) => (prev === 'tier-20' ? 'all' : 'tier-20'))}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'tier-20' ? 'all' : 'tier-20')); }}
            className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
              selectedTier === 'tier-20'
                ? 'ring-2 ring-sky-500 ring-offset-2 dark:ring-offset-slate-900 bg-sky-50/40 dark:bg-sky-950/30 border-sky-500'
                : 'border-sky-500/20 hover:border-sky-500/50 bg-gradient-to-b from-sky-500/5 to-transparent'
            }`}
            title="انقر لتصفية غرامات الـ 20 ج.م"
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-sky-100 dark:bg-sky-900/40 p-2 text-sky-600 dark:text-sky-300">
                  <Clock3 className="size-4" />
                </div>
                <div>
                  <h3 className="font-bold text-xs text-sky-900 dark:text-sky-200">صندوق غرامات 20 ج.م</h3>
                  <p className="text-[10px] text-[var(--text-muted)]">تأخير 16-30 دقيقة (10:16 - 10:30)</p>
                </div>
              </div>
              <button
                type="button"
                className="text-[11px] text-sky-600 dark:text-sky-400 hover:underline font-bold"
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveModalTier('tier-20');
                }}
              >
                تفاصيل ↗
              </button>
            </div>
            <div className="mt-3 flex items-baseline justify-between">
              <div>
                <span className="text-xl font-black text-sky-600 dark:text-sky-400">{tierStats.tier20.count}</span>
                <span className="text-xs text-[var(--text-muted)] mr-1">غرامة</span>
              </div>
              <span className="text-xs font-bold font-mono text-sky-700 dark:text-sky-300">
                {formatCurrency(tierStats.tier20.total)}
              </span>
            </div>
            <div className="mt-2 flex items-center justify-between pt-2 border-t border-sky-200/40 dark:border-sky-900/30 text-[10px] text-[var(--text-muted)]">
              <span>{tierStats.tier20.pendingCount} بانتظار التحصيل</span>
              <span className="text-sky-600 font-bold">{selectedTier === 'tier-20' ? '✓ مفعّل' : 'دخول الصندوق ←'}</span>
            </div>
          </div>

          {/* صندوق 50 ج.م */}
          <div
            role="button"
            tabIndex={0}
            onClick={() => setSelectedTier((prev) => (prev === 'tier-50' ? 'all' : 'tier-50'))}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'tier-50' ? 'all' : 'tier-50')); }}
            className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
              selectedTier === 'tier-50'
                ? 'ring-2 ring-amber-500 ring-offset-2 dark:ring-offset-slate-900 bg-amber-50/40 dark:bg-amber-950/30 border-amber-500'
                : 'border-amber-500/20 hover:border-amber-500/50 bg-gradient-to-b from-amber-500/5 to-transparent'
            }`}
            title="انقر لتصفية غرامات الـ 50 ج.م"
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-amber-100 dark:bg-amber-900/40 p-2 text-amber-600 dark:text-amber-300">
                  <SunMedium className="size-4" />
                </div>
                <div>
                  <h3 className="font-bold text-xs text-amber-900 dark:text-amber-200">صندوق غرامات 50 ج.م</h3>
                  <p className="text-[10px] text-[var(--text-muted)]">تأخير 31-60 دقيقة (10:31 - 11:00)</p>
                </div>
              </div>
              <button
                type="button"
                className="text-[11px] text-amber-600 dark:text-amber-400 hover:underline font-bold"
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveModalTier('tier-50');
                }}
              >
                تفاصيل ↗
              </button>
            </div>
            <div className="mt-3 flex items-baseline justify-between">
              <div>
                <span className="text-xl font-black text-amber-600 dark:text-amber-400">{tierStats.tier50.count}</span>
                <span className="text-xs text-[var(--text-muted)] mr-1">غرامة</span>
              </div>
              <span className="text-xs font-bold font-mono text-amber-700 dark:text-amber-300">
                {formatCurrency(tierStats.tier50.total)}
              </span>
            </div>
            <div className="mt-2 flex items-center justify-between pt-2 border-t border-amber-200/40 dark:border-amber-900/30 text-[10px] text-[var(--text-muted)]">
              <span>{tierStats.tier50.pendingCount} بانتظار التحصيل</span>
              <span className="text-amber-600 font-bold">{selectedTier === 'tier-50' ? '✓ مفعّل' : 'دخول الصندوق ←'}</span>
            </div>
          </div>

          {/* صندوق 150 ج.م */}
          <div
            role="button"
            tabIndex={0}
            onClick={() => setSelectedTier((prev) => (prev === 'tier-150' ? 'all' : 'tier-150'))}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'tier-150' ? 'all' : 'tier-150')); }}
            className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
              selectedTier === 'tier-150'
                ? 'ring-2 ring-orange-500 ring-offset-2 dark:ring-offset-slate-900 bg-orange-50/40 dark:bg-orange-950/30 border-orange-500'
                : 'border-orange-500/20 hover:border-orange-500/50 bg-gradient-to-b from-orange-500/5 to-transparent'
            }`}
            title="انقر لتصفية غرامات الـ 150 ج.م"
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-orange-100 dark:bg-orange-900/40 p-2 text-orange-600 dark:text-orange-300">
                  <Zap className="size-4" />
                </div>
                <div>
                  <h3 className="font-bold text-xs text-orange-900 dark:text-orange-200">صندوق غرامات 150 ج.م</h3>
                  <p className="text-[10px] text-[var(--text-muted)]">تأخير بعد 11:00 ص أو لم يبصم</p>
                </div>
              </div>
              <button
                type="button"
                className="text-[11px] text-orange-600 dark:text-orange-400 hover:underline font-bold"
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveModalTier('tier-150');
                }}
              >
                تفاصيل ↗
              </button>
            </div>
            <div className="mt-3 flex items-baseline justify-between">
              <div>
                <span className="text-xl font-black text-orange-600 dark:text-orange-400">{tierStats.tier150.count}</span>
                <span className="text-xs text-[var(--text-muted)] mr-1">غرامة</span>
              </div>
              <span className="text-xs font-bold font-mono text-orange-700 dark:text-orange-300">
                {formatCurrency(tierStats.tier150.total)}
              </span>
            </div>
            <div className="mt-2 flex items-center justify-between pt-2 border-t border-orange-200/40 dark:border-orange-900/30 text-[10px] text-[var(--text-muted)]">
              <span>{tierStats.tier150.pendingCount} بانتظار التحصيل</span>
              <span className="text-orange-600 font-bold">{selectedTier === 'tier-150' ? '✓ مفعّل' : 'دخول الصندوق ←'}</span>
            </div>
          </div>

          {/* صندوق 500 ج.م (المضاعفة) */}
          <div
            role="button"
            tabIndex={0}
            onClick={() => setSelectedTier((prev) => (prev === 'tier-500' ? 'all' : 'tier-500'))}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setSelectedTier((prev) => (prev === 'tier-500' ? 'all' : 'tier-500')); }}
            className={`card group relative p-4 cursor-pointer transition-all duration-200 hover:shadow-md hover:-translate-y-0.5 ${
              selectedTier === 'tier-500'
                ? 'ring-2 ring-purple-500 ring-offset-2 dark:ring-offset-slate-900 bg-purple-50/40 dark:bg-purple-950/30 border-purple-500'
                : 'border-purple-500/20 hover:border-purple-500/50 bg-gradient-to-b from-purple-500/5 to-transparent'
            }`}
            title="انقر لتصفية الغرامات المضاعفة لـ 500 ج.م"
          >
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-purple-100 dark:bg-purple-900/40 p-2 text-purple-600 dark:text-purple-300">
                  <Flame className="size-4" />
                </div>
                <div>
                  <h3 className="font-bold text-xs text-purple-900 dark:text-purple-200">غرامات مضاعفة 500 ج.م</h3>
                  <p className="text-[10px] text-[var(--text-muted)]">اليوم 2 لعدم سداد غرامة الأمس</p>
                </div>
              </div>
              <button
                type="button"
                className="text-[11px] text-purple-600 dark:text-purple-400 hover:underline font-bold"
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveModalTier('tier-500');
                }}
              >
                تفاصيل ↗
              </button>
            </div>
            <div className="mt-3 flex items-baseline justify-between">
              <div>
                <span className="text-xl font-black text-purple-600 dark:text-purple-400">{tierStats.tier500.count}</span>
                <span className="text-xs text-[var(--text-muted)] mr-1">غرامة</span>
              </div>
              <span className="text-xs font-bold font-mono text-purple-700 dark:text-purple-300">
                {formatCurrency(tierStats.tier500.total)}
              </span>
            </div>
            <div className="mt-2 flex items-center justify-between pt-2 border-t border-purple-200/40 dark:border-purple-900/30 text-[10px] text-[var(--text-muted)]">
              <span>{tierStats.tier500.pendingCount} بانتظار التحصيل</span>
              <span className="text-purple-600 font-bold">{selectedTier === 'tier-500' ? '✓ مفعّل' : 'دخول الصندوق ←'}</span>
            </div>
          </div>
        </div>
      </div>

      {/* ─── نموذج الإنشاء اليدوي ──────────────────────────────────── */}
      {formOpen && (
        <section className="card p-5">
          <h2 className="font-black">إنشاء غرامة فورية للتأخير</h2>
          <p className="mt-1 text-xs text-[var(--text-muted)]">
            الحضور يبدأ 10:00 ص: من 1-15 دقيقة = سماح بدون خصم (0 ج.م) | حتى 10:30 (16-30 دقيقة) = 20 ج.م | حتى 11:00 (31-60 دقيقة) = 50 ج.م | حتى 12:00 (61-120 دقيقة) = 150 ج.م.
          </p>
          <form className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={(ev) => void submitPenalty(ev)}>
            <label className="block">
              <span className="muted text-xs">الموظف *</span>
              <select className="input mt-1" value={employeeId} onChange={(ev) => setEmployeeId(ev.target.value)} required>
                <option value="">اختر الموظف…</option>
                {(employees ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.fullNameAr}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="muted text-xs">تاريخ التأخير *</span>
              <input className="input mt-1" type="date" value={workDate} onChange={(ev) => setWorkDate(ev.target.value)} required />
            </label>
            <label className="block">
              <span className="muted text-xs">دقائق التأخير *</span>
              <input
                className="input mt-1"
                type="number"
                min="1"
                max="480"
                step="1"
                value={lateMinutes}
                onChange={(ev) => setLateMinutes(ev.target.value)}
                placeholder="25"
                required
              />
              {Number(lateMinutes) > 0 && (
                <span className={`mt-1 block text-[11px] font-bold ${Number(lateMinutes) <= 15 ? 'text-emerald-600' : 'text-amber-600'}`}>
                  {Number(lateMinutes) <= 15
                    ? '✓ فترة سماح (10:00 - 10:15) — بدون أي خصم (0 ج.م)'
                    : Number(lateMinutes) <= 30
                      ? 'خصم 20 ج.م (حضور حتى 10:30)'
                      : Number(lateMinutes) <= 60
                        ? 'خصم 50 ج.م (حضور حتى 11:00)'
                        : 'خصم 150 ج.م (حضور حتى 12:00)'}
                </span>
              )}
            </label>
            <div className="flex items-end gap-2">
              <button
                type="submit"
                className="btn-primary"
                disabled={generatePenalty.isPending || !employeeId || !(Number(lateMinutes) > 0)}
              >
                {generatePenalty.isPending ? 'جارٍ الحفظ…' : 'تسجيل الغرامة'}
              </button>
              <button type="button" className="btn-secondary" onClick={() => setFormOpen(false)}>
                إلغاء
              </button>
            </div>
            {generatePenalty.isError && <p className="text-sm text-[var(--danger)] sm:col-span-2 lg:col-span-4">{safeErrorMessage(generatePenalty.error)}</p>}
          </form>
        </section>
      )}

      {/* ─── الموظفين المعلقين ──────────────────────────────────────── */}
      {(pendingEmployees.data ?? []).some((e) => e.isSuspended) && (
        <section className="card border-2 border-red-500/30 bg-red-50/50 dark:bg-red-950/20 p-4">
          <div className="flex items-center justify-between">
            <h3 className="flex items-center gap-2 font-black text-red-700 dark:text-red-400">
              <Ban className="size-4" aria-hidden="true" />
              موظفون موقوفون عن العمل — Day 3
            </h3>
            <span className="text-xs font-bold text-red-600 dark:text-red-400">تم إشعار الفريق</span>
          </div>
          <p className="mt-1 text-xs text-red-600 dark:text-red-400/80">
            حسابات مغلقة لعدم سداد 500 ج.م — لا يمكن تسجيل الدخول حتى السداد للـ HR.
          </p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {(pendingEmployees.data ?? [])
              .filter((e) => e.isSuspended)
              .map((e) => (
                <div key={e.employeeId} className="flex items-center justify-between rounded-lg bg-white dark:bg-gray-900/60 p-3 shadow-sm border border-red-200 dark:border-red-900/30">
                  <div>
                    <p className="font-bold text-red-700 dark:text-red-400">{e.employeeName ?? '—'}</p>
                    <p className="text-xs text-[var(--text-muted)]">{e.departmentName ?? '—'}</p>
                  </div>
                  <div className="text-end">
                    <span className="font-black text-red-600 dark:text-red-400 block">{formatCurrency(e.totalAmount)}</span>
                    <span className="text-[10px] text-red-500 dark:text-red-400/70 font-bold">معلّق</span>
                  </div>
                </div>
              ))}
          </div>
        </section>
      )}

      {/* ─── شريط التصفية النشطة حسب الصندوق ───────────────────────── */}
      {selectedTier !== 'all' && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-primary/30 bg-primary/5 px-4 py-2.5 text-xs">
          <div className="flex items-center gap-2">
            <span className="font-bold text-[var(--text-primary)]">تصفية نشطة حسب الصندوق:</span>
            <span className="inline-flex items-center gap-1 rounded-full bg-primary/15 px-2.5 py-0.5 font-black text-primary">
              {selectedTier === 'pending' && 'المطالبون بالدفع حالياً'}
              {selectedTier === 'suspended' && 'المعلّقون عن العمل (Day 3)'}
              {selectedTier === 'tier-20' && 'صندوق غرامات 20 ج.م (16-30 دقيقة تأخير)'}
              {selectedTier === 'tier-50' && 'صندوق غرامات 50 ج.م (31-60 دقيقة تأخير)'}
              {selectedTier === 'tier-150' && 'صندوق غرامات 150 ج.م (تأخير بعد 11:00 ص / عدم بصمة)'}
              {selectedTier === 'tier-500' && 'صندوق الغرامات المضاعفة 500 ج.م (اليوم الثاني)'}
            </span>
            <span className="text-[var(--text-muted)] font-mono">({rows.length} غرامة مطابقة)</span>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="font-bold text-primary hover:underline"
              onClick={() => setActiveModalTier(selectedTier)}
            >
              عرض الكشف التفصيلي الكامل للمحتوى ↗
            </button>
            <button
              type="button"
              className="rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 px-2.5 py-1 font-bold text-[var(--text-secondary)] hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => setSelectedTier('all')}
            >
              إلغاء التصفية ✕
            </button>
          </div>
        </div>
      )}

      {/* ─── شريط الفلاتر ──────────────────────────────────────────── */}
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالموظف أو الإدارة…"
        resultText={`عرض ${rows.length} من ${penalties.data?.length ?? 0}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {Object.entries(INSTANT_PENALTY_STATUS_LABELS).map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
        <button type="button" className="btn-secondary" onClick={handleCsvExport} disabled={rows.length === 0} title="تصدير Excel (CSV)">
          <FileSpreadsheet className="size-4" aria-hidden="true" />
          تصدير
        </button>
        <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
          <Printer className="size-4" aria-hidden="true" />
          PDF
        </button>
      </FilterBar>

      {/* ─── الجدول الرئيسي ────────────────────────────────────────── */}
      {penalties.isError ? (
        <ErrorState description={safeErrorMessage(penalties.error)} onRetry={() => void penalties.refetch()} />
      ) : penalties.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل الغرامات الفورية…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد غرامات فورية" description="لم تُسجل أي غرامات فورية للتأخير بعد." />
      ) : (
        <DataTable
          ariaLabel="جدول الغرامات الفورية للتأخير"
          rowKey={(p) => p.id}
          data={rows}
          minWidth="800px"
          columns={columns}
          emptyTitle="لا توجد نتائج"
          emptyDescription="جرّب تعديل البحث أو الحالة."
        />
      )}

      {/* ─── نافذة التفاصيل الشاملة للفئة / الصندوق ───────────────────────── */}
      {activeModalTier && (
        <DialogOverlay
          title={
            activeModalTier === 'pending'
              ? 'كشف الموظفين المطالبين بالدفع حالياً'
              : activeModalTier === 'suspended'
                ? 'كشف الموظفين الموقوفين عن العمل (Day 3)'
                : activeModalTier === 'total'
                  ? 'البيان الشامل وتفنيط الغرامات الفورية'
                  : activeModalTier === 'tier-20'
                    ? 'صندوق غرامات 20 ج.م (تأخير 16-30 دقيقة)'
                    : activeModalTier === 'tier-50'
                      ? 'صندوق غرامات 50 ج.م (تأخير 31-60 دقيقة)'
                      : activeModalTier === 'tier-150'
                        ? 'صندوق غرامات 150 ج.م (تأخير بعد 11:00 ص أو عدم البصمة)'
                        : 'صندوق الغرامات المضاعفة 500 ج.م (اليوم الثاني)'
          }
          onClose={() => setActiveModalTier(null)}
          maxWidth="max-w-4xl"
        >
          <div className="space-y-4 max-h-[75vh] overflow-y-auto px-1">
            {/* 1. كشف المطالبين بالدفع */}
            {activeModalTier === 'pending' && (
              <div className="space-y-4">
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                  <div className="rounded-xl bg-amber-500/10 border border-amber-500/20 p-3 text-center">
                    <span className="text-xs text-[var(--text-muted)] block">إجمالي المطالبين</span>
                    <span className="text-xl font-black text-amber-600 dark:text-amber-400">{pendingEmployees.data?.length ?? 0}</span>
                    <span className="text-[11px] text-[var(--text-muted)] mr-1">موظف</span>
                  </div>
                  <div className="rounded-xl bg-orange-500/10 border border-orange-500/20 p-3 text-center">
                    <span className="text-xs text-[var(--text-muted)] block">إجمالي المبالغ المطلوبة</span>
                    <span className="text-xl font-black text-orange-600 dark:text-orange-400 font-mono">{formatCurrency(stats.totalOwed)}</span>
                  </div>
                  <div className="rounded-xl bg-red-500/10 border border-red-500/20 p-3 text-center col-span-2 sm:col-span-1">
                    <span className="text-xs text-[var(--text-muted)] block">المعلقون عن العمل</span>
                    <span className="text-xl font-black text-red-600 dark:text-red-400">{stats.suspendedCount}</span>
                    <span className="text-[11px] text-[var(--text-muted)] mr-1">موظف</span>
                  </div>
                </div>

                <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
                  <table className="w-full text-start text-xs">
                    <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                      <tr>
                        <th className="p-3 text-start">الموظف</th>
                        <th className="p-3 text-start">الإدارة</th>
                        <th className="p-3 text-center">عدد الغرامات</th>
                        <th className="p-3 text-end">إجمالي المبلغ</th>
                        <th className="p-3 text-center">حالة الحساب</th>
                        <th className="p-3 text-center">إجراء سريع</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border-subtle)]">
                      {(pendingEmployees.data ?? []).length === 0 ? (
                        <tr>
                          <td colSpan={6} className="p-6 text-center text-[var(--text-muted)]">
                            لا يوجد أي موظف مطالب بالدفع حالياً! 🎉
                          </td>
                        </tr>
                      ) : (
                        (pendingEmployees.data ?? []).map((e) => {
                          const firstPenalty = (penalties.data ?? []).find(
                            (p) => p.employeeId === e.employeeId && (p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended')
                          );
                          return (
                            <tr key={e.employeeId} className="hover:bg-[var(--surface-hover)] transition-colors">
                              <td className="p-3">
                                <p className="font-bold text-[var(--text-primary)]">{e.employeeName ?? '—'}</p>
                                <p className="text-[10px] text-[var(--text-muted)] font-mono">{e.employeeCode ?? '—'}</p>
                              </td>
                              <td className="p-3 text-[var(--text-secondary)]">{e.departmentName ?? '—'}</td>
                              <td className="p-3 text-center font-bold font-mono text-amber-600">{e.pendingCount}</td>
                              <td className="p-3 text-end font-black font-mono text-[var(--text-primary)]">{formatCurrency(e.totalAmount)}</td>
                              <td className="p-3 text-center">
                                {e.isSuspended ? (
                                  <span className="inline-flex items-center gap-1 rounded-full bg-red-100 dark:bg-red-950/60 px-2 py-0.5 text-[10px] font-bold text-red-700 dark:text-red-300 border border-red-300 dark:border-red-800">
                                    <Ban className="size-3" /> معلّق
                                  </span>
                                ) : (
                                  <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 dark:bg-amber-950/60 px-2 py-0.5 text-[10px] font-bold text-amber-700 dark:text-amber-300 border border-amber-300 dark:border-amber-800">
                                    <Clock className="size-3" /> مطالب بالسداد
                                  </span>
                                )}
                              </td>
                              <td className="p-3 text-center">
                                <div className="flex items-center justify-center gap-1.5">
                                  {firstPenalty && (
                                    <button
                                      type="button"
                                      className="btn-primary !py-1 !px-2 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold"
                                      onClick={() => {
                                        setActiveModalTier(null);
                                        const confirmMsg = firstPenalty.status === 'suspended'
                                          ? `هل تم استلام 500 ج.م من الزميل ${firstPenalty.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`
                                          : `تأكيد استلام ${formatCurrency(firstPenalty.currentAmount)} من الزميل ${firstPenalty.employeeName ?? 'الموظف'} وإيداعها في صندوق الزمالة والتكافل؟`;
                                        setPaymentTarget({ id: firstPenalty.id, name: firstPenalty.employeeName ?? '', msg: confirmMsg });
                                        setPaymentNotes('');
                                        setPaymentDialogOpen(true);
                                      }}
                                      title="استلام وإيداع بالصندوق"
                                    >
                                      <Coins className="size-3 text-amber-300" />
                                      <span>إيداع بالصندوق</span>
                                    </button>
                                  )}
                                  <button
                                    type="button"
                                    className="btn-secondary !py-1 !px-2 text-[11px]"
                                    onClick={() => {
                                      setSearch(e.employeeName ?? '');
                                      setSelectedTier('all');
                                      setActiveModalTier(null);
                                    }}
                                    title="تصفية غرامات هذا الموظف في الجدول الرئيسي"
                                  >
                                    عرض غراماته
                                  </button>
                                </div>
                              </td>
                            </tr>
                          );
                        })
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* 2. كشف المعلقين عن العمل */}
            {activeModalTier === 'suspended' && (
              <div className="space-y-4">
                <div className="rounded-xl border border-red-500/30 bg-red-50/60 dark:bg-red-950/30 p-3.5 text-xs text-red-800 dark:text-red-300">
                  <p className="font-bold flex items-center gap-1.5">
                    <Ban className="size-4 text-red-600" />
                    تنبيه إيقاف الحسابات ومباشرة العمل (Day 3):
                  </p>
                  <p className="mt-1">
                    تم إيقاف حسابات هؤلاء الزملاء برمجياً بسبب عدم سداد غرامة الـ 500 ج.م المضاعفة. لا يمكنهم تسجيل الدخول على المنظومة حتى يتم استلام المبلغ وتوريده لصندوق الزمالة والتكافل.
                  </p>
                </div>

                <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
                  <table className="w-full text-start text-xs">
                    <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                      <tr>
                        <th className="p-3 text-start">الموظف</th>
                        <th className="p-3 text-start">الإدارة</th>
                        <th className="p-3 text-center">عدد الغرامات</th>
                        <th className="p-3 text-end">إجمالي المبلغ</th>
                        <th className="p-3 text-center">الإجراءات المتاحة</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border-subtle)]">
                      {(pendingEmployees.data ?? []).filter((e) => e.isSuspended).length === 0 ? (
                        <tr>
                          <td colSpan={5} className="p-6 text-center text-[var(--text-muted)]">
                            الحمد لله، لا يوجد أي موظف معلّق عن العمل حالياً! ✨
                          </td>
                        </tr>
                      ) : (
                        (pendingEmployees.data ?? [])
                          .filter((e) => e.isSuspended)
                          .map((e) => {
                            const suspendedPenalty = (penalties.data ?? []).find(
                              (p) => p.employeeId === e.employeeId && p.status === 'suspended'
                            );
                            return (
                              <tr key={e.employeeId} className="hover:bg-[var(--surface-hover)] transition-colors">
                                <td className="p-3">
                                  <p className="font-bold text-red-700 dark:text-red-400">{e.employeeName ?? '—'}</p>
                                  <p className="text-[10px] text-[var(--text-muted)] font-mono">{e.employeeCode ?? '—'}</p>
                                </td>
                                <td className="p-3 text-[var(--text-secondary)]">{e.departmentName ?? '—'}</td>
                                <td className="p-3 text-center font-bold font-mono text-red-600">{e.pendingCount}</td>
                                <td className="p-3 text-end font-black font-mono text-red-600">{formatCurrency(e.totalAmount)}</td>
                                <td className="p-3 text-center">
                                  <div className="flex items-center justify-center gap-1.5">
                                    {suspendedPenalty && (
                                      <button
                                        type="button"
                                        className="btn-primary !py-1 !px-2.5 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold"
                                        onClick={() => {
                                          setActiveModalTier(null);
                                          setPaymentTarget({
                                            id: suspendedPenalty.id,
                                            name: suspendedPenalty.employeeName ?? 'الموظف',
                                            msg: `هل تم استلام 500 ج.م من الزميل ${suspendedPenalty.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`,
                                          });
                                          setPaymentNotes('');
                                          setPaymentDialogOpen(true);
                                        }}
                                      >
                                        <Coins className="size-3 text-amber-300" />
                                        <span>استلام 500 ج.م وإيداع بالصندوق</span>
                                      </button>
                                    )}
                                    {suspendedPenalty && (
                                      <button
                                        type="button"
                                        className="btn-secondary !py-1 !px-2 text-[11px]"
                                        onClick={() => {
                                          setActiveModalTier(null);
                                          setLiftTarget({ id: suspendedPenalty.id, name: suspendedPenalty.employeeName ?? '' });
                                          setLiftReason('');
                                          setLiftDialogOpen(true);
                                        }}
                                      >
                                        رفع التعليق يدوياً
                                      </button>
                                    )}
                                  </div>
                                </td>
                              </tr>
                            );
                          })
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* 3. تفنيط المبالغ الشامل (total) */}
            {activeModalTier === 'total' && (
              <div className="space-y-4">
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  {/* 20 ج.م */}
                  <div className="rounded-xl border border-sky-500/30 bg-sky-50/40 dark:bg-sky-950/20 p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-sky-700 dark:text-sky-300">شريحة 20 ج.م</span>
                      <span className="text-[10px] bg-sky-100 dark:bg-sky-900/50 text-sky-700 dark:text-sky-300 px-1.5 py-0.5 rounded font-mono">16-30 د</span>
                    </div>
                    <p className="mt-2 text-xl font-black text-sky-600 dark:text-sky-400 font-mono">{formatCurrency(tierStats.tier20.total)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] mt-1 flex justify-between">
                      <span>العدد: {tierStats.tier20.count}</span>
                      <span className="text-amber-600 font-bold">{tierStats.tier20.pendingCount} معلق</span>
                    </p>
                  </div>

                  {/* 50 ج.م */}
                  <div className="rounded-xl border border-amber-500/30 bg-amber-50/40 dark:bg-amber-950/20 p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-amber-700 dark:text-amber-300">شريحة 50 ج.م</span>
                      <span className="text-[10px] bg-amber-100 dark:bg-amber-900/50 text-amber-700 dark:text-amber-300 px-1.5 py-0.5 rounded font-mono">31-60 د</span>
                    </div>
                    <p className="mt-2 text-xl font-black text-amber-600 dark:text-amber-400 font-mono">{formatCurrency(tierStats.tier50.total)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] mt-1 flex justify-between">
                      <span>العدد: {tierStats.tier50.count}</span>
                      <span className="text-amber-600 font-bold">{tierStats.tier50.pendingCount} معلق</span>
                    </p>
                  </div>

                  {/* 150 ج.م */}
                  <div className="rounded-xl border border-orange-500/30 bg-orange-50/40 dark:bg-orange-950/20 p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-orange-700 dark:text-orange-300">شريحة 150 ج.م</span>
                      <span className="text-[10px] bg-orange-100 dark:bg-orange-900/50 text-orange-700 dark:text-orange-300 px-1.5 py-0.5 rounded font-mono">&gt;11:00ص</span>
                    </div>
                    <p className="mt-2 text-xl font-black text-orange-600 dark:text-orange-400 font-mono">{formatCurrency(tierStats.tier150.total)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] mt-1 flex justify-between">
                      <span>العدد: {tierStats.tier150.count}</span>
                      <span className="text-amber-600 font-bold">{tierStats.tier150.pendingCount} معلق</span>
                    </p>
                  </div>

                  {/* 500 ج.م */}
                  <div className="rounded-xl border border-purple-500/30 bg-purple-50/40 dark:bg-purple-950/20 p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-purple-700 dark:text-purple-300">مضاعفة 500 ج.م</span>
                      <span className="text-[10px] bg-purple-100 dark:bg-purple-900/50 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 rounded font-mono">Day 2</span>
                    </div>
                    <p className="mt-2 text-xl font-black text-purple-600 dark:text-purple-400 font-mono">{formatCurrency(tierStats.tier500.total)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] mt-1 flex justify-between">
                      <span>العدد: {tierStats.tier500.count}</span>
                      <span className="text-amber-600 font-bold">{tierStats.tier500.pendingCount} معلق</span>
                    </p>
                  </div>
                </div>

                <div className="flex flex-col sm:flex-row items-center justify-between gap-3 rounded-xl border border-emerald-500/30 bg-emerald-50/50 dark:bg-emerald-950/20 p-4">
                  <div>
                    <h4 className="font-bold text-sm text-emerald-800 dark:text-emerald-300">صندوق الزمالة والتكافل</h4>
                    <p className="text-xs text-[var(--text-muted)] mt-0.5">
                      كل جنيه يتم تحصيله من هذه الغرامات يُودع مباشرة في الصندوق لصالح الفريق، وله سجل حركات كامل ومتاح لجميع الموظفين.
                    </p>
                  </div>
                  <Link
                    to="/fellowship-fund"
                    className="btn-primary !py-2 !px-4 text-xs font-bold whitespace-nowrap bg-emerald-600 hover:bg-emerald-700"
                    onClick={() => setActiveModalTier(null)}
                  >
                    فتح صندوق الزمالة ↗
                  </Link>
                </div>
              </div>
            )}

            {/* 4. تفاصيل الشرائح المحددة (20 / 50 / 150 / 500) */}
            {(activeModalTier === 'tier-20' || activeModalTier === 'tier-50' || activeModalTier === 'tier-150' || activeModalTier === 'tier-500') && (() => {
              const tierConfig =
                activeModalTier === 'tier-20'
                  ? { label: 'غرامات 20 ج.م', desc: 'الحضور من 10:16 ص إلى 10:30 ص (تأخير 16-30 دقيقة)', stats: tierStats.tier20, color: 'text-sky-600 dark:text-sky-400' }
                  : activeModalTier === 'tier-50'
                    ? { label: 'غرامات 50 ج.م', desc: 'الحضور من 10:31 ص إلى 11:00 ص (تأخير 31-60 دقيقة)', stats: tierStats.tier50, color: 'text-amber-600 dark:text-amber-400' }
                    : activeModalTier === 'tier-150'
                      ? { label: 'غرامات 150 ج.م', desc: 'الحضور بعد 11:00 ص أو عدم تسجيل البصمة', stats: tierStats.tier150, color: 'text-orange-600 dark:text-orange-400' }
                      : { label: 'غرامات مضاعفة 500 ج.م', desc: 'عدم سداد غرامة اليوم السابق حتى 10:00 ص اليوم التالي', stats: tierStats.tier500, color: 'text-purple-600 dark:text-purple-400' };

              return (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)] p-3 text-center">
                      <span className="text-xs text-[var(--text-muted)] block">إجمالي الغرامات</span>
                      <span className="text-lg font-black text-[var(--text-primary)] font-mono">{tierConfig.stats.count}</span>
                    </div>
                    <div className="rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)] p-3 text-center">
                      <span className="text-xs text-[var(--text-muted)] block">إجمالي القيمة</span>
                      <span className={`text-lg font-black font-mono ${tierConfig.color}`}>{formatCurrency(tierConfig.stats.total)}</span>
                    </div>
                    <div className="rounded-xl bg-amber-500/10 border border-amber-500/20 p-3 text-center">
                      <span className="text-xs text-amber-700 dark:text-amber-300 block">بانتظار التحصيل</span>
                      <span className="text-lg font-black text-amber-600 dark:text-amber-400 font-mono">{tierConfig.stats.pendingCount}</span>
                    </div>
                    <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/20 p-3 text-center">
                      <span className="text-xs text-emerald-700 dark:text-emerald-300 block">مُورّدة بالصندوق</span>
                      <span className="text-lg font-black text-emerald-600 dark:text-emerald-400 font-mono">{tierConfig.stats.count - tierConfig.stats.pendingCount}</span>
                    </div>
                  </div>

                  <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
                    <table className="w-full text-start text-xs">
                      <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                        <tr>
                          <th className="p-3 text-start">الموظف</th>
                          <th className="p-3 text-start">الإدارة</th>
                          <th className="p-3 text-start">تاريخ التأخير</th>
                          <th className="p-3 text-center">التأخير</th>
                          <th className="p-3 text-end">المطلوب</th>
                          <th className="p-3 text-center">الحالة</th>
                          <th className="p-3 text-center">إجراء سريع</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[var(--border-subtle)]">
                        {tierConfig.stats.items.length === 0 ? (
                          <tr>
                            <td colSpan={7} className="p-6 text-center text-[var(--text-muted)]">
                              لا توجد أي غرامات مسجلة في هذه الشريحة حالياً.
                            </td>
                          </tr>
                        ) : (
                          tierConfig.stats.items.map((p) => {
                            const isPending = p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended';
                            return (
                              <tr key={p.id} className="hover:bg-[var(--surface-hover)] transition-colors">
                                <td className="p-3 font-bold text-[var(--text-primary)]">
                                  {p.employeeName ?? '—'}
                                  {p.employeeCode && <span className="block text-[10px] text-[var(--text-muted)] font-mono">{p.employeeCode}</span>}
                                </td>
                                <td className="p-3 text-[var(--text-secondary)]">{p.departmentName ?? '—'}</td>
                                <td className="p-3 font-mono text-[var(--text-muted)]">{p.workDate}</td>
                                <td className="p-3 text-center">
                                  <span className="font-bold text-amber-600">{p.lateMinutes} د</span>
                                </td>
                                <td className="p-3 text-end font-black font-mono text-[var(--text-primary)]">{formatCurrency(p.currentAmount)}</td>
                                <td className="p-3 text-center">
                                  <StatusBadge status={p.status} label={INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status} />
                                </td>
                                <td className="p-3 text-center">
                                  {isPending ? (
                                    <button
                                      type="button"
                                      className="btn-primary !py-1 !px-2.5 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold whitespace-nowrap"
                                      onClick={() => {
                                        setActiveModalTier(null);
                                        const confirmMsg = p.status === 'suspended'
                                          ? `هل تم استلام 500 ج.م من الزميل ${p.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`
                                          : `تأكيد استلام ${formatCurrency(p.currentAmount)} من الزميل ${p.employeeName ?? 'الموظف'} وإيداعها في صندوق الزمالة والتكافل؟`;
                                        setPaymentTarget({ id: p.id, name: p.employeeName ?? '', msg: confirmMsg });
                                        setPaymentNotes('');
                                        setPaymentDialogOpen(true);
                                      }}
                                    >
                                      <Coins className="size-3 text-amber-300" />
                                      <span>إيداع بالصندوق</span>
                                    </button>
                                  ) : p.status === 'paid' ? (
                                    <span className="text-[11px] text-emerald-600 font-bold">✓ تم الإيداع</span>
                                  ) : (
                                    <span className="text-[11px] text-gray-400">ملغاة</span>
                                  )}
                                </td>
                              </tr>
                            );
                          })
                        )}
                      </tbody>
                    </table>
                  </div>

                  {/* أزرار أسفل المودال */}
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
                    <button
                      type="button"
                      className="btn-secondary text-xs flex items-center gap-1.5"
                      onClick={() => {
                        const cols: ExportColumn<(typeof tierConfig.stats.items)[number]>[] = [
                          { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
                          { key: 'code', header: 'الكود', get: (p) => p.employeeCode },
                          { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
                          { key: 'date', header: 'التاريخ', get: (p) => p.workDate },
                          { key: 'lateMinutes', header: 'التأخير (دقيقة)', get: (p) => p.lateMinutes },
                          { key: 'amount', header: 'المبلغ', get: (p) => p.currentAmount },
                          { key: 'status', header: 'الحالة', get: (p) => INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status },
                        ];
                        downloadCsv(`penalties-${activeModalTier}-${cairoTodayIso()}.csv`, toCsv(cols, tierConfig.stats.items));
                      }}
                      disabled={tierConfig.stats.items.length === 0}
                    >
                      <FileSpreadsheet className="size-4" />
                      <span>تصدير هذه الشريحة Excel</span>
                    </button>

                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        className="btn-primary !py-1.5 !px-3 text-xs"
                        onClick={() => {
                          setSelectedTier(activeModalTier);
                          setActiveModalTier(null);
                        }}
                      >
                        تصفية الجدول الرئيسي بهذه الشريحة ←
                      </button>
                      <button
                        type="button"
                        className="btn-secondary !py-1.5 !px-3 text-xs"
                        onClick={() => setActiveModalTier(null)}
                      >
                        إغلاق
                      </button>
                    </div>
                  </div>
                </div>
              );
            })()}
          </div>
        </DialogOverlay>
      )}

      <InputDialog
        open={paymentDialogOpen}
        title="استلام الغرامة وإيداعها في صندوق الزمالة والتكافل"
        message={paymentTarget?.msg ?? ''}
        inputLabel="ملاحظات الاستلام والإيداع (اختياري)"
        inputPlaceholder="أي تفاصيل أو ملاحظات إضافية…"
        inputValue={paymentNotes}
        onInputChange={setPaymentNotes}
        confirmLabel="تأكيد الاستلام والإيداع بالصندوق"
        tone="info"
        required={false}
        loading={confirmPayment.isPending}
        error={confirmPayment.isError ? safeErrorMessage(confirmPayment.error) : null}
        onConfirm={async () => {
          if (paymentTarget) {
            try {
              await confirmPayment.mutateAsync({ penaltyId: paymentTarget.id, notes: paymentNotes.trim() || undefined });
              setPaymentDialogOpen(false);
              setPaymentTarget(null);
              setPaymentNotes('');
            } catch {
              // Error is displayed inside InputDialog
            }
          }
        }}
        onCancel={() => {
          confirmPayment.reset();
          setPaymentDialogOpen(false);
          setPaymentTarget(null);
          setPaymentNotes('');
        }}
      />

      <InputDialog
        open={liftDialogOpen}
        title="رفع التعليق يدوياً"
        message={`هل تريد رفع التعليق عن ${liftTarget?.name ?? ''} بدون سداد؟ اذكر السبب:`}
        inputLabel="سبب رفع التعليق"
        inputPlaceholder="سبب رفع التعليق…"
        inputValue={liftReason}
        onInputChange={setLiftReason}
        confirmLabel="رفع التعليق"
        tone="warning"
        loading={liftSuspension.isPending}
        error={liftSuspension.isError ? safeErrorMessage(liftSuspension.error) : null}
        onConfirm={async () => {
          if (liftTarget && liftReason.trim()) {
            try {
              await liftSuspension.mutateAsync({ penaltyId: liftTarget.id, notes: liftReason.trim() });
              setLiftDialogOpen(false);
              setLiftTarget(null);
              setLiftReason('');
            } catch {
              // Error is displayed inside InputDialog
            }
          }
        }}
        onCancel={() => {
          liftSuspension.reset();
          setLiftDialogOpen(false);
          setLiftTarget(null);
          setLiftReason('');
        }}
      />

      <InputDialog
        open={cancelDialogOpen}
        title="إلغاء غرامة"
        message={`إلغاء غرامة ${cancelTarget?.name ?? ''} — اذكر السبب:`}
        inputLabel="سبب الإلغاء"
        inputPlaceholder="سبب الإلغاء…"
        inputValue={cancelReason}
        onInputChange={setCancelReason}
        confirmLabel="إلغاء الغرامة"
        tone="danger"
        loading={cancelPenalty.isPending}
        error={cancelPenalty.isError ? safeErrorMessage(cancelPenalty.error) : null}
        onConfirm={async () => {
          if (cancelTarget && cancelReason.trim()) {
            try {
              await cancelPenalty.mutateAsync({ penaltyId: cancelTarget.id, reason: cancelReason.trim() });
              setCancelDialogOpen(false);
              setCancelTarget(null);
              setCancelReason('');
            } catch {
              // Error is displayed inside InputDialog
            }
          }
        }}
        onCancel={() => {
          cancelPenalty.reset();
          setCancelDialogOpen(false);
          setCancelTarget(null);
          setCancelReason('');
        }}
      />
    </div>
  );
}
