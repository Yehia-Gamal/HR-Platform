import type { KpiEvaluationSummary } from '@ahla/shared-contracts';
import { CheckCircle2, Gauge, UsersRound } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { KpiEvaluationEditor } from './KpiEvaluationEditor';
import { usePerformance } from './usePerformance';

const stageLabel: Record<KpiEvaluationSummary['currentStage'], string> = {
  self: 'التقييم الذاتي',
  manager_review: 'مراجعة المدير المباشر',
  hr_review: 'مراجعة HR',
  manager_final: 'اعتماد المدير النهائي',
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
    manager: all.filter((item) => ['manager_review', 'manager_final'].includes(item.currentStage)).length,
    hr: all.filter((item) => item.currentStage === 'hr_review').length,
    completed: all.filter((item) => ['finalized', 'closed', 'archived'].includes(item.currentStage)).length,
  };

  return <div className="space-y-6">
    <PageHeader eyebrow="الأداء" title="KPI والأداء" description="الموظف يقيّم البنود السبعة، ثم يراجع المدير بنوده، وتثبت HR بنودها، ويعود التقييم إلى المدير المباشر للاعتماد النهائي. السكرتير التنفيذي يدير الدورة، والمدير التنفيذي يستقبل التقرير فقط." />
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="إجمالي التقييمات" value={counts.total} icon={UsersRound} /><MetricCard label="عند المديرين" value={counts.manager} icon={Gauge} /><MetricCard label="عند HR" value={counts.hr} icon={Gauge} /><MetricCard label="المكتملة" value={counts.completed} icon={CheckCircle2} /></section>
    <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث باسم الموظف أو الكود" resultText={`عرض ${items.length} من ${all.length} تقييم`} isDirty={Boolean(search || stage !== 'all')} onClear={() => { setSearch(''); setStage('all'); }}>
      <select className="input" aria-label="تصفية حسب مرحلة التقييم" value={stage} onChange={(event) => setStage(event.target.value)}><option value="all">كل المراحل</option><option value="self">التقييم الذاتي</option><option value="manager_review">مراجعة المدير</option><option value="hr_review">مراجعة HR</option><option value="manager_final">اعتماد المدير النهائي</option><option value="finalized">مدرج في التقرير</option><option value="closed">مغلق</option><option value="archived">مؤرشف</option></select>
    </FilterBar>
    {selected ? <KpiEvaluationEditor evaluationId={selected} onDone={() => setSelected(null)} /> : null}
    {query.isError ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : query.isLoading ? <ListSkeleton rows={3} label="جارٍ تحميل التقييمات" /> : items.length === 0 ? <EmptyState title="لا توجد تقييمات" description="لا توجد تقييمات مطابقة في الدورة الحالية." /> : null}
    <section className="space-y-4">{items.map((item) => <article key={item.id} className="card p-5"><div className="grid gap-5 lg:grid-cols-[1fr_240px]"><div><div className="flex flex-wrap items-center gap-2"><StatusBadge value={item.currentStage} /><span className="muted text-xs">{new Intl.DateTimeFormat('ar-EG', { month: 'long', year: 'numeric' }).format(new Date(item.periodMonth))}</span></div><h2 className="mt-3 text-lg font-black">{item.employeeName}</h2><p className="muted mt-1 text-sm">{item.employeeCode || 'بدون كود'} · {stageLabel[item.currentStage]}</p><div className="mt-4 flex flex-wrap gap-3"><span className={chipClass}>النتيجة: <strong>{item.finalScore ?? 'لم تعتمد'}</strong></span><span className={chipClass}>التقدير: <strong>{item.finalRating ?? '—'}</strong></span>{item.deadlineAt ? <span className={chipClass}>الموعد: <strong>{new Date(item.deadlineAt).toLocaleDateString('ar-EG')}</strong></span> : null}</div></div><button className="btn-primary self-center" onClick={() => setSelected(item.id)}>فتح نموذج التقييم</button></div></article>)}</section>
  </div>;
}
