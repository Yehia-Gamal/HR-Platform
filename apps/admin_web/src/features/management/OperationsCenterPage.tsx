import { BusFront, CalendarClock, CheckCircle2, CircleAlert, ClipboardCheck, ListTodo, Plus, Search, TimerReset, X } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useOperationsCenter, useOperationsCommands } from './useControlCenters';

type Tab = 'tasks' | 'missions' | 'convoys';
type TaskDraft = { title: string; description: string; assigneeId: string; priority: string; dueDate: string };
const emptyTask: TaskDraft = { title: '', description: '', assigneeId: '', priority: 'medium', dueDate: '' };

function date(value: string | null, withTime = false) {
  if (!value) return 'غير محدد';
  return new Intl.DateTimeFormat('ar-EG', withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' }).format(new Date(value));
}

function transport(value: string | null) {
  return ({ company_vehicle: 'سيارة الشركة', personal: 'سيارة شخصية', public: 'نقل عام', flight: 'طيران', other: 'أخرى' } as Record<string, string>)[value ?? ''] ?? 'غير محدد';
}

export function OperationsCenterPage() {
  const query = useOperationsCenter();
  const commands = useOperationsCommands();
  const [tab, setTab] = useState<Tab>('tasks');
  const [search, setSearch] = useState('');
  const [taskDraft, setTaskDraft] = useState<TaskDraft | null>(null);
  const data = query.data;
  const term = search.trim().toLocaleLowerCase('ar');
  const tasks = useMemo(() => (data?.tasks ?? []).filter((item) => !term || `${item.title} ${item.assigneeName} ${item.description ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const missions = useMemo(() => (data?.missions ?? []).filter((item) => !term || `${item.employeeName} ${item.destination} ${item.purpose}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const convoys = useMemo(() => (data?.convoys ?? []).filter((item) => !term || `${item.employeeName} ${item.name} ${item.origin} ${item.destination}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const openTasks = (data?.tasks ?? []).filter((item) => !['done', 'cancelled'].includes(item.status)).length;
  const urgentTasks = (data?.tasks ?? []).filter((item) => item.priority === 'urgent' && !['done', 'cancelled'].includes(item.status)).length;
  const activeCount = tab === 'tasks' ? tasks.length : tab === 'missions' ? missions.length : convoys.length;

  async function createTask(event: FormEvent) {
    event.preventDefault();
    if (!taskDraft) return;
    await commands.createTask.mutateAsync(taskDraft);
    setTaskDraft(null);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="مركز العمليات والمهام"
        description="متابعة المهام التشغيلية والمأموريات والقوافل من شاشة واحدة، مع بقاء اعتماد المأموريات والقوافل داخل مسار الطلبات الرسمي."
        actions={<button className="btn-primary" type="button" onClick={() => setTaskDraft({ ...emptyTask })}><Plus className="size-4" />مهمة جديدة</button>}
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="مهام مفتوحة" value={openTasks} icon={ListTodo} />
        <MetricCard label="أولوية عاجلة" value={urgentTasks} icon={CircleAlert} />
        <MetricCard label="مأموريات" value={data?.missions.length ?? 0} icon={CalendarClock} />
        <MetricCard label="قوافل مجدولة" value={data?.convoys.length ?? 0} icon={BusFront} />
      </section>

      <section className="filter-bar flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap gap-2" role="tablist" aria-label="أقسام مركز العمليات">
          <TabButton active={tab === 'tasks'} onClick={() => setTab('tasks')} icon={<ListTodo className="size-4" />} label={`المهام (${data?.tasks.length ?? 0})`} />
          <TabButton active={tab === 'missions'} onClick={() => setTab('missions')} icon={<CalendarClock className="size-4" />} label={`المأموريات (${data?.missions.length ?? 0})`} />
          <TabButton active={tab === 'convoys'} onClick={() => setTab('convoys')} icon={<BusFront className="size-4" />} label={`القوافل (${data?.convoys.length ?? 0})`} />
        </div>
        <div className="flex w-full flex-col gap-2 lg:max-w-sm">
          <label className="relative w-full"><Search aria-hidden="true" className="pointer-events-none absolute right-3 top-3 size-4 text-[var(--text-muted)]" /><input className="input pr-10" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="بحث في القسم الحالي…" aria-label="بحث العمليات" />{search ? <button type="button" className="icon-button absolute left-1.5 top-1.5" aria-label="مسح البحث" onClick={() => setSearch('')}><X className="size-4" /></button> : null}</label>
          <span className="muted text-xs" aria-live="polite">عدد النتائج: {activeCount}</span>
        </div>
      </section>

      {query.isError ? (
        <ErrorState
          title="تعذر تحميل مركز العمليات"
          description={query.error instanceof Error ? query.error.message : 'تحقق من الاتصال والصلاحيات.'}
          onRetry={() => void query.refetch()}
        />
      ) : query.isLoading ? (
        <div className="space-y-6" aria-busy="true" aria-label="جارٍ تحميل العمليات">
          <MetricSkeletonRow />
          <SkeletonCard className="h-72" />
        </div>
      ) : null}

      {data && tab === 'tasks' ? (
        <section className="card overflow-hidden">
          <div className="hidden overflow-x-auto md:block">
            <table className="w-full min-w-[880px] text-right text-sm">
              <thead className="bg-[var(--surface-muted)]"><tr><th className="p-4">المهمة</th><th className="p-4">المسؤول</th><th className="p-4">الأولوية</th><th className="p-4">الاستحقاق</th><th className="p-4">الحالة</th><th className="p-4">الإجراء</th></tr></thead>
              <tbody>{tasks.map((item) => <tr className="border-t border-[var(--border)]" key={item.id}><td className="p-4"><strong>{item.title}</strong>{item.description ? <p className="muted mt-1 max-w-md text-xs">{item.description}</p> : null}</td><td className="p-4"><div className="flex items-center gap-2"><UserAvatar displayName={item.assigneeName} size="sm" />{item.assigneeName}</div></td><td className="p-4"><StatusBadge value={item.priority} /></td><td className="p-4">{date(item.dueDate)}</td><td className="p-4"><StatusBadge value={item.status} /></td><td className="p-4"><TaskAction id={item.id} status={item.status} pending={commands.transitionTask.isPending} transition={(status) => void commands.transitionTask.mutateAsync({ id: item.id, status })} /></td></tr>)}</tbody>
            </table>
          </div>
          <div className="divide-y divide-[var(--border)] md:hidden">{tasks.map((item) => <article className="space-y-3 p-5" key={item.id}><div className="flex items-start justify-between gap-3"><div><strong>{item.title}</strong><div className="mt-1 flex items-center gap-2"><UserAvatar displayName={item.assigneeName} size="sm" /><p className="muted text-xs">{item.assigneeName} · {date(item.dueDate)}</p></div></div><StatusBadge value={item.priority} /></div><div className="flex items-center justify-between gap-3"><StatusBadge value={item.status} /><TaskAction id={item.id} status={item.status} pending={commands.transitionTask.isPending} transition={(status) => void commands.transitionTask.mutateAsync({ id: item.id, status })} /></div></article>)}</div>
          {!tasks.length ? <EmptyState title="لا توجد مهام مطابقة" description="أنشئ مهمة جديدة أو غيّر عبارة البحث." /> : null}
        </section>
      ) : null}

      {data && tab === 'missions' ? (
        <section className="grid gap-4 lg:grid-cols-2">{missions.map((item) => <article className="card p-5" key={item.id}><div className="flex items-start justify-between gap-3"><div><h2 className="font-black">{item.destination}</h2><div className="mt-1 flex items-center gap-2"><UserAvatar displayName={item.employeeName} size="sm" /><p className="muted text-sm">{item.employeeName}</p></div></div><StatusBadge value={item.status} /></div><p className="mt-4 leading-7">{item.purpose}</p><div className="mt-4 grid grid-cols-2 gap-3 text-sm"><Info label="الفترة" value={`${date(item.startAt, true)} — ${date(item.endAt, true)}`} /><Info label="وسيلة الانتقال" value={transport(item.transportMode)} /></div></article>)}{!missions.length ? <div className="lg:col-span-2"><EmptyState title="لا توجد مأموريات مطابقة" description="تظهر المأموريات بعد إنشائها من مركز الطلبات." /></div> : null}</section>
      ) : null}

      {data && tab === 'convoys' ? (
        <section className="grid gap-4 lg:grid-cols-2">{convoys.map((item) => <article className="card p-5" key={item.id}><div className="flex items-start justify-between gap-3"><div><h2 className="font-black">{item.name}</h2><div className="mt-1 flex items-center gap-2"><UserAvatar displayName={item.employeeName} size="sm" /><p className="muted text-sm">المسؤول: {item.employeeName}</p></div></div><StatusBadge value={item.status} /></div><div className="mt-5 flex items-center gap-3 rounded-2xl bg-[var(--surface-muted)] p-4"><span className="rounded-xl bg-[var(--surface)] p-2"><BusFront className="size-5 text-[var(--brand-primary)]" /></span><div><strong>{item.origin} ← {item.destination}</strong><p className="muted mt-1 text-xs">التحرك {date(item.departureAt, true)}</p></div></div><div className="mt-4 grid grid-cols-2 gap-3 text-sm"><Info label="الركاب" value={`${item.passengers} فرد`} /><Info label="المركبات" value={`${item.vehicles} مركبة`} /></div></article>)}{!convoys.length ? <div className="lg:col-span-2"><EmptyState title="لا توجد قوافل مطابقة" description="تظهر القوافل بعد إنشائها واعتمادها من مسار الطلبات." /></div> : null}</section>
      ) : null}

      {taskDraft ? (
        <DialogOverlay title="إنشاء مهمة تشغيلية" onClose={() => setTaskDraft(null)} maxWidth="max-w-2xl">
          <p className="muted -mt-3 mb-5 text-sm">ستظهر المهمة للموظف المسند إليه في تطبيق الهاتف.</p>
          <form className="space-y-4" onSubmit={(event) => void createTask(event)}>
              <label className="block text-sm font-bold">عنوان المهمة<input className="input mt-2" required value={taskDraft.title} onChange={(event) => setTaskDraft({ ...taskDraft, title: event.target.value })} /></label>
              <label className="block text-sm font-bold">التفاصيل<textarea className="input mt-2 min-h-24" value={taskDraft.description} onChange={(event) => setTaskDraft({ ...taskDraft, description: event.target.value })} /></label>
              <div className="grid gap-4 sm:grid-cols-3">
                <label className="block text-sm font-bold">المسؤول<select className="input mt-2" required value={taskDraft.assigneeId} onChange={(event) => setTaskDraft({ ...taskDraft, assigneeId: event.target.value })}><option value="">اختر الموظف</option>{data?.employees.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
                <label className="block text-sm font-bold">الأولوية<select className="input mt-2" value={taskDraft.priority} onChange={(event) => setTaskDraft({ ...taskDraft, priority: event.target.value })}><option value="low">منخفضة</option><option value="medium">متوسطة</option><option value="high">عالية</option><option value="urgent">عاجلة</option></select></label>
                <label className="block text-sm font-bold">تاريخ الاستحقاق<input className="input mt-2" type="date" value={taskDraft.dueDate} onChange={(event) => setTaskDraft({ ...taskDraft, dueDate: event.target.value })} /></label>
              </div>
              {commands.createTask.isError ? <ErrorBanner message={commands.createTask.error instanceof Error ? commands.createTask.error.message : 'تعذر إنشاء المهمة.'} /> : null}
              <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" className="btn-secondary" onClick={() => setTaskDraft(null)}>إلغاء</button><button className="btn-primary" disabled={commands.createTask.isPending}><ClipboardCheck className="size-4" />{commands.createTask.isPending ? 'جارٍ الإنشاء…' : 'إنشاء المهمة'}</button></div>
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function TabButton({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return <button type="button" role="tab" aria-selected={active} className={`filter-chip inline-flex items-center gap-2 ${active ? 'is-active' : ''}`} onClick={onClick}>{icon}{label}</button>;
}

function Info({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-[var(--surface-muted)] p-3"><span className="muted block text-xs">{label}</span><strong className="mt-1 block">{value}</strong></div>;
}

function TaskAction({ status, pending, transition }: { id: string; status: string; pending: boolean; transition: (status: string) => void }) {
  if (status === 'done') return <span className="inline-flex items-center gap-1 text-xs font-bold text-[var(--success)]"><CheckCircle2 className="size-4" />مكتملة</span>;
  if (status === 'cancelled') return <span className="muted text-xs">ملغاة</span>;
  return <button type="button" disabled={pending} className="btn-secondary whitespace-nowrap px-3 py-2 text-xs" onClick={() => transition(status === 'pending' ? 'in_progress' : 'done')}>{status === 'pending' ? <><TimerReset className="size-4" />بدء</> : <><CheckCircle2 className="size-4" />إكمال</>}</button>;
}
