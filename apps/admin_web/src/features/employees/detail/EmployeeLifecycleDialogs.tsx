import { AlertTriangle } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { cairoTodayIso } from '../../../core/cairoTime';
import { safeErrorMessage } from '../../../core/errorMapper';
import { ArabicDateInput } from '../../../ui/ArabicDateInput';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { ErrorBanner } from '../../../ui/ErrorState';
import {
  useArchiveEmployee,
  useChangeManager,
  useDeleteEmployee,
  useEmployees,
  useGrantWeeklyRestCredit,
} from '../useEmployees';

export function ArchiveEmployeeDialog({
  employeeId,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const archive = useArchiveEmployee();
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);
    try {
      await archive.mutateAsync({ employeeId, reason: reason.trim() });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };
  return (
    <DialogOverlay title="أرشفة الموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <p className="muted text-sm">سيُعطّل حساب {employeeName} وتُسحب جلساته وأجهزته، مع الاحتفاظ بالسجل التاريخي.</p>
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الأرشفة</span>
          <textarea className="input min-h-24 w-full" required minLength={5} value={reason} onChange={(event) => setReason(event.target.value)} />
        </label>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
          <span>أؤكد تعطيل الحساب وسحب الجلسات والأجهزة الموثوقة.</span>
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={archive.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={archive.isPending || !confirmed || reason.trim().length < 5}>
            {archive.isPending ? 'جارٍ الأرشفة…' : 'تأكيد الأرشفة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

export function GrantRestCompDialog({
  employeeId,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const grant = useGrantWeeklyRestCredit();
  const [workDate, setWorkDate] = useState(cairoTodayIso());
  const [days, setDays] = useState(1);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await grant.mutateAsync({ employeeId, workDate, days });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="منح بدل راحة أسبوعي" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="muted text-sm">
          منح رصيد بدل راحة عن عمل يوم الجمعة للموظف <strong>{employeeName}</strong> — يُضاف للرصيد دون أي خصم من رصيد الإجازات.
        </p>

        {error ? <ErrorBanner message={error} /> : null}

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">تاريخ بداية العمل (الجمعة)</span>
          <ArabicDateInput className="input w-full" value={workDate} onChange={(e) => setWorkDate(e.target.value)} required disabled={grant.isPending} />
        </label>

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">عدد أيام البدل</span>
          <input
            type="number"
            className="input w-full"
            value={days}
            min={1}
            max={365}
            onChange={(e) => setDays(Number(e.target.value))}
            required
            disabled={grant.isPending}
          />
        </label>

        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={grant.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={grant.isPending || days < 1 || days > 365} className="btn-primary">
            {grant.isPending ? 'جارٍ المنح...' : 'منح الرصيد'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

export function ChangeManagerDialog({
  employeeId,
  currentManagerName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  currentManagerName: string | null;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const { data: employees } = useEmployees();
  const changeManager = useChangeManager();
  const [selectedManagerId, setSelectedManagerId] = useState<string>('');
  const [reason, setReason] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  const availableManagers = (employees ?? []).filter((e) => e.id !== employeeId && e.isActive);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await changeManager.mutateAsync({ employeeId, managerId: selectedManagerId || null, reason });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="تغيير المدير المباشر" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="muted text-sm">المدير الحالي: {currentManagerName ?? 'غير معين'}</p>

        {error ? <ErrorBanner message={error} /> : null}

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">اختر المدير الجديد</span>
          <select className="input w-full" value={selectedManagerId} onChange={(e) => setSelectedManagerId(e.target.value)} disabled={changeManager.isPending}>
            <option value="">بدون مدير مباشر</option>
            {availableManagers.map((emp) => (
              <option key={emp.id} value={emp.id}>
                {emp.fullNameAr} ({emp.employeeCode})
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب التغيير</span>
          <textarea
            className="input min-h-24 w-full"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            required
            minLength={3}
            disabled={changeManager.isPending}
          />
        </label>

        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={changeManager.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={changeManager.isPending || reason.trim().length < 3} className="btn-primary">
            {changeManager.isPending ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

export function DeleteEmployeeDialog({
  employeeId,
  employeeCode,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeCode: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const deleteEmployee = useDeleteEmployee();
  const [confirmText, setConfirmText] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const codeMatches = confirmText.trim() === employeeCode;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await deleteEmployee.mutateAsync({ employeeId, confirmationCode: confirmText.trim(), reason: reason.trim() });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="حذف الموظف نهائياً" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="flex items-center gap-2 rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]">
          <AlertTriangle className="size-4 shrink-0" aria-hidden="true" />
          سيتم حذف <strong>{employeeName}</strong> نهائياً من النظام. لا يمكن التراجع عن هذا الإجراء.
        </p>
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الحذف النهائي</span>
          <textarea
            className="input min-h-24 w-full"
            required
            minLength={10}
            placeholder="اكتب سبب الحذف هنا (10 أحرف على الأقل، مثال: استقالة الموظف أو حساب تجريبي)"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
        </label>
        {reason.trim().length < 10 ? (
          <span className="-mt-2 block text-xs text-[var(--muted)]">يجب إدخال سبب واضح لا يقل عن 10 أحرف (المدخل حالياً: {reason.trim().length} من 10).</span>
        ) : (
          <span className="-mt-2 block text-xs text-[var(--success)] font-medium">✓ سبب الحذف مستوفٍ للحد الأدنى المطلوب.</span>
        )}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">
            اكتب كود الموظف للتأكيد:{' '}
            <span dir="ltr" className="font-mono">
              {employeeCode}
            </span>
          </span>
          <input
            className="input w-full"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder={employeeCode}
            autoComplete="off"
            disabled={deleteEmployee.isPending}
          />
          {confirmText && !codeMatches ? (
            <span className="mt-1 block text-xs text-[var(--danger)]">كود الموظف غير متطابق تماماً مع ({employeeCode}).</span>
          ) : null}
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={deleteEmployee.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={deleteEmployee.isPending || !codeMatches || reason.trim().length < 10} className="btn-danger">
            {deleteEmployee.isPending ? 'جارٍ الحذف...' : 'حذف نهائي'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
