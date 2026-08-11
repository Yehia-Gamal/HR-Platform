import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { ObservabilityDashboardPage } from '../ObservabilityDashboardPage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مختبر',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

const mutationMock = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

const mockHealthData = {
  generated_at: '2026-08-11T10:00:00Z',
  integration_queue: { pending: 3, failed: 1, dead_letter: 0, overdue: 0 },
  notifications: { queued: 2, delivered_24h: 150, failed_24h: 3, stuck: 0 },
  errors: { errors_last_1h: 5, fatal_last_1h: 0, warnings_last_1h: 12 },
  security: { critical_last_1h: 0, high_last_1h: 2 },
};

const mockAlerts: Array<{
  id: string;
  alert_key: string;
  severity: 'P0' | 'P1';
  source: string;
  title: string;
  detail: string | null;
  metric_value: number | null;
  threshold: number | null;
  status: 'open' | 'acknowledged' | 'resolved';
  first_seen_at: string;
  last_seen_at: string;
  occurrences: number;
  acknowledged_by: string | null;
  acknowledged_at: string | null;
  resolved_at: string | null;
  context: Record<string, unknown>;
}> = [
  {
    id: 'alert-001',
    alert_key: 'queue.failed.high',
    severity: 'P1',
    source: 'integration_queue',
    title: 'رسائل فاشلة في طابور التكامل',
    detail: 'عدد الرسائل الفاشلة تجاوز الحد',
    metric_value: 10,
    threshold: 5,
    status: 'open',
    first_seen_at: '2026-08-11T09:00:00Z',
    last_seen_at: '2026-08-11T10:00:00Z',
    occurrences: 3,
    acknowledged_by: null,
    acknowledged_at: null,
    resolved_at: null,
    context: {},
  },
];

const mockCronSummary = {
  total_jobs: 10,
  active: 8,
  failing: 1,
  unstable: 0,
  healthy: 7,
  never_run: 1,
  disabled: 1,
  checked_at: '2026-08-11T10:00:00Z',
  failures_24h_total: 2,
};

const mockCronJobs = [
  {
    jobid: 1,
    jobname: 'expire_sessions',
    schedule: '0 * * * *',
    active: true,
    last_status: 'succeeded',
    last_message: null,
    last_start: '2026-08-11T10:00:00Z',
    last_end: '2026-08-11T10:00:05Z',
    duration_seconds: 5.2,
    failures_24h: 0,
    health_status: 'healthy' as const,
  },
];

const mockEvents = [
  {
    id: 'evt-001',
    created_at: '2026-08-11T10:00:00Z',
    level: 'info' as const,
    source: 'cron/expire_sessions',
    event_type: 'cron.run',
    request_id: null,
    message: 'انتهت الجلسات المنتهية',
    error_name: null,
    duration_ms: 52,
    metadata: {},
  },
];

let healthOverrideFn: () => Record<string, unknown>;
let alertsOverrideFn: () => Record<string, unknown>;
let cronSummaryOverrideFn: () => Record<string, unknown>;
let cronJobsOverrideFn: () => Record<string, unknown>;
let eventsOverrideFn: () => Record<string, unknown>;

vi.mock('../useSystemHealth', () => ({
  useSystemHealth: () => healthOverrideFn(),
}));

vi.mock('../useSystemAlerts', () => ({
  useSystemAlerts: () => alertsOverrideFn(),
  useUpdateAlertStatus: () => mutationMock,
}));

vi.mock('../useCronHealth', () => ({
  useCronHealthSummary: () => cronSummaryOverrideFn(),
  useCronJobHealth: () => cronJobsOverrideFn(),
  useObservabilityEvents: () => eventsOverrideFn(),
}));

const dataHealthQuery = { data: mockHealthData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataAlertsQuery = { data: mockAlerts, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataCronSummaryQuery = { data: mockCronSummary, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataCronJobsQuery = { data: mockCronJobs, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataEventsQuery = { data: mockEvents, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

const emptyAlertsQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingHealthQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorHealthQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل تحميل الصحة'), isFetching: false, refetch: vi.fn() };

function setAllData() {
  healthOverrideFn = () => dataHealthQuery;
  alertsOverrideFn = () => dataAlertsQuery;
  cronSummaryOverrideFn = () => dataCronSummaryQuery;
  cronJobsOverrideFn = () => dataCronJobsQuery;
  eventsOverrideFn = () => dataEventsQuery;
}

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

describe('ObservabilityDashboardPage', () => {
  it('يُعرض بدون أخطاء', () => {
    setAllData();
    const { container } = render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    setAllData();
    render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(screen.getByText('لوحة مراقبة النظام')).toBeDefined();
  });

  it('يعرض بطاقات الإحصائيات', () => {
    setAllData();
    render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(screen.getByText('تنبيهات حرجة (P0)')).toBeDefined();
    expect(screen.getByText('تنبيهات (P1)')).toBeDefined();
    expect(screen.getByText('أخطاء آخر ساعة')).toBeDefined();
    expect(screen.getByText('أحداث أمنية حرجة')).toBeDefined();
  });

  it('يعرض التنبيهات المفتوحة', () => {
    setAllData();
    render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(screen.getByText('التنبيهات المفتوحة')).toBeDefined();
    expect(screen.getByText('رسائل فاشلة في طابور التكامل')).toBeDefined();
  });

  it('يعرض حالة فارغة عند انعدام التنبيهات', () => {
    healthOverrideFn = () => dataHealthQuery;
    alertsOverrideFn = () => emptyAlertsQuery;
    cronSummaryOverrideFn = () => dataCronSummaryQuery;
    cronJobsOverrideFn = () => dataCronJobsQuery;
    eventsOverrideFn = () => dataEventsQuery;
    render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    // "لا توجد تنبيهات" يظهر في العنوان + في hint بطاقة P1 — نتحقق من الرسالة الوصفية الخاصة بـ EmptyState
    expect(screen.getByText('النظام يعمل بسلاسة، لا تنبيهات مفتوحة.')).toBeDefined();
  });

  it('يعرض حالة التحميل (animate-pulse)', () => {
    healthOverrideFn = () => loadingHealthQuery;
    alertsOverrideFn = () => emptyAlertsQuery;
    cronSummaryOverrideFn = () => ({ data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() });
    cronJobsOverrideFn = () => ({ data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() });
    eventsOverrideFn = () => ({ data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() });
    const { container } = render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل تحميل الصحة', () => {
    healthOverrideFn = () => errorHealthQuery;
    alertsOverrideFn = () => emptyAlertsQuery;
    cronSummaryOverrideFn = () => ({ data: undefined, isLoading: false, isError: false, error: null, refetch: vi.fn() });
    cronJobsOverrideFn = () => ({ data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() });
    eventsOverrideFn = () => ({ data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() });
    render(<ObservabilityDashboardPage />, { wrapper: Wrapper });
    expect(screen.getByText('تعذر تحميل لوحة المراقبة')).toBeDefined();
  });
});
