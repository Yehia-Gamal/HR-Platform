import {
  dailyReportFeedItemSchema,
  toggleLikeResultSchema,
  type DailyReportFeedItem,
  type ToggleLikeResult,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

const FEED_KEY = 'daily-reports-feed';

export function useDailyReportsFeed(limit = 50) {
  const auth = useAuth();
  return useQuery({
    queryKey: [FEED_KEY, auth.isMock, limit],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<DailyReportFeedItem[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockDailyReportFeed;
      const data = await rpc('get_public_daily_reports_feed', { p_limit: limit });
      return dailyReportFeedItemSchema.array().parse(data ?? []);
    },
  });
}

export function useToggleDailyReportLike() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (reportId: string): Promise<ToggleLikeResult> => {
      if (auth.isMock) return { liked: true, count: 1 };
      return rpc('toggle_daily_report_like', { p_report_id: reportId }, toggleLikeResultSchema);
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [FEED_KEY] }),
  });
}

export function useAddDailyReportComment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { reportId: string; comment: string }): Promise<string> => {
      if (auth.isMock) return '00000000-0000-4000-8000-000000000000';
      return rpc('add_daily_report_comment', { p_report_id: input.reportId, p_comment: input.comment });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [FEED_KEY] }),
  });
}

export function useDeleteDailyReportComment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (commentId: string): Promise<void> => {
      if (auth.isMock) return;
      await rpc('delete_daily_report_comment', { p_comment_id: commentId });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [FEED_KEY] }),
  });
}

export function useSubmitDailyReport() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      reportDate: string;
      achievements: string;
      blockers?: string;
      tomorrowPlan?: string;
    }): Promise<string> => {
      if (auth.isMock) return '00000000-0000-4000-8000-000000000000';
      return rpc('upsert_my_daily_report', {
        p_report_date: input.reportDate,
        p_achievements: input.achievements,
        p_blockers: input.blockers ?? null,
        p_tomorrow_plan: input.tomorrowPlan ?? null,
      });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [FEED_KEY] }),
  });
}
