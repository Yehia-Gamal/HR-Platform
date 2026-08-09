import { describe, it, expect } from 'vitest';
import { knowledgeArticleListSchema } from '@ahla/shared-contracts';
import type { KnowledgeArticle } from '@ahla/shared-contracts';

// Ø¥Ø¹Ø§Ø¯Ø© Ù…Ù†Ø·Ù‚ Ø§Ù„ÙÙ„ØªØ±Ø© Ù…Ù† KnowledgePage.tsx (Ø¯Ø§Ù„Ø© Ø®Ø§Ù„ØµØ© Ù„Ù„Ø§Ø®ØªØ¨Ø§Ø±)
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
    title: 'Ø³ÙŠØ§Ø³Ø© Ø§Ù„Ø¥Ø¬Ø§Ø²Ø§Øª',
    category: 'Ø³ÙŠØ§Ø³Ø§Øª',
    body: 'Ù†Øµ Ø§Ù„Ù…Ù‚Ø§Ù„',
    is_published: true,
    author_employee_id: null,
    created_at: '2026-01-01T10:00:00.000Z',
    updated_at: null,
    created_by: null,
    ...overrides,
  };
}

describe('useKnowledge â€” article list schema & filter logic', () => {
  describe('knowledgeArticleListSchema', () => {
    it('parses a valid list', () => {
      const list = [makeArticle(), makeArticle({ id: '22222222-2222-4222-8222-222222222222', title: 'Ø¯Ù„ÙŠÙ„ Ø§Ù„Ø­Ø¶ÙˆØ±', is_published: false })];
      const parsed = knowledgeArticleListSchema.parse(list);
      expect(parsed).toHaveLength(2);
    });

    it('parses an empty list', () => {
      expect(knowledgeArticleListSchema.parse([])).toEqual([]);
    });

    it('accepts null category/body/author/updated_at', () => {
      const parsed = knowledgeArticleListSchema.parse([
        makeArticle({ category: null, body: null, updated_at: null, author_employee_id: null, created_by: null }),
      ]);
      expect(parsed[0].category).toBeNull();
      expect(parsed[0].body).toBeNull();
      expect(parsed[0].updated_at).toBeNull();
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
      makeArticle({ id: '22222222-2222-4222-8222-222222222222', title: 'Ø¯Ù„ÙŠÙ„ Ø§Ù„Ø­Ø¶ÙˆØ±', category: 'Ø¥Ø¬Ø±Ø§Ø¡Ø§Øª', is_published: false }),
      makeArticle({ id: '33333333-3333-4333-8333-333333333333', title: 'Ù‚ÙˆØ§Ø¹Ø¯ Ø§Ù„Ù„Ø¨Ø§Ø³', category: 'Ø³ÙŠØ§Ø³Ø§Øª', is_published: true }),
    ];

    it('returns all when no search and status=all', () => {
      expect(filterArticles(articles, '', 'all')).toHaveLength(3);
    });

    it('filters by title (case-insensitive)', () => {
      const result = filterArticles(articles, 'Ø¯Ù„ÙŠÙ„', 'all');
      expect(result).toHaveLength(1);
      expect(result[0].title).toBe('Ø¯Ù„ÙŠÙ„ Ø§Ù„Ø­Ø¶ÙˆØ±');
    });

    it('filters by category', () => {
      const result = filterArticles(articles, 'Ø¥Ø¬Ø±Ø§Ø¡Ø§Øª', 'all');
      expect(result).toHaveLength(1);
    });

    it('filters by published status', () => {
      expect(filterArticles(articles, '', 'published')).toHaveLength(2);
      expect(filterArticles(articles, '', 'draft')).toHaveLength(1);
    });

    it('combines search and status filter', () => {
      expect(filterArticles(articles, 'Ø³ÙŠØ§Ø³Ø©', 'published')).toHaveLength(1);
      expect(filterArticles(articles, 'Ø³ÙŠØ§Ø³Ø©', 'draft')).toHaveLength(0);
    });

    it('returns empty for no match', () => {
      expect(filterArticles(articles, 'ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯', 'all')).toHaveLength(0);
    });

    it('handles empty input', () => {
      expect(filterArticles([], '', 'all')).toHaveLength(0);
    });
  });
});
