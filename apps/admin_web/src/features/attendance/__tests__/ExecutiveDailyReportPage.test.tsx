import { render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockReportData = {
  attendance: {
    present: 42,
    late: 4,
    absent: 3,
    notYet: 5,
    checkedOut: 20,
    missingCheckout: 2,
  },
  employees: {
    active: 50,
    requiredToday: 49,
  },
  workStatus: {
    approvedLeave: 2,
    missions: 3,
    convoys: 1,
    fundraising: 0,
  },
  requests: {
    pendingLeave: 1,
    pendingMission: 0,
  },
  followUp: {
    decisions: 0,
    missingReports: 0,
    activeLocationRequests: 2,
    unansweredLocationRequests: 0,
  },
  kpi: {
    atEmployee: 0,
    atManager: 0,
    atHr: 0,
    ready: 10,
    overdue: 1,
  },
  cases: {
    new: 0,
    open: 1,
  },
};

const mockDetailData = {
  employees: [
    {
      employeeId: 'emp-1',
      employeeCode: 'E001',
      employeeName: 'أحمد محمود',
      departmentId: 'dept-1',
      departmentName: 'تقنية المعلومات',
      status: 'late',
      firstCheckIn: '09:45:00',
      lastCheckOut: '17:00:00',
      lateMinutes: 75,
      shiftName: 'الصباحية',
      workHours: 7.25,
    },
    {
      employeeId: 'emp-2',
      employeeCode: 'E002',
      employeeName: 'سارة علي',
      departmentId: 'dept-1',
      departmentName: 'تقنية المعلومات',
      status: 'absent',
      hasApprovedLeave: false,
      hasMission: false,
    },
    {
      employeeId: 'emp-3',
      employeeCode: 'E003',
      employeeName: 'محمود حسن',
      departmentId: 'dept-2',
      departmentName: 'الموارد البشرية',
      status: 'present',
      firstCheckIn: '08:30:00',
      lastCheckOut: null,
      lateMinutes: 0,
      shiftName: 'الصباحية',
      workHours: 4,
    },
  ],
  missions: [],
  convoys: [],
  leaves: [],
  kpis: [],
  cases: [],
};

let mockReportReturn: Record<string, unknown> = {};
let mockDetailReturn: Record<string, unknown> = {};
let mockAuthReturn: Record<string, unknown> = {
  access: {
    roles: ['admin'],
    permissions: ['reports.executive.read'],
  },
};

vi.mock('../useAttendanceDashboard', () => ({
  useExecutiveDailyReport: () => mockReportReturn,
  useExecutiveDailyReportDetail: () => mockDetailReturn,
  exportExecutiveDailyReportPdf: vi.fn(),
}));

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => mockAuthReturn,
}));

import { ExecutiveDailyReportPage } from '../ExecutiveDailyReportPage';

describe('ExecutiveDailyReportPage', () => {
  it('يعرض رسالة غير مصرح عند فقدان الصلاحية', () => {
    mockAuthReturn = { access: { roles: ['employee'], permissions: [] } };
    mockReportReturn = { data: mockReportData, isLoading: false, isError: false };
    mockDetailReturn = { data: mockDetailData, isLoading: false, isError: false };

    render(
      <Wrapper>
        <ExecutiveDailyReportPage />
      </Wrapper>,
    );

    expect(screen.getByText('غير مصرح')).toBeDefined();
  });

  it('يعرض عنوان التقرير والملخص التنفيذي عند توفر الصلاحية والبيانات', () => {
    mockAuthReturn = { access: { permissions: ['reports.executive.read'] } };
    mockReportReturn = { data: mockReportData, isLoading: false, isError: false, refetch: vi.fn() };
    mockDetailReturn = { data: mockDetailData, isLoading: false, isError: false, refetch: vi.fn() };

    render(
      <Wrapper>
        <ExecutiveDailyReportPage />
      </Wrapper>,
    );

    expect(screen.getByText('التقرير التنفيذي اليومي الشامل')).toBeDefined();
    expect(screen.getByText('الموجز التحليلي والملخص التنفيذي لليوم')).toBeDefined();
    expect(screen.getByText('مقارنة الحضور والانضباط عبر الإدارات')).toBeDefined();
    expect(screen.getByText('توزيع قوى العمل الكلي اليوم')).toBeDefined();
  });

  it('يعرض مصفوفة التدخل والمتابعة التنفيذية العاجلة للموظفين ذوي الحالات الحرجة', () => {
    mockAuthReturn = { access: { permissions: ['reports.executive.read'] } };
    mockReportReturn = { data: mockReportData, isLoading: false, isError: false, refetch: vi.fn() };
    mockDetailReturn = { data: mockDetailData, isLoading: false, isError: false, refetch: vi.fn() };

    render(
      <Wrapper>
        <ExecutiveDailyReportPage />
      </Wrapper>,
    );

    expect(screen.getByText('مصفوفة التدخل والمتابعة التنفيذية العاجلة')).toBeDefined();
    expect(screen.getAllByText('أحمد محمود').length).toBeGreaterThanOrEqual(2);
    expect(screen.getAllByText('سارة علي').length).toBeGreaterThanOrEqual(2);
    expect(screen.getAllByText('محمود حسن').length).toBeGreaterThanOrEqual(2);
    // تأخير 75 دقيقة منسق كـ "ساعة و15د"
    expect(screen.getByText(/تأخير 1 س و 15 د/)).toBeDefined();
    expect(screen.getByText('غياب بدون إذن')).toBeDefined();
    expect(screen.getByText('بصمة انصراف مفقودة')).toBeDefined();
  });
});
