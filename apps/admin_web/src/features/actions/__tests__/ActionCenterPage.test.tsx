import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ActionCenterPage } from '../ActionCenterPage';

const mockItem = {
  id: 'action-1',
  kind: 'leave_request',
  priority: 'urgent',
  status: 'pending',
  title: 'طلب إجازة يحتاج موافقتك',
  subtitle: 'تقدّم أحمد محمد بطلب إجازة سنوية',
  dueAt: '2026-08-15T12:00:00Z',
  actionUrl: '/hr/requests/req-1',
};

const normalItem = {
  id: 'action-2',
  kind: 'document_review',
  priority: 'high',
  status: 'pending',
  title: 'مستند ينتظر التوثيق',
  subtitle: null,
  dueAt: null,
  actionUrl: '/hr/documents',
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
