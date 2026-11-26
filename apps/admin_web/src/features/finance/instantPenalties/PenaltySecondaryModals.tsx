import { AlertTriangle, MessageCircle, RefreshCw, RotateCcw } from 'lucide-react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { openWhatsApp } from '../../../core/whatsappShare';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { buildRadarWhatsAppText, formatCurrency } from './penaltyFormatters';

export interface EarlyWarningEmployee {
  employeeId: string;
  employeeName: string;
  phone: string | null;
  count: number;
  totalAmount: number;
  dates: string[];
  isSuspended: boolean;
}

export interface DisputeReviewTarget {
  id: string;
  employeeName: string;
  reason: string;
}

export interface OvertimeSummaryData {
  totalOvertimeFormatted?: string | null;
  employeesCount?: number | null;
  totalOvertimeMinutes?: number | null;
  employees?: Array<{
    employeeId: string;
    employeeName: string;
    employeeCode?: string | null;
    departmentName?: string | null;
    isStillWorking?: boolean;
    overtimeFormatted: string;
    overtimeMinutes: number;
  }>;
}

export function DisputeReviewModal({
  target,
  note,
  onNoteChange,
  isPending,
  isError,
  error,
  onSubmit,
  onClose,
}: {
  target: DisputeReviewTarget | null;
  note: string;
  onNoteChange: (val: string) => void;
  isPending: boolean;
  isError: boolean;
  error: unknown;
  onSubmit: (status: 'approved' | 'rejected') => void;
  onClose: () => void;
}) {
  if (!target) return null;

  return (
    <DialogOverlay onClose={onClose} title={`مراجعة طعن — ${target.employeeName}`}>
      <div className="space-y-4">
        <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/30 p-4">
          <p className="text-xs text-[var(--text-muted)]">سبب الطعن:</p>
          <p className="text-sm font-bold text-[var(--text-primary)] mt-1">{target.reason}</p>
        </div>

        <div>
          <label className="block text-xs font-bold text-[var(--text-primary)] mb-1.5">ملاحظات المراجعة (اختياري)</label>
          <textarea
            value={note}
            onChange={(e) => onNoteChange(e.target.value)}
            placeholder="أي ملاحظات على قرار المراجعة…"
            rows={3}
            className="input-field w-full text-sm resize-none"
          />
        </div>

        {isError && <p className="text-xs text-[var(--danger)]">{safeErrorMessage(error)}</p>}

        <div className="flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
          >
            إلغاء
          </button>
          <button
            type="button"
            onClick={() => onSubmit('rejected')}
            disabled={isPending}
            className="px-4 py-2 text-xs font-black text-red-600 dark:text-red-400 border border-red-300 dark:border-red-700 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/30 transition-colors"
          >
            رفض الطعن
          </button>
          <button type="button" onClick={() => onSubmit('approved')} disabled={isPending} className="btn-primary text-xs !py-2 !px-4">
            {isPending ? 'جارٍ…' : 'قبول الطعن'}
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}

export function EarlyWarningRadarModal({
  open,
  employees,
  onClose,
}: {
  open: boolean;
  employees: EarlyWarningEmployee[];
  onClose: () => void;
}) {
  if (!open) return null;

  return (
    <DialogOverlay
      title="رادار الإنذار المبكر — الزملاء الأكثر عرضة للمضاعفة أو التعليق"
      onClose={onClose}
      maxWidth="max-w-2xl"
    >
      <div className="space-y-4">
        <p className="text-xs text-[var(--text-muted)] -mt-2">تنبيهات ودية تشجيعية مجانية 100% عبر الواتساب لتشجيع الانضباط قبل تفاقم الغرامات</p>

        <div className="overflow-y-auto max-h-[60vh] space-y-2.5 pr-1">
          {employees.length === 0 ? (
            <div className="text-center py-8 text-[var(--text-muted)] text-sm">ممتاز! لا يوجد أي زميل لديه تكرار تأخير حالياً.</div>
          ) : (
            employees.map((emp) => (
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
                  onClick={() => openWhatsApp(buildRadarWhatsAppText(emp), emp.phone)}
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
          <button type="button" onClick={onClose} className="btn-secondary text-xs !py-1.5 !px-3">
            إغلاق
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}

export function ResetExperimentalModal({
  open,
  isPending,
  resetError,
  onConfirm,
  onClose,
}: {
  open: boolean;
  isPending: boolean;
  resetError: string | null;
  onConfirm: () => Promise<void>;
  onClose: () => void;
}) {
  if (!open) return null;

  return (
    <DialogOverlay title="تصفير الدفع التجريبي وصندوق الزمالة" onClose={() => !isPending && onClose()} maxWidth="max-w-md">
      <div className="space-y-4 text-start">
        <div className="rounded-xl border border-rose-500/30 bg-rose-50/50 dark:bg-rose-950/20 p-3.5 text-xs text-rose-800 dark:text-rose-300 space-y-2">
          <div className="flex items-center gap-2 font-bold text-sm text-rose-700 dark:text-rose-400">
            <AlertTriangle className="size-4 shrink-0" />
            <span>إجراء تصفير البيانات التجريبية</span>
          </div>
          <p className="leading-relaxed">هذا الإجراء يقوم بما يلي:</p>
          <ul className="list-disc list-inside space-y-1 text-[11px] font-medium">
            <li>مسح وتصفير كافة حركات صندوق الزمالة والتكافل السابقة وإعادة الرصيد إلى 0.00 ج.م.</li>
            <li>إلغاء وتصفير السداد عن جميع الموظفين الذين قاموا بالدفع التجريبي سابقاً وإعادتها لحالة ملغاة تجريبياً مع إخلاء طرفهم.</li>
            <li>تسجيل حركة تدقيق إداري (Audit Log) بالعملية.</li>
          </ul>
        </div>

        {resetError && (
          <div className="rounded-lg bg-red-50 dark:bg-red-950/30 p-2.5 text-xs text-red-600 dark:text-red-400 border border-red-200 dark:border-red-900/30">
            {resetError}
          </div>
        )}

        <div className="flex items-center justify-end gap-2 pt-2 border-t border-[var(--border)]">
          <button type="button" onClick={onClose} disabled={isPending} className="btn-secondary text-xs !py-2 !px-4 cursor-pointer">
            إلغاء
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isPending}
            className="btn-primary !bg-rose-600 hover:!bg-rose-700 text-white text-xs !py-2 !px-4 inline-flex items-center gap-1.5 cursor-pointer"
          >
            {isPending ? (
              <>
                <RefreshCw className="size-3.5 animate-spin" />
                <span>جارٍ التصفير...</span>
              </>
            ) : (
              <>
                <RotateCcw className="size-3.5" />
                <span>تأكيد التصفير الآن</span>
              </>
            )}
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}

export function OvertimeSummaryModal({
  open,
  data,
  onClose,
}: {
  open: boolean;
  data?: OvertimeSummaryData | null;
  onClose: () => void;
}) {
  if (!open) return null;

  return (
    <DialogOverlay title="بيان ساعات العمل الإضافي لليوم (Overtime Hub)" onClose={onClose} maxWidth="max-w-2xl">
      <div className="space-y-4 max-h-[75vh] overflow-y-auto p-1">
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <div className="rounded-lg bg-[var(--surface-muted)] p-3 border border-[var(--border-subtle)] text-center">
            <p className="text-xs text-[var(--text-muted)]">إجمالي الساعات الإضافية</p>
            <p className="font-bold font-mono text-base text-teal-600 dark:text-teal-400 mt-0.5">{data?.totalOvertimeFormatted || '0'}</p>
          </div>
          <div className="rounded-lg bg-[var(--surface-muted)] p-3 border border-[var(--border-subtle)] text-center">
            <p className="text-xs text-[var(--text-muted)]">عدد الموظفين المستحقين</p>
            <p className="font-bold font-mono text-base text-[var(--text-primary)] mt-0.5">{data?.employeesCount ?? 0} موظفاً</p>
          </div>
          <div className="rounded-lg bg-[var(--surface-muted)] p-3 border border-[var(--border-subtle)] text-center col-span-2 sm:col-span-1">
            <p className="text-xs text-[var(--text-muted)]">إجمالي الدقائق الإضافية</p>
            <p className="font-bold font-mono text-base text-[var(--text-secondary)] mt-0.5">{data?.totalOvertimeMinutes ?? 0} دقيقة</p>
          </div>
        </div>

        <div className="divide-y divide-[var(--border-subtle)] rounded-xl border border-[var(--border)] overflow-hidden">
          {(data?.employees ?? []).length === 0 ? (
            <div className="p-6 text-center text-xs text-[var(--text-muted)]">لا يوجد وقت إضافي مسجل لهذا اليوم حتى الآن.</div>
          ) : (
            (data?.employees ?? []).map((emp) => (
              <div key={emp.employeeId} className="p-3 bg-[var(--surface)] hover:bg-[var(--surface-muted)] flex items-center justify-between gap-3 text-xs">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-[var(--text-primary)] truncate">{emp.employeeName}</span>
                    {emp.isStillWorking && (
                      <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30">
                        مستمر بالعمل الآن
                      </span>
                    )}
                  </div>
                  <p className="text-[11px] text-[var(--text-muted)] mt-0.5">
                    {emp.departmentName || '—'} • كود: {emp.employeeCode}
                  </p>
                </div>

                <div className="flex items-center gap-3 shrink-0 text-left font-mono">
                  <div>
                    <span className="inline-flex items-center gap-1 font-bold text-teal-600 dark:text-teal-400 bg-teal-500/10 px-2 py-0.5 rounded border border-teal-500/20">
                      +{emp.overtimeFormatted}
                    </span>
                    <p className="text-[10px] text-[var(--text-muted)] mt-0.5 text-right">({emp.overtimeMinutes} دقيقة إضافية)</p>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </DialogOverlay>
  );
}
