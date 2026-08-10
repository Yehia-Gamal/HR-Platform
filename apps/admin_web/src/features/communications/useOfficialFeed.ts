import {
  announcementEngagementSchema,
  officialFeedItemSchema,
  type AnnouncementEngagement,
  type OfficialFeedItem,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useOfficialFeed() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['official-feed', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<OfficialFeedItem[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockOfficialFeed;
      const data = await rpc('get_official_feed_admin', { p_limit: 100 });
      return officialFeedItemSchema.array().parse(data ?? []);
    },
  });
}

export function usePublishAnnouncement() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      title: string;
      body: string;
      category: string;
      priority: string;
      requiresAcknowledgement: boolean;
      bannerUrl?: string | null;
      postType?: string;
      pollOptions?: string[];
      expiresAt?: string;
    }) => {
      if (auth.isMock) return input;
      const pollOpts = input.postType === 'poll' && input.pollOptions?.length ? input.pollOptions.filter((o) => o.trim()) : null;
      return rpc('publish_official_announcement', {
        p_title: input.title,
        p_body: input.body,
        p_category: input.category,
        p_priority: input.priority,
        p_requires_acknowledgement: input.requiresAcknowledgement,
        p_banner_url: input.bannerUrl ?? null,
        p_post_type: input.postType ?? 'standard',
        p_poll_options: pollOpts,
        p_expires_at: input.expiresAt || null,
      });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['official-feed'] }),
  });
}

export function useAnnouncementEngagement(announcementId?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['announcement-engagement', announcementId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(announcementId),
    queryFn: async (): Promise<AnnouncementEngagement> => {
      if (!announcementId) throw new Error('announcement id is required');
      if (auth.isMock) {
        return announcementEngagementSchema.parse({
          announcementId,
          targetCount: 54,
          viewerCount: 0,
          reactionCount: 0,
          acknowledgedCount: 0,
          viewers: [],
          reactions: [],
          acknowledgements: [],
        });
      }
      const data = await rpc('get_announcement_engagement', { p_announcement_id: announcementId });
      return announcementEngagementSchema.parse(data);
    },
  });
}

export function useCreateDecisionDraft() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      title: string;
      body: string;
      category: string;
      requiresAcknowledgement: boolean;
      expectedOutcome?: string;
      successMetric?: string;
    }) => {
      if (auth.isMock) return input;
      return rpc('create_decision_draft', {
        p_title: input.title,
        p_body: input.body,
        p_category: input.category,
        p_effective_date: null,
        p_requires_read_receipt: input.requiresAcknowledgement,
        p_expected_outcome: input.expectedOutcome || null,
        p_success_metric: input.successMetric || null,
      });
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
      return rpc('transition_decision', {
        p_decision_id: input.decisionId,
        p_action: input.action,
        p_reason: input.reason || null,
        p_scheduled_for: null,
      });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['official-feed'] }),
  });
}
