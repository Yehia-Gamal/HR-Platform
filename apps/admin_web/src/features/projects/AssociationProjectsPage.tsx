import { useState, useMemo } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { useAssociationProjects, useAssociationProjectDetail } from './useAssociationProjects';
import { ProjectCard } from './ProjectCard';
import { ProjectDetailPanel } from './ProjectDetailPanel';
import { ProjectCreateDialog } from './ProjectCreateDialog';
import { QuickUpdateDialog } from './QuickUpdateDialog';
import { PageHeader } from '../../ui/PageHeader';
import { MetricCard } from '../../ui/MetricCard';
import { FilterBar } from '../../ui/FilterBar';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
import { ErrorState } from '../../ui/ErrorState';
import { FolderKanban, Plus, CircleCheck, CircleMinus, CircleX, LayoutGrid, List, ArrowUpDown } from 'lucide-react';

type SortKey = 'priority' | 'progress' | 'lastUpdate' | 'name';

const PRIORITY_ORDER: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 };

export function AssociationProjectsPage() {
  const { data, isLoading, error, refetch } = useAssociationProjects();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [ledFilter, setLedFilter] = useState('all');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [sortBy, setSortBy] = useState<SortKey>('priority');
  const [createOpen, setCreateOpen] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [quickUpdateProject, setQuickUpdateProject] = useState<AssociationProjectListItem | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const { data: detail } = useAssociationProjectDetail(selectedId);

  const filtered = useMemo(() => {
    if (!data?.projects) return [];
    const list = data.projects.filter((p) => {
      const matchSearch = !search || p.name.includes(search) || p.code.includes(search) || p.departmentName.includes(search) || p.ownerName.includes(search);
      const matchStatus = statusFilter === 'all' || p.status === statusFilter;
      const matchLed = ledFilter === 'all' || p.ledStatus === ledFilter;
      const matchPriority = priorityFilter === 'all' || p.priority === priorityFilter;
      return matchSearch && matchStatus && matchLed && matchPriority;
    });

    const sorted = [...list];
    switch (sortBy) {
      case 'priority':
        sorted.sort((a, b) => (PRIORITY_ORDER[a.priority] ?? 99) - (PRIORITY_ORDER[b.priority] ?? 99));
        break;
      case 'progress':
        sorted.sort((a, b) => b.progress - a.progress);
        break;
      case 'lastUpdate':
        sorted.sort((a, b) => {
          if (!a.lastUpdateAt) return 1;
          if (!b.lastUpdateAt) return -1;
          return new Date(b.lastUpdateAt).getTime() - new Date(a.lastUpdateAt).getTime();
        });
        break;
      case 'name':
        sorted.sort((a, b) => a.name.localeCompare(b.name, 'ar'));
        break;
    }
    return sorted;
  }, [data, search, statusFilter, ledFilter, priorityFilter, sortBy]);

  const stats = useMemo(() => {
    const all = data?.projects ?? [];
    return {
      total: all.length,
      active: all.filter((p) => p.ledStatus === 'active').length,
      halted: all.filter((p) => p.ledStatus === 'halted').length,
      stale: all.filter((p) => p.ledStatus === 'stale').length,
    };
  }, [data]);

  if (isLoading) return <ListSkeleton />;
  if (error) return <ErrorState />;

  return (
    <div className="space-y-6">
      <PageHeader
        title="مشاريع الجمعية"
        description="لوحة تحكم شاملة بجميع مشاريع الجمعية مع مؤشرات LED للحالة"
        actions={
          <div className="flex items-center gap-2">
            <div className="flex bg-gray-100 dark:bg-gray-800 rounded-lg p-0.5">
              <button onClick={() => setViewMode('grid')} className={`p-1.5 rounded ${viewMode === 'grid' ? 'bg-white dark:bg-gray-700 shadow' : ''}`} title="شبكة">
                <LayoutGrid className="w-4 h-4" />
              </button>
              <button onClick={() => setViewMode('list')} className={`p-1.5 rounded ${viewMode === 'list' ? 'bg-white dark:bg-gray-700 shadow' : ''}`} title="قائمة">
                <List className="w-4 h-4" />
              </button>
            </div>
            <button onClick={() => setCreateOpen(true)} className="btn-primary flex items-center gap-2">
              <Plus className="w-4 h-4" /> مشروع جديد
            </button>
          </div>
        }
      />

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard label="إجمالي المشاريع" value={stats.total} icon={FolderKanban} />
        <MetricCard label="نشطة" value={stats.active} icon={CircleCheck} hint="يتم تحديثها بانتظام" />
        <MetricCard label="متوقفة" value={stats.halted} icon={CircleMinus} hint="تحتاج متابعة" />
        <MetricCard label="مطفأة" value={stats.stale} icon={CircleX} hint="بدون تحديثات" />
      </div>

      <div className="flex gap-3 flex-wrap items-center">
        <span className="text-sm font-medium text-gray-500">LED:</span>
        {[
          { key: 'all', label: 'الكل', dot: '' },
          { key: 'active', label: 'نشط', dot: 'bg-emerald-500 shadow-[0_0_6px_2px_rgba(16,185,129,0.5)]' },
          { key: 'halted', label: 'متوقف', dot: 'bg-red-500 shadow-[0_0_6px_2px_rgba(239,68,68,0.5)]' },
          { key: 'stale', label: 'مطفأ', dot: 'bg-gray-400' },
        ].map((f) => (
          <button
            key={f.key}
            onClick={() => setLedFilter(f.key)}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-medium transition-all ${
              ledFilter === f.key
                ? 'bg-gray-200 dark:bg-gray-700 ring-2 ring-offset-1 ring-gray-300 dark:ring-gray-600'
                : 'bg-gray-50 text-gray-500 hover:bg-gray-100 dark:bg-gray-800 dark:hover:bg-gray-700'
            }`}
          >
            {f.dot && <span className={`w-2.5 h-2.5 rounded-full ${f.dot}`} />}
            {f.label}
          </button>
        ))}

        <span className="text-gray-300 dark:text-gray-600 mx-1">|</span>

        <span className="text-sm font-medium text-gray-500">الأولوية:</span>
        {[
          { key: 'all', label: 'الكل' },
          { key: 'critical', label: 'حرجة' },
          { key: 'high', label: 'عالية' },
          { key: 'medium', label: 'متوسطة' },
          { key: 'low', label: 'منخفضة' },
        ].map((f) => (
          <button
            key={f.key}
            onClick={() => setPriorityFilter(f.key)}
            className={`px-3 py-1.5 rounded-full text-xs font-medium transition-all ${
              priorityFilter === f.key
                ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                : 'bg-gray-50 text-gray-500 hover:bg-gray-100 dark:bg-gray-800 dark:hover:bg-gray-700'
            }`}
          >
            {f.label}
          </button>
        ))}

        <span className="text-gray-300 dark:text-gray-600 mx-1">|</span>

        <span className="text-sm font-medium text-gray-500 flex items-center gap-1">
          <ArrowUpDown className="w-3.5 h-3.5" /> ترتيب:
        </span>
        {[
          { key: 'priority', label: 'الأولوية' },
          { key: 'progress', label: 'التقدم' },
          { key: 'lastUpdate', label: 'آخر تحديث' },
          { key: 'name', label: 'الاسم' },
        ].map((f) => (
          <button
            key={f.key}
            onClick={() => setSortBy(f.key as SortKey)}
            className={`px-3 py-1.5 rounded-full text-xs font-medium transition-all ${
              sortBy === f.key
                ? 'bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400'
                : 'bg-gray-50 text-gray-500 hover:bg-gray-100 dark:bg-gray-800 dark:hover:bg-gray-700'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم أو الكود أو الإدارة أو المسؤول..."
        resultText={`${filtered.length} من ${data?.projects.length ?? 0} مشروع`}
      >
        <div className="flex gap-2 flex-wrap">
          {[
            { key: 'all', label: 'الكل' },
            { key: 'active', label: 'نشط' },
            { key: 'on_hold', label: 'متوقف' },
            { key: 'completed', label: 'مكتمل' },
            { key: 'planned', label: 'مخطط' },
          ].map((f) => (
            <button
              key={f.key}
              onClick={() => setStatusFilter(f.key)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                statusFilter === f.key
                  ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-400'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </FilterBar>

      {filtered.length === 0 ? (
        <EmptyState
          title="لا توجد مشاريع"
          description="لم يتم إنشاء أي مشاريع بعد أو لا توجد نتائج مطابقة للبحث"
          action={<button onClick={() => setCreateOpen(true)} className="btn-primary">إنشاء مشروع</button>}
        />
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map((p) => (
            <ProjectCard
              key={p.id}
              project={p}
              onClick={() => setSelectedId(p.id)}
              onQuickUpdate={setQuickUpdateProject}
            />
          ))}
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((p) => (
            <div
              key={p.id}
              className="w-full text-right flex items-center gap-4 p-4 rounded-lg border bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors cursor-pointer"
              onClick={() => setSelectedId(p.id)}
            >
              <div className={`w-3 h-3 rounded-full shrink-0 ${
                p.ledStatus === 'active' ? 'bg-emerald-500 shadow-[0_0_8px_2px_rgba(16,185,129,0.5)] animate-pulse' :
                p.ledStatus === 'halted' ? 'bg-red-500 shadow-[0_0_8px_2px_rgba(239,68,68,0.5)]' :
                'bg-gray-400'
              }`} />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-sm truncate">{p.name}</span>
                  <span className="text-xs text-gray-400 font-mono">{p.code}</span>
                </div>
                <span className="text-xs text-gray-500">{p.departmentName} — {p.ownerName}</span>
              </div>
              <div className="flex items-center gap-4 text-xs text-gray-500 shrink-0">
                <span>{p.progress}%</span>
                <span>{p.remainingSteps} خطوة</span>
              </div>
              <div className="w-24 bg-gray-200 dark:bg-gray-700 rounded-full h-1.5 shrink-0">
                <div className={`h-1.5 rounded-full ${p.ledStatus === 'active' ? 'bg-emerald-500' : p.ledStatus === 'halted' ? 'bg-red-500' : 'bg-gray-400'}`} style={{ width: `${p.progress}%` }} />
              </div>
              {p.ledStatus !== 'stale' && (
                <button
                  onClick={(e) => { e.stopPropagation(); setQuickUpdateProject(p); }}
                  className="p-1.5 rounded-lg bg-emerald-50 text-emerald-600 hover:bg-emerald-100 dark:bg-emerald-900/20 dark:hover:bg-emerald-900/40 transition-colors shrink-0"
                  title="تحديث سريع"
                >
                  ⚡
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {createOpen && <ProjectCreateDialog onClose={() => setCreateOpen(false)} />}
      {detail && <ProjectDetailPanel detail={detail} onClose={() => setSelectedId(null)} onRefresh={refetch} />}
      {quickUpdateProject && (
        <QuickUpdateDialog project={quickUpdateProject} onClose={() => { setQuickUpdateProject(null); refetch(); }} />
      )}
    </div>
  );
}
