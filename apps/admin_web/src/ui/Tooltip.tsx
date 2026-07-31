import { useCallback, useId, useRef, useState, type ReactNode } from 'react';

type TooltipPosition = 'top' | 'bottom' | 'start' | 'end';

const DEFAULT_DELAY = 300;

/* ───────────────────────── مكون التلميح ───────────────────────── */

export function Tooltip({
  content,
  children,
  position = 'top',
  delay = DEFAULT_DELAY,
}: {
  content: string;
  children: ReactNode;
  position?: TooltipPosition;
  delay?: number;
}) {
  const tooltipId = useId();
  const [visible, setVisible] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const show = useCallback(() => {
    clearTimer();
    timerRef.current = setTimeout(() => setVisible(true), delay);
  }, [delay, clearTimer]);

  const hide = useCallback(() => {
    clearTimer();
    setVisible(false);
  }, [clearTimer]);

  // اتجاه التلميح + سهم التوجيه
  const positionClasses: Record<TooltipPosition, string> = {
    top: 'bottom-full mb-2 start-1/2 -translate-x-1/2',
    bottom: 'top-full mt-2 start-1/2 -translate-x-1/2',
    start: 'end-full me-2 top-1/2 -translate-y-1/2',
    end: 'start-full ms-2 top-1/2 -translate-y-1/2',
  };

  const arrowClasses: Record<TooltipPosition, string> = {
    top: 'top-full start-1/2 -translate-x-1/2 border-t-[var(--text-primary)] border-x-transparent border-b-transparent',
    bottom: 'bottom-full start-1/2 -translate-x-1/2 border-b-[var(--text-primary)] border-x-transparent border-t-transparent',
    start: 'start-full top-1/2 -translate-y-1/2 border-s-[var(--text-primary)] border-y-transparent border-e-transparent',
    end: 'end-full top-1/2 -translate-y-1/2 border-e-[var(--text-primary)] border-y-transparent border-s-transparent',
  };

  return (
    <span className="relative inline-flex" onMouseEnter={show} onMouseLeave={hide} onFocus={show} onBlur={hide}>
      {/* العنصر الملفوف */}
      <span aria-describedby={visible ? tooltipId : undefined}>{children}</span>

      {/* فقاعة التلميح */}
      <span
        id={tooltipId}
        role="tooltip"
        className={`
          pointer-events-none absolute z-50 max-w-[240px] rounded-lg
          bg-[var(--text-primary)] px-2.5 py-1.5 text-xs font-bold leading-5
          text-white shadow-lg
          transition-opacity duration-200 ease-out
          ${positionClasses[position]}
          ${visible ? 'opacity-100' : 'opacity-0'}
        `}
        aria-hidden={!visible}
      >
        {content}
        {/* سهم التوجيه */}
        <span className={`absolute size-0 border-4 ${arrowClasses[position]}`} aria-hidden="true" />
      </span>
    </span>
  );
}
