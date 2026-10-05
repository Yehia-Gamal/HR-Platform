import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
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
    expect(screen.getByText('تحتاج تدخل')).toBeInTheDocument();
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
});
