import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ApprovalSpeedPage } from '../ApprovalSpeedPage';
import { MOCK_APPROVAL_SPEED_REPORT } from '../useApprovalSpeedReport';

let mockHookState: () => Record<string, unknown>;

vi.mock('../useApprovalSpeedReport', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../useApprovalSpeedReport')>();
  return {
    ...actual,
    useApprovalSpeedReport: () => mockHookState(),
  };
});

const dataState = {
  data: MOCK_APPROVAL_SPEED_REPORT,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
  isFetching: false,
};

const loadingState = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
  isFetching: false,
};

const errorState = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('خطأ في الصلاحيات'),
  refetch: vi.fn(),
  isFetching: false,
};

describe('ApprovalSpeedPage', () => {
  it('يُعرض بدون أخطاء ويعرض عنوان اللوحة والمؤشرات', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('لوحة سرعة الاعتمادات وSLA')).toBeDefined();
    expect(screen.getByText('إجمالي القرارات')).toBeDefined();
    expect(screen.getByText('وسيط زمن الرد')).toBeDefined();
    expect(screen.getByText('متوسط زمن الرد')).toBeDefined();
    expect(screen.getByText('طلبات معلقة')).toBeDefined();
    expect(screen.getByText('تم تصعيدها')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    mockHookState = () => loadingState;
    const { container } = render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ وزر إعادة المحاولة', () => {
    mockHookState = () => errorState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تعذر تحميل تقرير سرعة الاعتمادات')).toBeDefined();
    expect(screen.getByText('إعادة المحاولة')).toBeDefined();
  });

  it('يعرض جدول المعتمدين مع أسماء المسؤولين ومؤشراتهم', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('محمد عبدالباسط ( ابو عمار )')).toBeDefined();
    expect(screen.getByText('مصطفي محمد فايد')).toBeDefined();
    expect(screen.getByText('سجل المعتمدين وسرعة الإنجاز')).toBeDefined();
  });

  it('يدعم البحث بالاسم وتصفية النتائج', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );

    const searchInput = screen.getByPlaceholderText('بحث بالاسم أو الهاتف...');
    fireEvent.change(searchInput, { target: { value: 'ابو عمار' } });

    expect(screen.getByText('محمد عبدالباسط ( ابو عمار )')).toBeDefined();
    expect(screen.queryByText('مصطفي محمد فايد')).toBeNull();
  });

  it('يعرض تفصيل السرعة حسب نوع الطلب', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('السرعة حسب نوع الطلب')).toBeDefined();
    expect(screen.getByText('مأمورية عمل')).toBeDefined();
    expect(screen.getByText('طلب إجازة')).toBeDefined();
  });

  it('يعرض زر تصدير CSV ومحدد الفترات', () => {
    mockHookState = () => dataState;
    render(
      <MemoryRouter>
        <ApprovalSpeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText('تصدير CSV')).toBeDefined();
    expect(screen.getByText('اليوم')).toBeDefined();
    expect(screen.getByText('7 أيام')).toBeDefined();
    expect(screen.getByText('الشهر')).toBeDefined();
    expect(screen.getByText('الكل')).toBeDefined();
  });
});
