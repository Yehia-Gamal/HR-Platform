import { Search, SlidersHorizontal, X } from 'lucide-react';
import type { ReactNode } from 'react';

interface FilterBarProps {
  searchValue: string;
  onSearchChange: (value: string) => void;
  searchPlaceholder: string;
  children?: ReactNode;
  resultText?: string;
  isDirty?: boolean;
  onClear?: () => void;
  /** محتوى إضافي يُعرض داخل حقل البحث (مثل قائمة اقتراحات حيّة) */
  searchAdornment?: ReactNode;
  /** يُستدعى عند تغيّر حالة تركيز حقل البحث */
  onSearchFocusChange?: (focused: boolean) => void;
}

export function FilterBar({
  searchValue,
  onSearchChange,
  searchPlaceholder,
  children,
  resultText,
  isDirty = false,
  onClear,
  searchAdornment,
  onSearchFocusChange,
}: FilterBarProps) {
  return (
    <section className="filter-bar" aria-label="البحث والتصفية">
      <div className="filter-bar-heading">
        <div className="flex items-center gap-2.5">
          <span className="filter-bar-title">
            <SlidersHorizontal className="size-4" aria-hidden="true" />
            البحث والتصفية
          </span>
          {resultText ? (
            <span className="filter-result inline-block !m-0 !text-[11px] font-bold text-[var(--text-muted)] bg-[var(--surface-muted)] px-2.5 py-0.5 rounded-full border border-[var(--border-subtle)]" aria-live="polite">
              {resultText}
            </span>
          ) : null}
        </div>
        {isDirty && onClear ? (
          <button type="button" className="filter-clear" onClick={onClear}>
            <X className="size-3.5" aria-hidden="true" />
            مسح الكل
          </button>
        ) : null}
      </div>
      <div className="filter-bar-grid">
        <label className="filter-search">
          <span className="sr-only">بحث</span>
          <Search aria-hidden="true" />
          <input
            value={searchValue}
            onChange={(event) => onSearchChange(event.target.value)}
            placeholder={searchPlaceholder}
            className="input"
            type="search"
            onFocus={() => onSearchFocusChange?.(true)}
            onBlur={() => onSearchFocusChange?.(false)}
          />
          {searchAdornment}
        </label>
        {children}
      </div>
    </section>
  );
}
