import { useSearchParams } from 'react-router';
import { ReportsPage } from './ReportsPage';
import { ReportSchedulerPage } from './ReportSchedulerPage';
import { AnalyticsDashboardPage } from '../analytics/AnalyticsDashboardPage';

/**
 * مركز التقارير الموحّد — التقارير والجدولة والتحليلات بتبويبات.
 * المسارات القديمة (reports/scheduler، analytics) تُحوَّل هنا.
 */

const TABS = [
  { key: 'reports', label: 'تقارير HR' },
  { key: 'scheduler', label: 'الجدولة' },
  { key: 'analytics', label: 'التحليلات' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function ReportsHubPage() {
  const [params, setParams] = useSearchParams();
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw)
    ? (raw as TabKey)
    : 'reports';

  const setTab = (key: TabKey) => {
    const next = new URLSearchParams(params);
    if (key === 'reports') {
      next.delete('tab');
    } else {
      next.set('tab', key);
    }
    setParams(next, { replace: true });
  };

  return (
    <div className="space-y-4">
      <div
        className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1"
        role="tablist"
        aria-label="أقسام التقارير"
      >
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={`rounded-lg px-3.5 py-1.5 text-xs font-black transition-colors ${
              tab === t.key
                ? 'bg-[var(--brand-primary)] text-white'
                : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'scheduler' ? (
        <ReportSchedulerPage />
      ) : tab === 'analytics' ? (
        <AnalyticsDashboardPage />
      ) : (
        <ReportsPage />
      )}
    </div>
  );
}
