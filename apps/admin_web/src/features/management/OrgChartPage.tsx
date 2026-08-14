import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router';
import {
  ChevronDown,
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
const MOBILE_BREAKPOINT = 768;

/** Hook بسيط لكشف الموبايل عبر matchMedia */
function useIsMobile() {
  const [isMobile, setIsMobile] = useState(
    typeof window !== 'undefined' ? window.innerWidth < MOBILE_BREAKPOINT : false,
  );
  useEffect(() => {
    const mq = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);
  return isMobile;
}

export function OrgChartPage() {
  const [search, setSearch] = useState('');
  const { data, isLoading, error, refetch } = useOrgChart(search);
  const navigate = useNavigate();
  const isMobile = useIsMobile();

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
      if (e.key === '+' || e.key === '=') { e.preventDefault(); zoomIn(); }
      else if (e.key === '-' || e.key === '_') { e.preventDefault(); zoomOut(); }
      else if (e.key === '0') { e.preventDefault(); resetView(); }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [isMobile, zoomIn, zoomOut, resetView]);

  // Pan handlers (desktop only)
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (isMobile) return;
    setIsPanning(true);
    panStart.current = { x: e.clientX, y: e.clientY, tx: translate.x, ty: translate.y };
  }, [translate, isMobile]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!isPanning || isMobile) return;
    const dx = e.clientX - panStart.current.x;
    const dy = e.clientY - panStart.current.y;
    setTranslate({ x: panStart.current.tx + dx, y: panStart.current.ty + dy });
  }, [isPanning, isMobile]);

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

      {/* أزرار التحكم في العرض — سطح المكتب فقط */}
      {!isMobile && (
        <div className="org-controls-toolbar flex items-center gap-2 rounded-lg border border-[var(--border-color)] bg-[var(--surface)] px-3 py-2">
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
            Ctrl + Scroll للتكبير · اسحب للتحريك · +/- للتكبير · 0 لإعادة
          </div>
        </div>
      )}

      {/* منطقة الشجرة — قابل للتكبير والسحب على سطح المكتب */}
      <div
        className="org-tree-container relative overflow-auto rounded-xl border border-[var(--border)] bg-[var(--surface)] p-6"
        style={{ minHeight: '60vh' }}
        onMouseDown={!isMobile ? handleMouseDown : undefined}
        onMouseMove={!isMobile ? handleMouseMove : undefined}
        onMouseUp={!isMobile ? handleMouseUp : undefined}
        onMouseLeave={!isMobile ? handleMouseUp : undefined}
      >
        {tree.length === 0 ? (
          <EmptyState title="لا توجد بيانات" description="لم يتم العثور على موظفين مطابقين للبحث." />
        ) : (
          <div
            ref={treeRef}
            className="origin-top mx-auto inline-block"
            style={{
              transform: `scale(${scale}) translate(${translate.x}px, ${translate.y}px)`,
              cursor: isPanning ? 'grabbing' : 'grab',
            }}
          >
            {tree.map((node) => (
              <OrgNode key={node.employee.id} node={node} depth={0} navigate={navigate} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

/** عقدة شجرة هرمية — تُرسم نفسها وموظفيها بشكل متكرر */
function OrgNode({ node, depth, navigate }: { node: OrgChartTreeNode; depth: number; navigate: (path: string) => void }) {
  const [expanded, setExpanded] = useState(depth < 2);
  const emp = node.employee;
  const hasChildren = node.children.length > 0;

  return (
    <div className="org-node inline-block text-center">
      <button
        type="button"
        className="org-card mx-auto mb-2 inline-flex flex-col items-center gap-1 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-3 shadow-sm transition hover:shadow-md"
        onClick={() => navigate(`/admin/hr/employees/${emp.id}`)}
        style={{ minWidth: '160px' }}
      >
        <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl ?? null} size="sm" />
        <span className="text-sm font-bold text-[var(--text-primary)]">{emp.fullNameAr}</span>
        {emp.jobTitle ? <span className="text-xs text-[var(--text-muted)]">{emp.jobTitle}</span> : null}
        {emp.departmentName ? <span className="text-xs text-[var(--text-muted)]">{emp.departmentName}</span> : null}
      </button>

      {hasChildren ? (
        <>
          <button
            type="button"
            className="mb-1 inline-flex size-6 items-center justify-center rounded-full border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-muted)] hover:text-[var(--text-primary)]"
            onClick={() => setExpanded((v) => !v)}
            aria-label={expanded ? 'طي' : 'توسيع'}
          >
            <ChevronDown className={`size-4 transition-transform ${expanded ? '' : 'rotate-180'}`} aria-hidden="true" />
          </button>
          {expanded ? (
            <div className="flex justify-center gap-4 border-t border-[var(--border)] pt-4">
              {node.children.map((child) => (
                <OrgNode key={child.employee.id} node={child} depth={depth + 1} navigate={navigate} />
              ))}
            </div>
          ) : null}
        </>
      ) : null}
    </div>
  );
}   
