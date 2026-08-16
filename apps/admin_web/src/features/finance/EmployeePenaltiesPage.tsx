import { useMemo, useState, type FormEvent } from 'react';
import { AlertTriangle, FileSpreadsheet, Printer } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useEmployees } from '../employees/useEmployees';
import { PENALTY_STATUS_LABELS, PENALTY_TYPE_LABELS, useAddEmployeePenalty, useEmployeePenalties, useWaiveEmployeePenalty } from './useFinancialExtensions';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

export function EmployeePenaltiesPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const penalties = useEmployeePenalties(statusFilter === 'all' ? {} : { status: statusFilter });
  const addPenalty = useAddEmployeePenalty();
  const waivePenalty = useWaiveEmployeePenalty();
  const { data: employees } = useEmployees();

  const [formOpen, setFormOpen] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [penaltyType, setPenaltyType] = useState('attendance');
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [evidenceRef, setEvidenceRef] = useState('');

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    const items = penalties.data ?? [];
    return q
      ? items.filter(
          (p) =>
            (p.employeeName ?? '').toLowerCase().includes(q) || (p.reason ?? '').toLowerCase().includes(q) || (p.penaltyType ?? '').toLowerCase().includes(q),
        )
      : items;
  }, [penalties.data, search]);

  const columns: DataTableColumn<(typeof rows)[number]>[] = [
    { key: 'employeeName', header: 'الموظف', sortable: true, render: (p) => <span className="font-bold">{p.employeeName ?? '—'}</span> },
    { key: 'departmentName', header: 'الإدارة', render: (p) => p.departmentName ?? '—' },
    { key: 'penaltyType', header: 'النوع', render: (p) => PENALTY_TYPE_LABELS[p.penaltyType] ?? p.penaltyType },
    {
      key: 'reason',
      header: 'السبب',
      render: (p) => (
        <span className="block max-w-[240px] truncate" title={p.reason}>
          {p.reason}
        </span>
      ),
    },
    { key: 'amount', header: 'المبلغ', sortable: true, render: (p) => <span className="font-black text-[var(--danger)]">{formatCurrency(p.amount)}</span> },
    { key: 'issuedAt', header: 'تاريخ الإصدار', render: (p) => (p.issuedAt ? dateFormatter.format(new Date(p.issuedAt)) : '—') },
    {
      key: 'status',
      header: 'الحالة',
      render: (p) => <StatusBadge status={p.status} label={PENALTY_STATUS_LABELS[p.status] ?? p.status} />,
    },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (p) =>
        p.status === 'issued' || p.status === 'deducted' ? (
          <button
            type="button"
            className="btn-ghost text-xs"
            disabled={waivePenalty.isPending}
            onClick={() => {
              const reasonText = window.prompt('سبب الإسقاط:');
              if (reasonText?.trim()) {
                void waivePenalty.mutateAsync({ penaltyId: p.id, reason: reasonText.trim() });
              }
            }}
          >
            إسقاط
          </button>
        ) : null,
    },
  ];

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
  };

  const submitPenalty = async (ev: FormEvent) => {
    ev.preventDefault();
    if (!employeeId) return;
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) return;
    await addPenalty.mutateAsync({
      employeeId,
      penaltyType,
      amount: amt,
      reason: reason.trim(),
      evidenceRef: evidenceRef.trim() || undefined,
    });
    setFormOpen(false);
    setEmployeeId('');
    setAmount('');
    setReason('');
    setEvidenceRef('');
  };

  const handleCsvExport = () => {
    const cols: ExportColumn<(typeof rows)[number]>[] = [
      { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
      { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
      { key: 'type', header: 'النوع', get: (p) => PENALTY_TYPE_LABELS[p.penaltyType] ?? p.penaltyType },
      { key: 'reason', header: 'السبب', get: (p) => p.reason },
      { key: 'amount', header: 'المبلغ', get: (p) => p.amount },
      { key: 'status', header: 'الحالة', get: (p) => PENALTY_STATUS_LABELS[p.status] ?? p.status },
      { key: 'issuedAt', header: 'تاريخ الإصدار', get: (p) => (p.issuedAt ? dateFormatter.format(new Date(p.issuedAt)) : '—') },
    ];
    downloadCsv(`employee-penalties-${new Date().toISOString().slice(0, 10)}.csv`, toCsv(cols, rows));
  };

  const handlePdfExport = () => {
    printReport(
      [
        {
          title: 'المخالفات المالية للموظفين',
          subtitle: `${rows.length} مخالفة`,
          table: {
            headers: ['الموظف', 'الإدارة', 'النوع', 'السبب', 'المبلغ', 'الحالة', 'تاريخ الإصدار'],
            rows: rows.map((p) => [
              p.employeeName ?? '—',
              p.departmentName ?? '—',
              PENALTY_TYPE_LABELS[p.penaltyType] ?? p.penaltyType,
              p.reason,
              formatCurrency(p.amount),
              PENALTY_STATUS_LABELS[p.status] ?? p.status,
              p.issuedAt ? dateFormatter.format(new Date(p.issuedAt)) : '—',
            ]),
          },
        },
      ],
      'المخالفات المالية',
    );
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="المخالفات المالية"
        description="مخالفات تُخصم من رواتب الموظفين — تتبّع الإصدار والإسقاط والربط بدورات الرواتب."
        actions={
          <button type="button" className="btn-primary" onClick={() => setFormOpen((v) => !v)} disabled={addPenalty.isPending}>
            <AlertTriangle className="size-4" aria-hidden="true" />
            إصدار مخالفة
          </button>
        }
      />

      {formOpen && (
        <section className="card p-5">
          <h2 className="font-black">إصدار مخالفة جديدة</h2>
          <form className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5" onSubmit={(ev) => void submitPenalty(ev)}>
            <label className="block">
              <span className="muted text-xs">الموظف *</span>
              <select className="input mt-1" value={employeeId} onChange={(ev) => setEmployeeId(ev.target.value)} required>
                <option value="">اختر الموظف…</option>
                {(employees ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.fullNameAr}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="muted text-xs">النوع *</span>
              <select className="input mt-1" value={penaltyType} onChange={(ev) => setPenaltyType(ev.target.value)}>
                {Object.entries(PENALTY_TYPE_LABELS).map(([key, label]) => (
                  <option key={key} value={key}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="muted text-xs">المبلغ (ج.م) *</span>
              <input
                className="input mt-1"
                type="number"
                min="0"
                step="0.01"
                value={amount}
                onChange={(ev) => setAmount(ev.target.value)}
                placeholder="0.00"
                required
              />
            </label>
            <label className="block">
              <span className="muted text-xs">السبب *</span>
              <input className="input mt-1" value={reason} onChange={(ev) => setReason(ev.target.value)} placeholder="وصف المخالفة" required />
            </label>
            <label className="block">
              <span className="muted text-xs">مرجع مستند</span>
              <input className="input mt-1" value={evidenceRef} onChange={(ev) => setEvidenceRef(ev.target.value)} placeholder="اختياري" />
            </label>
            <div className="flex items-end gap-2 sm:col-span-2 lg:col-span-5">
              <button type="submit" className="btn-primary" disabled={addPenalty.isPending || !employeeId || !reason.trim() || !(Number(amount) > 0)}>
                {addPenalty.isPending ? 'جارٍ الحفظ…' : 'حفظ المخالفة'}
              </button>
              <button type="button" className="btn-secondary" onClick={() => setFormOpen(false)}>
                إلغاء
              </button>
              {addPenalty.isError && <p className="text-sm text-[var(--danger)]">{safeErrorMessage(addPenalty.error)}</p>}
            </div>
          </form>
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالموظف أو السبب…"
        resultText={`عرض ${rows.length} من ${penalties.data?.length ?? 0}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {Object.entries(PENALTY_STATUS_LABELS).map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
        <button type="button" className="btn-secondary" onClick={handleCsvExport} disabled={rows.length === 0} title="تصدير Excel (CSV)">
          <FileSpreadsheet className="size-4" aria-hidden="true" />
          تصدير
        </button>
        <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
          <Printer className="size-4" aria-hidden="true" />
          PDF
        </button>
      </FilterBar>

      {penalties.isError ? (
        <ErrorState description={safeErrorMessage(penalties.error)} onRetry={() => void penalties.refetch()} />
      ) : penalties.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل المخالفات…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد مخالفات" description="لم تُسجل أي مخالفات مالية بعد." />
      ) : (
        <DataTable
          ariaLabel="جدول المخالفات المالية"
          rowKey={(p) => p.id}
          data={rows}
          minWidth="820px"
          columns={columns}
          emptyTitle="لا توجد نتائج"
          emptyDescription="جرّب تعديل البحث أو الحالة."
        />
      )}
    </div>
  );
}
