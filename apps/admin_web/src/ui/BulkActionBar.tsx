import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { X, type LucideIcon } from 'lucide-react';

/* ───────────────────────── أنواع ───────────────────────── */

export interface BulkAction {
  label: string;
  icon?: LucideIcon;
  onClick: () => void;
  tone?: 'default' | 'danger' | 'success';
  disabled?: boolean;
}

interface BulkActionBarProps {
  selectedCount: number;
  actions: BulkAction[];
  onClearSelection: () => void;
}

/* ───────────────── أنماط الأزرار حسب النبرة ───────────────── */

const toneBtnClass: Record<NonNullable<BulkAction['tone']>, string> = {
  default: 'btn-secondary',
  danger: 'btn-danger',
  success: 'btn-primary',
};

/* ───────────────────── شريط الإجراءات الجماعية ───────────────────── */

export function BulkActionBar({ selectedCount, actions, onClearSelection }: BulkActionBarProps) {
  const [phase, setPhase] = useState<'enter' | 'visible' | 'exit'>('enter');
  const visible = selectedCount > 0;

  // حركة الظهور: enter → visible بعد التركيب
  useEffect(() => {
    if (!visible) {
      setPhase('enter');
      return;
    }
    const frame = requestAnimationFrame(() => {
      requestAnimationFrame(() => setPhase('visible'));
    });
    return () => cancelAnimationFrame(frame);
  }, [visible]);

  if (!visible) return null;

  const animClass = phase === 'visible' ? 'translate-y-0 opacity-100' : 'translate-y-4 opacity-0';

  return createPortal(
    <div
      className={`fixed inset-x-0 bottom-0 z-[90] flex justify-center p-4 transition-all duration-300 ease-out ${animClass}`}
      role="toolbar"
      aria-label="إجراءات جماعية"
    >
      <div
        className="flex w-full max-w-3xl items-center gap-4 rounded-2xl border border-[var(--border)] px-5 py-3 shadow-xl backdrop-blur-md"
        style={{ background: 'color-mix(in srgb, var(--surface) 82%, transparent)' }}
      >
        {/* عدد العناصر المحددة + زر إلغاء التحديد */}
        <div className="flex items-center gap-2">
          <span className="whitespace-nowrap text-sm font-black text-[var(--text-primary)]">تم تحديد {selectedCount} عنصر</span>
          <button
            type="button"
            className="grid size-7 shrink-0 place-items-center rounded-lg text-[var(--text-muted)] transition-colors hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]"
            onClick={onClearSelection}
            aria-label="إلغاء التحديد"
          >
            <X className="size-4" aria-hidden="true" />
          </button>
        </div>

        {/* فاصل عمودي */}
        <div className="h-6 w-px shrink-0 bg-[var(--border)]" aria-hidden="true" />

        {/* أزرار الإجراءات */}
        <div className="flex flex-1 items-center gap-2">
          {actions.map((action) => {
            const Icon = action.icon;
            const btnClass = toneBtnClass[action.tone ?? 'default'];
            return (
              <button key={action.label} type="button" className={`${btnClass} text-xs`} onClick={action.onClick} disabled={action.disabled}>
                {Icon && <Icon className="size-4" aria-hidden="true" />}
                {action.label}
              </button>
            );
          })}
        </div>
      </div>
    </div>,
    document.body,
  );
}
