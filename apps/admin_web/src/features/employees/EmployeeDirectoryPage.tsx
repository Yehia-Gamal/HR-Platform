import { Building2, CalendarDays, Circle, FileText, User, Users, Workflow } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEmployees } from './useEmployees';
import { useOrganizationLookups } from './useOrganizationLookups';
import { safeErrorMessage } from '../../core/errorMapper';

interface EmployeeDirectoryItem {
  id: string;
  employeeCode: string;
  fullNameAr: string;
  photoUrl: string | null;
  jobTitle: string | null;
  departmentName: string | null;
  branchName: string | null;
  departmentId: string | null;
  teamId: string | null;
  branchId: string | null;
  status: 'draft' | 'invited' | 'onboarding' | 'active' | 'suspended' | 'notice_period' | 'terminated' | 'archived' | 'probation_failed';
  subordinatesCount: number;
}

function getStatusConfig(status: EmployeeDirectoryItem['status']) {
  const configs: Record<EmployeeDirectoryItem['status'], { label: string; color: string; icon: typeof Circle }> = {
    active: { label: 'نشط', color: 'var(--success)', icon: Circle },
    suspended: { label: 'موقوف', color: 'var(--danger)', icon: Circle },
    onboarding: { label: 'أونبوردينغ', color: 'var(--info)', icon: Circle },
    draft: { label: 'مسودة', color: 'var(--text-muted)', icon: Circle },
    invited: { label: 'مُدعى', color: 'var(--warning)', icon: Circle },
    notice_period: { label: 'فترة إشعار', color: 'var(--warning)', icon: Circle },
    terminated: { label: 'منتهي', color: 'var(--danger)', icon: Circle },
    archived: { label: 'مؤرشف', color: 'var(--text-muted)', icon: Circle },
    probation_failed: { label: 'فشل تجريبي', color: 'var(--danger)', icon: Circle },
  };
  return configs[status] ?? { label: status, color: 'var(--text-muted)', icon: Circle };
}

function StatusIndicator({ status }: { status: EmployeeDirectoryItem['status'] }) {
  const config = getStatusConfig(status);
  const Icon = config.icon;
  return (
    <span className="inline-flex items-center gap-1.5" style={{ color: config.color }}>
      <Icon className="size-2" aria-hidden="true" />
      <span className="text-xs font-medium">{config.label}</span>
    </span>
  );
}

export function EmployeeDirectoryPage() {
  const query = useEmployees();
  const lookupsQuery = useOrganizationLookups();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [deptFilter, setDeptFilter] = useState<string>('all');
  const [selectedEmployee, setSelectedEmployee] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<'table' | 'cards'>('table');

  const departments = useMemo(() => lookupsQuery.data?.departments ?? [], [lookupsQuery.data]);

  const employees = useMemo(() => {
    if (!query.data) return [];
    const branches = lookupsQuery.data?.branches ?? [];
    return query.data.map((emp) => {
      const dept = departments.find((d) => d.id === emp.departmentId);
      const branch = branches.find((b) => b.id === emp.branchId);

      const subordinates = query.data?.filter((e) => e.id === emp.id).length ?? 0; // مؤقت - يحتاج RPC منفصل للمرؤوسين

      return {
        id: emp.id,
        employeeCode: emp.employeeCode ?? '—',
        fullNameAr: emp.fullNameAr,
        photoUrl: emp.photoUrl ?? null,
        jobTitle: emp.jobTitle ?? null,
        departmentName: emp.department ?? dept?.label ?? null,
        branchName: emp.branch ?? branch?.label ?? null,
        departmentId: emp.departmentId ?? null,
        teamId: emp.teamId ?? null,
        branchId: emp.branchId ?? null,
        status: emp.status,
        subordinatesCount: subordinates,
      } as EmployeeDirectoryItem;
    });
  }, [query.data, departments, lookupsQuery.data]);

  const filteredEmployees = useMemo(() => {
    return employees.filter((emp) => {
      const matchesSearch =
        !search ||
        emp.fullNameAr.toLowerCase().includes(search.toLowerCase()) ||
        emp.employeeCode.toLowerCase().includes(search.toLowerCase()) ||
        emp.departmentName?.toLowerCase().includes(search.toLowerCase()) ||
        emp.jobTitle?.toLowerCase().includes(search.toLowerCase()) ||
        emp.branchName?.toLowerCase().includes(search.toLowerCase());
      const matchesStatus = statusFilter === 'all' || emp.status === statusFilter;
      const matchesDept = deptFilter === 'all' || emp.departmentName === deptFilter;
      return matchesSearch && matchesStatus && matchesDept;
    });
  }, [employees, search, statusFilter, deptFilter]);

  const stats = useMemo(() => {
    return {
      total: employees.length,
      active: employees.filter((e) => e.status === 'active').length,
      suspended: employees.filter((e) => e.status === 'suspended').length,
      onboarding: employees.filter((e) => e.status === 'onboarding').length,
      managers: employees.filter((e) => e.subordinatesCount > 0).length,
    };
  }, [employees]);

  if (query.isError) {
    return <ErrorState title="تعذر تحميل دليل الموظفين" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) {
    return <SkeletonCard className="h-96" />;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="إدارة وسجل الموظفين"
        description="دليل شامل للموظفين: الهيكل الهرمي، الحالة، القسم، المسمى الوظيفي، المدير، المرؤوسون، البروفايل والتقارير — للاطلاع فقط."
        actions={
          <div className="flex items-center gap-2">
            <select className="input w-auto" value={viewMode} onChange={(e) => setViewMode(e.target.value as 'table' | 'cards')} aria-label="نمط العرض">
              <option value="table">جدول</option>
              <option value="cards">بطاقات</option>
            </select>
          </div>
        }
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5" aria-label="إحصائيات الدليل">
        <MetricCard label="إجمالي الموظفين" value={stats.total} icon={Users} />
        <MetricCard label="نشطون" value={stats.active} icon={User} />
        <MetricCard label="موقوفون" value={stats.suspended} icon={User} />
        <MetricCard label="أونبوردينغ" value={stats.onboarding} icon={CalendarDays} />
        <MetricCard label="مديرون" value={stats.managers} icon={Users} />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم، الكود، المسمى الوظيفي، القسم، الإدارة..."
        resultText={`عرض ${filteredEmployees.length} من ${employees.length} موظف`}
        isDirty={Boolean(search || statusFilter !== 'all' || deptFilter !== 'all')}
        onClear={() => {
          setSearch('');
          setStatusFilter('all');
          setDeptFilter('all');
        }}
      >
        <select className="input" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          <option value="active">نشط</option>
          <option value="suspended">موقوف</option>
          <option value="onboarding">أونبوردينغ</option>
          <option value="draft">مسودة</option>
          <option value="invited">مُدعى</option>
          <option value="notice_period">فترة إشعار</option>
          <option value="terminated">منتهي</option>
          <option value="archived">مؤرشف</option>
          <option value="probation_failed">فشل تجريبي</option>
        </select>
        <select className="input" value={deptFilter} onChange={(e) => setDeptFilter(e.target.value)} aria-label="تصفية حسب الإدارة">
          <option value="all">كل الإدارات</option>
          {departments.map((d) => (
            <option key={d.id} value={d.label}>
              {d.label}
            </option>
          ))}
        </select>
      </FilterBar>

      {filteredEmployees.length === 0 ? (
        <EmptyState title="لا توجد نتائج" description="لا يوجد موظفون يطابقون معايير البحث." />
      ) : viewMode === 'table' ? (
        <section className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1100px] text-start text-sm">
              <thead className="bg-[var(--surface-muted)]">
                <tr>
                  <th scope="col" className="p-3">
                    الموظف
                  </th>
                  <th scope="col" className="p-3 hidden md:table-cell">
                    الكود
                  </th>
                  <th scope="col" className="p-3 hidden lg:table-cell">
                    الإدارة
                  </th>
                  <th scope="col" className="p-3 hidden lg:table-cell">
                    القسم
                  </th>
                  <th scope="col" className="p-3 hidden lg:table-cell">
                    المسمى الوظيفي
                  </th>
                  <th scope="col" className="p-3">
                    الحالة
                  </th>
                  <th scope="col" className="p-3 hidden lg:table-cell">
                    المرؤوسون
                  </th>
                  <th scope="col" className="p-3">
                    الإجراءات
                  </th>
                </tr>
              </thead>
              <tbody>
                {filteredEmployees.map((emp) => (
                  <tr key={emp.id} className="border-t border-[var(--border)] hover:bg-[var(--surface-muted)]">
                    <td className="p-3">
                      <div className="flex items-center gap-3">
                        <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="sm" />
                        <div>
                          <p className="font-bold">{emp.fullNameAr}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-3 hidden md:table-cell text-[var(--text-muted)]">{emp.employeeCode}</td>
                    <td className="p-3 hidden lg:table-cell">{emp.branchName ?? '—'}</td>
                    <td className="p-3 hidden lg:table-cell">{emp.departmentName ?? '—'}</td>
                    <td className="p-3 hidden lg:table-cell text-[var(--text-muted)]">{emp.jobTitle ?? '—'}</td>
                    <td className="p-3">
                      <StatusIndicator status={emp.status} />
                    </td>
                    <td className="p-3 hidden lg:table-cell">
                      {emp.subordinatesCount > 0 ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]">
                          <Users className="size-3" aria-hidden="true" />
                          {emp.subordinatesCount}
                        </span>
                      ) : (
                        <span className="text-[var(--text-muted)]">—</span>
                      )}
                    </td>
                    <td className="p-3">
                      <div className="flex items-center gap-1">
                        <button
                          type="button"
                          className="icon-button btn-ghost btn-sm"
                          onClick={() => setSelectedEmployee(emp.id)}
                          aria-label={`عرض تفاصيل ${emp.fullNameAr}`}
                        >
                          <FileText className="size-4" aria-hidden="true" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filteredEmployees.map((emp) => (
            <article key={emp.id} className="card p-4 hover:shadow-md transition-shadow" onClick={() => setSelectedEmployee(emp.id)}>
              <div className="flex items-start gap-3">
                <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="md" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="font-bold truncate">{emp.fullNameAr}</h3>
                    <StatusIndicator status={emp.status} />
                  </div>
                  <p className="mt-1 text-sm text-[var(--text-muted)] truncate">{emp.employeeCode}</p>
                  <div className="mt-2 flex flex-wrap gap-1.5 text-xs text-[var(--text-muted)]">
                    {emp.branchName && (
                      <span className="flex items-center gap-1">
                        <Building2 className="size-3" />
                        {emp.branchName}
                      </span>
                    )}
                    {emp.departmentName && (
                      <span className="flex items-center gap-1">
                        <Building2 className="size-3" />
                        {emp.departmentName}
                      </span>
                    )}
                    {emp.jobTitle && (
                      <span className="flex items-center gap-1">
                        <Workflow className="size-3" />
                        {emp.jobTitle}
                      </span>
                    )}
                  </div>
                  <div className="mt-2 flex items-center gap-2 text-xs">
                    {emp.subordinatesCount > 0 && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]">
                        <Users className="size-3" />
                        {emp.subordinatesCount} مرؤوس
                      </span>
                    )}
                  </div>
                </div>
              </div>
            </article>
          ))}
        </section>
      )}

      {/* Employee Detail Modal */}
      {selectedEmployee && <EmployeeDetailModal employeeId={selectedEmployee} onClose={() => setSelectedEmployee(null)} employees={employees} />}
    </div>
  );
}

function EmployeeDetailModal({ employeeId, onClose, employees }: { employeeId: string; onClose: () => void; employees: EmployeeDirectoryItem[] }) {
  const emp = employees.find((e) => e.id === employeeId);
  if (!emp) return null;

  const subordinates = employees.filter((e) => e.departmentId === emp.departmentId && e.id !== emp.id); // تقريبي

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50" onClick={onClose}>
      <div className="bg-[var(--surface)] rounded-2xl shadow-xl max-w-3xl w-full max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="sticky top-0 flex items-center justify-between border-b border-[var(--border)] bg-[var(--surface)] p-4 rounded-t-2xl">
          <div className="flex items-center gap-3">
            <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="lg" />
            <div>
              <h2 className="text-xl font-bold">{emp.fullNameAr}</h2>
              <p className="text-sm text-[var(--text-muted)]">{emp.employeeCode}</p>
            </div>
          </div>
          <button type="button" className="icon-button" onClick={onClose} aria-label="إغلاق">
            <svg className="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="p-6 space-y-6">
          {/* Info Grid */}
          <div className="grid gap-4 sm:grid-cols-2">
            <InfoField label="الكود الوظيفي" value={emp.employeeCode} icon={<User className="size-4" />} />
            <InfoField label="المسمى الوظيفي" value={emp.jobTitle ?? '—'} icon={<Workflow className="size-4" />} />
            <InfoField label="الإدارة" value={emp.branchName ?? '—'} icon={<Building2 className="size-4" />} />
            <InfoField label="القسم" value={emp.departmentName ?? '—'} icon={<Building2 className="size-4" />} />
            <InfoField label="الحالة" value={<StatusIndicator status={emp.status} />} icon={<Circle className="size-4" />} />
          </div>

          {/* Subordinates */}
          {subordinates.length > 0 && (
            <section>
              <h3 className="font-bold flex items-center gap-2">
                <Users className="size-5" />
                الزملاء في نفس القسم ({subordinates.length})
              </h3>
              <div className="mt-2 grid gap-2 sm:grid-cols-2">
                {subordinates.map((sub) => (
                  <button
                    key={sub.id}
                    type="button"
                    className="flex items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-3 hover:bg-[var(--surface)] transition-colors"
                    onClick={() => {
                      // Can navigate to subordinate detail
                    }}
                  >
                    <UserAvatar displayName={sub.fullNameAr} photoUrl={sub.photoUrl} size="sm" />
                    <div className="flex-1 min-w-0">
                      <p className="font-medium truncate">{sub.fullNameAr}</p>
                      <p className="text-xs text-[var(--text-muted)] truncate">
                        {sub.employeeCode} · {sub.jobTitle ?? ''}
                      </p>
                    </div>
                    <StatusIndicator status={sub.status} />
                  </button>
                ))}
              </div>
            </section>
          )}

          {/* Actions */}
          <div className="flex flex-wrap gap-2 pt-4 border-t border-[var(--border)]">
            <button type="button" className="btn-secondary" onClick={onClose}>
              إغلاق
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function InfoField({ label, value, icon }: { label: string; value: React.ReactNode; icon: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-4">
      <div className="flex items-center gap-2 text-xs text-[var(--text-muted)] mb-1">
        {icon}
        <span>{label}</span>
      </div>
      <div className="text-sm font-medium">{value}</div>
    </div>
  );
}
