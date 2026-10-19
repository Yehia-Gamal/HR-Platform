import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type * as UseAttendanceDashboard from '../useAttendanceDashboard';

let rosterHook: Record<string, unknown> = {};

vi.mock('../useAttendanceDashboard', async (importOriginal) => {
  const actual = await importOriginal<typeof UseAttendanceDashboard>();
  return {
    ...actual,
    useAttendanceRosterPage: () => rosterHook,
  };
});

import { ExecutiveAttendanceModal } from '../ExecutiveAttendanceModal';

describe('ExecutiveAttendanceModal', () => {
  it('renders executive summary statistics and grouped tables for executive director', () => {
    rosterHook = {
      data: {
        items: [
          {
            employeeId: 'emp-1',
            employeeName: 'أحمد علي',
            departmentName: 'إدارة العمليات',
            status: 'present',
            firstCheckIn: '2026-10-18T07:00:00Z',
            lastCheckOut: null,
            shiftName: 'الصباحية',
            lateMinutes: 0,
          },
          {
            employeeId: 'emp-2',
            employeeName: 'محمد سعيد',
            departmentName: 'إدارة الحسابات',
            status: 'absent',
            firstCheckIn: null,
            lastCheckOut: null,
            shiftName: 'الصباحية',
            hasPendingRequest: true,
            pendingRequestNumber: 588,
            pendingRequestTitle: 'بدل راحة اسبوعية',
          },
          {
            employeeId: 'emp-3',
            employeeName: 'سارة حسن',
            departmentName: 'المطابخ',
            status: 'on_leave',
            firstCheckIn: null,
            lastCheckOut: null,
            hasApprovedLeave: true,
            leaveName: 'إجازة سنوية',
          },
        ],
        total: 3,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-18" onClose={() => undefined} />);

    // Header and title
    expect(screen.getByText('تقرير الحضور التنفيذي (جاهز للمدير التنفيذي)')).toBeDefined();
    expect(screen.getByText('كشف المتابعة اليومية للحضور والانصراف')).toBeDefined();

    // Stats
    expect(screen.getByText('إجمالي قوة العمل')).toBeDefined();
    expect(screen.getByText('الحضور الفعلي')).toBeDefined();
    expect(screen.getByText('الغياب')).toBeDefined();

    // Table rows
    expect(screen.getByText('أحمد علي')).toBeDefined();
    expect(screen.getByText('محمد سعيد')).toBeDefined();
    expect(screen.getByText('سارة حسن')).toBeDefined();

    // Action buttons
    expect(screen.getByText('حفظ كصورة (PNG)')).toBeDefined();
    expect(screen.getByText('نسخ الصورة لواتساب')).toBeDefined();
    expect(screen.getByText('نسخ نص واتساب')).toBeDefined();
  });

  it('renders pending mission with badge, destination, and purpose', () => {
    rosterHook = {
      data: {
        items: [
          {
            employeeId: 'emp-mission-1',
            employeeName: 'حاتم محمد سالم',
            departmentName: 'إدارة الحركة',
            branchName: 'مجمع أحلى شباب - منيل شيحة',
            status: 'absent',
            firstCheckIn: null,
            lastCheckOut: null,
            shiftName: 'الصباحية',
            hasPendingRequest: true,
            pendingRequestNumber: 594,
            pendingRequestType: 'mission',
            pendingRequestTitle: 'كورنيش المعادي',
            leaveTitle: 'كورنيش المعادي',
            leaveReason: 'صرف شيكات وإيداع تبرعات',
          },
        ],
        total: 1,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-19" onClose={() => undefined} />);

    // Employee name
    expect(screen.getByText('حاتم محمد سالم')).toBeDefined();

    // Badge showing pending mission with request number
    expect(screen.getByText('⏳ طلب مأمورية معلّق (#594)')).toBeDefined();

    // Destination and purpose
    expect(screen.getByText(/📍 كورنيش المعادي/)).toBeDefined();
    expect(screen.getByText(/💬 الغرض: صرف شيكات وإيداع تبرعات/)).toBeDefined();
  });
});

