import type { LucideIcon } from 'lucide-react';
import { Building2, Plus, Star, X } from 'lucide-react';
import type { ReactNode } from 'react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { ErrorBanner } from '../../../ui/ErrorState';
import { SkeletonCard } from '../../../ui/Skeletons';
import { useEmployeeDepartments, useRemoveDepartment } from '../useEmployees';

export function Info({ icon: Icon, label, dir }: { icon: LucideIcon; label: ReactNode; dir?: 'ltr' | 'rtl' }) {
  return (
    <span className="inline-flex items-center gap-2">
      <Icon className="size-4 muted" aria-hidden="true" />
      <span dir={dir}>{label}</span>
    </span>
  );
}

export function Data({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-3">
      <p className="muted text-xs">{label}</p>
      <p className="mt-1 font-bold">{value ?? '—'}</p>
    </div>
  );
}

export function LookupSelect({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <select className="input w-full" value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled}>
        <option value="">— غير محدد —</option>
        {options.map((opt) => (
          <option key={opt.id} value={opt.id}>
            {opt.label}
          </option>
        ))}
      </select>
    </label>
  );
}

// المسمى الوظيفي: إدخال حر مع اقتراحات — يسمح بكتابة مسمى جديد غير موجود في القائمة
// (يُنشأ تلقائياً عبر update_employee_admin عند الحفظ بنوع jobTitleName).
export function JobTitleInput({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <input
        className="input w-full"
        list="edit-job-titles-list"
        aria-label={label}
        value={value}
        maxLength={160}
        placeholder="اكتب مسمى جديد أو اختر من الموجود"
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
      />
      <datalist id="edit-job-titles-list">
        {options.map((opt) => (
          <option key={opt.id} value={opt.label} />
        ))}
      </datalist>
    </label>
  );
}

// ---------------------------------------------------------------------------
// DepartmentsSection — V17 تعدد الإدارات
// ---------------------------------------------------------------------------
export function DepartmentsSection({ employeeId, canEdit, onAdd }: { employeeId: string; canEdit: boolean; onAdd: () => void }) {
  const { data: departments, isLoading } = useEmployeeDepartments(employeeId);
  const removeDept = useRemoveDepartment();

  if (isLoading) return <SkeletonCard className="h-32" />;
  if (!departments || departments.length === 0) {
    return (
      <article className="card p-5">
        <div className="flex items-center justify-between">
          <h3 className="font-black flex items-center gap-2">
            <Building2 className="size-5" aria-hidden="true" />
            الإدارات
          </h3>
          {canEdit ? (
            <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
              <Plus className="size-4" aria-hidden="true" />
              إضافة إدارة
            </button>
          ) : null}
        </div>
        <p className="muted mt-3 text-sm">لم يُسنَد لأي إدارة بعد.</p>
      </article>
    );
  }

  return (
    <article className="card p-5">
      <div className="flex items-center justify-between">
        <h3 className="font-black flex items-center gap-2">
          <Building2 className="size-5" aria-hidden="true" />
          الإدارات ({departments.length})
        </h3>
        {canEdit ? (
          <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
            <Plus className="size-4" aria-hidden="true" />
            إضافة إدارة
          </button>
        ) : null}
      </div>
      <div className="mt-4 space-y-2">
        {departments.map((dept) => (
          <div key={dept.id} className="flex items-center justify-between gap-3 rounded-xl bg-[var(--surface-muted)] p-3">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="font-bold">{dept.departmentName}</p>
                {dept.isPrimary ? (
                  <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]">
                    <Star className="size-3" aria-hidden="true" />
                    أساسية
                  </span>
                ) : null}
              </div>
              {dept.jobTitle ? <p className="muted mt-1 text-xs">{dept.jobTitle}</p> : null}
            </div>
            {canEdit ? (
              <button
                type="button"
                className="rounded-lg p-1.5 text-[var(--text-muted)] hover:bg-[var(--danger-soft)] hover:text-[var(--danger)] transition-colors"
                disabled={removeDept.isPending}
                onClick={() => removeDept.mutate({ employeeId, departmentId: dept.departmentId })}
                title="إزالة من الإدارة"
                aria-label="إزالة من الإدارة"
              >
                <X className="size-4" aria-hidden="true" />
              </button>
            ) : null}
          </div>
        ))}
      </div>
      {removeDept.isError ? <ErrorBanner message={safeErrorMessage(removeDept.error)} /> : null}
    </article>
  );
}
