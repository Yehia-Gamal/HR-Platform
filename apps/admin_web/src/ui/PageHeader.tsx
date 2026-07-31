import type { ReactNode } from 'react';

export function PageHeader({ title, description, actions, eyebrow }: { title: string; description?: string; actions?: ReactNode; eyebrow?: string }) {
  return (
    <header className="mb-5 space-y-3">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          {eyebrow ? <p className="mb-1 text-xs font-black text-[var(--brand-primary)]">{eyebrow}</p> : null}
          <h1 className="text-2xl font-black tracking-tight md:text-[1.7rem]">{title}</h1>
        </div>
        {actions ? <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div> : null}
      </div>
      {description ? <p className="max-w-3xl text-sm leading-7 text-[var(--text-muted)]">{description}</p> : null}
    </header>
  );
}
