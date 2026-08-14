import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { SystemPage } from '../SystemPage';

/* ─── mock بيانات نظرة عامة على النظام ──────────────────────── */
const mockSystemData = {
  enabledFlags: 3,
  totalFlags: 5,
  unresolvedErrors: 2,
  fatalErrors: 0,
  latestBackupStatus: 'success',
  latestBackupAt: new Date().toISOString(),
  settingsCount: 15,
  recentErrors: [
    {
      id: '00000000-0000-0000-0000-000000000001',
      level: 'warning',
      source: 'auth',
      message: 'خطأ في المصادقة',
      occurredAt: new Date().toISOString(),
    },
  ],
  flags: [
    {
      id: '00000000-0000-0000-0000-000000000002',
      key: 'feature_biometric',
      name: 'البصمة البيومترية',
      enabled: true,
      rolloutPercent: 100,
      environment: 'production',
    },
  ],
  lastUpdatedAt: new Date().toISOString(),
};

/* ─── factory function لحالات الـ hook ──────────────────────── */
let systemOverviewOverride: () => Record<string, unknown>;

vi.mock('../useManagementOverviews', () => ({
  useSystemOverview: () => systemOverviewOverride(),
}));

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockSystemData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: vi.fn() };

describe('SystemPage', () => {
  it('يُعرض بدون أخطاء', () => {
    systemOverviewOverride = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    systemOverviewOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('إعدادات وصحة النظام')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    systemOverviewOverride = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ', () => {
    systemOverviewOverride = () => errorQuery;
    render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تعذر تحميل الحالة التقنية')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الرئيسية', () => {
    systemOverviewOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الميزات المفعلة')).toBeDefined();
    expect(screen.getByText('أخطاء غير محلولة')).toBeDefined();
    expect(screen.getByText('أخطاء حرجة')).toBeDefined();
    expect(screen.getByText('آخر نسخة احتياطية')).toBeDefined();
    expect(screen.getByText('إعدادات النظام')).toBeDefined();
  });

  it('يعرض قسم Feature Flags', () => {
    systemOverviewOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('Feature Flags')).toBeDefined();
    expect(screen.getByText('البصمة البيومترية')).toBeDefined();
  });

  it('يعرض قسم الأخطاء المفتوحة', () => {
    systemOverviewOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <SystemPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('أحدث الأخطاء المفتوحة')).toBeDefined();
    expect(screen.getByText('خطأ في المصادقة')).toBeDefined();
  });
});
