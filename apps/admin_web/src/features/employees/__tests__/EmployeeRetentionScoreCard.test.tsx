import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { EmployeeRetentionScoreCard } from '../EmployeeRetentionScoreCard';
import type { Employee360 } from '@ahla/shared-contracts';

const mockBaseEmployee: Employee360 = {
  id: '00000000-0000-0000-0000-000000000101',
  employeeCode: 'EMP-101',
  fullNameAr: 'طارق محمود',
  fullNameEn: 'Tarek Mahmoud',
  phoneE164: '01000000000',
  photoUrl: null,
  status: 'active',
  isActive: true,
  hireDate: '2024-01-01',
  contractEnd: null,
  probationEnd: null,
  jobTitle: 'مهندس أول',
  position: null,
  grade: null,
  department: 'الهندسة والتطوير',
  team: null,
  branch: 'المقر الرئيسي',
  workSite: null,
  managerName: 'أحمد سعيد',
  accountStatus: 'active',
  email: 'tarek@example.com',
  departments: [],
  roles: [],
  directReports: 0,
  attendance30: { present: 22, lateDays: 0, absent: 0, workMinutes: 9900 },
  requestCounts: { pending: 0, approved: 0, rejected: 0 },
  latestKpi: {
    id: '00000000-0000-0000-0000-000000000001',
    periodMonth: '2025-01',
    currentStage: 'معتمد',
    finalScore: 95,
    finalRating: 'ممتاز',
  },
  documents: [],
  assets: [],
  recentRequests: [],
  recentTasks: [],
  lastUpdatedAt: null,
};

describe('EmployeeRetentionScoreCard', () => {
  it('renders excellent retention score for disciplined employee', () => {
    render(<EmployeeRetentionScoreCard employee={mockBaseEmployee} />);

    expect(screen.getByText(/مؤشر الاستقرار والولاء الوظيفي/i)).toBeInTheDocument();
    expect(screen.getByText('استقرار والتزام ممتاز')).toBeInTheDocument();
    expect(screen.getByText('100%')).toBeInTheDocument();
    expect(screen.getByText(/الموظف يظهر التزاماً استثنائياً/i)).toBeInTheDocument();
  });

  it('renders alert state for employee with high absence and low KPI', () => {
    const strugglingEmployee: Employee360 = {
      ...mockBaseEmployee,
      attendance30: { present: 10, lateDays: 5, absent: 6, workMinutes: 4500 },
      latestKpi: {
        id: '00000000-0000-0000-0000-000000000002',
        periodMonth: '2025-01',
        currentStage: 'معتمد',
        finalScore: 55,
        finalRating: 'ضعيف',
      },
    };

    render(<EmployeeRetentionScoreCard employee={strugglingEmployee} />);

    expect(screen.getByText('خطر تسرب أو انقطاع وظيفي مرتفع')).toBeInTheDocument();
    expect(screen.getByText(/تكرار الغياب والانخفاض في مؤشرات الأداء/i)).toBeInTheDocument();
  });
});
