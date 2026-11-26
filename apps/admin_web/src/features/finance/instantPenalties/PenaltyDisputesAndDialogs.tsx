import { MessageSquare } from 'lucide-react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { InputDialog } from '../../../ui/InputDialog';
import { dateFormatter, formatCurrency } from './penaltyFormatters';
import type { DisputeReviewTarget } from './PenaltySecondaryModals';

export interface PendingDisputeItem {
  id: string;
  employee_name: string;
  department?: string | null;
  penalty_date: string;
  penalty_amount: number;
  reason: string;
}

export interface PenaltyDisputesAndDialogsProps {
  disputes: PendingDisputeItem[];
  onReviewDispute: (target: DisputeReviewTarget) => void;

  paymentDialogOpen: boolean;
  paymentTarget: { id: string; name: string; msg: string } | null;
  paymentNotes: string;
  onPaymentNotesChange: (val: string) => void;
  paymentPending: boolean;
  paymentIsError: boolean;
  paymentError: unknown;
  onConfirmPayment: () => Promise<void>;
  onCancelPayment: () => void;

  liftDialogOpen: boolean;
  liftTarget: { id: string; name: string } | null;
  liftReason: string;
  onLiftReasonChange: (val: string) => void;
  liftPending: boolean;
  liftIsError: boolean;
  liftError: unknown;
  onConfirmLift: () => Promise<void>;
  onCancelLift: () => void;

  revertDialogOpen: boolean;
  revertTarget: { id: string; name: string; originalAmount: number } | null;
  revertReason: string;
  onRevertReasonChange: (val: string) => void;
  revertPending: boolean;
  revertIsError: boolean;
  revertError: unknown;
  onConfirmRevert: () => Promise<void>;
  onCancelRevert: () => void;

  cancelDialogOpen: boolean;
  cancelTarget: { id: string; name: string } | null;
  cancelReason: string;
  onCancelReasonChange: (val: string) => void;
  cancelPending: boolean;
  cancelIsError: boolean;
  cancelError: unknown;
  onConfirmCancel: () => Promise<void>;
  onCancelCancel: () => void;

  bulkCancelOpen: boolean;
  selectedCount: number;
  bulkCancelReason: string;
  onBulkCancelReasonChange: (val: string) => void;
  bulkCancelPending: boolean;
  bulkCancelIsError: boolean;
  bulkCancelError: unknown;
  onConfirmBulkCancel: () => Promise<void>;
  onCancelBulkCancel: () => void;
}

export function PenaltyDisputesAndDialogs(props: PenaltyDisputesAndDialogsProps) {
  const {
    disputes,
    onReviewDispute,
    paymentDialogOpen,
    paymentTarget,
    paymentNotes,
    onPaymentNotesChange,
    paymentPending,
    paymentIsError,
    paymentError,
    onConfirmPayment,
    onCancelPayment,
    liftDialogOpen,
    liftTarget,
    liftReason,
    onLiftReasonChange,
    liftPending,
    liftIsError,
    liftError,
    onConfirmLift,
    onCancelLift,
    revertDialogOpen,
    revertTarget,
    revertReason,
    onRevertReasonChange,
    revertPending,
    revertIsError,
    revertError,
    onConfirmRevert,
    onCancelRevert,
    cancelDialogOpen,
    cancelTarget,
    cancelReason,
    onCancelReasonChange,
    cancelPending,
    cancelIsError,
    cancelError,
    onConfirmCancel,
    onCancelCancel,
    bulkCancelOpen,
    selectedCount,
    bulkCancelReason,
    onBulkCancelReasonChange,
    bulkCancelPending,
    bulkCancelIsError,
    bulkCancelError,
    onConfirmBulkCancel,
    onCancelBulkCancel,
  } = props;

  return (
    <>
      {/* ─── الطعون المعلقة ────────────────────────────────────────── */}
      {disputes.length > 0 && (
        <section className="space-y-3">
          <div className="flex items-center gap-2">
            <MessageSquare className="size-4 text-blue-500" />
            <h2 className="text-sm font-black text-[var(--text-primary)]">طعون معلقة — تحتاج مراجعة</h2>
            <span className="rounded-full bg-blue-100 dark:bg-blue-950/50 px-2 py-0.5 text-[10px] font-black text-blue-700 dark:text-blue-400">
              {disputes.length}
            </span>
          </div>

          <div className="space-y-2">
            {disputes.map((d) => (
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
                  <p className="text-xs text-[var(--text-secondary)] mt-1 bg-[var(--surface-muted)]/50 rounded-lg px-2.5 py-1.5 inline-block">
                    "{d.reason}"
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <button
                    type="button"
                    onClick={() => onReviewDispute({ id: d.id, employeeName: d.employee_name, reason: d.reason })}
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
        inputPlaceholder="أي تفاصيل أو طريقة السداد…"
        inputValue={paymentNotes}
        onInputChange={onPaymentNotesChange}
        quickSuggestions={['سداد نقدي تم التوريد للخزينة', 'تحويل إنستاباي InstaPay', 'تحويل فودافون كاش', 'استقطاع من الحافز/الراتب']}
        confirmLabel="تأكيد الاستلام والإيداع بالصندوق"
        tone="info"
        required={false}
        loading={paymentPending}
        error={paymentIsError ? safeErrorMessage(paymentError) : null}
        onConfirm={onConfirmPayment}
        onCancel={onCancelPayment}
      />

      <InputDialog
        open={liftDialogOpen}
        title="رفع التعليق يدوياً"
        message={`هل تريد رفع التعليق عن ${liftTarget?.name ?? ''} بدون سداد؟ اذكر السبب:`}
        inputLabel="سبب رفع التعليق"
        inputPlaceholder="سبب رفع التعليق…"
        inputValue={liftReason}
        onInputChange={onLiftReasonChange}
        quickSuggestions={['تعهد بالسداد لاحقاً', 'مراعاة لظرف طارئ موثق', 'توجيه من المدير التنفيذي', 'استيفاء ساعات العمل والتزام']}
        confirmLabel="رفع التعليق"
        tone="warning"
        loading={liftPending}
        error={liftIsError ? safeErrorMessage(liftError) : null}
        onConfirm={onConfirmLift}
        onCancel={onCancelLift}
      />

      <InputDialog
        open={revertDialogOpen}
        title="إرجاع الغرامة لقيمتها الأصلية بدون مضاعفة"
        message={`هل تريد إرجاع غرامة ${revertTarget?.name ?? ''} من 500 ج.م إلى قيمتها الأصلية (${formatCurrency(revertTarget?.originalAmount)}) لتمكينه من السداد؟ اذكر السبب (اختياري):`}
        inputLabel="سبب الإرجاع الإداري (اختياري)"
        inputPlaceholder="مثال: مراعاة لظرف الموظف وطلب سداد القيمة الأصلية"
        inputValue={revertReason}
        onInputChange={onRevertReasonChange}
        quickSuggestions={['مراعاة لظرف الموظف واستعداده للسداد', 'توجيه إداري بالسداد بالقيمة الأصلية', 'طلب الموظف تسوية ودية']}
        confirmLabel="إرجاع للأصل"
        tone="info"
        loading={revertPending}
        error={revertIsError ? safeErrorMessage(revertError) : null}
        onConfirm={onConfirmRevert}
        onCancel={onCancelRevert}
      />

      <InputDialog
        open={cancelDialogOpen}
        title="إلغاء غرامة"
        message={`إلغاء غرامة ${cancelTarget?.name ?? ''} — اذكر السبب:`}
        inputLabel="سبب الإلغاء"
        inputPlaceholder="سبب الإلغاء…"
        inputValue={cancelReason}
        onInputChange={onCancelReasonChange}
        quickSuggestions={[
          'مأمورية عمل رسمية',
          'إذن تأخير مسبق ومعتمد',
          'عطل فني في شبكة/هاتف البصمة',
          'استيفاء ساعات العمل لاحقاً',
          'توجيه إداري / إعفاء خاص',
        ]}
        confirmLabel="إلغاء الغرامة"
        tone="danger"
        loading={cancelPending}
        error={cancelIsError ? safeErrorMessage(cancelError) : null}
        onConfirm={onConfirmCancel}
        onCancel={onCancelCancel}
      />

      {/* ─── نافذة الإلغاء الجماعي ────────────────────────────────── */}
      <InputDialog
        open={bulkCancelOpen}
        title="إلغاء جماعي للغرامات"
        message={`إلغاء ${selectedCount} غرامة محددة — اذكر السبب:`}
        inputLabel="سبب الإلغاء الجماعي"
        inputPlaceholder="سبب الإلغاء…"
        inputValue={bulkCancelReason}
        onInputChange={onBulkCancelReasonChange}
        quickSuggestions={['مأمورية عمل جماعية', 'عطل عام في أجهزة البصمة', 'توجيه إداري من الإدارة التنفيذية', 'إعفاء جماعي معتمد']}
        confirmLabel={`إلغاء ${selectedCount} غرامة`}
        tone="danger"
        loading={bulkCancelPending}
        error={bulkCancelIsError ? safeErrorMessage(bulkCancelError) : null}
        onConfirm={onConfirmBulkCancel}
        onCancel={onCancelBulkCancel}
      />
    </>
  );
}
