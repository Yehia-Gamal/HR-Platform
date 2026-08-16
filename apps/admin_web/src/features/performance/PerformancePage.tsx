import type { KpiEvaluationSummary } from '@ahla/shared-contracts';
import { AlertTriangle, CheckCircle2, ClipboardList, Gauge, User, UsersRound } from 'lucide-react';
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
import { safeErrorMessage } from '../../core/errorMapper';

const stageLabel: Record<KpiEvaluationSummary['currentStage'], string> = {
  self: 'التقييم الذاتي',
  parallel_review: 'مراجعة متوازية',
  hr_review: 'مراجعة HR',
  manager_review: 'مراجعة المدير المباشر',
  manager_final: 'اعتماد المدير (قديم)',
  secretary_review: 'مراجعة السكرتير',
  executive_review: 'مراجعة المدير التنفيذي',
  finalized: 'مدرج في التقرير الشهري',
  closed: 'مغلق',
  archived: 'مؤرشف',
};

const chipClass = 'rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-sm';

// 0204: تعريف التابات — تقييمي / فريقي / المهام
type KpiRelation = 'self' | 'team' | 'review';
interface KpiTabDef {
  key: KpiRelation;
  label: string;
  icon: typeof User;
}
const TAB_DEFS: KpiTabDef[] = [
  { key: 'self', label: 'تقييمي', icon: User },
  { key: 'team', label: 'فريقي', icon: UsersRound },
  { key: 'review', label: 'المهام', icon: ClipboardList },
];

export function PerformancePage() {
  const query = usePerformance();
  const [search, setSearch] = useState('');
  const [stage, setStage] = useState('all');
  const [selected, setSelected] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<KpiRelation | null>(null);
  const all = useMemo(() => query.data ?? [], [query.data]);

  // 0204: تقسيم البيانات حسب relation
  const { availableTabs, currentTab } = useMemo(() => {
    const tabs = TAB_DEFS.filter((t) => all.some((item) => item.relation === t.key));
    // إذا لم توجد relation (بيانات قديمة) — عرض الكل بدون تابات.
    const hasRelation = all.some((item) => item.relation);
    if (!hasRelation) return { availableTabs: [] as KpiTabDef[], currentTab: null };
    // اختيار التاب النشط: المحدد أو أول تاب متوفر.
    const current = tabs.find((t) => t.key === activeTab) ?? tabs[0] ?? null;
    return { availableTabs: tabs, currentTab: current };
  }, [all, activeTab]);

  // تصفية حسب التاب النشط + البحث + المرحلة.
  const tabItems = useMemo(() => {
    if (!currentTab) return all;
    return all.filter((item) => item.relation === currentTab.key);
  }, [all, currentTab]);

  const items = useMemo(
    () =>
      tabItems.filter((item) => {
        const matchesSearch = `${item.employeeName} ${item.employeeCode ?? ''}`.toLowerCase().includes(search.trim().toLowerCase());
        return matchesSearch && (stage === 'all' || item.currentStage === stage);
      }),
    [tabItems, search, stage],
  );

  const counts = {
    total: tabItems.length,
    parallel: tabItems.filter((item) => item.currentStage === 'parallel_review').length,
    manager: tabItems.filter((item) => item.currentStage === 'manager_review').length,
    hr: tabItems.filter((item) => item.currentStage === 'hr_review').length,
    completed: tabItems.filter((item) => ['finalized', 'closed', 'archived'].includes(item.currentStage)).length,
    overdue: tabItems.filter((item) => (item.workflowStatus as string) === 'OVERDUE').length,
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الأداء"
        title="KPI والأداء"
        description="الموظف يقيّم ذاتيًا، ثم تراجع HR والمدير بالتوازي، ثم السكرتير التنفيذي يراجع والمدير التنفيذي يعتمد."
      />

      {/* 0204: شريط التابات */}
      {availableTabs.length > 1 ? (
        <nav className="flex gap-1 rounded-2xl bg-[var(--surface-muted)] p-1" role="tablist" aria-label="تصنيف التقييمات">
          {availableTabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = currentTab?.key === tab.key;
            const count = all.filter((item) => item.relation === tab.key).length;
            return (
              <button
                key={tab.key}
                role="tab"
                aria-selected={isActive}
                onClick={() => {
                  setActiveTab(tab.key);
                  setSearch('');
                  setStage('all');
                }}
                className={`flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-bold transition-colors ${isActive ? 'bg-[var(--surface)] shadow-sm text-[var(--text-primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}`}
              >
                <Icon className="size-4" />
                {tab.label}
                <span className={`rounded-full px-2 py-0.5 text-xs font-bold ${isActive ? 'bg-[var(--primary)] text-white' : 'bg-[var(--surface-muted)]'}`}>
                  {count}
                </span>
              </button>
            );
          })}
        </nav>
      ) : null}

      {counts.overdue > 0 ? (
        <section className="flex items-center gap-3 rounded-2xl border border-[var(--warning)] bg-[var(--warning-soft)] p-4 text-[var(--warning)]">
          <AlertTriangle className="size-5 shrink-0" aria-hidden="true" />
          <p className="font-bold">{counts.overdue} تقييم متأخر عن الموعد النهائي — يُرجى المتابعة مع المديرين والموظفين المعنيين.</p>
        </section>
      ) : null}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <MetricCard label="إجمالي التقييمات" value={counts.total} icon={UsersRound} />
        <MetricCard label="مراجعة متوازية" value={counts.parallel} icon={Gauge} />
        <MetricCard label="عند المديرين" value={counts.manager} icon={Gauge} />
        <MetricCard label="عند HR" value={counts.hr} icon={Gauge} />
        <MetricCard label="المكتملة" value={counts.completed} icon={CheckCircle2} />
      </section>
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث باسم الموظف أو الكود"
        resultText={`عرض ${items.length} من ${tabItems.length} تقييم`}
        isDirty={Boolean(search || stage !== 'all')}
        onClear={() => {
          setSearch('');
          setStage('all');
        }}
      >
        <select className="input" aria-label="تصفية حسب مرحلة التقييم" value={stage} onChange={(event) => setStage(event.target.value)}>
          <option value="all">كل المراحل</option>
          <option value="self">التقييم الذاتي</option>
          <option value="parallel_review">مراجعة متوازية (V23)</option>
          <option value="hr_review">مراجعة HR</option>
          <option value="manager_review">مراجعة المدير</option>
          <option value="secretary_review">مراجعة السكرتير</option>
          <option value="executive_review">مراجعة المدير التنفيذي</option>
          <option value="finalized">مدرج في التقرير</option>
          <option value="closed">مغلق</option>
          <option value="archived">مؤرشف</option>
        </select>
      </FilterBar>
      {selected ? <KpiEvaluationEditor evaluationId={selected} onDone={() => setSelected(null)} /> : null}
      {query.isError ? (
        <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <ListSkeleton rows={3} label="جارٍ تحميل التقييمات" />
      ) : items.length === 0 ? (
        <EmptyState title="لا توجد تقييمات" description="لا توجد تقييمات مطابقة في الدورة الحالية." />
      ) : null}
      <section className="space-y-4">
        {items.map((item) => (
          <article key={item.id} className="card p-5">
            <div className="grid gap-5 lg:grid-cols-[1fr_240px]">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <StatusBadge value={item.currentStage} />
                  <span className="muted text-xs">
                    {new Intl.DateTimeFormat('ar-EG', { month: 'long', year: 'numeric' }).format(new Date(item.periodMonth))}
                  </span>
                </div>
                <div className="mt-3 flex items-center gap-3">
                  <UserAvatar displayName={item.employeeName} size="sm" />
                  <div>
                    <h2 className="text-lg font-black">{item.employeeName}</h2>
                    <p className="muted mt-1 text-sm">
                      {item.employeeCode || 'بدون كود'} · {stageLabel[item.currentStage]}
                    </p>
                  </div>
                </div>
                <div className="mt-4 flex flex-wrap gap-3">
                  <span className={chipClass}>
                    النتيجة: <strong>{item.finalScore ?? 'لم تعتمد'}</strong>
                  </span>
                  <span className={chipClass}>
                    التقدير: <strong>{item.finalRating ?? '—'}</strong>
                  </span>
                </div>
              </div>
              <button className="btn-primary self-center" onClick={() => setSelected(item.id)}>
                فتح نموذج التقييم
              </button>
            </div>
          </article>
        ))}
      </section>
    </div>
  );
}
