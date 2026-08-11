import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { InstapayPage } from '../InstapayPage';

let catalogFn: () => Record<string, unknown>;
vi.mock('../usePeopleFinance', () => ({
  usePeopleFinanceCatalog: () => catalogFn(),
}));

let batchesFn: () => Record<string, unknown>;
let generateFn: () => Record<string, unknown>;
vi.mock('../useFinancialExtensions', () => ({
  INSTAPAY_STATUS_LABELS: {
    pending: 'معلق',
    processing: 'قيد المعالجة',
    sent: 'أُرسل',
    failed: 'فشل',
  },
  useInstapayBatches: () => batchesFn(),
  useGenerateInstapayBatch: () => generateFn(),
}));

const emptyBatches = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingBatches = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const idleMutation = {
  isPending: false,
  isError: false,
  isSuccess: false,
  error: null,
  mutateAsync: vi.fn(),
};
const emptyFinance = {
  data: { payrollRuns: [] },
  isLoading: false,
  isError: false,
  error: null,
};
const loadingFinance = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
};

function renderPage() {
  return render(
    <MemoryRouter>
      <InstapayPage />
    </MemoryRouter>,
  );
}

describe('InstapayPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogFn = () => emptyFinance;
    batchesFn = () => emptyBatches;
    generateFn = () => idleMutation;
    const { container } = renderPage();
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogFn = () => emptyFinance;
    batchesFn = () => emptyBatches;
    generateFn = () => idleMutation;
    renderPage();
    expect(screen.getByText('صرف الرواتب عبر InstaPay')).toBeDefined();
  });

  it('يعرض قسم توليد الدفعة الجديدة', () => {
    catalogFn = () => emptyFinance;
    batchesFn = () => emptyBatches;
    generateFn = () => idleMutation;
    renderPage();
    expect(screen.getByText('توليد دفعة جديدة')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    catalogFn = () => loadingFinance;
    batchesFn = () => loadingBatches;
    generateFn = () => idleMutation;
    const { container } = renderPage();
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود دفعات', () => {
    catalogFn = () => emptyFinance;
    batchesFn = () => emptyBatches;
    generateFn = () => idleMutation;
    renderPage();
    expect(screen.getByText('لا توجد دفعات بعد')).toBeDefined();
  });

  it('يعرض زر تصدير PDF وشريط التصفية', () => {
    catalogFn = () => emptyFinance;
    batchesFn = () => emptyBatches;
    generateFn = () => idleMutation;
    renderPage();
    expect(screen.getByTitle('طباعة PDF')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب الحالة')).toBeDefined();
  });
});
