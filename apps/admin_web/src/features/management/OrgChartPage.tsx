import { useCallback, useRef, useState, useEffect } from 'react';
import { useNavigate } from 'react-router';
import {
  ChevronDown,
  ChevronLeft,
  GitBranch,
  Maximize2,
  Minimize2,
  Minus,
  Plus,
  RefreshCw,
  Users,
} from 'lucide-react';
import type { OrgChartTreeNode } from '@ahla/shared-contracts';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { useOrgChart } from './useOrgChart';

const MIN_SCALE = 0.25;
const MAX_SCALE = 2;
const SCALE_STEP = 0.15;

export function OrgChartPage() {
  const [search, setSearch] = useState('');
  const { data, isLoading, error, refetch } = useOrgChart(search);
  const navigate = useNavigate();

  // ─── Zoom & Pan state ──────────────────────────────────────────────────
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

  // Mouse wheel zoom
  useEffect(() => {
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
  }, []);

  // Pan handlers
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    setIsPanning(true);
    panStart.current = { x: e.clientX, y: e.clientY, tx: translate.x, ty: translate.y };
  }, [translate]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!isPanning) return;
    const dx = e.clientX - panStart.current.x;
    const dy = e.clientY - panStart.current.y;
    setTranslate({ x: panStart.current.tx + dx, y: panStart.current.ty + dy });
  }, [isPanning]);

  const handleMouseUp = useCallback(() => setIsPanning(false), []);

  if (isLoading) return <LoadingScreen label="جارٍ تحميل الهيكل التنظيمي…" />;
  if (error) return <ErrorState title="تعذر تحميل الهيكل" onRetry={() => refetch()} />;

  const employees = data?.employees ?? [];
  const tree = data?.tree ?? [];
  const stats = data?.stats ?? { totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 };

  return (
    <div className="space-y-6">
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

      {/* بطاقات الإحصائيات */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <MetricCard label="إجمالي الموظفين" value={stats.totalEmployees} icon={Users} />
        <MetricCard label="عدد المديرين" value={stats.managersCount} icon={GitBranch} />
        <MetricCard label="أقصى عمق هرمي" value={stats.maxDepth} icon={GitBranch} />
        <MetricCard label="متوسط المرؤوسين" value={stats.avgDirectReports} icon={Users} />
      </div>

      {/* البحث */}
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالاسم أو الكود أو المسمى الوظيفي أو القسم…"
        resultText={`${employees.length} موظف`}
        isDirty={search.trim().length > 0}
        onClear={() => setSearch('')}
      />

      {/* أزرار التحكم في العرض */}
      <div className="flex items-center gap-2 rounded-lg border border-[var(--border-color)] bg-[var(--surface)] px-3 py-2">
        <button type="button" className="btn btn-xs btn-ghost" onClick={zoomOut} aria-label="تصغير" title="تصغير">
          <Minus className="size-4" aria-hidden="true" />
        </button>
        <span className="min-w-[3rem] text-center text-sm font-medium text-[var(--text-secondary)]">
          {Math.round(scale * 100)}%
        </span>
        <button type="button" className="btn btn-xs btn-ghost" onClick={zoomIn} aria-label="تكبير" title="تكبير">
          <Plus className="size-4" aria-hidden="true" />
        </button>
        <div className="mx-1 h-4 w-px bg-[var(--border-color)]" aria-hidden="true" />
        <button type="button" className="btn btn-xs btn-ghost" onClick={fitToScreen} title="ملاءمة الشاشة">
          <Maximize2 className="size-4" aria-hidden="true" />
          <span className="hidden sm:inline">ملاءمة</span>
        </button>
        <button type="button" className="btn btn-xs btn-ghost" onClick={resetView} title="إعادة تعيين">
          <Minimize2 className="size-4" aria-hidden="true" />
          <span className="hidden sm:inline">إعادة</span>
        </button>
        <div className="mr-auto text-xs text-[var(--text-muted)]">
          Ctrl + Scroll للتكبير · اسحب للتحريك
        </div>
      </div>

      {/* الشجرة — حاوية قابلة للتحريك والتكبير */}
      {tree.length === 0 ? (
        <EmptyState title="لا توجد بيانات" description="لم يتم العثور على موظفين نشطين في الهيكل التنظيمي." />
      ) : (
        <div
          className="org-tree-viewport"
          style={{ cursor: isPanning ? 'grabbing' : 'grab' }}
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
        >
          <div
            ref={treeRef}
            className="org-tree"
            role="tree"
            style={{
              transform: `translate(${translate.x}px, ${translate.y}px) scale(${scale})`,
              transformOrigin: 'top center',
            }}
          >
            {tree.map((node) => (
              <EmployeeCardNode
                key={node.employee.id}
                node={node}
                onNavigate={(id) => navigate(`/admin/hr/employees/${id}`)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── عقدة البطاقة المتفرعة ───────────────────────────────────────────────────
function EmployeeCardNode({
  node,
  onNavigate,
  depth = 0,
}: {
  node: OrgChartTreeNode;
  onNavigate: (employeeId: string) => void;
  depth?: number;
}) {
  const [expanded, setExpanded] = useState(depth < 2);
  const emp = node.employee;
  const hasChildren = node.children.length > 0;
  const isRoot = depth === 0;

  return (
    <div className="org-node-wrapper" style={{ '--org-depth': depth } as React.CSSProperties}>
      {depth > 0 ? <div className="org-connector-vertical" aria-hidden="true" /> : null}

      <div className={`org-node ${isRoot ? 'is-root' : ''} ${hasChildren ? 'has-reports' : ''}`}>
        <button
          type="button"
          className="org-node-card"
          onClick={() => onNavigate(emp.id)}
          aria-label={`عرض ملف ${emp.fullNameAr}`}
        >
          <UserAvatar
            displayName={emp.fullNameAr}
            photoUrl={emp.photoUrl}
            size={isRoot ? 'lg' : 'md'}
            eager={depth < 2}
            announceName={false}
          />
          <div className="org-node-info">
            <span className="org-node-name">{emp.fullNameAr}</span>
            {emp.jobTitle ? <span className="org-node-title">{emp.jobTitle || 'غير محدد'}</span> : <span className="org-node-title text-[var(--text-muted)]">غير محدد</span>}
            <div className="org-node-meta">
              <span className="org-node-dept">{emp.departmentName || 'غير محدد'}</span>
              <span className="org-node-code">{emp.employeeCode}</span>
            </div>
          </div>
          {hasChildren ? (
            <span className="org-node-badge" aria-label={`${emp.directReportsCount} مرؤوسون`}>
              {emp.directReportsCount}
            </span>
          ) : null}
        </button>

        {hasChildren ? (
          <button
            type="button"
            className="org-toggle"
            onClick={() => setExpanded((v) => !v)}
            aria-expanded={expanded}
            aria-label={expanded ? 'طي المرؤوسين' : 'توسيع المرؤوسين'}
          >
            {expanded ? <ChevronDown className="size-4" /> : <ChevronLeft className="size-4" />}
          </button>
        ) : null}
      </div>

      {hasChildren && expanded ? (
        <div className="org-children" role="group">
          <div className="org-connector-horizontal" aria-hidden="true" />
          <div className="org-children-row">
            {node.children.map((child) => (
              <EmployeeCardNode
                key={child.employee.id}
                node={child}
                onNavigate={onNavigate}
                depth={depth + 1}
              />
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}
