import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { KnowledgePage } from '../KnowledgePage';

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
  displayName: 'مستخدم اختبار',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let catalogOverrideFn: () => Record<string, unknown>;
vi.mock('../useKnowledge', () => ({
  useKnowledgeCatalog: () => catalogOverrideFn(),
  useUpsertKnowledgeArticle: () => noopMutation,
  useDeleteKnowledgeArticle: () => noopMutation,
  useUpsertKnowledgeCategory: () => noopMutation,
  useDeleteKnowledgeCategory: () => noopMutation,
}));

const mockCatalog = {
  articles: [
    {
      id: '11111111-1111-4111-8111-111111111111',
      title: 'دليل سياسة الإجازات',
      body: 'يحق لكل موظف الحصول على إجازة سنوية مدتها 21 يوم.',
      category: 'سياسات',
      category_id: 'cat-1',
      category_name: 'سياسات',
      is_published: true,
      created_at: '2026-01-10T10:00:00Z',
      updated_at: '2026-01-15T10:00:00Z',
    },
  ],
  categories: [
    { id: 'cat-1', name: 'سياسات', slug: 'policies', description: null, is_active: true },
  ],
  publishedCount: 1,
  draftCount: 0,
};

const emptyCatalog = { articles: [], categories: [], publishedCount: 0, draftCount: 0 };

const emptyQuery = { data: emptyCatalog, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockCatalog, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('KnowledgePage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByText('قاعدة المعرفة')).toBeDefined();
  });

  it('يعرض شريط البحث', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByPlaceholderText('ابحث بالعنوان أو المحتوى أو التصنيف…')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByText('مقالات منشورة')).toBeDefined();
    expect(screen.getByText('مسودات')).toBeDefined();
    expect(screen.getByText('تصنيفات')).toBeDefined();
  });

  it('يعرض المقالات عند توفر البيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByText('دليل سياسة الإجازات')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود مقالات', () => {
    catalogOverrideFn = () => emptyQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد مقالات')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض زر إنشاء مقال للمستخدم ذي الصلاحيات الكاملة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <KnowledgePage />
      </Wrapper>,
    );
    expect(screen.getByText('مقال جديد')).toBeDefined();
  });
});
