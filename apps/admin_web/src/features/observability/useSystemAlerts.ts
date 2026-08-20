import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

export interface SystemAlert {
  id: string;
  alert_key: string;
  severity: 'P0' | 'P1';
  source: string;
  title: string;
  detail: string | null;
  metric_value: number | null;
  threshold: number | null;
  status: 'open' | 'acknowledged' | 'resolved';
  first_seen_at: string;
  last_seen_at: string;
  occurrences: number;
  acknowledged_by: string | null;
  acknowledged_at: string | null;
  resolved_at: string | null;
  context: Record<string, unknown>;
}

/**
 * يقرأ التنبيهات المفتوحة من جدول system_alerts.
 * RLS يسمح لـ full_access / system.release.read بقراءتها.
 */
export function useSystemAlerts() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['system-alerts'],
    enabled: !auth.isMock,
    queryFn: async (): Promise<SystemAlert[]> => {
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('system_alerts')
        .select('*')
        .order('severity', { ascending: true })
        .order('last_seen_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as SystemAlert[];
    },
    refetchInterval: 30_000,
    staleTime: 20_000,
    retry: 1,
  });
}

/**
 * يحدّث حالة تنبيه (تأكيد/حل).
 */
export function useUpdateAlertStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ alertId, status }: { alertId: string; status: 'acknowledged' | 'resolved' }) => {
      const supabase = await getSupabase();
      const updates: Record<string, unknown> = { status };
      if (status === 'acknowledged') updates.acknowledged_at = new Date().toISOString();
      if (status === 'resolved') updates.resolved_at = new Date().toISOString();
      const { error } = await supabase.from('system_alerts').update(updates).eq('id', alertId);
      if (error) throw error;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['system-alerts'] });
      void queryClient.invalidateQueries({ queryKey: ['system-health'] });
    },
  });
}
