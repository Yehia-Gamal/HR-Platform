import { AppLogo } from './AppLogo';

export function LoadingScreen({ label = 'جارٍ تحميل النظام…' }: { label?: string }) {
  return (
    <main className="grid min-h-screen place-items-center p-6" aria-busy="true">
      <div className="flex flex-col items-center text-center">
        <AppLogo />
        <span className="mt-7 size-8 animate-spin rounded-full border-[3px] border-[var(--brand-primary-soft)] border-t-[var(--brand-primary)]" />
        <span className="mt-4 text-sm font-bold text-[var(--text-muted)]">{label}</span>
      </div>
    </main>
  );
}
