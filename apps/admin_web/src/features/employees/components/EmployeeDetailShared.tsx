import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';

export function Info({ icon: Icon, label, dir }: { icon: LucideIcon; label: ReactNode; dir?: 'ltr' | 'rtl' }) {
  return (
    <span className="inline-flex items-center gap-2">
      <Icon className="size-4 muted" aria-hidden="true" />
      <span dir={dir}>{label}</span>
    </span>
  );
}

export function Data({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-3">
      <p className="muted text-xs">{label}</p>
      <p className="mt-1 font-bold">{value ?? '—'}</p>
    </div>
  );
}

export function LookupSelect({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <select className="input w-full" value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled}>
        <option value="">— غير محدد —</option>
        {options.map((opt) => (
          <option key={opt.id} value={opt.id}>
            {opt.label}
          </option>
        ))}
      </select>
    </label>
  );
}
