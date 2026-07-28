import type { ReactNode } from 'react';

export function PageHeader({
  title,
  description,
  actions,
  eyebrow,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  eyebrow?: string;
}) {
  return (
    <header className="mb-5 flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
      <div className="min-w-0 flex-1">
        {eyebrow ? <p className="mb-1 text-xs font-black text-[var(--brand-primary)]">{eyebrow}</p> : null}
        <h1 className="text-2xl font-black tracking-tight md:text-[1.7rem]">{title}</h1>
        {description ? <p className="mt-1.5 max-w-3xl text-sm leading-7 text-[var(--text-muted)]">{description}</p> : null}
      </div>
      {actions ? <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div> : null}
    </header>
  );
}
