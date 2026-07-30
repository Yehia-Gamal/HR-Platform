import { useState } from 'react';
import { AlertTriangle, Info, Loader2 } from 'lucide-react';
import { DialogOverlay } from './DialogOverlay';

type Tone = 'danger' | 'warning' | 'info';

const toneConfig: Record<Tone, { icon: typeof AlertTriangle; color: string; softColor: string; btnClass: string }> = {
  danger:  { icon: AlertTriangle, color: 'var(--danger)',  softColor: 'var(--danger-soft)',  btnClass: 'btn-danger' },
  warning: { icon: AlertTriangle, color: 'var(--warning)', softColor: 'var(--warning-soft)', btnClass: 'btn-primary' },
  info:    { icon: Info,          color: 'var(--info)',    softColor: 'var(--info-soft)',    btnClass: 'btn-primary' },
};

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = 'تأكيد',
  cancelLabel = 'إلغاء',
  tone = 'danger',
  onConfirm,
  onCancel,
  loading = false,
  requireTypedConfirmation,
}: {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: Tone;
  onConfirm: () => void;
  onCancel: () => void;
  loading?: boolean;
  requireTypedConfirmation?: string;
}) {
  const [typed, setTyped] = useState('');

  if (!open) return null;

  const cfg = toneConfig[tone];
  const Icon = cfg.icon;
  const needsTyping = !!requireTypedConfirmation;
  const typingMatch = !needsTyping || typed === requireTypedConfirmation;

  return (
    <DialogOverlay title={title} onClose={loading ? () => {} : onCancel} maxWidth="max-w-md">
      <div className="grid place-items-center text-center">
        {/* أيقونة النبرة */}
        <span
          className="mx-auto grid size-14 place-items-center rounded-2xl"
          style={{ background: cfg.softColor, color: cfg.color }}
        >
          <Icon className="size-6" aria-hidden="true" />
        </span>

        <p className="mt-4 text-sm leading-7 text-[var(--text-muted)]">{message}</p>

        {/* حقل كتابة التأكيد — للعمليات الحرجة */}
        {needsTyping && (
          <div className="mt-4 w-full">
            <label className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">
              اكتب <span className="font-black text-[var(--text-primary)]">{requireTypedConfirmation}</span> للتأكيد
            </label>
            <input
              className="input w-full text-center"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              disabled={loading}
              autoFocus
            />
          </div>
        )}
      </div>

      {/* أزرار الإجراء */}
      <div className="mt-6 flex gap-3">
        <button
          className="btn-secondary flex-1"
          onClick={onCancel}
          disabled={loading}
        >
          {cancelLabel}
        </button>
        <button
          className={`${cfg.btnClass} flex-1`}
          onClick={onConfirm}
          disabled={loading || !typingMatch}
        >
          {loading && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          {confirmLabel}
        </button>
      </div>
    </DialogOverlay>
  );
}
