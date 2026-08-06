import { AlertTriangle, CalendarClock, CheckCircle2, Clock3, MapPin, RefreshCcw, UserMinus, Users } from 'lucide-react';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAttendanceDashboard } from './useAttendanceDashboard';
import type { AttendanceRosterCategory } from '@ahla/shared-contracts';

function detailsUrl(category: AttendanceRosterCategory, dateIso: string) {
  return `/hr/attendance/details?category=${category}&date=${dateIso}`;
}

export function AttendancePage() {
  const query = useAttendanceDashboard();
  const data = query.data;
  const todayIso = cairoTodayIso();
  return (
    <div className="space-y-6">
      <PageHeader
        title="الحضور والورديات"
        description="تصفح سجل اليوم، وراجع الحالات المعلقة والأحكام النهائية."
        actions={
          <button className="btn-secondary" onClick={() => void query.refetch()} disabled={query.isFetching} aria-busy={query.isFetching} aria-label="تحديث">
            <RefreshCcw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
            تحديث
          </button>
        }
      />
      <div className="card flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="flex items-center gap-2 text-sm">
          <CalendarClock className="size-5 text-brand" aria-hidden="true" />
          <strong>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date())}</strong>
        </div>
      </div>
      {query.isError ? (
        <ErrorState title="تعذر تحميل الحضور" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : !data && query.isLoading ? (
        <>
          <MetricSkeletonRow />
          <section className="grid gap-4 lg:grid-cols-2">
            <SkeletonCard className="h-44" />
            <SkeletonCard className="h-44" />
          </section>
        </>
      ) : data ? (
        <>
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard label="المجدولون اليوم" value={data.scheduled} icon={Users} hint="وفق الورديات وتقويم العمل" to={detailsUrl('scheduled', todayIso)} />
            <MetricCard
              label="حاضرون"
              value={data.present}
              icon={CheckCircle2}
              hint={`${data.scheduled ? Math.round((data.present / data.scheduled) * 100) : 0}% من المجدولين`}
              to={detailsUrl('present', todayIso)}
            />
            <MetricCard label="متأخرون" value={data.late} icon={Clock3} hint="تُحسب من سياسة الوردية" to={detailsUrl('late', todayIso)} />
            <MetricCard label="غياب" value={data.absent} icon={UserMinus} hint="بعد استبعاد الإجازات والمأموريات" to={detailsUrl('absent', todayIso)} />
          </section>
          <section className="grid gap-4 lg:grid-cols-2">
            <article className="card p-6">
              <h2 className="font-black">جودة سجلات اليوم</h2>
              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <MetricCard
                  label="بصمات غير مكتملة"
                  value={data.incomplete}
                  icon={AlertTriangle}
                  to={detailsUrl('incomplete', todayIso)}
                />
                <MetricCard
                  label="تحتاج مراجعة بشرية"
                  value={data.pendingReview}
                  icon={Users}
                  to={detailsUrl('pending_review', todayIso)}
                />
                <MetricCard
                  label="غياب بدون إذن"
                  value={data.unexcusedAbsent ?? 0}
                  icon={UserMinus}
                  hint="بعد استبعاد الإجازات المدفوعة والمأموريات"
                  to={detailsUrl('unexcused_absent', todayIso)}
                />
              </div>
            </article>
            <article className="card p-6">
              <h2 className="font-black">الموقع الجغرافي</h2>
              <div className="mt-5 grid gap-4 sm:grid-cols-2">
                <MetricCard
                  label="طلبات إرسال الموقع"
                  value={data.locationRequestsToday ?? 0}
                  icon={MapPin}
                  hint="طلبات مشاركة موقع لم يُستجب لها بعد"
                  to={detailsUrl('location_requests', todayIso)}
                />
                <MetricCard
                  label="استجابات الموقع"
                  value={data.locationRespondedToday ?? 0}
                  icon={MapPin}
                  hint="طلبات مشاركة موقع استُجيب لها"
                  to={detailsUrl('location_responded', todayIso)}
                />
              </div>
            </article>
            <article className="card p-6">
              <h2 className="font-black">قواعد التشغيل</h2>
              <ul className="mt-4 space-y-3 text-sm leading-7">
                <li className="flex gap-2">
                  <AlertTriangle className="mt-1 size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" />
                  ضعف GPS أو اختلاف الموقع ينشئ تنبيه مراجعة ولا يسجل مخالفة تلقائيًا.
                </li>
                <li className="flex gap-2">
                  <CheckCircle2 className="mt-1 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />
                  وقت الحضور المعتمد مصدره الخادم وليس ساعة الهاتف.
                </li>
                <li className="flex gap-2">
                  <Clock3 className="mt-1 size-4 shrink-0 text-brand" aria-hidden="true" />
                  آخر تحديث: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(data.lastUpdatedAt))}
                </li>
              </ul>
            </article>
          </section>
        </>
      ) : null}
    </div>
  );
}
