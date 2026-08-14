import { useEmployeeLocationRequests } from './useEmployeeDossier';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' });

const PURPOSE_LABELS: Record<string, string> = {
  verification: 'تحقق',
  attendance: 'حضور',
  safety: 'سلامة',
  field_visit: 'زيارة ميدانية',
  other: 'أخرى',
};

export function EmployeeLocationTab({ employeeId }: { employeeId: string }) {
  const query = useEmployeeLocationRequests(employeeId);
  const rows = query.data ?? [];

  if (query.isError) {
    return <ErrorState title="تعذر تحميل طلبات المواقع" description="أعد المحاولة أو تواصل مع الدعم." onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) return <SkeletonCard className="h-56" />;
  if (rows.length === 0) {
    return <EmptyState title="لا توجد طلبات مواقع" description="لا توجد طلبات تتبع موقع مسجلة لهذا الموظف." />;
  }

  return (
    <div className="card overflow-hidden p-0">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border-subtle)] text-start text-xs text-[var(--text-muted)]">
              <th className="px-4 py-3 text-start font-bold">الغرض</th>
              <th className="px-4 py-3 text-start font-bold">تاريخ الطلب</th>
              <th className="px-4 py-3 text-start font-bold">الحالة</th>
              <th className="px-4 py-3 text-start font-bold">المدة</th>
              <th className="px-4 py-3 text-start font-bold">السبب</th>
              <th className="px-4 py-3 text-start font-bold">بطلب من</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id} className="border-b border-[var(--border-subtle)] last:border-0">
                <td className="px-4 py-3 font-bold">{PURPOSE_LABELS[row.purpose] ?? row.purpose}</td>
                <td className="px-4 py-3">{dateFormatter.format(new Date(row.requestedAt))}</td>
                <td className="px-4 py-3">
                  <StatusBadge value={row.status} />
                </td>
                <td className="px-4 py-3">{row.durationMinutes ? `${row.durationMinutes} دقيقة` : '—'}</td>
                <td className="px-4 py-3 text-[var(--text-muted)]">{row.reason ?? '—'}</td>
                <td className="px-4 py-3 text-[var(--text-muted)]">{row.requestedByName ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
