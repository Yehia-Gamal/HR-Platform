import { z } from 'zod';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const systemHealthSchema = z.record(z.string(), z.unknown()).nullable();

/**
 * لقطة صحة النظام من get_system_health() RPC.
 * تعيد JSON موحّد: { cron, integration_queue, notifications, errors, security, open_alerts, generated_at }
 * تجدّد كل 30 ثانية.
 */
export function useSystemHealth() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['system-health'],
    enabled: auth.status === 'authenticated' && !auth.isMock,
    queryFn: () => rpc('get_system_health', undefined, systemHealthSchema),
    refetchInterval: 30_000,
    staleTime: 20_000,
    retry: 1,
  });
}
