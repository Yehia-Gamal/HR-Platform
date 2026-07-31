import { RefreshCw, WifiOff } from 'lucide-react';
import { useEffect, useState } from 'react';

/** حالة عدم الاتصال بالإنترنت — تظهر عند فقد الشبكة */
export function OfflineState({
  title = 'لا يوجد اتصال بالإنترنت',
  description = 'تحقق من اتصالك بالشبكة ثم أعد المحاولة.',
  onRetry,
}: {
  title?: string;
  description?: string;
  onRetry?: () => void;
}) {
  return (
    <div
      role="status"
      className="card grid min-h-56 place-items-center p-8 text-center"
      style={{ borderColor: 'color-mix(in srgb, var(--warning) 40%, var(--border))' }}
    >
      <div className="max-w-md">
        <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--warning-soft)] text-[var(--warning)]">
          <WifiOff className="size-6" aria-hidden="true" />
        </span>
        <h2 className="mt-4 text-lg font-black">{title}</h2>
        <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">{description}</p>
        {onRetry ? (
          <div className="mt-4 flex justify-center">
            <button type="button" className="btn-secondary" onClick={onRetry}>
              <RefreshCw className="size-4" />
              إعادة المحاولة
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

/** يراقب حالة الاتصال بالإنترنت عبر أحداث المتصفح */
export function useOnlineStatus(): boolean {
  const [online, setOnline] = useState(() => navigator.onLine);

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener('online', goOnline);
    window.addEventListener('offline', goOffline);
    return () => {
      window.removeEventListener('online', goOnline);
      window.removeEventListener('offline', goOffline);
    };
  }, []);

  return online;
}
