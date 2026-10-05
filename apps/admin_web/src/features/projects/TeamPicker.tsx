import { useId, useMemo, useState } from 'react';
import type { AssociationProjectPickerEmployee } from '@ahla/shared-contracts';
import { Crown, Search, X } from 'lucide-react';

/** تطبيع بسيط للبحث بالعربية (همزات/تاء مربوطة/ياء) حتى يجد «احمد» «أحمد». */
function normalize(text: string): string {
  return text
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/[ً-ْ]/g, '')
    .toLowerCase()
    .trim();
}

function matches(e: AssociationProjectPickerEmployee, q: string): boolean {
  if (!q) return true;
  return normalize(`${e.name} ${e.jobTitle ?? ''} ${e.departmentName ?? ''}`).includes(q);
}

interface PeoplePickerProps {
  label: string;
  hint?: string;
  employees: AssociationProjectPickerEmployee[];
  selected: string[];
  onChange: (ids: string[]) => void;
  /** اختيار شخص واحد فقط (القائد). */
  single?: boolean;
  /** أشخاص لا يظهرون في القائمة (مثل القائد في قائمة الأعضاء). */
  exclude?: string[];
  disabled?: boolean;
}

/** اختيار أشخاص بالبحث — المختارون يظهرون كشرائح قابلة للإزالة. */
export function PeoplePicker({ label, hint, employees, selected, onChange, single, exclude = [], disabled }: PeoplePickerProps) {
  const [query, setQuery] = useState('');
  const listId = useId();
  const q = normalize(query);
  const byId = useMemo(() => new Map(employees.map((e) => [e.id, e])), [employees]);
  const visible = useMemo(
    () => employees.filter((e) => !exclude.includes(e.id) && matches(e, q)).slice(0, 80),
    [employees, exclude, q],
  );

  function toggle(id: string) {
    if (single) {
      onChange([id]);
      setQuery('');
      return;
    }
    onChange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);
  }

  const chosen = selected.map((id) => byId.get(id)).filter((e): e is AssociationProjectPickerEmployee => Boolean(e));

  return (
    <fieldset className="space-y-2" disabled={disabled}>
      <legend className="text-sm font-bold">{label}</legend>
      {hint && <p className="text-xs text-[var(--text-muted)]">{hint}</p>}

      {chosen.length > 0 && (
        <ul className="flex flex-wrap gap-1.5" aria-label={`المختارون: ${label}`}>
          {chosen.map((e) => (
            <li
              key={e.id}
              className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-primary-soft)] px-2.5 py-1 text-xs font-bold text-[var(--brand-primary)]"
            >
              {single && <Crown className="size-3.5" aria-hidden="true" />}
              {e.name}
              {!single && !disabled && (
                <button type="button" onClick={() => toggle(e.id)} aria-label={`إزالة ${e.name}`} className="rounded-full hover:bg-[var(--surface-hover)]">
                  <X className="size-3.5" />
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {!disabled && (
        <>
          <label className="relative block">
            <span className="sr-only">بحث في {label}</span>
            <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
            <input
              className="input !ps-9"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="ابحث بالاسم أو الوظيفة أو الإدارة"
              aria-controls={listId}
            />
          </label>
          <ul id={listId} className="max-h-48 overflow-y-auto rounded-xl border border-[var(--border)] bg-[var(--surface)]" role="listbox" aria-multiselectable={!single}>
            {visible.length === 0 ? (
              <li className="p-3 text-center text-xs text-[var(--text-muted)]">لا توجد نتائج</li>
            ) : (
              visible.map((e) => {
                const isOn = selected.includes(e.id);
                return (
                  <li key={e.id} role="option" aria-selected={isOn}>
                    <button
                      type="button"
                      onClick={() => toggle(e.id)}
                      className={`flex w-full items-center gap-3 px-3 py-2 text-start text-sm hover:bg-[var(--surface-hover)] ${isOn ? 'bg-[var(--brand-primary-soft)]' : ''}`}
                    >
                      <span
                        className={`grid size-4 shrink-0 place-items-center border ${single ? 'rounded-full' : 'rounded'} ${isOn ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]' : 'border-[var(--border-strong)]'}`}
                        aria-hidden="true"
                      >
                        {isOn && <span className="size-1.5 rounded-full bg-white" />}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-bold">{e.name}</span>
                        <span className="block truncate text-xs text-[var(--text-muted)]">
                          {[e.jobTitle, e.departmentName].filter(Boolean).join(' • ') || '—'}
                        </span>
                      </span>
                    </button>
                  </li>
                );
              })
            )}
          </ul>
        </>
      )}
    </fieldset>
  );
}

interface DepartmentPickerProps {
  departments: { id: string; name: string }[];
  selected: string[];
  onChange: (ids: string[]) => void;
  disabled?: boolean;
}

/** إدارات المشروع — اختيارية ومتعددة. */
export function DepartmentPicker({ departments, selected, onChange, disabled }: DepartmentPickerProps) {
  const [query, setQuery] = useState('');
  const q = normalize(query);
  const visible = departments.filter((d) => selected.includes(d.id) || !q || normalize(d.name).includes(q));

  return (
    <fieldset className="space-y-2" disabled={disabled}>
      <legend className="text-sm font-bold">الإدارات المسؤولة (اختياري)</legend>
      <p className="text-xs text-[var(--text-muted)]">
        يمكن ترك المشروع بلا إدارة والاكتفاء بالفريق، أو ربطه بإدارة أو أكثر — موظفو الإدارة المرتبطة يتابعون المشروع ويديرون خطواته.
      </p>
      {departments.length > 8 && (
        <label className="relative block">
          <span className="sr-only">بحث في الإدارات</span>
          <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <input className="input !ps-9" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="ابحث عن إدارة" />
        </label>
      )}
      <div className="flex max-h-36 flex-wrap gap-2 overflow-y-auto">
        {visible.map((d) => {
          const isOn = selected.includes(d.id);
          return (
            <button
              key={d.id}
              type="button"
              aria-pressed={isOn}
              onClick={() => onChange(isOn ? selected.filter((x) => x !== d.id) : [...selected, d.id])}
              className={`filter-chip${isOn ? ' is-active' : ''}`}
            >
              {d.name}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}
