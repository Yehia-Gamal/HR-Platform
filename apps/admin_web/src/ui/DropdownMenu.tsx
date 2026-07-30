import { useCallback, useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import type { LucideIcon } from 'lucide-react';

/* ───────────────────────── أنواع البيانات ───────────────────────── */

export interface DropdownItem {
  label: string;
  icon?: LucideIcon;
  onClick?: () => void;
  disabled?: boolean;
  danger?: boolean;
  divider?: boolean;
}

interface DropdownMenuProps {
  trigger: ReactNode;
  items: DropdownItem[];
}

/* ───────────────────────── مساعدات داخلية ───────────────────────── */

const FOCUSABLE_ITEM = '[role="menuitem"]:not([aria-disabled="true"])';

/** حساب موضع القائمة بالنسبة للزر — يراعي RTL ويبقيها داخل الشاشة */
function computePosition(anchor: DOMRect): Record<string, number> {
  const GAP = 6;
  const MARGIN = 8;
  const isRtl = document.documentElement.dir === 'rtl' ||
    getComputedStyle(document.documentElement).direction === 'rtl';

  let top = anchor.bottom + GAP;
  // لو القائمة ستتجاوز أسفل الشاشة — نعرضها فوق الزر
  if (top + 200 > window.innerHeight) {
    top = Math.max(MARGIN, anchor.top - GAP - 200);
  }

  const style: Record<string, number> = { top };

  // في RTL: نمحاذي الحافة اليمنى للزر — في LTR: الحافة اليسرى
  if (isRtl) {
    style.right = Math.max(MARGIN, Math.min(
      window.innerWidth - anchor.right,
      window.innerWidth - 220 - MARGIN,
    ));
  } else {
    style.left = Math.max(MARGIN, Math.min(
      anchor.left,
      window.innerWidth - 220 - MARGIN,
    ));
  }

  return style;
}

/* ───────────────────────── المكوّن الرئيسي ───────────────────────── */

export function DropdownMenu({ trigger, items }: DropdownMenuProps) {
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<Record<string, number>>({});
  const menuId = useId();
  const triggerRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  /* ─── فتح / إغلاق ─── */

  const toggle = useCallback(() => {
    setOpen(prev => {
      if (!prev && triggerRef.current) {
        setPosition(computePosition(triggerRef.current.getBoundingClientRect()));
      }
      return !prev;
    });
  }, []);

  const close = useCallback(() => setOpen(false), []);

  /* ─── إغلاق عند النقر خارج القائمة ─── */

  useEffect(() => {
    if (!open) return;

    const onPointerDown = (e: PointerEvent) => {
      const target = e.target as Node;
      if (menuRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      close();
    };

    document.addEventListener('pointerdown', onPointerDown, true);
    return () => document.removeEventListener('pointerdown', onPointerDown, true);
  }, [open, close]);

  /* ─── التنقل بلوحة المفاتيح ─── */

  useEffect(() => {
    if (!open) return;

    // نقل التركيز لأول عنصر عند الفتح
    const menu = menuRef.current;
    if (menu) {
      const first = menu.querySelector<HTMLElement>(FOCUSABLE_ITEM);
      if (first) first.focus();
    }

    const onKeyDown = (e: KeyboardEvent) => {
      if (!menu) return;

      if (e.key === 'Escape') {
        e.preventDefault();
        close();
        // إعادة التركيز للزر
        const btn = triggerRef.current?.querySelector<HTMLElement>('button, [tabindex]');
        if (btn) btn.focus();
        else triggerRef.current?.focus();
        return;
      }

      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const focusable = Array.from(menu.querySelectorAll<HTMLElement>(FOCUSABLE_ITEM));
        if (!focusable.length) return;
        const idx = focusable.indexOf(document.activeElement as HTMLElement);
        const next = e.key === 'ArrowDown'
          ? focusable[(idx + 1) % focusable.length]
          : focusable[(idx - 1 + focusable.length) % focusable.length];
        next.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [open, close]);

  /* ─── تحديث الموقع عند تمرير الصفحة أو تغيير حجمها ─── */

  useEffect(() => {
    if (!open) return;

    const update = () => {
      if (triggerRef.current) {
        setPosition(computePosition(triggerRef.current.getBoundingClientRect()));
      }
    };

    window.addEventListener('scroll', update, true);
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('scroll', update, true);
      window.removeEventListener('resize', update);
    };
  }, [open]);

  /* ─── معالجة النقر على عنصر ─── */

  const handleItemClick = (item: DropdownItem) => {
    if (item.disabled || !item.onClick) return;
    item.onClick();
    close();
  };

  /* ─── العرض ─── */

  return (
    <>
      {/* زر التفعيل */}
      <div
        ref={triggerRef}
        onClick={toggle}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        className="inline-flex"
      >
        {trigger}
      </div>

      {/* القائمة المنسدلة */}
      {open && createPortal(
        <div
          ref={menuRef}
          id={menuId}
          role="menu"
          aria-label="قائمة الإجراءات"
          className="fixed z-[150] min-w-[200px] rounded-xl border border-[var(--border)] bg-[var(--surface)] p-1.5 shadow-lg"
          style={position}
        >
          {items.map((item, i) => {
            if (item.divider) {
              return (
                <div
                  key={`divider-${i}`}
                  role="separator"
                  className="my-1.5 border-t border-[var(--border)]"
                />
              );
            }

            const Icon = item.icon;

            return (
              <button
                key={`${item.label}-${i}`}
                role="menuitem"
                type="button"
                tabIndex={-1}
                aria-disabled={item.disabled || undefined}
                disabled={item.disabled}
                onClick={() => handleItemClick(item)}
                className={`flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-bold transition-colors
                  ${item.danger
                    ? 'text-[var(--danger)] hover:bg-[var(--danger-soft)]'
                    : 'text-[var(--text-primary)] hover:bg-[var(--surface-muted)]'
                  }
                  ${item.disabled ? 'pointer-events-none opacity-40' : 'cursor-pointer'}
                `}
              >
                {Icon && <Icon className="size-4 shrink-0" aria-hidden="true" />}
                {item.label}
              </button>
            );
          })}
        </div>,
        document.body,
      )}
    </>
  );
}
