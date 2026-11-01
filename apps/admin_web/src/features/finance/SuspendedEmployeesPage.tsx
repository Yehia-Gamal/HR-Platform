import { useState, useMemo } from 'react';
import {
  Ban,
  CheckCircle2,
  AlertTriangle,
  RotateCcw,
  Coins,
  MessageCircle,
  ShieldAlert,
  Phone,
  Building,
  UserCheck,
  Search,
  Filter,
  Copy,
  Check,
  Clock,
  Sparkles,
} from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { PageHeader } from '../../ui/PageHeader';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ListSkeleton } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useToast } from '../../ui/Toast';
import { safeErrorMessage } from '../../core/errorMapper';
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

  const [selectedEmp, setSelectedEmp] = useState<SuspendedEmployeeAdmin | null>(null);

  // Dialogs
  const [liftDialogOpen, setLiftDialogOpen] = useState(false);
  const [liftReason, setLiftReason] = useState('');
  const [liftLoading, setLiftLoading] = useState(false);

  const [revertDialogOpen, setRevertDialogOpen] = useState(false);
  const [revertPenaltyId, setRevertPenaltyId] = useState<string | null>(null);
  const [revertPenaltyDesc, setRevertPenaltyDesc] = useState('');
  const [revertReason, setRevertReason] = useState('');
  const [revertLoading, setRevertLoading] = useState(false);

  const [paymentDialogOpen, setPaymentDialogOpen] = useState(false);
  const [paymentPenaltyId, setPaymentPenaltyId] = useState<string | null>(null);
  const [paymentPenaltyAmount, setPaymentPenaltyAmount] = useState<number>(0);
  const [paymentNotes, setPaymentNotes] = useState('');
  const [paymentLoading, setPaymentLoading] = useState(false);

  const rawList = employees ?? [];

  // تصفية وبحث
  const filteredList = useMemo(() => {
    return rawList.filter((emp) => {
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
  }, [rawList, statusFilter, searchQuery]);

  const totalCurrent = rawList.reduce((s, e) => s + (e.totalCurrentDue || 0), 0);
  const totalOriginal = rawList.reduce((s, e) => s + (e.totalOriginalDue || 0), 0);
  const actuallySuspendedCount = rawList.filter((e) => e.status === 'suspended' || !e.isActive).length;
  const doubledOnlyCount = rawList.length - actuallySuspendedCount;

  // نسخ الهاتف للحافظة
  const copyPhone = (phone: string) => {
    navigator.clipboard.writeText(phone);
    setCopiedPhone(phone);
    setTimeout(() => setCopiedPhone(null), 2000);
  };

  // رفع الإيقاف إدارياً
  const handleLiftSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedEmp) return;
    setLiftLoading(true);
    try {
      await liftSuspension.mutateAsync({
        employeeId: selectedEmp.employeeId,
        reason: liftReason.trim() || undefined,
      });
      toast({
        message: `تم رفع الإيقاف عن الزميل ${selectedEmp.employeeName} وإعادة تفعيل حسابه بنجاح`,
        tone: 'success',
      });
      setLiftDialogOpen(false);
      setLiftReason('');
      setSelectedEmp(null);
      // تحديث فوري لكافة الكاشات المرتبطة
      await Promise.all([
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
    if (!revertPenaltyId) return;
    setRevertLoading(true);
    try {
      await revertPenalty.mutateAsync({
        penaltyId: revertPenaltyId,
        reason: revertReason.trim() || undefined,
      });
      toast({
        message: 'تم إرجاع الغرامة إلى قيمتها الأصلية بدون مضاعفة بنجاح',
        tone: 'success',
      });
      setRevertDialogOpen(false);
      setRevertReason('');
      setRevertPenaltyId(null);
      // تحديث فوري
      await Promise.all([
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
  const handleRevertAllForEmp = async (emp: SuspendedEmployeeAdmin) => {
    try {
      for (const pen of emp.penalties) {
        if (pen.currentAmount > pen.originalAmount) {
          await revertPenalty.mutateAsync({
            penaltyId: pen.id,
            reason: 'إرجاع إداري جماعي للموظف الموقوف',
          });
        }
      }
      toast({
        message: `تم إرجاع كافة غرامات الزميل ${emp.employeeName} إلى قيمتها الأصلية (${formatCurrency(emp.totalOriginalDue)}) بنجاح`,
        tone: 'success',
      });
      // تحديث فوري
      await Promise.all([
        queryClient.refetchQueries({ queryKey: ['suspended-employees-admin'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties'] }),
        queryClient.refetchQueries({ queryKey: ['instant-penalties-pending-employees'] }),
      ]);
    } catch {
      // main.tsx يعرض الخطأ
    }
  };

  // سداد غرامة ورفع الإيقاف
  const handlePaymentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!paymentPenaltyId) return;
    setPaymentLoading(true);
    try {
      await confirmPayment.mutateAsync({
        penaltyId: paymentPenaltyId,
        notes: paymentNotes.trim() || undefined,
      });
      toast({
        message: 'تم تسجيل السداد وإيداع المبلغ في صندوق الزمالة والتكافل ورفع الإيقاف بنجاح',
        tone: 'success',
      });
      setPaymentDialogOpen(false);
      setPaymentNotes('');
      setPaymentPenaltyId(null);
      // تحديث فوري
      await Promise.all([
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
      `📌 *المبلغ المطلوب حالياً:* *${formatCurrency(emp.totalCurrentDue)}* ` +
      `(أصل الغرامة بدون مضاعفة: *${formatCurrency(emp.totalOriginalDue)}*).\n\n` +
      `يرجى التكرم بالتوجه لإدارة الموارد البشرية (HR) أو التواصل مع م. يحيى للسداد وإعادة فتح الحساب فوراً لمباشرة عملكم المبارك.\n\n` +
      `مع خالص التقدير والاحترام 🌺`;

    const phone = emp.phone ? emp.phone.replace(/[^0-9]/g, '') : '';
    const url = phone
      ? `https://wa.me/${phone}?text=${encodeURIComponent(text)}`
      : `https://wa.me/?text=${encodeURIComponent(text)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="الموظفون الموقوفون عن العمل"
        description="متابعة الحسابات المعلقة وغرامات التأخير المتجاوزة للمهلة. يمكن سداد الغرامة لرفع الإيقاف فوراً وتوريدها لصندوق الزمالة، أو إرجاع الغرامات لقيمتها الأصلية (20/50/150 ج.م) بقرار إداري، أو رفع الإيقاف وتفعيل الحساب."
      />

      {/* بطاقات الإحصائيات العلوية المحسّنة */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="card p-5 bg-gradient-to-br from-rose-500/10 via-rose-500/5 to-transparent border border-rose-500/25 shadow-sm rounded-2xl relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-rose-700 dark:text-rose-300">الموقوفون عن العمل</span>
            <div className="p-2.5 rounded-xl bg-rose-500/15 text-rose-600 shadow-inner">
              <Ban className="size-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-black text-rose-700 dark:text-rose-300">{rawList.length}</span>
            <span className="text-xs text-[var(--text-muted)] font-medium">موظف مسجل بالجدول</span>
          </div>
          <div className="mt-2 flex items-center gap-2 text-[11px] text-[var(--text-muted)]">
            <span className="inline-block size-2 rounded-full bg-rose-500" />
            <span>{actuallySuspendedCount} حساب معلق فعلياً</span>
            <span className="text-[var(--border)]">•</span>
            <span>{doubledOnlyCount} نشط بمضاعفة 500 ج.م</span>
          </div>
        </div>

        <div className="card p-5 bg-gradient-to-br from-amber-500/10 via-amber-500/5 to-transparent border border-amber-500/25 shadow-sm rounded-2xl relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-amber-700 dark:text-amber-300">المطلوب بالمضاعفة (500 ج.م)</span>
            <div className="p-2.5 rounded-xl bg-amber-500/15 text-amber-600 shadow-inner">
              <ShieldAlert className="size-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-black text-amber-700 dark:text-amber-300">{formatCurrency(totalCurrent)}</span>
          </div>
          <p className="mt-2 text-[11px] text-[var(--text-muted)]">إجمالي المبالغ المطلوبة في حال تطبيق سقف المضاعفة كاملاً</p>
        </div>

        <div className="card p-5 bg-gradient-to-br from-emerald-500/10 via-emerald-500/5 to-transparent border border-emerald-500/25 shadow-sm rounded-2xl relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-emerald-700 dark:text-emerald-300">أصل الغرامات بدون مضاعفة</span>
            <div className="p-2.5 rounded-xl bg-emerald-500/15 text-emerald-600 shadow-inner">
              <Coins className="size-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-black text-emerald-700 dark:text-emerald-300">{formatCurrency(totalOriginal)}</span>
          </div>
          <div className="mt-2 flex items-center gap-1.5 text-[11px] text-emerald-700 dark:text-emerald-300 font-bold">
            <Sparkles className="size-3.5" />
            <span>فارق إعفاء إداري ممكن: {formatCurrency(totalCurrent - totalOriginal)}</span>
          </div>
        </div>
      </div>

      {/* شريط البحث وفلاتر الحالة */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 p-2 bg-[var(--surface-raised)] border border-[var(--border)] rounded-2xl">
        <div className="relative flex-1">
          <Search className="size-4 absolute right-3.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)] pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="ابحث باسم الموظف، الكود، الإدارة، أو رقم الهاتف..."
            className="input w-full pr-10 pl-3 py-2 text-xs bg-[var(--surface-base)] border-[var(--border)] rounded-xl"
          />
        </div>

        <div className="flex items-center gap-1 self-center sm:self-auto overflow-x-auto">
          <button
            type="button"
            onClick={() => setStatusFilter('all')}
            className={`px-3 py-1.5 text-xs font-bold rounded-xl transition-all cursor-pointer ${
              statusFilter === 'all'
                ? 'bg-[var(--brand-primary)] text-white shadow-sm'
                : 'text-[var(--text-muted)] hover:bg-[var(--surface-muted)]'
            }`}
          >
            الكل ({rawList.length})
          </button>
          <button
            type="button"
            onClick={() => setStatusFilter('suspended_only')}
            className={`px-3 py-1.5 text-xs font-bold rounded-xl transition-all cursor-pointer flex items-center gap-1 ${
              statusFilter === 'suspended_only'
                ? 'bg-rose-600 text-white shadow-sm'
                : 'text-rose-600 dark:text-rose-400 hover:bg-rose-500/10'
            }`}
          >
            <span className="size-2 rounded-full bg-rose-500" />
            <span>موقوف فعلياً ({actuallySuspendedCount})</span>
          </button>
          <button
            type="button"
            onClick={() => setStatusFilter('doubled_only')}
            className={`px-3 py-1.5 text-xs font-bold rounded-xl transition-all cursor-pointer flex items-center gap-1 ${
              statusFilter === 'doubled_only'
                ? 'bg-amber-600 text-white shadow-sm'
                : 'text-amber-600 dark:text-amber-400 hover:bg-amber-500/10'
            }`}
          >
            <span className="size-2 rounded-full bg-amber-500" />
            <span>غرامات 500 ج.م ({doubledOnlyCount})</span>
          </button>
        </div>
      </div>

      {/* قائمة بطاقات الموظفين */}
      {isLoading ? (
        <ListSkeleton rows={3} label="جارٍ تحميل الموظفين الموقوفين…" />
      ) : error ? (
        <div className="card p-6 border-rose-500/30 text-rose-700 text-center rounded-2xl">
          <AlertTriangle className="size-8 mx-auto mb-2 text-rose-500" />
          <p className="font-bold">تعذر تحميل بيانات الموظفين الموقوفين</p>
          <p className="text-xs text-[var(--text-muted)] mt-1">{safeErrorMessage(error)}</p>
          <button
            type="button"
            onClick={() => void refetch()}
            className="btn-secondary text-xs mt-3 cursor-pointer"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : filteredList.length === 0 ? (
        <div className="card p-12 text-center border-dashed border-[var(--border)] rounded-2xl">
          <div className="size-16 rounded-full bg-emerald-500/15 text-emerald-600 flex items-center justify-center mx-auto mb-4">
            <CheckCircle2 className="size-8" />
          </div>
          <h3 className="text-base font-black text-[var(--text-strong)]">
            {rawList.length === 0
              ? 'لا يوجد موظفون موقوفون عن العمل حالياً'
              : 'لا توجد نتائج مطابقة لمعايير البحث والتصفية'}
          </h3>
          <p className="text-sm text-[var(--text-muted)] mt-1 max-w-md mx-auto">
            {rawList.length === 0
              ? 'كافة حسابات منسوبي الجمعية نشطة ومستقرة، ولا توجد غرامات متجاوزة لمهلة السداد حالياً.'
              : 'جرّب تعديل كلمة البحث أو تغيير الفلتر لعرض السجلات.'}
          </p>
        </div>
      ) : (
        <div className="space-y-5">
          {filteredList.map((emp) => {
            const isActuallySuspended = emp.status === 'suspended' || !emp.isActive;
            return (
              <div
                key={emp.employeeId}
                className="card p-5 border border-rose-500/25 bg-[var(--surface-raised)]/30 hover:border-rose-500/40 transition-all rounded-2xl space-y-4 shadow-sm"
              >
                {/* ترويسة بطاقة الموظف */}
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="flex items-center gap-3.5">
                    <div className="shrink-0 relative">
                      <div className="rounded-full border-2 border-rose-500/40 p-0.5 overflow-hidden">
                        <UserAvatar
                          displayName={emp.employeeName}
                          photoUrl={emp.photoUrl}
                          size="lg"
                          announceName={false}
                        />
                      </div>
                      {isActuallySuspended ? (
                        <span
                          className="absolute -bottom-1 -right-1 size-4 bg-rose-600 border-2 border-[var(--surface-base)] rounded-full flex items-center justify-center"
                          title="حساب معلق عن العمل"
                        >
                          <Ban className="size-2.5 text-white" />
                        </span>
                      ) : (
                        <span
                          className="absolute -bottom-1 -right-1 size-4 bg-amber-500 border-2 border-[var(--surface-base)] rounded-full flex items-center justify-center"
                          title="نشط بمضاعفة"
                        >
                          <ShieldAlert className="size-2.5 text-white" />
                        </span>
                      )}
                    </div>

                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <h4 className="text-base font-black text-[var(--text-strong)]">{emp.employeeName}</h4>
                        {isActuallySuspended ? (
                          <span className="badge badge-danger text-[11px] font-black px-2.5 py-0.5 rounded-full flex items-center gap-1">
                            <Ban className="size-3" />
                            <span>موقوف عن العمل</span>
                          </span>
                        ) : (
                          <span className="badge badge-warning text-[11px] font-bold px-2.5 py-0.5 rounded-full flex items-center gap-1">
                            <Clock className="size-3" />
                            <span>نشط (مضاعفة 500 ج.م بانتظار السداد)</span>
                          </span>
                        )}
                      </div>

                      <div className="flex flex-wrap items-center gap-3 text-xs text-[var(--text-muted)] mt-1.5 font-medium">
                        {emp.departmentName && (
                          <span className="flex items-center gap-1 bg-[var(--surface-base)] px-2 py-0.5 rounded-md border border-[var(--border)]">
                            <Building className="size-3 text-[var(--text-muted)]" />
                            <span>{emp.departmentName}</span>
                          </span>
                        )}
                        {emp.jobTitle && (
                          <span className="bg-[var(--surface-base)] px-2 py-0.5 rounded-md border border-[var(--border)]">
                            {emp.jobTitle}
                          </span>
                        )}
                        {emp.phone && (
                          <div className="flex items-center gap-1.5 bg-[var(--surface-base)] px-2 py-0.5 rounded-md border border-[var(--border)] font-mono" dir="ltr">
                            <Phone className="size-3 text-[var(--text-muted)]" />
                            <span>{emp.phone}</span>
                            <button
                              type="button"
                              onClick={() => copyPhone(emp.phone!)}
                              className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer p-0.5"
                              title="نسخ رقم الهاتف"
                            >
                              {copiedPhone === emp.phone ? <Check className="size-3 text-emerald-600" /> : <Copy className="size-3" />}
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* ملخص المبالغ المالية */}
                  <div className="flex items-center gap-3 bg-[var(--surface-base)] border border-[var(--border)] rounded-2xl p-3 shadow-inner">
                    <div className="text-right">
                      <span className="text-[10px] text-[var(--text-muted)] font-bold block">المطلوب بالمضاعفة</span>
                      <span className="text-base font-black text-rose-600">{formatCurrency(emp.totalCurrentDue)}</span>
                    </div>
                    <div className="w-px h-8 bg-[var(--border)]" />
                    <div className="text-right">
                      <span className="text-[10px] text-[var(--text-muted)] font-bold block">الأصل دون مضاعفة</span>
                      <span className="text-base font-black text-emerald-600">{formatCurrency(emp.totalOriginalDue)}</span>
                    </div>
                  </div>
                </div>

                {/* جدول تفاصيل غرامات التأخير */}
                {emp.penalties.length > 0 && (
                  <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface-base)] shadow-inner">
                    <table className="w-full text-xs text-right">
                      <thead>
                        <tr className="border-b border-[var(--border)] bg-[var(--surface-muted)]/60 text-[var(--text-muted)] font-bold">
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
                            <td className="p-3 font-bold text-[var(--text-strong)]">
                              {formatArabicDate(pen.workDate)}
                            </td>
                            <td className="p-3 text-[var(--text-muted)]">
                              {formatLateMinutes(pen.lateMinutes)}
                            </td>
                            <td className="p-3 font-bold text-emerald-600">
                              <span className="px-2 py-0.5 rounded-md bg-emerald-500/10 border border-emerald-500/20">
                                {formatCurrency(pen.originalAmount)}
                              </span>
                            </td>
                            <td className="p-3 font-black text-rose-600">
                              <span className="px-2 py-0.5 rounded-md bg-rose-500/10 border border-rose-500/20">
                                {formatCurrency(pen.currentAmount)}
                              </span>
                            </td>
                            <td className="p-3">
                              <span className={`badge text-[10px] font-bold px-2 py-0.5 rounded-md ${
                                pen.status === 'suspended'
                                  ? 'badge-danger'
                                  : pen.status === 'doubled' || pen.currentAmount >= 500
                                  ? 'badge-warning'
                                  : 'badge-neutral'
                              }`}>
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
                                      setRevertPenaltyId(pen.id);
                                      setRevertPenaltyDesc(`غرامة يوم ${pen.workDate} (${formatCurrency(pen.currentAmount)} ← ${formatCurrency(pen.originalAmount)})`);
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
                )}

                {/* أزرار الإجراءات الإدارية الموحدة */}
                <div className="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-[var(--border)]">
                  <div className="flex flex-wrap items-center gap-2.5">
                    {/* 1) إرجاع كافة الغرامات للأصل */}
                    {emp.has500Penalty && (
                      <button
                        type="button"
                        onClick={() => handleRevertAllForEmp(emp)}
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

      {/* حوار رفع الإيقاف إدارياً */}
      {liftDialogOpen && selectedEmp && (
        <DialogOverlay
          title={`رفع الإيقاف عن الزميل ${selectedEmp.employeeName}`}
          onClose={() => setLiftDialogOpen(false)}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleLiftSubmit} className="space-y-4">
            <p className="text-sm text-[var(--text-muted)] leading-relaxed">
              سيتم إعادة فتح حساب الزميل <strong>{selectedEmp.employeeName}</strong> على المنظومة وتفعيله فوراً لمباشرة عمله، مع إرجاع أي غرامات موقوفة أو مضاعفة إلى قيمتها الأصلية وبانتظار السداد العادي.
            </p>
            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1">
                سبب رفع الإيقاف أو الملاحظة الإدارية (اختياري):
              </label>
              <textarea
                value={liftReason}
                onChange={(e) => setLiftReason(e.target.value)}
                rows={3}
                className="input w-full text-xs"
                placeholder="اكتب ملاحظة أو سبب قرار رفع الإيقاف..."
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setLiftDialogOpen(false)}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={liftLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer"
              >
                {liftLoading ? 'جارٍ رفع الإيقاف…' : 'تأكيد رفع الإيقاف'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}

      {/* حوار إرجاع الغرامة للأصل */}
      {revertDialogOpen && revertPenaltyId && (
        <DialogOverlay
          title="إرجاع الغرامة لقيمتها الأصلية بدون مضاعفة"
          onClose={() => setRevertDialogOpen(false)}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleRevertSubmit} className="space-y-4">
            <p className="text-sm text-[var(--text-muted)] leading-relaxed">
              سيتم إلغاء مضاعفة الـ 500 ج.م وإرجاع الغرامة ({revertPenaltyDesc}) إلى قيمتها الأصلية، لتصبح بانتظار السداد بالقيمة العادية حتى يتمكن الموظف من سدادها دون تعليق.
            </p>
            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1">
                سبب الإرجاع الإداري (اختياري):
              </label>
              <input
                type="text"
                value={revertReason}
                onChange={(e) => setRevertReason(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: مراعاة لظرف الموظف وطلب سداد القيمة الأصلية"
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setRevertDialogOpen(false)}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={revertLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-indigo-600 hover:bg-indigo-700 text-white cursor-pointer"
              >
                {revertLoading ? 'جارٍ الإرجاع…' : 'تأكيد إرجاع الغرامة للأصل'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}

      {/* حوار سداد الغرامة ورفع الإيقاف */}
      {paymentDialogOpen && paymentPenaltyId && selectedEmp && (
        <DialogOverlay
          title="تأكيد سداد الغرامة وتوريدها لصندوق الزمالة"
          onClose={() => setPaymentDialogOpen(false)}
          maxWidth="max-w-md"
        >
          <form onSubmit={handlePaymentSubmit} className="space-y-4">
            <p className="text-sm text-[var(--text-muted)] leading-relaxed">
              تأكيد استلام مبلغ <strong>{formatCurrency(paymentPenaltyAmount)}</strong> نقداً من الزميل <strong>{selectedEmp.employeeName}</strong> وتوريده بالكامل لصندوق الزمالة والتكافل.
              <br />
              <span className="text-emerald-600 font-bold mt-1 inline-block">
                ✨ سيتم رفع الإيقاف فوراً وإعادة فتح حساب الموظف على المنظومة.
              </span>
            </p>
            <div>
              <label className="block text-xs font-bold text-[var(--text-muted)] mb-1">
                ملاحظات التحصيل (اختياري):
              </label>
              <input
                type="text"
                value={paymentNotes}
                onChange={(e) => setPaymentNotes(e.target.value)}
                className="input w-full text-xs"
                placeholder="مثال: تم السداد نقداً لدى الـ HR"
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setPaymentDialogOpen(false)}
                className="btn-secondary text-xs cursor-pointer"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={paymentLoading}
                className="btn-primary flex items-center gap-1.5 text-xs bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer"
              >
                {paymentLoading ? 'جارٍ السداد…' : 'تأكيد السداد ورفع الإيقاف'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}
    </div>
  );
}
