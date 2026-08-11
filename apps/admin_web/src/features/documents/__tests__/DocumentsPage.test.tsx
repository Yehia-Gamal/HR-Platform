import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { DocumentsPage } from '../DocumentsPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockDoc = {
  id: 'doc-1',
  employeeId: 'emp-1',
  employeeName: 'أحمد محمد',
  employeeCode: 'EMP-001',
  title: 'هوية وطنية',
  type: 'national_id',
  number: '1234567890',
  expiryDate: '2027-01-01',
  status: 'active' as const,
  verified: false,
  uploadedAt: '2026-01-01T00:00:00Z',
};

const mockCatalogData = {
  documents: [mockDoc],
  assets: [],
  offboarding: [],
  expiringDocuments: 2,
  assignedAssets: 5,
  openOffboarding: 1,
  lastUpdatedAt: '2026-08-01T00:00:00Z',
};

const emptyCatalogData = {
  documents: [],
  assets: [],
  offboarding: [],
  expiringDocuments: 0,
  assignedAssets: 0,
  openOffboarding: 0,
  lastUpdatedAt: '2026-08-01T00:00:00Z',
};

let catalogReturn: Record<string, unknown> = {};

vi.mock('../useDocuments', () => ({
  useDocumentsCatalog: () => catalogReturn,
  useReviewDocument: () => ({
    mutate: vi.fn(),
    mutateAsync: vi.fn(),
    isPending: false,
    isError: false,
    error: null,
  }),
  DOCUMENT_STATUS_LABELS: {
    active: 'ساري',
    expired: 'منتهي',
    rejected: 'مرفوض',
    archived: 'مؤرشف',
  },
  ASSET_STATUS_LABELS: {
    available: 'متاح',
    assigned: 'مُسلم',
    return_requested: 'طلب استرجاع',
    returned: 'مسترجع',
    retired: 'متقاعد',
  },
  OFFBOARDING_STATUS_LABELS: {
    draft: 'مسودة',
    submitted: 'مُقدّم',
    in_clearance: 'في التخليص',
    ready_for_approval: 'جاهز للاعتماد',
    approved: 'معتمد',
    completed: 'مكتمل',
    cancelled: 'ملغي',
  },
}));

const dataQuery = {
  data: mockCatalogData,
  isLoading: false,
  isError: false,
  error: null,
  isFetching: false,
  refetch: vi.fn(),
};
const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  isFetching: true,
  refetch: vi.fn(),
};
const emptyQuery = {
  data: emptyCatalogData,
  isLoading: false,
  isError: false,
  error: null,
  isFetching: false,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  isFetching: false,
  refetch: vi.fn(),
};

describe('DocumentsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogReturn = dataQuery;
    const { container } = render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogReturn = dataQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('استوديو المستندات')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    catalogReturn = dataQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('مستندات تنتهي قريباً')).toBeDefined();
    expect(screen.getByText('عهد مُسلّمة')).toBeDefined();
    expect(screen.getByText('حالات خروج نشطة')).toBeDefined();
  });

  it('يعرض تبويبات الصفحة', () => {
    catalogReturn = dataQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('المستندات')).toBeDefined();
    expect(screen.getByText('العهد والأصول')).toBeDefined();
    expect(screen.getByText('إنهاء الخدمة')).toBeDefined();
  });

  it('يعرض بيانات المستندات', () => {
    catalogReturn = dataQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('أحمد محمد')).toBeDefined();
    expect(screen.getByText('هوية وطنية')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    catalogReturn = loadingQuery;
    const { container } = render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود مستندات', () => {
    catalogReturn = emptyQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('لا توجد مستندات')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    catalogReturn = errorQuery;
    render(<Wrapper><DocumentsPage /></Wrapper>);
    expect(screen.getByText('تعذّر تحميل البيانات')).toBeDefined();
  });
});
