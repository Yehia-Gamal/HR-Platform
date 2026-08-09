import { AlertTriangle, CalendarClock, CheckCircle2, Clock3, MapPin, RefreshCcw, UserMinus, Users } from 'lucide-react';
import { useState } from 'react';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAttendanceDashboard } from './useAttendanceDashboard';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import type { AttendanceRosterCategory } from '@ahla/shared-contracts';

function detailsUrl(
  category: AttendanceRosterCategory,
  dateIso: string,
  departmentId?: string | null,
  branchId?: string | null,
) {
  const params = new URLSearchParams({ category, date: dateIso });
  if (departmentId) params.set('dept', departmentId);
  if (branchId) params.set('branch', branchId);
  return `/hr/attendance/details?${params.toString()}`;
}

export function AttendancePage() {
  const [dateIso, setDateIso] = useState(cairoTodayIso());
  const [departmentId, setDepartmentId] = useState<string | null>(null);
  const [branchId, setBranchId] = useState<string | null>(null);
  const lookups = useOrganizationLookups();
  const query = useAttendanceDashboard({ dateIso, departmentId, branchId });
  const data = query.data;
  const presentPct = data && data.scheduled ? Math.round((data.present / data.scheduled) * 100) : 0;
  const hasFilters = Boolean(departmentId || branchId);
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
      {/* ─── شريط الفلاتر: التاريخ + القسم + الفرع ─── */}
      <div className="card flex flex-wrap items-end gap-4 p-4">
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--text-muted)]">
          التاريخ
          <input
            type="date"
            value={dateIso}
            onChange={(e) => setDateIso(e.target.value || cairoTodayIso())}
            className="input min-w-44"
          />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--text-muted)]">
          القسم
          <select
            className="select min-w-44"
            value={departmentId ?? ''}
            onChange={(e) => setDepartmentId(e.target.value || null)}
          >
            <option value="">كل الأقسام</option>
            {lookups.data?.departments.map((d) => (
              <option key={d.id} value={d.id}>{d.label}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--text-muted)]">
          الفرع
          <select
            className="select min-w-44"
            value={branchId ?? ''}
            onChange={(e) => setBranchId(e.target.value || null)}
          >
            <option value="">كل الفروع</option>
            {lookups.data?.branches.map((b) => (
              <option key={b.id} value={b.id}>{b.label}</option>
            ))}
          </select>
        </label>
        {hasFilters ? (
          <button
            type="button"
            className="btn-secondary"
            onClick={() => {
              setDepartmentId(null);
              setBranchId(null);
            }}
          >
            مسح الفلاتر
          </button>
        ) : null}
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
          {/* ─── شريط التاريخ + نسبة الحضور ─── */}
          <div className="card flex flex-wrap items-center justify-between gap-4 p-4">
            <div className="flex items-center gap-2 text-sm">
              <CalendarClock className="size-5 text-brand" aria-hidden="true" />
              <strong>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`))}</strong>
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
            <MetricCard label="المجدولون اليوم" value={data.scheduled} icon={Users} hint="وفق الورديات وتقويم العمل" to={detailsUrl('scheduled', dateIso, departmentId, branchId)} />
            <MetricCard
              label="حاضرون"
              value={data.present}
              icon={CheckCircle2}
              hint={`${presentPct}% من المجدولين`}
              to={detailsUrl('present', dateIso, departmentId, branchId)}
            />
            <MetricCard label="متأخرون" value={data.late} icon={Clock3} hint="حسب سياسة الوردية" to={detailsUrl('late', dateIso, departmentId, branchId)} />
            <MetricCard label="غياب" value={data.absent} icon={UserMinus} hint={`بدون إذن: ${data.unexcusedAbsent ?? 0}`} to={detailsUrl('absent', dateIso, departmentId, branchId)} />
          </section>

          {/* ─── حالات تحتاج اهتمام ─── */}
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="غياب بدون إذن"
              value={data.unexcusedAbsent ?? 0}
              icon={UserMinus}
              hint="بلا إجازة أو مأمورية"
              to={detailsUrl('unexcused_absent', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="بصمات غير مكتملة"
              value={data.incomplete}
              icon={AlertTriangle}
              hint="سجلات جزئية أو معلقة"
              to={detailsUrl('incomplete', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="تحتاج مراجعة"
              value={data.pendingReview}
              icon={Users}
              hint="تنبيهات تحتاج تدخل بشري"
              to={detailsUrl('pending_review', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="طلبات الموقع"
              value={data.locationRequestsToday ?? 0}
              icon={MapPin}
              hint={`استُجيب: ${data.locationRespondedToday ?? 0}`}
              to={detailsUrl('location_requests', dateIso, departmentId, branchId)}
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
