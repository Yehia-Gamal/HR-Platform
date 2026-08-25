import { useSearchParams } from 'react-router';
import { KnowledgePage } from '../knowledge/KnowledgePage';
import { LearningPage } from '../learning/LearningPage';

/**
 * مركز التدريب والمعرفة الموحّد — قاعدة المعرفة + التعلم بتبويبات.
 * المسار القديم learning يُحوَّل هنا.
 */

const TABS = [
  { key: 'knowledge', label: 'قاعدة المعرفة' },
  { key: 'learning', label: 'التعلم والتدريب' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function KnowledgeHubPage() {
  const [params, setParams] = useSearchParams();
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw)
    ? (raw as TabKey)
    : 'knowledge';

  const setTab = (key: TabKey) => {
    const next = new URLSearchParams(params);
    if (key === 'knowledge') {
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
        aria-label="أقسام التدريب والمعرفة"
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

      {tab === 'learning' ? <LearningPage /> : <KnowledgePage />}
    </div>
  );
}
