import { ArrowUpDown, FileSpreadsheet, Plus, Printer, RefreshCw, UserRound, UsersRound } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { MetricCard } from '../../ui/MetricCard';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { Pagination } from '../../ui/Pagination';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useEmployees } from './useEmployees';
import { EmployeeSearchSuggestions } from './EmployeeSearchSuggestions';
import { renderSafeIntlPhoneText } from '../../ui/phoneDisplay';

type SortMode = 'newest' | 'name' | 'code';

export function EmployeesPage() {
  const auth = useAuth();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [sort, setSort] = useState<SortMode>('newest');
  const [page, setPage] = useState(1);
  const [searchFocused, setSearchFocused] = useState(false);
  const pageSize = 25;
  const employees = useEmployees(search, status);
  const canCreate = hasPermission(auth.access, 'people.employee.create');
  const all = useMemo(() => employees.data ?? [], [employees.data]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return all
      .filter((employee) => {
        const matchesQuery =
          !query ||
          employee.fullNameAr.toLowerCase().includes(query) ||
          employee.employeeCode.toLowerCase().includes(query) ||
          employee.phoneE164?.includes(query);
        return matchesQuery && (status === 'all' || employee.status === status);
      })
      .sort((a, b) => {
        if (sort === 'name') return a.fullNameAr.localeCompare(b.fullNameAr, 'ar');
        if (sort === 'code') return a.employeeCode.localeCompare(b.employeeCode);
        return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
      });
  }, [all, search, sort, status]);

  const active = all.filter((employee) => employee.status === 'active' || employee.status === 'invited').length;
  const onboarding = all.filter((employee) => employee.status === 'onboarding').length;
  const inactive = all.filter((employee) => ['suspended', 'terminated', 'archived'].includes(employee.status)).length;

  /* إعادة الصفحة للأولى عند تغيّر البحث أو التصفية أو الترتيب */
  useEffect(() => {
    setPage(1);
  }, [search, status, sort]);

  const totalPages = Math.ceil(filtered.length / pageSize);
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize);

  const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

  const exportColumns: ExportColumn<(typeof filtered)[number]>[] = [
    { key: 'code', header: 'كود الموظف', get: (e) => e.employeeCode },
    { key: 'name', header: 'الاسم', get: (e) => e.fullNameAr },
    { key: 'dept', header: 'الإدارة', get: (e) => e.department ?? '' },
    { key: 'title', header: 'المسمى الوظيفي', get: (e) => e.jobTitle ?? '' },
    { key: 'phone', header: 'الهاتف', get: (e) => e.phoneE164 ?? '' },
    { key: 'status', header: 'الحالة', get: (e) => e.status },
    { key: 'created', header: 'تاريخ الإضافة', get: (e) => dateFormatter.format(new Date(e.createdAt)) },
  ];

  const handleCsvExport = () => {
    downloadCsv(`employees-${new Date().toISOString().slice(0, 10)}.csv`, toCsv(exportColumns, filtered));
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
        render: (emp) => (
          <div className="flex items-center gap-3">
            <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} announceName={false} />
            <div className="min-w-0">
              <Link to={`/hr/employees/${emp.id}`} className="block truncate font-black hover:text-[var(--brand-primary)]">
                {emp.fullNameAr}
              </Link>
            </div>
          </div>
        ),
      },
      {
        key: 'employeeCode',
        header: 'الكود',
        render: (emp) => <span className="font-mono text-xs">{emp.employeeCode}</span>,
      },
      {
        key: 'department',
        header: 'الإدارة',
        render: (emp) => <span className="text-sm">{emp.department ?? '—'}</span>,
      },
      {
        key: 'jobTitle',
        header: 'المسمى الوظيفي',
        render: (emp) => <span className="text-sm">{emp.jobTitle ?? '—'}</span>,
      },
      {
        key: 'phoneE164',
        header: 'الهاتف',
        render: (emp) => (emp.phoneE164 ? renderSafeIntlPhoneText(emp.phoneE164) : <span>—</span>),
      },
      {
        key: 'status',
        header: 'الحالة',
        render: (emp) => <StatusBadge status={emp.status} />,
      },
      {
        key: 'createdAt',
        header: 'تاريخ الإضافة',
        render: (emp) => (
          <span className="text-[var(--text-muted)]">{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' }).format(new Date(emp.createdAt))}</span>
        ),
      },
      {
        key: 'actions',
        header: '',
        render: (emp) => (
          <Link to={`/hr/employees/${emp.id}`} className="btn-secondary !px-3 !py-2 text-xs">
            فتح الملف
          </Link>
        ),
      },
    ],
    [],
  );

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="إدارة الأفراد"
        title="دليل الموظفين"
        description="ابحث في ملفات الموظفين وافتح الملف الشخصي لأي منهم."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={filtered.length === 0} title="طباعة PDF">
              <Printer className="size-4" aria-hidden="true" />
              PDF
            </button>
            <button type="button" className="btn-secondary" onClick={handleCsvExport} disabled={filtered.length === 0} title="تصدير Excel">
              <FileSpreadsheet className="size-4" aria-hidden="true" />
              تصدير
            </button>
            {canCreate && (
              <Link to="/hr/employees/new" className="btn-primary">
                <Plus className="size-4" aria-hidden="true" />
                إنشاء موظف
              </Link>
            )}
          </div>
        }
      />

      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجمالي الملفات" value={all.length} icon={UsersRound} hint="جميع الحالات داخل نطاقك" />
        <MetricCard
          label="موظفون نشطون"
          value={active}
          icon={UserRound}
          hint={all.length ? `${Math.round((active / all.length) * 100)}% من الملفات` : 'لا توجد بيانات'}
        />
        <MetricCard label="تهيئة ودعوات" value={onboarding} icon={RefreshCw} hint="لم تكتمل رحلة التفعيل" />
        <MetricCard label="موقوف أو منتهي" value={inactive} icon={ArrowUpDown} hint="سجلات محفوظة للتاريخ والتدقيق" />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم أو الكود أو الهاتف"
        resultText={`عرض ${filtered.length} من ${all.length} ملف`}
        isDirty={Boolean(search || status !== 'all' || sort !== 'newest')}
        onClear={() => {
          setSearch('');
          setStatus('all');
          setSort('newest');
        }}
        searchAdornment={<EmployeeSearchSuggestions query={search} employees={all} open={searchFocused} onClose={() => setSearchFocused(false)} />}
        onSearchFocusChange={setSearchFocused}
      >
        <select className="input" value={status} onChange={(event) => setStatus(event.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          <option value="active">نشط</option>
          <option value="onboarding">قيد التهيئة</option>
          <option value="suspended">موقوف</option>
          <option value="notice_period">فترة إخطار</option>
          <option value="terminated">منتهي</option>
          <option value="archived">مؤرشف</option>
        </select>
        <select className="input" value={sort} onChange={(event) => setSort(event.target.value as SortMode)} aria-label="ترتيب الموظفين">
          <option value="newest">الأحدث إضافة</option>
          <option value="name">الاسم أبجديًا</option>
          <option value="code">كود الموظف</option>
        </select>
        <button onClick={() => void employees.refetch()} className="btn-secondary" disabled={employees.isFetching} aria-busy={employees.isFetching}>
          <RefreshCw className={`size-4 ${employees.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
          تحديث
        </button>
      </FilterBar>

      {employees.isError ? (
        <ErrorState description={safeErrorMessage(employees.error)} onRetry={() => void employees.refetch()} />
      ) : employees.isLoading ? (
        <ListSkeleton rows={5} label="جارٍ تحميل الموظفين…" />
      ) : all.length === 0 ? (
        <EmptyState
          title="لا يوجد موظفون بعد"
          description="لم تتم إضافة أي ملف موظف داخل نطاقك حتى الآن."
          action={
            canCreate ? (
              <Link to="/hr/employees/new" className="btn-primary">
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
            minWidth="1020px"
          />
          {totalPages > 1 && <Pagination currentPage={page} totalPages={totalPages} totalItems={filtered.length} pageSize={pageSize} onPageChange={setPage} />}
        </>
      )}
    </div>
  );
}
