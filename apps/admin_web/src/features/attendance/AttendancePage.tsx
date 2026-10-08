import {
  AlertTriangle,
  ArrowUpRight,
  CalendarClock,
  CalendarDays,
  CheckCircle2,
  Clock3,
  Coins,
  FileSpreadsheet,
  MapPin,
  Plane,
  RefreshCcw,
  Sparkles,
  TrendingUp,
  UserMinus,
  Users,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAttendanceDashboard } from './useAttendanceDashboard';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import type { AttendanceRosterCategory } from '@ahla/shared-contracts';
import { AppPieChart, ChartCard } from '../../ui/charts';

function getBasePath() {
  if (typeof window !== 'undefined' && window.location.pathname.startsWith('/admin')) {
    return '/admin/hr';
  }
  return '/hr';
}

function detailsUrl(category: AttendanceRosterCategory, dateIso: string, departmentId?: string | null, branchId?: string | null) {
  const params = new URLSearchParams({ category, date: dateIso });
  if (departmentId) params.set('dept', departmentId);
  if (branchId) params.set('branch', branchId);
  return `${getBasePath()}/attendance/details?${params.toString()}`;
}

export function AttendancePage() {
  const [dateIso, setDateIso] = useState(cairoTodayIso());
  const [departmentId, setDepartmentId] = useState<string | null>(null);
  const [branchId, setBranchId] = useState<string | null>(null);
  const lookups = useOrganizationLookups();
  const query = useAttendanceDashboard({ dateIso, departmentId, branchId });
  const data = query.data;
  // المقام: المطلوب حضورهم فعلاً لا كل المجدولين — من في إجازة أو مأمورية لا يُخفض النسبة
  const expected = data ? (data.expected ?? data.scheduled) : 0;
  const pctOfExpected = (n: number) => (expected > 0 ? Math.min(100, Math.round((n / expected) * 100)) : 0);
  const presentPct = data ? pctOfExpected(data.present) : 0;
  const hasFilters = Boolean(departmentId || branchId);
  const onTimeCount = data ? Math.max(0, data.present - data.late) : 0;
  const onTimeRate = pctOfExpected(onTimeCount);
  const respondedGps = data?.locationRequestsResponded ?? data?.locationRespondedToday ?? 0;
  const totalGps = data?.locationRequestsToday ?? 0;
  const gpsRate = totalGps > 0 ? Math.round((respondedGps / totalGps) * 100) : 100;
  const criticalCount = data ? (data.unexcusedAbsent ?? 0) + (data.missingCheckout ?? 0) + (data.pendingReview ?? 0) : 0;

  const pieData = useMemo(() => {
    if (!data) return [];
    const items = [
      { name: 'حضور منتظم', value: Math.max(0, data.present - data.late), color: 'var(--success, #10b981)' },
      { name: 'متأخرون', value: data.late, color: 'var(--warning, #f59e0b)' },
      { name: 'غياب بدون إذن', value: data.unexcusedAbsent ?? 0, color: 'var(--danger, #ef4444)' },
      { name: 'في إجازة / مأمورية', value: (data.onLeave ?? 0) + (data.onMission ?? 0), color: '#3b82f6' },
      { name: 'بصمة غير مكتملة', value: (data.incomplete ?? 0) + (data.missingCheckout ?? 0), color: '#8b5cf6' },
    ];
    return items.filter((i) => i.value > 0);
  }, [data]);

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
          <input type="date" value={dateIso} onChange={(e) => setDateIso(e.target.value || cairoTodayIso())} className="input min-w-44" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--text-muted)]">
          القسم
          <select className="select min-w-44" value={departmentId ?? ''} onChange={(e) => setDepartmentId(e.target.value || null)}>
            <option value="">كل الأقسام</option>
            {lookups.data?.departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--text-muted)]">
          الفرع
          <select className="select min-w-44" value={branchId ?? ''} onChange={(e) => setBranchId(e.target.value || null)}>
            <option value="">كل الفروع</option>
            {lookups.data?.branches.map((b) => (
              <option key={b.id} value={b.id}>
                {b.label}
              </option>
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
              <strong>{new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`))}</strong>
            </div>
            {expected > 0 ? (
              <div className="flex items-center gap-3">
                <div className="h-2 w-32 overflow-hidden rounded-full bg-[var(--surface-muted)]">
                  <div className="h-full rounded-full bg-[var(--success)] transition-all duration-500" style={{ width: `${presentPct}%` }} />
                </div>
                <span className="text-sm font-bold text-[var(--success)]">{presentPct}%</span>
              </div>
            ) : null}
          </div>

          {/* ─── بوابات تنفيذية سريعة ─── */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Link
              to={`${getBasePath()}/attendance?tab=executive&date=${dateIso}`}
              className="card p-3 flex items-center justify-between gap-2 hover:border-[var(--brand-primary)] hover:shadow-xs transition-all group"
            >
              <div className="flex items-center gap-2.5 min-w-0">
                <span className="size-8 rounded-lg bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] flex items-center justify-center shrink-0">
                  <Sparkles className="size-4" aria-hidden="true" />
                </span>
                <div className="min-w-0">
                  <div className="text-xs font-black truncate group-hover:text-[var(--brand-primary)]">التقرير التنفيذي</div>
                  <div className="text-[10px] text-[var(--text-muted)] truncate">ملخص يومي شامل</div>
                </div>
              </div>
              <ArrowUpRight
                className="size-3.5 text-[var(--text-muted)] group-hover:text-[var(--brand-primary)] shrink-0 rtl:rotate-[-90deg]"
                aria-hidden="true"
              />
            </Link>

            <Link
              to={`${getBasePath()}/attendance?tab=report`}
              className="card p-3 flex items-center justify-between gap-2 hover:border-[var(--brand-primary)] hover:shadow-xs transition-all group"
            >
              <div className="flex items-center gap-2.5 min-w-0">
                <span className="size-8 rounded-lg bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 flex items-center justify-center shrink-0">
                  <FileSpreadsheet className="size-4" aria-hidden="true" />
                </span>
                <div className="min-w-0">
                  <div className="text-xs font-black truncate group-hover:text-[var(--brand-primary)]">الكشف الشهري</div>
                  <div className="text-[10px] text-[var(--text-muted)] truncate">تقفيل واعتماد الحضور</div>
                </div>
              </div>
              <ArrowUpRight
                className="size-3.5 text-[var(--text-muted)] group-hover:text-[var(--brand-primary)] shrink-0 rtl:rotate-[-90deg]"
                aria-hidden="true"
              />
            </Link>

            <Link
              to="/admin/finance?tab=instant-penalties"
              className="card p-3 flex items-center justify-between gap-2 hover:border-[var(--brand-primary)] hover:shadow-xs transition-all group"
            >
              <div className="flex items-center gap-2.5 min-w-0">
                <span className="size-8 rounded-lg bg-amber-500/10 text-amber-600 dark:text-amber-400 flex items-center justify-center shrink-0">
                  <Coins className="size-4" aria-hidden="true" />
                </span>
                <div className="min-w-0">
                  <div className="text-xs font-black truncate group-hover:text-[var(--brand-primary)]">غرامات الحضور</div>
                  <div className="text-[10px] text-[var(--text-muted)] truncate">صندوق الزمالة الفوري</div>
                </div>
              </div>
              <ArrowUpRight
                className="size-3.5 text-[var(--text-muted)] group-hover:text-[var(--brand-primary)] shrink-0 rtl:rotate-[-90deg]"
                aria-hidden="true"
              />
            </Link>

            <Link
              to="/admin/live-location"
              className="card p-3 flex items-center justify-between gap-2 hover:border-[var(--brand-primary)] hover:shadow-xs transition-all group"
            >
              <div className="flex items-center gap-2.5 min-w-0">
                <span className="size-8 rounded-lg bg-sky-500/10 text-sky-600 dark:text-sky-400 flex items-center justify-center shrink-0">
                  <MapPin className="size-4" aria-hidden="true" />
                </span>
                <div className="min-w-0">
                  <div className="text-xs font-black truncate group-hover:text-[var(--brand-primary)]">التتبع اللحظي</div>
                  <div className="text-[10px] text-[var(--text-muted)] truncate">تحقق الموقع والـ GPS</div>
                </div>
              </div>
              <ArrowUpRight
                className="size-3.5 text-[var(--text-muted)] group-hover:text-[var(--brand-primary)] shrink-0 rtl:rotate-[-90deg]"
                aria-hidden="true"
              />
            </Link>
          </div>

          {/* ─── المقاييس الأساسية ─── */}
          <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="المجدولون اليوم"
              value={data.scheduled}
              icon={Users}
              hint="وفق الورديات وتقويم العمل"
              compact={true}
              to={detailsUrl('scheduled', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="حاضرون"
              value={data.present}
              icon={CheckCircle2}
              hint={expected > 0 ? `${presentPct}% من ${expected} مطلوب حضورهم` : 'لا دوام مطلوب اليوم'}
              compact={true}
              to={detailsUrl('present', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="متأخرون"
              value={data.late}
              icon={Clock3}
              hint="حسب سياسة الوردية"
              compact={true}
              to={detailsUrl('late', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="غياب"
              value={data.absent}
              icon={UserMinus}
              hint={`بدون إذن: ${data.unexcusedAbsent ?? 0}`}
              compact={true}
              to={detailsUrl('absent', dateIso, departmentId, branchId)}
            />
          </section>

          {/* ─── حالات تحتاج اهتمام ─── */}
          <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="غياب بدون إذن"
              value={data.unexcusedAbsent ?? 0}
              icon={UserMinus}
              hint="بلا إجازة أو مأمورية"
              compact={true}
              to={detailsUrl('unexcused_absent', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="بصمات غير مكتملة"
              value={data.incomplete ?? 0}
              icon={AlertTriangle}
              hint="سجلات جزئية أو معلقة"
              compact={true}
              to={detailsUrl('incomplete', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="تحتاج مراجعة"
              value={data.pendingReview ?? 0}
              icon={Users}
              hint="تنبيهات تحتاج تدخل بشري"
              compact={true}
              to={detailsUrl('pending_review', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="طلبات الموقع"
              value={data.locationRequestsToday ?? 0}
              icon={MapPin}
              hint={`استُجيب: ${data.locationRequestsResponded ?? data.locationRespondedToday ?? 0}`}
              compact={true}
              to={detailsUrl('location_requests', dateIso, departmentId, branchId)}
            />
          </section>

          {/* ─── الاستثناءات: إجازات ومأموريات وبصمات ناقصة ─── */}
          <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="في إجازة"
              value={data.onLeave ?? 0}
              icon={CalendarDays}
              hint="طلبات إجازة معتمدة تغطي اليوم"
              compact={true}
              to={detailsUrl('on_leave', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="في مأمورية"
              value={data.onMission ?? 0}
              icon={Plane}
              hint="تكليفات نشطة بلا سجل حضور"
              compact={true}
              to={detailsUrl('on_mission', dateIso, departmentId, branchId)}
            />
            <MetricCard
              label="بصمة دخول بلا انصراف"
              value={data.missingCheckout ?? 0}
              icon={Clock3}
              hint="بصمة واحدة — تحتاج إكمال"
              compact={true}
              to={detailsUrl('missing_checkout', dateIso, departmentId, branchId)}
            />
          </section>

          {/* ─── التحليل البصري ونبض الانضباط التشغيلي ─── */}
          <section className="grid gap-4 lg:grid-cols-2">
            <ChartCard title="توزيع قوى العمل اليوم" subtitle="نظرة بصرية شاملة على توزيع الحالات والانضباط الميداني" empty={pieData.length === 0} height={260}>
              <AppPieChart data={pieData} donut height={240} />
            </ChartCard>

            <div className="card p-5 flex flex-col justify-between space-y-4">
              <div>
                <div className="flex items-center justify-between pb-3 border-b border-[var(--border)]">
                  <div className="flex items-center gap-2">
                    <span className="size-7 rounded-lg bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] flex items-center justify-center">
                      <TrendingUp className="size-4" aria-hidden="true" />
                    </span>
                    <h3 className="text-sm font-black">نبض الانضباط والجاهزية التشغيلية</h3>
                  </div>
                  <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-[var(--surface-muted)] text-[var(--text-muted)]">مؤشرات لحظية</span>
                </div>

                <div className="grid gap-3.5 sm:grid-cols-3 mt-4">
                  <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-3 space-y-1">
                    <span className="text-[11px] font-bold text-[var(--text-muted)] block">نسبة الحضور بالموعد</span>
                    <div className="text-xl font-black text-[var(--success)]">{onTimeRate}%</div>
                    <p className="text-[10px] text-[var(--text-muted)] leading-tight">{onTimeCount} موظف بدون أي تأخير</p>
                  </div>

                  <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-3 space-y-1">
                    <span className="text-[11px] font-bold text-[var(--text-muted)] block">استجابة الـ GPS</span>
                    <div className="text-xl font-black text-sky-600 dark:text-sky-400">{gpsRate}%</div>
                    <p className="text-[10px] text-[var(--text-muted)] leading-tight">
                      {respondedGps} من {totalGps} طلب موقع
                    </p>
                  </div>

                  <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-3 space-y-1">
                    <span className="text-[11px] font-bold text-[var(--text-muted)] block">حالات تحتاج تدخلاً</span>
                    <div className={`text-xl font-black ${criticalCount > 0 ? 'text-[var(--danger)]' : 'text-[var(--success)]'}`}>{criticalCount}</div>
                    <p className="text-[10px] text-[var(--text-muted)] leading-tight">غياب أو بصمات معلقة أو مراجعات</p>
                  </div>
                </div>
              </div>

              <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-3 text-xs flex items-center justify-between gap-3">
                <span className="text-[var(--text-muted)]">هل تحتاج إلى تفريغ مفصل لبيانات اليوم أو إرسال تقرير موجز للإدارة؟</span>
                <Link to={`${getBasePath()}/attendance?tab=executive&date=${dateIso}`} className="btn-primary !text-xs !py-1 !px-2.5 font-bold shrink-0">
                  فتح التقرير التنفيذي
                </Link>
              </div>
            </div>
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
              آخر تحديث:{' '}
              {new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(data.lastUpdatedAt ?? Date.now()))}
            </span>
          </div>
        </>
      ) : null}
    </div>
  );
}
