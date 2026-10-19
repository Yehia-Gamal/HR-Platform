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
  it('renders executive summary statistics, Donut chart, and department matrix for executive director', () => {
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
            shiftName: 'الدوام الأساسي (10 ص – 6 م)',
            lateMinutes: 0,
          },
          {
            employeeId: 'emp-2',
            employeeName: 'محمد سعيد',
            departmentName: 'إدارة الحسابات',
            status: 'absent',
            firstCheckIn: null,
            lastCheckOut: null,
            shiftName: 'الدوام الأساسي (10 ص – 6 م)',
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
    expect(screen.getByText('تقرير الحضور التنفيذي المعتمد')).toBeDefined();
    expect(screen.getByText('كشف المتابعة اليومية للحضور والانصراف')).toBeDefined();

    // Stats and KPIs
    expect(screen.getByText(/قوة العمل/)).toBeDefined();
    expect(screen.getByText('الحضور الفعلي')).toBeDefined();

    // Donut Chart
    expect(screen.getByText('توزيع قوى العمل اليوم')).toBeDefined();
    expect(screen.getByText('نظرة بصرية شاملة على توزيع الحالات والانضباط الميداني')).toBeDefined();

    // Department matrix
    expect(screen.getByText(/مصفوفة الانضباط وتوزيع القوى/)).toBeDefined();

    // Table rows
    expect(screen.getByText('أحمد علي')).toBeDefined();
    expect(screen.getByText('محمد سعيد')).toBeDefined();
    expect(screen.getByText('سارة حسن')).toBeDefined();

    // Action buttons
    expect(screen.getByText('حفظ كصورة (PNG)')).toBeDefined();
    expect(screen.getByText('نسخ الصورة لواتساب')).toBeDefined();
    expect(screen.getByText('طباعة / PDF (A4)')).toBeDefined();
    expect(screen.getByText('نسخ نص واتساب')).toBeDefined();
  });

  it('renders pending mission with badge, destination, and purpose without duplication', () => {
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
            shiftName: 'الدوام الأساسي (10 ص – 6 م)',
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
    expect(screen.getByText(/طلب معلّق \(خرج قبل الاعتماد\) #594/)).toBeDefined();

    // Destination and purpose
    expect(screen.getByText(/📍 كورنيش المعادي/)).toBeDefined();
    expect(screen.getByText(/💬 الغرض: صرف شيكات وإيداع تبرعات/)).toBeDefined();
  });

  it('includes employee who checked in and went out on mission in unified mission section', () => {
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
            pendingRequestTitle: 'شراء طفايات الحريق مجمع المنيل',
            leaveTitle: 'شراء طفايات الحريق مجمع المنيل',
            leaveReason: 'شراء طفايات الحريق لمجمع منيل شيحة',
          },
        ],
        total: 1,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-19" onClose={() => undefined} />);

    // Mohamed Sayed is listed
    expect(screen.getByText('محمد سيد محمد')).toBeDefined();

    // Shows in unified mission section
    expect(screen.getByText(/قائمة المأموريات والتكليفات الميدانية الرسمية/)).toBeDefined();

    // Destination is shown
    expect(screen.getByText(/📍 شراء طفايات الحريق مجمع المنيل/)).toBeDefined();
  });

  it('renders official association logo image, verified security code and refined header typography', () => {
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
    expect(logoImg.src).toContain('data:image/png;base64');

    // Title and association name
    expect(screen.getByText('جمعية خواطر أحلى شباب')).toBeDefined();
    expect(screen.getByText('كشف المتابعة اليومية للحضور والانصراف')).toBeDefined();
    expect(screen.getByText(/بيان تنفيذي رسمي معتمد للإدارة التنفيذية/)).toBeDefined();

    // Security Verification Code
    expect(screen.getByText(/كود التحقق: EXEC-20261019-/)).toBeDefined();
  });

  it('switches between Live Roster, End of Day, and Comparative Audit views', async () => {
    const { fireEvent } = await import('@testing-library/react');

    rosterHook = {
      data: {
        items: [
          {
            employeeId: 'emp-eod-1',
            employeeName: 'كريم محمود',
            departmentName: 'إدارة تكنولوجيا المعلومات',
            status: 'present',
            firstCheckIn: '2026-10-19T07:00:00Z',
            lastCheckOut: '2026-10-19T13:30:00Z',
            shiftName: 'الدوام الأساسي (10 ص – 6 م)',
            lateMinutes: 0,
          },
        ],
        total: 1,
      },
      isLoading: false,
      isError: false,
    };

    render(<ExecutiveAttendanceModal dateIso="2026-10-19" onClose={() => undefined} />);

    // 1. Initial live view
    expect(screen.getByText('كشف المتابعة اليومية للحضور والانصراف')).toBeDefined();

    // 2. Switch to End of Day
    fireEvent.click(screen.getByText(/كشف إغلاق اليوم وساعات العمل/));
    expect(screen.getByText('كشف إغلاق اليوم وساعات العمل والانصراف')).toBeDefined();
    expect(screen.getByText('اكتمل انصرافهم')).toBeDefined();

    // 3. Switch to Comparative Audit
    fireEvent.click(screen.getByText(/مقارنة التدقيق المنطقي/));
    expect(screen.getByText('مصفوفة التدقيق والتحقق المنطقي لكشف الحضور (قبل وبعد)')).toBeDefined();
    expect(screen.getByText(/دليل التدقيق والتحقق للمدير التنفيذي/)).toBeDefined();
    expect(screen.getByText(/الغياب غير المبرر/)).toBeDefined();
  });
});

