import { useMemo, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';
import {
  ArrowDown,
  Building2,
  ChevronDown,
  ExternalLink,
  Eye,
  GitBranch,
  Layers,
  Minus,
  Network,
  Plus,
  RefreshCw,
  Search,
  Shield,
  UserCheck,
  Users,
} from 'lucide-react';
import type { Employee360, OrgChartTreeNode } from '@ahla/shared-contracts';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEmployeeOrgHierarchy } from './useEmployeeOrgHierarchy';

export interface EmployeeOrgChartTabProps {
  employeeId: string;
  employee: Employee360;
  onChangeManagerClick?: () => void;
}

type SubordinatesViewMode = 'tree' | 'list';

export function EmployeeOrgChartTab({ employeeId, employee, onChangeManagerClick }: EmployeeOrgChartTabProps) {
  const navigate = useNavigate();
  const location = useLocation();
  const [viewMode, setViewMode] = useState<SubordinatesViewMode>('tree');
  const [searchSub, setSearchSub] = useState('');
  const [expandAll, setExpandAll] = useState<boolean | null>(null);

  // مسار الروابط حسب السياق الحالي (HR أو Admin)
  const employeeBasePath = location.pathname.startsWith('/admin') ? '/admin/hr/employees' : '/hr/employees';

  const { data, isLoading, isError, refetch } = useEmployeeOrgHierarchy(employeeId, {
    fullNameAr: employee.fullNameAr,
    fullNameEn: employee.fullNameEn,
    photoUrl: employee.photoUrl,
    jobTitle: employee.jobTitle,
    department: employee.department,
    employeeCode: employee.employeeCode,
    managerName: employee.managerName,
    managerId: employee.managerId,
    directReports: employee.directReports,
  });

  // تصفية المرؤوسين بالبحث
  const filteredSubTree = useMemo(() => {
    if (!data?.subTree) return null;
    const q = searchSub.trim().toLowerCase();
    if (!q) return data.subTree;

    function filterNode(node: OrgChartTreeNode): OrgChartTreeNode | null {
      const matchSelf =
        node.employee.fullNameAr.toLowerCase().includes(q) ||
        (node.employee.fullNameEn?.toLowerCase().includes(q) ?? false) ||
        node.employee.jobTitle.toLowerCase().includes(q) ||
        node.employee.departmentName.toLowerCase().includes(q) ||
        node.employee.employeeCode.toLowerCase().includes(q);

      const filteredChildren = node.children.map((child) => filterNode(child)).filter((c): c is OrgChartTreeNode => c !== null);

      if (matchSelf || filteredChildren.length > 0) {
        return {
          employee: node.employee,
          children: filteredChildren,
        };
      }
      return null;
    }

    return filterNode(data.subTree);
  }, [data?.subTree, searchSub]);

  if (isLoading) {
    return <LoadingScreen label="جارٍ تحميل الهيكل الإداري للموظف…" />;
  }

  if (isError || !data) {
    return (
      <ErrorState title="تعذر تحميل الهيكل الإداري للموظف" description="حدث خطأ أثناء جلب بيانات التبعية الإدارية وشجرة المرؤوسين." onRetry={() => refetch()} />
    );
  }

  const { ancestors, stats, isTopLevel, hasSubordinates } = data;
  const directManager = ancestors.length > 0 ? ancestors[ancestors.length - 1] : null;

  return (
    <div className="space-y-8 animate-fadeIn">
      {/* ─── الرأس وبطاقات الإحصائيات ─── */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5">
        <div>
          <div className="flex items-center gap-2">
            <span className="flex size-9 items-center justify-center rounded-xl bg-[var(--brand-primary-soft)] text-[var(--brand-primary)]">
              <Network className="size-5" aria-hidden="true" />
            </span>
            <div>
              <h3 className="text-lg font-black text-[var(--text-primary)]">الهيكل والتسلسل الإداري للموظف</h3>
              <p className="text-xs text-[var(--text-muted)]">سلسلة القيادة الإدارية صعوداً حتى الإدارة العليا، وشجرة المرؤوسين وفرق العمل التابعة نزولاً.</p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            className="btn btn-outline btn-sm gap-2"
            onClick={() => navigate(`${employeeBasePath}?tab=org-chart`)}
            title="فتح الهيكل التنظيمي الكامل للمؤسسة"
          >
            <GitBranch className="size-4" aria-hidden="true" />
            الهيكل التنظيمي العام
          </button>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => refetch()} title="تحديث البيانات">
            <RefreshCw className="size-4" aria-hidden="true" />
          </button>
        </div>
      </div>

      {/* ─── بطاقات المؤشرات الإدارية السريعة ─── */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <MetricCard
          label="المدير المباشر"
          value={directManager ? directManager.fullNameAr : isTopLevel ? 'الإدارة العليا' : (employee.managerName ?? 'غير محدد')}
          hint={directManager?.jobTitle ?? (isTopLevel ? 'رئيس المؤسسة' : undefined)}
          icon={UserCheck}
          onClick={directManager ? () => navigate(`${employeeBasePath}/${directManager.id}`) : undefined}
        />
        <MetricCard label="المرؤوسون المباشرون" value={stats.directReportsCount} hint="يتبعون للموظف مباشرة" icon={Users} />
        <MetricCard label="إجمالي الفريق التابع" value={stats.totalSubordinatesCount} hint="مباشر وغير مباشر بجميع المستويات" icon={Network} />
        <MetricCard
          label="مستويات التبعية التابعة"
          value={stats.maxSubtreeDepth}
          hint={stats.managersUnderCount > 0 ? `${stats.managersUnderCount} مديري فرق تحته` : 'فريق مباشر فقط'}
          icon={Layers}
        />
      </div>

      {/* ─── القسم الأول: سلسلة القيادة الإدارية الصاعدة (Ancestors) ─── */}
      <section className="card p-6">
        <div className="mb-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="flex size-7 items-center justify-center rounded-lg bg-indigo-500/10 text-indigo-500">
              <Shield className="size-4" aria-hidden="true" />
            </span>
            <div>
              <h4 className="font-black text-[var(--text-primary)]">سلسلة القيادة الإدارية (التسلسل الصاعد)</h4>
              <p className="text-xs text-[var(--text-muted)]">المسار الهرمي للموظف وصولاً إلى قمة الهيكل التنظيمي للمؤسسة.</p>
            </div>
          </div>
          {onChangeManagerClick ? (
            <button type="button" onClick={onChangeManagerClick} className="btn btn-outline btn-xs gap-1.5">
              تغيير المدير المباشر
            </button>
          ) : null}
        </div>

        {isTopLevel ? (
          <div className="flex items-center gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-amber-900 dark:text-amber-200">
            <Shield className="size-6 shrink-0 text-amber-500" />
            <div>
              <p className="text-sm font-bold">هذا الموظف في قمة الهيكل التنظيمي (الإدارة العليا / الإدارة العامة)</p>
              <p className="text-xs text-amber-800/80 dark:text-amber-300/80">
                ليس لديه مدير مباشر في النظام ويتبع مباشرة لمجلس الإدارة أو القيادة التنفيذية العليا.
              </p>
            </div>
          </div>
        ) : ancestors.length === 0 ? (
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-4 text-center text-sm text-[var(--text-muted)]">
            لم يتم تسجيل مدير مباشر لهذا الموظف بعد.
          </div>
        ) : (
          <div className="relative space-y-4">
            {ancestors.map((manager, index) => {
              const isDirect = index === ancestors.length - 1;
              return (
                <div key={manager.id} className="relative flex flex-col items-center">
                  <div
                    className={`w-full flex items-center justify-between gap-4 rounded-xl border p-4 transition ${
                      isDirect
                        ? 'border-[var(--brand-primary)] bg-[var(--brand-primary-soft)]/20 shadow-sm'
                        : 'border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-muted)]'
                    }`}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <UserAvatar displayName={manager.fullNameAr} photoUrl={manager.photoUrl} size="md" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-bold text-[var(--text-primary)] truncate">{manager.fullNameAr}</span>
                          <span
                            className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                              isDirect ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-muted)] text-[var(--text-muted)]'
                            }`}
                          >
                            {isDirect ? 'المدير المباشر' : `مستوى إداري أعلى (${ancestors.length - index})`}
                          </span>
                        </div>
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1 text-xs text-[var(--text-muted)]">
                          {manager.jobTitle ? <span>{manager.jobTitle}</span> : null}
                          {manager.departmentName ? (
                            <span className="flex items-center gap-1">
                              <Building2 className="size-3 text-[var(--text-muted)]" />
                              {manager.departmentName}
                            </span>
                          ) : null}
                          {manager.employeeCode ? <span className="font-mono">{manager.employeeCode}</span> : null}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        className="btn btn-outline btn-xs gap-1.5 shrink-0"
                        onClick={() => navigate(`${employeeBasePath}/${manager.id}`)}
                        title="فتح الملف الشخصي للمدير"
                      >
                        <Eye className="size-3.5" aria-hidden="true" />
                        <span className="hidden sm:inline">عرض الملف</span>
                      </button>
                    </div>
                  </div>

                  {/* سهم التبعية إلى المستوى التالي */}
                  <div className="flex items-center justify-center py-1">
                    <span className="flex size-6 items-center justify-center rounded-full bg-[var(--surface-muted)] border border-[var(--border)] text-[var(--text-muted)]">
                      <ArrowDown className="size-3.5" />
                    </span>
                  </div>
                </div>
              );
            })}

            {/* بطاقة الموظف الحالي في السلسلة */}
            <div className="flex items-center justify-between gap-4 rounded-xl border-2 border-[var(--brand-primary)] bg-[var(--surface)] p-4 shadow-md">
              <div className="flex items-center gap-3 min-w-0">
                <UserAvatar displayName={data.employee.fullNameAr} photoUrl={data.employee.photoUrl} size="md" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-base font-black text-[var(--text-primary)] truncate">{data.employee.fullNameAr}</span>
                    <span className="rounded-full bg-[var(--brand-primary)] px-2.5 py-0.5 text-[10px] font-black text-white">الموظف الحالي</span>
                  </div>
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1 text-xs text-[var(--text-muted)]">
                    {data.employee.jobTitle ? <span className="font-bold text-[var(--brand-primary)]">{data.employee.jobTitle}</span> : null}
                    {data.employee.departmentName ? (
                      <span className="flex items-center gap-1">
                        <Building2 className="size-3" />
                        {data.employee.departmentName}
                      </span>
                    ) : null}
                    <span className="font-mono">{data.employee.employeeCode}</span>
                  </div>
                </div>
              </div>

              <div className="text-end">
                <StatusBadge status={data.employee.status} />
              </div>
            </div>
          </div>
        )}
      </section>

      {/* ─── القسم الثاني: شجرة المرؤوسين وفريق العمل التابع ("وهكذه") ─── */}
      <section className="card p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[var(--border)] pb-4 mb-5">
          <div className="flex items-center gap-2">
            <span className="flex size-7 items-center justify-center rounded-lg bg-emerald-500/10 text-emerald-500">
              <Users className="size-4" aria-hidden="true" />
            </span>
            <div>
              <h4 className="font-black text-[var(--text-primary)]">
                المرؤوسون وفريق العمل التابع
                <span className="mr-2 text-xs font-normal text-[var(--text-muted)]">
                  ({stats.directReportsCount} مباشرين · {stats.totalSubordinatesCount} إجمالي الفريق)
                </span>
              </h4>
              <p className="text-xs text-[var(--text-muted)]">الهيكل الإداري التابع لهذا الموظف متدرجاً للمرؤوسين المباشرين والمرؤوسين التابعين لهم وهكذه.</p>
            </div>
          </div>

          {hasSubordinates ? (
            <div className="flex flex-wrap items-center gap-2">
              {/* مبدّل العرض */}
              <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] p-0.5 text-xs font-bold">
                <button
                  type="button"
                  onClick={() => setViewMode('tree')}
                  className={`rounded-md px-3 py-1.5 transition ${
                    viewMode === 'tree'
                      ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-sm'
                      : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                  }`}
                >
                  شجرة هرمية
                </button>
                <button
                  type="button"
                  onClick={() => setViewMode('list')}
                  className={`rounded-md px-3 py-1.5 transition ${
                    viewMode === 'list'
                      ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-sm'
                      : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                  }`}
                >
                  قائمة هرمية
                </button>
              </div>

              {/* أزرار التوسيع والطي */}
              <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => setExpandAll(true)} title="توسيع كامل الشجرة">
                <Plus className="size-3.5" />
                توسيع الكل
              </button>
              <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => setExpandAll(false)} title="طي الشجرة">
                <Minus className="size-3.5" />
                طي الكل
              </button>
            </div>
          ) : null}
        </div>

        {!hasSubordinates ? (
          <div className="rounded-2xl border border-dashed border-[var(--border)] bg-[var(--surface-muted)]/50 p-8 text-center">
            <div className="mx-auto flex size-12 items-center justify-center rounded-2xl bg-[var(--surface)] border border-[var(--border)] text-[var(--text-muted)] shadow-sm mb-3">
              <Users className="size-6" />
            </div>
            <h5 className="text-base font-bold text-[var(--text-primary)]">لا يوجد مرؤوسون تحت إدارة هذا الموظف حالياً</h5>
            <p className="mx-auto mt-1 max-w-md text-xs text-[var(--text-muted)]">
              الموظف يعمل بصفة مساهم فردي (Individual Contributor) وينفذ مهامه دون الإشراف على موظفين آخرين في الهيكل التنظيمي الحالي.
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            {/* حقل البحث داخل المرؤوسين */}
            {stats.totalSubordinatesCount > 2 ? (
              <div className="relative">
                <Search className="absolute right-3 top-2.5 size-4 text-[var(--text-muted)]" />
                <input
                  type="text"
                  placeholder="ابحث داخل فريق العمل التابع بالاسم أو الكود أو المسمى..."
                  value={searchSub}
                  onChange={(e) => setSearchSub(e.target.value)}
                  className="input w-full pr-9 text-xs"
                />
              </div>
            ) : null}

            {filteredSubTree === null || filteredSubTree.children.length === 0 ? (
              <EmptyState title="لا توجد نتائج مطابقة" description="لم يتم العثور على مرؤوسين يطابقون كلمة البحث." />
            ) : viewMode === 'tree' ? (
              /* العرض الشجري المرئي التفاعلي */
              <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/30 p-6 min-h-[300px]">
                <div className="inline-block min-w-full text-center">
                  <div className="flex justify-center gap-6">
                    {filteredSubTree.children.map((childNode) => (
                      <SubordinateTreeNode
                        key={childNode.employee.id}
                        node={childNode}
                        level={1}
                        expandAll={expandAll}
                        employeeBasePath={employeeBasePath}
                        navigate={navigate}
                      />
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              /* العرض الهرمي المتداخل كقائمة */
              <div className="divide-y divide-[var(--border)] rounded-xl border border-[var(--border)] bg-[var(--surface)] overflow-hidden">
                {filteredSubTree.children.map((childNode) => (
                  <SubordinateListItem
                    key={childNode.employee.id}
                    node={childNode}
                    level={1}
                    expandAll={expandAll}
                    employeeBasePath={employeeBasePath}
                    navigate={navigate}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// عقدة الشجرة المرئية للمرؤوسين (Recursive Subordinate Tree Node)
// ---------------------------------------------------------------------------
function SubordinateTreeNode({
  node,
  level,
  expandAll,
  employeeBasePath,
  navigate,
}: {
  node: OrgChartTreeNode;
  level: number;
  expandAll: boolean | null;
  employeeBasePath: string;
  navigate: (path: string) => void;
}) {
  const [expanded, setExpanded] = useState(level < 3);

  // مواكبة زر توسيع الكل / طي الكل
  if (expandAll !== null && expanded !== expandAll) {
    setExpanded(expandAll);
  }

  const emp = node.employee;
  const hasChildren = node.children.length > 0;

  return (
    <div className="flex flex-col items-center">
      {/* بطاقة المرؤوس */}
      <div className="group relative flex w-60 flex-col rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3 text-start shadow-sm transition hover:border-[var(--brand-primary)] hover:shadow-md">
        <div className="flex items-center justify-between gap-2 mb-2">
          <span className="rounded-md bg-[var(--surface-muted)] px-2 py-0.5 text-[10px] font-bold text-[var(--text-muted)]">مستوى {level}</span>
          <StatusBadge status={emp.status} />
        </div>

        <div className="flex items-center gap-2.5">
          <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="sm" />
          <div className="min-w-0 flex-1">
            <p className="text-xs font-bold text-[var(--text-primary)] truncate group-hover:text-[var(--brand-primary)]">{emp.fullNameAr}</p>
            <p className="text-[11px] text-[var(--text-muted)] truncate">{emp.jobTitle || 'موظف'}</p>
          </div>
        </div>

        <div className="mt-2.5 flex items-center justify-between border-t border-[var(--border)] pt-2 text-[10px] text-[var(--text-muted)]">
          <span className="truncate">{emp.departmentName || '—'}</span>
          <button
            type="button"
            className="flex items-center gap-1 font-bold text-[var(--brand-primary)] hover:underline"
            onClick={() => navigate(`${employeeBasePath}/${emp.id}`)}
          >
            <span>الملف</span>
            <ExternalLink className="size-3" />
          </button>
        </div>

        {hasChildren ? (
          <div className="mt-2 flex items-center justify-between rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-[10px]">
            <span className="font-bold text-[var(--text-primary)]">
              👥 {node.children.length} {node.children.length === 1 ? 'مرؤوس مباشر' : 'مرؤوسين'}
            </span>
            <button
              type="button"
              className="inline-flex items-center gap-1 font-bold text-[var(--brand-primary)]"
              onClick={() => setExpanded((v) => !v)}
              aria-label={expanded ? 'طي الفريق التابع' : 'توسيع الفريق التابع'}
            >
              <span>{expanded ? 'طي' : 'إظهار'}</span>
              <ChevronDown className={`size-3 transition-transform ${expanded ? '' : 'rotate-180'}`} />
            </button>
          </div>
        ) : null}
      </div>

      {/* خطوط الشجرة والتفرع إلى المرؤوسين التاليين */}
      {hasChildren && expanded ? (
        <div className="relative mt-2 flex flex-col items-center">
          {/* خط رأسي من العقدة الأب */}
          <div className="h-4 w-px bg-[var(--border)]" />

          {/* الحاوية الأفقية للأبناء */}
          <div className="flex gap-4 border-t border-[var(--border)] pt-4">
            {node.children.map((child) => (
              <SubordinateTreeNode
                key={child.employee.id}
                node={child}
                level={level + 1}
                expandAll={expandAll}
                employeeBasePath={employeeBasePath}
                navigate={navigate}
              />
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// عنصر القائمة الهرمية المتداخلة (Recursive Hierarchical List Item)
// ---------------------------------------------------------------------------
function SubordinateListItem({
  node,
  level,
  expandAll,
  employeeBasePath,
  navigate,
}: {
  node: OrgChartTreeNode;
  level: number;
  expandAll: boolean | null;
  employeeBasePath: string;
  navigate: (path: string) => void;
}) {
  const [expanded, setExpanded] = useState(level < 3);

  if (expandAll !== null && expanded !== expandAll) {
    setExpanded(expandAll);
  }

  const emp = node.employee;
  const hasChildren = node.children.length > 0;
  const indentPx = (level - 1) * 24;

  return (
    <div>
      <div
        className="flex items-center justify-between gap-3 p-3.5 hover:bg-[var(--surface-muted)] transition"
        style={{ paddingRight: `${Math.max(16, indentPx + 16)}px` }}
      >
        <div className="flex items-center gap-3 min-w-0">
          {hasChildren ? (
            <button
              type="button"
              className="flex size-6 items-center justify-center rounded-md border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text-primary)]"
              onClick={() => setExpanded((v) => !v)}
              aria-label={expanded ? 'طي' : 'توسيع'}
            >
              <ChevronDown className={`size-3.5 transition-transform ${expanded ? '' : '-rotate-90'}`} />
            </button>
          ) : (
            <span className="size-6 inline-block" />
          )}

          <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="sm" />

          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-sm font-bold text-[var(--text-primary)] truncate">{emp.fullNameAr}</span>
              <span className="rounded bg-[var(--surface-muted)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--text-muted)]">
                {level === 1 ? 'مرؤوس مباشر' : `مستوى ${level}`}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-x-3 text-xs text-[var(--text-muted)] mt-0.5">
              <span>{emp.jobTitle || 'موظف'}</span>
              <span>•</span>
              <span>{emp.departmentName || 'بدون إدارة'}</span>
              <span className="font-mono text-[11px]">{emp.employeeCode}</span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3 shrink-0">
          {hasChildren ? (
            <span className="rounded-full bg-indigo-500/10 px-2.5 py-0.5 text-xs font-bold text-indigo-500">{node.children.length} مرؤوسين</span>
          ) : null}

          <StatusBadge status={emp.status} />

          <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => navigate(`${employeeBasePath}/${emp.id}`)}>
            <Eye className="size-3.5" />
            <span className="hidden sm:inline">فتح الملف</span>
          </button>
        </div>
      </div>

      {hasChildren && expanded ? (
        <div className="border-r border-[var(--border)] mr-6">
          {node.children.map((child) => (
            <SubordinateListItem
              key={child.employee.id}
              node={child}
              level={level + 1}
              expandAll={expandAll}
              employeeBasePath={employeeBasePath}
              navigate={navigate}
            />
          ))}
        </div>
      ) : null}
    </div>
  );
}
