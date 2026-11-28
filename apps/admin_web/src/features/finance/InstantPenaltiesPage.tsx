import { ArabicDateInput } from '../../ui/ArabicDateInput';
import { cairoTodayIso } from '../../core/cairoTime';
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { useLocation } from 'react-router';
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  Clock3,
  Coins,
  Download,
  FileSpreadsheet,
  Flame,
  MessageCircle,
  Printer,
  RefreshCw,
  RotateCcw,
  ShieldAlert,
  Sparkles,
  SunMedium,
  Timer,
  Zap,
} from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { useEntityFocus } from '../../core/useEntityFocus';
import { openWhatsApp } from '../../core/whatsappShare';
import { DataTable } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { useToast } from '../../ui/Toast';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useEmployees } from '../employees/useEmployees';
import { useFellowshipFundSummary, useResetExperimentalPayments } from './useFellowshipFund';
import { usePenaltyDisputes, useReviewPenaltyDispute } from './usePenaltyDisputes';
import {
  useCancelInstantPenalty,
  useConfirmInstantPenaltyPayment,
  useGenerateInstantPenalty,
  useInstantPenalties,
  useLiftInstantPenaltySuspension,
  useRevertDoubledPenalty,
  usePendingPenaltyEmployees,
  useTriggerCheckPenaltiesNow,
  useBulkConfirmPenaltyPayments,
  useBulkCancelPenalties,
  useDailyOvertimeSummary,
  type InstantPenalty,
} from './useInstantPenalties';
import {
  buildWeeklyWhatsAppSummaryText,
  formatCurrency,
  generateEmployeePenaltyWhatsAppText,
  getYesterdayIso,
} from './instantPenalties/penaltyFormatters';
import {
  exportModalTierPdf,
  exportPenaltiesCsv,
  exportPenaltiesHtml,
  exportPenaltiesPdf,
} from './instantPenalties/penaltyExports';
import { PenaltyDisputesAndDialogs } from './instantPenalties/PenaltyDisputesAndDialogs';
import {
  DisputeReviewModal,
  EarlyWarningRadarModal,
  OvertimeSummaryModal,
  ResetExperimentalModal,
} from './instantPenalties/PenaltySecondaryModals';
import { buildPenaltyColumns } from './instantPenalties/PenaltyTableColumns';
import {
  PenaltyTierDetailModal,
  type ModalTier,
  type SelectedTier,
} from './instantPenalties/PenaltyTierDetailModal';
import { PenaltyWhatsAppModal } from './instantPenalties/PenaltyWhatsAppModal';

export function InstantPenaltiesPage() {
  const { toast } = useToast();
  const { pathname } = useLocation();
  const fellowshipFundPath = pathname.startsWith('/hr') ? '/hr/fellowship-fund' : '/admin/fellowship-fund';
  const [search, setSearch] = useState('');
  const [dateFilterMode, setDateFilterMode] = useState<'today' | 'yesterday' | 'specific' | 'all'>('today');
  const [specificDate, setSpecificDate] = useState<string>(cairoTodayIso());
  const [statusFilter, setStatusFilter] = useState<'unpaid' | 'all' | 'pending_payment' | 'doubled' | 'suspended' | 'paid' | 'cancelled'>('unpaid');
  const [selectedTier, setSelectedTier] = useState<SelectedTier>('all');
  const [activeModalTier, setActiveModalTier] = useState<ModalTier | null>(null);

  const penalties = useInstantPenalties();
  const pendingEmployees = usePendingPenaltyEmployees();
  const fundSummary = useFellowshipFundSummary();
  const resetExperimentalPayments = useResetExperimentalPayments();
  const auth = useAuth();
  const [resetDialogOpen, setResetDialogOpen] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);

  const canResetExperimental = Boolean(
    auth.access &&
    (hasPermission(auth.access, 'payroll.run.manage') ||
      hasPermission(auth.access, 'finance.manage') ||
      auth.access.workspaces?.includes('main_admin') ||
      auth.access.permissions?.includes('*')),
  );

  const confirmPayment = useConfirmInstantPenaltyPayment();
  const generatePenalty = useGenerateInstantPenalty();
  const cancelPenalty = useCancelInstantPenalty();
  const liftSuspension = useLiftInstantPenaltySuspension();
  const revertPenalty = useRevertDoubledPenalty();
  const triggerCheck = useTriggerCheckPenaltiesNow();
  const { data: employees } = useEmployees();

  const employeePhotoMap = useMemo(() => {
    const map = new Map<string, string | null>();
    for (const emp of employees ?? []) {
      map.set(emp.id, emp.photoUrl ?? null);
    }
    return map;
  }, [employees]);

  const [checkFeedback, setCheckFeedback] = useState<string | null>(null);
  const checkFeedbackTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (checkFeedbackTimer.current) clearTimeout(checkFeedbackTimer.current);
    };
  }, []);

  const [formOpen, setFormOpen] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [lateMinutes, setLateMinutes] = useState('');
  const [workDate, setWorkDate] = useState(cairoTodayIso());
  const [formFeedback, setFormFeedback] = useState<string | null>(null);

  const [paymentDialogOpen, setPaymentDialogOpen] = useState(false);
  const [paymentTarget, setPaymentTarget] = useState<{ id: string; name: string; msg: string } | null>(null);
  const [paymentNotes, setPaymentNotes] = useState('');

  const [revertDialogOpen, setRevertDialogOpen] = useState(false);
  const [revertTarget, setRevertTarget] = useState<{ id: string; name: string; originalAmount: number } | null>(null);
  const [revertReason, setRevertReason] = useState('');

  const [liftDialogOpen, setLiftDialogOpen] = useState(false);
  const [liftTarget, setLiftTarget] = useState<{ id: string; name: string } | null>(null);
  const [liftReason, setLiftReason] = useState('');

  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [cancelTarget, setCancelTarget] = useState<{ id: string; name: string } | null>(null);
  const [cancelReason, setCancelReason] = useState('');

  const disputes = usePenaltyDisputes('pending');
  const reviewDispute = useReviewPenaltyDispute();
  const [reviewTarget, setReviewTarget] = useState<{ id: string; employeeName: string; reason: string } | null>(null);
  const [reviewNote, setReviewNote] = useState('');

  const bulkConfirm = useBulkConfirmPenaltyPayments();
  const bulkCancel = useBulkCancelPenalties();
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkCancelOpen, setBulkCancelOpen] = useState(false);
  const [bulkCancelReason, setBulkCancelReason] = useState('');
  const [bulkWhatsAppOpen, setBulkWhatsAppOpen] = useState(false);
  const [sentWhatsAppIds, setSentWhatsAppIds] = useState<Set<string>>(new Set());

  const selectedPenalties = useMemo(() => {
    if (selectedIds.size === 0) return [];
    const items = penalties.data ?? [];
    return items.filter((p) => selectedIds.has(p.id));
  }, [selectedIds, penalties.data]);

  const [earlyWarningModalOpen, setEarlyWarningModalOpen] = useState(false);
  const [overtimeModalOpen, setOvertimeModalOpen] = useState(false);
  const overtimeSummary = useDailyOvertimeSummary(dateFilterMode === 'today' ? cairoTodayIso() : specificDate || undefined);

  // ─── رادار الإنذار المبكر للموظفين الذين تكرر تأخيرهم (2+ غرامات) ──────
  const earlyWarningList = useMemo(() => {
    const items = penalties.data ?? [];
    const map = new Map<
      string,
      { employeeId: string; employeeName: string; phone: string | null; count: number; totalAmount: number; isSuspended: boolean; dates: string[] }
    >();
    for (const p of items) {
      if (p.status === 'cancelled') continue;
      const emp = employees?.find((e) => e.id === p.employeeId);
      const existing = map.get(p.employeeId) ?? {
        employeeId: p.employeeId,
        employeeName: p.employeeName ?? emp?.fullNameAr ?? 'موظف',
        phone: emp?.phoneE164 ?? null,
        count: 0,
        totalAmount: 0,
        isSuspended: false,
        dates: [],
      };
      existing.count += 1;
      existing.totalAmount += p.currentAmount;
      if (p.status === 'suspended') existing.isSuspended = true;
      existing.dates.push(p.workDate);
      map.set(p.employeeId, existing);
    }
    return Array.from(map.values())
      .filter((e) => e.count >= 2)
      .sort((a, b) => b.count - a.count);
  }, [penalties.data, employees]);

  function sendEmployeeWhatsAppAlert(p: InstantPenalty) {
    const emp = employees?.find((e) => e.id === p.employeeId);
    const name = p.employeeName ?? emp?.fullNameAr ?? 'الزميل العزيز';
    const text = generateEmployeePenaltyWhatsAppText(p, name);
    openWhatsApp(text, emp?.phoneE164);
  }

  // ─── تفنيط وإحصائيات شرائح الغرامات ──────────────────────────────────

  const tierStats = useMemo(() => {
    const items = penalties.data ?? [];
    const pendingList = items.filter((p) => p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended');

    const tier20 = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 20 || (p.originalAmount === 20 && p.escalationLevel === 'initial')));
    const tier50 = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 50 || (p.originalAmount === 50 && p.escalationLevel === 'initial')));
    const tier150 = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 150 || (p.originalAmount === 150 && p.escalationLevel === 'initial')));
    const tier500 = items.filter((p) => p.status !== 'cancelled' && (p.status === 'doubled' || p.escalationLevel === 'doubled' || p.currentAmount === 500));
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
        paidCount: tier20.filter((p) => p.status === 'paid').length,
        items: tier20,
      },
      tier50: {
        count: tier50.length,
        total: tier50.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier50.filter((p) => p.status === 'pending_payment').length,
        paidCount: tier50.filter((p) => p.status === 'paid').length,
        items: tier50,
      },
      tier150: {
        count: tier150.length,
        total: tier150.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier150.filter((p) => p.status === 'pending_payment').length,
        paidCount: tier150.filter((p) => p.status === 'paid').length,
        items: tier150,
      },
      tier500: {
        count: tier500.length,
        total: tier500.reduce((s, p) => s + p.currentAmount, 0),
        pendingCount: tier500.filter((p) => p.status === 'doubled' || p.status === 'pending_payment' || p.status === 'suspended').length,
        paidCount: tier500.filter((p) => p.status === 'paid').length,
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

    // 1. فلتر التاريخ (اليوم / أمس / تاريخ محدد / كل التواريخ)
    if (dateFilterMode === 'today') {
      const today = cairoTodayIso();
      items = items.filter((p) => p.workDate === today);
    } else if (dateFilterMode === 'yesterday') {
      const yest = getYesterdayIso();
      items = items.filter((p) => p.workDate === yest);
    } else if (dateFilterMode === 'specific' && specificDate) {
      items = items.filter((p) => p.workDate === specificDate);
    }

    // 2. فلتر الحالة (الافتراضي: المطالبون بالسداد فقط — استثناء من دفعوا أو أُلغيت لهم)
    if (statusFilter === 'unpaid') {
      items = items.filter((p) => p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended');
    } else if (statusFilter !== 'all') {
      items = items.filter((p) => p.status === statusFilter);
    }

    // 3. فلتر الشريحة المحددة من البطاقات العلوية
    if (selectedTier === 'pending') {
      items = items.filter((p) => p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended');
    } else if (selectedTier === 'tier-20') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 20 || (p.originalAmount === 20 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-50') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 50 || (p.originalAmount === 50 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-150') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.currentAmount === 150 || (p.originalAmount === 150 && p.escalationLevel === 'initial')));
    } else if (selectedTier === 'tier-500') {
      items = items.filter((p) => p.status !== 'cancelled' && (p.status === 'doubled' || p.escalationLevel === 'doubled' || p.currentAmount === 500));
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
  }, [penalties.data, search, dateFilterMode, specificDate, statusFilter, selectedTier]);

  // ─── إحصائيات سريعة ───────────────────────────────────────────────

  const stats = useMemo(() => {
    const pending = pendingEmployees.data ?? [];
    const suspendedCount = pending.filter((e) => e.isSuspended).length;
    const pendingCount = pending.length;
    const totalOwed = pending.reduce((s, e) => s + e.totalAmount, 0);
    return { suspendedCount, pendingCount, totalOwed };
  }, [pendingEmployees.data]);

  // ─── أعمدة الجدول ─────────────────────────────────────────────────

  // الوصول من إشعار غرامة → إبراز صف الغرامة نفسه في الجدول.
  const focusedId = useEntityFocus(rows.length > 0, 'focus', () => {
    setCheckFeedback('الغرامة المطلوبة غير ظاهرة ضمن الفلتر الحالي — امسح الفلاتر لعرضها.');
    if (checkFeedbackTimer.current) clearTimeout(checkFeedbackTimer.current);
    checkFeedbackTimer.current = setTimeout(() => setCheckFeedback(null), 8000);
  });

  const columns = buildPenaltyColumns({
    employeePhotoMap,
    confirmPending: confirmPayment.isPending,
    liftPending: liftSuspension.isPending,
    revertPending: revertPenalty.isPending,
    cancelPending: cancelPenalty.isPending,
    onPaymentClick: (p) => {
      const confirmMsg =
        p.status === 'suspended'
          ? `هل تم استلام 500 ج.م من الزميل ${p.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`
          : `تأكيد استلام ${formatCurrency(p.currentAmount)} من الزميل ${p.employeeName ?? 'الموظف'} وإيداعها في صندوق الزمالة والتكافل؟`;
      setPaymentTarget({ id: p.id, name: p.employeeName ?? 'الموظف', msg: confirmMsg });
      setPaymentNotes('');
      setPaymentDialogOpen(true);
    },
    onLiftClick: (p) => {
      setLiftTarget({ id: p.id, name: p.employeeName ?? '' });
      setLiftReason('');
      setLiftDialogOpen(true);
    },
    onRevertClick: (p) => {
      setRevertTarget({ id: p.id, name: p.employeeName ?? '', originalAmount: p.originalAmount });
      setRevertReason('');
      setRevertDialogOpen(true);
    },
    onCancelClick: (p) => {
      setCancelTarget({ id: p.id, name: p.employeeName ?? '' });
      setCancelReason('');
      setCancelDialogOpen(true);
    },
    onWhatsAppClick: sendEmployeeWhatsAppAlert,
  });

  // ─── فلاتر ─────────────────────────────────────────────────────────

  const dirty = Boolean(search.trim() || dateFilterMode !== 'today' || statusFilter !== 'unpaid' || selectedTier !== 'all');
  const clearFilters = () => {
    setSearch('');
    setDateFilterMode('today');
    setSpecificDate(cairoTodayIso());
    setStatusFilter('unpaid');
    setSelectedTier('all');
  };

  // ─── إنشاء غرامة يدوية ────────────────────────────────────────────

  const submitPenalty = async (ev: FormEvent) => {
    ev.preventDefault();
    if (!employeeId) return;
    const mins = Math.min(120, Number(lateMinutes));
    if (!Number.isFinite(mins) || mins <= 0) return;
    setFormFeedback(null);
    const result = await generatePenalty.mutateAsync({
      employeeId,
      workDate,
      lateMinutes: mins,
    });
    if (result.isExempt) {
      setFormFeedback(result.message ?? 'الموظف معفى من غرامات الحضور والانصراف (مأمورية / إجازة / قافلة / فاندي)');
      return;
    }
    setFormOpen(false);
    setEmployeeId('');
    setLateMinutes('');
    setWorkDate(cairoTodayIso());
  };

  // ─── تصدير ─────────────────────────────────────────────────────────

  const handleCsvExport = () => exportPenaltiesCsv(rows);
  const handlePdfExport = () => exportPenaltiesPdf(rows, dateFilterMode, specificDate, statusFilter);
  const handleHtmlExport = () => exportPenaltiesHtml(rows, dateFilterMode, specificDate, statusFilter);
  const handleExportModalTierPdf = (tier: string) =>
    exportModalTierPdf({
      tier,
      allPenalties: penalties.data ?? [],
      pendingEmployees: pendingEmployees.data ?? [],
      totalOwed: stats.totalOwed,
      suspendedCount: stats.suspendedCount,
    });

  // ─── ملخص أسبوعي عبر واتساب للمدير (مجاني 100%) ─────────────────────

  const sendWeeklyWhatsAppSummary = () => {
    const items = penalties.data ?? [];
    const fundBalance = fundSummary.data?.currentBalance ?? 0;
    openWhatsApp(buildWeeklyWhatsAppSummaryText(items, fundBalance));
  };

  // ─── إحصائيات نسبة التحصيل ────────────────────────────────────────

  const collectionStats = useMemo(() => {
    const items = penalties.data ?? [];
    const nonCancelled = items.filter((p) => p.status !== 'cancelled');
    const paid = nonCancelled.filter((p) => p.status === 'paid');
    const totalCount = nonCancelled.length;
    const paidCount = paid.length;
    const rate = totalCount > 0 ? Math.round((paidCount / totalCount) * 100) : 0;
    const totalCollected = paid.reduce((s, p) => s + p.currentAmount, 0);
    return { rate, totalCollected, paidCount, totalCount };
  }, [penalties.data]);

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="الغرامات الفورية للتأخير"
        description="الحضور يبدأ 10:00 ص — أول 15 دقيقة سماح. الشرائح: 20/50/150 ج.م. عدم السداد → 500 ج.م ثم تعليق الحساب."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              className="btn-secondary flex items-center gap-1.5 text-xs sm:text-sm font-medium"
              onClick={async () => {
                try {
                  const res = await triggerCheck.mutateAsync();
                  setCheckFeedback(res.message ?? 'تم فحص الحضور وتطبيق الغرامات بنجاح');
                  if (checkFeedbackTimer.current) clearTimeout(checkFeedbackTimer.current);
                  checkFeedbackTimer.current = setTimeout(() => setCheckFeedback(null), 8000);
                } catch (err) {
                  setCheckFeedback('حدث خطأ أثناء الفحص: ' + safeErrorMessage(err));
                }
              }}
              disabled={triggerCheck.isPending}
              title="فحص فوري وتطبيق الخصومات على من لم يبصم حتى الآن وتحديث الشرائح"
            >
              <RefreshCw className={`size-4 ${triggerCheck.isPending ? 'animate-spin text-primary' : ''}`} aria-hidden="true" />
              <span>{triggerCheck.isPending ? 'جارٍ الفحص...' : 'فحص وتطبيق الآن'}</span>
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

      {/* ─── ملخص + صناديق شرائح الغرامات ─────────────────────────── */}
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2 text-xs">
          {stats.pendingCount > 0 && (
            <button
              type="button"
              onClick={() => setSelectedTier((prev) => (prev === 'pending' ? 'all' : 'pending'))}
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold transition-all cursor-pointer ${selectedTier === 'pending'
                ? 'border-amber-500 bg-amber-500/15 text-amber-600 dark:text-amber-400 ring-2 ring-amber-500/30'
                : 'border-amber-500/30 bg-amber-500/5 text-amber-700 dark:text-amber-300 hover:bg-amber-500/10'
                }`}
            >
              <AlertTriangle className="size-3.5" />
              <span>{stats.pendingCount} موظف مطالب بالدفع</span>
              <span className="font-mono opacity-80 mr-1">({formatCurrency(stats.totalOwed)})</span>
            </button>
          )}
          {stats.suspendedCount > 0 && (
            <button
              type="button"
              onClick={() => setSelectedTier((prev) => (prev === 'suspended' ? 'all' : 'suspended'))}
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold transition-all cursor-pointer ${selectedTier === 'suspended'
                ? 'border-red-500 bg-red-500/15 text-red-600 dark:text-red-400 ring-2 ring-red-500/30'
                : 'border-red-500/30 bg-red-500/5 text-red-700 dark:text-red-300 hover:bg-red-500/10'
                }`}
            >
              <Ban className="size-3.5" />
              <span>{stats.suspendedCount} معلّق عن العمل</span>
            </button>
          )}
          <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/30 bg-emerald-500/5 px-3 py-1.5 font-bold text-emerald-700 dark:text-emerald-300">
            <Coins className="size-3.5" />
            <span>رصيد صندوق الزمالة والتكافل: {formatCurrency(fundSummary.data?.currentBalance ?? 0)}</span>
          </span>
          {canResetExperimental && (
            <button
              type="button"
              onClick={() => {
                setResetError(null);
                setResetDialogOpen(true);
              }}
              className="inline-flex items-center gap-1.5 rounded-full border border-rose-500/30 bg-rose-500/10 hover:bg-rose-500/20 px-3 py-1.5 text-xs font-bold text-rose-700 dark:text-rose-300 transition-all cursor-pointer shadow-xs"
              title="تصفير ومسح السدادات وحركات صندوق الزمالة التجريبية السابقة"
            >
              <RotateCcw className="size-3.5 text-rose-600 dark:text-rose-400" />
              <span>تصفير الدفع التجريبي</span>
            </button>
          )}
          {collectionStats.totalCount > 0 && (
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold ${collectionStats.rate >= 80
                ? 'border-emerald-500/30 bg-emerald-500/5 text-emerald-700 dark:text-emerald-300'
                : collectionStats.rate >= 50
                  ? 'border-amber-500/30 bg-amber-500/5 text-amber-700 dark:text-amber-300'
                  : 'border-red-500/30 bg-red-500/5 text-red-700 dark:text-red-300'
                }`}
            >
              <CheckCircle2 className="size-3.5" />
              <span>
                نسبة التحصيل: {collectionStats.rate}% ({collectionStats.paidCount}/{collectionStats.totalCount})
              </span>
            </span>
          )}
          <button
            type="button"
            onClick={sendWeeklyWhatsAppSummary}
            className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/30 bg-emerald-600 hover:bg-emerald-700 px-3 py-1.5 font-bold text-white shadow-xs transition-all cursor-pointer"
            title="إرسال ملخص أسبوعي بالغرامات عبر واتساب للإدارة (مجاناً 100%)"
          >
            <MessageCircle className="size-3.5" />
            <span>ملخص أسبوعي واتساب</span>
          </button>
        </div>

        {/* ─── رادار الإنذار المبكر للتأخير المتكرر ─────────────────────── */}
        {earlyWarningList.length > 0 && (
          <div className="rounded-xl border border-amber-500/30 bg-gradient-to-r from-amber-500/10 via-amber-500/5 to-transparent p-3.5 text-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 shadow-xs">
            <div className="flex items-center gap-2.5">
              <div className="p-2 rounded-lg bg-amber-500/20 text-amber-700 dark:text-amber-300 shrink-0">
                <ShieldAlert className="size-5" />
              </div>
              <div>
                <p className="font-bold text-amber-900 dark:text-amber-200">
                  رادار الإنذار المبكر — {earlyWarningList.length} زملاء لديهم تكرار تأخير (2+ غرامات)
                </p>
                <p className="text-xs text-amber-800/80 dark:text-amber-300/80">
                  تنبيه استباقي وتشجيع على الانضباط لحمايتهم قبل الوصول للمضاعفة إلى 500 ج.م أو تعليق الحساب.
                </p>
              </div>
            </div>
            <button
              type="button"
              className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold bg-amber-600 hover:bg-amber-700 text-white shadow-sm transition-all cursor-pointer whitespace-nowrap shrink-0"
              onClick={() => setEarlyWarningModalOpen(true)}
            >
              <MessageCircle className="size-3.5" />
              <span>عرض كشف الرادار والتنبيهات</span>
            </button>
          </div>
        )}

        {/* ─── صندوق ساعات العمل الإضافي (Daily Overtime Hub) ─────────── */}
        <div className="rounded-xl border border-teal-500/30 bg-gradient-to-r from-teal-500/10 via-emerald-500/5 to-transparent p-3.5 text-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 shadow-xs">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-teal-500/20 text-teal-700 dark:text-teal-300 shrink-0">
              <Timer className="size-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-teal-950 dark:text-teal-200">صندوق ساعات العمل الإضافي — Overtime Hub</span>
                <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-bold bg-teal-500/15 text-teal-700 dark:text-teal-300 border border-teal-500/30">
                  {overtimeSummary.data?.employeesCount ?? 0} موظفاً قضوا وقتاً إضافياً اليوم
                </span>
              </div>
              <p className="text-xs text-teal-900/80 dark:text-teal-300/80 mt-0.5">
                إجمالي الوقت الإضافي لليوم:{' '}
                <span className="font-bold font-mono text-teal-700 dark:text-teal-300">{overtimeSummary.data?.totalOvertimeFormatted || '0 دقيقة'}</span> (
                {overtimeSummary.data?.totalOvertimeMinutes ?? 0} دقيقة زيادة فوق ساعات العمل المقررة)
              </p>
            </div>
          </div>
          <button
            type="button"
            className="inline-flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-bold bg-teal-600 hover:bg-teal-700 text-white shadow-sm transition-all cursor-pointer whitespace-nowrap shrink-0"
            onClick={() => setOvertimeModalOpen(true)}
          >
            <Timer className="size-3.5" />
            <span>عرض تفاصيل الموظفين والوقت الإضافي</span>
          </button>
        </div>

        <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
          {[
            {
              key: 'tier-20' as const,
              label: '20 ج.م',
              badge: '16-30 د',
              count: tierStats.tier20.count,
              total: tierStats.tier20.total,
              pending: tierStats.tier20.pendingCount,
              icon: Clock3,
              activeCls: 'border-sky-500 bg-sky-500/10 ring-2 ring-sky-500/30',
              inactiveCls: 'border-sky-500/25 bg-sky-500/[.03] hover:border-sky-500/50 hover:bg-sky-500/[.06]',
              iconCls: 'bg-sky-500/15 text-sky-600 dark:text-sky-400',
              badgeCls: 'bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/20',
              countCls: 'text-sky-600 dark:text-sky-400',
            },
            {
              key: 'tier-50' as const,
              label: '50 ج.م',
              badge: '½ ساعة - ساعتين',
              count: tierStats.tier50.count,
              total: tierStats.tier50.total,
              pending: tierStats.tier50.pendingCount,
              icon: SunMedium,
              activeCls: 'border-amber-500 bg-amber-500/10 ring-2 ring-amber-500/30',
              inactiveCls: 'border-amber-500/25 bg-amber-500/[.03] hover:border-amber-500/50 hover:bg-amber-500/[.06]',
              iconCls: 'bg-amber-500/15 text-amber-600 dark:text-amber-400',
              badgeCls: 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/20',
              countCls: 'text-amber-600 dark:text-amber-400',
            },
            {
              key: 'tier-150' as const,
              label: '150 ج.م',
              badge: 'ساعتين+ / عدم بصمة',
              count: tierStats.tier150.count,
              total: tierStats.tier150.total,
              pending: tierStats.tier150.pendingCount,
              icon: Zap,
              activeCls: 'border-orange-500 bg-orange-500/10 ring-2 ring-orange-500/30',
              inactiveCls: 'border-orange-500/25 bg-orange-500/[.03] hover:border-orange-500/50 hover:bg-orange-500/[.06]',
              iconCls: 'bg-orange-500/15 text-orange-600 dark:text-orange-400',
              badgeCls: 'bg-orange-500/10 text-orange-700 dark:text-orange-300 border-orange-500/20',
              countCls: 'text-orange-600 dark:text-orange-400',
            },
            {
              key: 'tier-500' as const,
              label: '500 ج.م',
              badge: 'مضاعفة اليوم 2',
              count: tierStats.tier500.count,
              total: tierStats.tier500.total,
              pending: tierStats.tier500.pendingCount,
              icon: Flame,
              activeCls: 'border-purple-500 bg-purple-500/10 ring-2 ring-purple-500/30',
              inactiveCls: 'border-purple-500/25 bg-purple-500/[.03] hover:border-purple-500/50 hover:bg-purple-500/[.06]',
              iconCls: 'bg-purple-500/15 text-purple-600 dark:text-purple-400',
              badgeCls: 'bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/20',
              countCls: 'text-purple-600 dark:text-purple-400',
            },
          ].map((t) => (
            <button
              key={t.key}
              type="button"
              onClick={() => setSelectedTier((prev) => (prev === t.key ? 'all' : t.key))}
              className={`text-start rounded-xl border p-3.5 transition-all cursor-pointer ${selectedTier === t.key ? t.activeCls : t.inactiveCls}`}
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <div className={`rounded-lg p-1.5 ${t.iconCls}`}>
                    <t.icon className="size-4" aria-hidden="true" />
                  </div>
                  <span className="text-xs font-bold text-[var(--text-primary)]">{t.label}</span>
                </div>
                <span className={`text-[10px] rounded border px-1.5 py-0.5 font-mono ${t.badgeCls}`}>{t.badge}</span>
              </div>
              <div className="flex items-baseline justify-between mt-1">
                <span className={`text-2xl font-black font-mono leading-none ${t.countCls}`}>{t.count}</span>
                <span className="text-xs font-mono font-bold text-[var(--text-secondary)]">{formatCurrency(t.total)}</span>
              </div>
              <div className="mt-2.5 pt-2 border-t border-[var(--border-subtle)] text-[11px] flex items-center justify-between">
                <span className="text-amber-500 font-medium">{t.pending} معلّق</span>
                <span className={`font-bold text-xs ${selectedTier === t.key ? 'text-primary' : 'text-[var(--text-muted)]'}`}>
                  {selectedTier === t.key ? 'محدد ✓' : 'عرض ←'}
                </span>
              </div>
            </button>
          ))}
        </div>

        {selectedTier !== 'all' && (
          <div className="flex items-center justify-between gap-2 rounded-lg border border-primary/30 bg-primary/5 px-3 py-2 text-xs">
            <div className="flex items-center gap-2">
              <span className="text-[var(--text-muted)]">تصفية:</span>
              <span className="font-bold text-primary">
                {selectedTier === 'pending' && 'المطالبون بالدفع'}
                {selectedTier === 'suspended' && 'المعلّقون عن العمل'}
                {selectedTier === 'tier-20' && 'شريحة 20 ج.م'}
                {selectedTier === 'tier-50' && 'شريحة 50 ج.م'}
                {selectedTier === 'tier-150' && 'شريحة 150 ج.م'}
                {selectedTier === 'tier-500' && 'مضاعفة 500 ج.م'}
              </span>
              <span className="text-[var(--text-muted)] font-mono">({rows.length})</span>
            </div>
            <div className="flex items-center gap-2">
              <button type="button" className="text-primary hover:underline font-bold" onClick={() => setActiveModalTier(selectedTier)}>
                الكشف التفصيلي ↗
              </button>
              <button type="button" className="text-[var(--danger)] hover:underline font-bold" onClick={() => setSelectedTier('all')}>
                إلغاء ✕
              </button>
            </div>
          </div>
        )}

        {stats.suspendedCount > 0 && selectedTier !== 'suspended' && (
          <div className="rounded-lg border border-red-500/30 bg-red-500/5 p-3 text-xs text-red-700 dark:text-red-300 flex items-center justify-between">
            <span className="flex items-center gap-2 font-bold">
              <Ban className="size-4" />
              {stats.suspendedCount} موظف موقوف — حسابات مغلقة لعدم سداد 500 ج.م
            </span>
            <button type="button" className="font-bold hover:underline" onClick={() => setSelectedTier('suspended')}>
              عرض الكشف ←
            </button>
          </div>
        )}
      </div>

      {/* ─── نموذج الإنشاء اليدوي ──────────────────────────────────── */}
      {formOpen && (
        <section className="card p-5">
          <h2 className="font-black">إنشاء غرامة فورية للتأخير</h2>
          <p className="mt-1 text-xs text-[var(--text-muted)]">
            الحضور يبدأ 10:00 ص: من 1-15 دقيقة = سماح بدون خصم (0 ج.م) | حتى 10:30 (16-30 دقيقة) = 20 ج.م | حتى 11:00 (31-60 دقيقة) = 50 ج.م | من 11:01 وحتى
            12:00 (61-120 دقيقة) = 150 ج.م.
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
              <ArabicDateInput className="input mt-1" value={workDate} onChange={(ev) => setWorkDate(ev.target.value)} required />
            </label>
            <label className="block">
              <span className="muted text-xs">دقائق التأخير *</span>
              <input
                className="input mt-1"
                type="number"
                min="1"
                max="120"
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
                        ? 'خصم 50 ج.م (تأخير من 10:31 وحتى 11:00)'
                        : 'خصم 150 ج.م (تأخير من 11:01 وحتى 12:00 — بحد أقصى ساعتين)'}
                </span>
              )}
            </label>
            <div className="flex items-end gap-2">
              <button type="submit" className="btn-primary" disabled={generatePenalty.isPending || !employeeId || !(Number(lateMinutes) > 0)}>
                {generatePenalty.isPending ? 'جارٍ الحفظ…' : 'تسجيل الغرامة'}
              </button>
              <button type="button" className="btn-secondary" onClick={() => setFormOpen(false)}>
                إلغاء
              </button>
            </div>
            {formFeedback && (
              <p className="text-sm font-bold text-amber-700 dark:text-amber-300 bg-amber-500/10 border border-amber-500/20 p-3 rounded-xl sm:col-span-2 lg:col-span-4">
                ⚠️ {formFeedback}
              </p>
            )}
            {generatePenalty.isError && <p className="text-sm text-[var(--danger)] sm:col-span-2 lg:col-span-4">{safeErrorMessage(generatePenalty.error)}</p>}
          </form>
        </section>
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
        {/* تحديد التاريخ */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <select
            className="input text-xs font-semibold"
            value={dateFilterMode}
            onChange={(ev) => setDateFilterMode(ev.target.value as typeof dateFilterMode)}
            aria-label="تصفية حسب التاريخ"
          >
            <option value="today">اليوم ({cairoTodayIso()})</option>
            <option value="yesterday">أمس ({getYesterdayIso()})</option>
            <option value="specific">تاريخ محدد…</option>
            <option value="all">كل التواريخ (الأرشيف)</option>
          </select>

          {/* أزرار سريعة بنقرة واحدة */}
          <div className="hidden sm:inline-flex items-center gap-0.5 p-0.5 bg-[var(--surface-muted)]/90 rounded-lg border border-[var(--border-subtle)] text-xs font-bold">
            <button
              type="button"
              onClick={() => setDateFilterMode('today')}
              className={`px-2 py-0.5 rounded-md transition-all cursor-pointer ${dateFilterMode === 'today'
                ? 'bg-[var(--brand-primary)] text-white shadow-xs font-black'
                : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface)]'
                }`}
            >
              اليوم
            </button>
            <button
              type="button"
              onClick={() => setDateFilterMode('yesterday')}
              className={`px-2 py-0.5 rounded-md transition-all cursor-pointer ${dateFilterMode === 'yesterday'
                ? 'bg-[var(--brand-primary)] text-white shadow-xs font-black'
                : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface)]'
                }`}
            >
              أمس
            </button>
            <button
              type="button"
              onClick={() => setDateFilterMode('all')}
              className={`px-2 py-0.5 rounded-md transition-all cursor-pointer ${dateFilterMode === 'all'
                ? 'bg-[var(--brand-primary)] text-white shadow-xs font-black'
                : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface)]'
                }`}
            >
              الأرشيف
            </button>
          </div>

          {dateFilterMode === 'specific' && (
            <ArabicDateInput
              className="input text-xs font-mono py-1 px-2 border-primary/50 shadow-xs !w-auto"
              value={specificDate}
              onChange={(ev) => setSpecificDate(ev.target.value)}
              aria-label="اختر التاريخ المحدد"
            />
          )}
        </div>

        {/* تحديد الحالة */}
        <select
          className="input text-xs font-semibold"
          value={statusFilter}
          onChange={(ev) => setStatusFilter(ev.target.value as typeof statusFilter)}
          aria-label="تصفية حسب الحالة"
        >
          <option value="unpaid">المطالبون بالسداد فقط (غير مدفوعة)</option>
          <option value="all">كل الحالات (شامل المدفوعة والملغاة)</option>
          <option value="pending_payment">بانتظار السداد (أولية)</option>
          <option value="doubled">مضاعفة (500 ج.م)</option>
          <option value="suspended">معلّق عن العمل</option>
          <option value="paid">مدفوعة</option>
          <option value="cancelled">ملغاة</option>
        </select>

        <button
          type="button"
          className="btn-secondary text-xs font-bold hover:border-emerald-500/50 hover:bg-emerald-500/5 hover:text-emerald-700 dark:hover:text-emerald-300 transition-all cursor-pointer"
          onClick={handleCsvExport}
          disabled={rows.length === 0}
          title="تصدير Excel (CSV)"
        >
          <FileSpreadsheet className="size-4 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
          <span>Excel</span>
        </button>
        <button
          type="button"
          className="btn-secondary text-xs font-bold hover:border-rose-500/50 hover:bg-rose-500/5 hover:text-rose-700 dark:hover:text-rose-300 transition-all cursor-pointer"
          onClick={handlePdfExport}
          disabled={rows.length === 0}
          title="طباعة وحفظ كملف PDF"
        >
          <Printer className="size-4 text-rose-600 dark:text-rose-400" aria-hidden="true" />
          <span>تصدير PDF</span>
        </button>
        <button
          type="button"
          className="btn-secondary text-xs font-bold hover:border-sky-500/50 hover:bg-sky-500/5 hover:text-sky-700 dark:hover:text-sky-300 transition-all cursor-pointer"
          onClick={handleHtmlExport}
          disabled={rows.length === 0}
          title="تنزيل تقرير HTML مستقل مباشرة"
        >
          <Download className="size-4 text-sky-600 dark:text-sky-400" aria-hidden="true" />
          <span>تنزيل HTML</span>
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
        <>
          {selectedIds.size > 0 && (
            <div className="flex flex-wrap items-center gap-3 rounded-xl border border-blue-300/80 dark:border-blue-700/60 bg-blue-50/70 dark:bg-blue-950/30 p-2.5 backdrop-blur-xs shadow-xs">
              <span className="text-xs font-bold text-blue-800 dark:text-blue-300 px-1">
                تم تحديد{' '}
                {selectedIds.size === 1
                  ? 'غرامة واحدة'
                  : selectedIds.size === 2
                    ? 'غرامتان'
                    : selectedIds.size <= 10
                      ? `${selectedIds.size} غرامات`
                      : `${selectedIds.size} غرامة`}
              </span>
              <div className="flex-1" />
              <button
                type="button"
                onClick={() => setBulkWhatsAppOpen(true)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold text-emerald-700 dark:text-emerald-300 bg-emerald-50 dark:bg-emerald-950/40 hover:bg-emerald-100 dark:hover:bg-emerald-900/50 border border-emerald-300 dark:border-emerald-700 rounded-lg shadow-xs transition-all active:scale-95 cursor-pointer"
                title="إرسال تنبيهات واتساب مخصصة لكل موظف محدد باسمه وتفاصيل غرامته"
              >
                <MessageCircle className="size-3.5 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
                <span>إرسال واتساب جماعي ({selectedIds.size})</span>
              </button>
              <button
                type="button"
                onClick={async () => {
                  const ids = [...selectedIds];
                  const count = await bulkConfirm.mutateAsync({ penaltyIds: ids });
                  toast({ message: `تم تأكيد ${count} غرامة`, tone: 'success' });
                  setSelectedIds(new Set());
                  setSentWhatsAppIds(new Set());
                }}
                disabled={bulkConfirm.isPending}
                className="inline-flex items-center gap-1.5 px-3.5 py-1.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 dark:bg-blue-600 dark:hover:bg-blue-500 rounded-lg shadow-xs transition-all active:scale-95 disabled:opacity-50 cursor-pointer"
              >
                {bulkConfirm.isPending ? 'جارٍ…' : `تأكيد دفع (${selectedIds.size})`}
              </button>
              <button
                type="button"
                onClick={() => setBulkCancelOpen(true)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold text-red-600 dark:text-red-400 border border-red-300 dark:border-red-800/60 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/40 transition-colors cursor-pointer"
              >
                إلغاء جماعي ({selectedIds.size})
              </button>
              <button
                type="button"
                onClick={() => {
                  setSelectedIds(new Set());
                  setSentWhatsAppIds(new Set());
                }}
                className="px-2.5 py-1.5 text-xs font-medium text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors cursor-pointer"
              >
                إلغاء التحديد
              </button>
            </div>
          )}

          <DataTable
            ariaLabel="جدول الغرامات الفورية للتأخير"
            rowKey={(p) => p.id}
            focusedKey={focusedId}
            data={rows}
            minWidth="960px"
            maxHeight="min(60vh, 520px)"
            columns={columns}
            selectable
            selectedKeys={selectedIds}
            onSelectionChange={setSelectedIds}
            pinFirstColumn
            pinLastColumn
            emptyTitle="لا توجد نتائج"
            emptyDescription="جرّب تعديل البحث أو الحالة."
            rowClassName={(p) => {
              const classes: string[] = [];
              if (p.status === 'paid' || p.status === 'cancelled') classes.push('row-dimmed');
              if (selectedIds.has(p.id)) classes.push('bg-blue-50/50 dark:bg-blue-950/10');
              return classes.length > 0 ? classes.join(' ') : undefined;
            }}
          />
        </>
      )}

      {/* ─── نافذة التفاصيل الشاملة للفئة / الصندوق ───────────────────────── */}
      <PenaltyTierDetailModal
        activeModalTier={activeModalTier}
        pendingEmployees={pendingEmployees.data ?? []}
        allPenalties={penalties.data ?? []}
        stats={{ totalOwed: stats.totalOwed, suspendedCount: stats.suspendedCount }}
        tierStats={tierStats}
        fellowshipFundPath={fellowshipFundPath}
        onExportPdf={handleExportModalTierPdf}
        onOpenPaymentDialog={(p) => {
          setActiveModalTier(null);
          const confirmMsg =
            p.status === 'suspended'
              ? `هل تم استلام 500 ج.م من الزميل ${p.employeeName ?? 'الموظف'} وتوريدها لصندوق الزمالة؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته لمباشرة العمل وإشعار الفريق.`
              : `تأكيد استلام ${formatCurrency(p.currentAmount)} من الزميل ${p.employeeName ?? 'الموظف'} وإيداعها في صندوق الزمالة والتكافل؟`;
          setPaymentTarget({ id: p.id, name: p.employeeName ?? '', msg: confirmMsg });
          setPaymentNotes('');
          setPaymentDialogOpen(true);
        }}
        onOpenLiftDialog={(p) => {
          setActiveModalTier(null);
          setLiftTarget({ id: p.id, name: p.employeeName ?? '' });
          setLiftReason('');
          setLiftDialogOpen(true);
        }}
        onFilterByEmployee={(employeeName) => {
          setSearch(employeeName);
          setSelectedTier('all');
          setActiveModalTier(null);
        }}
        onSelectTier={(tier) => {
          setSelectedTier(tier);
          setActiveModalTier(null);
        }}
        onClose={() => setActiveModalTier(null)}
      />

      {/* ─── الطعون المعلقة وحوارات الإجراءات ──────────────────────── */}
      <PenaltyDisputesAndDialogs
        disputes={disputes.data ?? []}
        onReviewDispute={(target) => {
          setReviewTarget(target);
          setReviewNote('');
        }}
        paymentDialogOpen={paymentDialogOpen}
        paymentTarget={paymentTarget}
        paymentNotes={paymentNotes}
        onPaymentNotesChange={setPaymentNotes}
        paymentPending={confirmPayment.isPending}
        paymentIsError={confirmPayment.isError}
        paymentError={confirmPayment.error}
        onConfirmPayment={async () => {
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
        onCancelPayment={() => {
          confirmPayment.reset();
          setPaymentDialogOpen(false);
          setPaymentTarget(null);
          setPaymentNotes('');
        }}
        liftDialogOpen={liftDialogOpen}
        liftTarget={liftTarget}
        liftReason={liftReason}
        onLiftReasonChange={setLiftReason}
        liftPending={liftSuspension.isPending}
        liftIsError={liftSuspension.isError}
        liftError={liftSuspension.error}
        onConfirmLift={async () => {
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
        onCancelLift={() => {
          liftSuspension.reset();
          setLiftDialogOpen(false);
          setLiftTarget(null);
          setLiftReason('');
        }}
        revertDialogOpen={revertDialogOpen}
        revertTarget={revertTarget}
        revertReason={revertReason}
        onRevertReasonChange={setRevertReason}
        revertPending={revertPenalty.isPending}
        revertIsError={revertPenalty.isError}
        revertError={revertPenalty.error}
        onConfirmRevert={async () => {
          if (revertTarget) {
            try {
              await revertPenalty.mutateAsync({
                penaltyId: revertTarget.id,
                reason: revertReason.trim() || undefined,
              });
              toast({
                message: `تم إرجاع غرامة ${revertTarget.name} إلى قيمتها الأصلية (${formatCurrency(revertTarget.originalAmount)}) بنجاح`,
                tone: 'success',
              });
              setRevertDialogOpen(false);
              setRevertTarget(null);
              setRevertReason('');
            } catch {
              // Error is displayed inside InputDialog
            }
          }
        }}
        onCancelRevert={() => {
          revertPenalty.reset();
          setRevertDialogOpen(false);
          setRevertTarget(null);
          setRevertReason('');
        }}
        cancelDialogOpen={cancelDialogOpen}
        cancelTarget={cancelTarget}
        cancelReason={cancelReason}
        onCancelReasonChange={setCancelReason}
        cancelPending={cancelPenalty.isPending}
        cancelIsError={cancelPenalty.isError}
        cancelError={cancelPenalty.error}
        onConfirmCancel={async () => {
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
        onCancelCancel={() => {
          cancelPenalty.reset();
          setCancelDialogOpen(false);
          setCancelTarget(null);
          setCancelReason('');
        }}
        bulkCancelOpen={bulkCancelOpen}
        selectedCount={selectedIds.size}
        bulkCancelReason={bulkCancelReason}
        onBulkCancelReasonChange={setBulkCancelReason}
        bulkCancelPending={bulkCancel.isPending}
        bulkCancelIsError={bulkCancel.isError}
        bulkCancelError={bulkCancel.error}
        onConfirmBulkCancel={async () => {
          if (bulkCancelReason.trim()) {
            try {
              const ids = [...selectedIds];
              const count = await bulkCancel.mutateAsync({ penaltyIds: ids, reason: bulkCancelReason.trim() });
              toast({ message: `تم إلغاء ${count} غرامة`, tone: 'success' });
              setBulkCancelOpen(false);
              setSelectedIds(new Set());
              setBulkCancelReason('');
            } catch {
              // Error is displayed inside InputDialog
            }
          }
        }}
        onCancelBulkCancel={() => {
          bulkCancel.reset();
          setBulkCancelOpen(false);
          setBulkCancelReason('');
        }}
      />

      {/* ─── نافذة مراجعة الطعن ──────────────────────────────────────── */}
      <DisputeReviewModal
        target={reviewTarget}
        note={reviewNote}
        onNoteChange={setReviewNote}
        isPending={reviewDispute.isPending}
        isError={reviewDispute.isError}
        error={reviewDispute.error}
        onSubmit={(status) => {
          if (!reviewTarget) return;
          reviewDispute.mutate(
            {
              disputeId: reviewTarget.id,
              status,
              note: reviewNote.trim() || (status === 'approved' ? 'قُبل الطعن' : undefined),
            },
            { onSuccess: () => setReviewTarget(null) },
          );
        }}
        onClose={() => setReviewTarget(null)}
      />

      {/* ─── نافذة كشف رادار الإنذار المبكر والتنبيهات ──────────────── */}
      <EarlyWarningRadarModal
        open={earlyWarningModalOpen}
        employees={earlyWarningList}
        onClose={() => setEarlyWarningModalOpen(false)}
      />

      {/* ─── نافذة تأكيد تصفير الدفعات التجريبية وصندوق الزمالة ─────────── */}
      <ResetExperimentalModal
        open={resetDialogOpen}
        isPending={resetExperimentalPayments.isPending}
        resetError={resetError}
        onConfirm={async () => {
          setResetError(null);
          try {
            const result = await resetExperimentalPayments.mutateAsync();
            toast({ message: result.message || 'تم تصفير البيانات التجريبية بنجاح', tone: 'success' });
            setResetDialogOpen(false);
          } catch (err) {
            setResetError(safeErrorMessage(err));
          }
        }}
        onClose={() => setResetDialogOpen(false)}
      />

      {/* ─── نافذة إرسال رسائل وتنبيهات واتساب المخصصة للموظفين المحددين ── */}
      <PenaltyWhatsAppModal
        open={bulkWhatsAppOpen}
        selectedPenalties={selectedPenalties}
        employees={employees}
        employeePhotoMap={employeePhotoMap}
        sentWhatsAppIds={sentWhatsAppIds}
        onMarkSent={(penaltyId) => setSentWhatsAppIds((prev) => new Set(prev).add(penaltyId))}
        onNotify={(message) => toast({ message, tone: 'success' })}
        onClose={() => setBulkWhatsAppOpen(false)}
      />

      {/* ─── نافذة تفاصيل ساعات العمل الإضافي ───────────────────────────── */}
      <OvertimeSummaryModal
        open={overtimeModalOpen}
        data={overtimeSummary.data}
        onClose={() => setOvertimeModalOpen(false)}
      />
    </div>
  );
}
