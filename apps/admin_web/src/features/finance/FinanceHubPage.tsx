import { useSearchParams } from 'react-router';
import { InstantPenaltiesPage } from './InstantPenaltiesPage';
import { FellowshipFundPage } from './FellowshipFundPage';

/**
 * غرامات الحضور والانصراف وصندوق الزمالة والتكافل
 * تم إزالة الرواتب والتشغيل وInstaPay والمالية القديمة وفق التوجيه المعتمد.
 */

const TABS = [
  { key: 'instant-penalties', label: 'غرامات الحضور والانصراف' },
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
    <div className="space-y-4">
      <div className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1 bg-[var(--surface-base)]" role="tablist" aria-label="أقسام الجزاءات وصندوق الزمالة">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={`rounded-lg px-4 py-2 text-xs font-black transition-colors ${
              tab === t.key ? 'bg-[var(--brand-primary)] text-white shadow-sm' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'fellowship-fund' ? (
        <FellowshipFundPage />
      ) : (
        <InstantPenaltiesPage />
      )}
    </div>
  );
}
