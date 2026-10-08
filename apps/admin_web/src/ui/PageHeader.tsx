import type { ReactNode } from 'react';

export function PageHeader({ title, description, actions, eyebrow }: { title: string; description?: ReactNode; actions?: ReactNode; eyebrow?: string }) {
  return (
    <header className="mb-6 space-y-3.5">
      <div className="min-w-0">
        {eyebrow ? <p className="mb-1 text-xs font-black tracking-wide text-[var(--brand-primary)]">{eyebrow}</p> : null}
        <h1 className="text-2xl font-black tracking-tight text-[var(--text-primary)] md:text-[1.85rem] leading-snug">{title}</h1>
        {description ? <div className="mt-1.5 max-w-5xl text-sm leading-relaxed text-[var(--text-muted)]">{description}</div> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2 pt-2 border-t border-[var(--border)]/50">{actions}</div> : null}
    </header>
  );
}
