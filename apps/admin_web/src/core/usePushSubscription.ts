import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '../features/auth/AuthProvider';
import { emitToast } from '../ui/Toast';

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY;

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

async function sendSubscriptionToBackend(subscription: PushSubscription, accessToken: string) {
  const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/push-subscribe`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(subscription.toJSON()),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Push subscribe failed: ${response.status} ${err}`);
  }
  return response.json();
}

async function deleteSubscriptionFromBackend(endpoint: string, accessToken: string) {
  const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/push-subscribe`, {
    method: 'DELETE',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ endpoint }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Push unsubscribe failed: ${response.status} ${err}`);
  }
}

export function usePushSubscription() {
  const { session } = useAuth();
  const [isSupported, setIsSupported] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission>('default');
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [subscription, setSubscription] = useState<PushSubscription | null>(null);

  useEffect(() => {
    const supported = 'serviceWorker' in navigator && 'PushManager' in window;
    setIsSupported(supported);
    if (supported) {
      setPermission(Notification.permission);
      // تحقق من اشتراك موجود
      navigator.serviceWorker.ready.then((reg) => {
        reg.pushManager.getSubscription().then((sub) => {
          if (sub) {
            setSubscription(sub);
            setIsSubscribed(true);
          }
        });
      });
    }
  }, []);

  const subscribe = useCallback(async () => {
    if (!isSupported || !VAPID_PUBLIC_KEY || !session?.access_token) {
      emitToast({ message: 'الإشعارات غير مدعومة أو مفتاح VAPID مفقود', tone: 'error' });
      return;
    }

    setIsLoading(true);
    try {
      const perm = await Notification.requestPermission();
      setPermission(perm);
      if (perm !== 'granted') {
        emitToast({ message: 'تم رفض إذن الإشعارات', tone: 'warning' });
        return;
      }

      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY) as BufferSource,
      });

      await sendSubscriptionToBackend(sub, session.access_token);
      setSubscription(sub);
      setIsSubscribed(true);
      emitToast({ message: 'تم تفعيل الإشعارات', tone: 'success' });
    } catch (err) {
      console.error('[Push] Subscribe error:', err);
      emitToast({ message: `فشل التفعيل: ${err instanceof Error ? err.message : 'خطأ غير معروف'}`, tone: 'error' });
    } finally {
      setIsLoading(false);
    }
  }, [isSupported, session?.access_token]);

  const unsubscribe = useCallback(async () => {
    if (!subscription || !session?.access_token) return;

    setIsLoading(true);
    try {
      await subscription.unsubscribe();
      await deleteSubscriptionFromBackend(subscription.endpoint, session.access_token);
      setSubscription(null);
      setIsSubscribed(false);
      emitToast({ message: 'تم إلغاء الإشعارات', tone: 'success' });
    } catch (err) {
      console.error('[Push] Unsubscribe error:', err);
      emitToast({ message: `فشل الإلغاء: ${err instanceof Error ? err.message : 'خطأ غير معروف'}`, tone: 'error' });
    } finally {
      setIsLoading(false);
    }
  }, [subscription, session?.access_token]);

  return {
    isSupported,
    permission,
    isSubscribed,
    isLoading,
    subscription,
    subscribe,
    unsubscribe,
  };
}
