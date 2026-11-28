import { describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { MOCK_PROJECTS, mockCatalog } from './projectMocks';
import { ProjectsDisplayPage, displayOrder, gridFor } from './ProjectsDisplayPage';

const query = vi.hoisted(() => ({ current: {} as Record<string, unknown> }));
vi.mock('./useAssociationProjects', () => ({ useAssociationProjects: () => query.current }));

describe('وضع العرض على الشاشة الكبيرة', () => {
  it('الترتيب: يحتاج تدخل أولاً، والمكتمل أخيراً، والملغى وغير المعتمد مستبعدان', () => {
    const order = displayOrder(MOCK_PROJECTS);
    expect(order[0]?.ledStatus).toBe('critical');
    expect(order.at(-1)?.ledStatus).toBe('completed');
    expect(order.every((p) => p.approvalStatus === 'approved' && p.ledStatus !== 'stale')).toBe(true);
  });

  it('شاشة 1080p (تلفزيون 64 بوصة) = 4 أعمدة × 3 صفوف', () => {
    expect(gridFor(1920, 1080)).toEqual({ cols: 4, rows: 3 });
    expect(gridFor(1366, 768)).toEqual({ cols: 3, rows: 2 });
    // مشاريع أقل = بطاقات أكبر
    expect(gridFor(1920, 1080, 5)).toEqual({ cols: 3, rows: 2 });
    expect(gridFor(1920, 1080, 2)).toEqual({ cols: 2, rows: 1 });
    expect(gridFor(1920, 1080, 30)).toEqual({ cols: 4, rows: 3 });
  });

  it('يعرض العدّادات والبطاقات، وتنبيه انقطاع مع إبقاء آخر بيانات', () => {
    query.current = { data: mockCatalog(), error: new Error('offline'), dataUpdatedAt: Date.now() - 3 * 60_000 };
    render(
      <MemoryRouter>
        <ProjectsDisplayPage />
      </MemoryRouter>,
    );
    expect(screen.getByRole('heading', { name: 'مشاريع الجمعية' })).toBeInTheDocument();
    expect(screen.getByText('تجاوز الموعد')).toBeInTheDocument();
    expect(screen.getByText('تجهيز مخزن المساعدات الجديد')).toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('منذ 3 دقائق');
  });

  it('أثناء التحميل الأول', () => {
    query.current = { data: undefined, error: null, dataUpdatedAt: 0 };
    render(
      <MemoryRouter>
        <ProjectsDisplayPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('جارٍ تحميل المشاريع…')).toBeInTheDocument();
  });

  it('يبرز سبب التعطل والمسؤول وأقرب موعد في بطاقة المشروع على شاشة المكتب', () => {
    const stopped = {
      ...MOCK_PROJECTS[0]!,
      status: 'on_hold' as const,
      ledStatus: 'halted' as const,
      isOverdue: false,
      leaderName: 'مسؤول المشروع',
      interruptionNote: 'بانتظار اعتماد دفعة المورد',
      nextDeadline: '2026-12-08',
      nextDeadlineTitle: 'استلام المعدات',
    };
    query.current = { data: { ...mockCatalog(), projects: [stopped] } };
    render(<MemoryRouter><ProjectsDisplayPage displayOnly /></MemoryRouter>);

    const card = screen.getByRole('article');
    expect(card).toHaveAttribute('data-interrupted', 'true');
    expect(card).toHaveTextContent('بانتظار اعتماد دفعة المورد');
    expect(card).toHaveTextContent('مسؤول المشروع');
    expect(card).toHaveTextContent('أقرب موعد');
    expect(screen.getByTitle('استلام المعدات')).toHaveTextContent('8');
  });

  it('يعرض مشاريع المدير التنفيذي دون روابط إلى مساحات الإدارة', () => {
    query.current = { data: mockCatalog() };
    const signOut = vi.fn(async () => {});
    render(<MemoryRouter><ProjectsDisplayPage displayOnly onSignOut={signOut} /></MemoryRouter>);

    expect(screen.getByRole('heading', { name: 'تجهيز مخزن المساعدات الجديد' })).toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'تسجيل الخروج' }));
    expect(signOut).toHaveBeenCalledOnce();
  });

  it('يعزل أسباب المتابعة ويحافظ على مسار الرجوع إلى مساحة المستخدم', () => {
    query.current = { data: mockCatalog() };
    render(
      <MemoryRouter initialEntries={[{ pathname: '/projects/display', state: { boardPath: '/hr/association-projects' } }]}>
        <ProjectsDisplayPage />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole('button', { name: /تحتاج متابعة/ }));
    expect(screen.queryByText('قافلة طبية — قرى الصعيد')).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'تجهيز مخزن المساعدات الجديد' })).toHaveAttribute(
      'href', `/hr/association-projects?project=${MOCK_PROJECTS[2]!.id}`,
    );
    expect(screen.getByRole('link', { name: 'العودة إلى لوحة المشاريع' })).toHaveAttribute('href', '/hr/association-projects');
  });

  it('يدعم التقليب اليدوي والإيقاف والاستئناف', () => {
    vi.useFakeTimers();
    vi.stubGlobal('innerWidth', 390);
    const refetch = vi.fn();
    query.current = { data: mockCatalog(), refetch };
    const view = render(<MemoryRouter><ProjectsDisplayPage /></MemoryRouter>);
    try {
      expect(screen.getByRole('region', { name: /صفحة 1 من/ })).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'إيقاف التقليب التلقائي' }));
      act(() => vi.advanceTimersByTime(30_000));
      expect(screen.getByRole('region', { name: /صفحة 1 من/ })).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'الصفحة التالية' }));
      expect(screen.getByRole('region', { name: /صفحة 2 من/ })).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'استئناف التقليب التلقائي' }));
      act(() => vi.advanceTimersByTime(15_000));
      expect(screen.getByRole('region', { name: /صفحة 3 من/ })).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'تحديث البيانات' }));
      expect(refetch).toHaveBeenCalledOnce();
    } finally {
      view.unmount();
      vi.useRealTimers();
      vi.unstubAllGlobals();
    }
  });
});
