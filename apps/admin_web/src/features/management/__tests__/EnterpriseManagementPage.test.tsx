import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { EnterpriseManagementPage } from '../EnterpriseManagementPage';

const mockCatalog = {
  objectives: [{ id: 'obj-1', code: 'OBJ-001', title: 'الهدف الأول', progress: 50, status: 'active' }],
  projects: [{ id: 'proj-1', code: 'PRJ-001', name: 'مشروع التطوير', openTasks: 3, progress: 25, status: 'active' }],
  risks: [{ id: 'risk-1', title: 'مخاطرة تشغيلية', score: 8, category: 'تشغيلي', status: 'open' }],
  serviceRequests: [{ id: 'sr-1', title: 'طلب خدمة', status: 'open' }],
  qualityCases: [{ id: 'qc-1', title: 'حالة جودة', number: 'QC-001', severity: 'medium', status: 'open' }],
  meetings: [],
  audits: [],
  incidents: [],
  automations: [],
  dataAssets: [],
  aiUseCases: [],
};

const emptyCatalog = {
  objectives: [],
  projects: [],
  risks: [],
  serviceRequests: [],
  qualityCases: [],
  meetings: [],
  audits: [],
  incidents: [],
  automations: [],
  dataAssets: [],
  aiUseCases: [],
};

let catalogReturn: Record<string, unknown> = {};

vi.mock('../useEnterpriseManagement', () => ({
  useEnterpriseManagementCatalog: () => catalogReturn,
}));

function Wrapper({ children }: { children: React.ReactNode }) {
  return <MemoryRouter>{children}</MemoryRouter>;
}

const dataQuery = {
  data: mockCatalog,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyQuery = {
  data: emptyCatalog,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};

describe('EnterpriseManagementPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogReturn = dataQuery;
    const { container } = render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogReturn = dataQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('مركز الإدارة المؤسسية')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    catalogReturn = dataQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('الأهداف')).toBeDefined();
    expect(screen.getByText('المشروعات')).toBeDefined();
    expect(screen.getByText('المخاطر المفتوحة')).toBeDefined();
    expect(screen.getByText('طلبات الخدمة')).toBeDefined();
  });

  it('يعرض لوحات المحتوى', () => {
    catalogReturn = dataQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('الأهداف والمشروعات')).toBeDefined();
    expect(screen.getByText('المخاطر والحوادث')).toBeDefined();
    expect(screen.getByText('الحوكمة والأتمتة')).toBeDefined();
  });

  it('يعرض بيانات الأهداف والمشروعات', () => {
    catalogReturn = dataQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('OBJ-001 — الهدف الأول')).toBeDefined();
    expect(screen.getByText('PRJ-001 — مشروع التطوير')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    catalogReturn = loadingQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('جارٍ تحميل مركز الإدارة المؤسسية…')).toBeDefined();
  });

  it('يعرض رسائل فارغة في اللوحات عند غياب البيانات', () => {
    catalogReturn = emptyQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('ستظهر البيانات بعد بدء الاستخدام.').length).toBeGreaterThan(0);
  });

  it('يعرض حالة الخطأ', () => {
    catalogReturn = errorQuery;
    render(
      <Wrapper>
        <EnterpriseManagementPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل مركز الإدارة المؤسسية')).toBeDefined();
  });
});
