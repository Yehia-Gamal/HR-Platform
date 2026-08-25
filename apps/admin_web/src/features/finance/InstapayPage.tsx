import { cairoTodayIso } from '../../core/cairoTime';
import { useMemo, useState } from 'react';
import { FileSpreadsheet, Printer, Send } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { usePeopleFinanceCatalog } from './usePeopleFinance';
import { INSTAPAY_STATUS_LABELS, useGenerateInstapayBatch, useInstapayBatches, type InstapayBatch } from './useFinancialExtensions';
const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

export function InstapayPage() {
  const finance = usePeopleFinanceCatalog();
  const batches = useInstapayBatches();
  const generateBatch = useGenerateInstapayBatch();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedRunId, setSelectedRunId] = useState('');

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    const items = batches.data ?? [];
    return items.filter((b) => {
      const matchSearch = !q || (b.batchReference ?? '').toLowerCase().includes(q) || (b.periodMonth ?? '').toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || b.status === statusFilter;
      return matchSearch && matchStatus;
    });
  }, [batches.data, search, statusFilter]);

  const approvedRuns = useMemo(() => (finance.data?.payrollRuns ?? []).filter((r) => ['approved', 'posted'].includes(r.status)), [finance.data]);

  const columns: DataTableColumn<InstapayBatch>[] = [
    { key: 'periodMonth', header: 'الشهر', sortable: true, render: (b) => <span className="font-bold">{b.periodMonth ?? '—'}</span> },
    { key: 'batchReference', header: 'رقم الدفعة', render: (b) => <span className="font-mono text-xs">{b.batchReference ?? '—'}</span> },
    { key: 'itemCount', header: 'العدد', render: (b) => b.itemCount },
    { key: 'totalAmount', header: 'الإجمالي', sortable: true, render: (b) => <span className="font-black">{formatCurrency(b.totalAmount)}</span> },
    { key: 'status', header: 'الحالة', render: (b) => <StatusBadge status={b.status} label={INSTAPAY_STATUS_LABELS[b.status] ?? b.status} /> },
    { key: 'createdAt', header: 'التاريخ', render: (b) => (b.createdAt ? dateFormatter.format(new Date(b.createdAt)) : '—') },
  ];

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
  };

  const handleGenerate = async () => {
    if (!selectedRunId) return;
    await generateBatch.mutateAsync(selectedRunId);
    setSelectedRunId('');
  };

  const handleCsvExport = () => {
    const items = rows.flatMap((b) => b.items.map((i) => ({ ...i, batchReference: b.batchReference, periodMonth: b.periodMonth })));
    const cols: ExportColumn<(typeof items)[number]>[] = [
      { key: 'batch', header: 'رقم الدفعة', get: (i) => i.batchReference },
      { key: 'period', header: 'الشهر', get: (i) => i.periodMonth },
      { key: 'employee', header: 'الموظف', get: (i) => i.employeeName },
      { key: 'mobile', header: 'رقم الجوال', get: (i) => i.mobileE164 },
      { key: 'amount', header: 'المبلغ', get: (i) => i.amount },
      { key: 'status', header: 'الحالة', get: (i) => INSTAPAY_STATUS_LABELS[i.status] ?? i.status },
    ];
    downloadCsv(`instapay-batches-${cairoTodayIso()}.csv`, toCsv(cols, items));
  };

  const handlePdfExport = () => {
    printReport(
      rows.map((b) => ({
        title: `دفعة InstaPay — ${b.periodMonth ?? ''}`,
        subtitle: `${b.batchReference ?? ''} · ${b.itemCount} عنصر`,
        table: {
          headers: ['الموظف', 'رقم الجوال', 'المبلغ', 'الحالة'],
          rows: b.items.map((i) => [i.employeeName ?? '—', i.mobileE164 ?? '—', formatCurrency(i.amount), INSTAPAY_STATUS_LABELS[i.status] ?? i.status]),
        },
      })),
      'دفعات صرف الرواتب عبر InstaPay',
    );
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="المالية"
        title="صرف الرواتب عبر InstaPay"
        description="توليد دفعات تحويل لرواتب الموظفين عبر المحافظ الإلكترونية — تُبنى من دورات الرواتب المعتمدة."
        actions={
          <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
            <Printer className="size-4" aria-hidden="true" />
            PDF
          </button>
        }
      />

      <section className="card p-5">
        <h2 className="font-black">توليد دفعة جديدة</h2>
        <p className="muted mt-1 text-sm">اختر دورة رواتب معتمدة (approved/posted) لإنشاء دفعة InstaPay منها — تشمل الموظفين الذين لديهم رقم جوال.</p>
        <div className="mt-4 flex flex-wrap items-end gap-3">
          <label className="block min-w-[260px] flex-1">
            <span className="muted text-xs">دورة الرواتب</span>
            <select className="input mt-1" value={selectedRunId} onChange={(ev) => setSelectedRunId(ev.target.value)}>
              <option value="">اختر الدورة…</option>
              {approvedRuns.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.periodMonth} — {r.status}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className="btn-primary"
            disabled={!selectedRunId || generateBatch.isPending || finance.isLoading}
            onClick={() => void handleGenerate()}
          >
            <Send className="size-4" aria-hidden="true" />
            {generateBatch.isPending ? 'جارٍ التوليد…' : 'توليد الدفعة'}
          </button>
        </div>
        {generateBatch.isError && <p className="mt-3 text-sm text-[var(--danger)]">{safeErrorMessage(generateBatch.error)}</p>}
        {generateBatch.isSuccess && <p className="mt-3 rounded-xl bg-[var(--success-soft)] p-3 text-sm text-[var(--success)]">تم توليد الدفعة بنجاح.</p>}
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث برقم الدفعة أو الشهر…"
        resultText={`عرض ${rows.length} من ${batches.data?.length ?? 0}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {Object.entries(INSTAPAY_STATUS_LABELS).map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
        <button type="button" className="btn-secondary" onClick={handleCsvExport} disabled={rows.length === 0} title="تصدير Excel (CSV)">
          <FileSpreadsheet className="size-4" aria-hidden="true" />
          تصدير
        </button>
      </FilterBar>

      {batches.isError ? (
        <ErrorState description={safeErrorMessage(batches.error)} onRetry={() => void batches.refetch()} />
      ) : batches.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل دفعات InstaPay…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد دفعات بعد" description="ولّد أول دفعة InstaPay من دورة رواتب معتمدة." />
      ) : (
        <DataTable<InstapayBatch>
          ariaLabel="جدول دفعات InstaPay"
          rowKey={(b) => b.id}
          data={rows}
          minWidth="720px"
          columns={columns}
          emptyTitle="لا توجد نتائج"
          emptyDescription="جرّب تعديل البحث أو الحالة."
        />
      )}
    </div>
  );
}
