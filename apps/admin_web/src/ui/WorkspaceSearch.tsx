import { Command, Search } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';

export interface SearchDestination {
  label: string;
  to: string;
  group: string;
}

export function WorkspaceSearch({ destinations }: { destinations: SearchDestination[] }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setOpen(true);
      }
      if (event.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  useEffect(() => {
    if (open) window.setTimeout(() => inputRef.current?.focus(), 20);
  }, [open]);

  const results = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return destinations.slice(0, 10);
    return destinations.filter((item) => `${item.label} ${item.group}`.toLowerCase().includes(normalized)).slice(0, 12);
  }, [destinations, query]);

  const choose = (to: string) => {
    navigate(to);
    setOpen(false);
    setQuery('');
  };

  return (
    <>
      <button type="button" className="workspace-search-trigger" onClick={() => setOpen(true)}>
        <Search className="size-4" />
        <span className="hidden sm:inline">بحث سريع في النظام</span>
        <kbd className="hidden lg:inline-flex"><Command className="size-3" />K</kbd>
      </button>
      {open ? (
        <div className="command-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
          <section className="command-dialog" role="dialog" aria-modal="true" aria-label="البحث السريع" onMouseDown={(event) => event.stopPropagation()}>
            <div className="command-input-wrap">
              <Search className="size-5 text-[var(--text-muted)]" />
              <input
                ref={inputRef}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="اكتب اسم الوحدة أو الصفحة…"
                aria-label="البحث في الوحدات"
              />
              <span className="command-esc">ESC</span>
            </div>
            <div className="command-results">
              {results.length === 0 ? <p className="p-6 text-center text-sm text-[var(--text-muted)]">لا توجد نتائج مطابقة.</p> : results.map((item) => (
                <button key={item.to} type="button" onClick={() => choose(item.to)} className="command-result">
                  <span className="command-result-dot" />
                  <span className="min-w-0 flex-1 text-start">
                    <strong className="block truncate text-sm">{item.label}</strong>
                    <small className="block truncate text-xs text-[var(--text-muted)]">{item.group}</small>
                  </span>
                </button>
              ))}
            </div>
          </section>
        </div>
      ) : null}
    </>
  );
}
