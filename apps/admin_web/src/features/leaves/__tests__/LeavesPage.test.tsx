import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { LeavesPage } from '../LeavesPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockRow = {
  requestId:     'req-1',
  requestNumber: 1001,
  status:        'pending' as const,
  createdAt:     '2026-06-01T00:00:00Z',
  employeeId:    'emp-1',
  employeeCode:  'EMP-101',
  employeeName:  'أحمد محمد',
  leaveTypeId:   'lt-1',
  leaveTypeCode: 'annual' as const,
  leaveTypeName: 'إجازة سنوية',
  isPaid:        true,
  startDate:     '2026-07-01',
  endDate:       '2026-07-07',
  daysCount:     7,
  hoursCount:    null,
  durationUnit:  'day' as const,
  isHalfDay:     false,
  reason:        'إجازة صيفية',
  handoverNotes: null,
  attachmentUrl: null,
};

const mockData = { total: 1, rows: [mockRow] };
const emptyData = { total: 0, rows: [] };

let queryOverrideFn: () => Record<string, unknown>;
vi.mock('../useLeaves', () => ({
  useAdminLeaves: () => queryOverrideFn(),
}));

const loadingQuery = { data: undefined, isLoading: true,  isError: false, error: null, refetch: vi.fn() };
const dataQuery    = { data: mockData,   isLoading: false, isError: false, error: null, refetch: vi.fn() };
const emptyQuery   = { data: emptyData,  isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery   = { data: undefined,  isLoading: false, isError: true,  error: new Error('server error'), refetch: vi.fn() };

describe('LeavesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    queryOverrideFn = () => dataQuery;
    const { container } = render(<Wrapper><LeavesPage /></Wrapper>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    queryOverrideFn = () => dataQuery;
    render(<Wrapper><LeavesPage /></Wrapper>);
    expect(screen.getByText('إدارة الإجازات')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    queryOverrideFn = () => dataQuery;
    render(<Wrapper><LeavesPage /></Wrapper>);
    expect(screen.getByText('إجمالي الطلبات')).toBeDefined();
    expect(screen.getByText('قيد المراجعة')).toBeDefined();
    expect(screen.getByText('معتمدة')).toBeDefined();
    expect(screen.getByText('مرفوضة')).toBeDefined();
  });

  it('يعرض طلبات الإجازة عند توفر البيانات', () => {
    queryOverrideFn = () => dataQuery;
    render(<Wrapper><LeavesPage /></Wrapper>);
    expect(screen.getAllByText('أحمد محمد').length).toBeGreaterThan(0);
  });

  it('يعرض حالة التحميل', () => {
    queryOverrideFn = () => loadingQuery;
    const { container } = render(<Wrapper><LeavesPage /></Wrapper>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود طلبات', () => {
    queryOverrideFn = () => emptyQuery;
    render(<Wrapper><LeavesPage /></Wrapper>);
    expect(screen.getByText('لا توجد طلبات إجازات')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    queryOverrideFn = () => errorQuery;
    render(<Wrapper><LeavesPage /></Wrapper>);
    expect(screen.getByText('تعذّر تحميل الإجازات')).toBeDefined();
  });
});
