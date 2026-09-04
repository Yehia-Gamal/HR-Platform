import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CustomReportBuilder } from '../CustomReportBuilder';
import { ToastProvider } from '../../../ui/Toast';

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => ({
    data: [
      {
        id: 'emp-1',
        employeeCode: 'EMP-001',
        fullNameAr: 'أحمد محمد',
        fullNameEn: 'Ahmed Mohamed',
        department: 'تكنولوجيا المعلومات',
        jobTitle: 'مهندس برمجيات',
        branch: 'الفرع الرئيسي',
        team: 'فريق الويب',
        phoneE164: '01012345678',
        status: 'active',
        isActive: true,
        photoUrl: null,
        departmentId: null,
        teamId: null,
        branchId: null,
        createdAt: '2024-01-01T00:00:00Z',
      },
      {
        id: 'emp-2',
        employeeCode: 'EMP-002',
        fullNameAr: 'منى حسن',
        fullNameEn: 'Mona Hassan',
        department: 'الموارد البشرية',
        jobTitle: 'أخصائي توظيف',
        branch: 'الفرع الرئيسي',
        team: 'فريق التوظيف',
        phoneE164: '01098765432',
        status: 'active',
        isActive: true,
        photoUrl: null,
        departmentId: null,
        teamId: null,
        branchId: null,
        createdAt: '2024-02-01T00:00:00Z',
      },
    ],
    isLoading: false,
    isError: false,
  }),
}));

describe('CustomReportBuilder', () => {
  it('renders report builder header and preset buttons', () => {
    render(
      <ToastProvider>
        <CustomReportBuilder />
      </ToastProvider>,
    );

    expect(screen.getByText('منشئ التقارير المخصص')).toBeInTheDocument();
    expect(screen.getByText('الكشف الوظيفي الشامل')).toBeInTheDocument();
    expect(screen.getByText('دليل الاتصال والمعلومات الوظيفية')).toBeInTheDocument();
    expect(screen.getByText('كشف التعيينات والهيكل التنظيمي')).toBeInTheDocument();
  });

  it('renders employee rows in the table', () => {
    render(
      <ToastProvider>
        <CustomReportBuilder />
      </ToastProvider>,
    );

    expect(screen.getByText('أحمد محمد')).toBeInTheDocument();
    expect(screen.getByText('منى حسن')).toBeInTheDocument();
    expect(screen.getByText('EMP-001')).toBeInTheDocument();
    expect(screen.getByText('EMP-002')).toBeInTheDocument();
  });

  it('switches columns when a preset is clicked', () => {
    render(
      <ToastProvider>
        <CustomReportBuilder />
      </ToastProvider>,
    );

    fireEvent.click(screen.getByText('دليل الاتصال والمعلومات الوظيفية'));
    expect(screen.getAllByText('رقم الهاتف').length).toBeGreaterThanOrEqual(1);
  });

  it('has export excel button', () => {
    render(
      <ToastProvider>
        <CustomReportBuilder />
      </ToastProvider>,
    );

    const exportBtn = screen.getByRole('button', { name: /تصدير Excel/i });
    expect(exportBtn).toBeInTheDocument();
    expect(exportBtn).not.toBeDisabled();
  });
});
