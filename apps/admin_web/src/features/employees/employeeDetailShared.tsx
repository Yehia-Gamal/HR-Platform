import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { Building2, History, Star, X } from 'lucide-react';
import { ErrorBanner } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import {
  useEmployeeDepartments,
  useRemoveDepartment,
  useEmployeeAuditTrail,
} from './useEmployees';
import { safeErrorMessage } from '../../core/errorMapper';

const dateTimeFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' });

// Accounts that have not finished activation can still be re-invited.
export const PENDING_ACCOUNT_STATES = new Set(['invited', 'onboarding', 'pending', 'draft']);

// الهاتف المصري المحلي: 11 رقماً يبدأ بـ 01
const LOCAL_PHONE_PATTERN = /^01\d{9}$/;

/** يفلتر إدخال الهاتف للأرقام و+ فقط ويقص للحد الأقصى، ويزيل علامات bidi المخفية. */
export function sanitizePhoneInput(raw: string, max = 11): string {
  return raw.replace(/[^\d+]/g, '').slice(0, max);
}

/** يطبيع الرقم قبل الإرسال: المحلي 01XXXXXXXXX → +20XXXXXXXXX. */
export function normalizePhoneForSubmit(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (LOCAL_PHONE_PATTERN.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

export const STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  invited: 'تمت الدعوة',
  onboarding: 'قيد التهيئة',
  active: 'نشط',
  suspended: 'موقوف',
  notice_period: 'فترة إخطار',
  terminated: 'منتهي',
  archived: 'مؤرشف',
  probation_failed: 'فشل فترة الاختبار',
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

export function Info({ icon: Icon, label, dir }: { icon: LucideIcon; label: ReactNode; dir?: 'ltr' | 'rtl' }) {
  return (
    <span className="inline-flex items-center gap-2">
      <Icon className="size-4 muted" aria-hidden="true" />
      <span dir={dir}>{label}</span>
    </span>
  );
}

export function Data({ label, value }: { label: string; value: ReactNode }) {
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
              <Star className="size-4" aria-hidden="true" />
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
            <Star className="size-4" aria-hidden="true" />
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

// ---------------------------------------------------------------------------
// EmployeeEditHistory — آخر التعديلات الهامة على الملف (من سجل التدقيق)
// ---------------------------------------------------------------------------
const FIELD_LABELS: Record<string, string> = {
  fullNameAr: 'الاسم بالعربية',
  fullNameEn: 'الاسم بالإنجليزية',
  phoneE164: 'رقم الهاتف',
  photoUrl: 'الصورة الشخصية',
  departmentId: 'الإدارة',
  teamId: 'الفريق',
  branchId: 'الفرع',
  workSiteId: 'موقع العمل',
  jobTitleId: 'المسمى الوظيفي',
  positionId: 'المنصب',
  gradeId: 'الدرجة',
  employmentTypeId: 'نوع التوظيف',
  hireDate: 'تاريخ التعيين',
  contractEnd: 'نهاية العقد',
  probationEnd: 'نهاية فترة الاختبار',
  status: 'الحالة',
};

function summarizeChangedFields(metadata: Record<string, unknown> | null): string | null {
  const after = metadata?.after;
  if (!after || typeof after !== 'object' || Array.isArray(after)) return null;
  const labels = Object.keys(after as Record<string, unknown>).map((key) => FIELD_LABELS[key] ?? key);
  if (labels.length === 0) return null;
  return labels.join('، ');
}

export function EmployeeEditHistory({ employeeId }: { employeeId: string }) {
  const auth = useAuth();
  const canViewAudit = Boolean(auth.access && hasPermission(auth.access, 'audit.view'));
  const query = useEmployeeAuditTrail(canViewAudit ? employeeId : undefined);

  if (!canViewAudit) return null;
  if (query.isLoading) return <SkeletonCard className="h-32" />;
  const events = query.data ?? [];

  return (
    <article className="card p-5">
      <h3 className="font-black flex items-center gap-2">
        <History className="size-5" aria-hidden="true" />
        آخر التعديلات على الملف
      </h3>
      {query.isError ? (
        <div className="mt-3">
          <ErrorBanner message={safeErrorMessage(query.error)} />
        </div>
      ) : null}
      {events.length === 0 && !query.isError ? (
        <p className="muted mt-3 text-sm">لا توجد تعديلات مسجلة بعد.</p>
      ) : (
        <ol className="mt-4 space-y-3">
          {events.map((event) => {
            const fields = summarizeChangedFields(event.metadata);
            return (
              <li key={event.id} className="rounded-xl bg-[var(--surface-muted)] p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="font-bold">{event.summary ?? 'تعديل بيانات الموظف'}</p>
                  <time className="muted text-xs" dateTime={event.occurredAt}>
                    {dateTimeFormatter.format(new Date(event.occurredAt))}
                  </time>
                </div>
                {fields ? <p className="muted mt-1 text-xs">الحقول المعدّلة: {fields}</p> : null}
                {event.description ? <p className="muted mt-1 text-xs">السبب: {event.description}</p> : null}
              </li>
            );
          })}
        </ol>
      )}
    </article>
  );
}
