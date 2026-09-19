import { useState, useMemo } from 'react';
import { useAssociationProjects, useAssociationProjectDetail } from './useAssociationProjects';
import { ProjectCard } from './ProjectCard';
import { ProjectDetailPanel } from './ProjectDetailPanel';
import { ProjectCreateDialog } from './ProjectCreateDialog';
import { PageHeader } from '../../ui/PageHeader';
import { MetricCard } from '../../ui/MetricCard';
import { FilterBar } from '../../ui/FilterBar';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
import { ErrorState } from '../../ui/ErrorState';
import { FolderKanban, Plus, CircleCheck, CircleMinus, CircleX } from 'lucide-react';

export function AssociationProjectsPage() {
  const { data, isLoading, error, refetch } = useAssociationProjects();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [createOpen, setCreateOpen] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const { data: detail } = useAssociationProjectDetail(selectedId);

  const filtered = useMemo(() => {
    if (!data?.projects) return [];
    return data.projects.filter((p) => {
      const matchSearch = !search || p.name.includes(search) || p.code.includes(search) || p.departmentName.includes(search);
      const matchStatus = statusFilter === 'all' || p.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [data, search, statusFilter]);

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
        description="لوحة تحكم شاملة بجميع مشاريع الجمعية مع مؤشرات الحالة"
        actions={
          <button onClick={() => setCreateOpen(true)} className="btn-primary flex items-center gap-2">
            <Plus className="w-4 h-4" /> مشروع جديد
          </button>
        }
      />

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard label="إجمالي المشاريع" value={stats.total} icon={FolderKanban} />
        <MetricCard label="نشطة" value={stats.active} icon={CircleCheck} hint="يتم تحديثها بانتظام" />
        <MetricCard label="متوقفة" value={stats.halted} icon={CircleMinus} hint="تحتاج متابعة" />
        <MetricCard label="مطفأة" value={stats.stale} icon={CircleX} hint="بدون تحديثات" />
      </div>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم أو الكود أو الإدارة..."
        resultText={`${filtered.length} من ${data?.projects.length ?? 0} مشروع`}
      >
        <div className="flex gap-2">
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
          description="لم يتم إنشاء أي مشاريع بعد"
          action={<button onClick={() => setCreateOpen(true)} className="btn-primary">إنشاء مشروع</button>}
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map((p) => (
            <ProjectCard key={p.id} project={p} onClick={() => setSelectedId(p.id)} />
          ))}
        </div>
      )}

      {createOpen && <ProjectCreateDialog onClose={() => setCreateOpen(false)} />}
      {detail && <ProjectDetailPanel detail={detail} onClose={() => setSelectedId(null)} onRefresh={refetch} />}
    </div>
  );
}
