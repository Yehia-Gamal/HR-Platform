import { ArrowLeft, CalendarDays, Download, Printer, Search, ShieldCheck, TrendingUp, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { cairoTodayIso } from '../../core/cairoTime';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useExecutiveDailyReport, useExecutiveDailyReportDetail, exportExecutiveDailyReportPdf } from './useAttendanceDashboard';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';

const STATUS_LABELS: Record<string, string> = {
  present: 'حاضر',
  late: 'متأخر',
  absent: 'غائب',
  on_leave: 'إجازة',
  holiday: 'عطلة',
  weekend: 'عطلة الأسبوع',
  partial: 'جزئي',
  pending: 'قيد الانتظار',
  on_mission: 'مأمورية',
  missing_checkout: 'بصمة بلا انصراف',
};

function statusLabel(status: string | null): string {
  if (!status) return '—';
  return STATUS_LABELS[status] ?? status;
}

function statusClass(status: string | null): string {
  if (status === 'present') return 'status-pill--ok';
  if (status === 'late') return 'status-pill--warn';
  if (status === 'absent') return 'status-pill--danger';
  if (status === 'missing_checkout') return 'status-pill--warn';
  if (status === 'on_leave') return 'status-pill--ok';
  if (status === 'on_mission') return 'status-pill--neutral';
  return 'status-pill--neutral';
}

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

function pctColor(pct: number): string {
  return pct >= 90 ? '#059669' : pct >= 75 ? '#f59e0b' : '#dc2626';
}

export function ExecutiveDailyReportPage() {
  const { toast } = useToast();
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const dateParam = params.get('date');
  const dateIso = /^\d{4}-\d{2}-\d{2}$/.test(dateParam ?? '') ? (dateParam as string) : cairoTodayIso();
  const [search, setSearch] = useState('');
  const [deptFilter, setDeptFilter] = useState('');
  const [branchFilter, setBranchFilter] = useState('');
  const [isExporting, setIsExporting] = useState(false);

  const canViewExecutive = Boolean(auth.access && hasPermission(auth.access, 'reports.executive.read'));
  const canExport = canViewExecutive;

  const report = useExecutiveDailyReport(dateIso);
  const detail = useExecutiveDailyReportDetail(dateIso);

  useEffect(() => {
    const next = new URLSearchParams(params);
    next.set('date', dateIso);
    setParams(next, { replace: true });
  }, [dateIso, params, setParams]);

  const s = report.data;
  const d = detail.data;

  if (!canViewExecutive) {
    return <ErrorState title="غير مصرح" description="هذا التقرير متاح للتنفيذيين والسكرتارية التنفيذية فقط." />;
  }
  if (report.isError || detail.isError) {
    return <ErrorState title="تعذر تحميل التقرير" description={safeErrorMessage(report.error ?? detail.error)} onRetry={() => { void report.refetch(); void detail.refetch(); }} />;
  }
  if (report.isLoading || detail.isLoading) {
    return (
      <div className="space-y-4">
        <SkeletonCard className="h-32" />
        <SkeletonCard className="h-32" />
        <SkeletonCard className="h-32" />
      </div>
    );
  }
  if (!s) {
    return <EmptyState title="لا توجد بيانات" description="لم يتم العثور على بيانات لهذا اليوم." />;
  }

  // حسابات ملخصة
  const totalEmployees = s.employees?.active ?? 0;
  const requiredToday = s.employees?.requiredToday ?? 0;
  const present = s.attendance?.present ?? 0;
  const late = s.attendance?.late ?? 0;
  const absent = s.attendance?.absent ?? 0;
  const notYet = s.attendance?.notYet ?? 0;
  const checkedOut = s.attendance?.checkedOut ?? 0;
  const missingCheckout = s.attendance?.missingCheckout ?? 0;
  const approvedLeave = s.workStatus?.approvedLeave ?? 0;
  const missions = s.workStatus?.missions ?? 0;
  const convoys = s.workStatus?.convoys ?? 0;
  const fundraising = s.workStatus?.fundraising ?? 0;
  const pendingLeave = s.requests?.pendingLeave ?? 0;
  const pendingMission = s.requests?.pendingMission ?? 0;
  const attendancePct = requiredToday > 0 ? ((present / requiredToday) * 100).toFixed(1) : '0.0';

  const date = new Date(dateIso);
  const dayName = date.toLocaleDateString('ar-EG', { weekday: 'long' });
  const monthName = date.toLocaleDateString('ar-EG', { month: 'long', year: 'numeric' });

  const handleExport = async () => {
    setIsExporting(true);
    try {
      await exportExecutiveDailyReportPdf(dateIso);
      toast({ message: 'تم تصدير التقرير التنفيذي كـ PDF', tone: 'success' });
    } catch (error) {
      toast({ message: safeErrorMessage(error), tone: 'error' });
    } finally {
      setIsExporting(false);
    }
  };

  const handlePrint = () => window.print();

  return (
    <div className="space-y-6">
      <PageHeader
        title="التقرير التنفيذي اليومي الشامل"
        description={`ملخص تنفيذي مفصل ليوم ${dayName}، ${date.getDate()} ${monthName} — الحضور، المأموريات، القوافل، الإجازات، الخلافات، والمتابعات.`}
        actions={
          <div className="flex flex-wrap gap-2">
            {canExport ? (
              <button
                type="button"
                className="btn-primary"
                onClick={handleExport}
                disabled={isExporting}
              >
                <Download className="size-4" aria-hidden="true" />
                {isExporting ? 'جاري التصدير…' : 'تصدير PDF'}
              </button>
            ) : null}
            <button type="button" className="btn-secondary" onClick={handlePrint}>
              <Printer className="size-4" aria-hidden="true" />
              طباعة
            </button>
            <Link to="/hr/attendance" className="btn-secondary">
              <ArrowLeft className="size-4" aria-hidden="true" />
              عودة للحضور
            </Link>
          </div>
        }
      />

      {/* اختيار التاريخ */}
      <div className="card p-4 flex flex-wrap items-center gap-4">
        <label className="flex items-center gap-2">
          <CalendarDays className="size-5 text-[var(--brand-primary)]" aria-hidden="true" />
          <input
            type="date"
            className="input w-auto"
            value={dateIso}
            onChange={(e) => setParams({ date: e.target.value }, { replace: true })}
            max={cairoTodayIso()}
            aria-label="اختر تاريخ التقرير"
          />
        </label>
        <div className="flex-1" />
        <div className="flex items-center gap-4 text-sm text-[var(--text-muted)]">
          <span><ShieldCheck className="size-4" aria-hidden="true" /> صلاحية تنفيذية</span>
          <span><Users className="size-4" aria-hidden="true" /> {totalEmployees} موظف نشط</span>
        </div>
      </div>

      {/* بطاقات الملخص التنفيذي */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-7">
        <MetricCard
          label="إجمالي الموظفين"
          value={totalEmployees}
          icon={Users}
        />
        <MetricCard
          label="مطلوب حضورهم اليوم"
          value={requiredToday}
          icon={Users}
          hint={`الحضور: ${attendancePct}%`}
        />
        <MetricCard
          label="حضور فعلي"
          value={present}
          hint={late > 0 ? `متأخرين: ${late}` : undefined}
          icon={TrendingUp}
        />
        <MetricCard
          label="متأخرون"
          value={late}
          icon={TrendingUp}
        />
        <MetricCard
          label="غياب"
          value={absent}
          icon={TrendingUp}
        />
        <MetricCard
          label="بصمة بلا انصراف"
          value={missingCheckout}
          icon={TrendingUp}
        />
        <MetricCard
          label="لم يسجلوا بعد"
          value={notYet}
          hint={`مغادرون: ${checkedOut}`}
          icon={TrendingUp}
        />
      </section>

      {/* بطاقات حالة العمل */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجازات معتمدة" value={approvedLeave} icon={CalendarDays} />
        <MetricCard label="مأموريات" value={missions} icon={CalendarDays} />
        <MetricCard label="قوافل" value={convoys} icon={CalendarDays} />
        <MetricCard label="جمع/فاندي" value={fundraising} icon={CalendarDays} />
      </section>

      {/* طلبات معلقة */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجازات معلقة" value={pendingLeave} icon={CalendarDays} />
        <MetricCard label="مأموريات/قوافل معلقة" value={pendingMission} icon={CalendarDays} />
        <MetricCard label="قرارات متابعة" value={s.followUp?.decisions ?? 0} icon={ShieldCheck} />
        <MetricCard label="تقارير مفقودة" value={s.followUp?.missingReports ?? 0} icon={ShieldCheck} />
      </section>

      {/* طلبات الموقع */}
      <section className="grid gap-4 sm:grid-cols-2">
        <MetricCard
          label="طلبات موقع نشطة"
          value={s.followUp?.activeLocationRequests ?? 0}
          icon={ShieldCheck}
        />
        <MetricCard
          label="طلبات بلا استجابة"
          value={s.followUp?.unansweredLocationRequests ?? 0}
          hint="حرجة"
          icon={ShieldCheck}
        />
      </section>

      {/* KPI */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <MetricCard label="عند الموظف" value={s.kpi?.atEmployee ?? 0} icon={TrendingUp} />
        <MetricCard label="عند المدير" value={s.kpi?.atManager ?? 0} icon={TrendingUp} />
        <MetricCard label="عند الموارد البشرية" value={s.kpi?.atHr ?? 0} icon={TrendingUp} />
        <MetricCard label="جاهزة" value={s.kpi?.ready ?? 0} hint="مُعتمدة" icon={TrendingUp} />
        <MetricCard label="متأخرة" value={s.kpi?.overdue ?? 0} hint="حرجة" icon={TrendingUp} />
      </section>

      {/* خلافات */}
      <section className="grid gap-4 sm:grid-cols-2">
        <MetricCard label="قضايا جديدة" value={s.cases?.new ?? 0} icon={ShieldCheck} />
        <MetricCard label="قضايا مفتوحة" value={s.cases?.open ?? 0} icon={ShieldCheck} />
      </section>

      {/* تفاصيل الموظفين - إذا متاح */}
      {d?.employees && d.employees.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">تفصيل حضور الموظفين ({d.employees.length})</h2>
          <div className="max-h-[60vh] overflow-auto">
            <table className="data-table w-full">
              <thead className="sticky top-0 z-10">
                <tr>
                  <th>الكود</th><th>الاسم</th><th>الحالة</th><th>الإدارة</th>
                  <th>الحضور</th><th>الانصراف</th><th>التأخير</th>
                  <th>الوردية</th><th>الموقع</th><th>العذر</th><th>ساعات العمل</th>
                </tr>
              </thead>
              <tbody>
                {d.employees
                  .filter(emp => !search || `${emp.employeeName} ${emp.employeeCode ?? ''} ${emp.departmentName ?? ''}`.toLowerCase().includes(search.toLowerCase()))
                  .filter(emp => !deptFilter || emp.departmentId === deptFilter)
                  .filter(emp => !branchFilter || emp.branchId === branchFilter)
                  .map(emp => (
                    <tr key={emp.employeeId} className={statusClass(emp.status)}>
                      <td>{emp.employeeCode ?? '—'}</td>
                      <td>{emp.employeeName}</td>
                      <td><span className={`status-pill ${statusClass(emp.status)}`}>{statusLabel(emp.status)}</span></td>
                      <td>{emp.departmentName ?? '—'}</td>
                      <td>{fmtTime12(emp.firstCheckIn)}</td>
                      <td>{fmtTime12(emp.lastCheckOut)}</td>
                      <td>{emp.lateMinutes ? `${emp.lateMinutes} د` : '—'}</td>
                      <td>{emp.shiftName ?? '—'}</td>
                      <td>{emp.locationRequestStatus ?? '—'}</td>
                      <td>{emp.hasApprovedLeave ? '✓ إجازة' : emp.hasMission ? '✈ مأمورية' : '—'}</td>
                      <td>{emp.workHours?.toFixed(1) ?? '—'}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
            {d.employees.length > 0 && (
              <div className="flex flex-wrap gap-2 mt-4">
                <input
                  type="search"
                  className="input w-auto sm:w-64"
                  placeholder="بحث بالاسم/الكود/الإدارة..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  aria-label="بحث في الموظفين"
                />
                <select className="input w-auto" value={deptFilter} onChange={(e) => setDeptFilter(e.target.value)} aria-label="تصفية حسب الإدارة">
                  <option value="">كل الإدارات</option>
                  {(d.employees as any[])
                    .map(e => e.departmentId).filter(Boolean)
                    .reduce<string[]>((acc, id: string) => acc.includes(id) ? acc : [...acc, id], [])
                    .map(id => {
                      const emp = d.employees.find(e => e.departmentId === id);
                      return <option key={id} value={id}>{emp?.departmentName}</option>;
                    })}
                </select>
              </div>
            )}
          </div>
        </section>
      )}

      {/* المأموريات */}
      {d?.missions && d.missions.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">المأموريات ({d.missions.length})</h2>
          <table className="data-table w-full">
            <thead><tr><th>الكود</th><th>الاسم</th><th>النوع</th><th>الوجهة</th><th>البداية</th><th>النهاية</th><th>الحالة</th><th>الغرض</th></tr></thead>
            <tbody>
              {d.missions.map(m => (
                <tr key={m.id}>
                  <td>{m.employeeCode ?? '—'}</td>
                  <td>{m.employeeName}</td>
                  <td>{m.missionType}</td>
                  <td>{m.destination}</td>
                  <td>{fmtTime12(m.startAt)}</td>
                  <td>{fmtTime12(m.endAt)}</td>
                  <td><span className={`status-pill ${statusClass(m.status)}`}>{statusLabel(m.status)}</span></td>
                  <td>{m.purpose ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* القوافل */}
      {d?.convoys && d.convoys.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">القوافل ({d.convoys.length})</h2>
          <table className="data-table w-full">
            <thead><tr><th>الكود</th><th>العنوان</th><th>النوع</th><th>المشاركون</th><th>البداية</th><th>النهاية</th><th>الحالة</th></tr></thead>
            <tbody>
              {d.convoys.map(c => (
                <tr key={c.id}>
                  <td>{c.code}</td>
                  <td>{c.title}</td>
                  <td>{c.type}</td>
                  <td>{c.participantsCount}</td>
                  <td>{fmtTime12(c.startAt)}</td>
                  <td>{fmtTime12(c.endAt)}</td>
                  <td><span className={`status-pill ${statusClass(c.status)}`}>{statusLabel(c.status)}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* الإجازات */}
      {d?.leaves && d.leaves.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">الإجازات ({d.leaves.length})</h2>
          <table className="data-table w-full">
            <thead><tr><th>الكود</th><th>الاسم</th><th>النوع</th><th>البداية</th><th>النهاية</th><th>الأيام</th><th>الحالة</th></tr></thead>
            <tbody>
              {d.leaves.map(l => (
                <tr key={l.id}>
                  <td>{l.employeeCode ?? '—'}</td>
                  <td>{l.employeeName}</td>
                  <td>{l.leaveType}</td>
                  <td>{fmtTime12(l.startAt)}</td>
                  <td>{fmtTime12(l.endAt)}</td>
                  <td>{l.daysCount}</td>
                  <td><span className={`status-pill ${statusClass(l.status)}`}>{statusLabel(l.status)}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* طلبات الموقع */}
      {d?.locationRequests && d.locationRequests.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">طلبات الموقع ({d.locationRequests.length})</h2>
          <table className="data-table w-full">
            <thead><tr><th>الكود</th><th>الاسم</th><th>النوع</th><th>الموقع</th><th>وقت الطلب</th><th>الحالة</th></tr></thead>
            <tbody>
              {d.locationRequests.map(lr => (
                <tr key={lr.id}>
                  <td>{lr.employeeCode ?? '—'}</td>
                  <td>{lr.employeeName}</td>
                  <td>{lr.requestType}</td>
                  <td>{lr.locationName}</td>
                  <td>{fmtTime12(lr.requestedAt)}</td>
                  <td><span className={`status-pill ${statusClass(lr.status)}`}>{statusLabel(lr.status)}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* الخلافات */}
      {d?.disputes && d.disputes.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">الخلافات ({d.disputes.length})</h2>
          <table className="data-table w-full">
            <thead><tr><th>الرقم</th><th>العنوان</th><th>النوع</th><th>الحالة</th><th>الأولوية</th><th>مقدم الطلب</th></tr></thead>
            <tbody>
              {d.disputes.map(dsp => (
                <tr key={dsp.id}>
                  <td>{dsp.caseNumber}</td>
                  <td>{dsp.title}</td>
                  <td>{dsp.caseType}</td>
                  <td><span className={`status-pill ${statusClass(dsp.status)}`}>{statusLabel(dsp.status)}</span></td>
                  <td>{dsp.priority}</td>
                  <td>{dsp.actorName ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {/* لا توجد بيانات تفصيلية */}
      {(!d?.employees || d.employees.length === 0) && (
        <div className="card p-8 text-center">
          <EmptyState
            title="بيانات الملخص متاحة فقط"
            description="لتفعيل التفاصيل الكاملة (الموظفين، المأموريات، القوافل، الإجازات)، يلزم إضافة RPC مخصص get_executive_daily_report_detail في قاعدة البيانات."
          />
        </div>
      )}
    </div>
  );
}