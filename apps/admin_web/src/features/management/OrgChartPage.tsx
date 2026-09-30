import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { Building2, ChevronDown, Eye, GitBranch, ListTree, Maximize2, Minimize2, Minus, Network, Plus, RefreshCw, Users } from 'lucide-react';
import type { OrgChartTreeNode } from '@ahla/shared-contracts';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useOrgChart } from './useOrgChart';

const MIN_SCALE = 0.25;
const MAX_SCALE = 2;
const SCALE_STEP = 0.15;
const MOBILE_BREAKPOINT = 768;

/** Hook بسيط لكشف الموبايل عبر matchMedia */
function useIsMobile() {
  const [isMobile, setIsMobile] = useState(
    typeof window !== 'undefined' && typeof window.matchMedia === 'function' ? window.innerWidth < MOBILE_BREAKPOINT : false,
  );
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mq = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);
  return isMobile;
}

export function OrgChartPage({ embedded = false }: { embedded?: boolean }) {
  const [search, setSearch] = useState('');
  const [selectedDept, setSelectedDept] = useState('');
  const [viewMode, setViewMode] = useState<'tree' | 'list'>('tree');
  const [expandAll, setExpandAll] = useState<boolean | null>(null);

  const { data, isLoading, error, refetch } = useOrgChart(search);
  const navigate = useNavigate();
  const location = useLocation();
  const isMobile = useIsMobile();
  // مسار الملف الشخصي حسب المساحة الحالية — لا يُصلّب /admin (صفحات HR المستقلة).
  const employeeBasePath = location.pathname.startsWith('/admin') ? '/admin/hr/employees' : '/hr/employees';

  // ─── Zoom & Pan state (desktop only) ─────────────────────────────────
  const [scale, setScale] = useState(1);
  const [translate, setTranslate] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const panStart = useRef({ x: 0, y: 0, tx: 0, ty: 0 });
  const treeRef = useRef<HTMLDivElement>(null);

  const zoomIn = useCallback(() => setScale((s) => Math.min(MAX_SCALE, s + SCALE_STEP)), []);
  const zoomOut = useCallback(() => setScale((s) => Math.max(MIN_SCALE, s - SCALE_STEP)), []);
  const resetView = useCallback(() => {
    setScale(1);
    setTranslate({ x: 0, y: 0 });
  }, []);

  const fitToScreen = useCallback(() => {
    if (!treeRef.current) return;
    const container = treeRef.current.parentElement;
    if (!container) return;
    const treeWidth = treeRef.current.scrollWidth;
    const treeHeight = treeRef.current.scrollHeight;
    const containerWidth = container.clientWidth;
    const containerHeight = container.clientHeight;
    if (treeWidth === 0 || treeHeight === 0) return;
    const scaleX = (containerWidth - 40) / treeWidth;
    const scaleY = (containerHeight - 40) / treeHeight;
    const newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, Math.min(scaleX, scaleY)));
    setScale(newScale);
    setTranslate({ x: 0, y: 0 });
  }, []);

  // Mouse wheel zoom (desktop only)
  useEffect(() => {
    if (isMobile) return;
    const container = treeRef.current?.parentElement;
    if (!container) return;
    const handleWheel = (e: WheelEvent) => {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        const delta = e.deltaY > 0 ? -SCALE_STEP : SCALE_STEP;
        setScale((s) => Math.max(MIN_SCALE, Math.min(MAX_SCALE, +(s + delta).toFixed(2))));
      }
    };
    container.addEventListener('wheel', handleWheel, { passive: false });
    return () => container.removeEventListener('wheel', handleWheel);
  }, [isMobile]);

  // Keyboard shortcuts (desktop only)
  useEffect(() => {
    if (isMobile) return;
    const handler = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === '+' || e.key === '=') {
        e.preventDefault();
        zoomIn();
      } else if (e.key === '-' || e.key === '_') {
        e.preventDefault();
        zoomOut();
      } else if (e.key === '0') {
        e.preventDefault();
        resetView();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [isMobile, zoomIn, zoomOut, resetView]);

  // Pan handlers (desktop only)
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (isMobile) return;
      setIsPanning(true);
      panStart.current = { x: e.clientX, y: e.clientY, tx: translate.x, ty: translate.y };
    },
    [translate, isMobile],
  );

  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!isPanning || isMobile) return;
      const dx = e.clientX - panStart.current.x;
      const dy = e.clientY - panStart.current.y;
      setTranslate({ x: panStart.current.tx + dx, y: panStart.current.ty + dy });
    },
    [isPanning, isMobile],
  );

  const handleMouseUp = useCallback(() => setIsPanning(false), []);

  const employees = data?.employees ?? [];
  const tree = data?.tree ?? [];
  const stats = data?.stats ?? { totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 };

  // استخراج قائمة الإدارات المتاحة
  const departmentOptions = useMemo(() => {
    const set = new Set<string>();
    for (const emp of employees) {
      if (emp.departmentName) set.add(emp.departmentName);
    }
    return Array.from(set).sort();
  }, [employees]);

  // تصفية الشجرة حسب الإدارة المختارة
  const displayTree = useMemo(() => {
    if (!selectedDept) return tree;

    function filterDeptNode(node: OrgChartTreeNode): OrgChartTreeNode | null {
      const match = node.employee.departmentName === selectedDept;
      const filteredChildren = node.children.map((child) => filterDeptNode(child)).filter((c): c is OrgChartTreeNode => c !== null);

      if (match || filteredChildren.length > 0) {
        return {
          employee: node.employee,
          children: filteredChildren,
        };
      }
      return null;
    }

    return tree.map((n) => filterDeptNode(n)).filter((n): n is OrgChartTreeNode => n !== null);
  }, [tree, selectedDept]);

  if (isLoading) return <LoadingScreen label="جارٍ تحميل الهيكل التنظيمي…" />;
  if (error) return <ErrorState title="تعذر تحميل الهيكل" onRetry={() => refetch()} />;

  return (
    <div className="space-y-6 animate-fadeIn">
      {!embedded ? (
        <PageHeader
          title="الهيكل التنظيمي الإداري"
          description="شجرة هرمية كاملة للموظفين: المدير المباشر ومرؤوسوه بشكل متكرر."
          eyebrow="الإدارة"
          actions={
            <button type="button" className="btn btn-outline" onClick={() => refetch()}>
              <RefreshCw className="size-4" aria-hidden="true" />
              تحديث
            </button>
          }
        />
      ) : null}

      {/* بطاقات الإحصائيات */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <MetricCard
          label="إجمالي الموظفين"
          value={stats.totalEmployees}
          icon={Users}
          onClick={() => {
            setSearch('');
            setSelectedDept('');
          }}
        />
        <MetricCard
          label="عدد المديرين"
          value={stats.managersCount}
          icon={GitBranch}
          onClick={() => {
            setSearch('');
            setSelectedDept('');
          }}
        />
        <MetricCard
          label="أقصى عمق هرمي"
          value={stats.maxDepth}
          icon={GitBranch}
          onClick={() => {
            setSearch('');
            setSelectedDept('');
          }}
        />
        <MetricCard
          label="متوسط المرؤوسين"
          value={stats.avgDirectReports}
          icon={Users}
          onClick={() => {
            setSearch('');
            setSelectedDept('');
          }}
        />
      </div>

      {/* شريط أدوات البحث والفلترة ومبدل العرض */}
      <div className="space-y-3">
        <FilterBar
          searchValue={search}
          onSearchChange={setSearch}
          searchPlaceholder="ابحث بالاسم أو الكود أو المسمى الوظيفي أو القسم…"
          resultText={`${employees.length} موظف`}
          isDirty={search.trim().length > 0 || Boolean(selectedDept)}
          onClear={() => {
            setSearch('');
            setSelectedDept('');
          }}
        />

        {/* شريط خيارات متقدمة: تبديل العرض + فلتر الإدارات + أزرار التوسيع */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3">
          <div className="flex flex-wrap items-center gap-3">
            {/* مبدل نمط العرض */}
            <div className="flex rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] p-0.5 text-xs font-bold">
              <button
                type="button"
                onClick={() => setViewMode('tree')}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 transition ${
                  viewMode === 'tree' ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-sm' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                <Network className="size-3.5" />
                شجرة هرمية
              </button>
              <button
                type="button"
                onClick={() => setViewMode('list')}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 transition ${
                  viewMode === 'list' ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-sm' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                <ListTree className="size-3.5" />
                قائمة هرمية منظمة
              </button>
            </div>

            {/* فلتر الإدارة */}
            {departmentOptions.length > 0 && (
              <div className="flex items-center gap-2 text-xs">
                <span className="text-[var(--text-muted)] font-medium">الإدارة:</span>
                <select
                  value={selectedDept}
                  onChange={(e) => setSelectedDept(e.target.value)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs text-[var(--text-primary)] outline-none focus:border-[var(--brand-primary)]"
                >
                  <option value="">جميع الإدارات ({departmentOptions.length})</option>
                  {departmentOptions.map((dept) => (
                    <option key={dept} value={dept}>
                      {dept}
                    </option>
                  ))}
                </select>
              </div>
            )}
          </div>

          {/* أزرار التوسيع والطي */}
          <div className="flex items-center gap-2">
            <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => setExpandAll(true)} title="توسيع كامل الهيكل">
              <Plus className="size-3.5" />
              توسيع الكل
            </button>
            <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => setExpandAll(false)} title="طي الهيكل إلى الجذور">
              <Minus className="size-3.5" />
              طي الكل
            </button>
          </div>
        </div>
      </div>

      {/* أزرار التحكم في الزووم — تظهر في وضع الشجرة لسطح المكتب فقط */}
      {!isMobile && viewMode === 'tree' && (
        <div className="org-controls-toolbar flex items-center gap-2 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-3 py-2">
          <button type="button" className="btn btn-xs btn-ghost" onClick={zoomOut} aria-label="تصغير" title="تصغير">
            <Minus className="size-4" aria-hidden="true" />
          </button>
          <span className="min-w-[3rem] text-center text-sm font-medium text-[var(--text-secondary)]">{Math.round(scale * 100)}%</span>
          <button type="button" className="btn btn-xs btn-ghost" onClick={zoomIn} aria-label="تكبير" title="تكبير">
            <Plus className="size-4" aria-hidden="true" />
          </button>
          <div className="mx-1 h-4 w-px bg-[var(--border)]" aria-hidden="true" />
          <button type="button" className="btn btn-xs btn-ghost" onClick={fitToScreen} title="ملاءمة الشاشة">
            <Maximize2 className="size-4" aria-hidden="true" />
            <span className="hidden sm:inline">ملاءمة</span>
          </button>
          <button type="button" className="btn btn-xs btn-ghost" onClick={resetView} title="إعادة تعيين">
            <Minimize2 className="size-4" aria-hidden="true" />
            <span className="hidden sm:inline">إعادة</span>
          </button>
          <div className="mr-auto text-xs text-[var(--text-muted)]">Ctrl + Scroll للتكبير · اسحب للتحريك · +/- للتكبير · 0 لإعادة التعيين</div>
        </div>
      )}

      {/* منطقة عرض الهيكل الإداري */}
      {displayTree.length === 0 ? (
        <EmptyState title="لا توجد بيانات" description="لم يتم العثور على موظفين مطابقين للبحث أو الإدارة المختارة." />
      ) : viewMode === 'tree' ? (
        /* العرض الشجري الهرمي المرئي */
        <div
          className="org-tree-container relative overflow-auto rounded-xl border border-[var(--border)] bg-[var(--surface)] p-6"
          style={{ minHeight: '60vh' }}
          onMouseDown={!isMobile ? handleMouseDown : undefined}
          onMouseMove={!isMobile ? handleMouseMove : undefined}
          onMouseUp={!isMobile ? handleMouseUp : undefined}
          onMouseLeave={!isMobile ? handleMouseUp : undefined}
        >
          <div
            ref={treeRef}
            className="origin-top mx-auto inline-block min-w-full text-center"
            style={{
              transform: `scale(${scale}) translate(${translate.x}px, ${translate.y}px)`,
              cursor: isPanning ? 'grabbing' : 'grab',
            }}
          >
            <div className="flex justify-center gap-8">
              {displayTree.map((node) => (
                <OrgNode key={node.employee.id} node={node} depth={0} expandAll={expandAll} navigate={navigate} employeeBasePath={employeeBasePath} />
              ))}
            </div>
          </div>
        </div>
      ) : (
        /* العرض القائمي المنظم المتداخل */
        <div className="divide-y divide-[var(--border)] rounded-xl border border-[var(--border)] bg-[var(--surface)] overflow-hidden shadow-sm">
          {displayTree.map((node) => (
            <OrgTreeRowItem key={node.employee.id} node={node} depth={0} expandAll={expandAll} navigate={navigate} employeeBasePath={employeeBasePath} />
          ))}
        </div>
      )}
    </div>
  );
}

/** عقدة شجرة هرمية مرئية — تُرسم نفسها وموظفيها بشكل متكرر */
function OrgNode({
  node,
  depth,
  expandAll,
  navigate,
  employeeBasePath,
}: {
  node: OrgChartTreeNode;
  depth: number;
  expandAll: boolean | null;
  navigate: (path: string) => void;
  employeeBasePath: string;
}) {
  const [expanded, setExpanded] = useState(depth < 2);

  // تحديث حالة الطي والتوسيع عند ضغط توسيع/طي الكل
  if (expandAll !== null && expanded !== expandAll) {
    setExpanded(expandAll);
  }

  const emp = node.employee;
  const hasChildren = node.children.length > 0;

  return (
    <div className="org-node flex flex-col items-center">
      {/* بطاقة الموظف */}
      <button
        type="button"
        className="org-card group mx-auto mb-2 flex flex-col items-center gap-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3.5 shadow-sm transition hover:border-[var(--brand-primary)] hover:shadow-md text-center"
        onClick={() => navigate(`${employeeBasePath}/${emp.id}`)}
        style={{ minWidth: '180px', maxWidth: '220px' }}
      >
        <div className="relative">
          <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl ?? null} size="md" />
          <span className="absolute -bottom-1 -right-1">
            <StatusBadge status={emp.status} />
          </span>
        </div>

        <span className="text-sm font-bold text-[var(--text-primary)] group-hover:text-[var(--brand-primary)] transition-colors line-clamp-1">
          {emp.fullNameAr}
        </span>

        {emp.jobTitle ? (
          <span className="rounded-md bg-[var(--brand-primary-soft)]/20 px-2 py-0.5 text-[11px] font-semibold text-[var(--brand-primary)] line-clamp-1">
            {emp.jobTitle}
          </span>
        ) : null}

        {emp.departmentName ? (
          <span className="flex items-center gap-1 text-[11px] text-[var(--text-muted)] line-clamp-1">
            <Building2 className="size-3 shrink-0" />
            {emp.departmentName}
          </span>
        ) : null}

        <div className="flex items-center justify-between w-full mt-1 border-t border-[var(--border)] pt-1 text-[10px] text-[var(--text-muted)]">
          <span className="font-mono">{emp.employeeCode}</span>
          {hasChildren ? (
            <span className="font-bold text-[var(--brand-primary)]">👥 {node.children.length}</span>
          ) : (
            <span className="text-[var(--text-muted)]">عضو فريق</span>
          )}
        </div>
      </button>

      {/* زر التوسيع والطي مع خطوط التفريع الهرمية */}
      {hasChildren ? (
        <div className="flex flex-col items-center">
          <button
            type="button"
            className="mb-1 inline-flex size-6 items-center justify-center rounded-full border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-muted)] hover:bg-[var(--brand-primary)] hover:text-white transition shadow-sm z-10"
            onClick={() => setExpanded((v) => !v)}
            aria-label={expanded ? 'طي' : 'توسيع'}
          >
            <ChevronDown className={`size-3.5 transition-transform ${expanded ? '' : 'rotate-180'}`} aria-hidden="true" />
          </button>

          {expanded ? (
            <div className="relative mt-1 flex flex-col items-center">
              {/* الخط الرأسي النازل من الأب */}
              <div className="h-4 w-px bg-[var(--border)]" />

              {/* الحاوية الأفقية لربط الأبناء */}
              <div className="flex justify-center gap-6 border-t border-[var(--border)] pt-4">
                {node.children.map((child) => (
                  <OrgNode
                    key={child.employee.id}
                    node={child}
                    depth={depth + 1}
                    expandAll={expandAll}
                    navigate={navigate}
                    employeeBasePath={employeeBasePath}
                  />
                ))}
              </div>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

/** صف شجرة هرمية منظم للعرض القائمي المتداخل */
function OrgTreeRowItem({
  node,
  depth,
  expandAll,
  navigate,
  employeeBasePath,
}: {
  node: OrgChartTreeNode;
  depth: number;
  expandAll: boolean | null;
  navigate: (path: string) => void;
  employeeBasePath: string;
}) {
  const [expanded, setExpanded] = useState(depth < 2);

  if (expandAll !== null && expanded !== expandAll) {
    setExpanded(expandAll);
  }

  const emp = node.employee;
  const hasChildren = node.children.length > 0;
  const indentPx = depth * 28;

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
                {depth === 0 ? 'الإدارة العليا' : `المستوى ${depth}`}
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
            <span className="rounded-full bg-[var(--brand-primary-soft)]/30 px-2.5 py-0.5 text-xs font-bold text-[var(--brand-primary)]">
              👥 {node.children.length} مرؤوس مباشر
            </span>
          ) : null}

          <StatusBadge status={emp.status} />

          <button type="button" className="btn btn-outline btn-xs gap-1" onClick={() => navigate(`${employeeBasePath}/${emp.id}`)}>
            <Eye className="size-3.5" />
            <span className="hidden sm:inline">عرض الملف</span>
          </button>
        </div>
      </div>

      {hasChildren && expanded ? (
        <div className="border-r border-[var(--border)] mr-6">
          {node.children.map((child) => (
            <OrgTreeRowItem
              key={child.employee.id}
              node={child}
              depth={depth + 1}
              expandAll={expandAll}
              navigate={navigate}
              employeeBasePath={employeeBasePath}
            />
          ))}
        </div>
      ) : null}
    </div>
  );
}
