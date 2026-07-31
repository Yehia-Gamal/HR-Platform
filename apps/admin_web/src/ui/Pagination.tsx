import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useMemo } from 'react';

interface PaginationProps {
  currentPage: number;
  totalPages: number;
  totalItems: number;
  pageSize: number;
  onPageChange: (page: number) => void;
  onPageSizeChange?: (size: number) => void;
}

const PAGE_SIZE_OPTIONS = [10, 25, 50, 100];

/** حساب أرقام الصفحات المعروضة (أقصى حد 5 مع علامات حذف). */
function getVisiblePages(current: number, total: number): (number | 'ellipsis-start' | 'ellipsis-end')[] {
  if (total <= 5) return Array.from({ length: total }, (_, i) => i + 1);

  if (current <= 3) return [1, 2, 3, 4, 'ellipsis-end', total];
  if (current >= total - 2) return [1, 'ellipsis-start', total - 3, total - 2, total - 1, total];

  return [1, 'ellipsis-start', current - 1, current, current + 1, 'ellipsis-end', total];
}

export function Pagination({ currentPage, totalPages, totalItems, pageSize, onPageChange, onPageSizeChange }: PaginationProps) {
  const visiblePages = useMemo(() => getVisiblePages(currentPage, totalPages), [currentPage, totalPages]);

  const isFirst = currentPage <= 1;
  const isLast = currentPage >= totalPages;

  if (totalPages <= 0) return null;

  return (
    <nav className="flex flex-wrap items-center justify-between gap-3 px-1 py-2" aria-label="التنقل بين الصفحات">
      {/* معلومات النتائج */}
      <p className="text-xs font-bold text-[var(--text-muted)]" aria-live="polite">
        عرض {totalItems.toLocaleString('ar-EG')} نتيجة — الصفحة {currentPage.toLocaleString('ar-EG')} من {totalPages.toLocaleString('ar-EG')}
      </p>

      <div className="flex flex-wrap items-center gap-2">
        {/* محدد عدد العناصر في الصفحة */}
        {onPageSizeChange ? (
          <label className="flex items-center gap-1.5 text-xs font-bold text-[var(--text-muted)]">
            <span>عناصر في الصفحة</span>
            <select
              value={pageSize}
              onChange={(e) => onPageSizeChange(Number(e.target.value))}
              className="input !w-auto !py-1.5 !pe-7 !ps-2.5 text-xs"
              aria-label="عدد العناصر في الصفحة"
            >
              {PAGE_SIZE_OPTIONS.map((size) => (
                <option key={size} value={size}>
                  {size.toLocaleString('ar-EG')}
                </option>
              ))}
            </select>
          </label>
        ) : null}

        {/* أزرار التنقل */}
        <div className="flex items-center gap-1" role="group" aria-label="أرقام الصفحات">
          {/* السابق — في RTL السهم لليمين يعني الرجوع */}
          <button type="button" className="filter-chip !px-2" disabled={isFirst} onClick={() => onPageChange(currentPage - 1)} aria-label="الصفحة السابقة">
            <ChevronRight className="size-4" aria-hidden="true" />
          </button>

          {visiblePages.map((page) => {
            if (typeof page === 'string') {
              return (
                <span
                  key={page}
                  className="flex min-h-[44px] min-w-[36px] items-center justify-center text-xs font-bold text-[var(--text-muted)]"
                  aria-hidden="true"
                >
                  …
                </span>
              );
            }

            const isActive = page === currentPage;
            return (
              <button
                key={page}
                type="button"
                className={`filter-chip !min-w-[36px] !px-1.5 ${isActive ? 'is-active' : ''}`}
                onClick={() => onPageChange(page)}
                aria-label={`الصفحة ${page.toLocaleString('ar-EG')}`}
                aria-current={isActive ? 'page' : undefined}
              >
                {page.toLocaleString('ar-EG')}
              </button>
            );
          })}

          {/* التالي — في RTL السهم لليسار يعني التقدم */}
          <button type="button" className="filter-chip !px-2" disabled={isLast} onClick={() => onPageChange(currentPage + 1)} aria-label="الصفحة التالية">
            <ChevronLeft className="size-4" aria-hidden="true" />
          </button>
        </div>
      </div>
    </nav>
  );
}
