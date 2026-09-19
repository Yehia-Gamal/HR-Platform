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
          disabled={loading}
          autoFocus
          dir="rtl"
        />
      </label>

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
