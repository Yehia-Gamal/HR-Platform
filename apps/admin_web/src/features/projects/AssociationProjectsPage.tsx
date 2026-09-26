import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router';
import type { AssociationProjectListItem, ProjectLedStatus } from '@ahla/shared-contracts';
import { AlertTriangle, Check, Download, FileText, Plus, Search, Send, Settings2, X } from 'lucide-react';
import { PageHeader } from '../../ui/PageHeader';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAssociationProjects, useApproveProject, useRejectProject, useSubmitProjectForApproval } from './useAssociationProjects';
import { ProjectCard } from './ProjectCard';
import { ProjectLed } from './ProjectLed';
import { ProjectDetailPanel, RejectDialog } from './ProjectDetailPanel';
import { ProjectFormDialog } from './ProjectFormDialog';
import { ProjectSettingsDialog } from './ProjectSettingsDialog';
import { QuickUpdateDialog } from './QuickUpdateDialog';
import { ActivityFeed } from './ActivityFeed';
import { exportProjectsCsv, exportProjectsPdf } from './exportProjects';
import { APPROVAL_LABELS, LED_META, LED_URGENCY, PRIORITY_ORDER, activityDays, isOnBoard } from './projectLedStatus';

type Tab = 'board' | 'requests' | 'activity';
type SortKey = 'urgency' | 'priority' | 'progress' | 'name';
type LedFilter = 'all' | 'active' | 'halted' | 'critical' | 'completed';

const LED_TILES: { key: LedFilter; label: string }[] = [
  { key: 'all', label: 'كل المشاريع' },
  { key: 'active', label: 'تعمل بانتظام' },
  { key: 'halted', label: 'متوقفة' },
  { key: 'critical', label: 'تحتاج تدخل' },
  { key: 'completed', label: 'مكتملة' },
];

const SORTS: { key: SortKey; label: string }[] = [
  { key: 'urgency', label: 'الأحوج للمتابعة أولاً' },
  { key: 'priority', label: 'الأولوية' },
  { key: 'progress', label: 'نسبة الإنجاز' },
  { key: 'name', label: 'الاسم' },
];

function sortProjects(list: AssociationProjectListItem[], sort: SortKey): AssociationProjectListItem[] {
  const sorted = [...list];
  switch (sort) {
    case 'urgency':
      return sorted.sort((a, b) => LED_URGENCY[a.ledStatus] - LED_URGENCY[b.ledStatus] || (activityDays(b) ?? 9999) - (activityDays(a) ?? 9999));
    case 'priority':
      return sorted.sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);
    case 'progress':
      return sorted.sort((a, b) => b.progress - a.progress);
    case 'name':
      return sorted.sort((a, b) => a.name.localeCompare(b.name, 'ar'));
  }
}

export function AssociationProjectsPage() {
  const { data, isLoading, error, refetch } = useAssociationProjects();
  const [params, setParams] = useSearchParams();
  const approve = useApproveProject();
  const reject = useRejectProject();
  const submit = useSubmitProjectForApproval();

  const tab = (params.get('tab') as Tab | null) ?? 'board';
  const selectedId = params.get('project');
  const [ledFilter, setLedFilter] = useState<LedFilter>('all');
  const [search, setSearch] = useState('');
  const [department, setDepartment] = useState('all');
  const [sort, setSort] = useState<SortKey>('urgency');
  const [createOpen, setCreateOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [quickUpdate, setQuickUpdate] = useState<AssociationProjectListItem | null>(null);
  const [rejecting, setRejecting] = useState<AssociationProjectListItem | null>(null);

  const isFullAccess = data?.isFullAccess ?? false;
  const projects = useMemo(() => data?.projects ?? [], [data]);
  const board = useMemo(() => projects.filter(isOnBoard), [projects]);
  const requests = useMemo(() => projects.filter((p) => !isOnBoard(p)), [projects]);
  // المدير التنفيذي يهمه ما ينتظر قراره؛ الإدارة يهمها كل ما لم يُعتمد بعد.
  const actionableRequests = isFullAccess ? requests.filter((p) => p.approvalStatus === 'pending_approval') : requests;

  const counts = useMemo(() => {
    const c: Record<LedFilter, number> = { all: board.length, active: 0, halted: 0, critical: 0, completed: 0 };
    for (const p of board) if (p.ledStatus in c) c[p.ledStatus as LedFilter] += 1;
    return c;
  }, [board]);

  const departments = useMemo(() => {
    const map = new Map<string, string>();
    for (const p of board) map.set(p.departmentId, p.departmentName);
    return [...map.entries()].sort((a, b) => a[1].localeCompare(b[1], 'ar'));
  }, [board]);

  const visible = useMemo(() => {
    const q = search.trim();
    const list = board.filter(
      (p) =>
        (ledFilter === 'all' || p.ledStatus === ledFilter) &&
        (department === 'all' || p.departmentId === department) &&
        (!q || p.name.includes(q) || p.code.includes(q) || p.departmentName.includes(q) || p.ownerName.includes(q)),
    );
    return sortProjects(list, sort);
  }, [board, ledFilter, department, search, sort]);

  function setParam(key: string, value: string | null) {
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        if (value) next.set(key, value);
        else next.delete(key);
        return next;
      },
      { replace: key === 'tab' },
    );
  }
  const openProject = (id: string) => setParam('project', id);

  if (isLoading) return <ListSkeleton />;
  if (error) return <ErrorState description={safeErrorMessage(error)} onRetry={() => void refetch()} />;

  const tabs: { key: Tab; label: string; badge?: number }[] = [
    { key: 'board', label: 'لوحة المشاريع' },
    { key: 'requests', label: isFullAccess ? 'طلبات الاعتماد' : 'قيد الإعداد والاعتماد', badge: actionableRequests.length },
    { key: 'activity', label: 'آخر التحديثات' },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="مشاريع الجمعية"
        description={
          isFullAccess
            ? 'كل مشاريع الإدارات المعتمدة في مكان واحد — اللمبة تخبرك فوراً أي مشروع يعمل وأيها متوقف ويحتاج تدخلك.'
            : 'مشاريع إدارتك: أنشئ مشروعاً وأرسله للاعتماد، ثم تابع خطواته وسجّل التحديثات ليبقى أخضر.'
        }
        actions={
          <>
            {isFullAccess && (
              <button className="icon-button" onClick={() => setSettingsOpen(true)} aria-label="إعدادات لمبة التنبيه" title="إعدادات لمبة التنبيه">
                <Settings2 className="size-4" />
              </button>
            )}
            <div className="relative">
              <button className="icon-button" onClick={() => setExportOpen((o) => !o)} aria-label="تصدير" aria-expanded={exportOpen} title="تصدير">
                <Download className="size-4" />
              </button>
              {exportOpen && (
                <div className="card absolute end-0 z-30 mt-2 w-44 p-1" onMouseLeave={() => setExportOpen(false)}>
                  <button
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-[var(--surface-hover)]"
                    onClick={() => {
                      exportProjectsCsv(visible);
                      setExportOpen(false);
                    }}
                  >
                    <Download className="size-4" aria-hidden="true" /> ملف Excel (CSV)
                  </button>
                  <button
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-[var(--surface-hover)]"
                    onClick={() => {
                      exportProjectsPdf(visible);
                      setExportOpen(false);
                    }}
                  >
                    <FileText className="size-4" aria-hidden="true" /> تقرير للطباعة
                  </button>
                </div>
              )}
            </div>
            {(data?.canCreate ?? true) && (
              <button className="btn-primary" onClick={() => setCreateOpen(true)}>
                <Plus className="size-4" aria-hidden="true" /> مشروع جديد
              </button>
            )}
          </>
        }
      />

      {/* التبويبات */}
      <nav className="flex gap-2 overflow-x-auto" aria-label="أقسام المشاريع">
        {tabs.map((t) => (
          <button
            key={t.key}
            className={`filter-chip${tab === t.key ? ' is-active' : ''}`}
            aria-pressed={tab === t.key}
            onClick={() => setParam('tab', t.key === 'board' ? null : t.key)}
          >
            {t.label}
            {t.badge ? <span className="ms-1.5 rounded-full bg-[var(--warning)] px-1.5 text-xs font-black text-white">{t.badge}</span> : null}
          </button>
        ))}
      </nav>

      {tab === 'board' && (
        <>
          {counts.critical > 0 && ledFilter !== 'critical' && (
            <button
              onClick={() => setLedFilter('critical')}
              className="flex w-full items-center gap-3 rounded-2xl bg-[var(--danger-soft)] p-4 text-start text-[var(--danger)]"
            >
              <ProjectLed status="critical" large />
              <span className="flex-1 font-black">
                {counts.critical === 1 ? 'مشروع واحد' : `${counts.critical} مشاريع`} بلا أي تحديث منذ {data?.settings.criticalDays} يوماً أو أكثر
                {isFullAccess ? ' — تحتاج تدخلك' : ''}
              </span>
              <span className="text-sm font-bold underline">عرضها</span>
            </button>
          )}

          {/* ملخص اللمبات — كل بطاقة فلتر */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {LED_TILES.map((t) => (
              <button
                key={t.key}
                onClick={() => setLedFilter(t.key)}
                aria-pressed={ledFilter === t.key}
                className={`card flex items-center gap-3 p-4 text-start transition-colors ${ledFilter === t.key ? 'ring-2 ring-[var(--brand-primary)]' : 'hover:border-[var(--border-strong)]'}`}
              >
                {t.key === 'all' ? (
                  <span className="grid size-[1.15rem] place-items-center text-[var(--brand-primary)]">●</span>
                ) : (
                  <ProjectLed status={t.key as ProjectLedStatus} large />
                )}
                <span className="min-w-0">
                  <span className="tabular block text-2xl leading-none font-black">{counts[t.key]}</span>
                  <span className="mt-1 block text-xs font-bold text-[var(--text-muted)]">{t.label}</span>
                </span>
              </button>
            ))}
          </div>

          {/* بحث وفرز */}
          <div className="flex flex-col gap-3 md:flex-row">
            <label className="relative flex-1">
              <span className="sr-only">بحث</span>
              <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
              <input className="input !ps-9" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ابحث باسم المشروع أو الإدارة أو المسؤول" />
            </label>
            <select className="input md:!w-56" value={department} onChange={(e) => setDepartment(e.target.value)} aria-label="الإدارة">
              <option value="all">كل الإدارات</option>
              {departments.map(([id, name]) => (
                <option key={id} value={id}>
                  {name}
                </option>
              ))}
            </select>
            <select className="input md:!w-56" value={sort} onChange={(e) => setSort(e.target.value as SortKey)} aria-label="الترتيب">
              {SORTS.map((s) => (
                <option key={s.key} value={s.key}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>

          {visible.length === 0 ? (
            <EmptyState
              title={board.length === 0 ? 'لا توجد مشاريع معتمدة بعد' : 'لا توجد نتائج'}
              description={board.length === 0 ? 'عندما تُرسل الإدارات مشاريعها ويعتمدها المدير التنفيذي تظهر هنا بلمبة حالتها.' : 'جرّب تغيير الفلتر أو البحث.'}
              action={
                board.length === 0 && (data?.canCreate ?? true) ? (
                  <button className="btn-primary" onClick={() => setCreateOpen(true)}>
                    <Plus className="size-4" aria-hidden="true" /> مشروع جديد
                  </button>
                ) : undefined
              }
            />
          ) : (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              {visible.map((p) => (
                <ProjectCard
                  key={p.id}
                  project={p}
                  onOpen={() => openProject(p.id)}
                  onQuickUpdate={(isFullAccess || p.canManage) && p.status !== 'completed' && p.status !== 'cancelled' ? () => setQuickUpdate(p) : undefined}
                />
              ))}
            </div>
          )}
        </>
      )}

      {tab === 'requests' && (
        <section className="space-y-3">
          {requests.length === 0 ? (
            <EmptyState
              title={isFullAccess ? 'لا توجد طلبات اعتماد' : 'لا توجد مشاريع قيد الإعداد'}
              description={isFullAccess ? 'عندما ترسل إدارة مشروعاً جديداً يظهر هنا لتعتمده أو تعيده لها.' : 'ابدأ بإنشاء مشروع جديد لإدارتك وأرسله للاعتماد.'}
            />
          ) : (
            sortProjects(requests, 'urgency').map((p) => (
              <article key={p.id} className="card flex flex-col gap-3 p-4 sm:flex-row sm:items-center">
                <ProjectLed status={p.ledStatus} large />
                <button className="min-w-0 flex-1 text-start" onClick={() => openProject(p.id)}>
                  <span className="block font-black">{p.name}</span>
                  <span className="block text-xs text-[var(--text-muted)]">
                    {p.departmentName} • {p.ownerName} • <span style={{ color: LED_META[p.ledStatus].tone }}>{APPROVAL_LABELS[p.approvalStatus]}</span>
                  </span>
                  {p.rejectionReason && <span className="mt-1 block text-xs font-bold text-[var(--danger)]">ملاحظة المدير التنفيذي: {p.rejectionReason}</span>}
                </button>
                <div className="flex shrink-0 flex-wrap gap-2">
                  {isFullAccess && p.approvalStatus === 'pending_approval' && (
                    <>
                      <button className="btn-primary btn-sm" disabled={approve.isPending} onClick={() => approve.mutate(p.id)}>
                        <Check className="size-4" aria-hidden="true" /> اعتماد
                      </button>
                      <button className="btn-danger btn-sm" onClick={() => setRejecting(p)}>
                        <X className="size-4" aria-hidden="true" /> إعادة
                      </button>
                    </>
                  )}
                  {(p.approvalStatus === 'draft' || p.approvalStatus === 'rejected') && (isFullAccess || p.canManage) && (
                    <button className="btn-primary btn-sm" disabled={submit.isPending} onClick={() => submit.mutate(p.id)}>
                      <Send className="size-4" aria-hidden="true" /> إرسال للاعتماد
                    </button>
                  )}
                  <button className="btn-secondary btn-sm" onClick={() => openProject(p.id)}>
                    التفاصيل
                  </button>
                </div>
              </article>
            ))
          )}
        </section>
      )}

      {tab === 'activity' && <ActivityFeed activities={data?.recentUpdates ?? []} onOpenProject={openProject} />}

      {!isFullAccess && requests.some((p) => p.approvalStatus === 'rejected') && tab === 'board' && (
        <p className="flex items-center gap-2 text-sm font-bold text-[var(--danger)]">
          <AlertTriangle className="size-4" aria-hidden="true" /> لديك مشاريع أُعيدت للتعديل — راجع تبويب «قيد الإعداد والاعتماد».
        </p>
      )}

      {/* النوافذ */}
      {selectedId && (
        <ProjectDetailPanel
          key={selectedId}
          projectId={selectedId}
          isFullAccess={isFullAccess}
          myDepartmentId={data?.myDepartmentId ?? null}
          onClose={() => setParam('project', null)}
        />
      )}
      {createOpen && <ProjectFormDialog isFullAccess={isFullAccess} myDepartmentId={data?.myDepartmentId ?? null} onClose={() => setCreateOpen(false)} />}
      {settingsOpen && data && <ProjectSettingsDialog settings={data.settings} onClose={() => setSettingsOpen(false)} />}
      {quickUpdate && <QuickUpdateDialog project={quickUpdate} onClose={() => setQuickUpdate(null)} />}
      {rejecting && (
        <RejectDialog
          projectName={rejecting.name}
          pending={reject.isPending}
          onCancel={() => setRejecting(null)}
          onConfirm={async (reason) => {
            await reject.mutateAsync({ projectId: rejecting.id, reason });
            setRejecting(null);
          }}
        />
      )}
    </div>
  );
}
