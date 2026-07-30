import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';

/* ─── mock لكل hooks الأجهزة ────────────────────────────────────── */
const mockRefetch = vi.fn();
const noop = vi.fn();

let pendingReturn: Record<string, unknown> = {};
let allReturn: Record<string, unknown> = {};

vi.mock('../useDevices', () => ({
  useDeviceApprovals: () => pendingReturn,
  useAllDevices: () => allReturn,
  useApproveDevice: () => ({ mutate: noop, isPending: false, isError: false, error: null }),
  useRevokeDevice: () => ({ mutate: noop, isPending: false, isError: false, error: null }),
}));

import { DeviceApprovalPage } from '../DeviceApprovalPage';

describe('DeviceApprovalPage', () => {
  it('يعرض عنوان الصفحة والوصف', () => {
    pendingReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByText('أجهزة الموظفين')).toBeDefined();
  });

  it('يعرض ألسنة التبويب', () => {
    pendingReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByText('طلبات الأجهزة')).toBeDefined();
    expect(screen.getByText('كل الأجهزة')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود أجهزة معلّقة', () => {
    pendingReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByText('لا توجد أجهزة معلّقة')).toBeDefined();
  });

  it('يعرض المقاييس عند وجود أجهزة معلّقة', () => {
    pendingReturn = {
      data: [
        {
          id: 'dev-1',
          employeeId: 'emp-1',
          employeeName: 'أحمد محمد',
          employeeCode: 'E001',
          employeePhotoUrl: null,
          deviceName: 'Samsung Galaxy',
          platform: 'android',
          status: 'pending',
          registeredAt: new Date().toISOString(),
          lastUsedAt: null,
          rejectionReason: null,
          revocationSource: null,
          metadata: {},
        },
      ],
      isLoading: false,
      isError: false,
      refetch: mockRefetch,
    };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByText('إجمالي المعلّقة')).toBeDefined();
    // "بانتظار الموافقة" تظهر في المقياس وفي خيارات الفلتر
    expect(screen.getAllByText('بانتظار الموافقة').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('محظورة')).toBeDefined();
  });

  it('يعرض بطاقة الجهاز مع اسم الموظف', () => {
    pendingReturn = {
      data: [
        {
          id: 'dev-1',
          employeeId: 'emp-1',
          employeeName: 'أحمد محمد',
          employeeCode: 'E001',
          employeePhotoUrl: null,
          deviceName: 'Samsung Galaxy',
          platform: 'android',
          status: 'pending',
          registeredAt: new Date().toISOString(),
          lastUsedAt: null,
          rejectionReason: null,
          revocationSource: null,
          metadata: {},
        },
      ],
      isLoading: false,
      isError: false,
      refetch: mockRefetch,
    };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByText('أحمد محمد')).toBeDefined();
  });

  it('يعرض أزرار الموافقة والرفض', () => {
    pendingReturn = {
      data: [
        {
          id: 'dev-1',
          employeeId: 'emp-1',
          employeeName: 'أحمد محمد',
          employeeCode: 'E001',
          employeePhotoUrl: null,
          deviceName: 'Samsung Galaxy',
          platform: 'android',
          status: 'pending',
          registeredAt: new Date().toISOString(),
          lastUsedAt: null,
          rejectionReason: null,
          revocationSource: null,
          metadata: {},
        },
      ],
      isLoading: false,
      isError: false,
      refetch: mockRefetch,
    };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(screen.getByLabelText('الموافقة على جهاز أحمد محمد')).toBeDefined();
    expect(screen.getByLabelText('رفض جهاز أحمد محمد')).toBeDefined();
  });

  it('يعرض هياكل التحميل أثناء جلب البيانات', () => {
    pendingReturn = { data: undefined, isLoading: true, isError: false, refetch: mockRefetch };
    allReturn = { data: undefined, isLoading: true, isError: false, refetch: mockRefetch };
    const { container } = render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
    expect(screen.queryByText('لا توجد أجهزة معلّقة')).toBeNull();
  });

  it('يعرض حالة الخطأ عند فشل الطلب', () => {
    pendingReturn = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: mockRefetch };
    allReturn = { data: [], isLoading: false, isError: false, refetch: mockRefetch };
    render(<DeviceApprovalPage />, { wrapper: ToastProvider });
    // ErrorState يظهر عند الخطأ
    expect(screen.getByText('إعادة المحاولة')).toBeDefined();
  });
});
