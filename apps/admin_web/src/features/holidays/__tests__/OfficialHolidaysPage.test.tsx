import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { OfficialHolidaysPage } from '../OfficialHolidaysPage';

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let holidaysOverrideFn: () => Record<string, unknown>;

vi.mock('../useHolidays', () => ({
  useHolidays: () => holidaysOverrideFn(),
  useCreateHoliday: () => noopMutation,
  useUpdateHoliday: () => noopMutation,
  useDeleteHoliday: () => noopMutation,
}));

vi.mock('../../employees/useOrganizationLookups', () => ({
  useOrganizationLookups: () => ({ data: { departments: [] }, isLoading: false, isError: false, error: null }),
}));

const mockHolidays = [
  {
    id: 'h1',
    name: 'اليوم الوطني',
    name_en: 'National Day',
    holiday_date: '2026-09-23',
    end_date: null,
    scope: 'all' as const,
    legal_entity_id: null,
    department_id: null,
    excluded_department_ids: [],
    notes: null,
    is_recurring: true,
    is_active: true,
    created_at: '2026-01-01T00:00:00Z',
    created_by: null,
  },
];

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockHolidays, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('OfficialHolidaysPage', () => {
  it('يُعرض بدون أخطاء', () => {
    holidaysOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    holidaysOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('العطل الرسمية')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    holidaysOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('إجمالي العطل')).toBeDefined();
    expect(screen.getByText('عطل فعّالة')).toBeDefined();
    expect(screen.getByText('عطل متكررة سنويًا')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    holidaysOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض اسم العطلة في الجدول عند وجود بيانات', () => {
    holidaysOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('اليوم الوطني')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود عطل', () => {
    holidaysOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <OfficialHolidaysPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد عطل مسجلة')).toBeDefined();
  });
});
