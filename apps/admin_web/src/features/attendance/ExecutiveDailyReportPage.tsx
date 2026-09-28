import {
  AlertTriangle,
  ArrowLeft,
  CalendarDays,
  Copy,
  Download,
  ExternalLink,
  Printer,
  ShieldCheck,
  Sparkles,
  TrendingUp,
  Users,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
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
import { fmtMinutesCompact } from './attendanceShared';
import { AppBarChart, AppPieChart, ChartCard } from '../../ui/charts';

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

export function ExecutiveDailyReportPage() {
  const { toast } = useToast();
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const dateParam = params.get('date');
  const dateIso = /^\d{4}-\d{2}-\d{2}$/.test(dateParam ?? '') ? (dateParam as string) : cairoTodayIso();
  const [search, setSearch] = useState('');
  const [deptFilter, setDeptFilter] = useState('');
  const [branchFilter] = useState('');
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

  // Memoize date-derived values so they don't change every render
  const { dayName, monthName, dateDay } = useMemo(() => {
    const dt = new Date(dateIso);
    return {
      dayName: dt.toLocaleDateString('ar-EG', { weekday: 'long' }),
      monthName: dt.toLocaleDateString('ar-EG', { month: 'long', year: 'numeric' }),
      dateDay: dt.getDate(),
    };
  }, [dateIso]);

  // Pre-compute executive digest text (must be before early returns per rules-of-hooks)
  const executiveDigestText = useMemo(() => {
    if (!s) return '';
    const present = s.attendance?.present ?? 0;
    const requiredToday = s.employees?.requiredToday ?? 0;
    const late = s.attendance?.late ?? 0;
    const absent = s.attendance?.absent ?? 0;
    const missions = s.workStatus?.missions ?? 0;
    const convoys = s.workStatus?.convoys ?? 0;
    const approvedLeave = s.workStatus?.approvedLeave ?? 0;
    const missingCheckout = s.attendance?.missingCheckout ?? 0;
    const attendancePct = requiredToday > 0 ? ((present / requiredToday) * 100).toFixed(1) : '0.0';
    const lines = [
      `📊 *التقرير التنفيذي اليومي — أحلى شباب*`,
      `📅 اليوم والتاريخ: ${dayName}، ${dateDay} ${monthName}`,
      `👥 إجمالي الحضور: ${present} من أصل ${requiredToday} مجدول (نسبة الإنجاز: ${attendancePct}%)`,
      `⏰ التأخيرات: ${late === 0 ? 'لا توجد تأخيرات مسجلة 👏' : `${late} حالة تأخير`}`,
      `🚫 الغياب: ${absent > 0 ? `${absent} موظفاً` : 'صفر غياب'}`,
      `✈️ المأموريات والقوافل: ${missions} مأمورية ميدانية · ${convoys} قوافل عمل`,
      `🏖️ الإجازات المعتمدة: ${approvedLeave} موظفاً`,
      `⚠️ تنبيهات المتابعة: ${missingCheckout > 0 ? `${missingCheckout} بصمة بلا انصراف مسجلة تحتاج لتسوية` : 'كافة البصمات منتظمة ومسواة'}`,
      `---`,
      `تم التوليد آلياً عبر نظام إدارة الموارد البشرية أحلى شباب`,
    ];
    return lines.join('\n');
  }, [s, dayName, dateDay, monthName]);

  // توزيع الحضور عبر الإدارات الرئيسية للرسم البياني العمودي
  const deptBarData = useMemo(() => {
    if (!d?.employees || d.employees.length === 0) return [];
    const deptMap = new Map<string, { label: string; حاضر: number; متأخر: number; غائب: number; total: number }>();
    for (const emp of d.employees) {
      const deptName = emp.departmentName || 'إدارة غير محددة';
      if (!deptMap.has(deptName)) {
        deptMap.set(deptName, { label: deptName, حاضر: 0, متأخر: 0, غائب: 0, total: 0 });
      }
      const item = deptMap.get(deptName)!;
      item.total += 1;
      if (emp.status === 'present') {
        item.حاضر += 1;
      } else if (emp.status === 'late') {
        item.متأخر += 1;
      } else if (emp.status === 'absent') {
        item.غائب += 1;
      }
    }
    return Array.from(deptMap.values())
      .sort((a, b) => b.total - a.total)
      .slice(0, 8);
  }, [d?.employees]);

  // توزيع الحالات الشامل للرسم البياني الدائري
  const workStatusPieData = useMemo(() => {
    if (!s) return [];
    const p = s.attendance?.present ?? 0;
    const l = s.attendance?.late ?? 0;
    const ab = s.attendance?.absent ?? 0;
    const onTime = Math.max(0, p - l);
    const lv = s.workStatus?.approvedLeave ?? 0;
    const m = (s.workStatus?.missions ?? 0) + (s.workStatus?.convoys ?? 0);
    const mc = s.attendance?.missingCheckout ?? 0;
    const items = [
      { name: 'حاضر بالموعد', value: onTime, color: 'var(--success, #10b981)' },
      { name: 'متأخر', value: l, color: 'var(--warning, #f59e0b)' },
      { name: 'غائب', value: ab, color: 'var(--danger, #ef4444)' },
      { name: 'في إجازة', value: lv, color: '#3b82f6' },
      { name: 'مأموريات وقوافل', value: m, color: '#8b5cf6' },
      { name: 'بصمة بلا انصراف', value: mc, color: '#ec4899' },
    ];
    return items.filter((i) => i.value > 0);
  }, [s]);

  // مصفوفة الحالات ذات الأولوية للتدخل التنفيذي العاجل
  const urgentActions = useMemo(() => {
    if (!d?.employees) return [];
    return d.employees
      .filter((emp) => {
        const isVeryLate = (emp.lateMinutes ?? 0) >= 60;
        const isUnexcusedAbsent = emp.status === 'absent' && !emp.hasApprovedLeave && !emp.hasMission;
        const isMissingCheckout = !emp.lastCheckOut && Boolean(emp.firstCheckIn);
        return isVeryLate || isUnexcusedAbsent || isMissingCheckout;
      })
      .slice(0, 6);
  }, [d?.employees]);

  if (!canViewExecutive) {
    return <ErrorState title="غير مصرح" description="هذا التقرير متاح للتنفيذيين والسكرتارية التنفيذية فقط." />;
  }
  if (report.isError || detail.isError) {
    return (
      <ErrorState
        title="تعذر تحميل التقرير"
        description={safeErrorMessage(report.error ?? detail.error)}
        onRetry={() => {
          void report.refetch();
          void detail.refetch();
        }}
      />
    );
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

  const handleCopyDigest = async () => {
    try {
      await navigator.clipboard.writeText(executiveDigestText);
      toast({ message: 'تم نسخ الملخص التنفيذي إلى الحافظة بنجاح!', tone: 'success' });
    } catch {
      toast({ message: 'تعذر نسخ الملخص تلقائياً، يرجى المحاولة يدوياً.', tone: 'error' });
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="التقرير التنفيذي اليومي الشامل"
        description={`ملخص تنفيذي مفصل ليوم ${dayName}، ${dateDay} ${monthName} — الحضور، المأموريات، القوافل، الإجازات، الخلافات، والمتابعات.`}
        actions={
          <div className="flex flex-wrap gap-2">
            {canExport ? (
              <button type="button" className="btn-primary" onClick={handleExport} disabled={isExporting}>
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
          <span>
            <ShieldCheck className="size-4" aria-hidden="true" /> صلاحية تنفيذية
          </span>
          <span>
            <Users className="size-4" aria-hidden="true" /> {totalEmployees} موظف نشط
          </span>
        </div>
      </div>

      {/* بطاقات الملخص التنفيذي */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-7">
        <MetricCard label="إجمالي الموظفين" value={totalEmployees} icon={Users} />
        <MetricCard label="مطلوب حضورهم اليوم" value={requiredToday} icon={Users} hint={`الحضور: ${attendancePct}%`} />
        <MetricCard label="حضور فعلي" value={present} hint={late > 0 ? `متأخرين: ${late}` : undefined} icon={TrendingUp} />
        <MetricCard label="متأخرون" value={late} icon={TrendingUp} />
        <MetricCard label="غياب" value={absent} icon={TrendingUp} />
        <MetricCard label="بصمة بلا انصراف" value={missingCheckout} icon={TrendingUp} />
        <MetricCard label="لم يسجلوا بعد" value={notYet} hint={`مغادرون: ${checkedOut}`} icon={TrendingUp} />
      </section>

      {/* بطاقات حالة العمل */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجازات معتمدة" value={approvedLeave} icon={CalendarDays} />
        <MetricCard label="مأموريات" value={missions} icon={CalendarDays} />
        <MetricCard label="قوافل" value={convoys} icon={CalendarDays} />
        <MetricCard label="يوم ترفيهي (فاندي)" value={fundraising} icon={CalendarDays} />
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
        <MetricCard label="طلبات موقع نشطة" value={s.followUp?.activeLocationRequests ?? 0} icon={ShieldCheck} />
        <MetricCard label="طلبات بلا استجابة" value={s.followUp?.unansweredLocationRequests ?? 0} hint="حرجة" icon={ShieldCheck} />
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

      {/* الموجز التحليلي التنفيذي الذكي */}
      <section className="card p-5 border-r-4 border-r-[var(--brand-primary)] bg-gradient-to-l from-[var(--surface)] to-[var(--surface-muted)]">
        <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-[var(--border)]">
          <div className="flex items-center gap-2">
            <span className="flex size-8 items-center justify-center rounded-lg bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]">
              <Sparkles className="size-4" aria-hidden="true" />
            </span>
            <div>
              <h2 className="text-base font-black">الموجز التحليلي والملخص التنفيذي لليوم</h2>
              <p className="text-xs muted">قراءة ذكية وموجزة لحالة العمليات والحضور والانضباط</p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => void handleCopyDigest()}
            className="btn-secondary text-xs flex items-center gap-1.5"
            title="نسخ الملخص التنفيذي للمشاركة"
          >
            <Copy className="size-3.5" aria-hidden="true" />
            نسخ الملخص التنفيذي
          </button>
        </div>

        <div className="mt-4 grid gap-4 lg:grid-cols-3">
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3.5 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-[var(--text-muted)]">نسبة الحضور والإنجاز</span>
              <span className="font-black text-sm text-[var(--success)]">{attendancePct}%</span>
            </div>
            <p className="text-xs leading-relaxed">
              حضور <strong className="tabular">{present}</strong> من إجمالي <strong className="tabular">{requiredToday}</strong> موظفاً مجدولاً اليوم.
              {absent > 0 ? ` سُجل غياب ${absent} موظفاً.` : ' لا يوجد أي غياب مسجل.'}
            </p>
          </div>

          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3.5 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-[var(--text-muted)]">مؤشر الانضباط والتأخيرات</span>
              <span className={`font-black text-sm ${late > 0 ? 'text-[var(--warning)]' : 'text-[var(--success)]'}`}>
                {late === 0 ? 'انضباط كامل' : `${late} متأخر`}
              </span>
            </div>
            <p className="text-xs leading-relaxed">
              {late === 0
                ? 'لم تسجل أي حالات تأخير عن مواعيد الحضور المحددة للورديات.'
                : `تم رصد ${late} موظفاً تجاوزوا موعد الحضور المحدد، وتتطلب مراجعة مبررات التأخير.`}
            </p>
          </div>

          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3.5 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-[var(--text-muted)]">العمليات الميدانية والسلامة</span>
              <span className="font-black text-sm text-[var(--brand-primary)]">{missions + convoys} مهمة</span>
            </div>
            <p className="text-xs leading-relaxed">
              {missions > 0 ? `${missions} مأموريات نشطة · ` : ''}
              {convoys > 0 ? `${convoys} قوافل · ` : ''}
              {approvedLeave > 0 ? `${approvedLeave} في إجازة معتمدة · ` : ''}
              {missingCheckout > 0 ? (
                <span className="text-[var(--warning)] font-bold">{missingCheckout} بصمة بلا انصراف مسجلة تحتاج لتسوية.</span>
              ) : (
                'كافة البصمات منتظمة ومسواة.'
              )}
            </p>
          </div>
        </div>
      </section>

      {/* ─── الرسوم البيانية والتحليل البصري المقارن ─── */}
      <section className="grid gap-5 lg:grid-cols-2">
        <ChartCard
          title="مقارنة الحضور والانضباط عبر الإدارات"
          subtitle="توزيع الحضور الفعلي والمتأخر والغياب لأعلى الإدارات كثافة"
          empty={deptBarData.length === 0}
          height={300}
        >
          <AppBarChart
            data={deptBarData}
            bars={[
              { key: 'حاضر', label: 'حاضر', color: 'var(--success)' },
              { key: 'متأخر', label: 'متأخر', color: 'var(--warning)' },
              { key: 'غائب', label: 'غائب', color: 'var(--danger)' },
            ]}
            height={280}
          />
        </ChartCard>

        <ChartCard
          title="توزيع قوى العمل الكلي اليوم"
          subtitle="الحصيلة الإجمالية لحالات الموظفين المجدولين اليوم"
          empty={workStatusPieData.length === 0}
          height={300}
        >
          <AppPieChart data={workStatusPieData} donut height={270} />
        </ChartCard>
      </section>

      {/* ─── مصفوفة التدخل والمتابعة التنفيذية العاجلة ─── */}
      {urgentActions.length > 0 && (
        <section className="card p-5 border-r-4 border-r-[var(--danger)] bg-gradient-to-l from-[var(--surface)] to-[var(--surface-muted)]">
          <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-[var(--border)]">
            <div className="flex items-center gap-2">
              <span className="flex size-8 items-center justify-center rounded-lg bg-[var(--danger)]/10 text-[var(--danger)]">
                <AlertTriangle className="size-4" aria-hidden="true" />
              </span>
              <div>
                <h3 className="text-base font-black">مصفوفة التدخل والمتابعة التنفيذية العاجلة</h3>
                <p className="text-xs text-[var(--text-muted)]">
                  حالات تستوجب المتابعة الفورية مع الإدارات (تأخير جسيم ≥ ساعة · غياب غير مبرر · بصمة انصراف مفقودة)
                </p>
              </div>
            </div>
            <span className="rounded-full bg-[var(--danger)]/10 px-2.5 py-1 text-xs font-bold text-[var(--danger)]">
              {urgentActions.length} حالات أولوية
            </span>
          </div>

          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 mt-4">
            {urgentActions.map((emp) => {
              const isVeryLate = (emp.lateMinutes ?? 0) >= 60;
              const isUnexcusedAbsent = emp.status === 'absent' && !emp.hasApprovedLeave && !emp.hasMission;
              const isMissingCheckout = !emp.lastCheckOut && Boolean(emp.firstCheckIn);

              let badgeText = 'متابعة';
              let badgeTone = 'warning';
              let issueText = '';

              if (isVeryLate) {
                badgeText = `تأخير ${fmtMinutesCompact(emp.lateMinutes ?? 0)}`;
                badgeTone = 'warning';
                issueText = `حضور ${fmtTime12(emp.firstCheckIn)} · الوردية ${emp.shiftName ?? 'الافتراضية'}`;
              } else if (isUnexcusedAbsent) {
                badgeText = 'غياب بدون إذن';
                badgeTone = 'danger';
                issueText = 'لم يُسجل حضور ولا يوجد طلب إجازة أو مأمورية';
              } else if (isMissingCheckout) {
                badgeText = 'بصمة انصراف مفقودة';
                badgeTone = 'warning';
                issueText = `دخول ${fmtTime12(emp.firstCheckIn)} · لم يتم تسجيل الخروج`;
              }

              return (
                <div
                  key={emp.employeeId}
                  className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3.5 space-y-2 hover:border-[var(--brand-primary)] transition-colors"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <Link
                        to={`/hr/employees/${emp.employeeId}`}
                        className="font-black text-xs hover:text-[var(--brand-primary)] flex items-center gap-1 group"
                      >
                        <span className="truncate">{emp.employeeName}</span>
                        <ExternalLink className="size-3 opacity-0 group-hover:opacity-100 transition-opacity shrink-0" aria-hidden="true" />
                      </Link>
                      <span className="text-[10px] text-[var(--text-muted)] block truncate">
                        {emp.employeeCode ? `#${emp.employeeCode} · ` : ''}{emp.departmentName || 'إدارة غير محددة'}
                      </span>
                    </div>
                    <span
                      className={`shrink-0 rounded-md px-2 py-0.5 text-[10px] font-bold ${
                        badgeTone === 'danger'
                          ? 'bg-[var(--danger)]/10 text-[var(--danger)]'
                          : 'bg-amber-500/10 text-amber-700 dark:text-amber-400'
                      }`}
                    >
                      {badgeText}
                    </span>
                  </div>
                  <p className="text-[11px] text-[var(--text-muted)] leading-relaxed">
                    {issueText}
                  </p>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* تفاصيل الموظفين - إذا متاح */}
      {d?.employees && d.employees.length > 0 && (
        <section className="card p-4">
          <h2 className="font-black mb-4">تفصيل حضور الموظفين ({d.employees.length})</h2>
          <div className="max-h-[60vh] overflow-auto">
            <table className="data-table w-full">
              <thead className="sticky top-0 z-10">
                <tr>
                  <th>الكود</th>
                  <th>الاسم</th>
                  <th>الحالة</th>
                  <th>الإدارة</th>
                  <th>الحضور</th>
                  <th>الانصراف</th>
                  <th>التأخير</th>
                  <th>الوردية</th>
                  <th>الموقع</th>
                  <th>العذر</th>
                  <th>ساعات العمل</th>
                </tr>
              </thead>
              <tbody>
                {d.employees
                  .filter(
                    (emp) =>
                      !search || `${emp.employeeName} ${emp.employeeCode ?? ''} ${emp.departmentName ?? ''}`.toLowerCase().includes(search.toLowerCase()),
                  )
                  .filter((emp) => !deptFilter || emp.departmentId === deptFilter)
                  .filter((emp) => !branchFilter || emp.branchId === branchFilter)
                  .map((emp) => (
                    <tr key={emp.employeeId}>
                      <td>{emp.employeeCode ?? '—'}</td>
                      <td>{emp.employeeName}</td>
                      <td>
                        <StatusBadge status={emp.status ?? undefined} />
                      </td>
                      <td>{emp.departmentName ?? '—'}</td>
                      <td>{fmtTime12(emp.firstCheckIn)}</td>
                      <td>{fmtTime12(emp.lastCheckOut)}</td>
                      <td>{emp.lateMinutes ? fmtMinutesCompact(emp.lateMinutes) : '—'}</td>
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
                  {Array.from(new Map(d.employees.filter((e) => e.departmentId).map((e) => [e.departmentId as string, e])).values()).map((e) => (
                    <option key={e.departmentId} value={e.departmentId ?? ''}>
                      {e.departmentName}
                    </option>
                  ))}
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
            <thead>
              <tr>
                <th>الكود</th>
                <th>الاسم</th>
                <th>النوع</th>
                <th>الوجهة</th>
                <th>البداية</th>
                <th>النهاية</th>
                <th>الحالة</th>
                <th>الغرض</th>
              </tr>
            </thead>
            <tbody>
              {d.missions.map((m) => (
                <tr key={m.id}>
                  <td>{m.employeeCode ?? '—'}</td>
                  <td>{m.employeeName}</td>
                  <td>{m.missionType}</td>
                  <td>{m.destination}</td>
                  <td>{fmtTime12(m.startAt)}</td>
                  <td>{fmtTime12(m.endAt)}</td>
                  <td>
                    <StatusBadge status={m.status ?? undefined} />
                  </td>
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
            <thead>
              <tr>
                <th>الكود</th>
                <th>العنوان</th>
                <th>النوع</th>
                <th>المشاركون</th>
                <th>البداية</th>
                <th>النهاية</th>
                <th>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {d.convoys.map((c) => (
                <tr key={c.id}>
                  <td>{c.code}</td>
                  <td>{c.title}</td>
                  <td>{c.type}</td>
                  <td>{c.participantsCount}</td>
                  <td>{fmtTime12(c.startAt)}</td>
                  <td>{fmtTime12(c.endAt)}</td>
                  <td>
                    <StatusBadge status={c.status ?? undefined} />
                  </td>
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
            <thead>
              <tr>
                <th>الكود</th>
                <th>الاسم</th>
                <th>النوع</th>
                <th>البداية</th>
                <th>النهاية</th>
                <th>الأيام</th>
                <th>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {d.leaves.map((l) => (
                <tr key={l.id}>
                  <td>{l.employeeCode ?? '—'}</td>
                  <td>{l.employeeName}</td>
                  <td>{l.leaveType}</td>
                  <td>{fmtTime12(l.startAt)}</td>
                  <td>{fmtTime12(l.endAt)}</td>
                  <td>{l.daysCount}</td>
                  <td>
                    <StatusBadge status={l.status ?? undefined} />
                  </td>
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
            <thead>
              <tr>
                <th>الكود</th>
                <th>الاسم</th>
                <th>النوع</th>
                <th>الموقع</th>
                <th>وقت الطلب</th>
                <th>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {d.locationRequests.map((lr) => (
                <tr key={lr.id}>
                  <td>{lr.employeeCode ?? '—'}</td>
                  <td>{lr.employeeName}</td>
                  <td>{lr.requestType}</td>
                  <td>{lr.locationName}</td>
                  <td>{fmtTime12(lr.requestedAt)}</td>
                  <td>
                    <StatusBadge status={lr.status ?? undefined} />
                  </td>
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
            <thead>
              <tr>
                <th>الرقم</th>
                <th>العنوان</th>
                <th>النوع</th>
                <th>الحالة</th>
                <th>الأولوية</th>
                <th>مقدم الطلب</th>
              </tr>
            </thead>
            <tbody>
              {d.disputes.map((dsp) => (
                <tr key={dsp.id}>
                  <td>{dsp.caseNumber}</td>
                  <td>{dsp.title}</td>
                  <td>{dsp.caseType}</td>
                  <td>
                    <StatusBadge status={dsp.status ?? undefined} />
                  </td>
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
