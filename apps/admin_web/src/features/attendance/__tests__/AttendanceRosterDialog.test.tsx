import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';

import type * as UseAttendanceDashboard from '../useAttendanceDashboard';

let hookReturn: Record<string, unknown> = {};

vi.mock('../useAttendanceDashboard', async (importOriginal) => {
  const actual = await importOriginal<typeof UseAttendanceDashboard>();
  return {
    ...actual,
    useAttendanceRoster: () => hookReturn,
  };
});

vi.mock('../../ui/useResolvedAvatarUrl', () => ({
  useResolvedAvatarUrl: (url: string | null | undefined) => url,
}));

import { AttendanceRosterDialog } from '../AttendanceRosterDialog';

function renderWithRouter(ui: React.ReactElement) {
  return render(<MemoryRouter>{ui}</MemoryRouter>);
}

describe('AttendanceRosterDialog', () => {
  it('يعرض عنوان الفئة واسم الموظفين الموجودين', () => {
    hookReturn = {
      data: [
        {
          employeeId: '11111111-2222-3333-4444-555555555555',
          employeeCode: 'EMP-001',
          employeeName: 'أحمد محمد علي',
          departmentName: 'إدارة البرامج',
          photoUrl: null,
          status: 'present',
          firstCheckIn: new Date().toISOString(),
          lastCheckOut: null,
          lateMinutes: 0,
          requiresReview: false,
          locationRequestStatus: null,
          locationRequestedAt: null,
          locationRespondedAt: null,
        },
      ],
      isLoading: false,
      isError: false,
      error: null,
    };
    renderWithRouter(<AttendanceRosterDialog category="present" dateIso="2026-08-05" onClose={() => {}} />);
    expect(screen.getByText('حاضرون')).toBeDefined();
    expect(screen.getByText('أحمد محمد علي')).toBeDefined();
    expect(screen.getByText('EMP-001')).toBeDefined();
  });

  it('يعرض نصًا للحالة الفارغة عند غياب البيانات', () => {
    hookReturn = { data: [], isLoading: false, isError: false, error: null };
    renderWithRouter(<AttendanceRosterDialog category="absent" dateIso="2026-08-05" onClose={() => {}} />);
    expect(screen.getByText('غياب')).toBeDefined();
    expect(screen.getByText(/لا غياب/)).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    hookReturn = { data: undefined, isLoading: true, isError: false, error: null };
    renderWithRouter(<AttendanceRosterDialog category="scheduled" dateIso="2026-08-05" onClose={() => {}} />);
    expect(screen.getByText('جاري تحميل القائمة')).toBeDefined();
  });

  it('يعرض حالة الخطأ عند فشل الطلب', () => {
    hookReturn = { data: undefined, isLoading: false, isError: true, error: new Error('network') };
    renderWithRouter(<AttendanceRosterDialog category="late" dateIso="2026-08-05" onClose={() => {}} />);
    expect(screen.getByText('تعذر تحميل القائمة')).toBeDefined();
  });
});
