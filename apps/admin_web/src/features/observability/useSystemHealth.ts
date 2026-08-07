import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';

/**
 * لقطة صحة النظام من get_system_health() RPC.
 * تعيد JSON موحّد: { cron, integration_queue, notifications, errors, security, open_alerts, generated_at }
 * تجدّد كل 30 ثانية.
 */
export function useSystemHealth() {
  return useQuery({
    queryKey: ['system-health'],
    queryFn: () => rpc<Record<string, unknown>>('get_system_health'),
    refetchInterval: 30_000,
    staleTime: 20_000,
    retry: 1,
  });
}
