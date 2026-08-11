import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { SystemSettingsPage } from '../SystemSettingsPage';

/* ─── mock بيانات إعدادات النظام ─────────────────────────────── */
const mockSetting = {
  key: 'max_leave_days',
  labelAr: 'أقصى أيام الإجازة',
  description: 'الحد الأقصى لأيام طلب الإجازة السنوية',
  value: '30',
  valueType: 'integer',
  groupName: 'requests',
};

const mockMutation = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

/* ─── factory functions لحالات الـ hooks ────────────────────── */
let settingsOverride: () => Record<string, unknown>;
let updateOverride: () => Record<string, unknown>;

vi.mock('../../finance/useFinancialExtensions', () => ({
  useEditableSystemSettings: () => settingsOverride(),
  useUpdateSystemSettings: () => updateOverride(),
}));

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const emptyQuery = { data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: [mockSetting], isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: vi.fn() };

describe('SystemSettingsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    settingsOverride = () => dataQuery;
    updateOverride = () => mockMutation;
    const { container } = render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    settingsOverride = () => dataQuery;
    updateOverride = () => mockMutation;
    render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(screen.getByText('إعدادات النظام')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    settingsOverride = () => loadingQuery;
    updateOverride = () => mockMutation;
    const { container } = render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود إعدادات', () => {
    settingsOverride = () => emptyQuery;
    updateOverride = () => mockMutation;
    render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(screen.getByText('لا توجد إعدادات قابلة للتعديل.')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    settingsOverride = () => errorQuery;
    updateOverride = () => mockMutation;
    render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(screen.getByText('إعادة المحاولة')).toBeDefined();
  });

  it('يعرض مجموعات الإعدادات عند توفر البيانات', () => {
    settingsOverride = () => dataQuery;
    updateOverride = () => mockMutation;
    render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    // groupLabel('requests') = 'الطلبات'
    expect(screen.getByText('الطلبات')).toBeDefined();
    expect(screen.getByText('أقصى أيام الإجازة')).toBeDefined();
  });

  it('يعرض زر حفظ الكل', () => {
    settingsOverride = () => dataQuery;
    updateOverride = () => mockMutation;
    render(<MemoryRouter><SystemSettingsPage /></MemoryRouter>);
    expect(screen.getByText('حفظ الكل')).toBeDefined();
  });
});
