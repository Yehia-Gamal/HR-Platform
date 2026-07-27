import {
  Activity,
  Briefcase,
  CalendarDays,
  Clock,
  Download,
  FileWarning,
  Inbox,
  MapPin,
  Scale,
  Target,
  UserCheck,
  UserMinus,
  Users,
} from 'lucide-react';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { useHrReportsSummary } from './useHrReportsSummary';

/** مساعد لتحويل قسم تقرير إلى صفوف CSV */
function sectionToCsv(title: string, data: Record<string, number | string | undefined>): string[] {
  const rows: string[] = [`\n${title}`];
  for (const [key, val] of Object.entries(data)) {
    if (val !== undefined) rows.push(`${key},${val}`);
  }
  return rows;
}

export function ReportsPage() {
  const q = useHrReportsSummary();
  const d = q.data;

  const download = () => {
    if (!d) return;
    const lines = [
      'المؤشر,القيمة',
      ...sectionToCsv('الحضور', d.attendance),
      ...sectionToCsv('الإجازات', d.leaves),
      ...sectionToCsv('التكليفات', d.assignments),
      ...sectionToCsv('الأداء (KPI)', d.kpi),
      ...sectionToCsv('النزاعات', d.disputes),
      ...sectionToCsv('الموقع', d.location),
      `\nتاريخ التوليد,${d.generatedAt}`,
    ];
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + lines.join('\n')], { type: 'text/csv;charset=utf-8' }));
    a.download = `hr-report-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return <div className="space-y-6">
    <PageHeader
      title="التقارير التشغيلية"
      description="ملخص شامل للحضور والإجازات والتكليفات والأداء والنزاعات والموقع — قابل للتصدير."
      actions={<button onClick={download} disabled={!d} className="btn-primary"><Download className="size-4" aria-hidden="true" />تصدير CSV</button>}
    />

    {q.isError ? (
      <ErrorState title="تعذر تحميل التقارير" description={q.error instanceof Error ? q.error.message : undefined} onRetry={() => void q.refetch()} />
    ) : q.isLoading && !d ? (
      <MetricSkeletonRow count={5} />
    ) : d ? (
      <>
        {/* الحضور */}
        <ReportSection title="الحضور" description="إحصائيات أحداث الحضور والانصراف">
          <MetricCard label="إجمالي الأحداث" value={num(d.attendance.totalEvents)} icon={Clock} />
          <MetricCard label="تسجيل دخول اليوم" value={num(d.attendance.checkIns)} icon={UserCheck} />
          <MetricCard label="تسجيل خروج اليوم" value={num(d.attendance.checkOuts)} icon={UserMinus} />
          <MetricCard label="بانتظار المراجعة" value={num(d.attendance.pendingReview)} icon={Inbox} hint="تصحيحات واستثناءات" />
          <MetricCard label="هذا الشهر" value={num(d.attendance.thisMonth)} icon={CalendarDays} />
        </ReportSection>

        {/* الإجازات */}
        <ReportSection title="الإجازات" description="طلبات الإجازة وحالتها">
          <MetricCard label="إجمالي الطلبات" value={num(d.leaves.totalRequests)} icon={Inbox} />
          <MetricCard label="معتمدة" value={num(d.leaves.approved)} icon={UserCheck} />
          <MetricCard label="معلقة" value={num(d.leaves.pending)} icon={Clock} />
          <MetricCard label="مرفوضة" value={num(d.leaves.rejected)} icon={FileWarning} />
          <MetricCard label="إجازات حالية" value={num(d.leaves.activeNow)} icon={CalendarDays} hint="موظفون في إجازة الآن" />
        </ReportSection>

        {/* التكليفات */}
        <ReportSection title="التكليفات" description="المهام والتكليفات الخارجية">
          <MetricCard label="الإجمالي" value={num(d.assignments.total)} icon={Briefcase} />
          <MetricCard label="نشطة" value={num(d.assignments.active)} icon={Activity} />
          <MetricCard label="مكتملة" value={num(d.assignments.completed)} icon={UserCheck} />
          <MetricCard label="معلقة" value={num(d.assignments.pending)} icon={Clock} />
        </ReportSection>

        {/* الأداء */}
        <ReportSection title="الأداء (KPI)" description="دورات التقييم والمؤشرات">
          <MetricCard label="دورات نشطة" value={num(d.kpi.activeCycles)} icon={Target} />
          <MetricCard label="إجمالي التقييمات" value={num(d.kpi.totalEvaluations)} icon={Users} />
          <MetricCard label="بانتظار التقييم" value={num(d.kpi.pendingEvaluations)} icon={Clock} hint="لم تُعتمد بعد" />
          <MetricCard label="مكتملة" value={num(d.kpi.completedEvaluations)} icon={UserCheck} />
        </ReportSection>

        {/* النزاعات */}
        <ReportSection title="النزاعات" description="حالة التظلمات والشكاوى">
          <MetricCard label="الإجمالي" value={num(d.disputes.total)} icon={Scale} />
          <MetricCard label="مفتوحة" value={num(d.disputes.open)} icon={FileWarning} />
          <MetricCard label="محلولة" value={num(d.disputes.resolved)} icon={UserCheck} />
          <MetricCard label="مصعّدة" value={num(d.disputes.escalated)} icon={Activity} />
        </ReportSection>

        {/* الموقع */}
        <ReportSection title="طلبات الموقع" description="طلبات تحديد الموقع الجغرافي">
          <MetricCard label="إجمالي الطلبات" value={num(d.location.totalRequests)} icon={MapPin} />
          <MetricCard label="معلقة" value={num(d.location.pending)} icon={Clock} />
          <MetricCard label="تمت الاستجابة" value={num(d.location.responded)} icon={UserCheck} />
        </ReportSection>

        {/* بيانات التوليد */}
        <section className="card flex items-center justify-between p-4">
          <p className="text-xs text-[var(--text-muted)]">آخر توليد: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(d.generatedAt))}</p>
        </section>
      </>
    ) : null}
  </div>;
}

/** مساعد لتحويل قيمة التقرير إلى رقم */
function num(v: number | string | undefined): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return Number(v) || 0;
  return 0;
}

/** قسم تقرير مع عنوان وبطاقات */
function ReportSection({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return (
    <section>
      <div className="mb-3">
        <h2 className="text-base font-black">{title}</h2>
        <p className="mt-1 text-xs text-[var(--text-muted)]">{description}</p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5">
        {children}
      </div>
    </section>
  );
}
