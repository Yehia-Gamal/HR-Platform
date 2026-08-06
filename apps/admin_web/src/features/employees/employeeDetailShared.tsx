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

// ╪º┘ä┘ç╪º╪¬┘ü ╪º┘ä┘à╪╡╪▒┘è ╪º┘ä┘à╪¡┘ä┘è: 11 ╪▒┘é┘à╪º┘ï ┘è╪¿╪»╪ú ╪¿┘Ç 01
const LOCAL_PHONE_PATTERN = /^01\d{9}$/;

/** ┘è┘ü┘ä╪¬╪▒ ╪Ñ╪»╪«╪º┘ä ╪º┘ä┘ç╪º╪¬┘ü ┘ä┘ä╪ú╪▒┘é╪º┘à ┘ê+ ┘ü┘é╪╖ ┘ê┘è┘é╪╡ ┘ä┘ä╪¡╪» ╪º┘ä╪ú┘é╪╡┘ë╪î ┘ê┘è╪▓┘è┘ä ╪╣┘ä╪º┘à╪º╪¬ bidi ╪º┘ä┘à╪«┘ü┘è╪⌐. */
export function sanitizePhoneInput(raw: string, max = 11): string {
  return raw.replace(/[^\d+]/g, '').slice(0, max);
}

/** ┘è╪╖╪¿┘è╪╣ ╪º┘ä╪▒┘é┘à ┘é╪¿┘ä ╪º┘ä╪Ñ╪▒╪│╪º┘ä: ╪º┘ä┘à╪¡┘ä┘è 01XXXXXXXXX ΓåÆ +20XXXXXXXXX. */
export function normalizePhoneForSubmit(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (LOCAL_PHONE_PATTERN.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

export const STATUS_LABELS: Record<string, string> = {
  draft: '┘à╪│┘ê╪»╪⌐',
  invited: '╪¬┘à╪¬ ╪º┘ä╪»╪╣┘ê╪⌐',
  onboarding: '┘é┘è╪» ╪º┘ä╪¬┘ç┘è╪ª╪⌐',
  active: '┘å╪┤╪╖',
  suspended: '┘à┘ê┘é┘ê┘ü',
  notice_period: '┘ü╪¬╪▒╪⌐ ╪Ñ╪«╪╖╪º╪▒',
  terminated: '┘à┘å╪¬┘ç┘è',
  archived: '┘à╪ñ╪▒╪┤┘ü',
  probation_failed: '┘ü╪┤┘ä ┘ü╪¬╪▒╪⌐ ╪º┘ä╪º╪«╪¬╪¿╪º╪▒',
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
      <p className="mt-1 font-bold">{value ?? 'ΓÇö'}</p>
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
        <option value="">ΓÇö ╪║┘è╪▒ ┘à╪¡╪»╪» ΓÇö</option>
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
// DepartmentsSection ΓÇö V17 ╪¬╪╣╪»╪» ╪º┘ä╪Ñ╪»╪º╪▒╪º╪¬
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
            ╪º┘ä╪Ñ╪»╪º╪▒╪º╪¬
          </h3>
          {canEdit ? (
            <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
              <Star className="size-4" aria-hidden="true" />
              ╪Ñ╪╢╪º┘ü╪⌐ ╪Ñ╪»╪º╪▒╪⌐
            </button>
          ) : null}
        </div>
        <p className="muted mt-3 text-sm">┘ä┘à ┘è┘Å╪│┘å┘Ä╪» ┘ä╪ú┘è ╪Ñ╪»╪º╪▒╪⌐ ╪¿╪╣╪».</p>
      </article>
    );
  }

  return (
    <article className="card p-5">
      <div className="flex items-center justify-between">
        <h3 className="font-black flex items-center gap-2">
          <Building2 className="size-5" aria-hidden="true" />
          ╪º┘ä╪Ñ╪»╪º╪▒╪º╪¬ ({departments.length})
        </h3>
        {canEdit ? (
          <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
            <Star className="size-4" aria-hidden="true" />
            ╪Ñ╪╢╪º┘ü╪⌐ ╪Ñ╪»╪º╪▒╪⌐
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
                    ╪ú╪│╪º╪│┘è╪⌐
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
                title="╪Ñ╪▓╪º┘ä╪⌐ ┘à┘å ╪º┘ä╪Ñ╪»╪º╪▒╪⌐"
                aria-label="╪Ñ╪▓╪º┘ä╪⌐ ┘à┘å ╪º┘ä╪Ñ╪»╪º╪▒╪⌐"
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
// EmployeeEditHistory ΓÇö ╪ó╪«╪▒ ╪º┘ä╪¬╪╣╪»┘è┘ä╪º╪¬ ╪º┘ä┘ç╪º┘à╪⌐ ╪╣┘ä┘ë ╪º┘ä┘à┘ä┘ü (┘à┘å ╪│╪¼┘ä ╪º┘ä╪¬╪»┘é┘è┘é)
// ---------------------------------------------------------------------------
const FIELD_LABELS: Record<string, string> = {
  fullNameAr: '╪º┘ä╪º╪│┘à ╪¿╪º┘ä╪╣╪▒╪¿┘è╪⌐',
  fullNameEn: '╪º┘ä╪º╪│┘à ╪¿╪º┘ä╪Ñ┘å╪¼┘ä┘è╪▓┘è╪⌐',
  phoneE164: '╪▒┘é┘à ╪º┘ä┘ç╪º╪¬┘ü',
  photoUrl: '╪º┘ä╪╡┘ê╪▒╪⌐ ╪º┘ä╪┤╪«╪╡┘è╪⌐',
  departmentId: '╪º┘ä╪Ñ╪»╪º╪▒╪⌐',
  teamId: '╪º┘ä┘ü╪▒┘è┘é',
  branchId: '╪º┘ä┘ü╪▒╪╣',
  workSiteId: '┘à┘ê┘é╪╣ ╪º┘ä╪╣┘à┘ä',
  jobTitleId: '╪º┘ä┘à╪│┘à┘ë ╪º┘ä┘ê╪╕┘è┘ü┘è',
  positionId: '╪º┘ä┘à┘å╪╡╪¿',
  gradeId: '╪º┘ä╪»╪▒╪¼╪⌐',
  employmentTypeId: '┘å┘ê╪╣ ╪º┘ä╪¬┘ê╪╕┘è┘ü',
  hireDate: '╪¬╪º╪▒┘è╪« ╪º┘ä╪¬╪╣┘è┘è┘å',
  contractEnd: '┘å┘ç╪º┘è╪⌐ ╪º┘ä╪╣┘é╪»',
  probationEnd: '┘å┘ç╪º┘è╪⌐ ┘ü╪¬╪▒╪⌐ ╪º┘ä╪º╪«╪¬╪¿╪º╪▒',
  status: '╪º┘ä╪¡╪º┘ä╪⌐',
};

function summarizeChangedFields(metadata: Record<string, unknown> | null): string | null {
  const after = metadata?.after;
  if (!after || typeof after !== 'object' || Array.isArray(after)) return null;
  const labels = Object.keys(after as Record<string, unknown>).map((key) => FIELD_LABELS[key] ?? key);
  if (labels.length === 0) return null;
  return labels.join('╪î ');
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
        ╪ó╪«╪▒ ╪º┘ä╪¬╪╣╪»┘è┘ä╪º╪¬ ╪╣┘ä┘ë ╪º┘ä┘à┘ä┘ü
      </h3>
      {query.isError ? (
        <div className="mt-3">
          <ErrorBanner message={safeErrorMessage(query.error)} />
        </div>
      ) : null}
      {events.length === 0 && !query.isError ? (
        <p className="muted mt-3 text-sm">┘ä╪º ╪¬┘ê╪¼╪» ╪¬╪╣╪»┘è┘ä╪º╪¬ ┘à╪│╪¼┘ä╪⌐ ╪¿╪╣╪».</p>
      ) : (
        <ol className="mt-4 space-y-3">
          {events.map((event) => {
            const fields = summarizeChangedFields(event.metadata);
            return (
              <li key={event.id} className="rounded-xl bg-[var(--surface-muted)] p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="font-bold">{event.summary ?? '╪¬╪╣╪»┘è┘ä ╪¿┘è╪º┘å╪º╪¬ ╪º┘ä┘à┘ê╪╕┘ü'}</p>
                  <time className="muted text-xs" dateTime={event.occurredAt}>
                    {dateTimeFormatter.format(new Date(event.occurredAt))}
                  </time>
                </div>
                {fields ? <p className="muted mt-1 text-xs">╪º┘ä╪¡┘é┘ê┘ä ╪º┘ä┘à╪╣╪»┘æ┘ä╪⌐: {fields}</p> : null}
                {event.description ? <p className="muted mt-1 text-xs">╪º┘ä╪│╪¿╪¿: {event.description}</p> : null}
              </li>
            );
          })}
        </ol>
      )}
    </article>
  );
}
