import { useState } from 'react';
import { Clock, Calendar, CheckCircle2, Info } from 'lucide-react';
import { cairoTodayIso } from '../../core/cairoTime';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner } from '../../ui/ErrorState';
import { useToast } from '../../ui/Toast';
import {
  formatShiftTiming,
  useAvailableShifts,
  useEmployeeActiveShift,
  useSetEmployeeShiftAdmin,
} from './useEmployees';

interface AssignShiftDialogProps {
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  onClose: () => void;
  onSuccess?: () => void;
}

export function AssignShiftDialog({
  employeeId,
  employeeName,
  employeeCode,
  onClose,
  onSuccess,
}: AssignShiftDialogProps) {
  const { toast } = useToast();
  const activeShiftQuery = useEmployeeActiveShift(employeeId);
  const availableShiftsQuery = useAvailableShifts();
  const setShiftMutation = useSetEmployeeShiftAdmin();

  const currentShiftId = activeShiftQuery.data?.shiftId ?? '';
  const [selectedShiftId, setSelectedShiftId] = useState<string>(currentShiftId);
  const [effectiveFrom, setEffectiveFrom] = useState<string>(cairoTodayIso());
  const [notes, setNotes] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  // If initial state was empty and query finishes, sync selectedShiftId
  if (!selectedShiftId && currentShiftId) {
    setSelectedShiftId(currentShiftId);
  }

  const shifts = availableShiftsQuery.data ?? [];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedShiftId) {
      setError('يرجى تحديد فترة العمل المراد إسنادها للموظف.');
      return;
    }
    setError(null);
    try {
      await setShiftMutation.mutateAsync({
        employeeId,
        shiftId: selectedShiftId,
        effectiveFrom: effectiveFrom || undefined,
        notes: notes.trim() || undefined,
      });
      toast({
        message: 'تم إسناد فترة العمل وتحديث وردية الموظف بنجاح.',
        tone: 'success',
      });
      onSuccess?.();
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="إسناد وتغيير فترة العمل (الوردية)" onClose={onClose} maxWidth="max-w-xl">
      <div className="mb-4">
        <p className="text-sm font-bold text-[var(--text)]">
          {employeeName}
          <span className="muted ms-2 font-mono text-xs">({employeeCode})</span>
        </p>
        <p className="text-xs text-[var(--text-secondary)] mt-0.5">
          تحديد الوردية الأساسية المعتمدة للموظف لاحتساب الحضور ودقائق التأخير ومواعيد الانصراف.
        </p>
      </div>

      {error ? <ErrorBanner message={error} /> : null}

      <form onSubmit={(e) => void handleSubmit(e)} className="space-y-5">
        <div>
          <label className="block text-sm font-bold mb-2">
            فترات العمل المتاحة بالمنظومة <span className="text-[var(--danger)]">*</span>
          </label>
          <div className="space-y-2">
            {availableShiftsQuery.isLoading ? (
              <div className="p-4 text-center text-xs text-[var(--text-secondary)]">جارٍ تحميل الورديات…</div>
            ) : shifts.length === 0 ? (
              <div className="p-4 text-center text-xs text-[var(--text-secondary)]">لا توجد ورديات متاحة</div>
            ) : (
              shifts.map((shift) => {
                const isSelected = selectedShiftId === shift.id;
                const isCurrent = activeShiftQuery.data?.shiftId === shift.id;
                return (
                  <label
                    key={shift.id}
                    className={`flex items-start gap-3 p-3.5 rounded-2xl border transition-all cursor-pointer ${
                      isSelected
                        ? 'border-[var(--brand-primary)] bg-[var(--brand-primary-soft)]/20 shadow-sm'
                        : 'border-[var(--border)] hover:bg-[var(--surface-muted)]'
                    }`}
                  >
                    <input
                      type="radio"
                      name="shiftSelection"
                      value={shift.id}
                      checked={isSelected}
                      onChange={() => setSelectedShiftId(shift.id)}
                      className="mt-1"
                      disabled={setShiftMutation.isPending}
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-sm">{shift.name}</span>
                        {isCurrent ? (
                          <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs font-bold text-emerald-600 border border-emerald-500/20">
                            <CheckCircle2 className="size-3" />
                            الوردية الحالية
                          </span>
                        ) : null}
                      </div>
                      <p className="text-xs text-[var(--text-secondary)] mt-1 flex items-center gap-1.5 font-sans">
                        <Clock className="size-3.5 text-[var(--brand-primary)]" />
                        {formatShiftTiming(shift.startTime, shift.endTime, shift.graceInMinutes)}
                      </p>
                    </div>
                  </label>
                );
              })
            )}
          </div>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block">
            <span className="mb-1.5 block text-xs font-bold">
              تاريخ سريان الوردية <span className="text-[var(--danger)]">*</span>
            </span>
            <div className="relative">
              <input
                type="date"
                required
                className="input w-full"
                value={effectiveFrom}
                onChange={(e) => setEffectiveFrom(e.target.value)}
                disabled={setShiftMutation.isPending}
              />
            </div>
            <span className="text-[11px] text-[var(--text-secondary)] mt-1 block">
              يبدأ تطبيق الوردية واحتساب التأخيرات بناءً عليها من هذا التاريخ.
            </span>
          </label>

          <label className="block">
            <span className="mb-1.5 block text-xs font-bold">ملاحظات / سبب التغيير (اختياري)</span>
            <input
              type="text"
              className="input w-full"
              placeholder="مثال: بناءً على طلب الموظف أو تكليف جديد"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              disabled={setShiftMutation.isPending}
            />
          </label>
        </div>

        <div className="rounded-xl bg-[var(--surface-muted)] p-3 text-xs text-[var(--text-secondary)] flex items-start gap-2">
          <Info className="size-4 shrink-0 text-[var(--brand-primary)] mt-0.5" />
          <span>
            سيتم تحديث الوردية المقررة فوراً، وتُحسب التأخيرات وساعات العمل اليومية تلقائياً وفقاً للوردية المعتمدة الجديدة.
          </span>
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <button
            type="button"
            className="btn-secondary"
            onClick={onClose}
            disabled={setShiftMutation.isPending}
          >
            إلغاء
          </button>
          <button
            type="submit"
            className="btn-primary"
            disabled={setShiftMutation.isPending || !selectedShiftId}
          >
            {setShiftMutation.isPending ? 'جارٍ الحفظ…' : 'حفظ وإسناد الوردية'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
