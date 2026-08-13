import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { LearningPage } from '../LearningPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let catalogOverrideFn: () => Record<string, unknown>;
vi.mock('../useLearning', () => ({
  useLearningCatalog: () => catalogOverrideFn(),
  useUpsertCourse: () => noopMutation,
  useEnrollEmployee: () => noopMutation,
  useTransitionEnrollment: () => noopMutation,
}));

const mockCatalogData = {
  courses: [
    {
      id: '1a2b3c4d-0000-0000-0000-000000000001',
      code: 'LDR-101',
      title: 'مهارات القيادة الفعّالة',
      category: 'management',
      deliveryMode: 'onsite',
      durationMinutes: 960,
      mandatory: true,
      active: true,
      enrollments: 1,
      completed: 0,
    },
  ],
  enrollments: [
    {
      id: '1a2b3c4d-0000-0000-0000-000000000002',
      courseId: '1a2b3c4d-0000-0000-0000-000000000001',
      courseTitle: 'مهارات القيادة الفعّالة',
      employeeId: '1a2b3c4d-0000-0000-0000-000000000003',
      employeeName: 'أحمد محمد',
      employeeCode: 'EMP-101',
      status: 'enrolled' as const,
      progress: null,
      score: null,
      enrolledAt: '2026-01-15T00:00:00Z',
      completedAt: null,
      expiresAt: null,
    },
  ],
  employees: [
    { id: '1a2b3c4d-0000-0000-0000-000000000003', name: 'أحمد محمد', code: 'EMP-101' },
  ],
};

const emptyData = { courses: [], enrollments: [], employees: [] };

const emptyQuery = { data: emptyData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockCatalogData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('LearningPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(screen.getByText('المعهد المهني والتدريب')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(screen.getByText('الدورات النشطة')).toBeDefined();
    expect(screen.getByText('إجمالي التسجيل')).toBeDefined();
    expect(screen.getByText('دورات إجبارية')).toBeDefined();
    expect(screen.getByText('تسجيلات مكتملة')).toBeDefined();
  });

  it('يعرض الدورات عند توفر البيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('مهارات القيادة الفعّالة').length).toBeGreaterThan(0);
  });

  it('يعرض حالة فارغة عند عدم وجود دورات', () => {
    catalogOverrideFn = () => emptyQuery;
    render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد دورات بعد')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <LearningPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });
});
