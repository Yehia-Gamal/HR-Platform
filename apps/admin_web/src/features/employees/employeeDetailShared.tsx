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

// الهاتف المصري المحلي: 11 رقماً يبدأ بـ 01
const LOCAL_PHONE_PATTERN = /^01\d{9}$/;

/**
 * يطبع الرقم قبل الإرسال: المحلي 01XXXXXXXXX → ‎+20XXXXXXXXX.
 * يُرجِع null للقيمة الفارغة. القيم الأخرى تُرجَع كما هي ليرفضها الخادم.
 */
export function normalizePhoneForSubmit(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (LOCAL_PHONE_PATTERN.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

// تسمية الحقول داخل سجل التدقيق لعرض ملخص مفهوم للتعديلات.
const FIELD_LABELS: Record<string, string> = {
  fullNameAr: 'الاسم بالعربية',
  fullNameEn: 'الاسم بالإنجليزية',
  phoneE164: 'رقم الهاتف',
  photoUrl: 'الصورة الشخصية',
  email: 'البريد الإلكتروني',
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
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return null;
  const after = (metadata as Record<string, unknown>).after;
  if (!after || typeof after !== 'object' || Array.isArray(after)) return null;
  const labels = Object.keys(after as Record<string, unknown>).map((key) => FIELD_LABELS[key] ?? key);
  return labels.length ? labels.join('، ') : null;
}

// ---------------------------------------------------------------------------
// EmployeeEditHistory — آخر التعديلات الهامة على الملف (من سجل التدقيق)
// ---------------------------------------------------------------------------
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
