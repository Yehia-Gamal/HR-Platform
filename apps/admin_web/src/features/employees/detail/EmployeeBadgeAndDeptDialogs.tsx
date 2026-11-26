import type { Employee360 } from '@ahla/shared-contracts';
import { Printer, ShieldCheck } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { ErrorBanner } from '../../../ui/ErrorState';
import { UserAvatar } from '../../../ui/UserAvatar';
import { useAssignDepartment } from '../useEmployees';
import { useOrganizationLookups } from '../useOrganizationLookups';

export function AddDepartmentDialog({ employeeId, onClose, onSuccess }: { employeeId: string; onClose: () => void; onSuccess: () => void }) {
  const lookups = useOrganizationLookups();
  const assignDept = useAssignDepartment();
  const [departmentId, setDepartmentId] = useState('');
  const [jobTitle, setJobTitle] = useState('');
  const [isPrimary, setIsPrimary] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const departments = useMemo(() => lookups.data?.departments ?? [], [lookups.data]);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await assignDept.mutateAsync({
        employeeId,
        departmentId,
        jobTitle: jobTitle.trim() || undefined,
        isPrimary,
        note: 'إضافة من صفحة ملف الموظف',
      });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="إضافة إدارة للموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">الإدارة</span>
          <select
            className="input w-full"
            value={departmentId}
            onChange={(e) => setDepartmentId(e.target.value)}
            required
            disabled={assignDept.isPending || lookups.isLoading}
          >
            <option value="">اختر إدارة…</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">المسمى الوظيفي في هذه الإدارة (اختياري)</span>
          <input
            className="input w-full"
            value={jobTitle}
            onChange={(e) => setJobTitle(e.target.value)}
            disabled={assignDept.isPending}
            placeholder="مثال: مسؤول مشتريات"
          />
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={isPrimary} onChange={(e) => setIsPrimary(e.target.checked)} disabled={assignDept.isPending} />
          <span>تعيين كإدارة أساسية</span>
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={assignDept.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={assignDept.isPending || !departmentId} className="btn-primary">
            {assignDept.isPending ? 'جارٍ الإضافة...' : 'إضافة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

export function PrintableIdBadgeDialog({ employee, onClose }: { employee: Employee360; onClose: () => void }) {
  const handlePrint = () => {
    window.print();
  };

  return (
    <DialogOverlay title="بطاقة الهوية الوظيفية المعتمدة" onClose={onClose} maxWidth="max-w-md">
      <div className="space-y-4">
        <p className="text-xs text-[var(--muted)]">معاينة بطاقة الهوية الرسمية للموظف. يمكنك طباعتها فورياً بحجم بطاقة العمل القياسية.</p>

        {/* The ID Card Preview */}
        <div
          id="printable-id-card"
          className="relative overflow-hidden rounded-2xl border-2 border-[var(--primary)] bg-gradient-to-br from-slate-900 via-indigo-950 to-blue-900 p-6 text-white shadow-xl"
        >
          {/* Top Header */}
          <div className="flex items-center justify-between border-b border-white/20 pb-3">
            <div className="flex items-center gap-2">
              <ShieldCheck className="size-6 text-emerald-400" />
              <div>
                <h4 className="text-xs font-black tracking-wider uppercase">جمعية أحلى شباب</h4>
                <p className="text-[10px] text-white/70">بطاقة هوية وظيفية معتمدة</p>
              </div>
            </div>
            <span className="rounded-full bg-emerald-500/20 px-2.5 py-0.5 text-[10px] font-bold text-emerald-300 border border-emerald-500/40">
              {employee.status === 'active' ? 'نشط ومفعل' : employee.status}
            </span>
          </div>

          {/* Body */}
          <div className="my-5 flex items-center gap-4">
            <UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} size="lg" />
            <div className="min-w-0 flex-1">
              <h3 className="text-base font-black text-white">{employee.fullNameAr}</h3>
              {employee.fullNameEn ? <p className="text-xs text-white/70">{employee.fullNameEn}</p> : null}
              <p className="mt-1 text-xs font-bold text-amber-300">{employee.jobTitle ?? 'موظف'}</p>
              <p className="text-[11px] text-white/60">
                {employee.departments && employee.departments.length > 0
                  ? employee.departments.map((d) => d.departmentName).join(' / ')
                  : (employee.department ?? 'الإدارة العامة')}
              </p>
            </div>
          </div>

          {/* Footer with Code & Verification (Clean - No QR Code, No Financials) */}
          <div className="flex items-center justify-between rounded-xl bg-black/30 p-3 backdrop-blur-sm border border-white/10">
            <div>
              <span className="block text-[10px] text-white/60">الرقم الوظيفي:</span>
              <span className="font-mono text-sm font-black tracking-widest text-emerald-400">{employee.employeeCode}</span>
            </div>
            <div className="text-center">
              <span className="block text-[10px] text-white/60">تاريخ التعيين:</span>
              <span className="font-mono text-xs text-white/90">{employee.hireDate ?? '—'}</span>
            </div>
            <div className="text-end">
              <span className="block text-[10px] text-white/60">الاعتماد:</span>
              <span className="text-[11px] font-bold text-emerald-300 flex items-center gap-1 justify-end">
                <ShieldCheck className="size-3.5 text-emerald-400" />
                موثق رسميًا
              </span>
            </div>
          </div>
        </div>

        {/* Dialog Actions */}
        <div className="flex justify-end gap-3 pt-2">
          <button type="button" onClick={onClose} className="btn-secondary">
            إغلاق
          </button>
          <button type="button" onClick={handlePrint} className="btn-primary">
            <Printer className="size-4" aria-hidden="true" />
            طباعة البطاقة
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}
