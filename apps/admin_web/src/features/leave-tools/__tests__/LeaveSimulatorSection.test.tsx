import { render, screen, fireEvent } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LeaveSimulatorSection } from '../LeaveSimulatorSection';

const mockEmployees = [
  {
    id: 'emp-1',
    employeeCode: 'EMP-101',
    fullNameAr: 'أحمد محمود',
    department: 'العمليات',
    status: 'active' as const,
    isActive: true,
  },
  {
    id: 'emp-2',
    employeeCode: 'EMP-102',
    fullNameAr: 'طارق سامي',
    department: 'العمليات',
    status: 'active' as const,
    isActive: true,
  },
];

const mockLeaves = {
  total: 1,
  rows: [
    {
      requestId: 'req-1',
      requestNumber: 101,
      employeeId: 'emp-2',
      employeeName: 'طارق سامي',
      startDate: '2026-10-15',
      endDate: '2026-10-20',
      status: 'approved' as const,
      leaveTypeCode: 'annual',
      leaveTypeName: 'إجازة سنوية',
    },
  ],
};

const mockCreateLeave = {
  mutateAsync: vi.fn(),
  isPending: false,
};

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => ({ data: mockEmployees, isLoading: false }),
}));

vi.mock('../../leaves/useLeaves', () => ({
  useAdminLeaves: () => ({ data: mockLeaves, isLoading: false }),
}));

vi.mock('../useLeaveTools', () => ({
  useLeaveTypes: () => ({ data: [], isLoading: false }),
  useCreateLeaveForEmployee: () => mockCreateLeave,
}));

describe('LeaveSimulatorSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders simulator header and conflict radar', () => {
    render(<LeaveSimulatorSection />);
    expect(screen.getByText('محاكي ومخطط الإجازات الذكي')).toBeDefined();
    expect(screen.getByText('منع التعارضات')).toBeDefined();
    expect(screen.getByText(/نتيجة المحاكاة التقديرية/)).toBeDefined();
  });

  it('detects department peer leave conflict when dates overlap', () => {
    render(<LeaveSimulatorSection />);

    // Select start and end dates overlapping with emp-2 (2026-10-15 to 2026-10-20)
    const dateInputs = screen.getAllByDisplayValue(/2026-/);
    if (dateInputs.length >= 2) {
      fireEvent.change(dateInputs[0], { target: { value: '2026-10-16' } });
      fireEvent.change(dateInputs[1], { target: { value: '2026-10-18' } });
    }

    expect(screen.getByText(/يوجد 1 تعارض/)).toBeDefined();
    expect(screen.getByText(/الزميل/)).toBeDefined();
    expect(screen.getAllByText(/طارق سامي/).length).toBeGreaterThan(0);
  });
});
