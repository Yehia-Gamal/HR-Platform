import { useEffect, useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';

const FOCUSABLE = 'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
const INPUT_SELECTOR = 'textarea:not([disabled]),input:not([disabled]),select:not([disabled])';

export function DialogOverlay({
  title,
  onClose,
  children,
  maxWidth = 'max-w-3xl',
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  maxWidth?: string;
}) {
  const titleId = useId();
  const dialogRef = useRef<HTMLElement>(null);
  const previousFocusRef = useRef<Element | null>(null);
  const onCloseRef = useRef(onClose);

  useEffect(() => {
    onCloseRef.current = onClose;
  });

  useEffect(() => {
    // حفظ العنصر الحالي لاستعادة التركيز عند الإغلاق
    previousFocusRef.current = document.activeElement;

    // نقل التركيز إلى أول حقل إدخال إن وُجد، وإلا أول عنصر قابل للتركيز —
    // حتى لا يُسرق التركيز من الحقول بواسطة زر الإغلاق (X) عند كل إعادة رندر.
    const dialog = dialogRef.current;
    if (dialog) {
      const firstInput = dialog.querySelector<HTMLElement>(INPUT_SELECTOR);
      const firstFocusable = dialog.querySelector<HTMLElement>(FOCUSABLE);
      const target = firstInput ?? firstFocusable;
      if (target) target.focus();
    }

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onCloseRef.current();
        return;
      }

      // حبس التركيز داخل المودال — Tab و Shift+Tab يدوران داخلها فقط
      if (e.key === 'Tab' && dialog) {
        const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE));
        if (!focusable.length) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        if (e.shiftKey) {
          if (document.activeElement === first) {
            e.preventDefault();
            last.focus();
          }
        } else {
          if (document.activeElement === last) {
            e.preventDefault();
            first.focus();
          }
        }
      }
    };

    document.addEventListener('keydown', onKeyDown);
    document.body.style.overflow = 'hidden';

    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = '';
      // استعادة التركيز للعنصر السابق
      if (previousFocusRef.current instanceof HTMLElement) {
        previousFocusRef.current.focus();
      }
    };
  }, []);

  return createPortal(
    <div
      className="fixed inset-0 z-[100] grid place-items-center overflow-y-auto bg-[rgb(3_10_23/58%)] p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <section ref={dialogRef} className={`card ${maxWidth} w-full max-h-[90vh] overflow-y-auto p-6`}>
        <div className="mb-5 flex items-center justify-between">
          <h2 id={titleId} className="text-xl font-black">
            {title}
          </h2>
          <button className="icon-button" onClick={onClose} aria-label="إغلاق">
            <X className="size-5" />
          </button>
        </div>
        {children}
      </section>
    </div>,
    document.body,
  );
}
