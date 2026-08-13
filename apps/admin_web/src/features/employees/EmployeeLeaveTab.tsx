import { LEAVE_TYPE_LABELS } from '@ahla/shared-contracts';
import { useAdminLeaves } from '../leaves/useLeaves';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

export function EmployeeLeaveTab({ employeeId }: { employeeId: string }) {
  const query = useAdminLeaves({ employeeId, limit: 100 });
  const rows = query.data?.rows ?? [];

  if (query.isError) {
    return (
      <ErrorState
        title="تعذر تحميل الإجازات"
        description="أعد المحاولة أو تواصل مع الدعم."
        onRetry={() => void query.refetch()}
      />
    );
  }
  if (query.isLoading) return <SkeletonCard className="h-56" />;
  if (rows.length === 0) {
    return <EmptyState title="لا توجد إجازات" description="لا توجد طلبات إجازة مسجلة لهذا الموظف." />;
  }

  return (
    <div className="card overflow-hidden p-0">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border-subtle)] text-start text-xs text-[var(--text-muted)]">
              <th className="px-4 py-3 text-start font-bold">نوع الإجازة</th>
              <th className="px-4 py-3 text-start font-bold">من</th>
              <th className="px-4 py-3 text-start font-bold">إلى</th>
              <th className="px-4 py-3 text-start font-bold">المدة</th>
              <th className="px-4 py-3 text-start font-bold">الحالة</th>
              <th className="px-4 py-3 text-start font-bold">السبب</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.requestId} className="border-b border-[var(--border-subtle)] last:border-0">
                <td className="px-4 py-3 font-bold">
                  {LEAVE_TYPE_LABELS[row.leaveTypeCode] ?? row.leaveTypeName}
                </td>
                <td className="px-4 py-3">{dateFormatter.format(new Date(`${row.startDate}T00:00:00`))}</td>
                <td className="px-4 py-3">{dateFormatter.format(new Date(`${row.endDate}T00:00:00`))}</td>
                <td className="px-4 py-3">
                  {row.durationUnit === 'hour'
                    ? `${row.hoursCount ?? 0} ساعة`
                    : `${row.daysCount} ${row.daysCount === 1 ? 'يوم' : 'أيام'}${row.isHalfDay ? ' (نصف يوم)' : ''}`}
                </td>
                <td className="px-4 py-3">
                  <StatusBadge value={row.status} />
                </td>
                <td className="px-4 py-3 text-[var(--text-muted)]">{row.reason ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
