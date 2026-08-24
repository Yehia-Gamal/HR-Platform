import { useMutation, useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';

export interface ActiveBroadcastAlert {
  id: string;
  message: string;
  createdAt: string;
  expiresAt: string;
}

/** التنبيه الشامل النشط (إن وُجد) — يُستعلم دوريًا كل 20 ثانية. */
export function useActiveBroadcastAlert(enabled = true) {
  return useQuery({
    queryKey: ['broadcast-alert'],
    queryFn: async (): Promise<ActiveBroadcastAlert | null> => {
      const data = await rpc<ActiveBroadcastAlert | null>('get_active_broadcast_alert');
      return data ?? null;
    },
    refetchInterval: 20_000,
    staleTime: 10_000,
    enabled,
    retry: false,
  });
}

/** إرسال تنبيه شامل — يتطلب صلاحية alerts.broadcast.send من الخادم. */
export function useSendBroadcastAlert() {
  return useMutation({
    mutationFn: async (message: string): Promise<string> => {
      const data = await rpc<{ id?: string }>('send_broadcast_alert', { p_message: message });
      return data?.id ?? 'sent';
    },
  });
}
