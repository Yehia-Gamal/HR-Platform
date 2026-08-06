import { notificationItemSchema, MOBILE_ONLY_ENTITY_TYPES, type NotificationItem } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { getSupabase } from '../../core/supabase';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

/**
 * اشتراك Realtime يُبطل كاش الإشعارات فور وصول إشعار جديد.
 * يعتمد على Supabase Realtime + RLS — يستقبل فقط إشعارات المستخدم الحالي.
 *
 * يُدار على مستوى الوحدة بعدّاد مرجعي: لوحة الإدارة (WorkspaceShell) وصفحة
 * الإشعارات يستدعيان هذا الهوك معاً، وكلاهما يطلب نفس قناة
 * 'notifications-realtime' — وRealtimeClient يدمج القنوات بنفس الاسم، لذا
 * استدعاء ثانٍ لـ .on() بعد .subscribe() يرمي خطأ. العدّاد يضمن اشتراكاً
 * واحداً فعلياً يُشترك عند أول مستهلك ويُغلق عند آخر خروج.
 */
let realtimeSubscription: { unsub: () => Promise<unknown> } | null = null;
let realtimeSubscriberCount = 0;

function useNotificationsRealtime() {
  const auth = useAuth();
  const queryClient = useQueryClient();

  useEffect(() => {
    if (auth.status !== 'authenticated' || auth.isMock) return;
    let cancelled = false;
    let joinedThisMount = false;

    const join = async () => {
      const supabase = await getSupabase();
      if (cancelled) return;

      if (!realtimeSubscription) {
        const channel = supabase
          .channel('notifications-realtime')
          .on(
            'postgres_changes',
            {
              event: 'INSERT',
              schema: 'public',
              table: 'notifications',
            },
            () => {
              void queryClient.invalidateQueries({ queryKey: ['my-notifications'] });
            },
          )
          .subscribe();
        realtimeSubscription = { unsub: () => channel.unsubscribe() };
      }
      realtimeSubscriberCount += 1;
      joinedThisMount = true;
    };

    void join();

    return () => {
      cancelled = true;
      if (joinedThisMount && realtimeSubscription) {
        realtimeSubscriberCount = Math.max(0, realtimeSubscriberCount - 1);
        if (realtimeSubscriberCount === 0) {
          const { unsub } = realtimeSubscription;
          realtimeSubscription = null;
          void unsub();
        }
      }
    };
  }, [auth.status, auth.isMock, queryClient]);
}

export function useNotifications() {
  const auth = useAuth();
  // اشتراك Realtime لتحديث الإشعارات فوراً بدون polling
  useNotificationsRealtime();
  return useQuery({
    queryKey: ['my-notifications', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<NotificationItem[]> => {
      if (auth.isMock) return notificationItemSchema.array().parse((await loadDomainMocks()).mockNotifications);
      const data = await rpc('get_my_notifications', { p_limit: 100 });
      const all = notificationItemSchema.array().parse(data ?? []);
      // فلترة: لوحة الإدارة لا تعرض إشعارات الموبايل الشخصية (تذكير حضور، طلب موقع).
      return all.filter((n) => !MOBILE_ONLY_ENTITY_TYPES.includes(n.entityType as (typeof MOBILE_ONLY_ENTITY_TYPES)[number]));
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
    meta: { silentError: true },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['my-notifications'] }),
  });
}
