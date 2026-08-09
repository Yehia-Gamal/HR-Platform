import { z } from 'zod';

const uuid = z.string().uuid();

export const knowledgeArticleSchema = z.object({
  id: uuid,
  title: z.string(),
  category: z.string().nullable(),
  category_id: uuid.nullable(),
  category_name: z.string().nullable(),
  body: z.string().nullable(),
  is_published: z.boolean(),
  author_employee_id: uuid.nullable(),
  created_at: z.string(),
  updated_at: z.string().nullable(),
  created_by: uuid.nullable(),
});
export type KnowledgeArticle = z.infer<typeof knowledgeArticleSchema>;

export const knowledgeArticleListSchema = z.array(knowledgeArticleSchema);
export type KnowledgeArticleList = z.infer<typeof knowledgeArticleListSchema>;

export const knowledgeCategorySchema = z.object({
  id: uuid,
  slug: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  is_active: z.boolean(),
  created_at: z.string(),
});
export type KnowledgeCategory = z.infer<typeof knowledgeCategorySchema>;

export const knowledgeCategoryListSchema = z.array(knowledgeCategorySchema);
export type KnowledgeCategoryList = z.infer<typeof knowledgeCategoryListSchema>;

export const knowledgeCatalogSchema = z.object({
  articles: knowledgeArticleListSchema,
  categories: knowledgeCategoryListSchema,
  publishedCount: z.number(),
  draftCount: z.number(),
  manage: z.boolean(),
  lastUpdatedAt: z.string(),
});
export type KnowledgeCatalog = z.infer<typeof knowledgeCatalogSchema>;
