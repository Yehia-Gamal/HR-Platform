import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { EmployeeActivityTimeline } from '../EmployeeActivityTimeline';
import type { Employee360 } from '@ahla/shared-contracts';

const mockEmployee: Employee360 = {
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
  documents: [{ id: 'doc-1', type: 'contract', title: 'عقد العمل', expiryDate: null, status: 'valid' }],
  assets: [{ id: 'ast-1', assetName: 'حاسب محمول', assetType: 'laptop', serial: 'LAP-01', handedOverAt: null, returnedAt: null }],
  recentRequests: [],
  recentTasks: [],
  lastUpdatedAt: null,
};

describe('EmployeeActivityTimeline', () => {
  it('renders timeline header and milestones', () => {
    render(<EmployeeActivityTimeline employee={mockEmployee} />);

    expect(screen.getByText('سجل النشاط والمحطات الإدارية')).toBeInTheDocument();
    expect(screen.getByText(/بدء الخدمة والتعيين الرسمي/i)).toBeInTheDocument();
    expect(screen.getByText(/منح رتبة التميز الوظيفي الفضية/i)).toBeInTheDocument();
    expect(screen.getByText(/إغلاق ومراجعة كشف الحضور الدوري/i)).toBeInTheDocument();
    expect(screen.getByText(/اعتماد دورة تقييم الأداء/i)).toBeInTheDocument();
    expect(screen.getByText(/تسليم واستلام العهد والأجهزة المؤسسية/i)).toBeInTheDocument();
    expect(screen.getByText(/إيداع وتدقيق مسوغات التعيين/i)).toBeInTheDocument();
  });

  it('handles employee with minimum optional fields', () => {
    const minimalEmployee: Employee360 = {
      ...mockEmployee,
      latestKpi: null,
      attendance30: { present: 0, lateDays: 0, absent: 0, workMinutes: 0 },
      assets: [],
      documents: [],
    };

    render(<EmployeeActivityTimeline employee={minimalEmployee} />);

    expect(screen.getByText('سجل النشاط والمحطات الإدارية')).toBeInTheDocument();
    expect(screen.getByText(/بدء الخدمة والتعيين الرسمي/i)).toBeInTheDocument();
    expect(screen.getByText(/منح رتبة التميز الوظيفي الفضية/i)).toBeInTheDocument();
  });
});
