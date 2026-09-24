import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ActionCenterPage, resolveActionHref } from '../ActionCenterPage';
import type { ActionCenterItem } from '@ahla/shared-contracts';

const mockItem: ActionCenterItem = {
  id: 'request-f47ac10b-58cc-4372-a567-0e02b2c3d479',
  kind: 'request',
  priority: 'urgent',
  status: 'pending',
  title: 'طلب إجازة يحتاج موافقتك',
  subtitle: 'تقدّم أحمد محمد بطلب إجازة سنوية',
  dueAt: '2026-08-15T12:00:00Z',
  actionUrl: '/hr/requests',
  sourceUpdatedAt: '2026-08-14T10:00:00Z',
};

const normalItem: ActionCenterItem = {
  id: 'action-2',
  kind: 'task',
  priority: 'high',
  status: 'pending',
  title: 'مستند ينتظر التوثيق',
  subtitle: null,
  dueAt: null,
  actionUrl: '/hr/documents',
  sourceUpdatedAt: null,
};

let actionReturn: Record<string, unknown> = {};

vi.mock('../useActionCenter', () => ({
  useActionCenter: () => actionReturn,
}));

function Wrapper({ children }: { children: React.ReactNode }) {
  return <MemoryRouter>{children}</MemoryRouter>;
}

const dataQuery = {
  data: [mockItem, normalItem],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyQuery = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};

describe('ActionCenterPage', () => {
  it('يُعرض بدون أخطاء', () => {
    actionReturn = dataQuery;
    const { container } = render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    actionReturn = dataQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getByText('مركز الإجراءات الموحد')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات بأرقام صحيحة', () => {
    actionReturn = dataQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getByText('إجمالي العناصر')).toBeDefined();
    expect(screen.getByText('عاجل')).toBeDefined();
    expect(screen.getByText('مرتفع')).toBeDefined();
  });

  it('يعرض بيانات الإجراءات', () => {
    actionReturn = dataQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getByText('طلب إجازة يحتاج موافقتك')).toBeDefined();
    expect(screen.getByText('مستند ينتظر التوثيق')).toBeDefined();
  });

  it('يعرض روابط فتح الإجراء', () => {
    actionReturn = dataQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('فتح الإجراء').length).toBeGreaterThan(0);
  });

  it('رابط الطلب يفتح التفاصيل مباشرة عبر ?request=', () => {
    actionReturn = dataQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    const anchors = screen.getAllByRole('link', { name: /فتح الإجراء/ });
    const requestAnchor = anchors.find((a) => a.getAttribute('href')?.includes('/admin/hr/requests?request='));
    expect(requestAnchor).toBeTruthy();
    expect(requestAnchor?.getAttribute('href')).toContain(
      '/admin/hr/requests?request=f47ac10b-58cc-4372-a567-0e02b2c3d479',
    );
  });

  it('resolveActionHref يبني رابط التفاصيل للطلب', () => {
    expect(resolveActionHref(mockItem)).toBe(
      '/admin/hr/requests?request=f47ac10b-58cc-4372-a567-0e02b2c3d479',
    );
    expect(resolveActionHref(normalItem)).toBe('/hr/documents');
  });

  it('يعرض حالة التحميل', () => {
    actionReturn = loadingQuery;
    const { container } = render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود إجراءات', () => {
    actionReturn = emptyQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد إجراءات معلقة')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    actionReturn = errorQuery;
    render(
      <Wrapper>
        <ActionCenterPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل مركز الإجراءات')).toBeDefined();
  });
});
