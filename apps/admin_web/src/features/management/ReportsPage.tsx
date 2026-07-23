import { Clock, Download, Inbox, Target, UserCheck, Users } from 'lucide-react';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { useDashboardOverview } from './useManagementOverviews';

export function ReportsPage() {
  const q = useDashboardOverview('hr');
  const d = q.data;

  const download = () => {
    if (!d) return;
    const csv = [
      'المؤشر,القيمة',
      `إجمالي الموظفين,${d.employees}`,
      `الموظفون النشطون,${d.activeEmployees}`,
      `الطلبات المعلقة,${d.pendingRequests}`,
      `الحضور قيد المراجعة,${d.attendancePendingReview}`,
      `تقييمات KPI,${d.pendingKpi}`,
    ].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
    a.download = 'hr-summary.csv';
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return <div className="space-y-6">
    <PageHeader title="تقارير HR" description="ملخص قابل للتصدير مبني على نفس مؤشرات اللوحة ومصدر البيانات نفسه." actions={<button onClick={download} disabled={!d} className="btn-primary"><Download className="size-4" aria-hidden="true"/>تصدير CSV</button>}/>
    {q.isError ? <ErrorState title="تعذر تحميل التقارير" description={q.error instanceof Error ? q.error.message : undefined} onRetry={() => void q.refetch()} /> : q.isLoading && !d ? <MetricSkeletonRow count={5} /> : null}
    {d ? <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5"><MetricCard label="الموظفون" value={d.employees} icon={Users}/><MetricCard label="النشطون" value={d.activeEmployees} icon={UserCheck}/><MetricCard label="الطلبات" value={d.pendingRequests} icon={Inbox}/><MetricCard label="مراجعات الحضور" value={d.attendancePendingReview} icon={Clock}/><MetricCard label="KPI" value={d.pendingKpi} icon={Target}/></section> : null}
  </div>;
}
