import { ShieldX } from 'lucide-react';
import type { ReactNode } from 'react';

/** حالة عدم وجود صلاحية — تظهر عند محاولة الوصول لصفحة محمية */
export function ForbiddenState({
  title = 'لا تملك صلاحية الوصول',
  description = 'هذه الصفحة تتطلب صلاحية غير متاحة لحسابك.',
  action,
}: {
  title?: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div
      role="alert"
      className="card grid min-h-56 place-items-center p-8 text-center"
      style={{ borderColor: 'color-mix(in srgb, var(--warning) 40%, var(--border))' }}
    >
      <div className="max-w-md">
        <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--warning-soft)] text-[var(--warning)]">
          <ShieldX className="size-6" aria-hidden="true" />
        </span>
        <h2 className="mt-4 text-lg font-black">{title}</h2>
        <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">{description}</p>
        {action ? <div className="mt-4 flex justify-center">{action}</div> : null}
      </div>
    </div>
  );
}
