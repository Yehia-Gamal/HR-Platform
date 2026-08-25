import { cairoTodayIso } from '../../core/cairoTime';
import { useMemo, useState } from 'react';
import { FileSpreadsheet, Printer } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { AUDIT_CATEGORY_LABELS, AUDIT_SEVERITY_LABELS, useAuditTrail, type AuditTrailItem } from '../finance/useFinancialExtensions';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' });

export function AuditTrailPage() {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [severity, setSeverity] = useState('all');
  const query = useAuditTrail({
    category: category === 'all' ? undefined : category,
    severity: severity === 'all' ? undefined : severity,
  });

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    const items = query.data?.items ?? [];
    return q
      ? items.filter(
          (a) =>
            (a.summaryAr ?? '').toLowerCase().includes(q) ||
            (a.eventType ?? '').toLowerCase().includes(q) ||
            (a.targetTable ?? '').toLowerCase().includes(q) ||
            (a.actorName ?? '').toLowerCase().includes(q),
        )
      : items;
  }, [query.data, search]);

  const columns: DataTableColumn<AuditTrailItem>[] = [
    {
      key: 'occurredAt',
      header: 'التاريخ',
      sortable: true,
      render: (a) => <span className="whitespace-nowrap text-xs">{a.occurredAt ? dateFormatter.format(new Date(a.occurredAt)) : '—'}</span>,
    },
    { key: 'actorName', header: 'الفاعل', render: (a) => a.actorName ?? '—' },
    { key: 'eventType', header: 'الحدث', render: (a) => <span className="font-mono text-xs">{a.eventType}</span> },
    {
      key: 'category',
      header: 'التصنيف',
      render: (a) => (a.category ? (AUDIT_CATEGORY_LABELS[a.category] ?? a.category) : '—'),
    },
    {
      key: 'severity',
      header: 'الخطورة',
      render: (a) => (a.severity ? <StatusBadge status={a.severity} label={AUDIT_SEVERITY_LABELS[a.severity] ?? a.severity} /> : '—'),
    },
    { key: 'summaryAr', header: 'الملخص', render: (a) => a.summaryAr ?? '—' },
    { key: 'targetTable', header: 'الجدول', render: (a) => (a.targetTable ? <span className="font-mono text-xs">{a.targetTable}</span> : '—') },
  ];

  const dirty = Boolean(search.trim() || category !== 'all' || severity !== 'all');
  const clearFilters = () => {
    setSearch('');
    setCategory('all');
    setSeverity('all');
  };

  const handleCsvExport = () => {
    const cols: ExportColumn<AuditTrailItem>[] = [
      { key: 'when', header: 'التاريخ', get: (a) => (a.occurredAt ? dateFormatter.format(new Date(a.occurredAt)) : '—') },
      { key: 'actor', header: 'الفاعل', get: (a) => a.actorName },
      { key: 'event', header: 'الحدث', get: (a) => a.eventType },
      { key: 'category', header: 'التصنيف', get: (a) => a.category },
      { key: 'severity', header: 'الخطورة', get: (a) => a.severity },
      { key: 'summary', header: 'الملخص', get: (a) => a.summaryAr },
      { key: 'table', header: 'الجدول', get: (a) => a.targetTable },
    ];
    downloadCsv(`audit-trail-${cairoTodayIso()}.csv`, toCsv(cols, rows));
  };

  const handlePdfExport = () => {
    printReport(
      [
        {
          title: 'سجل التدقيق',
          subtitle: `${rows.length} حدث من ${query.data?.total ?? 0}`,
          table: {
            headers: ['التاريخ', 'الفاعل', 'الحدث', 'التصنيف', 'الخطورة', 'الملخص'],
            rows: rows.map((a) => [
              a.occurredAt ? dateFormatter.format(new Date(a.occurredAt)) : '—',
              a.actorName ?? '—',
              a.eventType,
              a.category ? (AUDIT_CATEGORY_LABELS[a.category] ?? a.category) : '—',
              a.severity ? (AUDIT_SEVERITY_LABELS[a.severity] ?? a.severity) : '—',
              a.summaryAr ?? '—',
            ]),
          },
        },
      ],
      'سجل التدقيق',
    );
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الحوكمة والأمان"
        title="سجل التدقيق"
        description="تتبع تفاعلي لجميع الأحداث المهمة في النظام — من فعل ماذا، ومتى، وعلى أي كيان."
        actions={
          <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
            <Printer className="size-4" aria-hidden="true" />
            PDF
          </button>
        }
      />

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالحدث أو الفاعل أو الملخص…"
        resultText={`عرض ${rows.length} من ${query.data?.total ?? 0}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={category} onChange={(ev) => setCategory(ev.target.value)} aria-label="تصفية حسب التصنيف">
          <option value="all">كل التصنيفات</option>
          {Object.entries(AUDIT_CATEGORY_LABELS).map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
        <select className="input" value={severity} onChange={(ev) => setSeverity(ev.target.value)} aria-label="تصفية حسب الخطورة">
          <option value="all">كل الخطورة</option>
          {Object.entries(AUDIT_SEVERITY_LABELS).map(([key, label]) => (
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

      {query.isError ? (
        <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <ListSkeleton rows={5} label="جارٍ تحميل سجل التدقيق…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد أحداث" description="لا توجد سجلات تدقيق مطابقة للفلاتر الحالية." />
      ) : (
        <DataTable<AuditTrailItem>
          ariaLabel="جدول سجل التدقيق"
          rowKey={(a) => a.id}
          data={rows}
          minWidth="980px"
          columns={columns}
          emptyTitle="لا توجد نتائج"
          emptyDescription="جرّب تعديل البحث أو الفلاتر."
        />
      )}
    </div>
  );
}
