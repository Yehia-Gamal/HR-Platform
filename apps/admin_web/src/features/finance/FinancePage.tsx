import { useMemo, useState } from 'react';
import type { PeopleFinanceCatalog } from '@ahla/shared-contracts';
import { WalletCards, TrendingUp, HandCoins, RefreshCw, Users2, Megaphone } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import {
  CAMPAIGN_STATUS_LABELS,
  LOAN_STATUS_LABELS,
  PAYROLL_RUN_STATUS_LABELS,
  SALARY_STRUCTURE_STATUS_LABELS,
  WORKFORCE_PLAN_STATUS_LABELS,
  usePeopleFinanceCatalog,
} from './usePeopleFinance';

type Catalog = PeopleFinanceCatalog;

type PayrollRun = Catalog['payrollRuns'][number];
type SalaryStructure = Catalog['salaryStructures'][number];
type LoanItem = Catalog['loans'][number];
type WorkforcePlan = Catalog['workforcePlans'][number];
type CampaignItem = Catalog['campaigns'][number];

type Tab = 'payroll' | 'structures' | 'loans' | 'workforce' | 'campaigns';

const TABS: { key: Tab; label: string; icon: typeof WalletCards }[] = [
  { key: 'payroll', label: 'دورات الرواتب', icon: WalletCards },
  { key: 'structures', label: 'هياكل الرواتب', icon: TrendingUp },
  { key: 'loans', label: 'السلف والقروض', icon: HandCoins },
  { key: 'workforce', label: 'خطط القوى العاملة', icon: Users2 },
  { key: 'campaigns', label: 'حملات المشاركة', icon: Megaphone },
];

const CAMPAIGN_TYPE_LABELS: Record<string, string> = {
  survey: 'استبيان',
  recognition: 'تقدير',
  wellbeing: 'رفاهية',
  communication: 'تواصل',
};

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

export function FinancePage() {
  const catalog = usePeopleFinanceCatalog();
  const [tab, setTab] = useState<Tab>('payroll');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');

  const payrollRuns = useMemo(() => catalog.data?.payrollRuns ?? [], [catalog.data]);
  const structures = useMemo(() => catalog.data?.salaryStructures ?? [], [catalog.data]);
  const loans = useMemo(() => catalog.data?.loans ?? [], [catalog.data]);
  const workforcePlans = useMemo(() => catalog.data?.workforcePlans ?? [], [catalog.data]);
  const campaigns = useMemo(() => catalog.data?.campaigns ?? [], [catalog.data]);

  const filteredPayroll = useMemo(() => {
    const q = search.trim().toLowerCase();
    return payrollRuns.filter((r) => {
      const matchSearch = !q || r.periodMonth.includes(q) || r.status.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || r.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [payrollRuns, search, statusFilter]);

  const filteredStructures = useMemo(() => {
    const q = search.trim().toLowerCase();
    return structures.filter((s) => {
      const matchSearch = !q || s.name.toLowerCase().includes(q) || s.code.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || (s.active ? 'active' : 'inactive') === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [structures, search, statusFilter]);

  const filteredLoans = useMemo(() => {
    const q = search.trim().toLowerCase();
    return loans.filter((l) => {
      const matchSearch = !q || l.employeeName.toLowerCase().includes(q) || l.loanType.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || l.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [loans, search, statusFilter]);

  const filteredWorkforce = useMemo(() => {
    const q = search.trim().toLowerCase();
    return workforcePlans.filter((w) => {
      const matchSearch = !q || w.departmentName.toLowerCase().includes(q) || String(w.year).includes(q);
      const matchStatus = statusFilter === 'all' || w.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [workforcePlans, search, statusFilter]);

  const filteredCampaigns = useMemo(() => {
    const q = search.trim().toLowerCase();
    return campaigns.filter((c) => {
      const matchSearch = !q || c.title.toLowerCase().includes(q) || c.campaignType.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || c.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [campaigns, search, statusFilter]);

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => { setSearch(''); setStatusFilter('all'); };

  const payrollColumns: DataTableColumn<PayrollRun>[] = [
    { key: 'periodMonth', header: 'الشهر', sortable: true, render: (r) => r.periodMonth },
    { key: 'currency', header: 'العملة', render: (r) => r.currency },
    {
      key: 'totals',
      header: 'الإجماليات',
      render: (r) => {
        const totals = r.totals as Record<string, unknown> | null;
        const gross = totals?.gross as number | undefined;
        const net = totals?.net as number | undefined;
        return (
          <div className="text-xs">
            {gross != null ? <div><span className="text-[var(--text-muted)]">إجمالي:</span> {formatCurrency(gross)}</div> : null}
            {net != null ? <div><span className="text-[var(--text-muted)]">صافي:</span> {formatCurrency(net)}</div> : null}
            {!gross && !net ? '—' : null}
          </div>
        );
      },
    },
    {
      key: 'calculatedAt',
      header: 'تاريخ الحساب',
      render: (r) => (r.calculatedAt ? dateFormatter.format(new Date(r.calculatedAt)) : '—'),
    },
    {
      key: 'approvedAt',
      header: 'تاريخ الاعتماد',
      render: (r) => (r.approvedAt ? dateFormatter.format(new Date(r.approvedAt)) : '—'),
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (r) => <StatusBadge status={r.status} label={PAYROLL_RUN_STATUS_LABELS[r.status] ?? r.status} />,
    },
  ];

  const structureColumns: DataTableColumn<SalaryStructure>[] = [
    { key: 'code', header: 'الكود', sortable: true, render: (s) => s.code },
    { key: 'name', header: 'الاسم', sortable: true, render: (s) => <span className="font-bold">{s.name}</span> },
    { key: 'currency', header: 'العملة', render: (s) => s.currency },
    {
      key: 'effectiveFrom',
      header: 'ساري من',
      render: (s) => dateFormatter.format(new Date(s.effectiveFrom)),
    },
    {
      key: 'effectiveTo',
      header: 'ينتهي',
      render: (s) => (s.effectiveTo ? dateFormatter.format(new Date(s.effectiveTo)) : '—'),
    },
    {
      key: 'active',
      header: 'الحالة',
      render: (s) => <StatusBadge status={s.active ? 'active' : 'inactive'} label={s.active ? 'نشط' : 'غير نشط'} />,
    },
  ];

  const loanColumns: DataTableColumn<LoanItem>[] = [
    { key: 'employeeName', header: 'الموظف', sortable: true, render: (l) => <span className="font-bold">{l.employeeName}</span> },
    { key: 'loanType', header: 'النوع', render: (l) => l.loanType },
    { key: 'principalAmount', header: 'المبلغ الأصلي', sortable: true, render: (l) => formatCurrency(l.principalAmount) },
    { key: 'outstandingAmount', header: 'المتبقي', sortable: true, render: (l) => formatCurrency(l.outstandingAmount) },
    {
      key: 'status',
      header: 'الحالة',
      render: (l) => <StatusBadge status={l.status} label={LOAN_STATUS_LABELS[l.status] ?? l.status} />,
    },
  ];

  const workforceColumns: DataTableColumn<WorkforcePlan>[] = [
    { key: 'year', header: 'السنة', sortable: true, render: (w) => w.year },
    { key: 'departmentName', header: 'الإدارة', sortable: true, render: (w) => <span className="font-bold">{w.departmentName}</span> },
    { key: 'approvedHeadcount', header: 'العدد المعتمد', render: (w) => w.approvedHeadcount },
    { key: 'plannedHires', header: 'التعيينات المخططة', render: (w) => w.plannedHires },
    { key: 'plannedCost', header: 'التكلفة المخططة', render: (w) => formatCurrency(w.plannedCost) },
    {
      key: 'status',
      header: 'الحالة',
      render: (w) => <StatusBadge status={w.status} label={WORKFORCE_PLAN_STATUS_LABELS[w.status] ?? w.status} />,
    },
  ];

  const campaignColumns: DataTableColumn<CampaignItem>[] = [
    { key: 'title', header: 'العنوان', sortable: true, render: (c) => <span className="font-bold">{c.title}</span> },
    {
      key: 'campaignType',
      header: 'النوع',
      render: (c) => CAMPAIGN_TYPE_LABELS[c.campaignType] ?? c.campaignType,
    },
    {
      key: 'startsAt',
      header: 'يبدأ',
      render: (c) => (c.startsAt ? dateFormatter.format(new Date(c.startsAt)) : '—'),
    },
    {
      key: 'endsAt',
      header: 'ينتهي',
      render: (c) => (c.endsAt ? dateFormatter.format(new Date(c.endsAt)) : '—'),
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (c) => <StatusBadge status={c.status} label={CAMPAIGN_STATUS_LABELS[c.status] ?? c.status} />,
    },
  ];

  const statusOptions = tab === 'payroll'
    ? Object.entries(PAYROLL_RUN_STATUS_LABELS)
    : tab === 'loans'
      ? Object.entries(LOAN_STATUS_LABELS)
      : tab === 'workforce'
        ? Object.entries(WORKFORCE_PLAN_STATUS_LABELS)
        : tab === 'campaigns'
          ? Object.entries(CAMPAIGN_STATUS_LABELS)
          : Object.entries(SALARY_STRUCTURE_STATUS_LABELS);

  const currentData = tab === 'payroll' ? filteredPayroll : tab === 'structures' ? filteredStructures : tab === 'loans' ? filteredLoans : tab === 'campaigns' ? filteredCampaigns : filteredWorkforce;
  const totalCount = tab === 'payroll' ? payrollRuns.length : tab === 'structures' ? structures.length : tab === 'loans' ? loans.length : tab === 'campaigns' ? campaigns.length : workforcePlans.length;

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="المالية"
        title="الرواتب والمالية"
        description="إدارة دورات الرواتب وهياكل الأجور والسلف وخطط القوى العاملة."
        actions={
          <button type="button" className="btn-secondary" onClick={() => void catalog.refetch()} disabled={catalog.isFetching}>
            <RefreshCw className={`size-4 ${catalog.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
            تحديث
          </button>
        }
      />

      {catalog.isLoading ? (
        <MetricSkeletonRow count={3} />
      ) : (
        <section className="grid gap-3 sm:grid-cols-3">
          <MetricCard label="دورات رواتب" value={payrollRuns.length} icon={WalletCards} hint="إجمالي الدورات" />
          <MetricCard label="هياكل رواتب نشطة" value={structures.filter((s) => s.active).length} icon={TrendingUp} hint={`من ${structures.length} هيكل`} />
          <MetricCard label="سلف نشطة" value={loans.filter((l) => l.status === 'active').length} icon={HandCoins} hint={`من ${loans.length} سلفة`} />
        </section>
      )}

      {tab === 'campaigns' && !catalog.isLoading && (
        <section className="grid gap-3 sm:grid-cols-3">
          <MetricCard label="حملات نشطة" value={campaigns.filter((c) => c.status === 'active').length} icon={Megaphone} hint={`من ${campaigns.length} حملة`} />
          <MetricCard label="استبيانات" value={campaigns.filter((c) => c.campaignType === 'survey').length} icon={Megaphone} hint="نوع استبيان" />
          <MetricCard label="مكتملة" value={campaigns.filter((c) => c.status === 'completed').length} icon={Megaphone} hint="حملات مكتملة" />
        </section>
      )}

      <div className="flex gap-1 border-b border-[var(--border)]">
        {TABS.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            className={`inline-flex items-center gap-2 px-4 py-2.5 text-sm font-bold transition ${tab === key ? 'border-b-2 border-[var(--brand)] text-[var(--text-primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}`}
            onClick={() => { setTab(key); setSearch(''); setStatusFilter('all'); }}
          >
            <Icon className="size-4" aria-hidden="true" />
            {label}
          </button>
        ))}
      </div>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder={tab === 'payroll' ? 'ابحث بالشهر…' : tab === 'structures' ? 'ابحث باسم أو كود الهيكل…' : tab === 'loans' ? 'ابحث باسم الموظف…' : 'ابحث باسم الإدارة…'}
        resultText={`عرض ${currentData.length} من ${totalCount}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {statusOptions.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
        </select>
      </FilterBar>

      {catalog.isError ? (
        <ErrorState description={safeErrorMessage(catalog.error)} onRetry={() => void catalog.refetch()} />
      ) : catalog.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل البيانات المالية…" />
      ) : currentData.length === 0 ? (
        <EmptyState title="لا توجد بيانات" description="لم تُسجل أي بيانات في هذا القسم بعد." />
      ) : tab === 'payroll' ? (
        <DataTable<PayrollRun> ariaLabel="جدول دورات الرواتب" rowKey={(r) => r.id} data={filteredPayroll} minWidth="800px" columns={payrollColumns} emptyTitle="لا توجد نتائج مطابقة" emptyDescription="جرّب تعديل البحث أو الحالة." />
      ) : tab === 'structures' ? (
        <DataTable<SalaryStructure> ariaLabel="جدول هياكل الرواتب" rowKey={(s) => s.id} data={filteredStructures} minWidth="700px" columns={structureColumns} emptyTitle="لا توجد نتائج مطابقة" emptyDescription="جرّب تعديل البحث أو الحالة." />
      ) : tab === 'loans' ? (
        <DataTable<LoanItem> ariaLabel="جدول السلف والقروض" rowKey={(l) => l.id} data={filteredLoans} minWidth="700px" columns={loanColumns} emptyTitle="لا توجد نتائج مطابقة" emptyDescription="جرّب تعديل البحث أو الحالة." />
      ) : tab === 'campaigns' ? (
        <DataTable<CampaignItem> ariaLabel="جدول حملات المشاركة" rowKey={(c) => c.id} data={filteredCampaigns} minWidth="700px" columns={campaignColumns} emptyTitle="لا توجد نتائج مطابقة" emptyDescription="جرّب تعديل البحث أو الحالة." />
      ) : (
        <DataTable<WorkforcePlan> ariaLabel="جدول خطط القوى العاملة" rowKey={(w) => w.id} data={filteredWorkforce} minWidth="700px" columns={workforceColumns} emptyTitle="لا توجد نتائج مطابقة" emptyDescription="جرّب تعديل البحث أو الحالة." />
      )}
    </div>
  );
}
