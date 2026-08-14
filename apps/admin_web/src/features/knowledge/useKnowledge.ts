import { knowledgeCatalogSchema, type KnowledgeCategory } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

const QUERY_KEY = 'knowledge-catalog';

export interface KnowledgeCatalogFilters {
  search: string;
  categoryId: string | null;
  status: 'all' | 'published' | 'draft';
}

/**
 * كتالوج المعرفة عبر RPC get_knowledge_catalog — بحث server-side (pg_trgm)
 * مع فلترة تصنيف/حالة، ويرجع المقالات + التصنيفات + العدّادات + صلاحية الإدارة.
 */
export function useKnowledgeCatalog(filters: KnowledgeCatalogFilters) {
  const auth = useAuth();
  return useQuery({
    queryKey: [QUERY_KEY, filters, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => {
      if (auth.isMock) {
        return {
          articles: [],
          categories: [] as KnowledgeCategory[],
          publishedCount: 0,
          draftCount: 0,
          manage: false,
          lastUpdatedAt: new Date().toISOString(),
        };
      }
      const data = await rpc('get_knowledge_catalog', {
        p_query: filters.search.trim() || null,
        p_category_id: filters.categoryId,
        p_status: filters.status,
        p_limit: 200,
        p_offset: 0,
      });
      return knowledgeCatalogSchema.parse(data);
    },
    refetchOnWindowFocus: false,
  });
}

export function useUpsertKnowledgeArticle() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      id?: string | null;
      title: string;
      category?: string | null;
      category_id?: string | null;
      body?: string | null;
      is_published: boolean;
    }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      if (input.id) {
        const { error } = await supabase
          .from('knowledge_articles')
          .update({
            title: input.title.trim(),
            category: input.category?.trim() || null,
            category_id: input.category_id || null,
            body: input.body?.trim() || null,
            is_published: input.is_published,
            updated_at: new Date().toISOString(),
          })
          .eq('id', input.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('knowledge_articles').insert({
          title: input.title.trim(),
          category: input.category?.trim() || null,
          category_id: input.category_id || null,
          body: input.body?.trim() || null,
          is_published: input.is_published,
        });
        if (error) throw error;
      }
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [QUERY_KEY] }),
  });
}

export function useDeleteKnowledgeArticle() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.from('knowledge_articles').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [QUERY_KEY] }),
  });
}

/** إنشاء/تعديل تصنيف — knowledge.manage أو full access فقط (يحرسه الـ RPC). */
export function useUpsertKnowledgeCategory() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      id?: string | null;
      slug: string;
      name: string;
      description?: string | null;
      is_active?: boolean;
    }): Promise<{ id: string }> => {
      if (auth.isMock) return { id: 'mock-category-id' };
      const data = await rpc<{ id: string }>('upsert_knowledge_category', {
        p_id: input.id || null,
        p_slug: input.slug,
        p_name: input.name,
        p_description: input.description || null,
        p_is_active: input.is_active ?? true,
      });
      return data;
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [QUERY_KEY] }),
  });
}

/** حذف تصنيف — knowledge.manage أو full access فقط. */
export function useDeleteKnowledgeCategory() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      if (auth.isMock) return;
      await rpc('delete_knowledge_category', { p_id: id });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [QUERY_KEY] }),
  });
}
