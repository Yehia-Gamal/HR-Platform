import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { MonthlyAttendanceReportPage } from '../MonthlyAttendanceReportPage';

const mockEmployee = {
  id: 'emp-1',
  fullNameAr: 'أحمد محمد',
  employeeCode: 'EMP-001',
  department: 'الموارد البشرية',
  jobTitle: 'مسؤول موارد بشرية',
  photoUrl: null,
  status: 'active',
};

let employeesReturn: Record<string, unknown> = {};
let statementReturn: Record<string, unknown> = {};

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => employeesReturn,
}));

vi.mock('../useMonthlyStatement', () => ({
  useEmployeeMonthlyStatement: () => statementReturn,
}));

function Wrapper({ children }: { children: React.ReactNode }) {
  return <MemoryRouter>{children}</MemoryRouter>;
}

const dataQuery = {
  data: [mockEmployee],
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
const statementIdle = {
  data: undefined,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('MonthlyAttendanceReportPage', () => {
  it('يُعرض بدون أخطاء', () => {
    employeesReturn = dataQuery;
    statementReturn = statementIdle;
    const { container } = render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    employeesReturn = dataQuery;
    statementReturn = statementIdle;
    render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(screen.getByText('كشف الحضور والانصراف الشهري')).toBeDefined();
  });

  it('يعرض حقول اختيار الشهر والسنة', () => {
    employeesReturn = dataQuery;
    statementReturn = statementIdle;
    render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(screen.getByLabelText('الشهر')).toBeDefined();
    expect(screen.getByLabelText('السنة')).toBeDefined();
  });

  it('يعرض بطاقات الموظفين', () => {
    employeesReturn = dataQuery;
    statementReturn = statementIdle;
    render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(screen.getByText('أحمد محمد')).toBeDefined();
    expect(screen.getByText('الموارد البشرية')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    employeesReturn = loadingQuery;
    statementReturn = statementIdle;
    const { container } = render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود موظفين', () => {
    employeesReturn = emptyQuery;
    statementReturn = statementIdle;
    render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(screen.getByText('لا توجد نتائج')).toBeDefined();
  });

  it('يعرض حالة الخطأ عند فشل تحميل قائمة الموظفين', () => {
    employeesReturn = errorQuery;
    statementReturn = statementIdle;
    render(<Wrapper><MonthlyAttendanceReportPage /></Wrapper>);
    expect(screen.getByText('تعذّر تحميل البيانات')).toBeDefined();
  });
});
