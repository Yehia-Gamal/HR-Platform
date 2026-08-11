import { render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { AttendanceOperationsPage } from '../AttendanceOperationsPage';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

vi.mock('../../../core/cairoTime', () => ({
  cairoMonthIso: () => '2026-08',
  cairoTodayIso: () => '2026-08-11',
}));

const mockMut = { isPending: false, isError: false, error: null, mutateAsync: vi.fn(), mutate: vi.fn() };
const mockCommands = {
  saveShift: { ...mockMut },
  decideCorrection: { ...mockMut },
  decideOvertime: { ...mockMut },
  closePeriod: { ...mockMut },
  unlockPeriod: { ...mockMut },
};

let attendanceOpsFn: () => Record<string, unknown>;

vi.mock('../useAdvancedOperations', () => ({
  useAttendanceOperations: () => attendanceOpsFn(),
  useAttendanceOperationsCommands: () => mockCommands,
}));

const mockData = {
  summary: { scheduled: 25, present: 20, absent: 2, pendingOvertime: 3 },
  shifts: [],
  rosters: [],
  periods: [],
  overtime: [],
};
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('server error'),
  refetch: vi.fn(),
};
const mockShift = {
  id: 'shift-1',
  name: 'الدوام الرسمي',
  startTime: '10:00:00',
  endTime: '18:00:00',
  breakMinutes: 60,
  graceInMinutes: 15,
  active: true,
};
const dataWithShiftsQuery = {
  data: { ...mockData, shifts: [mockShift] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('AttendanceOperationsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    attendanceOpsFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    attendanceOpsFn = () => dataQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('الورديات وإغلاق الحضور')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    attendanceOpsFn = () => dataQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('الأيام المجدولة')).toBeDefined();
    expect(screen.getByText('الحضور')).toBeDefined();
    expect(screen.getByText('الغياب')).toBeDefined();
    expect(screen.getByText('إضافي معلق')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    attendanceOpsFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل التحميل', () => {
    attendanceOpsFn = () => errorQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذّر تحميل البيانات')).toBeDefined();
  });

  it('يعرض نموذج تعريف الوردية', () => {
    attendanceOpsFn = () => dataQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعريف وردية')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود جداول ورديات', () => {
    attendanceOpsFn = () => dataQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد جداول ورديات')).toBeDefined();
  });

  it('يعرض الورديات الحالية عند وجود بيانات', () => {
    attendanceOpsFn = () => dataWithShiftsQuery;
    render(
      <Wrapper>
        <AttendanceOperationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('الدوام الرسمي')).toBeDefined();
  });
});
