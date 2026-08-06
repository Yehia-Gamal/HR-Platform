import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';

import type * as UseAttendanceDashboard from '../useAttendanceDashboard';
import type * as UseOrganizationLookups from '../../employees/useOrganizationLookups';

let rosterHook: Record<string, unknown> = {};
let lookupsHook: Record<string, unknown> = {};

vi.mock('../useAttendanceDashboard', async (importOriginal) => {
  const actual = await importOriginal<typeof UseAttendanceDashboard>();
  return {
    ...actual,
    useAttendanceRosterPage: () => rosterHook,
  };
});

vi.mock('../../employees/useOrganizationLookups', async (importOriginal) => {
  const actual = await importOriginal<typeof UseOrganizationLookups>();
  return {
    ...actual,
    useOrganizationLookups: () => lookupsHook,
  };
});

vi.mock('../../ui/useResolvedAvatarUrl', () => ({
  useResolvedAvatarUrl: (url: string | null | undefined) => url,
}));

import { AttendanceDrilldownPage } from '../AttendanceDrilldownPage';

function renderPage(entry = '/hr/attendance/details?category=late&date=2026-08-05') {
  return render(
    <MemoryRouter initialEntries={[entry]}>
      <AttendanceDrilldownPage />
    </MemoryRouter>,
  );
}

const pageFixture = {
  items: [
    {
      employeeId: '11111111-2222-3333-4444-555555555555',
      employeeCode: 'EMP-001',
      employeeName: 'أحمد محمد علي',
      departmentName: 'إدارة البرامج',
      photoUrl: null,
      status: 'late',
      lateMinutes: 15,
      firstCheckIn: '2026-08-05T06:15:00Z',
      lastCheckOut: null,
      locationRequestStatus: null,
    },
  ],
  total: 1,
  limit: 25,
  offset: 0,
};

describe('AttendanceDrilldownPage', () => {
  it('يعرض عنوان الفئة وأسماء الموظفين ورابط فتح الملف', () => {
    lookupsHook = { data: { branches: [], departments: [] }, isLoading: false, isError: false };
    rosterHook = {
      data: pageFixture,
      isLoading: false,
      isError: false,
      error: null,
      refetch: () => undefined,
    };
    renderPage();
    expect(screen.getByText('قائمة «متأخرون»')).toBeDefined();
    expect(screen.getByText('أحمد محمد علي')).toBeDefined();
    expect(screen.getByText('EMP-001')).toBeDefined();
    const link = screen.getByText('فتح الملف').closest('a');
    expect(link?.getAttribute('href')).toBe('/hr/employees/11111111-2222-3333-4444-555555555555');
  });

  it('يعرض إجمالي النتائج والترقيم', () => {
    lookupsHook = { data: { branches: [], departments: [] }, isLoading: false, isError: false };
    rosterHook = {
      data: { ...pageFixture, total: 27 },
      isLoading: false,
      isError: false,
      error: null,
      refetch: () => undefined,
    };
    renderPage();
    expect(screen.getByText(/عرض ٢٧ نتيجة/)).toBeDefined();
  });

  it('يعرض حالة فارغة عند غياب العناصر', () => {
    lookupsHook = { data: { branches: [], departments: [] }, isLoading: false, isError: false };
    rosterHook = {
      data: { ...pageFixture, items: [], total: 0 },
      isLoading: false,
      isError: false,
      error: null,
      refetch: () => undefined,
    };
    renderPage('/hr/attendance/details?category=absent&date=2026-08-05');
    expect(screen.getByText('لا عناصر في هذه الفئة')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    lookupsHook = { data: undefined, isLoading: false, isError: false };
    rosterHook = { data: undefined, isLoading: true, isError: false, error: null, refetch: () => undefined };
    renderPage();
    expect(screen.getByRole('status').getAttribute('aria-label')).toBe('جاري تحميل القائمة');
  });

  it('يعرض حالة الخطأ عند فشل الطلب', () => {
    lookupsHook = { data: undefined, isLoading: false, isError: false };
    rosterHook = { data: undefined, isLoading: false, isError: true, error: new Error('network'), refetch: () => undefined };
    renderPage();
    expect(screen.getByText('تعذر تحميل القائمة')).toBeDefined();
  });

  it('يسقط الفئة غير الصالحة إلى المجدولون', () => {
    lookupsHook = { data: { branches: [], departments: [] }, isLoading: false, isError: false };
    rosterHook = {
      data: pageFixture,
      isLoading: false,
      isError: false,
      error: null,
      refetch: () => undefined,
    };
    renderPage('/hr/attendance/details?category=bad');
    expect(screen.getByText('قائمة «المجدولون»')).toBeDefined();
  });
});
