import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

export interface CronJobHealth {
  jobid: number;
  jobname: string;
  schedule: string;
  active: boolean;
  last_status: string | null;
  last_message: string | null;
  last_start: string | null;
  last_end: string | null;
  duration_seconds: number | null;
  failures_24h: number;
  health_status: 'disabled' | 'never_run' | 'failing' | 'unstable' | 'healthy';
}

export interface CronHealthSummary {
  total_jobs: number;
  active: number;
  failing: number;
  unstable: number;
  healthy: number;
  never_run: number;
  disabled: number;
  checked_at: string;
  failures_24h_total: number;
}

/**
 * ملخص صحة pg_cron من get_cron_health_summary() RPC (متاح لـ authenticated
 * بعد 0347 مع فحص observability.read). تُنشَّط فقط إذا كان المستخدم يملك
 * observability.read / admin.observability / full access.
 */
export function useCronHealthSummary(enabled = true) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['cron-health-summary'],
    enabled: enabled && !auth.isMock,
    queryFn: () => rpc<CronHealthSummary>('get_cron_health_summary'),
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
    enabled: enabled && !auth.isMock,
    queryFn: () => rpc<CronJobHealth[]>('get_cron_job_health'),
    refetchInterval: 60_000,
    staleTime: 45_000,
    retry: 1,
  });
}

export interface ObservabilityEvent {
  id: string;
  created_at: string;
  level: 'debug' | 'info' | 'warning' | 'error' | 'critical';
  source: string;
  event_type: string;
  request_id: string | null;
  message: string;
  error_name: string | null;
  duration_ms: number | null;
  metadata: Record<string, unknown>;
}

/**
 * آخر أحداث observability_events (سجل مركزي تكتبه Edge Functions/cron).
 * RLS يسمح بقراءتها لـ full access / observability.read / admin.observability.
 */
export function useObservabilityEvents(enabled = true, limit = 50) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['observability-events', limit],
    enabled: enabled && !auth.isMock,
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
