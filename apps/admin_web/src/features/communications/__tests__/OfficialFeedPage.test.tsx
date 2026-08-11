import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { OfficialFeedPage } from '../OfficialFeedPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مدير اختبار',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['main_admin'],
  permissions: ['*'],
  workspaces: ['main_admin'] as const,
  defaultWorkspace: 'main_admin' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null, data: null };

const mockEngagement = {
  data: { viewerCount: 12, reactionCount: 5, myReaction: null, reactions: [] },
  isLoading: false,
  isError: false,
};

vi.mock('../useOfficialFeed', () => ({
  useOfficialFeed: () => feedOverrideFn(),
  usePublishAnnouncement: () => noopMutation,
  useCreateDecisionDraft: () => noopMutation,
  useTransitionDecision: () => noopMutation,
  useAnnouncementEngagement: () => mockEngagement,
  useToggleReaction: () => ({ ...noopMutation, data: { myReaction: null } }),
}));

let feedOverrideFn: () => Record<string, unknown>;

const mockItems = [
  {
    id: '44000000-0000-4000-8000-000000000001',
    kind: 'decision',
    title: 'قرار تنظيم التقارير الأسبوعية',
    body: 'تسلم التقارير قبل نهاية يوم الخميس.',
    category: 'executive',
    priority: 'high',
    status: 'published',
    requiresAcknowledgement: true,
    publishedAt: '2026-08-01T10:00:00Z',
    expiresAt: null,
    acknowledgedCount: 39,
    targetCount: 54,
    viewCount: 0,
    reactionCount: 0,
    reactionSummary: {},
  },
  {
    id: '44000000-0000-4000-8000-000000000002',
    kind: 'announcement',
    title: 'موعد اجتماع مناقشة النظام الجديد',
    body: 'يعقد الاجتماع في القاعة الرئيسية.',
    category: 'event',
    priority: 'normal',
    status: 'published',
    requiresAcknowledgement: false,
    publishedAt: '2026-07-14T10:00:00Z',
    expiresAt: null,
    acknowledgedCount: 0,
    targetCount: null,
    viewCount: 12,
    reactionCount: 5,
    reactionSummary: {},
  },
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل الاتصال'), refetch: vi.fn() };
const dataQuery = { data: mockItems, isLoading: false, isError: false, error: null, refetch: vi.fn() };

describe('OfficialFeedPage', () => {
  it('يُعرض بدون أخطاء', () => {
    feedOverrideFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByText('القناة الرسمية للأخبار والقرارات')).toBeInTheDocument();
  });

  it('يعرض هيكل التحميل عند الانتظار', () => {
    feedOverrideFn = () => loadingQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByLabelText('جارٍ تحميل القناة الرسمية')).toBeInTheDocument();
  });

  it('يعرض رسالة الخطأ عند فشل التحميل', () => {
    feedOverrideFn = () => errorQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByText(/تعذر تحميل القناة/)).toBeInTheDocument();
  });

  it('يعرض حالة فارغة عندما لا توجد منشورات', () => {
    feedOverrideFn = () => emptyQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد منشورات بعد')).toBeInTheDocument();
  });

  it('يعرض عناوين المنشورات', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByText('قرار تنظيم التقارير الأسبوعية')).toBeInTheDocument();
    expect(screen.getByText('موعد اجتماع مناقشة النظام الجديد')).toBeInTheDocument();
  });

  it('يعرض البطاقات الإحصائية بالأرقام الصحيحة', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    // المنشورات الكلية = 2
    expect(screen.getByText('المنشورات')).toBeInTheDocument();
    // القرارات = 1
    expect(screen.getByText('القرارات')).toBeInTheDocument();
  });

  it('يعرض زر "عنصر رسمي جديد" للمستخدم المخوّل', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByText('عنصر رسمي جديد')).toBeInTheDocument();
  });

  it('يفلتر المنشورات بحسب نوع القرار', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    const select = screen.getByRole('combobox', { name: 'نوع العنصر الرسمي' });
    fireEvent.change(select, { target: { value: 'decision' } });
    expect(screen.getByText('قرار تنظيم التقارير الأسبوعية')).toBeInTheDocument();
    expect(screen.queryByText('موعد اجتماع مناقشة النظام الجديد')).not.toBeInTheDocument();
  });

  it('يفلتر المنشورات بالبحث النصي', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    const searchInput = screen.getByPlaceholderText('بحث في عنوان أو محتوى المنشور');
    fireEvent.change(searchInput, { target: { value: 'اجتماع' } });
    expect(screen.queryByText('قرار تنظيم التقارير الأسبوعية')).not.toBeInTheDocument();
    expect(screen.getByText('موعد اجتماع مناقشة النظام الجديد')).toBeInTheDocument();
  });

  it('يعرض حالة "لا توجد نتائج" عند بحث بدون مطابقة', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    const searchInput = screen.getByPlaceholderText('بحث في عنوان أو محتوى المنشور');
    fireEvent.change(searchInput, { target: { value: 'نص غير موجود أبداً' } });
    expect(screen.getByText('لا توجد نتائج مطابقة')).toBeInTheDocument();
  });

  it('يعرض شريط التفاعلات على الإعلانات المنشورة', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    // الإعلان المنشور يجب أن يحتوي على أزرار التفاعل
    expect(screen.getByRole('button', { name: 'إعجاب' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'احتفال' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'دعم' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'ملهم' })).toBeInTheDocument();
  });

  it('يعرض شريط نسبة الإقرار للمنشورات التي تتطلبه', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    expect(screen.getByRole('progressbar', { name: 'نسبة الاطلاع والإقرار' })).toBeInTheDocument();
    expect(screen.getByText('39 / 54')).toBeInTheDocument();
  });

  it('يفتح نافذة الإنشاء عند الضغط على زر "عنصر رسمي جديد"', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByText('عنصر رسمي جديد'));
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });

  it('يعيد ضبط الفلاتر عند الضغط على "مسح الفلاتر"', () => {
    feedOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <OfficialFeedPage />
      </Wrapper>,
    );
    const searchInput = screen.getByPlaceholderText('بحث في عنوان أو محتوى المنشور');
    fireEvent.change(searchInput, { target: { value: 'بحث' } });
    const clearButton = screen.getByRole('button', { name: /مسح/ });
    fireEvent.click(clearButton);
    expect(searchInput).toHaveValue('');
  });
});
