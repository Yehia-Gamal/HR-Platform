import { notificationItemSchema, type NotificationItem } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useNotifications() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['my-notifications', auth.isMock], enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<NotificationItem[]> => {
      if (auth.isMock) return notificationItemSchema.array().parse((await loadDomainMocks()).mockNotifications);
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_my_notifications', { p_limit: 100 });
      if (error) throw error;
      return notificationItemSchema.array().parse(data ?? []);
    },
  });
}

export function useMarkNotificationsRead() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (ids?: string[]) => {
      if (auth.isMock) return ids?.length ?? (await loadDomainMocks()).mockNotifications.filter((x) => !x.isRead).length;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('mark_my_notifications_read', { p_ids: ids ?? null });
      if (error) throw error;
      return Number(data ?? 0);
    },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['my-notifications'] }),
  });
}
