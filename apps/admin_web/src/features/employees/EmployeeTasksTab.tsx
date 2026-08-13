import { useEmployeeTasks } from './useEmployeeDossier';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

export function EmployeeTasksTab({ employeeId }: { employeeId: string }) {
  const query = useEmployeeTasks(employeeId);
  const rows = query.data ?? [];

  if (query.isError) {
    return (
      <ErrorState
        title="تعذر تحميل المهام"
        description="أعد المحاولة أو تواصل مع الدعم."
        onRetry={() => void query.refetch()}
      />
    );
  }
  if (query.isLoading) return <SkeletonCard className="h-56" />;
  if (rows.length === 0) {
    return <EmptyState title="لا توجد مهام" description="لا توجد مهام مسندة لهذا الموظف." />;
  }

  return (
    <div className="card overflow-hidden p-0">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border-subtle)] text-start text-xs text-[var(--text-muted)]">
              <th className="px-4 py-3 text-start font-bold">المهمة</th>
              <th className="px-4 py-3 text-start font-bold">الأولوية</th>
              <th className="px-4 py-3 text-start font-bold">الاستحقاق</th>
              <th className="px-4 py-3 text-start font-bold">الحالة</th>
              <th className="px-4 py-3 text-start font-bold">المنشئ</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id} className="border-b border-[var(--border-subtle)] last:border-0">
                <td className="px-4 py-3">
                  <p className="font-bold">{row.title}</p>
                  {row.description ? (
                    <p className="muted mt-0.5 text-xs">{row.description}</p>
                  ) : null}
                </td>
                <td className="px-4 py-3">
                  <StatusBadge value={row.priority} />
                </td>
                <td className="px-4 py-3">
                  {row.dueDate ? dateFormatter.format(new Date(`${row.dueDate}T00:00:00`)) : '—'}
                </td>
                <td className="px-4 py-3">
                  <StatusBadge value={row.status} />
                </td>
                <td className="px-4 py-3 text-[var(--text-muted)]">{row.createdByName ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
