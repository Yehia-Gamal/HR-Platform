import { renderHook } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { OrgChartEmployee, OrgChartTreeNode } from '@ahla/shared-contracts';
import { useEmployeeOrgHierarchy } from '../useEmployeeOrgHierarchy';

const CEO_ID = '11111111-1111-4111-8111-111111111111';
const DIRECTOR_ID = '22222222-2222-4222-8222-222222222222';
const EMPLOYEE_ID = '33333333-3333-4333-8333-333333333333';
const SUBORDINATE_1_ID = '44444444-4444-4444-8444-444444444444';
const SUBORDINATE_2_ID = '55555555-5555-4555-8555-555555555555';

const mockEmployees: OrgChartEmployee[] = [
  {
    id: CEO_ID,
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
    path: [CEO_ID],
  },
  {
    id: DIRECTOR_ID,
    fullNameAr: 'مدير الإدارة',
    fullNameEn: 'Director',
    photoUrl: null,
    jobTitle: 'مدير الموارد البشرية',
    departmentName: 'الموارد البشرية',
    employeeCode: 'EMP-002',
    departmentId: null,
    status: 'active',
    managerEmployeeId: CEO_ID,
    directReportsCount: 1,
    depth: 1,
    path: [CEO_ID, DIRECTOR_ID],
  },
  {
    id: EMPLOYEE_ID,
    fullNameAr: 'رئيس الفريق',
    fullNameEn: 'Team Lead',
    photoUrl: null,
    jobTitle: 'رئيس قسم التوظيف',
    departmentName: 'الموارد البشرية',
    employeeCode: 'EMP-003',
    departmentId: null,
    status: 'active',
    managerEmployeeId: DIRECTOR_ID,
    directReportsCount: 2,
    depth: 2,
    path: [CEO_ID, DIRECTOR_ID, EMPLOYEE_ID],
  },
  {
    id: SUBORDINATE_1_ID,
    fullNameAr: 'أخصائي توظيف 1',
    fullNameEn: 'Recruiter 1',
    photoUrl: null,
    jobTitle: 'أخصائي توظيف أول',
    departmentName: 'الموارد البشرية',
    employeeCode: 'EMP-004',
    departmentId: null,
    status: 'active',
    managerEmployeeId: EMPLOYEE_ID,
    directReportsCount: 1,
    depth: 3,
    path: [CEO_ID, DIRECTOR_ID, EMPLOYEE_ID, SUBORDINATE_1_ID],
  },
  {
    id: SUBORDINATE_2_ID,
    fullNameAr: 'مساعد توظيف',
    fullNameEn: 'Assistant',
    photoUrl: null,
    jobTitle: 'مساعد توظيف',
    departmentName: 'الموارد البشرية',
    employeeCode: 'EMP-005',
    departmentId: null,
    status: 'active',
    managerEmployeeId: SUBORDINATE_1_ID,
    directReportsCount: 0,
    depth: 4,
    path: [CEO_ID, DIRECTOR_ID, EMPLOYEE_ID, SUBORDINATE_1_ID, SUBORDINATE_2_ID],
  },
];

const mockTree: OrgChartTreeNode[] = [
  {
    employee: mockEmployees[0],
    children: [
      {
        employee: mockEmployees[1],
        children: [
          {
            employee: mockEmployees[2],
            children: [
              {
                employee: mockEmployees[3],
                children: [
                  {
                    employee: mockEmployees[4],
                    children: [],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
];

const mockChartData = {
  data: {
    employees: mockEmployees,
    tree: mockTree,
    stats: { totalEmployees: 5, managersCount: 4, maxDepth: 4, avgDirectReports: 1 },
  },
  isLoading: false,
  error: null,
  refetch: vi.fn(),
};

vi.mock('../../management/useOrgChart', () => ({
  useOrgChart: () => mockChartData,
}));

describe('useEmployeeOrgHierarchy', () => {
  it('يستخرج سلسلة القيادة الإدارية الصاعدة بشكل صحيح', () => {
    const { result } = renderHook(() => useEmployeeOrgHierarchy(EMPLOYEE_ID));
    expect(result.current.data).toBeDefined();

    const data = result.current.data!;
    expect(data.employee.id).toBe(EMPLOYEE_ID);
    expect(data.ancestors.length).toBe(2);
    expect(data.ancestors[0].id).toBe(CEO_ID);
    expect(data.ancestors[1].id).toBe(DIRECTOR_ID);
  });

  it('يحدد موظف الإدارة العليا الذي ليس لديه مدير كـ isTopLevel', () => {
    const { result } = renderHook(() => useEmployeeOrgHierarchy(CEO_ID));
    expect(result.current.data?.isTopLevel).toBe(true);
    expect(result.current.data?.ancestors.length).toBe(0);
  });

  it('يستخرج المرؤوسين المباشرين وغير المباشرين وشجرة الفريق التابع بدقة', () => {
    const { result } = renderHook(() => useEmployeeOrgHierarchy(EMPLOYEE_ID));
    const data = result.current.data!;

    expect(data.hasSubordinates).toBe(true);
    expect(data.directReports.length).toBe(1);
    expect(data.directReports[0].id).toBe(SUBORDINATE_1_ID);

    // إجمالي المرؤوسين يشمل التابعين المباشرين وغير المباشرين
    expect(data.allSubordinates.length).toBe(2);
    expect(data.stats.totalSubordinatesCount).toBe(2);
    expect(data.stats.managersUnderCount).toBe(1); // SUBORDINATE_1 لديه مرؤوس
  });

  it('يتعامل مع الموظف الفردي الذي ليس لديه مرؤوسين', () => {
    const { result } = renderHook(() => useEmployeeOrgHierarchy(SUBORDINATE_2_ID));
    const data = result.current.data!;

    expect(data.hasSubordinates).toBe(false);
    expect(data.directReports.length).toBe(0);
    expect(data.allSubordinates.length).toBe(0);
    expect(data.stats.totalSubordinatesCount).toBe(0);
  });

  it('يبني سياقاً احتياطياً إذا كان الموظف غير موجود في شجرة الهيكل', () => {
    const UNKNOWN_ID = '99999999-9999-4999-8999-999999999999';
    const { result } = renderHook(() =>
      useEmployeeOrgHierarchy(UNKNOWN_ID, {
        fullNameAr: 'موظف تجريبي جديد',
        jobTitle: 'مطور واجهات',
        department: 'التقنية',
        managerName: 'أحمد الإداري',
        managerId: DIRECTOR_ID,
        directReports: 0,
      }),
    );

    const data = result.current.data!;
    expect(data.employee.fullNameAr).toBe('موظف تجريبي جديد');
    expect(data.ancestors.length).toBe(1);
    expect(data.ancestors[0].id).toBe(DIRECTOR_ID);
    expect(data.hasSubordinates).toBe(false);
  });
});
