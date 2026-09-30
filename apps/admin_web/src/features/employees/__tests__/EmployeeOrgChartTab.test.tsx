import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import type { Employee360 } from '@ahla/shared-contracts';
import { EmployeeOrgChartTab } from '../EmployeeOrgChartTab';

const mockEmployee360: Employee360 = {
  id: '33333333-3333-4333-8333-333333333333',
  employeeCode: 'EMP-003',
  fullNameAr: 'رئيس قسم التوظيف',
  fullNameEn: 'Hiring Lead',
  phoneE164: '+201000000000',
  photoUrl: null,
  status: 'active',
  isActive: true,
  hireDate: '2025-01-01',
  contractEnd: null,
  probationEnd: null,
  jobTitle: 'رئيس قسم التوظيف',
  position: null,
  grade: null,
  department: 'الموارد البشرية',
  team: null,
  branch: 'الفرع الرئيسي',
  workSite: null,
  managerName: 'مدير الموارد البشرية',
  accountStatus: 'active',
  email: 'lead@example.com',
  departments: [],
  roles: [],
  directReports: 1,
  attendance30: { present: 22, lateDays: 0, absent: 0, workMinutes: 10560 },
  requestCounts: { pending: 0, approved: 2, rejected: 0 },
  latestKpi: null,
  documents: [],
  assets: [],
  recentRequests: [],
  recentTasks: [],
  lastUpdatedAt: '2026-09-01T00:00:00Z',
};

const mockHierarchyData = {
  employee: {
    id: '33333333-3333-4333-8333-333333333333',
    fullNameAr: 'رئيس قسم التوظيف',
    fullNameEn: 'Hiring Lead',
    photoUrl: null,
    jobTitle: 'رئيس قسم التوظيف',
    departmentName: 'الموارد البشرية',
    employeeCode: 'EMP-003',
    departmentId: null,
    status: 'active',
    managerEmployeeId: '22222222-2222-4222-8222-222222222222',
    directReportsCount: 1,
    depth: 2,
    path: ['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333'],
  },
  ancestors: [
    {
      id: '11111111-1111-4111-8111-111111111111',
      fullNameAr: 'المدير التنفيذي',
      fullNameEn: 'CEO',
      photoUrl: null,
      jobTitle: 'الرئيس التنفيذي',
      departmentName: 'الإدارة العليا',
      employeeCode: 'EMP-001',
      departmentId: null,
      status: 'active',
      managerEmployeeId: null,
      directReportsCount: 1,
      depth: 0,
      path: ['11111111-1111-4111-8111-111111111111'],
    },
    {
      id: '22222222-2222-4222-8222-222222222222',
      fullNameAr: 'مدير الموارد البشرية',
      fullNameEn: 'HR Director',
      photoUrl: null,
      jobTitle: 'مدير الموارد البشرية',
      departmentName: 'الموارد البشرية',
      employeeCode: 'EMP-002',
      departmentId: null,
      status: 'active',
      managerEmployeeId: '11111111-1111-4111-8111-111111111111',
      directReportsCount: 1,
      depth: 1,
      path: ['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'],
    },
  ],
  directReports: [
    {
      id: '44444444-4444-4444-8444-444444444444',
      fullNameAr: 'أخصائي توظيف أول',
      fullNameEn: 'Senior Recruiter',
      photoUrl: null,
      jobTitle: 'أخصائي توظيف أول',
      departmentName: 'الموارد البشرية',
      employeeCode: 'EMP-004',
      departmentId: null,
      status: 'active',
      managerEmployeeId: '33333333-3333-4333-8333-333333333333',
      directReportsCount: 0,
      depth: 3,
      path: [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
      ],
    },
  ],
  allSubordinates: [
    {
      id: '44444444-4444-4444-8444-444444444444',
      fullNameAr: 'أخصائي توظيف أول',
      fullNameEn: 'Senior Recruiter',
      photoUrl: null,
      jobTitle: 'أخصائي توظيف أول',
      departmentName: 'الموارد البشرية',
      employeeCode: 'EMP-004',
      departmentId: null,
      status: 'active',
      managerEmployeeId: '33333333-3333-4333-8333-333333333333',
      directReportsCount: 0,
      depth: 3,
      path: [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
      ],
    },
  ],
  subTree: {
    employee: {
      id: '33333333-3333-4333-8333-333333333333',
      fullNameAr: 'رئيس قسم التوظيف',
      fullNameEn: 'Hiring Lead',
      photoUrl: null,
      jobTitle: 'رئيس قسم التوظيف',
      departmentName: 'الموارد البشرية',
      employeeCode: 'EMP-003',
      departmentId: null,
      status: 'active',
      managerEmployeeId: '22222222-2222-4222-8222-222222222222',
      directReportsCount: 1,
      depth: 2,
      path: ['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333'],
    },
    children: [
      {
        employee: {
          id: '44444444-4444-4444-8444-444444444444',
          fullNameAr: 'أخصائي توظيف أول',
          fullNameEn: 'Senior Recruiter',
          photoUrl: null,
          jobTitle: 'أخصائي توظيف أول',
          departmentName: 'الموارد البشرية',
          employeeCode: 'EMP-004',
          departmentId: null,
          status: 'active',
          managerEmployeeId: '33333333-3333-4333-8333-333333333333',
          directReportsCount: 0,
          depth: 3,
          path: [
            '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222',
            '33333333-3333-4333-8333-333333333333',
            '44444444-4444-4444-8444-444444444444',
          ],
        },
        children: [],
      },
    ],
  },
  stats: {
    directReportsCount: 1,
    totalSubordinatesCount: 1,
    managersUnderCount: 0,
    maxSubtreeDepth: 1,
  },
  isTopLevel: false,
  hasSubordinates: true,
};

const hookResult = {
  data: mockHierarchyData,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

vi.mock('../useEmployeeOrgHierarchy', () => ({
  useEmployeeOrgHierarchy: () => hookResult,
}));

describe('EmployeeOrgChartTab', () => {
  it('يعرض عنوان التبويب وبطاقات المؤشرات وسلسلة القيادة', () => {
    render(
      <MemoryRouter>
        <EmployeeOrgChartTab employeeId={mockEmployee360.id} employee={mockEmployee360} />
      </MemoryRouter>,
    );

    expect(screen.getByText('الهيكل والتسلسل الإداري للموظف')).toBeDefined();
    expect(screen.getAllByText('المدير المباشر').length).toBeGreaterThan(0);
    expect(screen.getByText('المرؤوسون المباشرون')).toBeDefined();
    expect(screen.getByText('إجمالي الفريق التابع')).toBeDefined();
    expect(screen.getByText('سلسلة القيادة الإدارية (التسلسل الصاعد)')).toBeDefined();

    // التأكد من ظهور مديري السلسلة الصاعدة
    expect(screen.getByText('المدير التنفيذي')).toBeDefined();
    expect(screen.getAllByText('مدير الموارد البشرية').length).toBeGreaterThan(0);

    // التأكد من ظهور المرؤوس في الشجرة
    expect(screen.getAllByText('أخصائي توظيف أول').length).toBeGreaterThan(0);
  });
});
