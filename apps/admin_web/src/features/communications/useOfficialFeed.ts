import { officialFeedItemSchema, type OfficialFeedItem } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useOfficialFeed() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['official-feed', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<OfficialFeedItem[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockOfficialFeed;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_official_feed_admin', { p_limit: 100 });
      if (error) throw error;
      return officialFeedItemSchema.array().parse(data ?? []);
    },
  });
}

export function usePublishAnnouncement() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { title: string; body: string; category: string; priority: string; requiresAcknowledgement: boolean; bannerUrl?: string | null }) => {
      if (auth.isMock) return input;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('publish_official_announcement', {
        p_title: input.title,
        p_body: input.body,
        p_category: input.category,
        p_priority: input.priority,
        p_requires_acknowledgement: input.requiresAcknowledgement,
        p_banner_url: input.bannerUrl ?? null,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['official-feed'] }),
  });
}

export function useCreateDecisionDraft() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { title: string; body: string; category: string; requiresAcknowledgement: boolean; expectedOutcome?: string; successMetric?: string }) => {
      if (auth.isMock) return input;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('create_decision_draft', {
        p_title: input.title,
        p_body: input.body,
        p_category: input.category,
        p_effective_date: null,
        p_requires_read_receipt: input.requiresAcknowledgement,
        p_expected_outcome: input.expectedOutcome || null,
        p_success_metric: input.successMetric || null,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['official-feed'] }),
  });
}

export function useTransitionDecision() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { decisionId: string; action: 'submit_review' | 'approve' | 'publish' | 'archive' | 'revoke'; reason?: string }) => {
      if (auth.isMock) return input;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('transition_decision', {
        p_decision_id: input.decisionId,
        p_action: input.action,
        p_reason: input.reason || null,
        p_scheduled_for: null,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['official-feed'] }),
  });
}
