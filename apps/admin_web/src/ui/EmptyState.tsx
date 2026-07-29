import { Inbox } from 'lucide-react';
import type { ReactNode } from 'react';

export function EmptyState({ title, description, action }: { title: string; description: string; action?: ReactNode }) {
  return <div className="card grid min-h-56 place-items-center p-8 text-center"><div className="max-w-md"><span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--surface-muted)] text-[var(--brand-primary)]"><Inbox className="size-6" aria-hidden="true" /></span><h2 className="mt-4 text-lg font-black">{title}</h2><p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">{description}</p>{action ? <div className="mt-4 flex justify-center">{action}</div> : null}</div></div>;
}
