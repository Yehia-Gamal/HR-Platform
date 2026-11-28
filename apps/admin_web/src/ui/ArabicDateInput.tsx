import { Calendar } from 'lucide-react';
import { forwardRef, useCallback, useEffect, useRef, useState, type ChangeEvent, type InputHTMLAttributes, type MouseEvent } from 'react';

/**
 * يحوّل قيمة التاريخ ISO (`YYYY-MM-DD` أو `YYYY-MM-DDTHH:mm`) إلى عرض عربي موحد
 * (`YYYY/MM/DD` أو `YYYY/MM/DD HH:mm`) بأرقام غربية مستقلة عن لغة نظام التشغيل.
 */
export function formatArabicDateDisplay(isoDate: string | number | readonly string[] | undefined): string {
  const raw = typeof isoDate === 'string' ? isoDate.trim() : '';
  if (!raw) return '';
  const dtMatch = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(raw);
  if (dtMatch) {
    return `${dtMatch[1]}/${dtMatch[2]}/${dtMatch[3]} ${dtMatch[4]}:${dtMatch[5]}`;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(raw);
  if (!match) return raw;
  return `${match[1]}/${match[2]}/${match[3]}`;
}

export interface ArabicDateInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  type?: 'date' | 'datetime-local';
  /** إخفاء أيقونة التقويم عند وضع الحقل داخل شريط يمتلك أيقونة مسبقة. */
  hideIcon?: boolean;
  /** نص بديل يظهر عند خلوّ الحقل. */
  emptyLabel?: string;
}

/**
 * مكوّن تاريخ موحد يعتمد على `<input type="date" | "datetime-local">` داخلياً للحفاظ على التكامل
 * مع النماذج ومحدِّد النظام وقارئات الشاشة، مع طبقة عرض `yyyy/mm/dd` ثابتة
 * بدلاً من تنسيق النظام الأمريكي `mm/dd/yyyy`.
 */
export const ArabicDateInput = forwardRef<HTMLInputElement, ArabicDateInputProps>(function ArabicDateInput(
  { type = 'date', className = 'input', value, defaultValue, onChange, onClick, disabled, hideIcon = false, emptyLabel, style, ...rest },
  forwardedRef,
) {
  const resolvedEmptyLabel = emptyLabel ?? (type === 'datetime-local' ? 'yyyy/mm/dd --:--' : 'yyyy/mm/dd');
  const innerRef = useRef<HTMLInputElement | null>(null);
  const isControlled = value !== undefined;
  const [uncontrolledValue, setUncontrolledValue] = useState(() => (typeof defaultValue === 'string' ? defaultValue : ''));

  const setMergedRef = useCallback(
    (node: HTMLInputElement | null) => {
      innerRef.current = node;
      if (typeof forwardedRef === 'function') {
        forwardedRef(node);
      } else if (forwardedRef) {
        forwardedRef.current = node;
      }
    },
    [forwardedRef],
  );

  // مزامنة القيمة عند استخدام react-hook-form أو التعديل البرمجي عبر ref
  useEffect(() => {
    if (!isControlled && innerRef.current && innerRef.current.value !== uncontrolledValue) {
      setUncontrolledValue(innerRef.current.value);
    }
  });

  const currentValue = isControlled ? (typeof value === 'string' ? value : '') : uncontrolledValue;
  const formatted = formatArabicDateDisplay(currentValue);

  const handleChange = (event: ChangeEvent<HTMLInputElement>) => {
    if (!isControlled) {
      setUncontrolledValue(event.target.value);
    }
    onChange?.(event);
  };

  const handleClick = (event: MouseEvent<HTMLInputElement>) => {
    onClick?.(event);
    if (disabled) return;
    const el = event.currentTarget as HTMLInputElement & { showPicker?: () => void };
    if (typeof el.showPicker === 'function') {
      try {
        el.showPicker();
      } catch {
        // بعض المتصفحات تمنع showPicker بدون تفاعل مستخدم مباشر أو في بيئات الاختبار
      }
    }
  };

  return (
    <div
      style={style}
      className={`relative inline-flex items-center justify-between gap-2 select-none focus-within:border-[var(--brand-accent)] focus-within:shadow-[var(--focus-ring)] ${
        disabled ? 'cursor-not-allowed opacity-70' : 'cursor-pointer'
      } ${className}`}
    >
      <span
        dir="ltr"
        style={{ unicodeBidi: 'isolate' }}
        className={`tabular-nums truncate ${formatted ? 'text-[var(--text-primary)]' : 'text-[var(--text-muted)]'}`}
      >
        {formatted || resolvedEmptyLabel}
      </span>
      {!hideIcon ? <Calendar className="size-3.5 shrink-0 text-[var(--text-muted)] pointer-events-none" aria-hidden="true" /> : null}
      <input
        {...rest}
        ref={setMergedRef}
        type={type}
        disabled={disabled}
        value={isControlled ? value : undefined}
        defaultValue={isControlled ? undefined : defaultValue}
        onChange={handleChange}
        onClick={handleClick}
        className="absolute inset-0 z-10 h-full w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
      />
    </div>
  );
});
