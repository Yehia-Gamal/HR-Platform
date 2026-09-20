import { useState, useMemo, useCallback } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import {
  useAssociationProjects,
  useAssociationProjectDetail,
  useUpdateProjectStatus,
  useSubmitProjectForApproval,
  useApproveProject,
  useRejectProject,
} from './useAssociationProjects';
import { ProjectCard } from './ProjectCard';
import { ProjectDetailPanel } from './ProjectDetailPanel';
import { ProjectCreateDialog } from './ProjectCreateDialog';
import { QuickUpdateDialog } from './QuickUpdateDialog';
import { ActivityFeed } from './ActivityFeed';
import { ProjectCompare, CompareSelector } from './ProjectCompare';
import { useKeyboardShortcuts } from './useKeyboardShortcuts';
import { exportProjectsCsv, exportProjectsPdf } from './exportProjects';
import { APPROVAL_LABELS, APPROVAL_COLORS } from './projectLedStatus';
import { PageHeader } from '../../ui/PageHeader';
import { MetricCard } from '../../ui/MetricCard';
import { FilterBar } from '../../ui/FilterBar';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
import { ErrorState } from '../../ui/ErrorState';
import { BulkActionBar } from '../../ui/BulkActionBar';
import { DialogOverlay } from '../../ui/DialogOverlay';
import {
  FolderKanban,
  Plus,
  CircleCheck,
  CircleMinus,
  CircleX,
  LayoutGrid,
  List,
  ArrowUpDown,
  Download,
  FileText,
  ArrowLeftRight,
  Activity,
  CheckSquare,
  Keyboard,
  Send,
  Check,
  X,
  Clock,
  AlertTriangle,
} from 'lucide-react';

type SortKey = 'priority' | 'progress' | 'lastUpdate' | 'name';

const PRIORITY_ORDER: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 };

type Tab = 'projects' | 'activity' | 'shortcuts' | 'pending';

export function AssociationProjectsPage() {
  const { data, isLoading, error, refetch } = useAssociationProjects();
  const updateStatus = useUpdateProjectStatus();
  const submitForApproval = useSubmitProjectForApproval();
  const approveProject = useApproveProject();
  const rejectProject = useRejectProject();

  const isFullAccess = data?.isFullAccess ?? false;

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [ledFilter, setLedFilter] = useState('all');
  const [priorityFilter] = useState('all');
  const [approvalFilter, setApprovalFilter] = useState('all');
  const [sortBy, setSortBy] = useState<SortKey>('priority');
  const [createOpen, setCreateOpen] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [quickUpdateProject, setQuickUpdateProject] = useState<AssociationProjectListItem | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const [activeTab, setActiveTab] = useState<Tab>('projects');

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [compareOpen, setCompareOpen] = useState(false);
  const [compareData, setCompareData] = useState<{ a: AssociationProjectListItem; b: AssociationProjectListItem } | null>(null);
  const [exportMenuOpen, setExportMenuOpen] = useState(false);
  const [rejectDialogProject, setRejectDialogProject] = useState<AssociationProjectListItem | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  const { data: detail } = useAssociationProjectDetail(selectedId);

  const filtered = useMemo(() => {
    if (!data?.projects) return [];
    const list = data.projects.filter((p) => {
      const matchSearch = !search || p.name.includes(search) || p.code.includes(search) || p.departmentName.includes(search) || p.ownerName.includes(search);
      const matchStatus = statusFilter === 'all' || p.status === statusFilter;
      const matchLed = ledFilter === 'all' || p.ledStatus === ledFilter;
      const matchPriority = priorityFilter === 'all' || p.priority === priorityFilter;
      const matchApproval = approvalFilter === 'all' || p.approvalStatus === approvalFilter;
      return matchSearch && matchStatus && matchLed && matchPriority && matchApproval;
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
  }, [data, search, statusFilter, ledFilter, priorityFilter, approvalFilter, sortBy]);

  const stats = useMemo(() => {
    const all = data?.projects ?? [];
    return {
      total: all.length,
      active: all.filter((p) => p.ledStatus === 'active').length,
      halted: all.filter((p) => p.ledStatus === 'halted').length,
      stale: all.filter((p) => p.ledStatus === 'stale').length,
      pending: all.filter((p) => p.approvalStatus === 'pending_approval').length,
      draft: all.filter((p) => p.approvalStatus === 'draft').length,
      rejected: all.filter((p) => p.approvalStatus === 'rejected').length,
    };
  }, [data]);

  const pendingProjects = useMemo(() => {
    return (data?.projects ?? []).filter((p) => p.approvalStatus === 'pending_approval');
  }, [data]);

  // عمليات مجمّعة
  const allProjects = data?.projects ?? [];
  const selectedVisible = filtered.filter((p) => selectedIds.has(p.id));
  const allVisibleSelected = filtered.length > 0 && selectedVisible.length === filtered.length;

  const toggleSelect = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleSelectAll = useCallback(() => {
    if (allVisibleSelected) setSelectedIds(new Set());
    else setSelectedIds(new Set(filtered.map((p) => p.id)));
  }, [allVisibleSelected, filtered]);

  const bulkSetActive = useCallback(async () => {
    for (const id of selectedIds) await updateStatus.mutateAsync({ projectId: id, status: 'active' });
    setSelectedIds(new Set());
    refetch();
  }, [selectedIds, updateStatus, refetch]);

  const bulkSetOnHold = useCallback(async () => {
    for (const id of selectedIds) await updateStatus.mutateAsync({ projectId: id, status: 'on_hold' });
    setSelectedIds(new Set());
    refetch();
  }, [selectedIds, updateStatus, refetch]);

  const handleApprove = useCallback(
    async (projectId: string) => {
      await approveProject.mutateAsync(projectId);
      refetch();
    },
    [approveProject, refetch],
  );

  const handleReject = useCallback(async () => {
    if (!rejectDialogProject) return;
    await rejectProject.mutateAsync({ projectId: rejectDialogProject.id, reason: rejectReason });
    setRejectDialogProject(null);
    setRejectReason('');
    refetch();
  }, [rejectDialogProject, rejectReason, rejectProject, refetch]);

  // اختصارات لوحة المفاتيح
  useKeyboardShortcuts([
    { key: 'n', action: () => setCreateOpen(true), description: 'مشروع جديد' },
    { key: 'e', action: () => setExportMenuOpen(true), description: 'تصدير' },
    { key: 'c', action: () => setCompareOpen(true), description: 'مقارنة' },
    { key: 'a', action: () => toggleSelectAll(), description: 'تحديد الكل' },
    { key: '1', action: () => setActiveTab('projects'), description: 'المشاريع' },
    { key: '2', action: () => setActiveTab('pending'), description: 'بانتظار الموافقة' },
    { key: '3', action: () => setActiveTab('activity'), description: 'النشاطات' },
    { key: '4', action: () => setActiveTab('shortcuts'), description: 'الاختصارات' },
    {
      key: 'Escape',
      action: () => {
        setSelectedIds(new Set());
        setExportMenuOpen(false);
      },
      description: 'إلغاء التحديد',
    },
  ]);

  if (isLoading) return <ListSkeleton />;
  if (error) return <ErrorState title="تعذّر تحميل البيانات" description={error.message || String(error)} onRetry={() => void refetch()} />;

  return (
    <div className="space-y-6">
      <PageHeader
        title="مشاريع الجمعية"
        description={isFullAccess ? 'لوحة تحكم شاملة بجميع مشاريع الجمعية' : 'مشاريعي وإدارة المشاريع'}
        actions={
          <div className="flex items-center gap-2 flex-wrap">
            <div className="flex bg-gray-100 dark:bg-gray-800 rounded-lg p-0.5">
              {[
                { key: 'projects' as Tab, label: 'المشاريع', icon: FolderKanban },
                ...(isFullAccess ? [{ key: 'pending' as Tab, label: `بانتظار الموافقة (${stats.pending})`, icon: Clock }] : []),
                { key: 'activity' as Tab, label: 'النشاطات', icon: Activity },
                { key: 'shortcuts' as Tab, label: 'الاختصارات', icon: Keyboard },
              ].map((t) => (
                <button
                  key={t.key}
                  onClick={() => setActiveTab(t.key)}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded text-xs font-medium transition-colors ${
                    activeTab === t.key
                      ? 'bg-white dark:bg-gray-700 shadow text-emerald-600 dark:text-emerald-400'
                      : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'
                  }`}
                >
                  <t.icon className="w-3.5 h-3.5" />
                  <span className="hidden sm:inline">{t.label}</span>
                </button>
              ))}
            </div>

            <div className="relative">
              <button
                onClick={() => setExportMenuOpen(!exportMenuOpen)}
                className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                title="تصدير"
              >
                <Download className="w-4 h-4" />
              </button>
              {exportMenuOpen && (
                <div className="absolute left-0 mt-2 w-48 bg-white dark:bg-gray-800 border rounded-lg shadow-xl z-50 py-1">
                  <button
                    onClick={() => {
                      exportProjectsCsv(filtered);
                      setExportMenuOpen(false);
                    }}
                    className="w-full text-right px-4 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-700 flex items-center gap-2"
                  >
                    <Download className="w-4 h-4" /> تصدير CSV
                  </button>
                  <button
                    onClick={() => {
                      exportProjectsPdf(filtered);
                      setExportMenuOpen(false);
                    }}
                    className="w-full text-right px-4 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-700 flex items-center gap-2"
                  >
                    <FileText className="w-4 h-4" /> تصدير PDF
                  </button>
                </div>
              )}
            </div>

            <button
              onClick={() => setCompareOpen(true)}
              className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
              title="مقارنة"
            >
              <ArrowLeftRight className="w-4 h-4" />
            </button>

            <div className="flex bg-gray-100 dark:bg-gray-800 rounded-lg p-0.5">
              <button
                onClick={() => setViewMode('grid')}
                className={`p-1.5 rounded ${viewMode === 'grid' ? 'bg-white dark:bg-gray-700 shadow' : ''}`}
                title="شبكة"
              >
                <LayoutGrid className="w-4 h-4" />
              </button>
              <button
                onClick={() => setViewMode('list')}
                className={`p-1.5 rounded ${viewMode === 'list' ? 'bg-white dark:bg-gray-700 shadow' : ''}`}
                title="قائمة"
              >
                <List className="w-4 h-4" />
              </button>
            </div>

            <button onClick={() => setCreateOpen(true)} className="btn-primary flex items-center gap-2">
              <Plus className="w-4 h-4" /> مشروع جديد
            </button>
          </div>
        }
      />

      {/* تبويب بانتظار الموافقة — المدير التنفيذي فقط */}
      {activeTab === 'pending' && isFullAccess && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Clock className="w-5 h-5 text-amber-500" />
            <h2 className="font-extrabold text-lg">مشاريع بانتظار الموافقة ({pendingProjects.length})</h2>
          </div>
          {pendingProjects.length === 0 ? (
            <EmptyState title="لا توجد مشاريع بانتظار الموافقة" description="لم يتم تقديم أي مشاريع للموافقة بعد" />
          ) : (
            <div className="space-y-3">
              {pendingProjects.map((p) => (
                <div
                  key={p.id}
                  className="flex items-center gap-4 p-4 rounded-xl border-2 border-amber-200 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-950/20"
                >
                  <div className="w-3 h-3 rounded-full bg-amber-500 shadow-[0_0_8px_2px_rgba(245,158,11,0.5)] animate-pulse shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-bold">{p.name}</span>
                      <span className="text-xs text-gray-400 font-mono">{p.code}</span>
                    </div>
                    <span className="text-sm text-gray-500">
                      {p.departmentName} — {p.ownerName}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <button
                      onClick={() => handleApprove(p.id)}
                      className="flex items-center gap-1.5 px-4 py-2 bg-emerald-500 text-white rounded-lg hover:bg-emerald-600 transition-colors text-sm font-medium"
                    >
                      <Check className="w-4 h-4" /> موافقة
                    </button>
                    <button
                      onClick={() => {
                        setRejectDialogProject(p);
                        setRejectReason('');
                      }}
                      className="flex items-center gap-1.5 px-4 py-2 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors text-sm font-medium"
                    >
                      <X className="w-4 h-4" /> رفض
                    </button>
                    <button
                      onClick={() => setSelectedId(p.id)}
                      className="flex items-center gap-1.5 px-3 py-2 bg-gray-100 dark:bg-gray-800 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors text-sm"
                    >
                      التفاصيل
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* تبويب النشاطات */}
      {activeTab === 'activity' && (
        <div className="bg-white dark:bg-gray-900 rounded-xl border p-6">
          <h2 className="font-extrabold text-lg mb-4">سجل النشاطات</h2>
          <ActivityFeed projects={allProjects} />
        </div>
      )}

      {/* تبويب الاختصارات */}
      {activeTab === 'shortcuts' && (
        <div className="bg-white dark:bg-gray-900 rounded-xl border p-6">
          <h2 className="font-extrabold text-lg mb-4">اختصارات لوحة المفاتيح</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
            {[
              { key: 'N', desc: 'مشروع جديد' },
              { key: 'E', desc: 'قائمة التصدير' },
              { key: 'C', desc: 'مقارنة مشاريع' },
              { key: 'A', desc: 'تحديد/إلغاء الكل' },
              { key: '1', desc: 'تبويب المشاريع' },
              ...(isFullAccess ? [{ key: '2', desc: 'بانتظار الموافقة' }] : []),
              { key: isFullAccess ? '3' : '2', desc: 'النشاطات' },
              { key: isFullAccess ? '4' : '3', desc: 'الاختصارات' },
              { key: 'Esc', desc: 'إلغاء التحديد' },
            ].map((s) => (
              <div key={s.key} className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                <kbd className="px-2 py-1 bg-white dark:bg-gray-700 border rounded text-xs font-mono font-bold shadow-sm min-w-[2rem] text-center">{s.key}</kbd>
                <span className="text-sm text-gray-600 dark:text-gray-400">{s.desc}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* تبويب المشاريع الرئيسي */}
      {activeTab === 'projects' && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
            <MetricCard label="إجمالي" value={stats.total} icon={FolderKanban} />
            <MetricCard label="نشطة" value={stats.active} icon={CircleCheck} />
            <MetricCard label="متوقفة" value={stats.halted} icon={CircleMinus} />
            <MetricCard label="مطفأة" value={stats.stale} icon={CircleX} />
            {isFullAccess && <MetricCard label="بانتظار الموافقة" value={stats.pending} icon={Clock} />}
            <MetricCard label="مسودات" value={stats.draft} icon={AlertTriangle} />
            <MetricCard label="مرفوضة" value={stats.rejected} icon={X} />
          </div>

          <div className="flex gap-3 flex-wrap items-center">
            <span className="text-sm font-medium text-gray-500">LED:</span>
            {[
              { key: 'all', label: 'الكل', dot: '' },
              { key: 'active', label: 'نشط', dot: 'bg-emerald-500 shadow-[0_0_6px_2px_rgba(16,185,129,0.5)]' },
              { key: 'halted', label: 'متوقف', dot: 'bg-red-500 shadow-[0_0_6px_2px_rgba(239,68,68,0.5)]' },
              { key: 'stale', label: 'مطفأ', dot: 'bg-gray-400' },
              { key: 'pending', label: 'بانتظار', dot: 'bg-amber-500 shadow-[0_0_6px_2px_rgba(245,158,11,0.5)]' },
              { key: 'draft', label: 'مسودة', dot: 'bg-slate-400' },
              { key: 'rejected', label: 'مرفوض', dot: 'bg-rose-500' },
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

            <span className="text-sm font-medium text-gray-500">الحالة:</span>
            {[
              { key: 'all', label: 'الكل' },
              { key: 'draft', label: 'مسودة' },
              { key: 'pending_approval', label: 'بانتظار' },
              { key: 'approved', label: 'معتمد' },
              { key: 'rejected', label: 'مرفوض' },
            ].map((f) => (
              <button
                key={f.key}
                onClick={() => setApprovalFilter(f.key)}
                className={`px-3 py-1.5 rounded-full text-xs font-medium transition-all ${
                  approvalFilter === f.key
                    ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400'
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
            <div className="flex gap-2 flex-wrap items-center">
              <button
                onClick={toggleSelectAll}
                className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                  allVisibleSelected
                    ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-400'
                }`}
              >
                <CheckSquare className="w-3.5 h-3.5" />
                {allVisibleSelected ? 'إلغاء التحديد' : `تحديد الكل (${filtered.length})`}
              </button>

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
              action={
                <button onClick={() => setCreateOpen(true)} className="btn-primary">
                  إنشاء مشروع
                </button>
              }
            />
          ) : viewMode === 'grid' ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 md:gap-5">
              {filtered.map((p) => (
                <div key={p.id} className="relative">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleSelect(p.id);
                    }}
                    className={`absolute top-3 left-3 z-10 w-5 h-5 rounded border-2 flex items-center justify-center transition-all ${
                      selectedIds.has(p.id)
                        ? 'bg-emerald-500 border-emerald-500 text-white'
                        : 'bg-white dark:bg-gray-800 border-gray-300 dark:border-gray-600 hover:border-emerald-400'
                    }`}
                  >
                    {selectedIds.has(p.id) && (
                      <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                  </button>

                  {/* شارة حالة الموافقة */}
                  {p.approvalStatus !== 'approved' && (
                    <div className={`absolute top-3 right-3 z-10 px-2 py-0.5 rounded-full text-xs font-bold ${APPROVAL_COLORS[p.approvalStatus]}`}>
                      {APPROVAL_LABELS[p.approvalStatus]}
                    </div>
                  )}

                  <ProjectCard
                    project={p}
                    onClick={() => setSelectedId(p.id)}
                    onQuickUpdate={p.approvalStatus === 'approved' ? setQuickUpdateProject : undefined}
                  />

                  {/* أزرار الموافقة للمدير التنفيذي */}
                  {isFullAccess && p.approvalStatus === 'pending_approval' && (
                    <div className="flex gap-2 mt-2">
                      <button
                        onClick={() => handleApprove(p.id)}
                        className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-emerald-500 text-white rounded-lg hover:bg-emerald-600 transition-colors text-sm font-medium"
                      >
                        <Check className="w-4 h-4" /> موافقة
                      </button>
                      <button
                        onClick={() => {
                          setRejectDialogProject(p);
                          setRejectReason('');
                        }}
                        className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors text-sm font-medium"
                      >
                        <X className="w-4 h-4" /> رفض
                      </button>
                    </div>
                  )}

                  {/* زر إرسال للموافقة للمالك */}
                  {!isFullAccess && (p.approvalStatus === 'draft' || p.approvalStatus === 'rejected') && (
                    <button
                      onClick={async () => {
                        await submitForApproval.mutateAsync(p.id);
                        refetch();
                      }}
                      className="w-full mt-2 flex items-center justify-center gap-1.5 py-2 bg-amber-500 text-white rounded-lg hover:bg-amber-600 transition-colors text-sm font-medium"
                    >
                      <Send className="w-4 h-4" /> إرسال للموافقة
                    </button>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="space-y-2">
              {filtered.map((p) => (
                <div
                  key={p.id}
                  className="w-full text-end flex items-center gap-4 p-3 md:p-4 rounded-lg border bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors cursor-pointer"
                  onClick={() => setSelectedId(p.id)}
                >
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleSelect(p.id);
                    }}
                    className={`w-5 h-5 rounded border-2 flex items-center justify-center shrink-0 transition-all ${
                      selectedIds.has(p.id)
                        ? 'bg-emerald-500 border-emerald-500 text-white'
                        : 'bg-white dark:bg-gray-800 border-gray-300 dark:border-gray-600 hover:border-emerald-400'
                    }`}
                  >
                    {selectedIds.has(p.id) && (
                      <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                  </button>

                  <div
                    className={`w-3 h-3 rounded-full shrink-0 ${
                      p.ledStatus === 'active'
                        ? 'bg-emerald-500 shadow-[0_0_8px_2px_rgba(16,185,129,0.5)] animate-pulse'
                        : p.ledStatus === 'halted'
                          ? 'bg-red-500 shadow-[0_0_8px_2px_rgba(239,68,68,0.5)]'
                          : p.ledStatus === 'pending'
                            ? 'bg-amber-500 shadow-[0_0_8px_2px_rgba(245,158,11,0.5)] animate-pulse'
                            : p.ledStatus === 'rejected'
                              ? 'bg-rose-500'
                              : p.ledStatus === 'draft'
                                ? 'bg-slate-400'
                                : 'bg-gray-400'
                    }`}
                  />

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-sm truncate">{p.name}</span>
                      <span className="text-xs text-gray-400 font-mono hidden sm:inline">{p.code}</span>
                      {p.approvalStatus !== 'approved' && (
                        <span className={`px-1.5 py-0.5 rounded text-xs font-bold ${APPROVAL_COLORS[p.approvalStatus]}`}>
                          {APPROVAL_LABELS[p.approvalStatus]}
                        </span>
                      )}
                    </div>
                    <span className="text-xs text-gray-500">
                      {p.departmentName} — {p.ownerName}
                    </span>
                  </div>

                  <div className="flex items-center gap-3 md:gap-4 text-xs text-gray-500 shrink-0">
                    <span className="hidden sm:inline">{p.progress}%</span>
                    <span>{p.remainingSteps} خطوة</span>
                  </div>

                  <div className="w-20 md:w-24 bg-gray-200 dark:bg-gray-700 rounded-full h-1.5 shrink-0 hidden sm:block">
                    <div
                      className={`h-1.5 rounded-full ${p.ledStatus === 'active' ? 'bg-emerald-500' : p.ledStatus === 'halted' ? 'bg-red-500' : p.ledStatus === 'pending' ? 'bg-amber-500' : 'bg-gray-400'}`}
                      style={{ width: `${p.progress}%` }}
                    />
                  </div>

                  {/* أزرار الموافقة */}
                  {isFullAccess && p.approvalStatus === 'pending_approval' && (
                    <div className="flex gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
                      <button
                        onClick={() => handleApprove(p.id)}
                        className="p-1.5 rounded-lg bg-emerald-50 text-emerald-600 hover:bg-emerald-100 transition-colors"
                        title="موافقة"
                      >
                        <Check className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => {
                          setRejectDialogProject(p);
                          setRejectReason('');
                        }}
                        className="p-1.5 rounded-lg bg-rose-50 text-rose-600 hover:bg-rose-100 transition-colors"
                        title="رفض"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                  )}

                  {!isFullAccess && (p.approvalStatus === 'draft' || p.approvalStatus === 'rejected') && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        submitForApproval.mutateAsync(p.id).then(() => refetch());
                      }}
                      className="p-1.5 rounded-lg bg-amber-50 text-amber-600 hover:bg-amber-100 transition-colors shrink-0"
                      title="إرسال للموافقة"
                    >
                      <Send className="w-4 h-4" />
                    </button>
                  )}

                  {p.approvalStatus === 'approved' && p.ledStatus !== 'stale' && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setQuickUpdateProject(p);
                      }}
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
        </>
      )}

      {/* شريط العمليات المجمّعة */}
      {selectedIds.size > 0 && (
        <BulkActionBar
          selectedCount={selectedIds.size}
          onClearSelection={() => setSelectedIds(new Set())}
          actions={[
            { label: 'تفعيل', icon: CircleCheck, onClick: bulkSetActive, tone: 'success' },
            { label: 'إيقاف', icon: CircleMinus, onClick: bulkSetOnHold },
          ]}
        />
      )}

      {/* النوافذ */}
      {createOpen && <ProjectCreateDialog onClose={() => setCreateOpen(false)} />}
      {detail && <ProjectDetailPanel detail={detail} onClose={() => setSelectedId(null)} onRefresh={refetch} />}
      {quickUpdateProject && (
        <QuickUpdateDialog
          project={quickUpdateProject}
          onClose={() => {
            setQuickUpdateProject(null);
            refetch();
          }}
        />
      )}
      {compareOpen && (
        <CompareSelector
          projects={allProjects}
          onClose={() => setCompareOpen(false)}
          onSelect={(a, b) => {
            setCompareOpen(false);
            setCompareData({ a, b });
          }}
        />
      )}
      {compareData && <ProjectCompare projectA={compareData.a} projectB={compareData.b} onClose={() => setCompareData(null)} />}
      {rejectDialogProject && (
        <DialogOverlay
          title="رفض المشروع"
          onClose={() => {
            setRejectDialogProject(null);
            setRejectReason('');
          }}
          maxWidth="max-w-md"
        >
          <div className="p-4 space-y-4">
            <p className="text-sm">
              هل أنت متأكد من رفض <strong>{rejectDialogProject.name}</strong>؟
            </p>
            <label className="block">
              <span className="text-sm font-medium">سبب الرفض (اختياري)</span>
              <textarea
                className="input mt-1 w-full"
                rows={2}
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="اكتب سبب الرفض..."
              />
            </label>
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => {
                  setRejectDialogProject(null);
                  setRejectReason('');
                }}
                className="btn-secondary"
              >
                إلغاء
              </button>
              <button onClick={handleReject} disabled={rejectProject.isPending} className="btn-danger">
                {rejectProject.isPending ? 'جاري الرفض...' : 'رفض المشروع'}
              </button>
            </div>
          </div>
        </DialogOverlay>
      )}
    </div>
  );
}
