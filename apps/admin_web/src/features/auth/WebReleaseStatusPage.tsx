import type { PublicReleasePolicy } from '@ahla/shared-contracts';
import { CloudOff, Construction, RefreshCcw, ShieldX, Download } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { AppLogo } from '../../ui/AppLogo';

function ReleaseGateShell({
  icon: Icon,
  iconClassName,
  title,
  message,
  detail,
  onRetry,
  retryLabel = 'إعادة التحقق',
  isError = false,
}: {
  icon: LucideIcon;
  iconClassName?: string;
  title: string;
  message: string;
  detail?: ReactNode;
  onRetry?: () => void;
  retryLabel?: string;
  isError?: boolean;
}) {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <section className="card max-w-xl p-8 text-center" {...(isError ? { role: 'alert' } : {})}>
        <div className="mb-6 flex justify-center">
          <AppLogo />
        </div>
        <Icon className={`mx-auto size-16 ${iconClassName ?? ''}`} aria-hidden="true" />
        <h1 className="mt-5 text-2xl font-black">{title}</h1>
        <p className="muted mt-3 leading-7">{message}</p>
        {detail ? <p className="muted mt-3 text-xs">{detail}</p> : null}
        {onRetry ? (
          <button className="btn-primary mx-auto mt-6" onClick={onRetry}>
            <RefreshCcw className="size-4" aria-hidden="true" />
            {retryLabel}
          </button>
        ) : null}
      </section>
    </main>
  );
}

export function WebReleaseStatusPage({ policy, onRetry }: { policy: PublicReleasePolicy; onRetry: () => void }) {
  const blocked = policy.action === 'blocked';
  const maintenance = policy.action === 'maintenance';
  const Icon = blocked ? ShieldX : maintenance ? Construction : Download;
  const iconClassName = blocked
    ? 'text-[var(--danger)]'
    : maintenance
      ? 'text-[var(--warning)]'
      : 'text-[var(--brand-primary)]';
  const title = blocked ? 'تم إبطال هذا المتصفح' : maintenance ? 'لوحة الإدارة تحت الصيانة' : 'يجب تحديث لوحة الويب';
  const message =
    policy.messageAr ??
    (blocked
      ? 'تم إبطال هذا التثبيت لأسباب أمنية.'
      : maintenance
        ? 'نعمل على تحديث النظام. أعد المحاولة بعد قليل.'
        : 'أعد تحميل الصفحة للحصول على الإصدار المدعوم.');

  return (
    <ReleaseGateShell
      icon={Icon}
      iconClassName={iconClassName}
      title={title}
      message={message}
      detail={
        policy.action === 'update_required'
          ? `نسختك ${policy.currentVersion}+${policy.currentBuild} · الحد الأدنى ${policy.minSupportedVersion}+${policy.minSupportedBuild}`
          : undefined
      }
      onRetry={!blocked ? onRetry : undefined}
      isError={blocked}
    />
  );
}

export function WebReleaseCheckError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <ReleaseGateShell
      icon={CloudOff}
      iconClassName="text-[var(--danger)]"
      title="تعذر التحقق من إصدار الويب"
      message="تحقق من الاتصال ثم أعد المحاولة. في الإنتاج لا تُفتح بيانات الإدارة قبل اجتياز بوابة الإصدار."
      detail={message}
      onRetry={onRetry}
      retryLabel="إعادة المحاولة"
      isError
    />
  );
}
