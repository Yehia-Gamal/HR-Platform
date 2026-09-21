import { cronHealthSummarySchema, cronJobHealthSchema, type CronHealthSummary, type CronJobHealth, type ObservabilityEvent } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { z } from 'zod';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

export type { CronHealthSummary, CronJobHealth, ObservabilityEvent };

const cronJobHealthArraySchema = z.array(cronJobHealthSchema);

/**
 * ملخص صحة pg_cron من get_cron_health_summary() RPC (متاح لـ authenticated
 * بعد 0347 مع فحص observability.read). تُنشَّط فقط إذا كان المستخدم يملك
 * observability.read / admin.observability / full access.
 */
export function useCronHealthSummary(enabled = true) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['cron-health-summary'],
    enabled: enabled && auth.status === 'authenticated' && !auth.isMock,
    queryFn: () => rpc('get_cron_health_summary', undefined, cronHealthSummarySchema),
    refetchInterval: 60_000,
    staleTime: 45_000,
    retry: 1,
  });
}

/**
 * قائمة تفصيلية لصحة مهام pg_cron من get_cron_job_health().
 */
export function useCronJobHealth(enabled = true) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['cron-job-health'],
    enabled: enabled && auth.status === 'authenticated' && !auth.isMock,
    queryFn: () => rpc('get_cron_job_health', undefined, cronJobHealthArraySchema),
    refetchInterval: 60_000,
    staleTime: 45_000,
    retry: 1,
  });
}

/**
 * آخر أحداث observability_events (سجل مركزي تكتبه Edge Functions/cron).
 * RLS يسمح بقراءتها لـ full access / observability.read / admin.observability.
 */
export function useObservabilityEvents(enabled = true, limit = 50) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['observability-events', limit],
    enabled: enabled && auth.status === 'authenticated' && !auth.isMock,
    queryFn: async (): Promise<ObservabilityEvent[]> => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.from('observability_events').select('*').order('created_at', { ascending: false }).limit(limit);
      if (error) throw error;
      return (data ?? []) as ObservabilityEvent[];
    },
    refetchInterval: 60_000,
    staleTime: 45_000,
    retry: 1,
  });
}
