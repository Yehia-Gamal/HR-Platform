import { AlertTriangle, Info, Loader2 } from 'lucide-react';
import { DialogOverlay } from './DialogOverlay';

type Tone = 'danger' | 'warning' | 'info';

const toneConfig: Record<Tone, { icon: typeof AlertTriangle; color: string; softColor: string; btnClass: string }> = {
  danger: { icon: AlertTriangle, color: 'var(--danger)', softColor: 'var(--danger-soft)', btnClass: 'btn-danger' },
  warning: { icon: AlertTriangle, color: 'var(--warning)', softColor: 'var(--warning-soft)', btnClass: 'btn-primary' },
  info: { icon: Info, color: 'var(--info)', softColor: 'var(--info-soft)', btnClass: 'btn-primary' },
};

export function InputDialog({
  open,
  title,
  message,
  inputLabel,
  inputPlaceholder,
  inputValue,
  onInputChange,
  confirmLabel = 'تأكيد',
  cancelLabel = 'إلغاء',
  tone = 'warning',
  onConfirm,
  onCancel,
  loading = false,
  required = true,
  minLength = 0,
  error = null,
  quickSuggestions,
}: {
  open: boolean;
  title: string;
  message: string;
  inputLabel: string;
  inputPlaceholder?: string;
  inputValue: string;
  onInputChange: (value: string) => void;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: Tone;
  onConfirm: () => void;
  onCancel: () => void;
  loading?: boolean;
  required?: boolean;
  minLength?: number;
  error?: string | null;
  quickSuggestions?: string[];
}) {
  if (!open) return null;

  const cfg = toneConfig[tone];
  const Icon = cfg.icon;
  const canSubmit = required ? inputValue.trim().length >= minLength : true;

  return (
    <DialogOverlay title={title} onClose={loading ? () => {} : onCancel} maxWidth="max-w-md">
      <div className="grid place-items-center text-center">
        <span className="mx-auto grid size-14 place-items-center rounded-2xl" style={{ background: cfg.softColor, color: cfg.color }}>
          <Icon className="size-6" aria-hidden="true" />
        </span>

        <p className="mt-4 text-sm leading-7 text-[var(--text-muted)]">{message}</p>
      </div>

      <label className="mt-4 block">
        <span className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">{inputLabel}</span>
        <input
          className="input w-full"
          placeholder={inputPlaceholder}
          value={inputValue}
          onChange={(e) => onInputChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && canSubmit && !loading) {
              e.preventDefault();
              onConfirm();
            }
          }}
          disabled={loading}
          autoFocus
          dir="rtl"
        />
      </label>

      {quickSuggestions && quickSuggestions.length > 0 && (
        <div className="mt-2.5 flex flex-wrap gap-1.5 text-xs">
          <span className="text-[11px] font-bold text-[var(--text-muted)] w-full text-start mb-0.5">أسباب واختيارات سريعة:</span>
          {quickSuggestions.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => onInputChange(s)}
              className="text-[11px] font-semibold px-2 py-0.5 rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] hover:bg-[var(--primary)]/10 hover:border-[var(--primary)]/40 active:scale-95 transition-all cursor-pointer text-start text-[var(--text-secondary)] hover:text-[var(--primary)]"
            >
              + {s}
            </button>
          ))}
        </div>
      )}

      {error && (
        <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-3 text-xs font-semibold text-rose-700 dark:border-rose-900/50 dark:bg-rose-950/40 dark:text-rose-300">
          {error}
        </div>
      )}

      <div className="mt-6 flex gap-3">
        <button className="btn-secondary flex-1" onClick={onCancel} disabled={loading}>
          {cancelLabel}
        </button>
        <button className={`${cfg.btnClass} flex-1`} onClick={onConfirm} disabled={loading || !canSubmit}>
          {loading && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          {confirmLabel}
        </button>
      </div>
    </DialogOverlay>
  );
}
