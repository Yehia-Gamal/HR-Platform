import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { AuditTrailPage } from '../AuditTrailPage';

/* ─── mock بيانات سجل التدقيق ────────────────────────────────── */
const mockAuditItem = {
  id: '00000000-0000-0000-0000-000000000001',
  eventType: 'employee_created',
  category: 'hr',
  severity: 'info',
  actorUserId: '00000000-0000-0000-0000-000000000010',
  actorEmployeeId: null,
  actorName: 'المسؤول',
  targetTable: 'employees',
  targetId: null,
  summaryAr: 'تم إنشاء موظف جديد',
  metadata: null,
  occurredAt: new Date().toISOString(),
};

const mockAuditCategoryLabels: Record<string, string> = {
  hr: 'موارد بشرية',
  system: 'النظام',
  security: 'أمن',
  financial: 'مالية',
  data: 'بيانات',
};

const mockAuditSeverityLabels: Record<string, string> = {
  info: 'معلومة',
  warning: 'تحذير',
  error: 'خطأ',
  critical: 'حرج',
};

/* ─── factory function لحالات الـ hook ──────────────────────── */
let auditTrailOverride: () => Record<string, unknown>;

vi.mock('../../finance/useFinancialExtensions', () => ({
  useAuditTrail: () => auditTrailOverride(),
  AUDIT_CATEGORY_LABELS: { hr: 'موارد بشرية', system: 'النظام', security: 'أمن', financial: 'مالية', data: 'بيانات' },
  AUDIT_SEVERITY_LABELS: { info: 'معلومة', warning: 'تحذير', error: 'خطأ', critical: 'حرج' },
}));

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const emptyQuery = { data: { total: 0, items: [] }, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: { total: 1, items: [mockAuditItem] }, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: vi.fn() };

describe('AuditTrailPage', () => {
  it('يُعرض بدون أخطاء', () => {
    auditTrailOverride = () => dataQuery;
    const { container } = render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    auditTrailOverride = () => dataQuery;
    render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(screen.getByText('سجل التدقيق')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    auditTrailOverride = () => loadingQuery;
    const { container } = render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود سجلات', () => {
    auditTrailOverride = () => emptyQuery;
    render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(screen.getByText('لا توجد أحداث')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    auditTrailOverride = () => errorQuery;
    render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    // ErrorState يستخدم onRetry، نتحقق من وجود زر أو نص الخطأ
    expect(screen.getByText('إعادة المحاولة')).toBeDefined();
  });

  it('يعرض قوائم تصفية التصنيف والخطورة', () => {
    auditTrailOverride = () => dataQuery;
    render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(screen.getByLabelText('تصفية حسب التصنيف')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب الخطورة')).toBeDefined();
  });

  it('يعرض صفوف البيانات في جدول عند توفرها', () => {
    auditTrailOverride = () => dataQuery;
    render(<MemoryRouter><AuditTrailPage /></MemoryRouter>);
    expect(screen.getByText('تم إنشاء موظف جديد')).toBeDefined();
    expect(screen.getByText('المسؤول')).toBeDefined();
  });
});
