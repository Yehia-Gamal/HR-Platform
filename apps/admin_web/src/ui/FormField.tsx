import type { ReactNode } from 'react';

// ─── حقل نموذج موحد (label + محتوى + تلميح + خطأ) ──────────────────────────
export function FormField({ label, hint, error, children }: { label: string; hint?: string; error?: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      {children}
      {hint ? <span className="muted mt-1 block text-xs">{hint}</span> : null}
      {error !== undefined ? <span className="mt-1 block min-h-4 text-xs text-[var(--danger)]">{error}</span> : null}
    </label>
  );
}

// ─── حقل نصي ────────────────────────────────────────────────────────────────
export function TextInput({
  label,
  value,
  onChange,
  required,
  disabled,
  placeholder,
  type = 'text',
  hint,
  error,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  disabled?: boolean;
  placeholder?: string;
  type?: string;
  hint?: string;
  error?: string;
}) {
  return (
    <FormField label={label} hint={hint} error={error}>
      <input
        className="input"
        type={type}
        required={required}
        disabled={disabled}
        placeholder={placeholder}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </FormField>
  );
}

// ─── حقل رقمي مع حد أدنى ────────────────────────────────────────────────────
export function NumberInput({
  label,
  value,
  onChange,
  min,
  hint,
  error,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
  min: number;
  hint?: string;
  error?: string;
}) {
  return (
    <FormField label={label} hint={hint} error={error}>
      <input className="input" type="number" min={min} required value={value} onChange={(e) => onChange(Math.max(min, Number(e.target.value) || min))} />
    </FormField>
  );
}

// ─── قائمة منسدلة ───────────────────────────────────────────────────────────
export function SelectField({
  label,
  value,
  onChange,
  required,
  disabled,
  children,
  options,
  withPlaceholder = true,
  placeholderOption = 'اختر…',
  hint,
  error,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  disabled?: boolean;
  children?: ReactNode;
  options?: Array<{ id: string; name: string }>;
  withPlaceholder?: boolean;
  placeholderOption?: string;
  hint?: string;
  error?: string;
}) {
  return (
    <FormField label={label} hint={hint} error={error}>
      <select className="input" required={required} disabled={disabled} aria-label={label} value={value} onChange={(e) => onChange(e.target.value)}>
        {withPlaceholder ? <option value="">{placeholderOption}</option> : null}
        {options
          ? options.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))
          : children}
      </select>
    </FormField>
  );
}
