import { useReportSchedulerCatalog } from '../management/useEnterpriseOperations';
import { useEmployeeDailyReports, useEmployeePublishedDecisions } from './useEmployeeDossier';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const dateTimeFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' });

const DECISION_CATEGORY_LABELS: Record<string, string> = {
  general: 'عام',
  hr: 'موارد بشرية',
  financial: 'مالي',
  disciplinary: 'تأديبي',
  organizational: 'تنظيمي',
  policy: 'سياسة',
};

const SCOPE_LABELS: Record<string, string> = {
  self: 'الموظف',
  direct_reports: 'فريق المدير',
  department: 'الإدارة',
  branch: 'الفرع',
  organization: 'المنظمة',
  selected_users: 'مستلمون محددون',
};

const SCHEDULE_KIND_LABELS: Record<string, string> = {
  daily: 'يومي',
  weekly: 'أسبوعي',
  monthly: 'شهري',
  manual: 'يدوي',
};

const REPORT_TYPE_LABELS: Record<string, string> = {
  attendance: 'الحضور والانصراف',
  leaves: 'الإجازات',
  executive_summary: 'ملخص تنفيذي',
  daily_summary: 'ملخص يومي',
  weekly_summary: 'ملخص أسبوعي',
  performance: 'الأداء',
  operations: 'العمليات',
};

function reportTypeLabel(reportType: string): string {
  return REPORT_TYPE_LABELS[reportType] ?? reportType;
}

export function EmployeeReportsTab({ employeeId }: { employeeId: string }) {
  const daily = useEmployeeDailyReports(employeeId);
  const decisions = useEmployeePublishedDecisions(employeeId);
  const scheduler = useReportSchedulerCatalog();

  return (
    <div className="space-y-6">
      <section className="card p-5">
        <h3 className="text-lg font-black">التقارير اليومية للموظف</h3>
        <p className="muted mt-1 text-sm">التقارير التي كتبها الموظف (الإنجازات والمعوقات وخطة الغد).</p>
        <div className="mt-4">
          {daily.isError ? (
            <ErrorState title="تعذر تحميل التقارير اليومية" onRetry={() => void daily.refetch()} />
          ) : daily.isLoading ? (
            <SkeletonCard className="h-40" />
          ) : daily.data && daily.data.length > 0 ? (
            <ul className="space-y-3">
              {daily.data.map((report) => (
                <li key={report.id} className="rounded-xl border border-[var(--border-subtle)] p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-black">{dateFormatter.format(new Date(`${report.reportDate}T00:00:00`))}</span>
                    {report.reviewerName ? (
                      <StatusBadge value="reviewed" label={`راجعه ${report.reviewerName}`} />
                    ) : (
                      <StatusBadge value="pending" label="بانتظار المراجعة" />
                    )}
                  </div>
                  {report.achievements ? (
                    <p className="mt-2 text-sm">
                      <span className="font-bold">الإنجازات: </span>
                      {report.achievements}
                    </p>
                  ) : null}
                  {report.blockers ? (
                    <p className="mt-1 text-sm">
                      <span className="font-bold">المعوقات: </span>
                      {report.blockers}
                    </p>
                  ) : null}
                  {report.tomorrowPlan ? (
                    <p className="mt-1 text-sm">
                      <span className="font-bold">خطة الغد: </span>
                      {report.tomorrowPlan}
                    </p>
                  ) : null}
                  {report.managerComment ? (
                    <p className="muted mt-2 border-t border-[var(--border-subtle)] pt-2 text-sm">
                      <span className="font-bold">تعليق المدير: </span>
                      {report.managerComment}
                    </p>
                  ) : null}
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState title="لا توجد تقارير يومية" description="لم يكتب هذا الموظف تقارير يومية بعد." />
          )}
        </div>
      </section>

      <section className="card p-5">
        <h3 className="text-lg font-black">القرارات المنشورة للموظف</h3>
        <p className="muted mt-1 text-sm">القرارات الإدارية المنشورة الموجهة له أو للجميع.</p>
        <div className="mt-4">
          {decisions.isError ? (
            <ErrorState title="تعذر تحميل القرارات" onRetry={() => void decisions.refetch()} />
          ) : decisions.isLoading ? (
            <SkeletonCard className="h-40" />
          ) : decisions.data && decisions.data.length > 0 ? (
            <ul className="space-y-3">
              {decisions.data.map((decision) => (
                <li key={decision.id} className="rounded-xl border border-[var(--border-subtle)] p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-black">{decision.title}</span>
                    {decision.decisionNumber ? <span className="muted text-xs">#{decision.decisionNumber}</span> : null}
                    <StatusBadge value={decision.category} label={DECISION_CATEGORY_LABELS[decision.category] ?? decision.category} />
                    <StatusBadge value={decision.acknowledged ? 'read' : 'unread'} label={decision.acknowledged ? 'مقرّ به' : 'لم يُقرّ به'} />
                  </div>
                  <p className="muted mt-1 text-xs">
                    {decision.effectiveDate ? `ساري من ${dateFormatter.format(new Date(`${decision.effectiveDate}T00:00:00`))}` : 'بدون تاريخ سريان'}
                    {decision.publishedAt ? ` • نُشر ${dateTimeFormatter.format(new Date(decision.publishedAt))}` : ''}
                  </p>
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState title="لا توجد قرارات منشورة" description="لا توجد قرارات منشورة موجهة لهذا الموظف." />
          )}
        </div>
      </section>

      <section className="card p-5">
        <h3 className="text-lg font-black">التقارير المجدولة لفئة الموظف</h3>
        <p className="muted mt-1 text-sm">التقارير الدورية النشطة التي يشمل نطاقها فئة الموظف.</p>
        <div className="mt-4">
          {scheduler.isError ? (
            <ErrorState title="تعذر تحميل التقارير المجدولة" onRetry={() => void scheduler.refetch()} />
          ) : scheduler.isLoading ? (
            <SkeletonCard className="h-40" />
          ) : scheduler.data && scheduler.data.schedules.filter((s) => s.active && s.audienceScope !== 'self').length > 0 ? (
            <ul className="space-y-3">
              {scheduler.data.schedules
                .filter((s) => s.active && s.audienceScope !== 'self')
                .map((schedule) => (
                  <li key={schedule.id} className="rounded-xl border border-[var(--border-subtle)] p-4">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-black">{schedule.name}</span>
                      <StatusBadge value="active" label="نشط" />
                    </div>
                    <p className="muted mt-1 text-xs">
                      {reportTypeLabel(schedule.reportType)} • النطاق: {SCOPE_LABELS[schedule.audienceScope] ?? schedule.audienceScope} • الدورية:{' '}
                      {SCHEDULE_KIND_LABELS[schedule.scheduleKind] ?? schedule.scheduleKind}
                      {schedule.nextRunAt ? ` • التشغيل القادم ${dateTimeFormatter.format(new Date(schedule.nextRunAt))}` : ''}
                    </p>
                  </li>
                ))}
            </ul>
          ) : (
            <EmptyState title="لا توجد تقارير مجدولة" description="لا توجد تقارير دورية نشطة تشمل فئة هذا الموظف." />
          )}
        </div>
      </section>
    </div>
  );
}
