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

  it('includes employee who checked in and went out on mission in Table 1 with mission destination', () => {
    rosterHook = {
      data: {
        items: [
          {
            employeeId: 'emp-mohamed-sayed',
            employeeName: 'محمد سيد محمد',
            departmentName: 'إدارة اللوجستيك',
            branchName: 'مجمع أحلى شباب - منيل شيحة',
            status: 'present',
            firstCheckIn: '2026-10-19T06:57:39Z',
            lastCheckOut: null,
            shiftName: 'الدوام الأساسي (10 ص – 6 م)',
            lateMinutes: 0,
            hasPendingRequest: true,
            pendingRequestNumber: 599,
            pendingRequestType: 'mission',
            pendingRequestTitle: 'نازل اشتري طفايات الحريق مجمع المنيل',
            leaveTitle: 'نازل اشتري طفايات الحريق مجمع المنيل',
            leaveReason: 'شراء طفايات الحريق لمجمع منيل شيحة',
          },
        ],
        total: 1,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-19" onClose={() => undefined} />);

    // In Table 1: Mohamed Sayed is listed
    expect(screen.getAllByText('محمد سيد محمد').length).toBeGreaterThanOrEqual(1);

    // Shows mission divider banner
    expect(screen.getByText(/موظفون سجلوا حضوراً ثم خرجوا في مأموريات عمل ميدانية/)).toBeDefined();

    // Destination is shown (in Table 1 and Table 3)
    expect(screen.getAllByText(/📍 نازل اشتري طفايات الحريق مجمع المنيل/).length).toBe(2);

    // Does NOT say "متواجد حالياً في المجمع" for Mohamed Sayed
    expect(screen.queryByText('متواجد حالياً في المجمع')).toBeNull();
  });

  it('renders official association logo image and refined header typography', () => {
    rosterHook = {
      data: {
        items: [],
        total: 0,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-19" onClose={() => undefined} />);

    // Logo image is present
    const logoImg = screen.getByAltText('شعار جمعية خواطر أحلى شباب') as HTMLImageElement;
    expect(logoImg).toBeDefined();
    expect(logoImg.src).toContain('/brand/association-logo-white.png');

    // Title and association name
    expect(screen.getByText('جمعية خواطر أحلى شباب')).toBeDefined();
    expect(screen.getByText('كشف المتابعة اليومية للحضور والانصراف')).toBeDefined();
    expect(screen.getByText(/بيان تنفيذي رسمي معتمد للإدارة التنفيذية/)).toBeDefined();

    // Word "أحلى" standalone badge is replaced by logo
    expect(screen.queryByText('أحلى')).toBeNull();
  });
});


