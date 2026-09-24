import { cairoTodayIso } from '../../core/cairoTime';
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import {
  AlertTriangle,
  Ban,
  Calendar,
  CheckCircle2,
  Clock,
  Clock3,
  Coins,
  FileSpreadsheet,
  Flame,
  MessageSquare,
  MessageCircle,
  Printer,
  RefreshCw,
  ShieldAlert,
  Sparkles,
  SunMedium,
  XCircle,
  Zap,
} from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { useEntityFocus } from '../../core/useEntityFocus';
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
import { useToast } from '../../ui/Toast';
import { useEmployees } from '../employees/useEmployees';
import { useFellowshipFundSummary } from './useFellowshipFund';
import { usePenaltyDisputes, useReviewPenaltyDispute } from './usePenaltyDisputes';
import { PendingSuspensionsCard } from './PendingSuspensionsCard';
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
  useBulkConfirmPenaltyPayments,
  useBulkCancelPenalties,
  type InstantPenalty,
  type PendingPenaltyEmployee,
} from './useInstantPenalties';

const dateFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { year: 'numeric', month: 'short', day: 'numeric' });
const currencyFmt = new Intl.NumberFormat('ar-EG-u-nu-latn', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

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
      return <XCircle className="size-4 text-[var(--text-muted)]" aria-hidden="true" />;
    default:
      return null;
  }
}

export function InstantPenaltiesPage() {
  const { toast } = useToast();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedTier, setSelectedTier] = useState<'all' | 'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended'>('all');
  const [activeModalTier, setActiveModalTier] = useState<'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended' | 'total' | null>(null);

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

  const [earlyWarningModalOpen, setEarlyWarningModalOpen] = useState(false);

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
    const rawPhone = emp?.phoneE164 ?? '';
    let cleanPhone = rawPhone.replace(/[^0-9]/g, '');
    if (cleanPhone.startsWith('01')) {
      cleanPhone = '20' + cleanPhone.substring(1);
    } else if (!cleanPhone.startsWith('20') && cleanPhone.length === 10) {
      cleanPhone = '20' + cleanPhone;
    }

    const name = p.employeeName ?? emp?.fullNameAr ?? 'الزميل العزيز';
    let text: string;
    if (p.status === 'suspended') {
      text = `*إشعار هام من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️\n\nالسلام عليكم ورحمة الله، أستاذ/ة ${name} 🌸\n\nنود إحاطتكم بأنه قد تم تعليق حسابكم مؤقتاً على السيستم بسبب تجاوز مهلة سداد غرامة الحضور المضاعفة (500 ج.م) ليوم ${p.workDate}.\n\n🤝 *تنويه هام:* جميع الغرامات المحصلة تُودع بالكامل في *صندوق الزمالة والتكافل* لدعم الزملاء والمساعدات الاجتماعية.\n\nيرجى مراجعة إدارة الموارد البشرية لإنهاء السداد ورفع التعليق فوراً.\n\nمع خالص التقدير والاحترام 🌺`;
    } else if (p.status === 'doubled') {
      text = `*تنبيه عاجل: غرامة حضور مضاعفة (500 ج.م)* ⚠️\n\nالسلام عليكم ورحمة الله، أستاذ/ة ${name} 🌸\n\nنود تذكيركم بأنه نظراً لانقضاء مهلة الـ 24 ساعة، تضاعفت غرامة الحضور ليوم ${p.workDate} لتصبح *500 ج.م*.\n\n⏰ يرجى سرعة السداد نقداً أو عبر إنستاباي لتفادي تعليق الحساب على السيستم.\n\n🤝 *نحيطكم علماً بأن 100% من حصيلة الغرامات تذهب لصندوق الزمالة والتكافل لدعم الزملاء.*\n\nمع تمنياتنا لكم بالتوفيق 🌺`;
    } else {
      text = `*إشعار تسجيل غرامة حضور فورية* ⏰\n\nالسلام عليكم ورحمة الله، أستاذ/ة ${name} 🌸\n\nتم تسجيل غرامة حضور وتأخير ليوم ${p.workDate} بمبلغ *${p.currentAmount} ج.م* (${p.lateMinutes} دقيقة تأخير).\n\n⏳ *المهلة النظامية:* متبقي على مهلة الـ 24 ساعة قبل مضاعفة الغرامة إلى 500 ج.م.\n\n💳 يمكنكم السداد نقداً أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.\n\n🤝 *جميع المبالغ المحصلة تذهب لصالح صندوق الزمالة والتكافل ولا تمثل أي ربح للإدارة.*\n\nشكراً لتعاونكم وحرصكم على الانضباط 🌺`;
    }

    if (cleanPhone) {
      window.open(`https://wa.me/${cleanPhone}?text=${encodeURIComponent(text)}`, '_blank');
    } else {
      window.open(`https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`, '_blank');
    }
  }

  function sendEmployeeRadarWhatsApp(emp: { employeeName: string; phone: string | null; count: number; totalAmount: number; dates: string[] }) {
    let cleanPhone = (emp.phone ?? '').replace(/[^0-9]/g, '');
    if (cleanPhone.startsWith('01')) {
      cleanPhone = '20' + cleanPhone.substring(1);
    } else if (!cleanPhone.startsWith('20') && cleanPhone.length === 10) {
      cleanPhone = '20' + cleanPhone;
    }
    const text = `*رسالة تقدير وتنبيه ودي من الموارد البشرية (أحلى شباب)* 🌸\n\nالسلام عليكم ورحمة الله، أستاذ/ة ${emp.employeeName} العزيز/ة 🌺\n\nنود لفت عنايتكم الكريمة إلى أنه تم رصد تكرار تأخير خلال الفترة الأخيرة بواقع (${emp.count} مرات).\n\nحرصاً منا على مصلحتكم وتفادياً لتراكم أي غرامات إضافية أو تعليق الحساب، نرجو التكرم بالحرص على الحضور بالموعد المحدد (10:00 ص)، ونحن جاهزون للاستماع لأي ظرف قد يواجهكم ومساعدتكم دائماً.\n\nتمنياتنا لكم بكل التوفيق والتميز! 🌟`;

    if (cleanPhone) {
      window.open(`https://wa.me/${cleanPhone}?text=${encodeURIComponent(text)}`, '_blank');
    } else {
      window.open(`https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`, '_blank');
    }
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

  // الوصول من إشعار غرامة → إبراز صف الغرامة نفسه في الجدول.
  const focusedId = useEntityFocus(rows.length > 0, 'focus', () => {
    setCheckFeedback('الغرامة المطلوبة غير ظاهرة ضمن الفلتر الحالي — امسح الفلاتر لعرضها.');
    if (checkFeedbackTimer.current) clearTimeout(checkFeedbackTimer.current);
    checkFeedbackTimer.current = setTimeout(() => setCheckFeedback(null), 8000);
  });

  const columns: DataTableColumn<(typeof rows)[number]>[] = [
    {
      key: 'employeeName',
      header: 'الموظف والإدارة',
      sortable: true,
      render: (p) => {
        const initials = p.employeeName
          ? p.employeeName
              .trim()
              .split(/\s+/)
              .slice(0, 2)
              .map((s) => s[0])
              .join('')
          : 'م';
        return (
          <div className="flex items-center gap-3 min-w-[180px]">
            <div className="size-9 rounded-full bg-primary/10 border border-primary/20 text-primary flex items-center justify-center font-bold text-xs shrink-0 select-none">
              {initials}
            </div>
            <div className="flex flex-col min-w-0">
              <span className="font-bold text-sm text-[var(--text-primary)] leading-snug truncate">{p.employeeName ?? '—'}</span>
              <div className="flex items-center gap-1.5 text-[11px] text-[var(--text-muted)] mt-0.5">
                {p.employeeCode && (
                  <span className="font-mono bg-[var(--surface-muted)] px-1.5 py-0.5 rounded text-[10px] text-[var(--text-secondary)]">{p.employeeCode}</span>
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
        <div className="flex items-center gap-1.5 text-xs whitespace-nowrap font-mono text-[var(--text-secondary)]">
          <Calendar className="size-3.5 text-[var(--text-muted)] shrink-0" aria-hidden="true" />
          <span>{p.workDate}</span>
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
            {isUnpunched || p.lateMinutes >= 420 ? (
              <span className="inline-flex items-center gap-1 w-fit rounded-md bg-rose-500/10 border border-rose-500/25 px-2 py-0.5 text-[11px] font-bold text-rose-600 dark:text-rose-400 whitespace-nowrap">
                <Clock className="size-3 text-rose-500" aria-hidden="true" />
                لم يسجل بصمة
              </span>
            ) : (
              <span className="font-bold font-mono text-sm text-amber-600 dark:text-amber-400 whitespace-nowrap">
                {p.lateMinutes} <span className="text-xs font-normal">دقيقة</span>
              </span>
            )}
            {isActualLate && <span className="text-[10px] text-amber-700/80 dark:text-amber-300/80 font-medium">تأخير حضور فعلي</span>}
            {isUnpunched && <span className="text-[10px] text-[var(--text-muted)] font-mono">تجاوز 11:00 ص</span>}
          </div>
        );
      },
    },
    {
      key: 'originalAmount',
      header: 'الغرامة الأصلية',
      render: (p) => (
        <span className="text-xs font-mono text-[var(--text-muted)] whitespace-nowrap bg-[var(--surface-muted)] px-2 py-1 rounded-md border border-[var(--border-subtle)]">
          {formatCurrency(p.originalAmount)}
        </span>
      ),
    },
    {
      key: 'currentAmount',
      header: 'المطلوب سداده',
      sortable: true,
      render: (p) => {
        const isDoubled = p.currentAmount > p.originalAmount;
        return (
          <div className="flex flex-col gap-0.5 whitespace-nowrap">
            <span
              className={`font-black font-mono text-base ${
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
              <span className="inline-flex items-center gap-0.5 text-[10px] font-bold text-red-600 dark:text-red-400">
                <Flame className="size-3" aria-hidden="true" /> مضاعف (يوم 2)
              </span>
            )}
          </div>
        );
      },
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (p) => {
        const isExempt =
          p.status === 'cancelled' &&
          (p.notes?.includes('إلغاء بأثر رجعي') ||
            p.notes?.includes('إلغاء تلقائي') ||
            p.notes?.includes('مأمورية') ||
            p.notes?.includes('إجازة') ||
            p.notes?.includes('قافلة') ||
            p.notes?.includes('فاندي') ||
            p.notes?.includes('المدير التنفيذي') ||
            p.notes?.includes('استثناء') ||
            p.notes?.includes('معفى'));
        return (
          <div className="flex items-center gap-1.5 whitespace-nowrap" title={p.notes ?? undefined}>
            <StatusIcon status={p.status} />
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
          const isExempt =
            p.notes?.includes('إلغاء بأثر رجعي') ||
            p.notes?.includes('إلغاء تلقائي') ||
            p.notes?.includes('مأمورية') ||
            p.notes?.includes('إجازة') ||
            p.notes?.includes('قافلة') ||
            p.notes?.includes('فاندي') ||
            p.notes?.includes('المدير التنفيذي') ||
            p.notes?.includes('استثناء') ||
            p.notes?.includes('معفى');
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
          <div className="flex items-center gap-2 whitespace-nowrap">
            <button
              type="button"
              className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 shadow-sm transition-all active:scale-95 disabled:opacity-50 whitespace-nowrap cursor-pointer"
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
              title="استلام من الموظف وإيداع في صندوق الزمالة والتكافل"
            >
              <Coins className="size-3.5 text-amber-300" aria-hidden="true" />
              <span>استلام وإيداع بالصندوق</span>
            </button>
            {p.status === 'suspended' && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold bg-amber-500/10 hover:bg-amber-500/20 text-amber-700 dark:text-amber-300 border border-amber-500/30 transition-all whitespace-nowrap cursor-pointer"
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
                className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold text-[var(--danger)] hover:bg-[var(--danger)]/10 border border-transparent hover:border-[var(--danger)]/20 transition-all whitespace-nowrap cursor-pointer"
                disabled={cancelPenalty.isPending}
                onClick={() => {
                  setCancelTarget({ id: p.id, name: p.employeeName ?? '' });
                  setCancelReason('');
                  setCancelDialogOpen(true);
                }}
                title="إلغاء الغرامة"
              >
                <XCircle className="size-3.5" aria-hidden="true" />
                <span>إلغاء</span>
              </button>
            )}
            {(p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended') && (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold bg-emerald-50 hover:bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800 transition-all whitespace-nowrap cursor-pointer"
                onClick={() => sendEmployeeWhatsAppAlert(p)}
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
    const totalAmount = rows.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
    const pendingRows = rows.filter((r) => r.status === 'pending_payment' || r.status === 'doubled' || r.status === 'suspended');
    const paidRows = rows.filter((r) => r.status === 'paid');
    printReport(
      [
        {
          title: 'الغرامات الفورية للتأخير',
          subtitle: `${rows.length} غرامة — إجمالي المبالغ المطلوبة: ${formatCurrency(totalAmount)}`,
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
      [
        { label: 'إجمالي الغرامات', value: rows.length.toString() },
        { label: 'بانتظار السداد', value: pendingRows.length.toString() },
        { label: 'مدفوعة', value: paidRows.length.toString() },
        { label: 'إجمالي المبالغ', value: formatCurrency(totalAmount) },
      ],
    );
  };

  const handleExportModalTierPdf = (tier: string) => {
    const all = penalties.data ?? [];
    if (tier === 'pending') {
      const items = pendingEmployees.data ?? [];
      printReport(
        [
          {
            title: 'كشف الموظفين المطالبين بسداد غرامات التأخير',
            subtitle: `${items.length} موظف مطالب بالسداد — إجمالي المطلوب: ${formatCurrency(stats.totalOwed)}`,
            table: {
              headers: ['الموظف', 'الكود', 'الإدارة', 'عدد الغرامات', 'المبلغ المطلوب', 'حالة الحساب'],
              rows: items.map((e) => [
                e.employeeName ?? '—',
                e.employeeCode ?? '—',
                e.departmentName ?? '—',
                String(e.pendingCount),
                formatCurrency(e.totalAmount),
                e.isSuspended ? 'معلق عن العمل' : 'نشط',
              ]),
            },
          },
        ],
        'كشف المطالبين بالسداد',
        [
          { label: 'إجمالي المطالبين', value: String(items.length) },
          { label: 'المعلقون عن العمل', value: String(stats.suspendedCount) },
          { label: 'المبالغ المطلوبة', value: formatCurrency(stats.totalOwed) },
        ],
      );
      return;
    }

    if (tier === 'suspended') {
      const items = all.filter((p) => p.status === 'suspended');
      const totalAmount = items.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
      printReport(
        [
          {
            title: 'كشف الموظفين الموقوفين عن العمل (اليوم الثالث)',
            subtitle: `${items.length} موظف موقوف لعدم سداد الغرامة — إجمالي المطلوب: ${formatCurrency(totalAmount)}`,
            table: {
              headers: ['الموظف', 'الكود', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب (500 ج.م)', 'الحالة'],
              rows: items.map((p) => [
                p.employeeName ?? '—',
                p.employeeCode ?? '—',
                p.departmentName ?? '—',
                p.workDate,
                `${p.lateMinutes} دقيقة`,
                formatCurrency(p.originalAmount),
                formatCurrency(p.currentAmount),
                'معلق عن العمل',
              ]),
            },
          },
        ],
        'كشف الموقوفين عن العمل',
        [
          { label: 'الموظفون الموقوفون', value: String(items.length) },
          { label: 'إجمالي المبالغ المستحقة', value: formatCurrency(totalAmount) },
        ],
      );
      return;
    }

    let filtered = all;
    let tierTitle = 'البيان الشامل وتفنيط الغرامات الفورية';
    if (tier === 'tier-20') {
      filtered = all.filter((p) => p.lateMinutes > 15 && p.lateMinutes <= 30);
      tierTitle = 'كشف غرامات 20 ج.م (تأخير 16-30 دقيقة)';
    } else if (tier === 'tier-50') {
      filtered = all.filter((p) => p.lateMinutes > 30 && p.lateMinutes <= 60);
      tierTitle = 'كشف غرامات 50 ج.م (تأخير 31-60 دقيقة)';
    } else if (tier === 'tier-150') {
      filtered = all.filter((p) => p.lateMinutes > 60);
      tierTitle = 'كشف غرامات 150 ج.م (تأخير بعد 11:00 ص)';
    } else if (tier === 'doubled') {
      filtered = all.filter((p) => p.status === 'doubled');
      tierTitle = 'كشف الغرامات المضاعفة 500 ج.م (اليوم الثاني)';
    }

    const total = filtered.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
    printReport(
      [
        {
          title: tierTitle,
          subtitle: `${filtered.length} غرامة — إجمالي المبالغ: ${formatCurrency(total)}`,
          table: {
            headers: ['الموظف', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب', 'التصعيد', 'الحالة'],
            rows: filtered.map((p) => [
              p.employeeName ?? '—',
              p.departmentName ?? '—',
              p.workDate,
              `${p.lateMinutes} دقيقة`,
              formatCurrency(p.originalAmount),
              formatCurrency(p.currentAmount),
              INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel,
              INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status,
            ]),
          },
        },
      ],
      tierTitle,
      [
        { label: 'عدد الغرامات', value: String(filtered.length) },
        { label: 'إجمالي المبالغ', value: formatCurrency(total) },
      ],
    );
  };

  // ─── ملخص أسبوعي عبر واتساب للمدير (مجاني 100%) ─────────────────────

  const sendWeeklyWhatsAppSummary = () => {
    const items = penalties.data ?? [];
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const weekAgoIso = weekAgo.toISOString().slice(0, 10);

    const thisWeek = items.filter((p) => p.workDate >= weekAgoIso);
    const pendingThisWeek = thisWeek.filter((p) => p.status === 'pending_payment');
    const paidThisWeek = thisWeek.filter((p) => p.status === 'paid');
    const doubledThisWeek = thisWeek.filter((p) => p.status === 'doubled');
    const suspendedThisWeek = thisWeek.filter((p) => p.status === 'suspended');
    const cancelledThisWeek = thisWeek.filter((p) => p.status === 'cancelled');

    const totalAmount = thisWeek.reduce((s, p) => s + p.currentAmount, 0);
    const paidAmount = paidThisWeek.reduce((s, p) => s + p.currentAmount, 0);
    const pendingAmount = pendingThisWeek.reduce((s, p) => s + p.currentAmount, 0);

    const collectionRate = thisWeek.length > 0 ? Math.round((paidThisWeek.length / Math.max(1, thisWeek.length - cancelledThisWeek.length)) * 100) : 0;

    // أكثر 3 موظفين تأخراً
    const empCounts = new Map<string, { name: string; count: number }>();
    for (const p of thisWeek) {
      if (p.status === 'cancelled') continue;
      const existing = empCounts.get(p.employeeId) ?? { name: p.employeeName ?? 'موظف', count: 0 };
      existing.count++;
      empCounts.set(p.employeeId, existing);
    }
    const topLate = [...empCounts.values()].sort((a, b) => b.count - a.count).slice(0, 3);

    const fundBalance = fundSummary.data?.currentBalance ?? 0;

    const text = `*📊 التقرير الأسبوعي لغرامات الحضور — أحلى شباب*\n*الفترة:* ${weekAgoIso} → ${cairoTodayIso()}\n\n📌 *الملخص:*\n• إجمالي الغرامات: ${thisWeek.length} غرامة\n• إجمالي المبالغ: ${formatCurrency(totalAmount)}\n• المدفوع: ${paidThisWeek.length} (${formatCurrency(paidAmount)})\n• بانتظار السداد: ${pendingThisWeek.length} (${formatCurrency(pendingAmount)})\n• المضاعفة: ${doubledThisWeek.length}\n• المعلّقة: ${suspendedThisWeek.length}\n• الملغاة (أعذار مقبولة): ${cancelledThisWeek.length}\n\n📈 *نسبة التحصيل:* ${collectionRate}%\n💰 *رصيد صندوق الزمالة:* ${formatCurrency(fundBalance)}\n\n${topLate.length > 0 ? `⚠️ *الأكثر تأخراً هذا الأسبوع:*\n${topLate.map((e, i) => `${i + 1}. ${e.name} — ${e.count} مرات`).join('\n')}\n` : '✅ لا يوجد تكرار تأخير ملحوظ هذا الأسبوع.\n'}\n🤝 *تذكير:* جميع حصيلة الغرامات تذهب كاملة لصندوق الزمالة والتكافل لدعم الزملاء.\n\n_تقرير آلي من منظومة أحلى شباب — مجاني بدون رسوم_ ✨`;

    window.open(`https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`, '_blank');
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
                  setCheckFeedback(res.message);
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

      {/* ─── مستحقون للتعليق — بانتظار قرار بشري (0554) ───────────── */}
      <PendingSuspensionsCard />

      {/* ─── ملخص + صناديق شرائح الغرامات ─────────────────────────── */}
      <div className="space-y-3">
        <div className="flex flex-wrap items-center gap-2 text-xs">
          {stats.pendingCount > 0 && (
            <button
              type="button"
              onClick={() => setSelectedTier((prev) => (prev === 'pending' ? 'all' : 'pending'))}
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold transition-all cursor-pointer ${
                selectedTier === 'pending'
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
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold transition-all cursor-pointer ${
                selectedTier === 'suspended'
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
          {collectionStats.totalCount > 0 && (
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-bold ${
                collectionStats.rate >= 80
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

        <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
          {[
            {
              key: 'tier-20' as const,
              label: '20 ج.م',
              badge: '16-30 دقيقة',
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
              badge: '31-60 دقيقة',
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
              badge: '> 11:00 ص / عدم بصمة',
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
            الحضور يبدأ 10:00 ص: من 1-15 دقيقة = سماح بدون خصم (0 ج.م) | حتى 10:30 (16-30 دقيقة) = 20 ج.م | حتى 11:00 (31-60 دقيقة) = 50 ج.م | حتى 12:00 (61-120
            دقيقة) = 150 ج.م.
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
          <span>Excel</span>
        </button>
        <button type="button" className="btn-secondary font-medium" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
          <Printer className="size-4 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
          <span>تصدير PDF</span>
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
            <div className="flex items-center gap-3 rounded-xl border border-blue-300 dark:border-blue-700 bg-blue-50 dark:bg-blue-950/20 p-3">
              <span className="text-xs font-bold text-blue-700 dark:text-blue-400">تم تحديد {selectedIds.size} غرامة</span>
              <div className="flex-1" />
              <button
                type="button"
                onClick={async () => {
                  const ids = [...selectedIds];
                  const count = await bulkConfirm.mutateAsync({ penaltyIds: ids });
                  toast({ message: `تم تأكيد ${count} غرامة`, tone: 'success' });
                  setSelectedIds(new Set());
                }}
                disabled={bulkConfirm.isPending}
                className="btn-primary text-xs !py-1.5 !px-3"
              >
                {bulkConfirm.isPending ? 'جارٍ…' : `تأكيد دفع (${selectedIds.size})`}
              </button>
              <button
                type="button"
                onClick={() => setBulkCancelOpen(true)}
                className="px-3 py-1.5 text-xs font-bold text-red-600 dark:text-red-400 border border-red-300 dark:border-red-700 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
              >
                إلغاء جماعي ({selectedIds.size})
              </button>
              <button
                type="button"
                onClick={() => setSelectedIds(new Set())}
                className="px-2 py-1.5 text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)]"
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
            minWidth="920px"
            maxHeight="75vh"
            columns={columns}
            selectable
            selectedKeys={selectedIds}
            onSelectionChange={setSelectedIds}
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
      {activeModalTier && (
        <DialogOverlay
          title={
            activeModalTier === 'pending'
              ? 'كشف الموظفين المطالبين بالدفع حالياً'
              : activeModalTier === 'suspended'
                ? 'كشف الموظفين الموقوفين عن العمل (اليوم الثالث)'
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
            {/* ─── شريط التصدير السريع للكشف ─── */}
            <div className="flex items-center justify-between gap-3 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)]/60">
              <div className="flex items-center gap-2">
                <FileSpreadsheet className="size-4 text-emerald-600 dark:text-emerald-400" />
                <span className="text-xs font-bold text-[var(--text-secondary)]">كشف معتمد جاهز للتصدير والطباعة</span>
              </div>
              <button
                type="button"
                className="btn-secondary text-xs font-bold flex items-center gap-1.5 !py-1.5 !px-3 shadow-xs hover:border-emerald-500/50"
                onClick={() => handleExportModalTierPdf(activeModalTier)}
                title="تصدير هذا الكشف كملف PDF"
              >
                <Printer className="size-3.5 text-emerald-600 dark:text-emerald-400" />
                <span>تصدير هذا الكشف PDF</span>
              </button>
            </div>

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
                            (p) => p.employeeId === e.employeeId && (p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended'),
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
                                        const confirmMsg =
                                          firstPenalty.status === 'suspended'
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

                {/* أزرار أسفل المودال */}
                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
                  <button
                    type="button"
                    className="btn-secondary text-xs flex items-center gap-1.5"
                    onClick={() => {
                      const cols: ExportColumn<PendingPenaltyEmployee>[] = [
                        { key: 'employee', header: 'الموظف', get: (e) => e.employeeName },
                        { key: 'code', header: 'الكود', get: (e) => e.employeeCode },
                        { key: 'department', header: 'الإدارة', get: (e) => e.departmentName },
                        { key: 'count', header: 'عدد الغرامات', get: (e) => e.pendingCount },
                        { key: 'amount', header: 'إجمالي المبلغ', get: (e) => e.totalAmount },
                        { key: 'suspended', header: 'معلّق عن العمل', get: (e) => (e.isSuspended ? 'نعم' : 'لا') },
                      ];
                      downloadCsv(`pending-penalty-employees-${cairoTodayIso()}.csv`, toCsv(cols, pendingEmployees.data ?? []));
                    }}
                    disabled={(pendingEmployees.data ?? []).length === 0}
                  >
                    <FileSpreadsheet className="size-4" />
                    <span>تصدير كشف المطالبين Excel</span>
                  </button>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      className="btn-primary !py-1.5 !px-3 text-xs"
                      onClick={() => {
                        setSelectedTier('pending');
                        setActiveModalTier(null);
                      }}
                    >
                      تصفية الجدول بهؤلاء الموظفين ←
                    </button>
                    <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={() => setActiveModalTier(null)}>
                      إغلاق
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* 2. كشف المعلقين عن العمل */}
            {activeModalTier === 'suspended' && (
              <div className="space-y-4">
                <div className="rounded-xl border border-red-500/30 bg-red-50/60 dark:bg-red-950/30 p-3.5 text-xs text-red-800 dark:text-red-300">
                  <p className="font-bold flex items-center gap-1.5">
                    <Ban className="size-4 text-red-600" />
                    تنبيه إيقاف الحسابات ومباشرة العمل (اليوم الثالث):
                  </p>
                  <p className="mt-1">
                    تم إيقاف حسابات هؤلاء الزملاء برمجياً بسبب عدم سداد غرامة الـ 500 ج.م المضاعفة. لا يمكنهم تسجيل الدخول على المنظومة حتى يتم استلام المبلغ
                    وتوريده لصندوق الزمالة والتكافل.
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
                            const suspendedPenalty = (penalties.data ?? []).find((p) => p.employeeId === e.employeeId && p.status === 'suspended');
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

                {/* أزرار أسفل المودال */}
                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
                  <button
                    type="button"
                    className="btn-secondary text-xs flex items-center gap-1.5"
                    onClick={() => {
                      const suspendedList = (pendingEmployees.data ?? []).filter((e) => e.isSuspended);
                      const cols: ExportColumn<PendingPenaltyEmployee>[] = [
                        { key: 'employee', header: 'الموظف', get: (e) => e.employeeName },
                        { key: 'code', header: 'الكود', get: (e) => e.employeeCode },
                        { key: 'department', header: 'الإدارة', get: (e) => e.departmentName },
                        { key: 'count', header: 'عدد الغرامات', get: (e) => e.pendingCount },
                        { key: 'amount', header: 'إجمالي المبلغ', get: (e) => e.totalAmount },
                      ];
                      downloadCsv(`suspended-employees-${cairoTodayIso()}.csv`, toCsv(cols, suspendedList));
                    }}
                    disabled={(pendingEmployees.data ?? []).filter((e) => e.isSuspended).length === 0}
                  >
                    <FileSpreadsheet className="size-4" />
                    <span>تصدير كشف المعلقين Excel</span>
                  </button>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      className="btn-primary !py-1.5 !px-3 text-xs"
                      onClick={() => {
                        setSelectedTier('suspended');
                        setActiveModalTier(null);
                      }}
                    >
                      تصفية الجدول بالمعلقين ←
                    </button>
                    <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={() => setActiveModalTier(null)}>
                      إغلاق
                    </button>
                  </div>
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
                      <span className="text-[10px] bg-amber-100 dark:bg-amber-900/50 text-amber-700 dark:text-amber-300 px-1.5 py-0.5 rounded font-mono">
                        31-60 د
                      </span>
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
                      <span className="text-[10px] bg-orange-100 dark:bg-orange-900/50 text-orange-700 dark:text-orange-300 px-1.5 py-0.5 rounded font-mono">
                        &gt;11:00ص
                      </span>
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
                      <span className="text-[10px] bg-purple-100 dark:bg-purple-900/50 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 rounded font-mono">
                        اليوم الثاني
                      </span>
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
                  <div className="flex items-center gap-2">
                    <Link
                      to="/admin/fellowship-fund"
                      className="btn-primary !py-2 !px-4 text-xs font-bold whitespace-nowrap bg-emerald-600 hover:bg-emerald-700"
                      onClick={() => setActiveModalTier(null)}
                    >
                      فتح صندوق الزمالة ↗
                    </Link>
                    <button type="button" className="btn-secondary !py-2 !px-4 text-xs font-bold whitespace-nowrap" onClick={() => setActiveModalTier(null)}>
                      إغلاق
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* 4. تفاصيل الشرائح المحددة (20 / 50 / 150 / 500) */}
            {(activeModalTier === 'tier-20' || activeModalTier === 'tier-50' || activeModalTier === 'tier-150' || activeModalTier === 'tier-500') &&
              (() => {
                const tierConfig =
                  activeModalTier === 'tier-20'
                    ? {
                        label: 'غرامات 20 ج.م',
                        desc: 'الحضور من 10:16 ص إلى 10:30 ص (تأخير 16-30 دقيقة)',
                        stats: tierStats.tier20,
                        color: 'text-sky-600 dark:text-sky-400',
                      }
                    : activeModalTier === 'tier-50'
                      ? {
                          label: 'غرامات 50 ج.م',
                          desc: 'الحضور من 10:31 ص إلى 11:00 ص (تأخير 31-60 دقيقة)',
                          stats: tierStats.tier50,
                          color: 'text-amber-600 dark:text-amber-400',
                        }
                      : activeModalTier === 'tier-150'
                        ? {
                            label: 'غرامات 150 ج.م',
                            desc: 'الحضور بعد 11:00 ص أو عدم تسجيل البصمة',
                            stats: tierStats.tier150,
                            color: 'text-orange-600 dark:text-orange-400',
                          }
                        : {
                            label: 'غرامات مضاعفة 500 ج.م',
                            desc: 'عدم سداد غرامة اليوم السابق حتى 10:00 ص اليوم التالي',
                            stats: tierStats.tier500,
                            color: 'text-purple-600 dark:text-purple-400',
                          };

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
                        <span className="text-lg font-black text-emerald-600 dark:text-emerald-400 font-mono">{tierConfig.stats.paidCount}</span>
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
                                  <td className="p-3 whitespace-nowrap text-[var(--text-muted)]">{dateFormatter.format(new Date(p.workDate + 'T00:00:00'))}</td>
                                  <td className="p-3 text-center">
                                    <span className="font-bold text-amber-600 dark:text-amber-400">{p.lateMinutes} د</span>
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
                                          const confirmMsg =
                                            p.status === 'suspended'
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
                                      <span className="text-[11px] text-emerald-600 dark:text-emerald-400 font-bold">✓ تم الإيداع</span>
                                    ) : (
                                      <span className="text-[11px] text-[var(--text-muted)]">ملغاة</span>
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
                        <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={() => setActiveModalTier(null)}>
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

      {/* ─── الطعون المعلقة ────────────────────────────────────────── */}
      {disputes.data && disputes.data.length > 0 && (
        <section className="space-y-3">
          <div className="flex items-center gap-2">
            <MessageSquare className="size-4 text-blue-500" />
            <h2 className="text-sm font-black text-[var(--text-primary)]">طعون معلقة — تحتاج مراجعة</h2>
            <span className="rounded-full bg-blue-100 dark:bg-blue-950/50 px-2 py-0.5 text-[10px] font-black text-blue-700 dark:text-blue-400">
              {disputes.data.length}
            </span>
          </div>

          <div className="space-y-2">
            {disputes.data.map((d) => (
              <div
                key={d.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-blue-200 dark:border-blue-800/40 bg-blue-50/50 dark:bg-blue-950/15 p-4"
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-black text-[var(--text-primary)]">{d.employee_name}</span>
                    {d.department && <span className="text-[11px] text-[var(--text-muted)]">— {d.department}</span>}
                  </div>
                  <p className="text-xs text-[var(--text-muted)] mt-0.5">
                    غرامة يوم {dateFormatter.format(new Date(d.penalty_date + 'T00:00:00'))} — {formatCurrency(d.penalty_amount)}
                  </p>
                  <p className="text-xs text-[var(--text-secondary)] mt-1 bg-[var(--surface-muted)]/50 rounded-lg px-2.5 py-1.5 inline-block">"{d.reason}"</p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <button
                    type="button"
                    onClick={() => {
                      setReviewTarget({ id: d.id, employeeName: d.employee_name, reason: d.reason });
                      setReviewNote('');
                    }}
                    className="btn-primary text-xs !py-1.5 !px-3"
                  >
                    مراجعة
                  </button>
                </div>
              </div>
            ))}
          </div>
        </section>
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

      {/* ─── نافذة الإلغاء الجماعي ────────────────────────────────── */}
      <InputDialog
        open={bulkCancelOpen}
        title="إلغاء جماعي للغرامات"
        message={`إلغاء ${selectedIds.size} غرامة محددة — اذكر السبب:`}
        inputLabel="سبب الإلغاء الجماعي"
        inputPlaceholder="سبب الإلغاء…"
        inputValue={bulkCancelReason}
        onInputChange={setBulkCancelReason}
        confirmLabel={`إلغاء ${selectedIds.size} غرامة`}
        tone="danger"
        loading={bulkCancel.isPending}
        error={bulkCancel.isError ? safeErrorMessage(bulkCancel.error) : null}
        onConfirm={async () => {
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
        onCancel={() => {
          bulkCancel.reset();
          setBulkCancelOpen(false);
          setBulkCancelReason('');
        }}
      />

      {/* ─── نافذة مراجعة الطعن ──────────────────────────────────────── */}
      {reviewTarget && (
        <DialogOverlay onClose={() => setReviewTarget(null)} title={`مراجعة طعن — ${reviewTarget.employeeName}`}>
          <div className="space-y-4">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/30 p-4">
              <p className="text-xs text-[var(--text-muted)]">سبب الطعن:</p>
              <p className="text-sm font-bold text-[var(--text-primary)] mt-1">{reviewTarget.reason}</p>
            </div>

            <div>
              <label className="block text-xs font-bold text-[var(--text-primary)] mb-1.5">ملاحظات المراجعة (اختياري)</label>
              <textarea
                value={reviewNote}
                onChange={(e) => setReviewNote(e.target.value)}
                placeholder="أي ملاحظات على قرار المراجعة…"
                rows={3}
                className="input-field w-full text-sm resize-none"
              />
            </div>

            {reviewDispute.isError && <p className="text-xs text-[var(--danger)]">{safeErrorMessage(reviewDispute.error)}</p>}

            <div className="flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setReviewTarget(null)}
                className="px-4 py-2 text-xs font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
              >
                إلغاء
              </button>
              <button
                type="button"
                onClick={() => {
                  reviewDispute.mutate(
                    { disputeId: reviewTarget.id, status: 'rejected', note: reviewNote.trim() || undefined },
                    { onSuccess: () => setReviewTarget(null) },
                  );
                }}
                disabled={reviewDispute.isPending}
                className="px-4 py-2 text-xs font-black text-red-600 dark:text-red-400 border border-red-300 dark:border-red-700 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
              >
                رفض الطعن
              </button>
              <button
                type="button"
                onClick={() => {
                  reviewDispute.mutate(
                    { disputeId: reviewTarget.id, status: 'approved', note: reviewNote.trim() || 'قُبل الطعن' },
                    { onSuccess: () => setReviewTarget(null) },
                  );
                }}
                disabled={reviewDispute.isPending}
                className="btn-primary text-xs !py-2 !px-4"
              >
                {reviewDispute.isPending ? 'جارٍ…' : 'قبول الطعن'}
              </button>
            </div>
          </div>
        </DialogOverlay>
      )}

      {/* ─── نافذة كشف رادار الإنذار المبكر والتنبيهات ──────────────── */}
      {earlyWarningModalOpen && (
        <DialogOverlay
          title="رادار الإنذار المبكر — الزملاء الأكثر عرضة للمضاعفة أو التعليق"
          onClose={() => setEarlyWarningModalOpen(false)}
          maxWidth="max-w-2xl"
        >
          <div className="space-y-4">
            <p className="text-xs text-[var(--text-muted)] -mt-2">تنبيهات ودية تشجيعية مجانية 100% عبر الواتساب لتشجيع الانضباط قبل تفاقم الغرامات</p>

            <div className="overflow-y-auto max-h-[60vh] space-y-2.5 pr-1">
              {earlyWarningList.length === 0 ? (
                <div className="text-center py-8 text-[var(--text-muted)] text-sm">ممتاز! لا يوجد أي زميل لديه تكرار تأخير حالياً.</div>
              ) : (
                earlyWarningList.map((emp) => (
                  <div
                    key={emp.employeeId}
                    className="p-3.5 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-sm text-[var(--text-primary)]">{emp.employeeName}</span>
                        {emp.isSuspended && (
                          <span className="text-[10px] font-black px-2 py-0.5 rounded-full bg-red-500/15 text-red-600 border border-red-500/30">
                            معلّق عن العمل
                          </span>
                        )}
                        <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-700 dark:text-amber-300">
                          {emp.count} غرامات مسجلة
                        </span>
                      </div>
                      <p className="text-xs text-[var(--text-muted)] mt-1">
                        إجمالي المبالغ: {formatCurrency(emp.totalAmount)} • تواريخ: {emp.dates.slice(0, 3).join('، ')}
                        {emp.dates.length > 3 ? ` و+${emp.dates.length - 3} أخرى` : ''}
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={() => sendEmployeeRadarWhatsApp(emp)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg shadow-xs transition-all cursor-pointer whitespace-nowrap self-start sm:self-auto"
                      title="إرسال رسالة نصيحة وتشجيع ودية عبر الواتساب (مجاناً)"
                    >
                      <MessageCircle className="size-3.5" />
                      <span>إرسال تنبيه ودي</span>
                    </button>
                  </div>
                ))
              )}
            </div>

            <div className="pt-3 border-t border-[var(--border)] flex items-center justify-between text-xs text-[var(--text-muted)]">
              <span>💡 جميع رسائل الواتساب مجانية بالكامل ومفتوحة عبر الويب والتطبيق مباشرة بدون أي اشتراكات.</span>
              <button type="button" onClick={() => setEarlyWarningModalOpen(false)} className="btn-secondary text-xs !py-1.5 !px-3">
                إغلاق
              </button>
            </div>
          </div>
        </DialogOverlay>
      )}
    </div>
  );
}
