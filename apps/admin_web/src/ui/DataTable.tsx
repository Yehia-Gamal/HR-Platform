import { ArrowDownUp, ArrowDownAZ, ArrowUpAZ } from 'lucide-react';
import { type ReactNode, useCallback, useMemo, useState } from 'react';
import { EmptyState } from './EmptyState';

/** وصف عمود واحد في الجدول. */
export interface DataTableColumn<T> {
  key: string;
  header: string;
  render?: (row: T, index: number) => ReactNode;
  sortable?: boolean;
}

interface DataTableProps<T> {
  columns: DataTableColumn<T>[];
  data: T[];
  loading?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
  selectable?: boolean;
  selectedKeys?: Set<string>;
  onSelectionChange?: (keys: Set<string>) => void;
  rowKey: (row: T) => string;
  minWidth?: string;
  ariaLabel?: string;
}

type SortDir = 'ascending' | 'descending';

export function DataTable<T>({
  columns,
  data,
  loading = false,
  emptyTitle = 'لا توجد بيانات',
  emptyDescription = 'لم يتم العثور على أي سجلات لعرضها.',
  emptyAction,
  selectable = false,
  selectedKeys,
  onSelectionChange,
  rowKey,
  minWidth = '720px',
  ariaLabel = 'جدول بيانات',
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDir>('ascending');

  const handleSort = useCallback(
    (key: string) => {
      if (sortKey === key) {
        setSortDir((prev) => (prev === 'ascending' ? 'descending' : 'ascending'));
      } else {
        setSortKey(key);
        setSortDir('ascending');
      }
    },
    [sortKey],
  );

  const sorted = useMemo(() => {
    if (!sortKey) return data;
    const col = columns.find((c) => c.key === sortKey);
    if (!col?.sortable) return data;
    const dir = sortDir === 'ascending' ? 1 : -1;
    return [...data].sort((a, b) => {
      const va = (a as Record<string, unknown>)[sortKey];
      const vb = (b as Record<string, unknown>)[sortKey];
      if (va == null && vb == null) return 0;
      if (va == null) return dir;
      if (vb == null) return -dir;
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * dir;
      return String(va).localeCompare(String(vb), 'ar') * dir;
    });
  }, [data, sortKey, sortDir, columns]);

  const allKeys = useMemo(() => new Set(data.map(rowKey)), [data, rowKey]);
  const allSelected = selectable && selectedKeys && allKeys.size > 0 && allKeys.size === selectedKeys.size && [...allKeys].every((k) => selectedKeys.has(k));
  const someSelected = selectable && selectedKeys && selectedKeys.size > 0 && !allSelected;

  const toggleAll = useCallback(() => {
    if (!onSelectionChange) return;
    onSelectionChange(allSelected ? new Set() : new Set(allKeys));
  }, [allSelected, allKeys, onSelectionChange]);

  const toggleRow = useCallback(
    (key: string) => {
      if (!onSelectionChange || !selectedKeys) return;
      const next = new Set(selectedKeys);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      onSelectionChange(next);
    },
    [selectedKeys, onSelectionChange],
  );

  /* حالة التحميل — هيكل عظمي */
  if (loading) {
    return (
      <section className="card overflow-hidden" aria-busy="true" aria-label="جارٍ التحميل…">
        <div className="overflow-x-auto">
          <table className="data-table w-full text-start text-sm" style={{ minWidth }}>
            <thead className="bg-[var(--surface-muted)] text-xs text-[var(--text-muted)]">
              <tr>
                {selectable ? (
                  <th scope="col" className="w-12 px-4 py-3.5">
                    <span className="sr-only">تحديد</span>
                  </th>
                ) : null}
                {columns.map((col) => (
                  <th key={col.key} scope="col" className="px-4 py-3.5">
                    {col.header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {Array.from({ length: 3 }).map((_, rowIdx) => (
                <tr key={rowIdx} aria-hidden="true">
                  {selectable ? (
                    <td className="px-4 py-3.5">
                      <div className="h-4 w-4 animate-pulse rounded bg-[var(--surface-muted)]" />
                    </td>
                  ) : null}
                  {columns.map((col, colIdx) => (
                    <td key={col.key} className="px-4 py-3.5">
                      <div className={`h-4 animate-pulse rounded bg-[var(--surface-muted)] ${colIdx === 0 ? 'w-2/3' : 'w-1/2'}`} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    );
  }

  /* حالة فارغة */
  if (data.length === 0) {
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  }

  return (
    <section className="card overflow-hidden">
      <div className="overflow-x-auto">
        <table className="data-table w-full text-start text-sm" style={{ minWidth }} aria-label={ariaLabel}>
          <thead className="bg-[var(--surface-muted)] text-xs text-[var(--text-muted)]">
            <tr>
              {selectable ? (
                <th scope="col" className="w-12 px-4 py-3.5">
                  <input
                    type="checkbox"
                    checked={allSelected}
                    ref={(el) => {
                      if (el) el.indeterminate = Boolean(someSelected);
                    }}
                    onChange={toggleAll}
                    aria-label="تحديد الكل"
                    className="size-4 accent-[var(--brand-primary)]"
                  />
                </th>
              ) : null}
              {columns.map((col) => {
                const ariaSortValue = col.sortable && sortKey === col.key ? sortDir : undefined;
                return (
                  <th key={col.key} scope="col" className="px-4 py-3.5" aria-sort={ariaSortValue}>
                    {col.sortable ? (
                      <button
                        type="button"
                        className="inline-flex items-center gap-1.5 border-0 bg-transparent p-0 font-[inherit] text-[inherit] hover:text-[var(--text-primary)]"
                        onClick={() => handleSort(col.key)}
                        aria-label={`ترتيب حسب ${col.header}`}
                      >
                        {col.header}
                        {sortKey === col.key ? (
                          sortDir === 'ascending' ? (
                            <ArrowDownAZ className="size-3.5" aria-hidden="true" />
                          ) : (
                            <ArrowUpAZ className="size-3.5" aria-hidden="true" />
                          )
                        ) : (
                          <ArrowDownUp className="size-3.5 opacity-40" aria-hidden="true" />
                        )}
                      </button>
                    ) : (
                      col.header
                    )}
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {sorted.map((row, rowIndex) => {
              const key = rowKey(row);
              const isSelected = selectable && selectedKeys?.has(key);
              return (
                <tr key={key} aria-selected={selectable ? isSelected : undefined}>
                  {selectable ? (
                    <td className="px-4 py-3.5">
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => toggleRow(key)}
                        aria-label="تحديد الصف"
                        className="size-4 accent-[var(--brand-primary)]"
                      />
                    </td>
                  ) : null}
                  {columns.map((col) => (
                    <td key={col.key} className="px-4 py-3.5">
                      {col.render ? col.render(row, rowIndex) : String((row as Record<string, unknown>)[col.key] ?? '—')}
                    </td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}
