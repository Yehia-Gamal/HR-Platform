import { useEmployeeKpiEvaluations } from './useEmployeeDossier';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

const STAGE_LABELS: Record<string, string> = {
  self: 'تقييم ذاتي',
  manager: 'عند المدير',
  manager_review: 'مراجعة المدير',
  manager_final: 'الاعتماد النهائي للمدير',
  hr: 'عند الموارد البشرية',
  secretary: 'عند السكرتير',
  executive: 'مراجعة تنفيذية',
  parallel_review: 'مراجعة موازية',
  finalized: 'مكتمل',
  closed: 'مغلق',
  archived: 'مؤرشف',
};

export function EmployeeKpiTab({ employeeId }: { employeeId: string }) {
  const query = useEmployeeKpiEvaluations(employeeId);
  const rows = query.data ?? [];

  if (query.isError) {
    return <ErrorState title="تعذر تحميل تقييمات الأداء" description="أعد المحاولة أو تواصل مع الدعم." onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) return <SkeletonCard className="h-56" />;
  if (rows.length === 0) {
    return <EmptyState title="لا توجد تقييمات" description="لا توجد دورات تقييم أداء مسجلة لهذا الموظف." />;
  }

  return (
    <div className="card overflow-hidden p-0">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border-subtle)] text-start text-xs text-[var(--text-muted)]">
              <th className="px-4 py-3 text-start font-bold">الدورة</th>
              <th className="px-4 py-3 text-start font-bold">المرحلة</th>
              <th className="px-4 py-3 text-start font-bold">حالة الدورة</th>
              <th className="px-4 py-3 text-start font-bold">الدرجة</th>
              <th className="px-4 py-3 text-start font-bold">التقدير</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id} className="border-b border-[var(--border-subtle)] last:border-0">
                <td className="px-4 py-3 font-bold">{row.periodMonth ? dateFormatter.format(new Date(`${row.periodMonth}T00:00:00`)) : '—'}</td>
                <td className="px-4 py-3">
                  {row.currentStage ? <StatusBadge value={row.currentStage} label={STAGE_LABELS[row.currentStage] ?? row.currentStage} /> : '—'}
                </td>
                <td className="px-4 py-3">{row.cycleStatus ? <StatusBadge value={row.cycleStatus} /> : '—'}</td>
                <td className="px-4 py-3 font-black">{row.finalScore != null ? row.finalScore.toFixed(2) : '—'}</td>
                <td className="px-4 py-3">{row.finalRating ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
