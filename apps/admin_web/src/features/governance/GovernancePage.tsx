import { AlertTriangle, ClipboardList, Plus, ShieldAlert } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useIncidents, useRisks, useUpsertIncident, useUpsertRisk } from './useGovernance';

type Tab = 'risks' | 'incidents';

const SEVERITIES: Record<string, string> = {
  low: 'منخفض',
  medium: 'متوسط',
  high: 'مرتفع',
  critical: 'حرج',
};

const LIKELIHOODS: Record<string, string> = {
  low: 'منخفض',
  medium: 'متوسط',
  high: 'مرتفع',
};

const RISK_STATUSES = ['open', 'mitigating', 'accepted', 'closed'];
const INCIDENT_STATUSES = ['open', 'investigating', 'resolved', 'closed'];

function date(value: string | null) {
  if (!value) return 'غير محدد';
  return new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

export function GovernancePage() {
  const auth = useAuth();
  const risksQuery = useRisks();
  const incidentsQuery = useIncidents();
  const upsertRisk = useUpsertRisk();
  const upsertIncident = useUpsertIncident();
  const [tab, setTab] = useState<Tab>('risks');
  const [search, setSearch] = useState('');
  const [riskOpen, setRiskOpen] = useState(false);
  const [incidentOpen, setIncidentOpen] = useState(false);
  const [riskDraft, setRiskDraft] = useState({ title: '', description: '', likelihood: 'low', impact: 'medium', severity: 'medium', status: 'open' });
  const [incidentDraft, setIncidentDraft] = useState({ title: '', description: '', severity: 'medium', status: 'open' });

  const canManage = Boolean(auth.access && hasPermission(auth.access, 'governance.data.manage'));

  const risks = useMemo(() => risksQuery.data ?? [], [risksQuery.data]);
  const incidents = useMemo(() => incidentsQuery.data ?? [], [incidentsQuery.data]);
  const term = search.trim().toLocaleLowerCase('ar');

  const filteredRisks = useMemo(() => {
    if (!term) return risks;
    return risks.filter((r) => `${r.title} ${r.description ?? ''} ${r.owner_name ?? ''}`.toLocaleLowerCase('ar').includes(term));
  }, [risks, term]);

  const filteredIncidents = useMemo(() => {
    if (!term) return incidents;
    return incidents.filter((i) => `${i.title} ${i.description ?? ''} ${i.reporter_name ?? ''}`.toLocaleLowerCase('ar').includes(term));
  }, [incidents, term]);

  const criticalRisks = risks.filter((r) => r.severity === 'critical' || r.severity === 'high').length;
  const openIncidents = incidents.filter((i) => i.status === 'open' || i.status === 'investigating').length;
  const openRisks = risks.filter((r) => r.status === 'open' || r.status === 'mitigating').length;

  async function submitRisk(event: FormEvent) {
    event.preventDefault();
    try {
      await upsertRisk.mutateAsync(riskDraft);
      setRiskOpen(false);
      setRiskDraft({ title: '', description: '', likelihood: 'low', impact: 'medium', severity: 'medium', status: 'open' });
    } catch {
      /* error via ErrorBanner */
    }
  }

  async function submitIncident(event: FormEvent) {
    event.preventDefault();
    try {
      await upsertIncident.mutateAsync(incidentDraft);
      setIncidentOpen(false);
      setIncidentDraft({ title: '', description: '', severity: 'medium', status: 'open' });
    } catch {
      /* error via ErrorBanner */
    }
  }

  const riskColumns: DataTableColumn<(typeof risks)[number]>[] = [
    { key: 'title', header: 'المخاطرة', sortable: true, render: (r) => <span className="font-medium">{r.title}</span> },
    { key: 'severity', header: 'الشدة', render: (r) => <StatusBadge status={r.severity} label={SEVERITIES[r.severity]} /> },
    { key: 'likelihood', header: 'الاحتمال', render: (r) => <StatusBadge status={r.likelihood} label={LIKELIHOODS[r.likelihood] ?? r.likelihood} /> },
    { key: 'status', header: 'الحالة', render: (r) => <StatusBadge status={r.status} /> },
    { key: 'owner', header: 'المسؤول', render: (r) => r.owner_name ?? '—' },
    { key: 'updated_at', header: 'آخر تحديث', sortable: true, render: (r) => date(r.updated_at) },
  ];

  const incidentColumns: DataTableColumn<(typeof incidents)[number]>[] = [
    { key: 'title', header: 'الحادث', sortable: true, render: (i) => <span className="font-medium">{i.title}</span> },
    { key: 'severity', header: 'الشدة', render: (i) => <StatusBadge status={i.severity} label={SEVERITIES[i.severity]} /> },
    { key: 'status', header: 'الحالة', render: (i) => <StatusBadge status={i.status} /> },
    { key: 'reporter', header: 'المبلّغ', render: (i) => i.reporter_name ?? '—' },
    { key: 'created_at', header: 'التاريخ', sortable: true, render: (i) => date(i.created_at) },
  ];

  const activeLoading = tab === 'risks' ? risksQuery.isLoading : incidentsQuery.isLoading;
  const activeError = tab === 'risks' ? risksQuery.isError : incidentsQuery.isError;
  const activeRefetch = tab === 'risks' ? risksQuery.refetch : incidentsQuery.refetch;
  const activeRows = tab === 'risks' ? filteredRisks : filteredIncidents;

  return (
    <div className="space-y-6">
      <PageHeader
        title="الحوكمة والالتزام"
        description="سجل المخاطر والحوادث: تحديد المخاطر التشغيلية، تقييم الشدة، ومتابعة الإجراءات التصحيحية."
        actions={
          canManage ? (
            <div className="flex flex-wrap items-center gap-2">
              <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={() => setIncidentOpen(true)}>
                <Plus className="size-4" /> حادث جديد
              </button>
              <button type="button" className="btn-primary inline-flex items-center gap-2" onClick={() => setRiskOpen(true)}>
                <Plus className="size-4" /> مخاطرة جديدة
              </button>
            </div>
          ) : null
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="مخاطر حرجة" value={criticalRisks} icon={ShieldAlert} hint="بشدة مرتفعة أو حرجة" onClick={() => setTab('risks')} />
        <MetricCard label="مخاطر مفتوحة" value={openRisks} icon={AlertTriangle} hint="قيد التقييم أو المعالجة" onClick={() => setTab('risks')} />
        <MetricCard label="حوادث مفتوحة" value={openIncidents} icon={AlertTriangle} hint="مفتوحة أو قيد التحقيق" onClick={() => setTab('incidents')} />
        <MetricCard label="إجمالي الحوادث" value={incidents.length} icon={ClipboardList} hint="كل الحوادث المسجلة" onClick={() => setTab('incidents')} />
      </div>

      <div className="card flex items-center gap-4 p-2">
        {(['risks', 'incidents'] as Tab[]).map((key) => (
          <button key={key} type="button" onClick={() => setTab(key)} className={`filter-chip ${tab === key ? 'filter-chip-active' : ''}`}>
            {key === 'risks' ? 'سجل المخاطر' : 'سجل الحوادث'}
          </button>
        ))}
      </div>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder={tab === 'risks' ? 'ابحث في المخاطر...' : 'ابحث في الحوادث...'}
        resultText={`${activeRows.length} سجل`}
      />

      {activeError ? (
        <ErrorState title="تعذر تحميل البيانات" description={safeErrorMessage(activeError)} onRetry={() => void activeRefetch()} />
      ) : activeLoading ? (
        <ListSkeleton rows={5} />
      ) : activeRows.length === 0 ? (
        <EmptyState title="لا توجد سجلات" description="لم يتم العثور على سجلات مطابقة." />
      ) : tab === 'risks' ? (
        <DataTable ariaLabel="جدول المخاطر" rowKey={(r) => r.id} data={filteredRisks} columns={riskColumns} minWidth="900px" />
      ) : (
        <DataTable ariaLabel="جدول الحوادث" rowKey={(r) => r.id} data={filteredIncidents} columns={incidentColumns} minWidth="900px" />
      )}

      {upsertRisk.isError ? <ErrorBanner message={safeErrorMessage(upsertRisk.error)} /> : null}
      {upsertIncident.isError ? <ErrorBanner message={safeErrorMessage(upsertIncident.error)} /> : null}

      {riskOpen ? (
        <DialogOverlay title="مخاطرة جديدة" onClose={() => setRiskOpen(false)} maxWidth="max-w-lg">
          <form onSubmit={submitRisk} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              <span>العنوان *</span>
              <input
                className="input"
                required
                value={riskDraft.title}
                onChange={(e) => setRiskDraft({ ...riskDraft, title: e.target.value })}
                placeholder="مثال: تأخر صرف الرواتب"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span>الوصف</span>
              <textarea
                className="input min-h-24"
                value={riskDraft.description}
                onChange={(e) => setRiskDraft({ ...riskDraft, description: e.target.value })}
              />
            </label>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-sm">
                <span>الاحتمال</span>
                <select className="input" value={riskDraft.likelihood} onChange={(e) => setRiskDraft({ ...riskDraft, likelihood: e.target.value })}>
                  {Object.entries(LIKELIHOODS).map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                <span>الأثر</span>
                <select className="input" value={riskDraft.impact} onChange={(e) => setRiskDraft({ ...riskDraft, impact: e.target.value })}>
                  {Object.entries(LIKELIHOODS).map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                <span>الشدة</span>
                <select className="input" value={riskDraft.severity} onChange={(e) => setRiskDraft({ ...riskDraft, severity: e.target.value })}>
                  {Object.entries(SEVERITIES).map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                <span>الحالة</span>
                <select className="input" value={riskDraft.status} onChange={(e) => setRiskDraft({ ...riskDraft, status: e.target.value })}>
                  {RISK_STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" className="btn-secondary" onClick={() => setRiskOpen(false)}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary">
                حفظ
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}

      {incidentOpen ? (
        <DialogOverlay title="حادث جديد" onClose={() => setIncidentOpen(false)} maxWidth="max-w-lg">
          <form onSubmit={submitIncident} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              <span>العنوان *</span>
              <input
                className="input"
                required
                value={incidentDraft.title}
                onChange={(e) => setIncidentDraft({ ...incidentDraft, title: e.target.value })}
                placeholder="مثال: حادثة وصول غير مصرح به"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span>الوصف</span>
              <textarea
                className="input min-h-24"
                value={incidentDraft.description}
                onChange={(e) => setIncidentDraft({ ...incidentDraft, description: e.target.value })}
              />
            </label>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-sm">
                <span>الشدة</span>
                <select className="input" value={incidentDraft.severity} onChange={(e) => setIncidentDraft({ ...incidentDraft, severity: e.target.value })}>
                  {Object.entries(SEVERITIES).map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                <span>الحالة</span>
                <select className="input" value={incidentDraft.status} onChange={(e) => setIncidentDraft({ ...incidentDraft, status: e.target.value })}>
                  {INCIDENT_STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" className="btn-secondary" onClick={() => setIncidentOpen(false)}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary">
                تسجيل
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}
