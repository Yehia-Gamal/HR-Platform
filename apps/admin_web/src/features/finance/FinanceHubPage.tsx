import { useSearchParams } from 'react-router';
import { lazy, Suspense } from 'react';
import { ListSkeleton } from '../../ui/Skeletons';
import { useSuspendedEmployeesAdmin } from './useInstantPenalties';

const InstantPenaltiesPage = lazy(() => import('./InstantPenaltiesPage').then((m) => ({ default: m.InstantPenaltiesPage })));
const SuspendedEmployeesPage = lazy(() => import('./SuspendedEmployeesPage').then((m) => ({ default: m.SuspendedEmployeesPage })));
const FellowshipFundPage = lazy(() => import('./FellowshipFundPage').then((m) => ({ default: m.FellowshipFundPage })));
const PenaltyDashboardPage = lazy(() => import('./PenaltyDashboardPage').then((m) => ({ default: m.PenaltyDashboardPage })));
const PenaltySettingsPage = lazy(() => import('./PenaltySettingsPage').then((m) => ({ default: m.PenaltySettingsPage })));

const TABS = [
  { key: 'instant-penalties', label: 'غرامات الحضور والانصراف' },
  { key: 'suspended-employees', label: 'الموظفون الموقوفون عن العمل' },
  { key: 'dashboard', label: 'لوحة الإحصائيات' },
  { key: 'settings', label: 'الإعدادات' },
  { key: 'fellowship-fund', label: 'صندوق الزمالة والتكافل' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function FinanceHubPage() {
  const [params, setParams] = useSearchParams();
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw) ? (raw as TabKey) : 'instant-penalties';

  const { data: suspendedEmployees } = useSuspendedEmployeesAdmin();
  const suspendedCount = suspendedEmployees?.length ?? 0;

  const setTab = (key: TabKey) => {
    const next = new URLSearchParams(params);
    if (key === 'instant-penalties') {
      next.delete('tab');
    } else {
      next.set('tab', key);
    }
    setParams(next, { replace: true });
  };

  return (
    <div className="space-y-5">
      <div
        className="flex flex-wrap gap-1.5 rounded-2xl border border-[var(--border)] p-1.5 bg-[var(--surface-muted)]/60 shadow-inner"
        role="tablist"
        aria-label="أقسام الجزاءات وصندوق الزمالة"
      >
        {TABS.map((t) => {
          const isActive = tab === t.key;
          const isSuspendedTab = t.key === 'suspended-employees';
          return (
            <button
              key={t.key}
              type="button"
              role="tab"
              aria-selected={isActive}
              onClick={() => setTab(t.key)}
              className={`rounded-xl px-5 py-2.5 text-xs font-bold transition-all flex items-center gap-2 cursor-pointer ${
                isActive
                  ? 'bg-[var(--brand-primary)] text-white shadow-md shadow-[var(--brand-primary)]/20'
                  : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)] hover:text-[var(--text-primary)]'
              }`}
            >
              <span>{t.label}</span>
              {isSuspendedTab && suspendedCount > 0 && (
                <span
                  className={`inline-flex items-center justify-center px-1.5 py-0.2 text-[10px] font-black rounded-full min-w-5 h-4.5 ${
                    isActive
                      ? 'bg-rose-500 text-white'
                      : 'bg-rose-500/15 text-rose-600 dark:text-rose-400 border border-rose-500/30'
                  }`}
                >
                  {suspendedCount}
                </span>
              )}
            </button>
          );
        })}
      </div>

      <div className="pt-1">
        <Suspense fallback={<ListSkeleton rows={3} label="جارٍ التحميل…" />}>
          {tab === 'fellowship-fund' ? (
            <FellowshipFundPage />
          ) : tab === 'suspended-employees' ? (
            <SuspendedEmployeesPage />
          ) : tab === 'dashboard' ? (
            <PenaltyDashboardPage />
          ) : tab === 'settings' ? (
            <PenaltySettingsPage />
          ) : (
            <InstantPenaltiesPage />
          )}
        </Suspense>
      </div>
    </div>
  );
}
