import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { AlertTriangle, CheckCircle2, Info, X, XCircle } from 'lucide-react';

type ToastTone = 'success' | 'error' | 'warning' | 'info';

interface ToastOptions {
  message: string;
  tone: ToastTone;
  duration?: number;
}

interface ToastEntry extends Required<ToastOptions> {
  id: number;
}

interface ToastContextValue {
  toast: (options: ToastOptions) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

/* ───────────── جسر خارج React لـ MutationCache ─────────────
 * يسمح لكود خارج شجرة React (مثل MutationCache) بإطلاق الإشعارات.
 * يشترك ToastProvider عند التركيب ويُلغي الاشتراك عند الإزالة. */
type ToastEmitter = (options: ToastOptions) => void;
let toastEmitter: ToastEmitter | null = null;

export function subscribeToastEmitter(emitter: ToastEmitter): () => void {
  toastEmitter = emitter;
  return () => {
    if (toastEmitter === emitter) toastEmitter = null;
  };
}

export function emitToast(options: ToastOptions): void {
  toastEmitter?.(options);
}

const MAX_VISIBLE = 3;
const DEFAULT_DURATION = 4000;
const EXIT_MS = 300;

const toneConfig: Record<ToastTone, { icon: typeof CheckCircle2; bg: string; accent: string }> = {
  success: { icon: CheckCircle2, bg: 'var(--success-soft)', accent: 'var(--success)' },
  error: { icon: XCircle, bg: 'var(--danger-soft)', accent: 'var(--danger)' },
  warning: { icon: AlertTriangle, bg: 'var(--warning-soft)', accent: 'var(--warning)' },
  info: { icon: Info, bg: 'var(--brand-accent-soft)', accent: 'var(--info)' },
};

/* ───────────────────────── عنصر إشعار واحد ───────────────────────── */

function ToastItem({ entry, onRemove }: { entry: ToastEntry; onRemove: (id: number) => void }) {
  const [phase, setPhase] = useState<'enter' | 'visible' | 'exit'>('enter');
  const cfg = toneConfig[entry.tone];
  const Icon = cfg.icon;

  // تفعيل حركة الدخول بعد التركيب
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      requestAnimationFrame(() => setPhase('visible'));
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  // إخفاء تلقائي بعد المدة المحددة
  useEffect(() => {
    const timer = setTimeout(() => setPhase('exit'), entry.duration);
    return () => clearTimeout(timer);
  }, [entry.duration]);

  // حذف العنصر بعد انتهاء حركة الخروج (مع fallback)
  useEffect(() => {
    if (phase !== 'exit') return;
    const fallback = setTimeout(() => onRemove(entry.id), EXIT_MS + 50);
    return () => clearTimeout(fallback);
  }, [phase, entry.id, onRemove]);

  const animClass = phase === 'visible' ? 'translate-y-0 opacity-100' : '-translate-y-2 opacity-0';

  return (
    <div
      role="alert"
      aria-live="polite"
      className={`flex items-center gap-3 rounded-xl border-s-[3px] px-4 py-3 shadow-lg backdrop-blur-sm transition-all duration-300 ease-out ${animClass}`}
      style={{ background: cfg.bg, borderColor: cfg.accent }}
      onTransitionEnd={(e) => {
        if (e.target === e.currentTarget && phase === 'exit') onRemove(entry.id);
      }}
    >
      <Icon className="size-5 shrink-0" style={{ color: cfg.accent }} aria-hidden="true" />
      <span className="flex-1 text-sm font-bold text-[var(--text-primary)]">{entry.message}</span>
      <button
        className="grid size-6 shrink-0 place-items-center rounded-lg transition-opacity hover:opacity-80"
        style={{ color: cfg.accent }}
        onClick={() => setPhase('exit')}
        aria-label="إغلاق"
      >
        <X className="size-3.5" />
      </button>
    </div>
  );
}

/* ───────────────────────── مزوّد الإشعارات ───────────────────────── */

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastEntry[]>([]);
  const idRef = useRef(0);

  const toast = useCallback((opts: ToastOptions) => {
    setToasts((prev) => [
      ...prev,
      {
        ...opts,
        id: ++idRef.current,
        duration: opts.duration ?? DEFAULT_DURATION,
      },
    ]);
  }, []);

  const remove = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  // ربط الجسر الخارجي بـ MutationCache طوال عمر المزوّد
  useEffect(() => subscribeToastEmitter(toast), [toast]);

  // عرض أول MAX_VISIBLE فقط — الباقي في الطابور
  const visible = toasts.slice(0, MAX_VISIBLE);

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      {toasts.length > 0 &&
        createPortal(
          <div className="pointer-events-none fixed inset-x-0 top-0 z-[200] flex flex-col items-center gap-2 p-4">
            {visible.map((entry) => (
              <div key={entry.id} className="pointer-events-auto w-full max-w-md">
                <ToastItem entry={entry} onRemove={remove} />
              </div>
            ))}
          </div>,
          document.body,
        )}
    </ToastContext.Provider>
  );
}

/* ───────────────────────── Hook ───────────────────────── */

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error('useToast يجب استخدامه داخل ToastProvider');
  return ctx;
}
