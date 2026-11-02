import { useState, useMemo } from 'react';
import {
  Ban,
  CheckCircle2,
  AlertTriangle,
  RotateCcw,
  Coins,
  MessageCircle,
  Phone,
  Building,
  UserCheck,
  Search,
  Filter,
  Copy,
  Check,
  Sparkles,
} from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { PageHeader } from '../../ui/PageHeader';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ListSkeleton } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useToast } from '../../ui/Toast';
import {
  useSuspendedEmployeesAdmin,
  useLiftEmployeeSuspensionAdmin,
  useRevertDoubledPenalty,
  useConfirmInstantPenaltyPayment,
  type SuspendedEmployeeAdmin,
} from './useInstantPenalties';

const currencyFmt = new Intl.NumberFormat('ar-EG-u-nu-latn', {
  style: 'currency',
  currency: 'EGP',
  maximumFractionDigits: 0,
});

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '0 ج.م';
  return currencyFmt.format(amount);
}

function formatArabicDate(dateStr: string): string {
  try {
    const [y, m, d] = dateStr.split('-').map(Number);
    const date = new Date(y, m - 1, d);
    return date.toLocaleDateString('ar-EG-u-nu-latn', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
  } catch {
    return dateStr;
  }
}

function formatLateMinutes(mins: number): string {
  if (mins >= 120) return 'ساعتان (120 دقيقة)';
  if (mins === 60) return 'ساعة (60 دقيقة)';
  return `${mins} دقيقة`;
}

export function SuspendedEmployeesPage() {
  const queryClient = useQueryClient();
  const { data: employees, isLoading, error, refetch } = useSuspendedEmployeesAdmin();
  const liftSuspension = useLiftEmployeeSuspensionAdmin();
  const revertPenalty = useRevertDoubledPenalty();
  const confirmPayment = useConfirmInstantPenaltyPayment();
  const { toast } = useToast();

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'suspended_only' | 'doubled_only'>('all');
  const [copiedPhone, setCopiedPhone] = useState<string | null>(null);

  // استبعاد فوري للموظفين الذين تم رفع الإيقاف عنهم لمنع أي تأخير في الاختفاء
  const [dismissedEmployeeIds, setDismissedEmployeeIds] = useState<Set<string>>(new Set());

  // Dialogs
  const [selectedEmp, setSelectedEmp] = useState<SuspendedEmployeeAdmin | null>(null);
  const [liftDialogOpen, setLiftDialogOpen] = useState(false);
  const [liftReason, setLiftReason] = useState('');
  const [liftLoading, setLiftLoading] = useState(false);

  // إرجاع غرامة مفردة
  const [revertDialogOpen, setRevertDialogOpen] = useState(false);
  const [revertPenaltyDetails, setRevertPenaltyDetails] = useState<{
    id: string;
    employeeName: string;
    workDate: string;
    lateMinutes: number;
    currentAmount: number;
    originalAmount: number;
  } | null>(null);
  const [revertReason, setRevertReason] = useState('');
  const [revertLoading, setRevertLoading] = useState(false);

  // إرجاع كافة غرامات الموظف دفعة واحدة
  const [revertAllTarget, setRevertAllTarget] = useState<SuspendedEmployeeAdmin | null>(null);
  const [revertAllLoading, setRevertAllLoading] = useState(false);

  // سداد غرامة
  const [paymentDialogOpen, setPaymentDialogOpen] = useState(false);
  const [paymentPenaltyId, setPaymentPenaltyId] = useState<string | null>(null);
  const [paymentPenaltyAmount, setPaymentPenaltyAmount] = useState<number>(0);
  const [paymentNotes, setPaymentNotes] = useState('');
  const [paymentLoading, setPaymentLoading] = useState(false);

  const rawList = employees ?? [];

  // تصفية وبحث
  const filteredList = useMemo(() => {
    return rawList.filter((emp) => {
      // 0) التحقق من عدم الاستبعاد اللحظي
      if (dismissedEmployeeIds.has(emp.employeeId)) return false;

      // 1) فلتر الحالة
      const isActuallySuspended = emp.status === 'suspended' || !emp.isActive;
      if (statusFilter === 'suspended_only' && !isActuallySuspended) return false;
      if (statusFilter === 'doubled_only' && isActuallySuspended) return false;

      // 2) فلتر البحث
      if (!searchQuery.trim()) return true;
      const q = searchQuery.trim().toLowerCase();
      const matchName = emp.employeeName.toLowerCase().includes(q);
      const matchDept = emp.departmentName?.toLowerCase().includes(q) ?? false;
      const matchCode = emp.employeeCode?.toLowerCase().includes(q) ?? false;
      const matchPhone = emp.phone?.includes(q) ?? false;
      const matchJob = emp.jobTitle?.toLowerCase().includes(q) ?? false;
      return matchName || matchDept || matchCode || matchPhone || matchJob;
    });
  }, [rawList, statusFilter, searchQuery, dismissedEmployeeIds]);

  const activeDisplayList = useMemo(() => {
    return rawList.filter((e) => !dismissedEmployeeIds.has(e.employeeId));
  }, [rawList, dismissedEmployeeIds]);

  const totalCurrent = activeDisplayList.reduce((s, e) => s + (e.totalCurrentDue || 0), 0);
  const totalOriginal = activeDisplayList.reduce((s, e) => s + (e.totalOriginalDue || 0), 0);
  const actuallySuspendedCount = activeDisplayList.filter((e) => e.status === 'suspended' || !e.isActive).length;
  const doubledOnlyCount = activeDisplayList.length - actuallySuspendedCount;

  // نسخ الهاتف للحافظة
  const copyPhone = (phone: string) => {
    navigator.clipboard.writeText(phone);
    setCopiedPhone(phone);
    setTimeout(() => setCopiedPhone(null), 2000);
  };

  // رفع الإيقاف إدارياً وتفعيل الحساب
  const handleLiftSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedEmp) return;
    const empId = selectedEmp.employeeId;
    const empName = selectedEmp.employeeName;
    setLiftLoading(true);
    try {
      await liftSuspension.mutateAsync({
        employeeId: empId,
        reason: liftReason.trim() || undefined,
      });

      // إزالة فورية من الكاش والحالة المحلية
      setDismissedEmployeeIds((prev) => new Set(prev).add(empId));
      queryClient.setQueriesData<SuspendedEmployeeAdmin[]>({ queryKey: ['suspended-employees-admin'] }, (old) =>
        old ? old.filter((item) => item.employeeId !== empId) : [],
      );

      toast({
        message: `تم رفع الإيقاف عن الزميل ${empName} وإعادة تفعيل حسابه بنجاح`,
        tone: 'success',
      });
      setLiftDialogOpen(false);
      setLiftReason('');
      setSelectedEmp(null);

      // تحديث فوري لباقي الكاشات بالتوازي
      await Promise.allSettled([
        queryClient.refetchQueries({ queryKey: ['suspended-employees-admin'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties-pending-employees'] }),
        queryClient.refetchQueries({ queryKey: ['employees'] }),
      ]);
    } catch {
      // main.tsx يعرض رسالة الخطأ تلقائياً عبر safeErrorMessage
    } finally {
      setLiftLoading(false);
    }
  };

  // إرجاع غرامة مفردة للأصل
  const handleRevertSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!revertPenaltyDetails) return;
    const { id: penaltyId, employeeName, originalAmount } = revertPenaltyDetails;
    setRevertLoading(true);
    try {
      await revertPenalty.mutateAsync({
        penaltyId,
        reason: revertReason.trim() || undefined,
      });

      // تحديث تفاؤلي فوري في الكاش
      queryClient.setQueriesData<SuspendedEmployeeAdmin[]>({ queryKey: ['suspended-employees-admin'] }, (old) => {
        if (!old) return [];
        return old
          .map((emp) => {
            const hasPen = emp.penalties.some((p) => p.id === penaltyId);
            if (!hasPen) return emp;
            const updatedPens = emp.penalties.map((p) =>
              p.id === penaltyId ? { ...p, currentAmount: p.originalAmount, status: 'pending_payment', escalationLevel: 'initial' } : p,
            );
            const newTotalCurrent = updatedPens.reduce((s, p) => s + p.currentAmount, 0);
            const has500 = updatedPens.some((p) => p.currentAmount >= 500);
            return {
              ...emp,
              penalties: updatedPens,
              totalCurrentDue: newTotalCurrent,
              has500Penalty: has500,
            };
          })
          .filter((emp) => emp.status === 'suspended' || !emp.isActive || emp.has500Penalty);
      });

      toast({
        message: `تم إرجاع غرامة الزميل ${employeeName} إلى أصلها (${formatCurrency(originalAmount)}) بنجاح`,
        tone: 'success',
      });
      setRevertDialogOpen(false);
      setRevertReason('');
      setRevertPenaltyDetails(null);

      // تحديث السيرفر
      await Promise.allSettled([
        queryClient.refetchQueries({ queryKey: ['suspended-employees-admin'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties-pending-employees'] }),
      ]);
    } catch {
      // main.tsx يعرض رسالة الخطأ تلقائياً
    } finally {
      setRevertLoading(false);
    }
  };

  // إرجاع كافة الغرامات للموظف للأصل
  const handleRevertAllSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!revertAllTarget) return;
    const target = revertAllTarget;
    setRevertAllLoading(true);
    try {
      for (const pen of target.penalties) {
        if (pen.currentAmount > pen.originalAmount) {
          await revertPenalty.mutateAsync({
            penaltyId: pen.id,
            reason: revertReason.trim() || 'إرجاع إداري جماعي للموظف الموقوف',
          });
        }
      }

      // تحديث تفاؤلي للكاش
      queryClient.setQueriesData<SuspendedEmployeeAdmin[]>({ queryKey: ['suspended-employees-admin'] }, (old) => {
        if (!old) return [];
        return old
          .map((emp) => {
            if (emp.employeeId !== target.employeeId) return emp;
            const updatedPens = emp.penalties.map((p) => ({
              ...p,
              currentAmount: p.originalAmount,
              status: 'pending_payment',
              escalationLevel: 'initial',
            }));
            return {
              ...emp,
              penalties: updatedPens,
              totalCurrentDue: emp.totalOriginalDue,
              has500Penalty: false,
            };
          })
          .filter((emp) => emp.status === 'suspended' || !emp.isActive);
      });

      toast({
        message: `تم إرجاع كافة غرامات الزميل ${target.employeeName} إلى قيمتها الأصلية (${formatCurrency(target.totalOriginalDue)}) بنجاح`,
        tone: 'success',
      });
      setRevertAllTarget(null);
      setRevertReason('');

      // تحديث متوازي
      await Promise.allSettled([
        queryClient.refetchQueries({ queryKey: ['suspended-employees-admin'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties-pending-employees'] }),
      ]);
    } catch {
      // main.tsx يعرض الخطأ
    } finally {
      setRevertAllLoading(false);
    }
  };

  // سداد غرامة ورفع الإيقاف
  const handlePaymentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!paymentPenaltyId) return;
    const penaltyId = paymentPenaltyId;
    setPaymentLoading(true);
    try {
      await confirmPayment.mutateAsync({
        penaltyId,
        notes: paymentNotes.trim() || undefined,
      });

      // إزالة تفاؤلية للغرامة المسددة
      queryClient.setQueriesData<SuspendedEmployeeAdmin[]>({ queryKey: ['suspended-employees-admin'] }, (old) => {
        if (!old) return [];
        return old
          .map((emp) => {
            const hasPen = emp.penalties.some((p) => p.id === penaltyId);
            if (!hasPen) return emp;
            const remainingPens = emp.penalties.filter((p) => p.id !== penaltyId);
            const newTotalCurrent = remainingPens.reduce((s, p) => s + p.currentAmount, 0);
            const newTotalOrig = remainingPens.reduce((s, p) => s + p.originalAmount, 0);
            const has500 = remainingPens.some((p) => p.currentAmount >= 500);
            return {
              ...emp,
              penalties: remainingPens,
              totalCurrentDue: newTotalCurrent,
              totalOriginalDue: newTotalOrig,
              unpaidCount: remainingPens.length,
              has500Penalty: has500,
            };
          })
          .filter((emp) => (emp.status === 'suspended' || !emp.isActive || emp.has500Penalty) && emp.penalties.length > 0);
      });

      toast({
        message: 'تم تسجيل السداد وإيداع المبلغ في صندوق الزمالة والتكافل ورفع الإيقاف بنجاح',
        tone: 'success',
      });
      setPaymentDialogOpen(false);
      setPaymentNotes('');
      setPaymentPenaltyId(null);

      // تحديث فوري
      await Promise.allSettled([
        queryClient.refetchQueries({ queryKey: ['suspended-employees-admin'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties-pending-employees'] }),
        queryClient.refetchQueries({ queryKey: ['fellowship-fund-summary'] }),
        queryClient.refetchQueries({ queryKey: ['fellowship-fund-transactions'] }),
        queryClient.refetchQueries({ queryKey: ['employees'] }),
      ]);
    } catch {
      // main.tsx
    } finally {
      setPaymentLoading(false);
    }
  };

  // إرسال تنبيه واتساب مهذب ومباشر
  const sendWhatsAppReminder = (emp: SuspendedEmployeeAdmin) => {
    const isActuallySuspended = emp.status === 'suspended' || !emp.isActive;
    const text =
      `*إشعار هام من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️\n\n` +
      `السلام عليكم ورحمة الله، أستاذ *${emp.employeeName}* 🌸\n\n` +
      (isActuallySuspended
        ? `نود إحاطتكم بأنه قد تم *تعليق حسابكم مؤقتاً على المنظومة* لتجاوز مهلة سداد غرامات الحضور والانصراف.\n\n`
        : `نود تذكيركم بوجود غرامات حضور وانصراف مضاعفة بانتظار السداد لتفادي تعليق الحساب.\n\n`) +
      `📌 *بيان المبالغ المستحقة:*\n` +
      `• إجمالي المبلغ بالمضاعفة (500 ج.م): *${formatCurrency(emp.totalCurrentDue)}*\n` +
      `• أصل الغرامات دون مضاعفة: *${formatCurrency(emp.totalOriginalDue)}*\n` +
      `• عدد الغرامات غير المسددة: *${emp.unpaidCount}*\n\n` +
      `يرجى التكرم بمراجعة قسم الموارد البشرية لتسوية الغرامة وإعادة تفعيل الحساب فوراً لمباشرة العمل.\n\n` +
      `مع خالص الشكر والتقدير،\n*إدارة الموارد البشرية — جمعية أحلى شباب*`;

    if (!emp.phone) {
      toast({ message: 'لا يوجد رقم هاتف مسجل لهذا الموظف', tone: 'warning' });
      return;
    }

    const cleanPhone = emp.phone.replace(/[^0-9]/g, '');
    const url = `https://wa.me/${cleanPhone}?text=${encodeURIComponent(text)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="الموظفون الموقوفون عن العمل"
        description="إدارة ومتابعة الموظفين المعلقين عن العمل بسبب غرامات الحضور والانصراف المتجاوزة للمهلة. يمكن سداد الغرامة لرفع الإيقاف فوراً، أو إرجاع الغرامات لقيمتها الأصلية (20/50/150 ج.م) بدون مضاعفة، أو رفع الإيقاف إدارياً."
      />

      {/* ─── بطاقات الإحصائيات العلوية ───────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {/* 1) الموقوفون عن العمل */}
        <div className="relative overflow-hidden rounded-2xl border border-red-500/20 bg-gradient-to-br from-red-500/10 via-red-500/5 to-transparent p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-red-600 dark:text-red-400">الموقوفون عن العمل</span>
            <div className="rounded-xl bg-red-500/15 p-2 text-red-600">
              <Ban className="size-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-black text-red-600 dark:text-red-400">{actuallySuspendedCount}</span>
            <span className="text-xs text-[var(--text-muted)]">موظف معلق حسابه</span>
          </div>
          <p className="mt-2 text-[11px] text-[var(--text-muted)]">حساباتهم معلقة بانتظار الإجراء</p>
        </div>

        {/* 2) حسابات نشطة بغرامات 500 ج.م */}
        <div className="relative overflow-hidden rounded-2xl border border-amber-500/20 bg-gradient-to-br from-amber-500/10 via-amber-500/5 to-transparent p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-amber-600 dark:text-amber-400">غرامات مضاعفة (نشطة)</span>
            <div className="rounded-xl bg-amber-500/15 p-2 text-amber-600">
              <AlertTriangle className="size-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-black text-amber-600 dark:text-amber-400">{doubledOnlyCount}</span>
            <span className="text-xs text-[var(--text-muted)]">موظف نشط</span>
          </div>
          <p className="mt-2 text-[11px] text-[var(--text-muted)]">لديهم غرامة 500 ج.م بانتظار السداد</p>
        </div>

        {/* 3) إجمالي المطلوب بالمضاعفة */}
        <div className="relative overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-[var(--text-secondary)]">المطلوب بالمضاعفة (500 ج.م)</span>
            <div className="rounded-xl bg-rose-500/10 p-2 text-rose-500">
              <Coins className="size-5" />
            </div>
          </div>
          <div className="mt-3">
            <span className="text-2xl font-black text-rose-600 dark:text-rose-400">{formatCurrency(totalCurrent)}</span>
          </div>
          <p className="mt-2 text-[11px] text-[var(--text-muted)]">إجمالي المبالغ الحالية مع المضاعفة</p>
        </div>

        {/* 4) أصل الغرامات بدون مضاعفة */}
        <div className="relative overflow-hidden rounded-2xl border border-emerald-500/20 bg-gradient-to-br from-emerald-500/10 via-emerald-500/5 to-transparent p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-emerald-600 dark:text-emerald-400">أصل الغرامات بدون مضاعفة</span>
            <div className="rounded-xl bg-emerald-500/15 p-2 text-emerald-600">
              <Sparkles className="size-5" />
            </div>
          </div>
          <div className="mt-3">
            <span className="text-2xl font-black text-emerald-600 dark:text-emerald-400">{formatCurrency(totalOriginal)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between text-[11px] text-[var(--text-muted)]">
            <span>المبلغ المستحق حال إرجاعها للأصل</span>
            {totalCurrent > totalOriginal && (
              <span className="font-bold text-violet-600 dark:text-violet-400">(وفر إداري: {formatCurrency(totalCurrent - totalOriginal)})</span>
            )}
          </div>
        </div>
      </div>

      {/* ─── شريط التصفية والبحث ───────────────────────────────────────── */}
      <div className="flex flex-col gap-3 rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] p-4 shadow-sm md:flex-row md:items-center md:justify-between">
        {/* حقل البحث */}
        <div className="relative flex-1">
          <Search className="absolute right-3.5 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="ابحث بالاسم، كود الموظف، القسم، المسمى الوظيفي، أو الهاتف..."
            className="input w-full pr-10 text-xs sm:text-sm"
          />
        </div>

        {/* أزرار الفلترة السريعة */}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 md:pb-0">
          <Filter className="size-4 text-[var(--text-muted)] shrink-0 ml-1" />
          <button
            type="button"
            onClick={() => setStatusFilter('all')}
            className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap ${
              statusFilter === 'all'
                ? 'bg-[var(--primary)] text-white shadow-xs'
                : 'bg-[var(--surface-muted)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
            }`}
          >
            الكل ({activeDisplayList.length})
          </button>
          <button
            type="button"
            onClick={() => setStatusFilter('suspended_only')}
            className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap flex items-center gap-1 ${
              statusFilter === 'suspended_only' ? 'bg-red-600 text-white shadow-xs' : 'bg-red-500/10 text-red-600 dark:text-red-400 hover:bg-red-500/20'
            }`}
          >
            <Ban className="size-3" />
            <span>موقوف فعلياً ({actuallySuspendedCount})</span>
          </button>
          <button
            type="button"
            onClick={() => setStatusFilter('doubled_only')}
            className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap flex items-center gap-1 ${
              statusFilter === 'doubled_only' ? 'bg-amber-600 text-white shadow-xs' : 'bg-amber-500/10 text-amber-600 dark:text-amber-400 hover:bg-amber-500/20'
            }`}
          >
            <AlertTriangle className="size-3" />
            <span>غرامات 500 ج.م ({doubledOnlyCount})</span>
          </button>
        </div>
      </div>

      {/* ─── حالة التحميل ──────────────────────────────────────────────── */}
      {isLoading && <ListSkeleton rows={4} />}

      {/* ─── حالة الخطأ ────────────────────────────────────────────────── */}
      {error && (
        <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-center">
          <p className="text-sm font-bold text-red-600">تعذر تحميل بيانات الموظفين الموقوفين</p>
          <button type="button" onClick={() => refetch()} className="btn-secondary mt-3 text-xs">
            إعادة المحاولة
          </button>
        </div>
      )}

      {/* ─── قائمة فارغة ──────────────────────────────────────────────── */}
      {!isLoading && !error && filteredList.length === 0 && (
        <div className="rounded-2xl border border-dashed border-[var(--border)] bg-[var(--surface-raised)]/40 p-12 text-center">
          <div className="mx-auto w-12 h-12 rounded-full bg-emerald-500/10 text-emerald-600 flex items-center justify-center mb-3">
            <CheckCircle2 className="size-6" />
          </div>
          <p className="text-base font-bold text-[var(--text-strong)]">
            {searchQuery ? 'لا توجد نتائج مطابقة لبحثك' : 'لا يوجد موظفون موقوفون عن العمل حالياً'}
          </p>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            {searchQuery ? 'جرّب تعديل كلمات البحث أو تصفير الفلاتر' : 'كافة الحسابات نشطة ولا توجد غرامات متجاوزة لمهلة السداد'}
          </p>
        </div>
      )}

      {/* ─── قائمة الموظفين الموقوفين ─────────────────────────────────── */}
      {!isLoading && !error && filteredList.length > 0 && (
        <div className="space-y-4">
          {filteredList.map((emp) => {
            const isActuallySuspended = emp.status === 'suspended' || !emp.isActive;
            return (
              <div
                key={emp.employeeId}
                className="overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] shadow-sm hover:border-[var(--border-strong)] transition-all"
              >
                {/* رأس بطاقة الموظف */}
                <div className="flex flex-col gap-3 p-5 sm:flex-row sm:items-center sm:justify-between border-b border-[var(--border)] bg-[var(--surface)]/40">
                  <div className="flex items-center gap-3.5">
                    <UserAvatar displayName={emp.employeeName} photoUrl={emp.photoUrl} size="lg" announceName={false} />
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h3 className="font-bold text-base text-[var(--text-strong)]">{emp.employeeName}</h3>
                        {isActuallySuspended ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30 px-3 py-1 text-xs font-black shadow-xs">
                            <Ban className="size-3.5" />
                            <span>موقوف عن العمل</span>
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30 px-3 py-1 text-xs font-bold shadow-xs">
                            <AlertTriangle className="size-3.5" />
                            <span>حساب نشط — غرامة مضاعفة 500 ج.م</span>
                          </span>
                        )}
                      </div>

                      <div className="mt-1 flex items-center gap-3 text-xs text-[var(--text-muted)] flex-wrap">
                        {emp.jobTitle && <span>{emp.jobTitle}</span>}
                        {emp.departmentName && (
                          <span className="flex items-center gap-1">
                            <Building className="size-3.5" />
                            {emp.departmentName}
                          </span>
                        )}
                        {emp.employeeCode && (
                          <span className="font-mono bg-[var(--surface-muted)] px-1.5 py-0.5 rounded text-[10px] text-[var(--text-secondary)]">
                            كود: {emp.employeeCode}
                          </span>
                        )}
                        {emp.phone && (
                          <button
                            type="button"
                            onClick={() => copyPhone(emp.phone!)}
                            className="inline-flex items-center gap-1 text-[11px] text-[var(--text-secondary)] hover:text-primary transition-colors cursor-pointer"
                            title="انقر لنسخ رقم الهاتف"
                          >
                            <Phone className="size-3" />
                            <span dir="ltr">{emp.phone}</span>
                            {copiedPhone === emp.phone ? <Check className="size-3 text-emerald-500" /> : <Copy className="size-3 text-[var(--text-muted)]" />}
                          </button>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* ملخص المبالغ المستحقة */}
                  <div className="flex items-center gap-3 self-end sm:self-center">
                    <div className="rounded-xl border border-red-500/20 bg-red-500/10 px-4 py-2 text-center">
                      <span className="block text-[10px] font-bold text-red-600 dark:text-red-400">المطلوب بالمضاعفة</span>
                      <span className="text-sm sm:text-base font-black text-red-600 dark:text-red-400">{formatCurrency(emp.totalCurrentDue)}</span>
                    </div>
                    <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 px-4 py-2 text-center">
                      <span className="block text-[10px] font-bold text-emerald-600 dark:text-emerald-400">الأصل دون مضاعفة</span>
                      <span className="text-sm sm:text-base font-black text-emerald-600 dark:text-emerald-400">{formatCurrency(emp.totalOriginalDue)}</span>
                    </div>
                  </div>
                </div>

                {/* جدول الغرامات المسجلة على الموظف */}
                <div className="p-4 overflow-x-auto">
                  <table className="w-full text-right text-xs">
                    <thead>
                      <tr className="border-b border-[var(--border)] text-[var(--text-muted)]">
                        <th className="p-3">تاريخ العمل</th>
                        <th className="p-3">مدة التأخير</th>
                        <th className="p-3">القيمة الأصلية</th>
                        <th className="p-3">القيمة الحالية (المضاعفة)</th>
                        <th className="p-3">الحالة والتصعيد</th>
                        <th className="p-3 text-center">إجراءات الغرامة</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border)]">
                      {emp.penalties.map((pen) => (
                        <tr key={pen.id} className="hover:bg-[var(--surface-raised)]/60 transition-colors">
                          <td className="p-3 font-bold text-[var(--text-strong)]">{formatArabicDate(pen.workDate)}</td>
                          <td className="p-3 text-[var(--text-muted)]">{formatLateMinutes(pen.lateMinutes)}</td>
                          <td className="p-3 font-bold text-emerald-600">
                            <span className="px-2 py-0.5 rounded-md bg-emerald-500/10 border border-emerald-500/20">{formatCurrency(pen.originalAmount)}</span>
                          </td>
                          <td className="p-3 font-black text-rose-600">
                            <span className="px-2 py-0.5 rounded-md bg-rose-500/10 border border-rose-500/20">{formatCurrency(pen.currentAmount)}</span>
                          </td>
                          <td className="p-3">
                            <span
                              className={`badge text-[10px] font-bold px-2 py-0.5 rounded-md ${
                                pen.status === 'suspended'
                                  ? 'badge-danger'
                                  : pen.status === 'doubled' || pen.currentAmount >= 500
                                    ? 'badge-warning'
                                    : 'badge-neutral'
                              }`}
                            >
                              {pen.status === 'suspended'
                                ? 'إيقاف ومضاعفة 500 ج.م'
                                : pen.status === 'doubled' || pen.currentAmount >= 500
                                  ? 'مضاعفة 500 ج.م'
                                  : 'بانتظار السداد'}
                            </span>
                          </td>
                          <td className="p-3 text-center">
                            <div className="flex items-center justify-center gap-2">
                              {/* زر سداد هذه الغرامة الفردية */}
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedEmp(emp);
                                  setPaymentPenaltyId(pen.id);
                                  setPaymentPenaltyAmount(pen.currentAmount);
                                  setPaymentNotes('');
                                  setPaymentDialogOpen(true);
                                }}
                                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer shadow-sm transition-all"
                                title="تحصيل الغرامة وإيداعها بصندوق الزمالة والتكافل ورفع الإيقاف فوراً"
                              >
                                <Coins className="size-3.5" />
                                <span>سداد ({formatCurrency(pen.currentAmount)})</span>
                              </button>

                              {/* زر إرجاع هذه الغرامة الفردية للأصل */}
                              {pen.currentAmount > pen.originalAmount && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setRevertPenaltyDetails({
                                      id: pen.id,
                                      employeeName: emp.employeeName,
                                      workDate: pen.workDate,
                                      lateMinutes: pen.lateMinutes,
                                      currentAmount: pen.currentAmount,
                                      originalAmount: pen.originalAmount,
                                    });
                                    setRevertReason('');
                                    setRevertDialogOpen(true);
                                  }}
                                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-indigo-50 hover:bg-indigo-100 text-indigo-700 dark:bg-indigo-950/40 dark:text-indigo-300 border border-indigo-300 dark:border-indigo-800 cursor-pointer transition-all"
                                  title={`إلغاء المضاعفة وإرجاع هذه الغرامة لأصلها (${formatCurrency(pen.originalAmount)})`}
                                >
                                  <RotateCcw className="size-3.5 text-indigo-600 dark:text-indigo-400" />
                                  <span>أصل الغرامة ({formatCurrency(pen.originalAmount)})</span>
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* تذييل البطاقة: الإجراءات الإدارية الكبرى */}
                <div className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between border-t border-[var(--border)] bg-[var(--surface)]/30">
                  <div className="flex items-center gap-2 flex-wrap">
                    {/* 1) إرجاع كافة الغرامات للأصل */}
                    {emp.has500Penalty && (
                      <button
                        type="button"
                        onClick={() => {
                          setRevertAllTarget(emp);
                          setRevertReason('');
                        }}
                        className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold text-indigo-700 dark:text-indigo-300 bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/30 cursor-pointer transition-all shadow-sm"
                        title={`إرجاع كافة غرامات الموظف المضاعفة إلى قيمتها الأصلية (${formatCurrency(emp.totalOriginalDue)})`}
                      >
                        <RotateCcw className="size-4 text-indigo-600 dark:text-indigo-400" />
                        <span>إرجاع كافة الغرامات للأصل ({formatCurrency(emp.totalOriginalDue)})</span>
                      </button>
                    )}

                    {/* 2) رفع الإيقاف إدارياً */}
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedEmp(emp);
                        setLiftReason('');
                        setLiftDialogOpen(true);
                      }}
                      className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold text-emerald-700 dark:text-emerald-300 bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/30 cursor-pointer transition-all shadow-sm"
                      title="رفع الإيقاف إدارياً وإعادة فتح الحساب فوراً"
                    >
                      <UserCheck className="size-4 text-emerald-600 dark:text-emerald-400" />
                      <span>رفع الإيقاف إدارياً وتفعيل الحساب</span>
                    </button>
                  </div>

                  {/* 3) تنبيه واتساب */}
                  <button
                    type="button"
                    onClick={() => sendWhatsAppReminder(emp)}
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold text-white bg-[#25D366] hover:bg-[#1EBE5D] cursor-pointer transition-all shadow-sm"
                    title="إرسال رسالة تذكير للموظف عبر واتساب بالسداد وإعادة التفعيل"
                  >
                    <MessageCircle className="size-4" />
                    <span>تنبيه واتساب</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ─── حوار رفع الإيقاف إدارياً ───────────────────────────────────── */}
      {liftDialogOpen && selectedEmp && (
        <DialogOverlay
          title={`رفع الإيقاف وتفعيل حساب: ${selectedEmp.employeeName}`}
          onClose={() => {
            setLiftDialogOpen(false);
            setSelectedEmp(null);
            setLiftReason('');
          }}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleLiftSubmit} className="space-y-4">
            <div className="flex items-center gap-3 p-3 rounded-2xl bg-[var(--surface-raised)] border border-[var(--border)]">
              <UserAvatar displayName={selectedEmp.employeeName} photoUrl={selectedEmp.photoUrl} size="md" announceName={false} />
              <div className="min-w-0">
                <p className="font-bold text-sm text-[var(--text-strong)]">{selectedEmp.employeeName}</p>
                <p className="text-xs text-[var(--text-muted)]">{selectedEmp.jobTitle ?? selectedEmp.departmentName ?? 'موظف'}</p>
              </div>
            </div>

            <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-800 dark:text-emerald-300 space-y-1.5">
              <p className="font-bold flex items-center gap-1.5">
                <CheckCircle2 className="size-4 shrink-0 text-emerald-600" />
                <span>ما سيحدث فوراً عند تأكيد رفع الإيقاف:</span>
              </p>
              <ul className="list-disc list-inside space-y-1 text-[11px] pr-2 text-emerald-700 dark:text-emerald-300/90 leading-relaxed">
                <li>إعادة فتح وتفعيل حساب الموظف فوراً وتمكينه من تسجيل الحضور ومباشرة العمل.</li>
                <li>إرجاع كافة غراماته الموقوفة والمضاعفة (500 ج.م) إلى أصلها العادي بانتظار السداد.</li>
                <li>إزالة الموظف فوراً وبشكل نهائي من قائمة الموقوفين عن العمل.</li>
              </ul>
            </div>

            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1.5">سبب رفع الإيقاف أو الملاحظة الإدارية (اختياري):</label>
              <input
                type="text"
                value={liftReason}
                onChange={(e) => setLiftReason(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: استئناف العمل بقرار إداري وتسوية الغرامات"
              />
              <div className="flex flex-wrap gap-1.5 mt-2">
                {['استئناف العمل بقرار إداري', 'تسوية ودية وتعهد بالالتزام', 'موافقة المدير التنفيذي'].map((chip) => (
                  <button
                    key={chip}
                    type="button"
                    onClick={() => setLiftReason(chip)}
                    className="text-[10px] px-2 py-0.5 rounded-full bg-[var(--surface-muted)] hover:bg-[var(--surface-hover)] border border-[var(--border)] text-[var(--text-secondary)] transition-colors cursor-pointer"
                  >
                    + {chip}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border)]">
              <button
                type="button"
                onClick={() => {
                  setLiftDialogOpen(false);
                  setSelectedEmp(null);
                  setLiftReason('');
                }}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={liftLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer"
              >
                <UserCheck className="size-3.5" />
                <span>{liftLoading ? 'جارٍ رفع الإيقاف…' : 'تأكيد رفع الإيقاف والتفعيل'}</span>
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}

      {/* ─── حوار إرجاع غرامة مفردة للأصل ─────────────────────────────── */}
      {revertDialogOpen && revertPenaltyDetails && (
        <DialogOverlay
          title="إرجاع الغرامة لقيمتها الأصلية بدون مضاعفة"
          onClose={() => {
            setRevertDialogOpen(false);
            setRevertPenaltyDetails(null);
            setRevertReason('');
          }}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleRevertSubmit} className="space-y-4">
            {/* بطاقة ملخص الغرامة والوفر المالي */}
            <div className="rounded-2xl border border-indigo-500/20 bg-indigo-500/5 dark:bg-indigo-950/20 p-4 space-y-3">
              <div className="flex items-center justify-between text-xs">
                <span className="font-bold text-[var(--text-secondary)]">تاريخ الغرامة:</span>
                <span className="font-bold text-[var(--text-strong)]">{formatArabicDate(revertPenaltyDetails.workDate)}</span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="font-bold text-[var(--text-secondary)]">مدة التأخير:</span>
                <span className="text-[var(--text-muted)] font-mono">{formatLateMinutes(revertPenaltyDetails.lateMinutes)}</span>
              </div>

              <div className="grid grid-cols-2 gap-3 pt-2 border-t border-indigo-500/20">
                <div className="rounded-xl bg-red-500/10 border border-red-500/20 p-2.5 text-center">
                  <span className="block text-[10px] font-bold text-red-600 dark:text-red-400">القيمة الحالية (المضاعفة)</span>
                  <span className="text-base font-black text-red-600 line-through">{formatCurrency(revertPenaltyDetails.currentAmount)}</span>
                </div>
                <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/20 p-2.5 text-center">
                  <span className="block text-[10px] font-bold text-emerald-600 dark:text-emerald-400">القيمة الأصلية المستحقة</span>
                  <span className="text-base font-black text-emerald-600">{formatCurrency(revertPenaltyDetails.originalAmount)}</span>
                </div>
              </div>

              <div className="flex items-center justify-between px-3 py-2 rounded-xl bg-violet-500/10 border border-violet-500/20 text-xs font-bold text-violet-700 dark:text-violet-300">
                <span>فارق الإعفاء الإداري (وفر للموظف):</span>
                <span>{formatCurrency(revertPenaltyDetails.currentAmount - revertPenaltyDetails.originalAmount)}</span>
              </div>
            </div>

            <p className="text-xs text-[var(--text-muted)] leading-relaxed">
              💡 سيتم إرجاع الغرامة لقيمتها الأصلية وبانتظار السداد، مما يتيح للموظف سدادها لدى الـ HR بالقيمة العادية دون مضاعفة.
            </p>

            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1.5">سبب الإرجاع الإداري (اختياري):</label>
              <input
                type="text"
                value={revertReason}
                onChange={(e) => setRevertReason(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: مراعاة لظرف الموظف واستعداده للسداد"
              />
              <div className="flex flex-wrap gap-1.5 mt-2">
                {['مراعاة لظرف الموظف واستعداده للسداد', 'توجيه إداري بالسداد بالأصل', 'تسوية ودية وتعهد بالالتزام'].map((chip) => (
                  <button
                    key={chip}
                    type="button"
                    onClick={() => setRevertReason(chip)}
                    className="text-[10px] px-2 py-0.5 rounded-full bg-[var(--surface-muted)] hover:bg-[var(--surface-hover)] border border-[var(--border)] text-[var(--text-secondary)] transition-colors cursor-pointer"
                  >
                    + {chip}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border)]">
              <button
                type="button"
                onClick={() => {
                  setRevertDialogOpen(false);
                  setRevertPenaltyDetails(null);
                  setRevertReason('');
                }}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={revertLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-indigo-600 hover:bg-indigo-700 text-white cursor-pointer"
              >
                <RotateCcw className="size-3.5" />
                <span>{revertLoading ? 'جارٍ الإرجاع…' : 'تأكيد إرجاع الغرامة للأصل'}</span>
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}

      {/* ─── حوار إرجاع كافة الغرامات للموظف ───────────────────────────── */}
      {revertAllTarget && (
        <DialogOverlay
          title={`إرجاع كافة غرامات: ${revertAllTarget.employeeName}`}
          onClose={() => {
            setRevertAllTarget(null);
            setRevertReason('');
          }}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleRevertAllSubmit} className="space-y-4">
            <div className="p-4 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 text-xs space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-bold text-[var(--text-secondary)]">إجمالي المطلوب حالياً (بالمضاعفة):</span>
                <span className="font-black text-rose-600 text-base">{formatCurrency(revertAllTarget.totalCurrentDue)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="font-bold text-[var(--text-secondary)]">إجمالي المطلوب بعد الإرجاع للأصل:</span>
                <span className="font-black text-emerald-600 text-base">{formatCurrency(revertAllTarget.totalOriginalDue)}</span>
              </div>
              <div className="flex items-center justify-between pt-2 border-t border-indigo-500/20 font-bold text-violet-700 dark:text-violet-300">
                <span>إجمالي فارق الإعفاء (وفر للموظف):</span>
                <span className="text-sm">{formatCurrency(revertAllTarget.totalCurrentDue - revertAllTarget.totalOriginalDue)}</span>
              </div>
            </div>

            <p className="text-xs text-[var(--text-muted)] leading-relaxed">
              سيتم إلغاء كافة مضاعفات الـ 500 ج.م المسجلة على الزميل <strong>{revertAllTarget.employeeName}</strong> وإرجاعها لقيمتها الأصلية (20/50/150 ج.م)
              بانتظار السداد العادي.
            </p>

            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1.5">سبب الإرجاع الجماعي (اختياري):</label>
              <input
                type="text"
                value={revertReason}
                onChange={(e) => setRevertReason(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: تسوية ودية شاملة لكافة الغرامات"
              />
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border)]">
              <button
                type="button"
                onClick={() => {
                  setRevertAllTarget(null);
                  setRevertReason('');
                }}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={revertAllLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-indigo-600 hover:bg-indigo-700 text-white cursor-pointer"
              >
                <RotateCcw className="size-3.5" />
                <span>{revertAllLoading ? 'جارٍ إرجاع الغرامات…' : 'تأكيد إرجاع كافة الغرامات'}</span>
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}

      {/* ─── حوار سداد الغرامة ورفع الإيقاف ─────────────────────────────── */}
      {paymentDialogOpen && paymentPenaltyId && selectedEmp && (
        <DialogOverlay title="تأكيد سداد الغرامة وتوريدها لصندوق الزمالة" onClose={() => setPaymentDialogOpen(false)} maxWidth="max-w-md">
          <form onSubmit={handlePaymentSubmit} className="space-y-4">
            <p className="text-sm text-[var(--text-muted)] leading-relaxed">
              تأكيد استلام مبلغ <strong>{formatCurrency(paymentPenaltyAmount)}</strong> نقداً من الزميل <strong>{selectedEmp.employeeName}</strong> وتوريده
              بالكامل لصندوق الزمالة والتكافل.
              <br />
              <span className="text-emerald-600 font-bold mt-1 inline-block">✨ سيتم رفع الإيقاف فوراً وإعادة فتح حساب الموظف على المنظومة.</span>
            </p>
            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1">ملاحظات التحصيل (اختياري):</label>
              <input
                type="text"
                value={paymentNotes}
                onChange={(e) => setPaymentNotes(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: تم السداد نقداً لدى الـ HR"
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button type="button" onClick={() => setPaymentDialogOpen(false)} className="btn-secondary text-xs cursor-pointer">
                إلغاء
              </button>
              <button
                type="submit"
                disabled={paymentLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer"
              >
                <Coins className="size-3.5" />
                <span>{paymentLoading ? 'جارٍ تسجيل السداد…' : 'تأكيد التحصيل والتوريد'}</span>
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}
    </div>
  );
}
