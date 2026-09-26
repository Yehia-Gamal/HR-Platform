// Service Worker للإشعارات (Web Push)
// مسجل من main.tsx — يتعامل مع push events ويعرض notification

const CACHE_NAME = 'ahla-push-v1';

// تحويل base64url إلى Uint8Array لتطبيق VAPID
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  if (!event.data) return;

  const data = event.data.json();
  const {
    title = 'أحلى شباب',
    body = 'إشعار جديد',
    icon = '/icon-192.png',
    badge = '/icon-192.png',
    tag = 'default',
    data: payload = {},
    actions = [],
    requireInteraction = false,
  } = data;

  const options = {
    body,
    icon,
    badge,
    tag,
    data: payload,
    actions,
    requireInteraction,
    dir: 'rtl',
    lang: 'ar',
    vibrate: [200, 100, 200],
    timestamp: Date.now(),
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const { action } = event;
  const data = event.notification.data || {};
  // الوجهة يحسبها التطبيق من الإشعار نفسه (/notification/{id}) بنفس منطق صفحة
  // الإشعارات: كان actionUrl الخام فارغاً في إشعارات الطلبات أو مساراً للموبايل
  // (/attendance) أو ahlashabab:// — فيهبط المستخدم على الرئيسية لا على الحدث.
  const targetUrl = data.notificationId ? '/notification/' + encodeURIComponent(data.notificationId) : '/';

  // إذا كان هناك action محدد، قد نريد توجيه مختلف
  if (action === 'dismiss') return;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      // إذا التطبيق مفتوح، ركّز عليه
      for (const client of clients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.postMessage({ type: 'NOTIFICATION_CLICK', targetUrl, action });
          return client.focus();
        }
      }
      // خلاف ذلك افتح نافذة جديدة
      return self.clients.openWindow(targetUrl);
    })
  );
});

// معالجة رسائل من العميل (للتركيز عند النقر على الإشعار)
self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});