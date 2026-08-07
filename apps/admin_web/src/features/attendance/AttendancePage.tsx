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
  const presentPct = data && data.scheduled ? Math.round((data.present / data.scheduled) * 100) : 0;
  return (
    <div className="space-y-6">
      <PageHeader
        title="الحضور والورديات"
        description="انقر أي بطاقة لعرض قائمة الموظفين المعنيين."
        actions={
          <button className="btn-secondary" onClick={() => void query.refetch()} disabled={query.isFetching} aria-busy={query.isFetching} aria-label="تحديث">
            <RefreshCcw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
            تحديث
          </button>
        }
      />
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
          {/* ─── شريط التاريخ + نسبة الحضور ─── */}
          <div className="card flex flex-wrap items-center justify-between gap-4 p-4">
            <div className="flex items-center gap-2 text-sm">
              <CalendarClock className="size-5 text-brand" aria-hidden="true" />
              <strong>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date())}</strong>
            </div>
            {data.scheduled > 0 ? (
              <div className="flex items-center gap-3">
                <div className="h-2 w-32 overflow-hidden rounded-full bg-[var(--surface-muted)]">
                  <div
                    className="h-full rounded-full bg-[var(--success)] transition-all duration-500"
                    style={{ width: `${presentPct}%` }}
                  />
                </div>
                <span className="text-sm font-bold text-[var(--success)]">{presentPct}%</span>
              </div>
            ) : null}
          </div>

          {/* ─── المقاييس الأساسية ─── */}
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard label="المجدولون اليوم" value={data.scheduled} icon={Users} hint="وفق الورديات وتقويم العمل" to={detailsUrl('scheduled', todayIso)} />
            <MetricCard
              label="حاضرون"
              value={data.present}
              icon={CheckCircle2}
              hint={`${presentPct}% من المجدولين`}
              to={detailsUrl('present', todayIso)}
            />
            <MetricCard label="متأخرون" value={data.late} icon={Clock3} hint="حسب سياسة الوردية" to={detailsUrl('late', todayIso)} />
            <MetricCard label="غياب" value={data.absent} icon={UserMinus} hint={`بدون إذن: ${data.unexcusedAbsent ?? 0}`} to={detailsUrl('absent', todayIso)} />
          </section>

          {/* ─── حالات تحتاج اهتمام ─── */}
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="غياب بدون إذن"
              value={data.unexcusedAbsent ?? 0}
              icon={UserMinus}
              hint="بلا إجازة أو مأمورية"
              to={detailsUrl('unexcused_absent', todayIso)}
            />
            <MetricCard
              label="بصمات غير مكتملة"
              value={data.incomplete}
              icon={AlertTriangle}
              hint="سجلات جزئية أو معلقة"
              to={detailsUrl('incomplete', todayIso)}
            />
            <MetricCard
              label="تحتاج مراجعة"
              value={data.pendingReview}
              icon={Users}
              hint="تنبيهات تحتاج تدخل بشري"
              to={detailsUrl('pending_review', todayIso)}
            />
            <MetricCard
              label="طلبات الموقع"
              value={data.locationRequestsToday ?? 0}
              icon={MapPin}
              hint={`استُجيب: ${data.locationRespondedToday ?? 0}`}
              to={detailsUrl('location_requests', todayIso)}
            />
          </section>

          {/* ─── ملاحظات التشغيل ─── */}
          <div className="card flex flex-wrap items-center gap-x-6 gap-y-2 p-4 text-xs leading-6 text-[var(--text-muted)]">
            <span className="flex items-center gap-1.5">
              <AlertTriangle className="size-3.5 shrink-0 text-[var(--warning)]" aria-hidden="true" />
              ضعف GPS يُنشئ تنبيه مراجعة لا مخالفة تلقائية.
            </span>
            <span className="flex items-center gap-1.5">
              <CheckCircle2 className="size-3.5 shrink-0 text-[var(--success)]" aria-hidden="true" />
              وقت الحضور المعتمد مصدره الخادم.
            </span>
            <span className="flex items-center gap-1.5">
              <Clock3 className="size-3.5 shrink-0 text-brand" aria-hidden="true" />
              آخر تحديث: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(data.lastUpdatedAt))}
            </span>
          </div>
        </>
      ) : null}
    </div>
  );
}
