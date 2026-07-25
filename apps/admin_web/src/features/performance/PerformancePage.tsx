import type { KpiEvaluationSummary } from '@ahla/shared-contracts';
import { AlertTriangle, CheckCircle2, Gauge, UsersRound } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { KpiEvaluationEditor } from './KpiEvaluationEditor';
import { usePerformance } from './usePerformance';

const stageLabel: Record<KpiEvaluationSummary['currentStage'], string> = {
  self: 'التقييم الذاتي',
  hr_review: 'مراجعة HR',
  manager_review: 'مراجعة المدير المباشر',
  manager_final: 'اعتماد المدير (قديم)',
  finalized: 'مدرج في التقرير الشهري',
  closed: 'مغلق',
  archived: 'مؤرشف',
};

const chipClass = 'rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-sm';

export function PerformancePage() {
  const query = usePerformance();
  const [search, setSearch] = useState('');
  const [stage, setStage] = useState('all');
  const [selected, setSelected] = useState<string | null>(null);
  const all = query.data ?? [];
  const items = useMemo(() => all.filter((item) => {
    const matchesSearch = `${item.employeeName} ${item.employeeCode ?? ''}`.toLowerCase().includes(search.trim().toLowerCase());
    return matchesSearch && (stage === 'all' || item.currentStage === stage);
  }), [all, search, stage]);
  const counts = {
    total: all.length,
    manager: all.filter((item) => item.currentStage === 'manager_review').length,
    hr: all.filter((item) => item.currentStage === 'hr_review').length,
    completed: all.filter((item) => ['finalized', 'closed', 'archived'].includes(item.currentStage)).length,
    overdue: all.filter((item) => item.workflowStatus === 'OVERDUE').length,
  };

  return <div className="space-y-6">
    <PageHeader eyebrow="الأداء" title="KPI والأداء" description="الموظف يقيّم ذاتيًا، ثم تراجع HR (الحضور والصلاة والحلقة)، ثم المدير المباشر يراجع ويعتمد. السكرتير التنفيذي يدير الدورة." />
    {counts.overdue > 0 ? <section className="flex items-center gap-3 rounded-2xl border border-amber-300 bg-amber-50 p-4 text-amber-950"><AlertTriangle className="size-5 shrink-0" /><p className="font-bold">{counts.overdue} تقييم متأخر عن الموعد النهائي — يُرجى المتابعة مع المديرين والموظفين المعنيين.</p></section> : null}
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="إجمالي التقييمات" value={counts.total} icon={UsersRound} /><MetricCard label="عند المديرين" value={counts.manager} icon={Gauge} /><MetricCard label="عند HR" value={counts.hr} icon={Gauge} /><MetricCard label="المكتملة" value={counts.completed} icon={CheckCircle2} /></section>
    <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث باسم الموظف أو الكود" resultText={`عرض ${items.length} من ${all.length} تقييم`} isDirty={Boolean(search || stage !== 'all')} onClear={() => { setSearch(''); setStage('all'); }}>
      <select className="input" aria-label="تصفية حسب مرحلة التقييم" value={stage} onChange={(event) => setStage(event.target.value)}><option value="all">كل المراحل</option><option value="self">التقييم الذاتي</option><option value="hr_review">مراجعة HR</option><option value="manager_review">مراجعة المدير</option><option value="finalized">مدرج في التقرير</option><option value="closed">مغلق</option><option value="archived">مؤرشف</option></select>
    </FilterBar>
    {selected ? <KpiEvaluationEditor evaluationId={selected} onDone={() => setSelected(null)} /> : null}
    {query.isError ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : query.isLoading ? <ListSkeleton rows={3} label="جارٍ تحميل التقييمات" /> : items.length === 0 ? <EmptyState title="لا توجد تقييمات" description="لا توجد تقييمات مطابقة في الدورة الحالية." /> : null}
    <section className="space-y-4">{items.map((item) => <article key={item.id} className="card p-5"><div className="grid gap-5 lg:grid-cols-[1fr_240px]"><div><div className="flex flex-wrap items-center gap-2"><StatusBadge value={item.currentStage} /><span className="muted text-xs">{new Intl.DateTimeFormat('ar-EG', { month: 'long', year: 'numeric' }).format(new Date(item.periodMonth))}</span></div><div className="mt-3 flex items-center gap-3"><UserAvatar displayName={item.employeeName} size="sm" /><div><h2 className="text-lg font-black">{item.employeeName}</h2><p className="muted mt-1 text-sm">{item.employeeCode || 'بدون كود'} · {stageLabel[item.currentStage]}</p></div></div><div className="mt-4 flex flex-wrap gap-3"><span className={chipClass}>النتيجة: <strong>{item.finalScore ?? 'لم تعتمد'}</strong></span><span className={chipClass}>التقدير: <strong>{item.finalRating ?? '—'}</strong></span></div></div><button className="btn-primary self-center" onClick={() => setSelected(item.id)}>فتح نموذج التقييم</button></div></article>)}</section>
  </div>;
}
