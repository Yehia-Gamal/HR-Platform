import { Sparkles } from 'lucide-react';
import { PageHeader } from './PageHeader';

/** صفحة بديلة للميزات المخفية خلف Feature Flag — تُعرض عند تفعيل Flag قبل اكتمال التطوير */
export function ComingSoonPage({ title }: { title: string }) {
  return (
    <div className="space-y-6">
      <PageHeader title={title} />
      <div className="card grid min-h-56 place-items-center p-8 text-center">
        <div className="max-w-md">
          <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
            <Sparkles className="size-6" aria-hidden="true" />
          </span>
          <h2 className="mt-4 text-lg font-black">قريبًا</h2>
          <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">هذه الميزة قيد التطوير وستكون متاحة قريبًا.</p>
        </div>
      </div>
    </div>
  );
}
