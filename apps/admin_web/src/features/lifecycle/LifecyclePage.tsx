import { useMemo, useState, type FormEvent } from 'react';
import type { OnboardingAdminCatalog } from '@ahla/shared-contracts';
import { Award, CheckCircle2, ClipboardCheck, Eye, Loader2, PackageCheck, Plus, RefreshCw, UsersRound, X } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { JOURNEY_STATUS_LABELS, TASK_STATUS_LABELS, TASK_STATUS_ORDER, useLifecycleCatalog, useLifecycleCommands } from './useLifecycle';

type Journey = OnboardingAdminCatalog['journeys'][number];
type JourneyTask = Journey['tasks'][number];
type EligibleEmployee = OnboardingAdminCatalog['eligibleEmployees'][number];

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

const STATUS_FILTERS = ['all', 'in_progress', 'completed'] as const;

export function LifecyclePage() {
  const catalog = useLifecycleCatalog();

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [createOpen, setCreateOpen] = useState(false);
  const [viewJourney, setViewJourney] = useState<Journey | null>(null);

  const journeys = useMemo(() => catalog.data?.journeys ?? [], [catalog.data]);
  const employees = useMemo(() => catalog.data?.eligibleEmployees ?? [], [catalog.data]);

  const inProgress = journeys.filter((j) => j.status === 'in_progress').length;
  const completed = journeys.filter((j) => j.status === 'completed').length;
  const onboardingEmployees = employees.filter((e) => e.status === 'onboarding').length;
  const avgProgress = journeys.length === 0 ? 0 : Math.round(journeys.reduce((sum, j) => sum + j.progress, 0) / journeys.length);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return journeys
      .filter((j) => {
        const matchSearch = !q || j.employeeName.toLowerCase().includes(q) || (j.employeeCode ?? '').toLowerCase().includes(q);
        const matchStatus = statusFilter === 'all' || j.status === statusFilter;
        return matchSearch && matchStatus;
      })
      .sort((a, b) => a.employeeName.localeCompare(b.employeeName, 'ar'));
  }, [journeys, search, statusFilter]);

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
  };

  const columns: DataTableColumn<Journey>[] = [
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (j) => (
        <div>
          <span className="font-bold">{j.employeeName}</span>
          {j.employeeCode ? <span className="mr-2 text-xs text-[var(--text-muted)]">{j.employeeCode}</span> : null}
        </div>
      ),
    },
    {
      key: 'status',
      header: 'المرحلة',
      render: (j) => <StatusBadge status={j.status} label={JOURNEY_STATUS_LABELS[j.status] ?? j.status} />,
    },
    {
      key: 'progress',
      header: 'التقدم',
      render: (j) => (
        <div className="flex items-center gap-2">
          <div className="h-1.5 w-24 overflow-hidden rounded-full bg-[var(--surface-muted)]">
            <div className="h-full rounded-full bg-[var(--success)]" style={{ width: `${j.progress}%` }} />
          </div>
          <span className="text-xs font-bold">{j.progress}%</span>
        </div>
      ),
    },
    {
      key: 'tasks',
      header: 'المهام',
      render: (j) => (
        <span className="inline-flex items-center gap-1.5">
          <ClipboardCheck className="size-4 text-[var(--text-muted)]" aria-hidden="true" />
          {j.completedTasks}/{j.totalTasks}
        </span>
      ),
    },
    {
      key: 'startedAt',
      header: 'بداية الرحلة',
      render: (j) => (j.startedAt ? dateFormatter.format(new Date(j.startedAt)) : '—'),
    },
    {
      key: 'probationEnd',
      header: 'نهاية التجربة',
      render: (j) => (j.probationEnd ? dateFormatter.format(new Date(j.probationEnd)) : '—'),
    },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (j) => (
        <button
          type="button"
          title="عرض المهام"
          aria-label={`عرض مهام ${j.employeeName}`}
          className="inline-grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:border-[var(--border-strong)] hover:bg-[var(--surface-muted)] hover:text-[var(--text-primary)]"
          onClick={() => setViewJourney(j)}
        >
          <Eye className="size-4" aria-hidden="true" />
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="دورة حياة الموظف"
        description="متابعة مراحل دورة حياة الموظف بدءاً من التهيئة، ومتابعة إنجاز المهام ونهاية فترة التجربة."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary" onClick={() => void catalog.refetch()} disabled={catalog.isFetching}>
              <RefreshCw className={`size-4 ${catalog.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
              تحديث
            </button>
            <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
              <Plus className="size-4" aria-hidden="true" />
              رحلة تهيئة جديدة
            </button>
          </div>
        }
      />

      {catalog.isLoading ? (
        <MetricSkeletonRow count={4} />
      ) : (
        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard
            label="رحلات قيد التنفيذ"
            value={inProgress}
            icon={PackageCheck}
            hint="في مرحلة التهيئة حالياً"
            onClick={() => setStatusFilter('in_progress')}
          />
          <MetricCard label="رحلات مكتملة" value={completed} icon={CheckCircle2} hint="اجتازت مرحلة التهيئة" onClick={() => setStatusFilter('completed')} />
          <MetricCard label="متوسط الإنجاز" value={`${avgProgress}%`} icon={Award} hint="عبر جميع الرحلات" onClick={() => setStatusFilter('all')} />
          <MetricCard
            label="موظفون في التهيئة"
            value={onboardingEmployees}
            icon={UsersRound}
            hint="من قائمة الموظفين المتاحة"
            onClick={() => setStatusFilter('all')}
          />
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث باسم الموظف أو الكود…"
        resultText={`عرض ${filtered.length} من ${journeys.length} رحلة`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب المرحلة">
          {STATUS_FILTERS.map((key) => (
            <option key={key} value={key}>
              {key === 'all' ? 'كل المراحل' : (JOURNEY_STATUS_LABELS[key] ?? key)}
            </option>
          ))}
        </select>
      </FilterBar>

      {catalog.isError ? (
        <ErrorState description={safeErrorMessage(catalog.error)} onRetry={() => void catalog.refetch()} />
      ) : catalog.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل رحلات التهيئة…" />
      ) : journeys.length === 0 ? (
        <EmptyState
          title="لا توجد رحلات تهيئة بعد"
          description="ابدأ بإنشاء أول رحلة تهيئة لموظف جديد، ثم تابع إنجاز المهام داخل الرحلة."
          action={
            <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
              <Plus className="size-4" aria-hidden="true" />
              إنشاء رحلة
            </button>
          }
        />
      ) : (
        <DataTable<Journey>
          ariaLabel="جدول رحلات دورة حياة الموظف"
          rowKey={(j) => j.id}
          data={filtered}
          minWidth="960px"
          columns={columns}
          emptyTitle="لا توجد نتائج مطابقة"
          emptyDescription="جرّب تعديل البحث أو تغيير المرحلة."
        />
      )}

      {createOpen ? <CreateJourneyDialog employees={employees} onClose={() => setCreateOpen(false)} /> : null}
      {viewJourney ? <JourneyTasksDialog journey={viewJourney} onClose={() => setViewJourney(null)} /> : null}
    </div>
  );
}

function CreateJourneyDialog({ employees, onClose }: { employees: EligibleEmployee[]; onClose: () => void }) {
  const { createJourney } = useLifecycleCommands();

  const [employeeId, setEmployeeId] = useState('');
  const [probationEnd, setProbationEnd] = useState('');
  const [tasks, setTasks] = useState<Array<{ title: string; ownerRole: string; dueOffsetDays: string }>>([{ title: '', ownerRole: '', dueOffsetDays: '0' }]);
  const [error, setError] = useState<string | null>(null);

  const updateTask = (index: number, patch: Partial<{ title: string; ownerRole: string; dueOffsetDays: string }>) => {
    setTasks((prev) => prev.map((task, i) => (i === index ? { ...task, ...patch } : task)));
  };

  const removeTask = (index: number) => {
    setTasks((prev) => prev.filter((_, i) => i !== index));
  };

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);

    if (!employeeId) {
      setError('اختر موظفاً لبدء الرحلة.');
      return;
    }

    const validTasks = tasks
      .map((t) => ({
        title: t.title.trim(),
        ownerRole: t.ownerRole.trim(),
        dueOffsetDays: t.dueOffsetDays.trim(),
      }))
      .filter((t) => t.title);

    if (validTasks.length === 0) {
      setError('أضف مهمة واحدة على الأقل بعنوان واضح.');
      return;
    }
    if (validTasks.length > 200) {
      setError('عدد المهام يتجاوز الحد الأقصى (200 مهمة).');
      return;
    }

    try {
      await createJourney.mutateAsync({
        employeeId,
        probationEnd: probationEnd || null,
        tasks: validTasks.map((t) => ({
          title: t.title,
          ownerRole: t.ownerRole || null,
          dueOffsetDays: t.dueOffsetDays === '' ? 0 : Number(t.dueOffsetDays),
        })),
      });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="رحلة تهيئة جديدة" onClose={onClose} maxWidth="max-w-2xl">
      <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
        {error ? <ErrorBanner message={error} /> : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">الموظف</span>
            {employees.length === 0 ? (
              <p className="text-sm text-[var(--text-muted)]">لا يوجد موظفون متاحون لبدء رحلة تهيئة.</p>
            ) : (
              <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required autoFocus>
                <option value="">— اختر موظفاً —</option>
                {employees.map((employee) => (
                  <option key={employee.id} value={employee.id}>
                    {employee.name}
                    {employee.code ? ` (${employee.code})` : ''}
                  </option>
                ))}
              </select>
            )}
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">نهاية فترة التجربة (اختياري)</span>
            <input className="input" type="date" value={probationEnd} onChange={(e) => setProbationEnd(e.target.value)} />
          </label>
        </div>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-sm font-bold">مهام التهيئة</span>
            <button
              type="button"
              className="btn-secondary !px-3 !py-1 text-xs"
              onClick={() => setTasks((prev) => [...prev, { title: '', ownerRole: '', dueOffsetDays: '0' }])}
            >
              <Plus className="size-3.5" aria-hidden="true" />
              إضافة مهمة
            </button>
          </div>
          {tasks.map((task, index) => (
            <div key={index} className="flex items-start gap-2 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-3">
              <input
                className="input flex-1"
                value={task.title}
                onChange={(e) => updateTask(index, { title: e.target.value })}
                placeholder={`عنوان المهمة ${index + 1}…`}
                aria-label={`عنوان المهمة ${index + 1}`}
              />
              <input
                className="input w-36"
                value={task.ownerRole}
                onChange={(e) => updateTask(index, { ownerRole: e.target.value })}
                placeholder="صاحب المهمة (مثل: hr)"
                aria-label={`صاحب المهمة ${index + 1}`}
              />
              <input
                className="input w-24"
                type="number"
                min="0"
                value={task.dueOffsetDays}
                onChange={(e) => updateTask(index, { dueOffsetDays: e.target.value })}
                placeholder="بعد أيام"
                aria-label={`استحقاق المهمة ${index + 1} بالأيام`}
              />
              <button
                type="button"
                className="grid size-8 shrink-0 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:border-[var(--danger)] hover:text-[var(--danger)]"
                onClick={() => removeTask(index)}
                aria-label={`حذف المهمة ${index + 1}`}
              >
                <X className="size-4" aria-hidden="true" />
              </button>
            </div>
          ))}
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={createJourney.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={createJourney.isPending || employees.length === 0}>
            {createJourney.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
            إنشاء الرحلة
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

function JourneyTasksDialog({ journey, onClose }: { journey: Journey; onClose: () => void }) {
  const { transitionTask } = useLifecycleCommands();
  const { toast } = useToast();

  const pendingTasks = journey.tasks.filter((t) => t.status !== 'completed' && t.status !== 'skipped').length;

  const handleTaskStatus = async (task: JourneyTask, status: string) => {
    if (status === task.status) return;
    try {
      await transitionTask.mutateAsync({ taskId: task.id, status });
      toast({ message: `تم تحديث المهمة إلى «${TASK_STATUS_LABELS[status] ?? status}»`, tone: 'success' });
    } catch {
      /* error surfaced via MutationCache global toast */
    }
  };

  return (
    <DialogOverlay title="مهام رحلة التهيئة" onClose={onClose} maxWidth="max-w-2xl">
      <div className="space-y-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1">
            <p className="truncate font-black">{journey.employeeName}</p>
            <p className="text-xs text-[var(--text-muted)]">
              {journey.employeeCode ?? 'بدون كود'} · بدأت {journey.startedAt ? dateFormatter.format(new Date(journey.startedAt)) : '—'}
            </p>
          </div>
          <StatusBadge status={journey.status} label={JOURNEY_STATUS_LABELS[journey.status] ?? journey.status} />
          <div className="flex items-center gap-2">
            <div className="h-1.5 w-24 overflow-hidden rounded-full bg-[var(--surface-muted)]">
              <div className="h-full rounded-full bg-[var(--success)]" style={{ width: `${journey.progress}%` }} />
            </div>
            <span className="text-xs font-bold">{journey.progress}%</span>
          </div>
        </div>

        {journey.tasks.length === 0 ? (
          <EmptyState title="لا توجد مهام" description="لم تُضف مهام لهذه الرحلة بعد." />
        ) : (
          <ul className="space-y-2">
            {journey.tasks.map((task) => (
              <li key={task.id} className="flex flex-wrap items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-bold">{task.title}</p>
                  <p className="text-xs text-[var(--text-muted)]">
                    {task.ownerRole ? `صاحب المهمة: ${task.ownerRole} · ` : ''}
                    {task.dueOffsetDays != null ? `مستحقة بعد ${task.dueOffsetDays} يوم` : ''}
                  </p>
                </div>
                <StatusBadge status={task.status} label={TASK_STATUS_LABELS[task.status] ?? task.status} />
                <select
                  className="rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2 py-1.5 text-xs font-bold text-[var(--text-primary)] transition focus:border-[var(--brand-accent)] focus:outline-none disabled:opacity-50"
                  value={task.status}
                  disabled={transitionTask.isPending}
                  onChange={(ev) => void handleTaskStatus(task, ev.target.value)}
                  aria-label="تحديث حالة المهمة"
                >
                  {TASK_STATUS_ORDER.map((value) => (
                    <option key={value} value={value}>
                      {TASK_STATUS_LABELS[value] ?? value}
                    </option>
                  ))}
                </select>
              </li>
            ))}
          </ul>
        )}

        <div className="flex items-center justify-between gap-3 pt-2">
          <span className="text-sm font-bold text-[var(--text-muted)]">
            {journey.completedTasks}/{journey.totalTasks} مهام مكتملة — {pendingTasks} معلقة
          </span>
          <button type="button" className="btn-secondary" onClick={onClose} disabled={transitionTask.isPending}>
            إغلاق
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}
