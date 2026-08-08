import { z } from 'zod';

const uuid = z.string().uuid();

export const knowledgeArticleSchema = z.object({
  id: uuid,
  title: z.string(),
  category: z.string().nullable(),
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
