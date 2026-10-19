import { render, screen, fireEvent, act } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ManualMissingCheckoutModal } from '../ManualMissingCheckoutModal';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';

const mockPresentItems: AttendanceRosterItem[] = [
  {
    employeeId: 'emp-1',
    employeeName: 'أحمد علي',
    employeeCode: 'EMP-001',
    departmentName: 'الشؤون الإدارية',
    branchName: 'مجمع منيل شيحة',
    shiftName: 'الصباحية (9 ص – 5 م)',
    photoUrl: null,
    status: 'present',
    lateMinutes: 0,
    firstCheckIn: '2026-10-19T06:15:00Z',
    lastCheckOut: null,
    locationRequestStatus: null,
  },
  {
    employeeId: 'emp-2',
    employeeName: 'سارة إبراهيم',
    employeeCode: 'EMP-002',
    departmentName: 'العيادات الطبية',
    branchName: 'مجمع منيل شيحة',
    shiftName: 'المسائية (3 م – 11 م)',
    photoUrl: null,
    status: 'present',
    lateMinutes: 10,
    firstCheckIn: '2026-10-19T12:10:00Z',
    lastCheckOut: null,
    locationRequestStatus: null,
  },
];

describe('ManualMissingCheckoutModal', () => {
  it('renders modal title and candidate employees with check-in time', () => {
    const handleClose = vi.fn();
    const handleMark = vi.fn().mockResolvedValue(undefined);

    render(
      <ManualMissingCheckoutModal
        dateIso="2026-10-19"
        onClose={handleClose}
        onMark={handleMark}
        isActionPending={false}
        alreadyMarkedIds={new Set()}
        presentItems={mockPresentItems}
      />,
    );

    expect(screen.getByText('تسجيل موظف «مشي بدون بصمة»')).toBeDefined();
    expect(screen.getByText('أحمد علي')).toBeDefined();
    expect(screen.getByText('سارة إبراهيم')).toBeDefined();
  });

  it('triggers onMark when clicking "تسجيل مشي بدون بصمة"', async () => {
    const handleClose = vi.fn();
    const handleMark = vi.fn().mockResolvedValue(undefined);

    render(
      <ManualMissingCheckoutModal
        dateIso="2026-10-19"
        onClose={handleClose}
        onMark={handleMark}
        isActionPending={false}
        alreadyMarkedIds={new Set()}
        presentItems={mockPresentItems}
      />,
    );

    const markButtons = screen.getAllByText('تسجيل مشي بدون بصمة');
    expect(markButtons.length).toBeGreaterThan(0);
    await act(async () => {
      fireEvent.click(markButtons[0]);
    });

    expect(handleMark).toHaveBeenCalledWith(['emp-1']);
  });

  it('filters candidates based on search input', () => {
    const handleClose = vi.fn();
    const handleMark = vi.fn().mockResolvedValue(undefined);

    render(
      <ManualMissingCheckoutModal
        dateIso="2026-10-19"
        onClose={handleClose}
        onMark={handleMark}
        isActionPending={false}
        alreadyMarkedIds={new Set()}
        presentItems={mockPresentItems}
      />,
    );

    const searchInput = screen.getByPlaceholderText(/ابحث بالاسم أو الرقم الوظيفي/);
    fireEvent.change(searchInput, { target: { value: 'سارة' } });

    expect(screen.queryByText('أحمد علي')).toBeNull();
    expect(screen.getByText('سارة إبراهيم')).toBeDefined();
  });
});
