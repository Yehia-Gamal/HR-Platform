import { useState } from 'react';
import { useNavigate } from 'react-router';
import { ChevronDown, ChevronLeft, GitBranch, RefreshCw, Users } from 'lucide-react';
import type { OrgChartTreeNode } from '@ahla/shared-contracts';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { useOrgChart } from './useOrgChart';

export function OrgChartPage() {
  const [search, setSearch] = useState('');
  const { data, isLoading, error, refetch } = useOrgChart(search);
  const navigate = useNavigate();

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

      {/* الشجرة */}
      {tree.length === 0 ? (
        <EmptyState title="لا توجد بيانات" description="لم يتم العثور على موظفين نشطين في الهيكل التنظيمي." />
      ) : (
        <div className="org-tree" role="tree">
          {tree.map((node) => (
            <EmployeeCardNode
              key={node.employee.id}
              node={node}
              onNavigate={(id) => navigate(`/admin/hr/employees/${id}`)}
            />
          ))}
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
      {/* خط الربط العمودي من الأب */}
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
            {emp.jobTitle ? <span className="org-node-title">{emp.jobTitle}</span> : null}
            <div className="org-node-meta">
              {emp.departmentName ? <span className="org-node-dept">{emp.departmentName}</span> : null}
              <span className="org-node-code">{emp.employeeCode}</span>
            </div>
          </div>
          {hasChildren ? (
            <span className="org-node-badge" aria-label={`${emp.directReportsCount} مرؤوسون`}>
              {emp.directReportsCount}
            </span>
          ) : null}
        </button>

        {/* زر التوسيع/الطي */}
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

      {/* الأبناء المباشرون */}
      {hasChildren && expanded ? (
        <div className="org-children" role="group">
          {/* خط أفقي يربط الأبناء بالأب */}
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
