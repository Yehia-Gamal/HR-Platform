import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ExecutiveMonthlyReportPage } from '../ExecutiveMonthlyReportPage';
import { MOCK_EXECUTIVE_MONTHLY_REPORT } from '../useExecutiveMonthlyReport';

let mockHookState: () => Record<string, unknown>;

vi.mock('../useExecutiveMonthlyReport', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../useExecutiveMonthlyReport')>();
  return {
    ...actual,
    useExecutiveMonthlyReport: () => mockHookState(),
  };
});

const mockExport = vi.fn().mockResolvedValue(undefined);
vi.mock('../exportExecutiveMonthlyReport', () => ({
  exportExecutiveMonthlyReport: (...args: unknown[]) => mockExport(...args),
}));

const dataState = {
  data: MOCK_EXECUTIVE_MONTHLY_REPORT,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
  regenerate: vi.fn().mockResolvedValue(MOCK_EXECUTIVE_MONTHLY_REPORT),
  isRegenerating: false,
};

const loadingState = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
  regenerate: vi.fn(),
  isRegenerating: false,
};

const errorState = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('خطأ في الصلاحيات'),
  refetch: vi.fn(),
  regenerate: vi.fn(),
  isRegenerating: false,
};

describe('ExecutiveMonthlyReportPage', () => {
  it('يُعرض بدون أخطاء ويعرض عنوان التقرير والمؤشرات الرئيسية', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('التقرير الشهري التنفيذي الشامل')).toBeDefined();
    expect(screen.getByText('نسبة الحضور العامة')).toBeDefined();
    expect(screen.getByText('الموظفون النشطون')).toBeDefined();
    expect(screen.getByText('حركة الطلبات والمعتمدة')).toBeDefined();
    expect(screen.getByText('سرعة الاعتماد (SLA)')).toBeDefined();
    expect(screen.getByText('أداء الحضور والانضباط عبر الإدارات والأقسام')).toBeDefined();
  });

  it('يعرض الإدارات وأرقامها بشكل صحيح', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('الإدارة العامة والموارد البشرية')).toBeDefined();
    expect(screen.getByText('إدارة العمليات الميدانية والقوافل')).toBeDefined();
    expect(screen.getByText('96.4%')).toBeDefined();
  });

  it('يعرض حالة التحميل عند جلب البيانات', () => {
    mockHookState = () => loadingState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('جارٍ استخراج وتجميع بيانات التقرير الشهري...')).toBeDefined();
  });

  it('يعرض رسالة الخطأ وزر إعادة المحاولة عند الفشل', () => {
    mockHookState = () => errorState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    expect(screen.getByText(/فشل استخراج التقرير/)).toBeDefined();
    expect(screen.getByText('إعادة المحاولة')).toBeDefined();
  });

  it('يستدعي تصدير PDF عند النقر على زر التصدير', async () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    const exportBtn = screen.getByText('تصدير PDF');
    fireEvent.click(exportBtn);

    await waitFor(() => {
      expect(mockExport).toHaveBeenCalled();
    });
  });

  it('يسمح بتغيير الشهر والسنة', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ExecutiveMonthlyReportPage />
      </MemoryRouter>,
    );

    const monthSelect = screen.getByLabelText('اختر الشهر');
    fireEvent.change(monthSelect, { target: { value: '5' } });
    expect((monthSelect as HTMLSelectElement).value).toBe('5');
  });
});
