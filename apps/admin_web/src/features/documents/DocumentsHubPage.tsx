import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { Printer } from 'lucide-react';
import { DocumentsPage } from './DocumentsPage';
import { DocumentsStudioPage } from './DocumentsStudioPage';
import { OfficialDocumentGeneratorModal } from './OfficialDocumentGeneratorModal';

/**
 * مركز المستندات الموحّد — الإدارة والاستوديو بتبويبات وتوليد الوثائق الرسمية.
 * المسار القديم documents/studio يُحوَّل هنا عبر redirect.
 */

const TABS = [
  { key: 'documents', label: 'المستندات' },
  { key: 'studio', label: 'الاستوديو' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function DocumentsHubPage() {
  const [params, setParams] = useSearchParams();
  const [showDocGenerator, setShowDocGenerator] = useState(false);
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw) ? (raw as TabKey) : 'documents';

  const setTab = (key: TabKey) => {
    const next = new URLSearchParams(params);
    if (key === 'documents') {
      next.delete('tab');
    } else {
      next.set('tab', key);
    }
    setParams(next, { replace: true });
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1" role="tablist" aria-label="أقسام المستندات">
          {TABS.map((t) => (
            <button
              key={t.key}
              type="button"
              role="tab"
              aria-selected={tab === t.key}
              onClick={() => setTab(t.key)}
              className={`rounded-lg px-3.5 py-1.5 text-xs font-black transition-colors ${
                tab === t.key ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        <button
          type="button"
          onClick={() => setShowDocGenerator(true)}
          className="btn-primary text-xs flex items-center gap-1.5 py-2 px-3.5 shadow-sm"
        >
          <Printer className="size-4" aria-hidden="true" />
          توليد وطباعة وثيقة رسمية (عقد / شهادة راتب / إخلاء)
        </button>
      </div>

      {tab === 'studio' ? <DocumentsStudioPage /> : <DocumentsPage />}

      <OfficialDocumentGeneratorModal
        isOpen={showDocGenerator}
        onClose={() => setShowDocGenerator(false)}
      />
    </div>
  );
}
