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
        <span className="filter-bar-title">
          <SlidersHorizontal className="size-4" aria-hidden="true" />
          البحث والتصفية
        </span>
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
      {resultText ? (
        <p className="filter-result" aria-live="polite">
          {resultText}
        </p>
      ) : null}
    </section>
  );
}
