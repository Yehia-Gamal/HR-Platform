import { notificationItemSchema, MOBILE_ONLY_ENTITY_TYPES, type NotificationItem } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import { getSupabase } from '../../core/supabase';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

/**
 * اشتراك Realtime يُبطل كاش الإشعارات فور وصول إشعار جديد.
 * يعتمد على Supabase Realtime + RLS — يستقبل فقط إشعارات المستخدم الحالي.
 */
function useNotificationsRealtime() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const channelRef = useRef<ReturnType<Awaited<ReturnType<typeof getSupabase>>['channel']> | null>(null);

  useEffect(() => {
    if (auth.status !== 'authenticated' || auth.isMock) return;
    let cancelled = false;

    (async () => {
      const supabase = await getSupabase();
      if (cancelled) return;
      channelRef.current = supabase
        .channel('notifications-realtime')
        .on('postgres_changes', {
          event: 'INSERT',
          schema: 'public',
          table: 'notifications',
        }, () => {
          void queryClient.invalidateQueries({ queryKey: ['my-notifications'] });
        })
        .subscribe();
    })();

    return () => {
      cancelled = true;
      if (channelRef.current) {
        void channelRef.current.unsubscribe();
        channelRef.current = null;
      }
    };
  }, [auth.status, auth.isMock, queryClient]);
}

export function useNotifications() {
  const auth = useAuth();
  // اشتراك Realtime لتحديث الإشعارات فوراً بدون polling
  useNotificationsRealtime();
  return useQuery({
    queryKey: ['my-notifications', auth.isMock], enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<NotificationItem[]> => {
      if (auth.isMock) return notificationItemSchema.array().parse((await loadDomainMocks()).mockNotifications);
      const data = await rpc('get_my_notifications', { p_limit: 100 });
      const all = notificationItemSchema.array().parse(data ?? []);
      // فلترة: لوحة الإدارة لا تعرض إشعارات الموبايل الشخصية (تذكير حضور، طلب موقع).
      return all.filter((n) => !MOBILE_ONLY_ENTITY_TYPES.includes(n.entityType as typeof MOBILE_ONLY_ENTITY_TYPES[number]));
    },
  });
}

export function useMarkNotificationsRead() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (ids?: string[]) => {
      if (auth.isMock) return ids?.length ?? (await loadDomainMocks()).mockNotifications.filter((x) => !x.isRead).length;
      const data = await rpc('mark_my_notifications_read', { p_ids: ids ?? null });
      return Number(data ?? 0);
    },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['my-notifications'] }),
  });
}
