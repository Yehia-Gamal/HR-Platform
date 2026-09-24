import { useState } from 'react';
import { Ban } from 'lucide-react';
import { InputDialog } from '../../ui/InputDialog';
import { safeErrorMessage } from '../../core/errorMapper';
import { useCanSuspendEmployees, usePendingSuspensions, useSuspendEmployeeForPenalty, type PendingSuspension } from './usePendingSuspensions';

const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

/**
 * لوحة قرار التعليق (0554).
 *
 * منذ 0550 لا يعلّق الكرون أحداً: من تجاوز مهلة سداد الغرامة المضاعفة يُسجَّل
 * «مستحقاً للتعليق» ويبقى القرار لإنسان مخوَّل. تظهر اللوحة فقط لمن يملك تغيير
 * حالة الموظف، وفقط حين يوجد مستحقون.
 */
export function PendingSuspensionsCard() {
  const canSuspend = useCanSuspendEmployees();
  const pending = usePendingSuspensions(canSuspend);
  const suspend = useSuspendEmployeeForPenalty();
  const [target, setTarget] = useState<PendingSuspension | null>(null);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (!canSuspend) return null;
  const items = pending.data ?? [];
  if (items.length === 0) return null;

  const open = (p: PendingSuspension) => {
    setTarget(p);
    setReason('');
    setError(null);
  };
  const close = () => {
    setTarget(null);
    setReason('');
    setError(null);
  };
  const confirm = () => {
    if (!target) return;
    const trimmed = reason.trim();
    if (trimmed.length < 3) {
      setError('سبب القرار مطلوب (3 أحرف على الأقل)');
      return;
    }
    suspend.mutate({ penaltyId: target.penaltyId, reason: trimmed }, { onSuccess: close, onError: (e) => setError(safeErrorMessage(e)) });
  };

  return (
    <section className="card p-5 border border-red-500/30" aria-labelledby="pending-suspensions-title">
      <div className="flex items-center gap-2">
        <Ban className="size-5 text-red-600 dark:text-red-400" aria-hidden="true" />
        <h2 id="pending-suspensions-title" className="font-black">
          مستحقون للتعليق — بانتظار قرارك
        </h2>
        <span className="rounded-full bg-red-500/10 px-2 py-0.5 text-xs font-bold text-red-700 dark:text-red-300">{items.length}</span>
      </div>
      <p className="muted mt-1 text-xs">تجاوزوا مهلة سداد الغرامة المضاعفة. لا يُعلَّق أحد تلقائياً — القرار لك، ويُسجَّل سببه في سجل التدقيق.</p>

      <ul className="mt-3 divide-y divide-[var(--border)]">
        {items.map((p) => (
          <li key={p.penaltyId} className="flex flex-wrap items-center justify-between gap-3 py-2.5">
            <div className="min-w-0">
              <div className="font-bold">
                {p.employeeName ?? '—'}
                {p.employeeCode && <span className="mr-2 font-mono text-xs text-[var(--text-muted)]">{p.employeeCode}</span>}
              </div>
              <div className="text-xs text-[var(--text-muted)]">
                {p.departmentName ?? '—'} · غرامة يوم {p.workDate} · {currencyFmt.format(p.amount)} · متأخر {p.daysOverdue} يوم
              </div>
            </div>
            <button type="button" className="btn-danger" aria-label={`تعليق ${p.employeeName ?? 'الموظف'}`} onClick={() => open(p)}>
              تعليق
            </button>
          </li>
        ))}
      </ul>

      <InputDialog
        open={target !== null}
        tone="danger"
        title="تأكيد تعليق الموظف"
        message={
          target ? `سيُغلق حساب ${target.employeeName ?? 'الموظف'} على السيستم ويُرسَل إشعار لكامل الفريق. يُرفع التعليق بالسداد أو بقرار رفع التعليق.` : ''
        }
        inputLabel="سبب القرار"
        inputPlaceholder="مثال: لم يُسدَّد المبلغ رغم التذكير"
        inputValue={reason}
        onInputChange={setReason}
        required
        minLength={3}
        confirmLabel="تعليق الموظف"
        loading={suspend.isPending}
        error={error}
        onConfirm={confirm}
        onCancel={close}
      />
    </section>
  );
}
