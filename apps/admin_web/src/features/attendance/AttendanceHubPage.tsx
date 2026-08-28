import { useSearchParams } from 'react-router';
import { AttendancePage } from './AttendancePage';
import { AttendanceOperationsPage } from '../advanced/AttendanceOperationsPage';
import { MonthlyAttendanceReportPage } from './MonthlyAttendanceReportPage';

/**
 * مركز الحضور الموحّد — يدمج التفاصيل والتشغيل والكشف الشهري في صفحة
 * واحدة بتبويبات (بند دمج الخدمات). المسارات القديمة تُحوَّل هنا عبر
 * redirects مع ?tab — فلا ينكسر أي رابط أو إشعار قديم.
 */

const TABS = [
  { key: 'details', label: 'الحضور' },
  { key: 'operations', label: 'الورديات والتشغيل' },
  { key: 'report', label: 'الكشف الشهري' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

export function AttendanceHubPage() {
  const [params, setParams] = useSearchParams();
  const raw = params.get('tab');
  const tab: TabKey = TABS.some((t) => t.key === raw) ? (raw as TabKey) : 'details';

  const setTab = (key: TabKey) => {
    const next = new URLSearchParams(params);
    if (key === 'details') {
      next.delete('tab');
    } else {
      next.set('tab', key);
    }
    setParams(next, { replace: true });
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1" role="tablist" aria-label="أقسام الحضور">
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

      {tab === 'operations' ? <AttendanceOperationsPage /> : tab === 'report' ? <MonthlyAttendanceReportPage /> : <AttendancePage />}
    </div>
  );
}
