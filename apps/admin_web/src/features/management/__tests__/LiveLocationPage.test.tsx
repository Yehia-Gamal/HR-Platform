import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { LiveLocationPage } from '../LiveLocationPage';

/* ─── mock بيانات موظف مع معلومات موقع ───────────────────────── */
const mockLocationItem = {
  id: '00000000-0000-0000-0000-000000000001',
  name: 'أحمد محمد',
  employeeCode: 'EMP001',
  jobTitle: 'موظف ميداني',
  department: 'الميدان',
  lastLatitude: 30.0622,
  lastLongitude: 31.2357,
  lastAccuracy: 10,
  lastRecordedAt: new Date().toISOString(),
  activeRequestId: null,
  activeRequestStatus: null,
};

const mockMutation = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

/* ─── factory functions لحالات الـ hook ─────────────────────── */
let locationDirectoryOverride: () => Record<string, unknown>;
let locationCommandsOverride: () => Record<string, unknown>;

vi.mock('../useControlCenters', () => ({
  useLocationDirectory: () => locationDirectoryOverride(),
  useLiveLocationCommands: () => locationCommandsOverride(),
}));

/* ─── mock ExecutiveMonitoringPage لتجنب تبعياتها ─────────────── */
vi.mock('../ExecutiveMonitoringPage', () => ({
  ExecutiveMonitoringPage: () => <div data-testid="exec-monitoring">ExecutiveMonitoring</div>,
}));

const loadingDirectoryQuery = { data: undefined, isLoading: true, isError: false, isFetching: true, error: null, refetch: vi.fn() };
const emptyDirectoryQuery = { data: [], isLoading: false, isError: false, isFetching: false, error: null, refetch: vi.fn() };
const dataDirectoryQuery = { data: [mockLocationItem], isLoading: false, isError: false, isFetching: false, error: null, refetch: vi.fn() };

const defaultCommands = { request: { ...mockMutation } };

describe('LiveLocationPage', () => {
  it('يُعرض بدون أخطاء', () => {
    locationDirectoryOverride = () => dataDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    const { container } = render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    locationDirectoryOverride = () => dataDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(screen.getByText('مركز الموقع الحي')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    locationDirectoryOverride = () => loadingDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    const { container } = render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض بطاقات المؤشرات الأربع', () => {
    locationDirectoryOverride = () => dataDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(screen.getByText('ضمن نطاق الوصول')).toBeDefined();
    expect(screen.getByText('متصلون خلال 15 دقيقة')).toBeDefined();
    // "طلبات نشطة" يظهر مرتين: بطاقة مؤشر + زر تصفية
    expect(screen.getAllByText('طلبات نشطة').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('دون موقع مسجل')).toBeDefined();
  });

  it('يعرض أزرار التبويب', () => {
    locationDirectoryOverride = () => dataDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(screen.getByText('دليل المواقع')).toBeDefined();
    expect(screen.getByText('متابعة اليوم')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود موظفين', () => {
    locationDirectoryOverride = () => emptyDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(screen.getByText('لا توجد نتائج مطابقة')).toBeDefined();
  });

  it('يعرض اسم الموظف في دليل المواقع', () => {
    locationDirectoryOverride = () => dataDirectoryQuery;
    locationCommandsOverride = () => defaultCommands;
    render(<MemoryRouter><LiveLocationPage /></MemoryRouter>);
    expect(screen.getByText('أحمد محمد')).toBeDefined();
  });
});
