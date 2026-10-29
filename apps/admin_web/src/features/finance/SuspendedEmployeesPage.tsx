import { useState } from 'react';
import {
  Ban,
  CheckCircle2,
  AlertTriangle,
  RotateCcw,
  Coins,
  MessageCircle,
  ShieldAlert,
  ArrowRight,
  Phone,
  Building,
  UserCheck,
} from 'lucide-react';
import { PageHeader } from '../../ui/PageHeader';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
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

export function SuspendedEmployeesPage() {
  const { data: employees, isLoading, error } = useSuspendedEmployeesAdmin();
  const liftSuspension = useLiftEmployeeSuspensionAdmin();
  const revertPenalty = useRevertDoubledPenalty();
  const confirmPayment = useConfirmInstantPenaltyPayment();
  const { toast } = useToast();

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

  const list = employees ?? [];
  const totalCurrent = list.reduce((s, e) => s + (e.totalCurrentDue || 0), 0);
  const totalOriginal = list.reduce((s, e) => s + (e.totalOriginalDue || 0), 0);

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
        message: `تم رفع الإيقاف عن ${selectedEmp.employeeName} وإعادة تفعيل حسابه بنجاح`,
        tone: 'success',
      });
      setLiftDialogOpen(false);
      setLiftReason('');
      setSelectedEmp(null);
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
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
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
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
        message: `تم إرجاع كافة غرامات ${emp.employeeName} إلى قيمتها الأصلية (${formatCurrency(emp.totalOriginalDue)}) بنجاح`,
        tone: 'success',
      });
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
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
        message: 'تم تسجيل السداد وإيداع المبلغ في صندوق الزمالة ورفع الإيقاف بنجاح',
        tone: 'success',
      });
      setPaymentDialogOpen(false);
      setPaymentNotes('');
      setPaymentPenaltyId(null);
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
    } finally {
      setPaymentLoading(false);
    }
  };

  // إرسال تنبيه واتساب
  const sendWhatsAppReminder = (emp: SuspendedEmployeeAdmin) => {
    const text =
      `*إشعار هام وعاجل من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️\n\n` +
      `السلام عليكم ورحمة الله، أستاذ *${emp.employeeName}* 🌸\n\n` +
      `نود إحاطتكم بأنه قد تم *تعليق حسابكم مؤقتاً على السيستم* لتجاوز مهلة سداد غرامات الحضور والانصراف.\n\n` +
      `📌 *إجمالي المبلغ المطلوب لسداد الغرامات ورفع الإيقاف:* *${formatCurrency(emp.totalCurrentDue)}* (أصل الغرامات: *${formatCurrency(emp.totalOriginalDue)}*).\n\n` +
      `يرجى سرعة التوجه للـ HR أو التواصل مع الإدارة للسداد وإعادة فتح الحساب فوراً لمباشرة العمل.\n\n` +
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
        description="إدارة ومتابعة الموظفين المعلقين عن العمل بسبب غرامات الحضور والانصراف المتجاوزة للمهلة. يمكن سداد الغرامة لرفع الإيقاف فوراً، أو إرجاع الغرامات لقيمتها الأصلية (20/50/150 ج.م) بدون مضاعفة، أو رفع الإيقاف إدارياً."
      />

      {/* بطاقات الإحصائيات العلوية */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="card p-5 bg-gradient-to-br from-rose-500/10 via-rose-500/5 to-transparent border-rose-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-rose-700 dark:text-rose-300">الموقوفون عن العمل</span>
            <div className="p-2 rounded-xl bg-rose-500/15 text-rose-600">
              <Ban className="size-5" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-black text-rose-700 dark:text-rose-300">{list.length}</span>
            <span className="text-xs text-[var(--text-muted)]">موظف</span>
          </div>
          <p className="mt-1 text-xs text-[var(--text-muted)]">حساباتهم معلقة بانتظار الإجراء</p>
        </div>

        <div className="card p-5 bg-gradient-to-br from-amber-500/10 via-amber-500/5 to-transparent border-amber-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-amber-700 dark:text-amber-300">المطلوب بالمضاعفة (500 ج.م)</span>
            <div className="p-2 rounded-xl bg-amber-500/15 text-amber-600">
              <ShieldAlert className="size-5" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-black text-amber-700 dark:text-amber-300">{formatCurrency(totalCurrent)}</span>
          </div>
          <p className="mt-1 text-xs text-[var(--text-muted)]">إجمالي المبالغ الحالية مع المضاعفة</p>
        </div>

        <div className="card p-5 bg-gradient-to-br from-emerald-500/10 via-emerald-500/5 to-transparent border-emerald-500/20">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-emerald-700 dark:text-emerald-300">أصل الغرامات بدون مضاعفة</span>
            <div className="p-2 rounded-xl bg-emerald-500/15 text-emerald-600">
              <Coins className="size-5" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-black text-emerald-700 dark:text-emerald-300">{formatCurrency(totalOriginal)}</span>
          </div>
          <p className="mt-1 text-xs text-[var(--text-muted)]">المبلغ المستحق حال إرجاعها للأصل</p>
        </div>
      </div>

      {/* قائمة الموظفين */}
      {isLoading ? (
        <ListSkeleton rows={3} label="جارٍ تحميل الموظفين الموقوفين…" />
      ) : error ? (
        <div className="card p-6 border-rose-500/30 text-rose-700 text-center">
          <AlertTriangle className="size-8 mx-auto mb-2 text-rose-500" />
          <p className="font-bold">تعذر تحميل بيانات الموظفين الموقوفين</p>
          <p className="text-xs text-[var(--text-muted)] mt-1">{safeErrorMessage(error)}</p>
        </div>
      ) : list.length === 0 ? (
        <div className="card p-12 text-center border-dashed border-[var(--border)]">
          <div className="size-16 rounded-full bg-emerald-500/15 text-emerald-600 flex items-center justify-center mx-auto mb-4">
            <CheckCircle2 className="size-8" />
          </div>
          <h3 className="text-base font-black text-[var(--text-strong)]">لا يوجد موظفون موقوفون عن العمل</h3>
          <p className="text-sm text-[var(--text-muted)] mt-1 max-w-md mx-auto">
            كافة حسابات منسوبي الجمعية نشطة ومستقرة، ولا توجد غرامات متجاوزة لمهلة السداد حالياً.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {list.map((emp) => (
            <div
              key={emp.employeeId}
              className="card p-5 border border-rose-500/25 bg-gradient-to-r from-rose-500/5 via-transparent to-transparent hover:border-rose-500/40 transition-all space-y-4"
            >
              {/* ترويسة الموظف */}
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="size-12 rounded-full overflow-hidden bg-[var(--surface-muted)] border-2 border-rose-500/30 flex items-center justify-center text-lg font-black text-rose-600 shrink-0">
                    {emp.photoUrl ? (
                      <img src={emp.photoUrl} alt={emp.employeeName} className="size-full object-cover" />
                    ) : (
                      emp.employeeName.slice(0, 2)
                    )}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="text-base font-black text-[var(--text-strong)]">{emp.employeeName}</h4>
                      <span className="badge badge-danger text-xs font-bold px-2 py-0.5">موقوف عن العمل</span>
                    </div>
                    <div className="flex flex-wrap items-center gap-3 text-xs text-[var(--text-muted)] mt-1">
                      {emp.departmentName && (
                        <span className="flex items-center gap-1">
                          <Building className="size-3.5" /> {emp.departmentName}
                        </span>
                      )}
                      {emp.phone && (
                        <span className="flex items-center gap-1 font-mono" dir="ltr">
                          <Phone className="size-3.5" /> {emp.phone}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* المبالغ */}
                <div className="flex items-center gap-3 bg-[var(--surface-raised)] border border-[var(--border)] rounded-xl p-3">
                  <div className="text-right">
                    <span className="text-[11px] text-[var(--text-muted)] block">المطلوب بالمضاعفة</span>
                    <span className="text-base font-black text-rose-600">{formatCurrency(emp.totalCurrentDue)}</span>
                  </div>
                  <div className="w-px h-8 bg-[var(--border)]" />
                  <div className="text-right">
                    <span className="text-[11px] text-[var(--text-muted)] block">الأصل دون مضاعفة</span>
                    <span className="text-base font-black text-emerald-600">{formatCurrency(emp.totalOriginalDue)}</span>
                  </div>
                </div>
              </div>

              {/* جدول غرامات هذا الموظف */}
              {emp.penalties.length > 0 && (
                <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/30">
                  <table className="w-full text-xs text-right">
                    <thead>
                      <tr className="border-b border-[var(--border)] text-[var(--text-muted)]">
                        <th className="p-2.5 font-bold">تاريخ العمل</th>
                        <th className="p-2.5 font-bold">التأخير</th>
                        <th className="p-2.5 font-bold">القيمة الأصلية</th>
                        <th className="p-2.5 font-bold">القيمة الحالية (المضاعفة)</th>
                        <th className="p-2.5 font-bold">الحالة</th>
                        <th className="p-2.5 font-bold text-center">إجراء على الغرامة</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border)]">
                      {emp.penalties.map((pen) => (
                        <tr key={pen.id} className="hover:bg-[var(--surface-raised)]/50">
                          <td className="p-2.5 font-bold">{pen.workDate}</td>
                          <td className="p-2.5 text-[var(--text-muted)]">{pen.lateMinutes} دقيقة</td>
                          <td className="p-2.5 font-bold text-emerald-600">{formatCurrency(pen.originalAmount)}</td>
                          <td className="p-2.5 font-black text-rose-600">{formatCurrency(pen.currentAmount)}</td>
                          <td className="p-2.5">
                            <span className="badge badge-warning text-[10px] px-2 py-0.5">
                              {pen.status === 'suspended' ? 'إيقاف ومضاعفة' : pen.status === 'doubled' ? 'مضاعفة 500 ج.م' : 'بانتظار السداد'}
                            </span>
                          </td>
                          <td className="p-2.5 text-center">
                            <div className="flex items-center justify-center gap-1.5">
                              {/* زر سداد هذه الغرامة */}
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedEmp(emp);
                                  setPaymentPenaltyId(pen.id);
                                  setPaymentPenaltyAmount(pen.currentAmount);
                                  setPaymentNotes('');
                                  setPaymentDialogOpen(true);
                                }}
                                className="inline-flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-bold bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer shadow-sm"
                                title="تحصيل الغرامة وإيداعها بصندوق الزمالة ورفع الإيقاف"
                              >
                                <Coins className="size-3" />
                                <span>سداد ({formatCurrency(pen.currentAmount)})</span>
                              </button>

                              {/* زر إرجاع هذه الغرامة للأصل */}
                              {pen.currentAmount > pen.originalAmount && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setRevertPenaltyId(pen.id);
                                    setRevertPenaltyDesc(`غرامة يوم ${pen.workDate} (${formatCurrency(pen.currentAmount)} ← ${formatCurrency(pen.originalAmount)})`);
                                    setRevertReason('');
                                    setRevertDialogOpen(true);
                                  }}
                                  className="inline-flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-bold bg-indigo-50 hover:bg-indigo-100 text-indigo-700 dark:bg-indigo-950/40 dark:text-indigo-300 border border-indigo-300 dark:border-indigo-800 cursor-pointer"
                                  title={`إرجاع هذه الغرامة لأصلها (${formatCurrency(pen.originalAmount)}) بدون مضاعفة`}
                                >
                                  <RotateCcw className="size-3 text-indigo-600 dark:text-indigo-400" />
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
              <div className="flex flex-wrap items-center gap-2 pt-2 border-t border-[var(--border)]">
                {/* 1) إرجاع كافة الغرامات للأصل */}
                {emp.has500Penalty && (
                  <button
                    type="button"
                    onClick={() => handleRevertAllForEmp(emp)}
                    className="btn-secondary flex items-center gap-1.5 text-xs text-indigo-700 dark:text-indigo-300 border-indigo-500/30 hover:bg-indigo-500/10 cursor-pointer"
                    title={`إرجاع كافة غرامات الموظف المضاعفة إلى قيمتها الأصلية (${formatCurrency(emp.totalOriginalDue)})`}
                  >
                    <RotateCcw className="size-3.5 text-indigo-600" />
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
                  className="btn-secondary flex items-center gap-1.5 text-xs text-emerald-700 dark:text-emerald-300 border-emerald-500/30 hover:bg-emerald-500/10 cursor-pointer"
                  title="رفع الإيقاف إدارياً وإعادة فتح الحساب فوراً"
                >
                  <UserCheck className="size-3.5 text-emerald-600" />
                  <span>رفع الإيقاف إدارياً وتفعيل الحساب</span>
                </button>

                {/* 3) تنبيه واتساب */}
                <button
                  type="button"
                  onClick={() => sendWhatsAppReminder(emp)}
                  className="btn-secondary flex items-center gap-1.5 text-xs text-emerald-700 dark:text-emerald-300 border-emerald-500/30 hover:bg-emerald-500/10 cursor-pointer"
                  title="إرسال رسالة تذكير للموظف عبر واتساب بالسداد"
                >
                  <MessageCircle className="size-3.5 text-emerald-600" />
                  <span>تنبيه واتساب</span>
                </button>
              </div>
            </div>
          ))}
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
              سيتم إعادة فتح حساب الزميل <strong>{selectedEmp.employeeName}</strong> على المنظومة وتفعيله فوراً لمباشرة عمله، مع إرجاع أي غرامات موقوفة أو مضاعفة إلى قيمتها الأصلية وبانتظار السداد.
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
                ✨ سيتم رفع الإيقاف فوراً وإعادة فتح حساب الموظف على السيستم.
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

