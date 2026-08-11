import { render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { LifecyclePage } from '../LifecyclePage';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockMut = { isPending: false, isError: false, error: null, mutateAsync: vi.fn(), mutate: vi.fn() };

let catalogFn: () => Record<string, unknown>;

vi.mock('../useLifecycle', () => ({
  useLifecycleCatalog: () => catalogFn(),
  useLifecycleCommands: () => ({
    createJourney: { ...mockMut },
    transitionTask: { ...mockMut },
  }),
  JOURNEY_STATUS_LABELS: {
    all: 'كل المراحل',
    in_progress: 'قيد التنفيذ',
    completed: 'مكتملة',
  },
  TASK_STATUS_LABELS: {
    pending: 'معلقة',
    in_progress: 'جارٍ',
    completed: 'مكتملة',
    skipped: 'متخطاة',
  },
  TASK_STATUS_ORDER: ['pending', 'in_progress', 'completed', 'skipped'],
}));

const emptyQuery = {
  data: { journeys: [], eligibleEmployees: [] },
  isLoading: false,
  isError: false,
  error: null,
  isFetching: false,
  refetch: vi.fn(),
};
const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  isFetching: true,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('server error'),
  isFetching: false,
  refetch: vi.fn(),
};
const mockJourney = {
  id: 'journey-1',
  employeeName: 'أحمد محمد',
  employeeCode: 'EMP-101',
  status: 'in_progress',
  progress: 50,
  completedTasks: 3,
  totalTasks: 6,
  startedAt: '2026-08-01T00:00:00Z',
  probationEnd: '2026-10-01',
  tasks: [],
};
const dataQuery = {
  data: { journeys: [mockJourney], eligibleEmployees: [] },
  isLoading: false,
  isError: false,
  error: null,
  isFetching: false,
  refetch: vi.fn(),
};

describe('LifecyclePage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogFn = () => emptyQuery;
    const { container } = render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogFn = () => emptyQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByText('دورة حياة الموظف')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    catalogFn = () => emptyQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByText('رحلات قيد التنفيذ')).toBeDefined();
    expect(screen.getByText('رحلات مكتملة')).toBeDefined();
    expect(screen.getByText('متوسط الإنجاز')).toBeDefined();
    expect(screen.getByText('موظفون في التهيئة')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    catalogFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل التحميل', () => {
    catalogFn = () => errorQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذّر تحميل البيانات')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود رحلات', () => {
    catalogFn = () => emptyQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد رحلات تهيئة بعد')).toBeDefined();
  });

  it('يعرض شريط بحث وتصفية الرحلات', () => {
    catalogFn = () => emptyQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByPlaceholderText('ابحث باسم الموظف أو الكود…')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب المرحلة')).toBeDefined();
  });

  it('يعرض رحلة الموظف في الجدول عند وجود بيانات', () => {
    catalogFn = () => dataQuery;
    render(
      <Wrapper>
        <LifecyclePage />
      </Wrapper>,
    );
    expect(screen.getByText('أحمد محمد')).toBeDefined();
  });
});
