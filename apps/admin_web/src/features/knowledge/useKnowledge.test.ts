import { describe, it, expect } from 'vitest';
import { knowledgeArticleListSchema } from '@ahla/shared-contracts';
import type { KnowledgeArticle } from '@ahla/shared-contracts';

// إعادة منطق الفلترة من KnowledgePage.tsx (دالة خالصة للاختبار)
const filterArticles = (articles: KnowledgeArticle[], search: string, statusFilter: string) => {
  const q = search.trim().toLowerCase();
  return articles.filter((a) => {
    const matchSearch = !q || a.title.toLowerCase().includes(q) || (a.category ?? '').toLowerCase().includes(q);
    const matchStatus = statusFilter === 'all' || (statusFilter === 'published' && a.is_published) || (statusFilter === 'draft' && !a.is_published);
    return matchSearch && matchStatus;
  });
};

function makeArticle(overrides: Partial<KnowledgeArticle> = {}): KnowledgeArticle {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    title: 'سياسة الإجازات',
    category: 'سياسات',
    category_id: null,
    category_name: null,
    body: 'نص المقال',
    is_published: true,
    author_employee_id: null,
    created_at: '2026-01-01T10:00:00.000Z',
    updated_at: null,
    created_by: null,
    ...overrides,
  } as KnowledgeArticle;
}

describe('useKnowledge — article list schema & filter logic', () => {
  describe('knowledgeArticleListSchema', () => {
    it('parses a valid list', () => {
      const list = [makeArticle(), makeArticle({ id: '22222222-2222-4222-8222-222222222222', title: 'دليل الحضور', is_published: false })];
      const parsed = knowledgeArticleListSchema.parse(list);
      expect(parsed).toHaveLength(2);
    });

    it('parses an empty list', () => {
      expect(knowledgeArticleListSchema.parse([])).toEqual([]);
    });

    it('accepts null category/body/author/updated_at and category relation', () => {
      const parsed = knowledgeArticleListSchema.parse([
        makeArticle({ category: null, body: null, updated_at: null, author_employee_id: null, created_by: null, category_id: null, category_name: null }),
      ]);
      expect(parsed[0].category).toBeNull();
      expect(parsed[0].body).toBeNull();
      expect(parsed[0].updated_at).toBeNull();
      expect(parsed[0].category_id).toBeNull();
    });

    it('requires a valid uuid id', () => {
      expect(() => knowledgeArticleListSchema.parse([{ ...makeArticle(), id: 'not-a-uuid' }])).toThrow();
    });

    it('requires a valid uuid created_by when present', () => {
      expect(() => knowledgeArticleListSchema.parse([{ ...makeArticle(), created_by: 'not-a-uuid' }])).toThrow();
    });
  });

  describe('knowledge article filter logic', () => {
    const articles = [
      makeArticle(),
      makeArticle({ id: '22222222-2222-4222-8222-222222222222', title: 'دليل الحضور', category: 'إجراءات', is_published: false }),
      makeArticle({ id: '33333333-3333-4333-8333-333333333333', title: 'قواعد اللباس', category: 'سياسات', is_published: true }),
    ];

    it('returns all when no search and status=all', () => {
      expect(filterArticles(articles, '', 'all')).toHaveLength(3);
    });

    it('filters by title (case-insensitive)', () => {
      const result = filterArticles(articles, 'دليل', 'all');
      expect(result).toHaveLength(1);
      expect(result[0].title).toBe('دليل الحضور');
    });

    it('filters by category', () => {
      const result = filterArticles(articles, 'إجراءات', 'all');
      expect(result).toHaveLength(1);
    });

    it('filters by published status', () => {
      expect(filterArticles(articles, '', 'published')).toHaveLength(2);
      expect(filterArticles(articles, '', 'draft')).toHaveLength(1);
    });

    it('combines search and status filter', () => {
      expect(filterArticles(articles, 'سياسة', 'published')).toHaveLength(1);
      expect(filterArticles(articles, 'سياسة', 'draft')).toHaveLength(0);
    });

    it('returns empty for no match', () => {
      expect(filterArticles(articles, 'غير موجود', 'all')).toHaveLength(0);
    });

    it('handles empty input', () => {
      expect(filterArticles([], '', 'all')).toHaveLength(0);
    });
  });
});
