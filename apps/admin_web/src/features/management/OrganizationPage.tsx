import { Building2, BriefcaseBusiness, ChevronDown, ChevronLeft, Edit3, List, Network, Plus, Save, UsersRound } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { safeErrorMessage } from '../../core/errorMapper';
import { useOrganizationAdminCatalog, useOrganizationCommands } from './useAdminOperations';

type DepartmentDraft = {
  id?: string | null;
  entityId: string;
  branchId: string;
  parentId: string;
  managerId: string;
  code: string;
  name: string;
  nameEn: string;
  active: boolean;
};
type PositionDraft = {
  id?: string | null;
  departmentId: string;
  teamId: string;
  jobTitleId: string;
  gradeId: string;
  reportsToId: string;
  code: string;
  name: string;
  nameEn: string;
  headcount: number;
  active: boolean;
};

const emptyDepartment: DepartmentDraft = { entityId: '', branchId: '', parentId: '', managerId: '', code: '', name: '', nameEn: '', active: true };
const emptyPosition: PositionDraft = {
  departmentId: '',
  teamId: '',
  jobTitleId: '',
  gradeId: '',
  reportsToId: '',
  code: '',
  name: '',
  nameEn: '',
  headcount: 1,
  active: true,
};

type ViewMode = 'table' | 'tree';
type DepartmentRow = {
  id: string;
  entityId: string;
  branchId: string | null;
  parentId: string | null;
  managerId: string | null;
  code: string;
  name: string;
  nameEn: string | null;
  active: boolean;
  employeeCount: number;
  positionCount: number;
};

export function OrganizationPage() {
  const query = useOrganizationAdminCatalog();
  const commands = useOrganizationCommands();
  const [departmentDraft, setDepartmentDraft] = useState<DepartmentDraft | null>(null);
  const [positionDraft, setPositionDraft] = useState<PositionDraft | null>(null);
  const [filter, setFilter] = useState('');
  const [viewMode, setViewMode] = useState<ViewMode>('table');
  const data = query.data;
  const departments = useMemo(
    () => (data?.departments ?? []).filter((item) => `${item.code} ${item.name}`.toLowerCase().includes(filter.toLowerCase())),
    [data, filter],
  );

  async function saveDepartment(event: FormEvent) {
    event.preventDefault();
    if (!departmentDraft) return;
    try {
      await commands.department.mutateAsync({
        id: departmentDraft.id,
        entityId: departmentDraft.entityId,
        branchId: departmentDraft.branchId || null,
        parentId: departmentDraft.parentId || null,
        managerId: departmentDraft.managerId || null,
        code: departmentDraft.code,
        name: departmentDraft.name,
        nameEn: departmentDraft.nameEn || null,
        active: departmentDraft.active,
      });
      setDepartmentDraft(null);
    } catch {
      /* isError handled in dialog UI */
    }
  }

  async function savePosition(event: FormEvent) {
    event.preventDefault();
    if (!positionDraft) return;
    try {
      await commands.position.mutateAsync({
        id: positionDraft.id,
        departmentId: positionDraft.departmentId,
        teamId: positionDraft.teamId || null,
        jobTitleId: positionDraft.jobTitleId || null,
        gradeId: positionDraft.gradeId || null,
        reportsToId: positionDraft.reportsToId || null,
        code: positionDraft.code,
        name: positionDraft.name,
        nameEn: positionDraft.nameEn || null,
        headcount: positionDraft.headcount,
        active: positionDraft.active,
      });
      setPositionDraft(null);
    } catch {
      /* isError handled in dialog UI */
    }
  }

  function openDepartmentEdit(department: DepartmentRow) {
    setDepartmentDraft({
      id: department.id,
      entityId: department.entityId,
      branchId: department.branchId ?? '',
      parentId: department.parentId ?? '',
      managerId: department.managerId ?? '',
      code: department.code,
      name: department.name,
      nameEn: department.nameEn ?? '',
      active: department.active,
    });
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={viewMode === 'tree' ? 'الهيكل التنظيمي' : 'الهيكل المؤسسي والمناصب'}
        description={
          viewMode === 'tree'
            ? 'عرض شجري للإدارات والتبعية مع عدد الموظفين والمناصب في كل إدارة.'
            : 'إدارة الإدارات والتبعية والمناصب والطاقة المعتمدة من شاشة واحدة مرتبطة بسجل التدقيق.'
        }
        actions={
          <div className="flex flex-wrap gap-2">
            <div className="flex overflow-hidden rounded-lg border border-[var(--border)]">
              <button
                className={`flex items-center gap-1.5 px-3 py-2 text-sm font-bold transition-colors ${viewMode === 'table' ? 'bg-[var(--brand-primary)] text-white' : 'hover:bg-[var(--surface-muted)]'}`}
                onClick={() => setViewMode('table')}
                aria-label={'عرض جدولي'}
              >
                <List className="size-4" aria-hidden="true" />
                {'جدول'}
              </button>
              <button
                className={`flex items-center gap-1.5 px-3 py-2 text-sm font-bold transition-colors ${viewMode === 'tree' ? 'bg-[var(--brand-primary)] text-white' : 'hover:bg-[var(--surface-muted)]'}`}
                onClick={() => setViewMode('tree')}
                aria-label={'عرض شجري'}
              >
                <Network className="size-4" aria-hidden="true" />
                {'شجرة'}
              </button>
            </div>
            <button className="btn-secondary" onClick={() => setDepartmentDraft({ ...emptyDepartment, entityId: data?.entities[0]?.id ?? '' })}>
              <Plus className="size-4" aria-hidden="true" />
              {'إدارة جديدة'}
            </button>
            <button className="btn-primary" onClick={() => setPositionDraft({ ...emptyPosition, departmentId: data?.departments[0]?.id ?? '' })}>
              <Plus className="size-4" aria-hidden="true" />
              {'منصب جديد'}
            </button>
          </div>
        }
      />
      {query.isError ? (
        <ErrorState title={'تعذر تحميل الهيكل'} description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && !data ? (
        <LoadingScreen label={'جارٍ تحميل الهيكل…'} />
      ) : null}
      {data ? (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
            <MetricCard label={'الكيانات'} value={data.entities.length} icon={Building2} />
            <MetricCard label={'الفروع'} value={data.branches.length} icon={Building2} />
            <MetricCard label={'الإدارات'} value={data.departments.length} icon={UsersRound} />
            <MetricCard label={'المناصب'} value={data.positions.length} icon={BriefcaseBusiness} />
            <MetricCard
              label={'الشواغر'}
              value={data.positions.reduce((sum, item) => sum + Math.max(item.headcount - item.assignedCount, 0), 0)}
              icon={BriefcaseBusiness}
            />
          </section>

          {viewMode === 'tree' ? (
            <section className="card overflow-hidden">
              <div className="border-b border-[var(--border)] p-5">
                <h2 className="font-black">{'الهيكل التنظيمي'}</h2>
                <p className="muted mt-1 text-sm">{'عرض شجري للإدارات حسب التبعية. اضغط على الإدارة لتوسيعها.'}</p>
              </div>
              {data.departments.length === 0 ? (
                <EmptyState title={'لا توجد إدارات'} description={'لم يتم إنشاء أي إدارة بعد.'} />
              ) : (
                <div className="p-5">
                  <DepartmentTree
                    departments={data.departments}
                    positions={data.positions}
                    branches={data.branches}
                    employees={data.employees}
                    onEdit={openDepartmentEdit}
                  />
                </div>
              )}
            </section>
          ) : (
            <>
              <section className="card overflow-hidden">
                <div className="flex flex-col gap-3 border-b border-[var(--border)] p-5">
                  <div>
                    <h2 className="font-black">{'الإدارات'}</h2>
                    <p className="muted mt-1 text-sm">{'يمنع الخادم إنشاء حلقات في الهيكل الإداري.'}</p>
                  </div>
                  <FilterBar
                    searchValue={filter}
                    onSearchChange={setFilter}
                    searchPlaceholder={'بحث بالاسم أو الكود'}
                    resultText={`${departments.length} إدارة`}
                    isDirty={!!filter}
                    onClear={() => setFilter('')}
                  />
                </div>
                {departments.length === 0 ? (
                  <EmptyState title={'لا توجد إدارات'} description={'لا توجد إدارات مطابقة للبحث الحالي.'} />
                ) : (
                  <div className="overflow-x-auto">
                    <table className="data-table w-full min-w-[800px] text-start text-sm">
                      <thead className="bg-[var(--surface-muted)]">
                        <tr>
                          <th scope="col" className="p-4">
                            {'الإدارة'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الفرع'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الإدارة الأعلى'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الموظفون'}
                          </th>
                          <th scope="col" className="p-4">
                            {'المناصب'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الحالة'}
                          </th>
                          <th scope="col" className="p-4">
                            {'إجراء'}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {departments.map((department) => (
                          <tr key={department.id} className="border-t border-[var(--border)]">
                            <td className="p-4">
                              <p className="font-black">{department.name}</p>
                              <p className="muted font-mono text-xs">{department.code}</p>
                            </td>
                            <td className="p-4">{data.branches.find((x) => x.id === department.branchId)?.name ?? '—'}</td>
                            <td className="p-4">{data.departments.find((x) => x.id === department.parentId)?.name ?? 'إدارة عليا'}</td>
                            <td className="p-4">{department.employeeCount}</td>
                            <td className="p-4">{department.positionCount}</td>
                            <td className="p-4">
                              <StatusBadge value={department.active ? 'active' : 'inactive'} />
                            </td>
                            <td className="p-4">
                              <button className="icon-button" aria-label={'تعديل الإدارة'} onClick={() => openDepartmentEdit(department)}>
                                <Edit3 className="size-4" aria-hidden="true" />
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>

              <section className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <h2 className="font-black">{'المناصب والطاقة المعتمدة'}</h2>
                  <p className="muted mt-1 text-sm">{'العدد المعتمد مقابل الموظفين المسندين والشواغر الفعلية.'}</p>
                </div>
                {data.positions.length === 0 ? (
                  <EmptyState title={'لا توجد مناصب'} description={'لم يتم إنشاء أي منصب بعد.'} />
                ) : (
                  <div className="overflow-x-auto">
                    <table className="data-table w-full min-w-[880px] text-start text-sm">
                      <thead className="bg-[var(--surface-muted)]">
                        <tr>
                          <th scope="col" className="p-4">
                            {'المنصب'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الإدارة'}
                          </th>
                          <th scope="col" className="p-4">
                            {'يرفع إلى'}
                          </th>
                          <th scope="col" className="p-4">
                            {'المعتمد'}
                          </th>
                          <th scope="col" className="p-4">
                            {'المسند'}
                          </th>
                          <th scope="col" className="p-4">
                            {'الشاغر'}
                          </th>
                          <th scope="col" className="p-4">
                            {'إجراء'}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.positions.map((position) => (
                          <tr key={position.id} className="border-t border-[var(--border)]">
                            <td className="p-4">
                              <p className="font-black">{position.name}</p>
                              <p className="muted font-mono text-xs">{position.code}</p>
                            </td>
                            <td className="p-4">{data.departments.find((x) => x.id === position.departmentId)?.name ?? '—'}</td>
                            <td className="p-4">{data.positions.find((x) => x.id === position.reportsToId)?.name ?? 'أعلى مستوى'}</td>
                            <td className="p-4">{position.headcount}</td>
                            <td className="p-4">{position.assignedCount}</td>
                            <td className="p-4 font-black">{Math.max(position.headcount - position.assignedCount, 0)}</td>
                            <td className="p-4">
                              <button
                                className="icon-button"
                                aria-label={'تعديل المنصب'}
                                onClick={() =>
                                  setPositionDraft({
                                    id: position.id,
                                    departmentId: position.departmentId,
                                    teamId: position.teamId ?? '',
                                    jobTitleId: position.jobTitleId ?? '',
                                    gradeId: position.gradeId ?? '',
                                    reportsToId: position.reportsToId ?? '',
                                    code: position.code,
                                    name: position.name,
                                    nameEn: position.nameEn ?? '',
                                    headcount: position.headcount,
                                    active: position.active,
                                  })
                                }
                              >
                                <Edit3 className="size-4" aria-hidden="true" />
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            </>
          )}
        </>
      ) : null}

      {departmentDraft && data ? (
        <DialogOverlay title={departmentDraft.id ? 'تعديل الإدارة' : 'إنشاء إدارة'} onClose={() => setDepartmentDraft(null)}>
          <form className="space-y-4" onSubmit={(event) => void saveDepartment(event)}>
            <div className="grid gap-4 sm:grid-cols-2">
              <Input label={'الكود'} required value={departmentDraft.code} onChange={(value) => setDepartmentDraft({ ...departmentDraft, code: value })} />
              <Input
                label={'اسم الإدارة'}
                required
                value={departmentDraft.name}
                onChange={(value) => setDepartmentDraft({ ...departmentDraft, name: value })}
              />
              <Select
                label={'الكيان'}
                required
                value={departmentDraft.entityId}
                onChange={(value) => setDepartmentDraft({ ...departmentDraft, entityId: value })}
                options={data.entities}
              />
              <Select
                label={'الفرع'}
                value={departmentDraft.branchId}
                onChange={(value) => setDepartmentDraft({ ...departmentDraft, branchId: value })}
                options={data.branches.filter((x) => !departmentDraft.entityId || x.entityId === departmentDraft.entityId)}
              />
              <Select
                label={'الإدارة الأعلى'}
                value={departmentDraft.parentId}
                onChange={(value) => setDepartmentDraft({ ...departmentDraft, parentId: value })}
                options={data.departments.filter((x) => x.id !== departmentDraft.id)}
              />
              <Select
                label={'المدير'}
                value={departmentDraft.managerId}
                onChange={(value) => setDepartmentDraft({ ...departmentDraft, managerId: value })}
                options={data.employees}
              />
            </div>
            <Toggle checked={departmentDraft.active} onChange={(active) => setDepartmentDraft({ ...departmentDraft, active })} />
            {commands.department.isError && <ErrorBanner message={safeErrorMessage(commands.department.error)} />}
            <Submit pending={commands.department.isPending} />
          </form>
        </DialogOverlay>
      ) : null}

      {positionDraft && data ? (
        <DialogOverlay title={positionDraft.id ? 'تعديل المنصب' : 'إنشاء منصب'} onClose={() => setPositionDraft(null)}>
          <form className="space-y-4" onSubmit={(event) => void savePosition(event)}>
            <div className="grid gap-4 sm:grid-cols-2">
              <Input label={'الكود'} required value={positionDraft.code} onChange={(value) => setPositionDraft({ ...positionDraft, code: value })} />
              <Input label={'اسم المنصب'} required value={positionDraft.name} onChange={(value) => setPositionDraft({ ...positionDraft, name: value })} />
              <Select
                label={'الإدارة'}
                required
                value={positionDraft.departmentId}
                onChange={(value) => setPositionDraft({ ...positionDraft, departmentId: value, teamId: '' })}
                options={data.departments}
              />
              <Select
                label={'الفريق'}
                value={positionDraft.teamId}
                onChange={(value) => setPositionDraft({ ...positionDraft, teamId: value })}
                options={data.teams.filter((x) => x.departmentId === positionDraft.departmentId)}
              />
              <Select
                label={'المسمى الوظيفي'}
                value={positionDraft.jobTitleId}
                onChange={(value) => setPositionDraft({ ...positionDraft, jobTitleId: value })}
                options={data.jobTitles}
              />
              <Select
                label={'الدرجة'}
                value={positionDraft.gradeId}
                onChange={(value) => setPositionDraft({ ...positionDraft, gradeId: value })}
                options={data.grades}
              />
              <Select
                label={'يرفع إلى'}
                value={positionDraft.reportsToId}
                onChange={(value) => setPositionDraft({ ...positionDraft, reportsToId: value })}
                options={data.positions.filter((x) => x.id !== positionDraft.id)}
              />
              <Input
                label={'العدد المعتمد'}
                type="number"
                required
                value={String(positionDraft.headcount)}
                onChange={(value) => setPositionDraft({ ...positionDraft, headcount: Math.max(0, Number(value) || 0) })}
              />
            </div>
            <Toggle checked={positionDraft.active} onChange={(active) => setPositionDraft({ ...positionDraft, active })} />
            {commands.position.isError && <ErrorBanner message={safeErrorMessage(commands.position.error)} />}
            <Submit pending={commands.position.isPending} />
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

// ─── عرض شجري للإدارات ────────────────────────────────────────────────────────

type TreeDept = DepartmentRow & { children: TreeDept[] };

function buildTree(departments: DepartmentRow[]): TreeDept[] {
  const map = new Map<string, TreeDept>();
  for (const d of departments) map.set(d.id, { ...d, children: [] });
  const roots: TreeDept[] = [];
  for (const node of map.values()) {
    const parent = node.parentId ? map.get(node.parentId) : undefined;
    if (parent) {
      parent.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function DepartmentTree({
  departments,
  positions,
  branches,
  employees,
  onEdit,
}: {
  departments: DepartmentRow[];
  positions: Array<{ id: string; departmentId: string; name: string; code: string; headcount: number; assignedCount: number }>;
  branches: Array<{ id: string; name: string }>;
  employees: Array<{ id: string; name: string }>;
  onEdit: (department: DepartmentRow) => void;
}) {
  const roots = useMemo(() => buildTree(departments), [departments]);
  if (roots.length === 0) return <EmptyState title={'لا توجد إدارات'} description={'لم يتم إنشاء أي إدارة بعد.'} />;
  return (
    <div className="space-y-1">
      {roots.map((node) => (
        <TreeNode key={node.id} node={node} depth={0} positions={positions} branches={branches} employees={employees} onEdit={onEdit} />
      ))}
    </div>
  );
}

function TreeNode({
  node,
  depth,
  positions,
  branches,
  employees,
  onEdit,
}: {
  node: TreeDept;
  depth: number;
  positions: Array<{ id: string; departmentId: string; name: string; code: string; headcount: number; assignedCount: number }>;
  branches: Array<{ id: string; name: string }>;
  employees: Array<{ id: string; name: string }>;
  onEdit: (department: DepartmentRow) => void;
}) {
  const [expanded, setExpanded] = useState(depth < 2);
  const hasChildren = node.children.length > 0;
  const deptPositions = positions.filter((p) => p.departmentId === node.id);
  const manager = node.managerId ? employees.find((e) => e.id === node.managerId) : null;
  const branch = node.branchId ? branches.find((b) => b.id === node.branchId) : null;

  return (
    <div>
      <div
        className={`flex items-center gap-2 rounded-lg px-3 py-2.5 transition-colors hover:bg-[var(--surface-muted)] ${depth === 0 ? 'font-black' : ''}`}
        style={{ paddingInlineStart: `${depth * 28 + 12}px` }}
      >
        <button
          className="flex size-5 shrink-0 items-center justify-center rounded text-[var(--text-muted)]"
          onClick={() => setExpanded(!expanded)}
          aria-label={expanded ? 'طي' : 'وسع'}
          disabled={!hasChildren && deptPositions.length === 0}
        >
          {hasChildren || deptPositions.length > 0 ? (
            expanded ? (
              <ChevronDown className="size-4" />
            ) : (
              <ChevronLeft className="size-4" />
            )
          ) : (
            <span className="size-1.5 rounded-full bg-[var(--text-muted)] opacity-40" />
          )}
        </button>
        <Building2 className="size-4 shrink-0 text-[var(--text-muted)]" />
        <span className="min-w-0 flex-1 truncate">{node.name}</span>
        <span className="font-mono text-xs text-[var(--text-muted)]">{node.code}</span>
        {branch ? <span className="hidden rounded bg-[var(--surface-muted)] px-2 py-0.5 text-xs text-[var(--text-muted)] sm:inline">{branch.name}</span> : null}
        <span className="flex items-center gap-1 text-xs text-[var(--text-muted)]">
          <UsersRound className="size-3" />
          {node.employeeCount}
        </span>
        <StatusBadge value={node.active ? 'active' : 'inactive'} />
        <button className="icon-button" aria-label={'تعديل الإدارة'} onClick={() => onEdit(node)}>
          <Edit3 className="size-3.5" />
        </button>
      </div>

      {expanded && (
        <>
          {deptPositions.length > 0 && (
            <div className="space-y-0.5" style={{ paddingInlineStart: `${(depth + 1) * 28 + 12}px` }}>
              {deptPositions.map((position) => (
                <div key={position.id} className="flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm text-[var(--text-muted)]">
                  <BriefcaseBusiness className="size-3.5 shrink-0" />
                  <span className="min-w-0 flex-1 truncate">{position.name}</span>
                  <span className="font-mono text-xs">{position.code}</span>
                  <span className="text-xs">
                    {position.assignedCount}/{position.headcount}
                  </span>
                  {position.headcount > position.assignedCount && (
                    <span className="rounded bg-[var(--warning-soft)] px-1.5 py-0.5 text-[10px] font-bold text-[var(--warning)]">
                      {'شاغر'}
                    </span>
                  )}
                </div>
              ))}
            </div>
          )}
          {manager && (
            <div className="flex items-center gap-2 text-xs text-[var(--text-muted)]" style={{ paddingInlineStart: `${(depth + 1) * 28 + 24}px` }}>
              <span>{'المدير:'}</span>
              <span className="font-bold">{manager.name}</span>
            </div>
          )}
          {node.children.map((child) => (
            <TreeNode key={child.id} node={child} depth={depth + 1} positions={positions} branches={branches} employees={employees} onEdit={onEdit} />
          ))}
        </>
      )}
    </div>
  );
}

// ─── مكونات مساعدة ────────────────────────────────────────────────────────────

function Input({
  label,
  value,
  onChange,
  required,
  type = 'text',
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  type?: string;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      <input className="input" type={type} required={required} value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}
function Select({
  label,
  value,
  onChange,
  options,
  required,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Array<{ id: string; name: string }>;
  required?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      <select className="input" required={required} aria-label={label} value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="">{'غير محدد'}</option>
        {options.map((item) => (
          <option key={item.id} value={item.id}>
            {item.name}
          </option>
        ))}
      </select>
    </label>
  );
}
function Toggle({ checked, onChange }: { checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">
      <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
      {'نشط'}
    </label>
  );
}
function Submit({ pending }: { pending: boolean }) {
  return (
    <button className="btn-primary" type="submit" disabled={pending}>
      <Save className="size-4" aria-hidden="true" />
      {pending ? 'جارٍ الحفظ…' : 'حفظ'}
    </button>
  );
}
