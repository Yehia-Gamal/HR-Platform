import { cairoTodayIso } from '../../core/cairoTime';
import { ArrowUpDown, FileSpreadsheet, KeyRound, Network, Plus, Printer, RefreshCw, Search, UserRound, UsersRound, X } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { Pagination } from '../../ui/Pagination';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission, useHrPrefix } from '../workspaces/access';
import { useEmployees } from './useEmployees';
import { usePendingPenaltyEmployees } from '../finance/useInstantPenalties';
import { EmployeeSearchSuggestions } from './EmployeeSearchSuggestions';
import { isPhoneLikeCode, renderSafeIntlPhoneText } from '../../ui/phoneDisplay';
import { OrgChartPage } from '../management/OrgChartPage';
import { hierarchyCompare } from '@ahla/shared-contracts';

type SortMode = 'newest' | 'name' | 'code' | 'hierarchy';
type EmployeesTab = 'directory' | 'org-chart';

const dateFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { year: 'numeric', month: 'short', day: 'numeric' });

export function EmployeesPage() {
  const auth = useAuth();
  const hrPrefix = useHrPrefix();
  const [searchParams, setSearchParams] = useSearchParams();
  const location = useLocation();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [todayStatus, setTodayStatus] = useState('all');
  const [sort, setSort] = useState<SortMode>('hierarchy');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState<number>(100);
  const [searchFocused, setSearchFocused] = useState(false);
  const employees = useEmployees(search, status);
  const { data: pendingPenalties = [] } = usePendingPenaltyEmployees();
  const canCreate = hasPermission(auth.access, 'people.employee.create');
  const canViewOrgChart = hasPermission(auth.access, 'organization.org_chart.read');
  const all = useMemo(() => employees.data ?? [], [employees.data]);

  const pendingMap = useMemo(() => {
    const map = new Map<string, (typeof pendingPenalties)[number]>();
    for (const p of pendingPenalties) {
      map.set(p.employeeId, p);
    }
    return map;
  }, [pendingPenalties]);

  const totalPendingAmount = useMemo(() => pendingPenalties.reduce((sum, p) => sum + p.totalAmount, 0), [pendingPenalties]);

  // تبويب نشط من رابط مباشر (?tab=org-chart) — الدليل افتراضي.
  const tabParam = searchParams.get('tab');
  const tab: EmployeesTab = tabParam === 'org-chart' && canViewOrgChart ? 'org-chart' : 'directory';
  const setTab = (next: EmployeesTab) => {
    if (next === 'org-chart') setSearchParams({ tab: 'org-chart' });
    else setSearchParams({});
  };

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return all
      .filter((employee) => {
        const matchesQuery =
          !query ||
          employee.fullNameAr.toLowerCase().includes(query) ||
          employee.employeeCode.toLowerCase().includes(query) ||
          employee.phoneE164?.includes(query);
        const matchesStatus =
          status === 'all' || (status === 'inactive' ? ['suspended', 'terminated', 'archived'].includes(employee.status) : employee.status === status);
        const matchesToday =
          todayStatus === 'all' ||
          (todayStatus === 'special'
            ? ['mission', 'convoy', 'fundraising'].includes(employee.statusToday ?? '')
            : (employee.statusToday ?? 'not_recorded') === todayStatus);
        return matchesQuery && matchesStatus && matchesToday;
      })
      .sort((a, b) => {
        if (sort === 'hierarchy') return hierarchyCompare(a, b);
        if (sort === 'name') return a.fullNameAr.localeCompare(b.fullNameAr, 'ar');
        if (sort === 'code') return a.employeeCode.localeCompare(b.employeeCode);
        return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
      });
  }, [all, search, sort, status, todayStatus]);

  const active = all.filter((employee) => employee.status === 'active' || employee.status === 'invited').length;
  const onboarding = all.filter((employee) => employee.status === 'onboarding').length;
  const inactive = all.filter((employee) => ['suspended', 'terminated', 'archived'].includes(employee.status)).length;

  const todayMetrics = useMemo(() => {
    let present = 0;
    let field = 0;
    let late = 0;
    let absent = 0;
    let onLeave = 0;
    for (const emp of all) {
      if (['suspended', 'terminated', 'archived'].includes(emp.status)) continue;
      const st = emp.statusToday;
      if (st === 'present') present++;
      else if (st === 'mission' || st === 'convoy' || st === 'fundraising') field++;
      else if (st === 'late') late++;
      else if (st === 'absent') absent++;
      else if (st === 'on_leave') onLeave++;
    }
    return { present, field, late, absent, onLeave };
  }, [all]);

  /* إعادة الصفحة للأولى عند تغيّر البحث أو التصفية أو الترتيب */
  useEffect(() => {
    setPage(1);
  }, [search, status, todayStatus, sort, pageSize]);

  const totalPages = Math.ceil(filtered.length / pageSize);
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize);

  const exportColumns: ExportColumn<(typeof filtered)[number]>[] = [
    { key: 'code', header: 'كود الموظف', get: (e) => (isPhoneLikeCode(e.employeeCode, e.phoneE164) ? '' : e.employeeCode) },
    { key: 'name', header: 'الاسم', get: (e) => e.fullNameAr },
    { key: 'dept', header: 'الإدارة', get: (e) => e.department ?? '' },
    { key: 'title', header: 'المسمى الوظيفي', get: (e) => e.jobTitle ?? '' },
    {
      key: 'statusToday',
      header: 'حالة اليوم',
      get: (e) => {
        const label = e.statusTodayLabel ?? (e.statusToday === 'not_recorded' ? 'لم يسجل بعد' : e.statusToday ?? 'لم يسجل بعد');
        return e.activityTitle ? `${label} (📍 ${e.activityTitle})` : label;
      },
    },
    { key: 'phone', header: 'الهاتف', get: (e) => e.phoneE164 ?? '' },
    { key: 'status', header: 'الحالة', get: (e) => e.status },
    { key: 'created', header: 'تاريخ الإضافة', get: (e) => dateFormatter.format(new Date(e.createdAt)) },
  ];

  const handleCsvExport = () => {
    downloadCsv(`employees-${cairoTodayIso()}.csv`, toCsv(exportColumns, filtered));
  };

  const handlePdfExport = () => {
    printReport(
      [
        {
          title: 'دليل الموظفين',
          subtitle: `${filtered.length} موظف`,
          table: {
            headers: exportColumns.map((c) => c.header),
            rows: filtered.map((e) => exportColumns.map((c) => String(c.get(e) ?? ''))),
          },
        },
      ],
      'دليل الموظفين — أحلى شباب',
    );
  };

  const columns: DataTableColumn<(typeof filtered)[number]>[] = useMemo(
    () => [
      {
        key: 'fullNameAr',
        header: 'الموظف',
        render: (emp) => {
          const penaltyInfo = pendingMap.get(emp.id);
          return (
            <div className="flex items-center gap-2.5">
              <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} announceName={false} size="sm" />
              <div className="min-w-0">
                <div className="flex items-center gap-1.5 flex-wrap">
                  <Link
                    to={`${hrPrefix}/employees/${emp.id}`}
                    className="block truncate font-black text-sm text-[var(--text-primary)] hover:text-[var(--brand-primary)] transition-colors"
                  >
                    {emp.fullNameAr}
                  </Link>
                  {penaltyInfo && (
                    <Link
                      to={`/admin/finance?tab=instant-penalties&employee=${emp.id}`}
                      className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[10px] font-bold border transition-colors shrink-0 ${
                        penaltyInfo.isSuspended
                          ? 'bg-red-100 text-red-800 border-red-300 dark:bg-red-950/60 dark:text-red-300 dark:border-red-800 animate-pulse'
                          : penaltyInfo.totalAmount >= 500
                            ? 'bg-amber-100 text-amber-800 border-amber-300 dark:bg-amber-950/60 dark:text-amber-300 dark:border-amber-800'
                            : 'bg-orange-100 text-orange-800 border-orange-300 dark:bg-orange-950/60 dark:text-orange-300 dark:border-orange-800'
                      }`}
                      title="اضغط للانتقال السريع لصفحة سداد الغرامة"
                    >
                      {penaltyInfo.isSuspended ? <>🔒 معلّق ({penaltyInfo.totalAmount} ج.م)</> : <>⚠️ مطالب بـ {penaltyInfo.totalAmount} ج.م</>}
                    </Link>
                  )}
                </div>
              </div>
            </div>
          );
        },
      },
      {
        key: 'statusToday',
        header: 'حالة اليوم',
        render: (emp) => {
          const st = emp.statusToday;
          const label = emp.statusTodayLabel ?? (st === 'not_recorded' ? 'لم يسجل بعد' : st ?? 'لم يسجل بعد');
          const isSpecial = st === 'present' || st === 'mission' || st === 'convoy' || st === 'fundraising';
          const badgeColor =
            st === 'present'
              ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30'
              : st === 'convoy'
              ? 'bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/30'
              : st === 'fundraising'
              ? 'bg-teal-500/10 text-teal-700 dark:text-teal-300 border-teal-500/30'
              : st === 'mission'
              ? 'bg-blue-500/10 text-blue-700 dark:text-blue-300 border-blue-500/30'
              : st === 'on_leave'
              ? 'bg-sky-500/10 text-sky-700 dark:text-sky-300 border-sky-500/30'
              : st === 'late'
              ? 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30'
              : st === 'absent'
              ? 'bg-rose-500/10 text-rose-700 dark:text-rose-300 border-rose-500/30'
              : 'bg-gray-500/10 text-gray-600 dark:text-gray-400 border-gray-500/20';

          return (
            <div className="flex flex-col gap-0.5 items-start justify-center">
              <span className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-bold border shrink-0 ${badgeColor}`}>
                <span className="relative flex size-1.5">
                  {isSpecial && <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-current opacity-75" />}
                  <span className="relative inline-flex size-1.5 rounded-full bg-current" />
                </span>
                <span>{label}</span>
              </span>
              {emp.activityTitle ? (
                <span className="text-[10px] text-[var(--text-muted)] font-medium max-w-[150px] truncate flex items-center gap-1 mt-0.5" title={emp.activityTitle}>
                  <span className="shrink-0 opacity-70 text-[10px]">📍</span>
                  <span className="truncate">{emp.activityTitle}</span>
                </span>
              ) : null}
            </div>
          );
        },
      },
      {
        key: 'department',
        header: 'الإدارة',
        render: (emp) => {
          if (!emp.department) return <span className="text-[var(--text-disabled)]">—</span>;
          const parts = emp.department.split(' / ').map((p) => p.trim()).filter(Boolean);
          if (parts.length === 0) return <span className="text-[var(--text-disabled)]">—</span>;
          const primaryDept = parts[0];
          const hasMore = parts.length > 1;

          return (
            <div className="flex items-center gap-1.5 flex-nowrap">
              <span
                className="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-semibold bg-blue-500/10 text-blue-700 dark:text-blue-300 border border-blue-500/20 max-w-[150px] truncate"
                title={emp.department}
              >
                {primaryDept}
              </span>
              {hasMore && (
                <span
                  className="inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-indigo-500/10 text-indigo-700 dark:text-indigo-300 border border-indigo-500/20 cursor-help shrink-0"
                  title={parts.join(' • ')}
                >
                  +{parts.length - 1} أخرى
                </span>
              )}
            </div>
          );
        },
      },
      {
        key: 'jobTitle',
        header: 'المسمى الوظيفي',
        render: (emp) => (
          <span className="text-xs text-[var(--text-secondary)] font-medium truncate max-w-[140px] block" title={emp.jobTitle ?? undefined}>
            {emp.jobTitle ?? '—'}
          </span>
        ),
      },
      {
        key: 'phoneE164',
        header: 'الهاتف',
        render: (emp) => (
          emp.phoneE164 ? (
            <span className="text-xs font-mono font-medium text-[var(--text-secondary)]">
              {renderSafeIntlPhoneText(emp.phoneE164)}
            </span>
          ) : (
            <span className="text-[var(--text-disabled)]">—</span>
          )
        ),
      },
      {
        key: 'actions',
        header: '',
        render: (emp) => (
          <Link to={`${hrPrefix}/employees/${emp.id}`} className="btn-secondary !px-3 !py-1 text-xs font-bold whitespace-nowrap inline-flex items-center">
            فتح الملف
          </Link>
        ),
      },
    ],
    [pendingMap, hrPrefix],
  );

  const isDirty = Boolean(search || status !== 'all' || todayStatus !== 'all' || sort !== 'hierarchy');
  const handleClearFilters = () => {
    setSearch('');
    setStatus('all');
    setTodayStatus('all');
    setSort('hierarchy');
  };

  return (
    <div className="space-y-3.5">
      <PageHeader
        eyebrow="إدارة الأفراد"
        title={tab === 'org-chart' ? 'الموظفون والهيكل التنظيمي' : 'دليل الموظفين'}
        description={tab === 'org-chart' ? 'شجرة هرمية كاملة: اضغط على أي موظف لفتح ملفه الشامل.' : 'ابحث في ملفات الموظفين وافتح الملف الشخصي لأي منهم.'}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={handleCsvExport} disabled={filtered.length === 0} title="تصدير Excel">
              <FileSpreadsheet className="size-3.5" aria-hidden="true" />
              <span>Excel</span>
            </button>
            <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs font-medium" onClick={handlePdfExport} disabled={filtered.length === 0} title="طباعة PDF">
              <Printer className="size-3.5 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
              <span>تصدير PDF</span>
            </button>
            <Link
              to={`${hrPrefix}/passwords`}
              className="btn-secondary !py-1.5 !px-3 text-xs"
              title="إدارة كلمات المرور والحسابات"
            >
              <KeyRound className="size-3.5 text-[var(--brand-primary)]" aria-hidden="true" />
              كلمات المرور
            </Link>
            {canCreate && (
              <Link to={`${hrPrefix}/employees/new`} className="btn-primary !py-1.5 !px-3.5 text-xs font-bold">
                <Plus className="size-3.5" aria-hidden="true" />
                إنشاء موظف
              </Link>
            )}
          </div>
        }
      />

      {/* تبويبات: دليل الموظفين / الهيكل التنظيمي — صفحة موحّدة واحدة */}
      <nav className="flex gap-1 rounded-xl bg-[var(--surface-muted)] p-1 max-w-fit" role="tablist" aria-label="تصفح الموظفين">
        <button
          role="tab"
          aria-selected={tab === 'directory'}
          onClick={() => setTab('directory')}
          className={`flex items-center gap-2 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-colors ${tab === 'directory' ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}`}
        >
          <UsersRound className="size-3.5" aria-hidden="true" />
          دليل الموظفين
          <span
            className={`rounded-full px-2 py-0.5 text-[11px] font-black ${tab === 'directory' ? 'bg-[var(--primary)] text-white' : 'bg-[var(--surface-muted)] text-[var(--text-secondary)]'}`}
          >
            {all.length}
          </span>
        </button>
        {canViewOrgChart ? (
          <button
            role="tab"
            aria-selected={tab === 'org-chart'}
            onClick={() => setTab('org-chart')}
            className={`flex items-center gap-2 rounded-lg px-3.5 py-1.5 text-xs font-bold transition-colors ${tab === 'org-chart' ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}`}
          >
            <Network className="size-3.5" aria-hidden="true" />
            الهيكل التنظيمي
          </button>
        ) : null}
      </nav>

      {tab === 'org-chart' ? (
        <OrgChartPage embedded />
      ) : (
        <>
          <section className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard label="إجمالي الملفات" value={all.length} icon={UsersRound} hint="جميع الحالات داخل نطاقك" onClick={() => setStatus('all')} compact showAction={false} />
            <MetricCard
              label="موظفون نشطون"
              value={active}
              icon={UserRound}
              hint={all.length ? `${Math.round((active / all.length) * 100)}% من الملفات` : 'لا توجد بيانات'}
              onClick={() => setStatus('active')}
              compact
              showAction={false}
            />
            <MetricCard label="تهيئة ودعوات" value={onboarding} icon={RefreshCw} hint="لم تكتمل رحلة التفعيل" onClick={() => setStatus('onboarding')} compact showAction={false} />
            <MetricCard
              label="موقوف أو منتهي"
              value={inactive}
              icon={ArrowUpDown}
              hint="سجلات محفوظة للتاريخ والتدقيق"
              onClick={() => setStatus('inactive')}
              compact
              showAction={false}
            />
          </section>

          {pendingPenalties.length > 0 && (
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-2 p-2.5 sm:px-3 bg-amber-50 dark:bg-amber-950/40 border border-amber-300 dark:border-amber-800/60 rounded-xl">
              <div className="flex items-center gap-2">
                <span className="text-lg shrink-0" aria-hidden="true">
                  ⚠️
                </span>
                <div className="min-w-0">
                  <h4 className="text-xs sm:text-sm font-bold text-amber-900 dark:text-amber-200">
                    يوجد {pendingPenalties.length} موظف مطالبين بغرامات فورية للتأخير (إجمالي {totalPendingAmount.toLocaleString('ar-EG-u-nu-latn')} ج.م)
                  </h4>
                  <p className="text-[11px] text-amber-700 dark:text-amber-400">الموظفون موضح بجوار أسمائهم علامة حمراء/برتقالية بالقيمة المستحقة.</p>
                </div>
              </div>
              <Link to="/admin/finance?tab=instant-penalties" className="btn-primary !text-xs !py-1.5 !px-3 font-bold shrink-0">
                تحصيل الجزاءات
              </Link>
            </div>
          )}

          {/* شريط التحكم والتصفية المدمج الفاخر */}
          <section className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-2.5 sm:p-3 shadow-xs space-y-2.5" aria-label="أدوات التصفية والبحث">
            {/* السطر الأول: فلاتر حالة اليوم اللحظية */}
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--border)]/60 pb-2">
              <div className="flex items-center gap-1.5 overflow-x-auto text-xs py-0.5">
                <span className="font-bold text-[var(--text-muted)] shrink-0 ml-1 text-[11px]">حالة اليوم:</span>
                <button
                  type="button"
                  onClick={() => setTodayStatus('all')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 ${
                    todayStatus === 'all'
                      ? 'bg-[var(--brand-primary)] text-white shadow-xs'
                      : 'bg-[var(--surface-muted)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                  }`}
                >
                  الكل ({all.length})
                </button>
                <button
                  type="button"
                  onClick={() => setTodayStatus(todayStatus === 'present' ? 'all' : 'present')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 flex items-center gap-1.5 ${
                    todayStatus === 'present'
                      ? 'bg-emerald-600 text-white shadow-xs'
                      : 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 hover:bg-emerald-500/20 border border-emerald-500/20'
                  }`}
                >
                  <span className="size-1.5 rounded-full bg-emerald-500" />
                  حاضر ({todayMetrics.present})
                </button>
                <button
                  type="button"
                  onClick={() => setTodayStatus(todayStatus === 'special' ? 'all' : 'special')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 flex items-center gap-1.5 ${
                    todayStatus === 'special'
                      ? 'bg-blue-600 text-white shadow-xs'
                      : 'bg-blue-500/10 text-blue-700 dark:text-blue-300 hover:bg-blue-500/20 border border-blue-500/20'
                  }`}
                >
                  <span className="size-1.5 rounded-full bg-blue-500" />
                  ميداني / مأموريات ({todayMetrics.field})
                </button>
                <button
                  type="button"
                  onClick={() => setTodayStatus(todayStatus === 'late' ? 'all' : 'late')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 flex items-center gap-1.5 ${
                    todayStatus === 'late'
                      ? 'bg-amber-600 text-white shadow-xs'
                      : 'bg-amber-500/10 text-amber-700 dark:text-amber-300 hover:bg-amber-500/20 border border-amber-500/20'
                  }`}
                >
                  <span className="size-1.5 rounded-full bg-amber-500" />
                  متأخر ({todayMetrics.late})
                </button>
                <button
                  type="button"
                  onClick={() => setTodayStatus(todayStatus === 'absent' ? 'all' : 'absent')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 flex items-center gap-1.5 ${
                    todayStatus === 'absent'
                      ? 'bg-rose-600 text-white shadow-xs'
                      : 'bg-rose-500/10 text-rose-700 dark:text-rose-300 hover:bg-rose-500/20 border border-rose-500/20'
                  }`}
                >
                  <span className="size-1.5 rounded-full bg-rose-500" />
                  غائب ({todayMetrics.absent})
                </button>
                <button
                  type="button"
                  onClick={() => setTodayStatus(todayStatus === 'on_leave' ? 'all' : 'on_leave')}
                  className={`px-2.5 py-1 rounded-lg font-bold text-xs transition-all shrink-0 flex items-center gap-1.5 ${
                    todayStatus === 'on_leave'
                      ? 'bg-sky-600 text-white shadow-xs'
                      : 'bg-sky-500/10 text-sky-700 dark:text-sky-300 hover:bg-sky-500/20 border border-sky-500/20'
                  }`}
                >
                  <span className="size-1.5 rounded-full bg-sky-500" />
                  إجازة ({todayMetrics.onLeave})
                </button>
              </div>

              {isDirty && (
                <button
                  type="button"
                  onClick={handleClearFilters}
                  className="text-xs font-bold text-rose-600 dark:text-rose-400 hover:underline flex items-center gap-1 shrink-0 py-0.5"
                >
                  <X className="size-3.5" />
                  مسح التصفية
                </button>
              )}
            </div>

            {/* السطر الثاني: البحث، الحالات، الترتيب، حجم الصفحة والتحديث في سطر أفقي سلس */}
            <div className="flex flex-wrap items-center gap-2">
              {/* حقل البحث الذكي مع الاقتراحات */}
              <div className="relative flex-1 min-w-[200px] max-w-sm">
                <Search className="absolute inset-inline-start-3 top-1/2 -translate-y-1/2 size-4 text-[var(--text-muted)] pointer-events-none" />
                <input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="بحث بالاسم أو الكود أو الهاتف"
                  className="w-full h-9 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-primary)] text-xs font-bold ps-9 pe-3 focus:bg-[var(--surface)] focus:border-[var(--brand-primary)] outline-none transition-colors"
                  type="search"
                  onFocus={() => setSearchFocused(true)}
                  onBlur={() => setSearchFocused(false)}
                />
                <EmployeeSearchSuggestions query={search} employees={all} open={searchFocused} onClose={() => setSearchFocused(false)} />
              </div>

              {/* قائمة الحالات التعاقدية */}
              <select
                value={status}
                onChange={(e) => setStatus(e.target.value)}
                className="h-9 px-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-primary)] text-xs font-bold outline-none cursor-pointer hover:border-[var(--border-strong)] transition-colors shrink-0"
                aria-label="تصفية حسب الحالة"
              >
                <option value="all">كل الحالات التعاقدية</option>
                <option value="active">نشط</option>
                <option value="onboarding">قيد التهيئة</option>
                <option value="suspended">موقوف</option>
                <option value="notice_period">فترة إخطار</option>
                <option value="terminated">منتهي</option>
                <option value="archived">مؤرشف</option>
                <option value="inactive">موقوف أو منتهي (الكل)</option>
              </select>

              {/* قائمة الترتيب */}
              <select
                value={sort}
                onChange={(e) => setSort(e.target.value as SortMode)}
                className="h-9 px-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-primary)] text-xs font-bold outline-none cursor-pointer hover:border-[var(--border-strong)] transition-colors shrink-0"
                aria-label="ترتيب الموظفين"
              >
                <option value="hierarchy">الهيكل الإداري</option>
                <option value="newest">الأحدث إضافة</option>
                <option value="name">الاسم أبجديًا</option>
                <option value="code">كود الموظف</option>
              </select>

              {/* زر التحديث */}
              <button
                onClick={() => void employees.refetch()}
                className="btn-secondary !h-9 !py-1 !px-3 !text-xs font-bold shrink-0 flex items-center gap-1.5"
                disabled={employees.isFetching}
                aria-busy={employees.isFetching}
                title="تحديث البيانات"
              >
                <RefreshCw className={`size-3.5 ${employees.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
                تحديث
              </button>

              {/* إحصائية النتائج + محدد عدد العناصر دفعة واحدة */}
              <div className="ms-auto flex items-center gap-2 text-xs text-[var(--text-secondary)] font-bold shrink-0">
                <span className="hidden md:inline bg-[var(--surface-muted)] px-2.5 py-1 rounded-lg border border-[var(--border)]">
                  عرض {filtered.length} من {all.length}
                </span>

                {/* مفتاح عرض الكل / حجم الصفحة */}
                <div className="flex items-center gap-1 bg-[var(--surface-muted)] p-0.5 rounded-lg border border-[var(--border)]">
                  <span className="text-[11px] text-[var(--text-muted)] px-1">عرض:</span>
                  {[25, 50, 100, 500].map((size) => (
                    <button
                      key={size}
                      type="button"
                      onClick={() => {
                        setPageSize(size);
                        setPage(1);
                      }}
                      className={`px-2 py-0.5 rounded-md text-[11px] font-bold transition-colors ${
                        pageSize === size
                          ? 'bg-[var(--brand-primary)] text-white shadow-xs'
                          : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                      }`}
                      title={size === 500 ? 'عرض جميع الموظفين في صفحة واحدة' : `عرض ${size} موظف`}
                    >
                      {size === 500 ? 'الكل' : size}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </section>

          {employees.isError ? (
            <ErrorState description={safeErrorMessage(employees.error)} onRetry={() => void employees.refetch()} />
          ) : employees.isLoading ? (
            <ListSkeleton rows={6} label="جارٍ تحميل الموظفين…" />
          ) : all.length === 0 ? (
            <EmptyState
              title="لا يوجد موظفون بعد"
              description="لم تتم إضافة أي ملف موظف داخل نطاقك حتى الآن."
              action={
                canCreate ? (
                  <Link to={`${hrPrefix}/employees/new`} className="btn-primary">
                    <Plus className="size-4" aria-hidden="true" />
                    إنشاء موظف
                  </Link>
                ) : undefined
              }
            />
          ) : (
            <>
              <DataTable
                columns={columns}
                data={paged}
                rowKey={(emp) => emp.id}
                emptyTitle="لا توجد نتائج مطابقة"
                emptyDescription="جرّب تعديل البحث أو مسح عوامل التصفية لعرض المزيد من الملفات."
                ariaLabel="جدول الموظفين"
                minWidth="860px"
              />
              {totalPages > 1 ? (
                <Pagination currentPage={page} totalPages={totalPages} totalItems={filtered.length} pageSize={pageSize} onPageChange={setPage} />
              ) : (
                <div className="flex items-center justify-between text-xs text-[var(--text-muted)] px-1 pt-1 font-medium">
                  <span>تم عرض جميع النتائج ({filtered.length} موظف) دفعة واحدة</span>
                  {filtered.length > 25 && pageSize < 500 && (
                    <button
                      type="button"
                      onClick={() => setPageSize(500)}
                      className="text-[var(--brand-primary)] hover:underline font-bold"
                    >
                      عرض الكل في صفحة واحدة
                    </button>
                  )}
                </div>
              )}
            </>
          )}
        </>
      )}
    </div>
  );
}
