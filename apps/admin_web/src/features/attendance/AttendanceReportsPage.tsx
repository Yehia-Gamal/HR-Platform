import { ArrowLeft, CalendarDays, CalendarRange, Clock3, Download, FileText, Plane, Printer, Users, BadgeCheck } from 'lucide-react';
import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { cairoTodayIso, startOfWeek, endOfWeek, startOfMonth, endOfMonth } from '../../core/cairoTime';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { Tabs } from '../../ui/Tabs';
import { useToast } from '../../ui/Toast';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { exportAttendancePDF } from './exportAttendancePDF';
import { exportAttendancePdf, exportExecutiveDailyReportPdf } from './useAttendanceDashboard';
import { exportWeeklyAttendancePdf, exportMonthlyAttendancePdf } from './exportRangeReports';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

export type ReportPeriod = 'day' | 'week' | 'month';
export type ReportScope = 'individual' | 'team' | 'all';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

function fmtTime12(iso: string | null | undefined): string {
  if (!iso) return '—';
  const m = /^(\d{1,2}):(\d{2})/.exec(iso);
  if (!m) return iso;
  let h = parseInt(m[1], 10);
  const min = m[2];
  if (Number.isNaN(h)) return iso;
  const period = h < 12 ? 'ص' : 'م';
  h = h % 12 === 0 ? 12 : h % 12;
  return `${String(h).padStart(2, '0')}:${min} ${period}`;
}

export function AttendanceReportsPage() {
  const { employeeId } = useParams<{ employeeId: string }>();
  const isIndividual = Boolean(employeeId);
  const auth = useAuth();
  const { toast } = useToast();

  const [period, setPeriod] = useState<ReportPeriod>('month');
  const [scope, setScope] = useState<ReportScope>(isIndividual ? 'individual' : 'all');
  const [dateIso, setDateIso] = useState(cairoTodayIso());
  const [deptFilter, setDeptFilter] = useState('');
  const [branchFilter, setBranchFilter] = useState('');
  const [isExporting, setIsExporting] = useState(false);

  const getDateRange = (baseDate: string, period: ReportPeriod): { start: string; end: string } => {
    const d = new Date(baseDate);
    if (period === 'day') return { start: baseDate, end: baseDate };
    if (period === 'week') return { start: startOfWeek(d), end: endOfWeek(d) };
    return { start: startOfMonth(d), end: endOfMonth(d) };
  };

  const { start, end } = getDateRange(dateIso, period);
  const year = new Date(dateIso).getFullYear();
  const month = new Date(dateIso).getMonth() + 1;

  const canViewAll = Boolean(auth.access && hasPermission(auth.access, 'reports.attendance.read'));
  const canViewIndividual = isIndividual || canViewAll;

  const statement = useEmployeeMonthlyStatement(employeeId ?? null, year, month);

  if (!canViewIndividual) {
    return <ErrorState title="غير مصرح" description="لا يمكنك عرض تقارير الحضور." />;
  }

  const handleExport = async () => {
    setIsExporting(true);
    try {
      if (isIndividual && employeeId) {
        if (period === 'month') {
          if (!statement.data) throw new Error('لا توجد بيانات للكشف الشهري');
          exportAttendancePDF(statement.data);
        } else if (period === 'week') {
          await exportWeeklyAttendancePdf(employeeId, start, end);
        } else {
          await exportAttendancePdf({ category: 'scheduled', dateIso: start });
        }
      } else {
        if (period === 'day') {
          await exportExecutiveDailyReportPdf(start);
        } else if (period === 'week') {
          await exportWeeklyAttendancePdf('all', start, end, { dept: deptFilter, branch: branchFilter });
        } else {
          await exportMonthlyAttendancePdf(start.slice(0, 7), { dept: deptFilter, branch: branchFilter });
        }
      }
      toast({ message: `تم تصدير التقرير ${period === 'day' ? 'اليومي' : period === 'week' ? 'الأسبوعي' : 'الشهري'} بنجاح`, tone: 'success' });
    } catch (error) {
      toast({ message: safeErrorMessage(error), tone: 'error' });
    } finally {
      setIsExporting(false);
    }
  };

  const periodLabel = period === 'day' ? 'يومي' : period === 'week' ? 'أسبوعي' : 'شهري';
  const scopeLabel = scope === 'individual' ? 'فردي' : scope === 'team' ? 'فريقي' : 'شامل';

  return (
    <div className="space-y-6">
      <PageHeader
        title="تقارير الحضور والانصراف"
        description={`إنشاء وطباعة تقارير ${periodLabel} (${scopeLabel}) — مع الإجازات، المأموريات، الطلبات، والقوافل.`}
        actions={
          <div className="flex flex-wrap gap-2">
            <button type="button" className="btn-primary" onClick={() => void handleExport()} disabled={isExporting || !canViewAll}>
              <Download className="size-4" aria-hidden="true" />
              {isExporting ? 'جاري التصدير…' : `تصدير ${periodLabel} PDF`}
            </button>
            <button type="button" className="btn-secondary" onClick={() => window.print()}>
              <Printer className="size-4" aria-hidden="true" />
              طباعة
            </button>
            {!isIndividual && (
              <Link to="/hr/attendance" className="btn-secondary">
                <ArrowLeft className="size-4" />
                عودة للحضور
              </Link>
            )}
          </div>
        }
      />

      <div className="card p-4 space-y-4">
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">النطاق:</label>
            <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] p-1" role="radiogroup">
              {(['day', 'week', 'month'] as ReportPeriod[]).map((p) => (
                <button
                  key={p}
                  type="button"
                  role="radio"
                  aria-checked={period === p}
                  onClick={() => setPeriod(p)}
                  className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                    period === p ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
                  }`}
                >
                  {p === 'day' ? 'يوم' : p === 'week' ? 'أسبوع' : 'شهر'}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">النوع:</label>
            <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] p-1" role="radiogroup">
              {(['individual', 'team', 'all'] as ReportScope[])
                .filter((s) => !isIndividual || s === 'individual')
                .map((s) => (
                  <button
                    key={s}
                    type="button"
                    role="radio"
                    aria-checked={scope === s}
                    onClick={() => setScope(s)}
                    className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                      scope === s ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
                    }`}
                  >
                    {s === 'individual' ? 'فردي' : s === 'team' ? 'فريقي' : 'شامل'}
                  </button>
                ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">{period === 'month' ? 'الشهر:' : period === 'week' ? 'الأسبوع:' : 'اليوم:'}</label>
            <input
              type={period === 'month' ? 'month' : 'date'}
              className="input w-auto"
              value={period === 'month' ? dateIso.slice(0, 7) : dateIso}
              onChange={(e) => setDateIso(period === 'month' ? `${e.target.value}-01` : e.target.value)}
              max={cairoTodayIso()}
              aria-label="اختر التاريخ"
            />
          </div>

          {!isIndividual && scope !== 'individual' && (
            <div className="flex flex-wrap gap-2">
              <select className="input w-auto" value={deptFilter} onChange={(e) => setDeptFilter(e.target.value)} aria-label="تصفية حسب الإدارة">
                <option value="">كل الإدارات</option>
              </select>
              <select className="input w-auto" value={branchFilter} onChange={(e) => setBranchFilter(e.target.value)} aria-label="تصفية حسب الفرع">
                <option value="">كل الفروع</option>
              </select>
            </div>
          )}

          <div className="flex-1" />
          <div className="flex items-center gap-4 text-sm text-[var(--text-muted)]">
            <span className="flex items-center gap-1">
              <CalendarRange className="size-4" aria-hidden="true" /> {start} → {end}
            </span>
            <span className="flex items-center gap-1">
              <FileText className="size-4" aria-hidden="true" /> {periodLabel}
            </span>
            <span className="flex items-center gap-1">
              <Users className="size-4" aria-hidden="true" /> {scopeLabel}
            </span>
          </div>
        </div>
      </div>

      <Tabs
        tabs={[
          { id: 'attendance', label: 'الحضور والانصراف' },
          { id: 'leaves', label: 'الإجازات' },
          { id: 'missions', label: 'المأموريات' },
          { id: 'requests', label: 'الطلبات' },
          { id: 'convoys', label: 'القوافل' },
        ]}
        activeTab="attendance"
        onTabChange={() => {}}
        ariaLabel="أقسام التقرير"
      >
        {isIndividual && employeeId ? (
          <>
            {statement.isError ? (
              <ErrorState title="تعذر تحميل الكشف" description={safeErrorMessage(statement.error)} onRetry={() => void statement.refetch()} />
            ) : null}
            {statement.isLoading ? (
              <SkeletonCard className="h-72" />
            ) : statement.data ? (
              <div className="space-y-6">
                <div className="card p-5">
                  <div className="flex flex-wrap items-center justify-between gap-4">
                    <div>
                      <h2 className="text-xl font-black">{statement.data.employee.fullNameAr}</h2>
                      <p className="muted mt-1">
                        {statement.data.employee.jobTitle} • {statement.data.employee.employeeCode}
                      </p>
                    </div>
                    <div className="rounded-2xl bg-[var(--surface-muted)] p-4 text-start">
                      <p className="muted text-xs">الفترة</p>
                      <p className="font-black">
                        {MONTHS[statement.data.period.month - 1]} {statement.data.period.year}
                      </p>
                    </div>
                  </div>
                </div>

                <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
                  <MetricCard label="أيام الحضور" value={statement.data.summary.presentDays} icon={BadgeCheck} />
                  <MetricCard label="أيام الغياب" value={statement.data.summary.absentDays} icon={CalendarDays} />
                  <MetricCard label="إجازات" value={statement.data.summary.leaveDays} icon={CalendarDays} />
                  <MetricCard label="مأموريات" value={statement.data.summary.missionDays} icon={Plane} />
                  <MetricCard label="ساعات العمل" value={statement.data.summary.totalWorkHours.toFixed(1)} icon={Clock3} />
                </section>

                <section className="card p-4">
                  <h3 className="font-black mb-4">تفصيل الأيام</h3>
                  <div className="overflow-auto">
                    <table className="data-table w-full">
                      <thead className="sticky top-0 z-10">
                        <tr>
                          <th>التاريخ</th>
                          <th>اليوم</th>
                          <th>الحضور</th>
                          <th>الانصراف</th>
                          <th>الوردية</th>
                          <th>ساعات</th>
                          <th>تأخير</th>
                          <th>خروج مبكر</th>
                          <th>إضافي</th>
                          <th>الحالة</th>
                        </tr>
                      </thead>
                      <tbody>
                        {statement.data.days.map((d) => (
                          <tr key={d.date} className={d.isOpenShift ? 'bg-[var(--info-soft)]' : d.isAbsent ? 'bg-[var(--danger-soft)]' : ''}>
                            <td>{d.date}</td>
                            <td>{d.dayNameAr}</td>
                            <td>{fmtTime12(d.checkIn)}</td>
                            <td>{fmtTime12(d.checkOut)}</td>
                            <td>{d.shiftName || '—'}</td>
                            <td>{d.workHours ? d.workHours.toFixed(1) : '—'}</td>
                            <td>{d.lateMinutes ? `${d.lateMinutes} د` : '—'}</td>
                            <td>{d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : '—'}</td>
                            <td>{d.overtimeMinutes ? `${d.overtimeMinutes} د` : '—'}</td>
                            <td>
                              <StatusBadge value={d.status} />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </section>
              </div>
            ) : (
              <EmptyState title="لا توجد بيانات" description="لا يوجد كشف لهذا الموظف في الفترة المحددة." />
            )}
          </>
        ) : (
          <div className="space-y-6">
            <div className="card p-4">
              <h3 className="font-black mb-4">
                ملخص {scope === 'all' ? 'الشركة' : 'الفريق'} — {periodLabel}
              </h3>
              <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                <MetricCard label="إجمالي الموظفين" value={0} icon={Users} />
                <MetricCard label="حضور فعلي" value={0} icon={BadgeCheck} />
                <MetricCard label="غياب" value={0} icon={CalendarDays} />
                <MetricCard label="مأموريات" value={0} icon={Plane} />
              </div>
              <p className="muted mt-4 text-sm text-center">اختر نطاق التاريخ واضغط «تصدير PDF» للحصول على التقرير الكامل مع الجداول التفصيلية.</p>
            </div>

            <section className="card p-4">
              <h3 className="font-black mb-4">إجازات {scope === 'all' ? 'الشركة' : 'الفريق'}</h3>
              <p className="muted text-sm">سيظهر التفصيل في ملف PDF المُصدّر.</p>
            </section>

            <section className="card p-4">
              <h3 className="font-black mb-4">مأموريات {scope === 'all' ? 'الشركة' : 'الفريق'}</h3>
              <p className="muted text-sm">سيظهر التفصيل في ملف PDF المُصدّر.</p>
            </section>

            <section className="card p-4">
              <h3 className="font-black mb-4">طلبات {scope === 'all' ? 'الشركة' : 'الفريق'}</h3>
              <p className="muted text-sm">سيظهر التفصيل في ملف PDF المُصدّر.</p>
            </section>

            <section className="card p-4">
              <h3 className="font-black mb-4">قوافل {scope === 'all' ? 'الشركة' : 'الفريق'}</h3>
              <p className="muted text-sm">سيظهر التفصيل في ملف PDF المُصدّر.</p>
            </section>
          </div>
        )}
      </Tabs>
    </div>
  );
}
