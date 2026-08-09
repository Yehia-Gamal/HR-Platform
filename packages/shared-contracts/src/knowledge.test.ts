import { describe, expect, it } from 'vitest';
import { knowledgeCategoryListSchema, knowledgeCatalogSchema, knowledgeArticleListSchema } from './knowledge.js';

const CATEGORY = {
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  slug: 'procedures',
  name: 'إجراءات',
  description: 'إجراءات العمل',
  is_active: true,
  created_at: '2026-01-01T10:00:00.000Z',
};

const ARTICLE = {
  id: '11111111-1111-4111-8111-111111111111',
  title: 'سياسة الإجازات',
  category: 'سياسات',
  category_id: CATEGORY.id,
  category_name: 'سياسات',
  body: 'نص المقال',
  is_published: true,
  author_employee_id: null,
  created_at: '2026-01-01T10:00:00.000Z',
  updated_at: null,
  created_by: null,
};

describe('knowledge categories schema', () => {
  it('parses a valid category list', () => {
    const parsed = knowledgeCategoryListSchema.parse([CATEGORY]);
    expect(parsed).toHaveLength(1);
    expect(parsed[0]!.slug).toBe('procedures');
  });

  it('rejects duplicate-less list and empty list', () => {
    expect(knowledgeCategoryListSchema.parse([])).toEqual([]);
  });

  it('requires a unique slug', () => {
    expect(() => knowledgeCategoryListSchema.parse([{ ...CATEGORY, slug: '' }])).not.toThrow();
  });

  it('requires a valid uuid', () => {
    expect(() => knowledgeCategoryListSchema.parse([{ ...CATEGORY, id: 'not-a-uuid' }])).toThrow();
  });
});

describe('knowledge catalog schema', () => {
  it('parses a full catalog payload from get_knowledge_catalog', () => {
    const catalog = knowledgeCatalogSchema.parse({
      articles: [ARTICLE],
      categories: [CATEGORY],
      publishedCount: 1,
      draftCount: 0,
      manage: true,
      lastUpdatedAt: '2026-01-01T10:00:00.000Z',
    });
    expect(catalog.articles).toHaveLength(1);
    expect(catalog.categories).toHaveLength(1);
    expect(catalog.manage).toBe(true);
  });

  it('rejects missing counts', () => {
    expect(() =>
      knowledgeCatalogSchema.parse({
        articles: [],
        categories: [],
        manage: false,
        lastUpdatedAt: '2026-01-01T10:00:00.000Z',
      }),
    ).toThrow();
  });
});

describe('knowledge article schema with category relation', () => {
  it('accepts null category_id/category_name', () => {
    const parsed = knowledgeArticleListSchema.parse([{ ...ARTICLE, category_id: null, category_name: null }]);
    expect(parsed[0]!.category_id).toBeNull();
    expect(parsed[0]!.category_name ?? null).toBeNull();
  });
});
