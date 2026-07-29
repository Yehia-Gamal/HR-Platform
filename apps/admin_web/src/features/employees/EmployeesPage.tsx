import { ArrowUpDown, Plus, RefreshCw, UserRound, UsersRound } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { MetricCard } from '../../ui/MetricCard';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { safeErrorMessage } from '../../core/errorMapper';
import { useEmployees } from './useEmployees';
import { safeErrorMessage } from '../../core/errorMapper';

type SortMode = 'newest' | 'name' | 'code';

export function EmployeesPage() {
  const auth = useAuth();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [sort, setSort] = useState<SortMode>('newest');
  const employees = useEmployees(search, status);
  const canCreate = hasPermission(auth.access!, 'people.employee.create');
  const all = employees.data ?? [];

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return all.filter((employee) => {
      const matchesQuery = !query
        || employee.fullNameAr.toLowerCase().includes(query)
        || employee.employeeCode.toLowerCase().includes(query)
        || employee.phoneE164?.includes(query);
      return matchesQuery && (status === 'all' || employee.status === status);
    }).sort((a, b) => {
      if (sort === 'name') return a.fullNameAr.localeCompare(b.fullNameAr, 'ar');
      if (sort === 'code') return a.employeeCode.localeCompare(b.employeeCode);
      return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
    });
  }, [all, search, sort, status]);

  const active = all.filter((employee) => employee.status === 'active' || employee.status === 'invited').length;
  const onboarding = all.filter((employee) => employee.status === 'onboarding').length;
  const inactive = all.filter((employee) => ['suspended', 'terminated', 'archived'].includes(employee.status)).length;

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="إدارة الأفراد"
        title="دليل الموظفين"
        description="ابحث في ملفات الموظفين وافتح ملف 360°، مع احترام نطاق الوصول الذي يطبقه الخادم."
        actions={canCreate ? <Link to="/hr/employees/new" className="btn-primary"><Plus className="size-4" aria-hidden="true" />إنشاء موظف</Link> : undefined}
      />

      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجمالي الملفات" value={all.length} icon={UsersRound} hint="جميع الحالات داخل نطاقك" />
        <MetricCard label="موظفون نشطون" value={active} icon={UserRound} hint={all.length ? `${Math.round((active / all.length) * 100)}% من الملفات` : 'لا توجد بيانات'} />
        <MetricCard label="تهيئة ودعوات" value={onboarding} icon={RefreshCw} hint="لم تكتمل رحلة التفعيل" />
        <MetricCard label="موقوف أو منتهي" value={inactive} icon={ArrowUpDown} hint="سجلات محفوظة للتاريخ والتدقيق" />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم أو الكود أو الهاتف"
        resultText={`عرض ${filtered.length} من ${all.length} ملف`}
        isDirty={Boolean(search || status !== 'all' || sort !== 'newest')}
        onClear={() => { setSearch(''); setStatus('all'); setSort('newest'); }}
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
            <RefreshCw className={`size-4 ${employees.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />تحديث
          </button>
      </FilterBar>

      {employees.isError ? (
        <ErrorState
          description={safeErrorMessage(employees.error)}
          onRetry={() => void employees.refetch()}
        />
      ) : employees.isLoading ? (
        <ListSkeleton rows={5} label="جارٍ تحميل الموظفين…" />
      ) : all.length === 0 ? (
        <EmptyState
          title="لا يوجد موظفون بعد"
          description="لم تتم إضافة أي ملف موظف داخل نطاقك حتى الآن."
          action={canCreate ? <Link to="/hr/employees/new" className="btn-primary"><Plus className="size-4" aria-hidden="true" />إنشاء موظف</Link> : undefined}
        />
      ) : filtered.length === 0 ? (
        <EmptyState
          title="لا توجد نتائج مطابقة"
          description="جرّب تعديل البحث أو مسح عوامل التصفية لعرض المزيد من الملفات."
        />
      ) : (
        <>
          <section className="card hidden overflow-hidden md:block" aria-busy={employees.isFetching}>
            <div className="overflow-x-auto">
              <table className="data-table w-full min-w-[1020px] text-start text-sm">
                <thead className="bg-[var(--surface-muted)] text-xs text-[var(--text-muted)]">
                  <tr><th scope="col" className="px-4 py-3.5">الموظف</th><th scope="col" className="px-4 py-3.5">الكود</th><th scope="col" className="px-4 py-3.5">الإدارة</th><th scope="col" className="px-4 py-3.5">المسمى الوظيفي</th><th scope="col" className="px-4 py-3.5">الهاتف</th><th scope="col" className="px-4 py-3.5">الحالة</th><th scope="col" className="px-4 py-3.5">تاريخ الإضافة</th><th scope="col" className="px-4 py-3.5"><span className="sr-only">فتح</span></th></tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  {filtered.map((employee) => (
                    <tr key={employee.id}>
                      <td className="px-4 py-3.5"><div className="flex items-center gap-3"><UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} announceName={false} /><div className="min-w-0"><Link to={`/hr/employees/${employee.id}`} className="block truncate font-black hover:text-[var(--brand-primary)]">{employee.fullNameAr}</Link></div></div></td>
                      <td className="px-4 py-3.5 font-mono text-xs">{employee.employeeCode}</td>
                      <td className="px-4 py-3.5 text-sm">{employee.department ?? '—'}</td>
                      <td className="px-4 py-3.5 text-sm">{employee.jobTitle ?? '—'}</td>
                      <td className="px-4 py-3.5" dir="ltr">{employee.phoneE164 ?? '—'}</td>
                      <td className="px-4 py-3.5"><StatusBadge status={employee.status} /></td>
                      <td className="px-4 py-3.5 text-[var(--text-muted)]">{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' }).format(new Date(employee.createdAt))}</td>
                      <td className="px-4 py-3.5"><Link to={`/hr/employees/${employee.id}`} className="btn-secondary !px-3 !py-2 text-xs">فتح الملف</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="grid gap-3 md:hidden" aria-busy={employees.isFetching}>
            {filtered.map((employee) => (
              <Link key={employee.id} to={`/hr/employees/${employee.id}`} className="mobile-record-card card-interactive">
                <div className="flex items-start gap-3"><UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} announceName={false} /><div className="min-w-0 flex-1"><div className="flex items-start justify-between gap-2"><div><h2 className="font-black">{employee.fullNameAr}</h2><p className="mt-1 font-mono text-xs text-[var(--text-muted)]">{employee.employeeCode}</p></div><StatusBadge status={employee.status} /></div><div className="mt-3 flex flex-wrap gap-3 text-xs text-[var(--text-muted)]">{employee.department ? <span>{employee.department}</span> : null}{employee.jobTitle ? <span>{employee.jobTitle}</span> : null}<span dir="ltr">{employee.phoneE164 ?? 'بدون هاتف'}</span><span>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' }).format(new Date(employee.createdAt))}</span></div></div></div>
              </Link>
            ))}
          </section>
        </>
      )}
    </div>
  );
}
