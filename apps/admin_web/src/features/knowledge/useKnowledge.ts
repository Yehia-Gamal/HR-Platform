import { knowledgeArticleListSchema, type KnowledgeArticle } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

const QUERY_KEY = 'knowledge-articles';

export function useKnowledgeArticles() {
  const auth = useAuth();
  return useQuery({
    queryKey: [QUERY_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<KnowledgeArticle[]> => {
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('knowledge_articles')
        .select('id,title,category,body,is_published,author_employee_id,created_at,updated_at,created_by')
        .order('updated_at', { ascending: false, nullsFirst: false })
        .limit(200);
      if (error) throw error;
      return knowledgeArticleListSchema.parse(data ?? []);
    },
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
            body: input.body?.trim() || null,
            is_published: input.is_published,
            updated_at: new Date().toISOString(),
          })
          .eq('id', input.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('knowledge_articles')
          .insert({
            title: input.title.trim(),
            category: input.category?.trim() || null,
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
