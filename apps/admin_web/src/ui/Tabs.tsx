import { useRef, useCallback, type ReactNode, type KeyboardEvent } from 'react';

export interface TabItem {
  id: string;
  label: string;
  count?: number;
}

interface TabsProps {
  tabs: TabItem[];
  activeTab: string;
  onTabChange: (id: string) => void;
  children: ReactNode;
  ariaLabel?: string;
}

/**
 * مكوّن ألسنة (Tabs) قابل لإعادة الاستخدام مع دعم لوحة المفاتيح و ARIA.
 * يستخدم نمط filter-chip المتبع في باقي الصفحات.
 */
export function Tabs({ tabs, activeTab, onTabChange, children, ariaLabel = 'ألسنة التصفية' }: TabsProps) {
  const tablistRef = useRef<HTMLDivElement>(null);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLDivElement>) => {
      const currentIndex = tabs.findIndex((t) => t.id === activeTab);
      if (currentIndex === -1) return;

      /* RTL: ArrowRight = السابق، ArrowLeft = التالي */
      const nextIndex = (() => {
        switch (e.key) {
          case 'ArrowRight':
            return currentIndex > 0 ? currentIndex - 1 : tabs.length - 1;
          case 'ArrowLeft':
            return currentIndex < tabs.length - 1 ? currentIndex + 1 : 0;
          case 'Home':
            return 0;
          case 'End':
            return tabs.length - 1;
          default:
            return -1;
        }
      })();
      if (nextIndex === -1) return;

      e.preventDefault();
      const next = tabs[nextIndex];
      onTabChange(next.id);

      const btn = tablistRef.current?.querySelector<HTMLButtonElement>(`#tab-${next.id}`);
      btn?.focus();
    },
    [tabs, activeTab, onTabChange],
  );

  return (
    <div className="space-y-4">
      <div ref={tablistRef} className="flex flex-wrap gap-2" role="tablist" aria-label={ariaLabel} onKeyDown={handleKeyDown}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            type="button"
            id={`tab-${tab.id}`}
            role="tab"
            aria-selected={tab.id === activeTab}
            aria-controls={`panel-${tab.id}`}
            tabIndex={tab.id === activeTab ? 0 : -1}
            className={`filter-chip ${tab.id === activeTab ? 'is-active' : ''}`}
            onClick={() => onTabChange(tab.id)}
          >
            {tab.label}
            {tab.count != null ? (
              <span className="mr-1.5 rounded-full bg-current/10 px-1.5 py-0.5 text-[.65rem] font-black leading-none">{tab.count}</span>
            ) : null}
          </button>
        ))}
      </div>

      <div id={`panel-${activeTab}`} role="tabpanel" aria-labelledby={`tab-${activeTab}`}>
        {children}
      </div>
    </div>
  );
}
