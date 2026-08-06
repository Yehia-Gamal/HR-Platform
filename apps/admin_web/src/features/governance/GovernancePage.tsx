import { useMemo, useState } from 'react';
import { AlertTriangle, FileSearch, ShieldAlert, Target } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { Tabs } from '../../ui/Tabs';
import { useEnterpriseCatalog } from './useGovernance';

const RISK_STATUS: Record<string, string> = { open: 'مفتوح', mitigated: 'مُخفَّف', closed: 'مغلق', monitoring: 'تحت المراقبة' };
const AUDIT_STATUS: Record<string, string> = { planned: 'مخطط', in_progress: 'قيد التنفيذ', completed: 'مكتمل', draft: 'مسودة' };

export function GovernancePage() {
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<'risks' | 'incidents' | 'audits'>('risks');
  const catalog = useEnterpriseCatalog();

  const stats = useMemo(() => {
    const d = catalog.data;
    return {
      openRisks: d?.risks.filter((r) => r.status === 'open').length ?? 0,
      highRisks: d?.risks.filter((r) => r.score >= 12).length ?? 0,
      openIncidents: d?.incidents.filter((i) => !['closed', 'resolved'].includes(i.status)).length ?? 0,
      activeAudits: d?.audits.filter((a) => a.status === 'in_progress').length ?? 0,
    };
  }, [catalog.data]);

  const filteredRisks = useMemo(() => {
    const q = search.trim().toLowerCase();
    const risks = catalog.data?.risks ?? [];
    if (!q) return risks;
    return risks.filter((r) => r.title.toLowerCase().includes(q) || r.number.toLowerCase().includes(q));
  }, [catalog.data?.risks, search]);

  if (catalog.isLoading) return <ListSkeleton />;
  if (catalog.isError) return <ErrorState title="تعذّر تحميل البيانات" description={safeErrorMessage(catalog.error)} onRetry={() => catalog.refetch()} />;

  return (
    <div className="space-y-5">
      <PageHeader eyebrow="الحوكمة والمخاطر" title="مركز الحوكمة وإدارة المخاطر" description="سجل المخاطر، الحوادث، والتدقيق الداخلي" />
      <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard label="مخاطر مفتوحة" value={stats.openRisks} icon={AlertTriangle} hint={`${stats.highRisks} عالية`} />
        <MetricCard label="حوادث نشطة" value={stats.openIncidents} icon={ShieldAlert} />
        <MetricCard label="تدقيقات جارية" value={stats.activeAudits} icon={FileSearch} />
        <MetricCard label="مشاريع استراتيجية" value={catalog.data?.projects.length ?? 0} icon={Target} />
      </section>
      <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث في المخاطر…" resultText={`عرض ${filteredRisks.length} من ${catalog.data?.risks.length ?? 0} مخاطرة`} isDirty={Boolean(search)} onClear={() => setSearch('')} />
      <Tabs tabs={[{ id: 'risks', label: 'المخاطر' }, { id: 'incidents', label: 'الحوادث' }, { id: 'audits', label: 'التدقيق' }]} activeTab={tab} onTabChange={(id) => setTab(id as 'risks' | 'incidents' | 'audits')} ariaLabel="أقسام الحوكمة">
        {tab === 'risks' && (
          filteredRisks.length ? (
            <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
              <table className="w-full text-sm">
                <thead><tr className="bg-[var(--surface-muted)] text-right">
                  <th className="px-4 py-3 font-semibold">الرقم</th><th className="px-4 py-3 font-semibold">العنوان</th><th className="px-4 py-3 font-semibold">الفئة</th><th className="px-4 py-3 font-semibold">النتيجة</th><th className="px-4 py-3 font-semibold">الحالة</th>
                </tr></thead>
                <tbody className="divide-y divide-[var(--border-color)]">
                  {filteredRisks.map((r) => (
                    <tr key={r.id} className="hover:bg-[var(--surface-hover)]">
                      <td className="px-4 py-3 font-mono text-xs">{r.number}</td>
                      <td className="px-4 py-3 font-medium">{r.title}</td>
                      <td className="px-4 py-3 text-[var(--text-secondary)]">{r.category}</td>
                      <td className="px-4 py-3 text-center"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${r.score >= 12 ? 'bg-red-100 text-red-700' : r.score >= 6 ? 'bg-amber-100 text-amber-700' : 'bg-blue-100 text-blue-700'}`}>{r.score}</span></td>
                      <td className="px-4 py-3"><StatusBadge status="neutral" label={RISK_STATUS[r.status] ?? r.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <EmptyState title="لا توجد مخاطر" description="لا توجد مخاطر مسجلة" />
        )}
        {tab === 'incidents' && (
          (catalog.data?.incidents.length ?? 0) ? (
            <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
              <table className="w-full text-sm">
                <thead><tr className="bg-[var(--surface-muted)] text-right">
                  <th className="px-4 py-3 font-semibold">الرقم</th><th className="px-4 py-3 font-semibold">العنوان</th><th className="px-4 py-3 font-semibold">الخطورة</th><th className="px-4 py-3 font-semibold">الحالة</th>
                </tr></thead>
                <tbody className="divide-y divide-[var(--border-color)]">
                  {catalog.data?.incidents.map((i) => (
                    <tr key={i.id} className="hover:bg-[var(--surface-hover)]">
                      <td className="px-4 py-3 font-mono text-xs">{i.number}</td>
                      <td className="px-4 py-3 font-medium">{i.title}</td>
                      <td className="px-4 py-3"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${i.severity === 'critical' ? 'bg-red-100 text-red-700' : 'bg-blue-100 text-blue-700'}`}>{i.severity}</span></td>
                      <td className="px-4 py-3 text-[var(--text-secondary)]">{i.status}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <EmptyState title="لا توجد حوادث" description="لا توجد حوادث مسجلة" />
        )}
        {tab === 'audits' && (
          (catalog.data?.audits.length ?? 0) ? (
            <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
              <table className="w-full text-sm">
                <thead><tr className="bg-[var(--surface-muted)] text-right">
                  <th className="px-4 py-3 font-semibold">الرمز</th><th className="px-4 py-3 font-semibold">العنوان</th><th className="px-4 py-3 font-semibold">الحالة</th><th className="px-4 py-3 font-semibold">الملاحظات</th>
                </tr></thead>
                <tbody className="divide-y divide-[var(--border-color)]">
                  {catalog.data?.audits.map((a) => (
                    <tr key={a.id} className="hover:bg-[var(--surface-hover)]">
                      <td className="px-4 py-3 font-mono text-xs">{a.code}</td>
                      <td className="px-4 py-3 font-medium">{a.title}</td>
                      <td className="px-4 py-3"><StatusBadge status={a.status === 'completed' ? 'success' : a.status === 'in_progress' ? 'warning' : 'neutral'} label={AUDIT_STATUS[a.status] ?? a.status} /></td>
                      <td className="px-4 py-3 text-center font-bold">{a.findings}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <EmptyState title="لا توجد تدقيقات" description="لا توجد عمليات تدقيق مسجلة" />
        )}
      </Tabs>
    </div>
  );
}
