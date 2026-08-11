import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { AuditSecurityPage } from '../AuditSecurityPage';

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

let centerOverrideFn: () => Record<string, unknown>;
vi.mock('../useControlCenters', () => ({
  useAuditSecurityCenter: () => centerOverrideFn(),
  useAuditSecurityCommands: () => ({
    handleEvent: mutationMock,
    revokeDevice: mutationMock,
  }),
}));

const mockAuditData = {
  securityEvents: [
    {
      id: 'sec-001',
      eventType: 'login_failed',
      severity: 'high',
      outcome: 'blocked',
      handled: false,
      occurredAt: '2026-08-11T10:00:00Z',
    },
    {
      id: 'sec-002',
      eventType: 'access.role_assigned',
      severity: 'low',
      outcome: 'success',
      handled: true,
      occurredAt: '2026-08-11T09:00:00Z',
    },
  ],
  auditEvents: [
    {
      id: 'aud-001',
      eventType: 'employee.updated',
      category: 'data',
      severity: 'low',
      summary: 'تحديث بيانات الموظف',
      targetTable: 'employees',
      occurredAt: '2026-08-11T10:00:00Z',
    },
  ],
  devices: [
    {
      id: 'dev-001',
      name: 'iPhone 14',
      platform: 'ios',
      appVersion: '0.11.1',
      environment: 'production',
      trusted: true,
      status: 'active',
      lastSeenAt: '2026-08-11T10:00:00Z',
      firstSeenAt: '2026-01-01T10:00:00Z',
      employeeId: '00000000-0000-0000-0000-000000000002',
      employeeName: 'أحمد',
      deviceModel: 'iPhone 14 Pro',
      osVersion: 'iOS 17.0',
    },
  ],
};

const dataQuery = { data: mockAuditData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل التحميل'), isFetching: false, refetch: vi.fn() };

describe('AuditSecurityPage', () => {
  it('يُعرض بدون أخطاء', () => {
    centerOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    centerOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('التدقيق والأمان')).toBeDefined();
  });

  it('يعرض بطاقات الإحصائيات', () => {
    centerOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('أحداث غير معالجة')).toBeDefined();
    expect(screen.getByText('عالية الخطورة')).toBeDefined();
    expect(screen.getByText('أجهزة نشطة')).toBeDefined();
    expect(screen.getByText('نشطة وغير موثوقة')).toBeDefined();
  });

  it('يعرض حالة التحميل (animate-pulse)', () => {
    centerOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض تبويبات الأحداث الأمنية والتدقيق والأجهزة', () => {
    centerOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(screen.getByRole('tablist', { name: 'أقسام التدقيق والأمان' })).toBeDefined();
  });

  it('يعرض الأحداث الأمنية في التبويب الافتراضي', () => {
    centerOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('محاولة دخول فاشلة')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    centerOverrideFn = () => errorQuery;
    render(
      <MemoryRouter>
        <AuditSecurityPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تعذر تحميل مركز الأمان')).toBeDefined();
  });
});
