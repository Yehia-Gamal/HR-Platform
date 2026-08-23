import { useMemo, useState } from 'react';
import type { DocumentItem, AssetItem, OffboardingCase } from '@ahla/shared-contracts';
import { FileCheck, Package, UserMinus, RefreshCw, CheckCircle2, XCircle, Archive } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { ASSET_STATUS_LABELS, DOCUMENT_STATUS_LABELS, OFFBOARDING_STATUS_LABELS, useDocumentsCatalog, useReviewDocument } from './useDocuments';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

type Tab = 'documents' | 'assets' | 'offboarding';

const TABS: { key: Tab; label: string; icon: typeof FileCheck }[] = [
  { key: 'documents', label: 'المستندات', icon: FileCheck },
  { key: 'assets', label: 'العهد والأصول', icon: Package },
  { key: 'offboarding', label: 'إنهاء الخدمة', icon: UserMinus },
];

export function DocumentsPage() {
  const catalog = useDocumentsCatalog();
  const reviewDoc = useReviewDocument();
  const { toast } = useToast();
  const [tab, setTab] = useState<Tab>('documents');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');

  const documents = useMemo(() => catalog.data?.documents ?? [], [catalog.data]);
  const assets = useMemo(() => catalog.data?.assets ?? [], [catalog.data]);
  const offboarding = useMemo(() => catalog.data?.offboarding ?? [], [catalog.data]);

  const filteredDocs = useMemo(() => {
    const q = search.trim().toLowerCase();
    return documents.filter((d) => {
      const matchSearch =
        !q || d.employeeName.toLowerCase().includes(q) || (d.employeeCode ?? '').toLowerCase().includes(q) || d.title.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || d.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [documents, search, statusFilter]);

  const filteredAssets = useMemo(() => {
    const q = search.trim().toLowerCase();
    return assets.filter((a) => {
      const matchSearch = !q || a.name.toLowerCase().includes(q) || (a.assetCode ?? '').toLowerCase().includes(q) || (a.serial ?? '').toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || a.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [assets, search, statusFilter]);

  const filteredOffboarding = useMemo(() => {
    const q = search.trim().toLowerCase();
    return offboarding.filter((o) => {
      const matchSearch =
        !q || o.employeeName.toLowerCase().includes(q) || (o.employeeCode ?? '').toLowerCase().includes(q) || o.caseNumber.toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || o.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [offboarding, search, statusFilter]);

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
  };

  const handleReview = async (doc: DocumentItem, decision: 'verified' | 'rejected' | 'archived') => {
    const reason = decision === 'rejected' ? (window.prompt('سبب الرفض:') ?? '') : undefined;
    try {
      await reviewDoc.mutateAsync({ documentId: doc.id, decision, reason: reason || undefined });
      toast({ message: decision === 'verified' ? 'تم توثيق المستند' : decision === 'rejected' ? 'تم رفض المستند' : 'تم أرشفة المستند', tone: 'success' });
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
    }
  };

  const docColumns: DataTableColumn<DocumentItem>[] = [
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (d) => (
        <div>
          <span className="font-bold">{d.employeeName}</span>
          {d.employeeCode ? <span className="mr-2 text-xs text-[var(--text-muted)]">{d.employeeCode}</span> : null}
        </div>
      ),
    },
    { key: 'title', header: 'المستند', sortable: true, render: (d) => d.title },
    { key: 'type', header: 'النوع', render: (d) => d.type },
    { key: 'number', header: 'الرقم', render: (d) => d.number ?? '—' },
    {
      key: 'expiryDate',
      header: 'الانتهاء',
      sortable: true,
      render: (d) => (d.expiryDate ? dateFormatter.format(new Date(d.expiryDate)) : '—'),
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (d) => <StatusBadge status={d.status} label={DOCUMENT_STATUS_LABELS[d.status] ?? d.status} />,
    },
    {
      key: 'verified',
      header: 'التوثيق',
      render: (d) => (d.verified ? <CheckCircle2 className="size-4 text-[var(--success)]" /> : <XCircle className="size-4 text-[var(--text-muted)]" />),
    },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (d) => (
        <div className="flex gap-1">
          {d.status === 'active' && !d.verified ? (
            <>
              <button
                type="button"
                title="توثيق"
                aria-label={`توثيق ${d.title}`}
                className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--success)] transition hover:bg-[var(--success-soft)]"
                disabled={reviewDoc.isPending}
                onClick={() => void handleReview(d, 'verified')}
              >
                <CheckCircle2 className="size-4" aria-hidden="true" />
              </button>
              <button
                type="button"
                title="رفض"
                aria-label={`رفض ${d.title}`}
                className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--danger)] transition hover:bg-[var(--danger-soft)]"
                disabled={reviewDoc.isPending}
                onClick={() => void handleReview(d, 'rejected')}
              >
                <XCircle className="size-4" aria-hidden="true" />
              </button>
            </>
          ) : (
            <button
              type="button"
              title="أرشفة"
              aria-label={`أرشفة ${d.title}`}
              className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] transition hover:bg-[var(--surface-muted)]"
              disabled={reviewDoc.isPending}
              onClick={() => void handleReview(d, 'archived')}
            >
              <Archive className="size-4" aria-hidden="true" />
            </button>
          )}
        </div>
      ),
    },
  ];

  const assetColumns: DataTableColumn<AssetItem>[] = [
    { key: 'name', header: 'الأصل', sortable: true, render: (a) => <span className="font-bold">{a.name}</span> },
    { key: 'assetCode', header: 'الكود', render: (a) => a.assetCode ?? '—' },
    { key: 'serial', header: 'الرقم التسلسلي', render: (a) => a.serial ?? '—' },
    { key: 'type', header: 'النوع', render: (a) => a.type },
    {
      key: 'assignment',
      header: 'المسلم إليه',
      render: (a) =>
        a.assignment?.employeeName ? (
          <div>
            <span className="font-bold">{a.assignment.employeeName}</span>
            {a.assignment.status ? (
              <span className="mr-2 text-xs text-[var(--text-muted)]">{ASSET_STATUS_LABELS[a.assignment.status] ?? a.assignment.status}</span>
            ) : null}
          </div>
        ) : (
          '—'
        ),
    },
    { key: 'location', header: 'الموقع', render: (a) => a.location ?? '—' },
    {
      key: 'status',
      header: 'الحالة',
      render: (a) => (a.status ? <StatusBadge status={a.status} label={ASSET_STATUS_LABELS[a.status] ?? a.status} /> : '—'),
    },
  ];

  const offboardingColumns: DataTableColumn<OffboardingCase>[] = [
    { key: 'caseNumber', header: 'رقم الحالة', render: (o) => o.caseNumber },
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (o) => (
        <div>
          <span className="font-bold">{o.employeeName}</span>
          {o.employeeCode ? <span className="mr-2 text-xs text-[var(--text-muted)]">{o.employeeCode}</span> : null}
        </div>
      ),
    },
    { key: 'reasonType', header: 'السبب', render: (o) => o.reasonType },
    { key: 'lastWorkingDate', header: 'آخر يوم عمل', render: (o) => (o.lastWorkingDate ? dateFormatter.format(new Date(o.lastWorkingDate)) : '—') },
    { key: 'clearance', header: 'التخليص', render: (o) => `${o.clearance.filter((c) => c.status === 'completed').length}/${o.clearance.length}` },
    {
      key: 'status',
      header: 'الحالة',
      render: (o) => <StatusBadge status={o.status} label={OFFBOARDING_STATUS_LABELS[o.status] ?? o.status} />,
    },
  ];

  const statusOptions =
    tab === 'documents'
      ? Object.entries(DOCUMENT_STATUS_LABELS)
      : tab === 'assets'
        ? Object.entries(ASSET_STATUS_LABELS)
        : Object.entries(OFFBOARDING_STATUS_LABELS);

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="إدارة المستندات"
        description="إدارة مستندات الموظفين والعهد والأصول وعمليات إنهاء الخدمة في مكان واحد."
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
          <MetricCard label="مستندات تنتهي قريباً" value={catalog.data?.expiringDocuments ?? 0} icon={FileCheck} hint="خلال 30 يوماً" onClick={() => setTab('documents')} />
          <MetricCard label="عهد مُسلّمة" value={catalog.data?.assignedAssets ?? 0} icon={Package} hint="موكّلة لموظفين حالياً" onClick={() => setTab('assets')} />
          <MetricCard label="حالات خروج نشطة" value={catalog.data?.openOffboarding ?? 0} icon={UserMinus} hint="قيد التخليص" onClick={() => setTab('offboarding')} />
        </section>
      )}

      <div className="flex gap-1 border-b border-[var(--border)]">
        {TABS.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            className={`inline-flex items-center gap-2 px-4 py-2.5 text-sm font-bold transition ${tab === key ? 'border-b-2 border-[var(--brand)] text-[var(--text-primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}`}
            onClick={() => {
              setTab(key);
              setSearch('');
              setStatusFilter('all');
            }}
          >
            <Icon className="size-4" aria-hidden="true" />
            {label}
          </button>
        ))}
      </div>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder={
          tab === 'documents' ? 'ابحث باسم الموظف أو عنوان المستند…' : tab === 'assets' ? 'ابحث باسم الأصل أو الكود…' : 'ابحث باسم الموظف أو رقم الحالة…'
        }
        resultText={
          tab === 'documents'
            ? `عرض ${filteredDocs.length} من ${documents.length} مستند`
            : tab === 'assets'
              ? `عرض ${filteredAssets.length} من ${assets.length} أصل`
              : `عرض ${filteredOffboarding.length} من ${offboarding.length} حالة`
        }
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {statusOptions.map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
      </FilterBar>

      {catalog.isError ? (
        <ErrorState description={safeErrorMessage(catalog.error)} onRetry={() => void catalog.refetch()} />
      ) : catalog.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل البيانات…" />
      ) : tab === 'documents' ? (
        filteredDocs.length === 0 ? (
          <EmptyState title="لا توجد مستندات" description="لم يُرفع أي مستند موظف بعد." />
        ) : (
          <DataTable<DocumentItem>
            ariaLabel="جدول المستندات"
            rowKey={(d) => d.id}
            data={filteredDocs}
            minWidth="900px"
            columns={docColumns}
            emptyTitle="لا توجد نتائج مطابقة"
            emptyDescription="جرّب تعديل البحث أو الحالة."
          />
        )
      ) : tab === 'assets' ? (
        filteredAssets.length === 0 ? (
          <EmptyState title="لا توجد عهد أو أصول" description="لم تُضف أي أصول أو عهد بعد." />
        ) : (
          <DataTable<AssetItem>
            ariaLabel="جدول العهد والأصول"
            rowKey={(a) => a.id}
            data={filteredAssets}
            minWidth="800px"
            columns={assetColumns}
            emptyTitle="لا توجد نتائج مطابقة"
            emptyDescription="جرّب تعديل البحث أو الحالة."
          />
        )
      ) : filteredOffboarding.length === 0 ? (
        <EmptyState title="لا توجد حالات إنهاء خدمة" description="لم تُسجل أي حالة إنهاء خدمة بعد." />
      ) : (
        <DataTable<OffboardingCase>
          ariaLabel="جدول حالات إنهاء الخدمة"
          rowKey={(o) => o.id}
          data={filteredOffboarding}
          minWidth="800px"
          columns={offboardingColumns}
          emptyTitle="لا توجد نتائج مطابقة"
          emptyDescription="جرّب تعديل البحث أو الحالة."
        />
      )}
    </div>
  );
}
