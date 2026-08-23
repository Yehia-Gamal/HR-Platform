import { CheckCircle2, CircleDashed, ClipboardCheck, Plus, Rocket, Save, X } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { ListSkeleton } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useOnboardingAdminCatalog, useOnboardingCommands } from './useAdminOperations';

const defaultTasks = [
  { title: 'مراجعة المستندات الأساسية', ownerRole: 'HR', dueOffsetDays: 0 },
  { title: 'إنشاء الحساب وتأكيد الدخول', ownerRole: 'System Admin', dueOffsetDays: 0 },
  { title: 'توقيع السياسات والإقرارات', ownerRole: 'Employee', dueOffsetDays: 1 },
  { title: 'تعيين المدير والوردية وموقع العمل', ownerRole: 'HR', dueOffsetDays: 1 },
  { title: 'اجتماع اليوم الأول', ownerRole: 'Direct Manager', dueOffsetDays: 1 },
];

export function OnboardingPage() {
  const query = useOnboardingAdminCatalog();
  const commands = useOnboardingCommands();
  const [open, setOpen] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [probationEnd, setProbationEnd] = useState('');
  const [tasks, setTasks] = useState(defaultTasks);
  // النقر على بطاقات الملخص يصفّي قائمة الرحلات حسب الحالة.
  const [statusQuick, setStatusQuick] = useState<'all' | 'in_progress' | 'completed'>('all');
  const data = query.data;
  const visibleJourneys = data ? (statusQuick === 'all' ? data.journeys : data.journeys.filter((item) => item.status === statusQuick)) : [];

  async function create(event: FormEvent) {
    event.preventDefault();
    try {
      await commands.createJourney.mutateAsync({ employeeId, probationEnd: probationEnd || null, tasks });
      setOpen(false);
      setEmployeeId('');
      setProbationEnd('');
      setTasks(defaultTasks);
    } catch {
      /* mutation error surfaced via commands.createJourney.isError */
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Onboarding وفترة التجربة"
        description="رحلة موحدة من إنشاء الحساب حتى اكتمال اليوم الأول والسياسات ومراجعة فترة التجربة."
        actions={
          <button className="btn-primary" onClick={() => setOpen(true)}>
            <Plus className="size-4" aria-hidden="true" />
            بدء رحلة
          </button>
        }
      />
      {query.isError ? (
        <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && !data ? (
        <ListSkeleton rows={3} label="جارٍ تحميل رحلات الإلحاق…" />
      ) : null}
      {(commands.createJourney.isError || commands.transitionTask.isError) && (
        <ErrorBanner message={safeErrorMessage(commands.createJourney.error ?? commands.transitionTask.error)} />
      )}
      {data ? (
        <>
          <section className="grid gap-4 sm:grid-cols-3">
            <MetricCard
              label="الرحلات النشطة"
              value={data.journeys.filter((item) => item.status === 'in_progress').length}
              icon={Rocket}
              onClick={() => setStatusQuick('in_progress')}
            />
            <MetricCard
              label="المكتملة"
              value={data.journeys.filter((item) => item.status === 'completed').length}
              icon={CheckCircle2}
              onClick={() => setStatusQuick('completed')}
            />
            <MetricCard
              label="مهام معلقة"
              value={data.journeys.reduce((sum, item) => sum + item.totalTasks - item.completedTasks, 0)}
              icon={ClipboardCheck}
              onClick={() => setStatusQuick('all')}
            />
          </section>
          <section className="space-y-4">
            {visibleJourneys.length ? (
              visibleJourneys.map((journey) => (
                <article key={journey.id} className="card p-5">
                  <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <UserAvatar displayName={journey.employeeName} size="sm" />
                        <h2 className="font-black">{journey.employeeName}</h2>
                        <StatusBadge value={journey.status} />
                      </div>
                      <p className="muted mt-1 text-sm">
                        {journey.employeeCode}
                        {journey.probationEnd ? ` · نهاية التجربة ${new Date(journey.probationEnd).toLocaleDateString('ar-EG')}` : ''}
                      </p>
                    </div>
                    <div className="min-w-56">
                      <div className="flex justify-between text-sm">
                        <span>التقدم</span>
                        <strong>{journey.progress}%</strong>
                      </div>
                      <div className="mt-2 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]">
                        <div className="h-full rounded-full bg-brand" style={{ width: `${journey.progress}%` }} />
                      </div>
                    </div>
                  </div>
                  <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                    {journey.tasks.map((task) => (
                      <div key={task.id} className="rounded-xl border border-[var(--border)] p-4">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className="font-bold">{task.title}</p>
                            <p className="muted mt-1 text-xs">
                              {task.ownerRole ?? 'غير مسند'} · اليوم +{task.dueOffsetDays ?? 0}
                            </p>
                          </div>
                          {task.status === 'completed' ? (
                            <>
                              <CheckCircle2 className="size-5 text-[var(--success)]" aria-hidden="true" />
                              <span className="sr-only">مكتملة</span>
                            </>
                          ) : (
                            <>
                              <CircleDashed className="size-5 text-[var(--warning)]" aria-hidden="true" />
                              <span className="sr-only">قيد الانتظار</span>
                            </>
                          )}
                        </div>
                        <select
                          className="input mt-3"
                          aria-label={`حالة المهمة: ${task.title}`}
                          value={task.status}
                          onChange={(event) => commands.transitionTask.mutate({ taskId: task.id, status: event.target.value })}
                        >
                          <option value="pending">معلقة</option>
                          <option value="in_progress">قيد التنفيذ</option>
                          <option value="completed">مكتملة</option>
                          <option value="skipped">تم التجاوز</option>
                        </select>
                      </div>
                    ))}
                  </div>
                </article>
              ))
            ) : (
              <EmptyState title="لا توجد رحلات Onboarding" description="ابدأ رحلة لموظف جديد وحدد مهام اليوم الأول وفترة التجربة." />
            )}
          </section>
        </>
      ) : null}

      {open && data ? (
        <DialogOverlay title="بدء رحلة Onboarding" onClose={() => setOpen(false)} maxWidth="max-w-4xl">
          <form className="space-y-5" onSubmit={(event) => void create(event)}>
            <label>
              <span className="mb-1.5 block text-sm font-bold">الموظف</span>
              <select className="input" required value={employeeId} onChange={(event) => setEmployeeId(event.target.value)}>
                <option value="">اختر الموظف…</option>
                {data.eligibleEmployees.map((employee) => (
                  <option key={employee.id} value={employee.id}>
                    {employee.name} · {employee.code}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span className="mb-1.5 block text-sm font-bold">نهاية فترة التجربة</span>
              <input className="input" type="date" value={probationEnd} onChange={(event) => setProbationEnd(event.target.value)} />
            </label>
            <div>
              <div className="mb-3 flex items-center justify-between">
                <h3 className="font-black">مهام الرحلة</h3>
                <button type="button" className="btn-secondary" onClick={() => setTasks([...tasks, { title: '', ownerRole: 'HR', dueOffsetDays: 0 }])}>
                  <Plus className="size-4" aria-hidden="true" />
                  مهمة
                </button>
              </div>
              <div className="space-y-3">
                {tasks.map((task, index) => (
                  <div key={index} className="grid gap-3 rounded-xl bg-[var(--surface-muted)] p-3 sm:grid-cols-[1.5fr_1fr_120px_auto]">
                    <input
                      className="input"
                      required
                      placeholder="عنوان المهمة"
                      value={task.title}
                      onChange={(event) => setTasks(tasks.map((item, current) => (current === index ? { ...item, title: event.target.value } : item)))}
                    />
                    <input
                      className="input"
                      placeholder="المسؤول"
                      aria-label="المسؤول"
                      value={task.ownerRole}
                      onChange={(event) => setTasks(tasks.map((item, current) => (current === index ? { ...item, ownerRole: event.target.value } : item)))}
                    />
                    <input
                      className="input"
                      type="number"
                      min={0}
                      aria-label="عدد الأيام"
                      value={task.dueOffsetDays}
                      onChange={(event) =>
                        setTasks(tasks.map((item, current) => (current === index ? { ...item, dueOffsetDays: Number(event.target.value) || 0 } : item)))
                      }
                    />
                    <button
                      type="button"
                      className="icon-button text-[var(--danger)]"
                      aria-label="حذف المهمة"
                      onClick={() => setTasks(tasks.filter((_, current) => current !== index))}
                    >
                      <X className="size-4" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
            <button className="btn-primary" disabled={commands.createJourney.isPending}>
              <Save className="size-4" aria-hidden="true" />
              {commands.createJourney.isPending ? 'جارٍ البدء…' : 'بدء الرحلة'}
            </button>
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}
