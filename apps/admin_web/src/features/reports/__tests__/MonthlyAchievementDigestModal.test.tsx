import { render, screen, fireEvent } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MonthlyAchievementDigestModal } from '../MonthlyAchievementDigestModal';
import { ToastProvider } from '../../../ui/Toast';

const mockEmployees = [
  {
    id: 'emp-1',
    employeeCode: 'EMP-101',
    fullNameAr: 'أحمد محمود',
    department: 'العمليات واللوجستيات',
    status: 'active' as const,
    isActive: true,
    phoneE164: '+201012345678',
  },
  {
    id: 'emp-2',
    employeeCode: 'EMP-102',
    fullNameAr: 'سارة خالد',
    department: 'الموارد البشرية',
    status: 'active' as const,
    isActive: true,
    phoneE164: null,
  },
];

const mockDailyReports = [
  {
    id: 'rep-1',
    employeeId: 'emp-1',
    employeeName: 'أحمد محمود',
    reportDate: '2026-10-05',
    achievements: 'توزيع 50 كرتونة مواد غذائية بالقرية 1\nمتابعة التخزين اللوجستي',
    blockers: 'عطل في سيارة النقل تم إصلاحه',
    tomorrowPlan: 'استكمال المسح الميداني',
    managerComment: 'جهد متميز وعمل متقن',
    reviewerName: 'طارق سامي',
    reviewedAt: '2026-10-05T18:00:00Z',
    createdAt: '2026-10-05T17:00:00Z',
  },
  {
    id: 'rep-2',
    employeeId: 'emp-1',
    employeeName: 'أحمد محمود',
    reportDate: '2026-10-06',
    achievements: 'تسليم مساعدات لـ 20 أسرة مستحقة',
    blockers: 'لا يوجد',
    tomorrowPlan: 'تسليم التقارير الورقية',
    managerComment: null,
    reviewerName: null,
    reviewedAt: null,
    createdAt: '2026-10-06T17:00:00Z',
  },
];

const mockShareWhatsApp = vi.fn();

vi.mock('../../../core/whatsappShare', () => ({
  shareMonthlyAchievementReport: (...args: unknown[]) => mockShareWhatsApp(...args),
  cleanPhoneForWhatsApp: (p: string) => p,
  openWhatsApp: vi.fn(),
}));

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => ({ data: mockEmployees, isLoading: false }),
}));

vi.mock('../../employees/useEmployeeDossier', () => ({
  useEmployeeDailyReports: () => ({ data: mockDailyReports, isLoading: false }),
}));

describe('MonthlyAchievementDigestModal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders modal with title, employee selector and stats', () => {
    render(
      <ToastProvider>
        <MonthlyAchievementDigestModal
          isOpen={true}
          onClose={vi.fn()}
          initialYear={2026}
          initialMonth={10}
        />
      </ToastProvider>,
    );

    expect(screen.getByText('مُولّد تقرير الإنجاز الشهري الذكي')).toBeDefined();
    expect(screen.getByText(/أيام التوثيق/)).toBeDefined();
    expect(screen.getByText(/إجمالي المهام/)).toBeDefined();
    expect(screen.getByText('توزيع 50 كرتونة مواد غذائية بالقرية 1')).toBeDefined();
    expect(screen.getByText('متابعة التخزين اللوجستي')).toBeDefined();
    expect(screen.getByText('تسليم مساعدات لـ 20 أسرة مستحقة')).toBeDefined();
  });

  it('triggers WhatsApp share with aggregated achievements', () => {
    render(
      <ToastProvider>
        <MonthlyAchievementDigestModal
          isOpen={true}
          onClose={vi.fn()}
          initialYear={2026}
          initialMonth={10}
        />
      </ToastProvider>,
    );

    const shareBtn = screen.getByRole('button', { name: /مشاركة واتساب كتقرير رسمي/ });
    fireEvent.click(shareBtn);

    expect(mockShareWhatsApp).toHaveBeenCalledTimes(1);
    expect(mockShareWhatsApp).toHaveBeenCalledWith(
      expect.objectContaining({
        employeeName: 'أحمد محمود',
        monthName: 'أكتوبر',
        year: 2026,
        reportedDaysCount: 2,
        achievementsCount: 3,
      }),
    );
  });
});
