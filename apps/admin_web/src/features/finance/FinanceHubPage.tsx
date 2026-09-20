import { useSearchParams } from 'react-router';
import { lazy, Suspense } from 'react';
import { ListSkeleton } from '../../ui/Skeletons';

const InstantPenaltiesPage = lazy(() => import('./InstantPenaltiesPage').then((m) => ({ default: m.InstantPenaltiesPage })));
const FellowshipFundPage = lazy(() => import('./FellowshipFundPage').then((m) => ({ default: m.FellowshipFundPage })));
const PenaltyDashboardPage = lazy(() => import('./PenaltyDashboardPage').then((m) => ({ default: m.PenaltyDashboardPage })));
const PenaltySettingsPage = lazy(() => import('./PenaltySettingsPage').then((m) => ({ default: m.PenaltySettingsPage })));

const TABS = [
  { key: 'instant-penalties', label: 'غرامات الحضور والانصراف' },
  { key: 'dashboard', label: 'لوحة الإحصائيات' },
  { key: 'settings', label: 'الإعدادات' },
  { key: 'fellowship-fund', label: 'صندوق الزمالة والتكافل' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function FinanceHubPage() {
  const [params, setParams] = useSearchParams();
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw) ? (raw as TabKey) : 'instant-penalties';

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
        className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1 bg-[var(--surface-muted)]/50"
        role="tablist"
        aria-label="أقسام الجزاءات وصندوق الزمالة"
      >
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={`rounded-lg px-5 py-2.5 text-sm font-bold transition-all ${
              tab === t.key
                ? 'bg-[var(--brand-primary)] text-white shadow-md shadow-[var(--brand-primary)]/20'
                : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)] hover:text-[var(--text-primary)]'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="pt-1">
        <Suspense fallback={<ListSkeleton rows={3} label="جارٍ التحميل…" />}>
          {tab === 'fellowship-fund' ? (
            <FellowshipFundPage />
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
