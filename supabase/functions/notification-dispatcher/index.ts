import { createClient } from '@supabase/supabase-js';
import { createLogger } from "../_shared/logger.ts";
import { corsHeaders } from '../_shared/cors.ts';
import { timingSafeEqual } from '../_shared/secret.ts';
import { createHandler } from "../_shared/withHandler.ts";
const log = createLogger({ functionName: "notification-dispatcher", version: "1.0.0" });

// notification-dispatcher: يستهلك طابور notification_jobs ويرسل الدفع.
// يدعم FCM v1 (Android + APNs عبر FCM) مع تجربة إشعار عاجل (شاشة كاملة/صوت/اهتزاز)
// للطلبات ذات الأولوية urgent + metadata.fullScreen. يبقى PUSH_PROVIDER_URL
// كاحتياط إن لم تُضبط أسرار FCM. يكتب سجل التسليم notification_delivery_log.

/** صف من notification_jobs مع العلاقة المرتبطة notifications(priority). */
interface JobRow {
  id: string;
  notification_id: string;
  recipient_user_id: string;
  channel: string;
  attempts: number;
  notifications: { priority: string } | Array<{ priority: string }> | null;
}

/** صف إشعار كامل يُجلب لبناء رسالة FCM. */
interface NotificationRow {
  id: string;
  title: string | null;
  body: string | null;
  action_url: string | null;
  priority: string | null;
  metadata: Record<string, unknown> | null;
  entity_id: string | null;
  entity_type: string | null;
}

function createAdminClient(url: string, key: string) {
  return createClient(url, key, { auth: { persistSession: false } });
}

type SupabaseAdminClient = ReturnType<typeof createAdminClient>;

Deno.serve(createHandler({ functionName: "notification-dispatcher", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return respond(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (!await timingSafeEqual(req.headers.get('x-cron-secret'), cronSecret)) return respond(req, { error: 'UNAUTHORIZED' }, 401);
  const url = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return respond(req, { error: 'SERVER_CONFIGURATION' }, 500);
  const supabase = createAdminClient(url, key);
  const worker = crypto.randomUUID(); const now = new Date().toISOString();

  // طلب العاجل أولًا: نرتّب حسب أولوية الإشعار المرتبط ثم وقت التوفر.
  const { data: jobs, error } = await supabase
    .from('notification_jobs')
    .select('id,notification_id,recipient_user_id,channel,attempts,notifications(priority)')
    .eq('status', 'queued').lte('available_at', now)
    .order('available_at', { ascending: true })
    .limit(50);
  if (error) return respond(req, { error: 'LOAD_FAILED' }, 500);

  // إعادة ترتيب: urgent قبل غيره (Supabase لا يرتّب على جدول مرتبط بسهولة).
  const ordered = ((jobs ?? []) as JobRow[]).slice().sort((a, b) => {
    const aNotification = Array.isArray(a.notifications) ? a.notifications[0] : a.notifications;
    const bNotification = Array.isArray(b.notifications) ? b.notifications[0] : b.notifications;
    const pa = aNotification?.priority === 'urgent' ? 0 : 1;
    const pb = bNotification?.priority === 'urgent' ? 0 : 1;
    return pa - pb;
  });

  let sent = 0; let failed = 0;
  let fcmToken: string | null = null; // access token مؤقت (يُجلب مرة واحدة)

  for (const job of ordered) {
    const { data: locked } = await supabase.from('notification_jobs')
      .update({ status: 'processing', locked_at: now, locked_by: worker, attempts: job.attempts + 1 })
      .eq('id', job.id).eq('status', 'queued').select('id').maybeSingle();
    if (!locked) continue;

    const { data: notification } = await supabase.from('notifications')
      .select('id,title,body,action_url,priority,metadata,entity_id,entity_type')
      .eq('id', job.notification_id).maybeSingle() as { data: NotificationRow | null };
    const { data: subscriptions } = await supabase.from('push_subscriptions')
      .select('id,fcm_token,endpoint,platform').eq('user_id', job.recipient_user_id).eq('is_active', true);

    // V25: قطع حلقة الرنين المتكرر — لا يُرسل دفع عاجل لطلب موقع لم يعد
    // pending (قُبل/رُفض/أُكمل) حتى لو أُعيدت جدولة الـ job أو فشل أول إرسال.
    if (job.channel === 'push' &&
        notification?.entity_type === 'live_location_request' &&
        notification.entity_id) {
      const { data: request } = await supabase.from('live_location_requests')
        .select('status,expires_at').eq('id', notification.entity_id).maybeSingle();
      const stillPending = !!request &&
        request.status === 'pending' &&
        (!request.expires_at || new Date(request.expires_at).getTime() > Date.now());
      if (!stillPending) {
        await supabase.from('notification_jobs').update({
          status: 'cancelled',
          last_error: 'request_no_longer_pending',
          locked_at: null,
          locked_by: null,
        }).eq('id', job.id);
        continue;
      }
    }

    try {
      if (job.channel === 'in_app') {
        await supabase.from('notification_jobs').update({ status: 'sent', sent_at: new Date().toISOString() }).eq('id', job.id);
        sent += 1; continue;
      }

      if (!(subscriptions?.length)) {
        await logDelivery(supabase, job, null, 'token_missing', null, 'NO_ACTIVE_PUSH_TOKEN');
        await supabase.from('notification_jobs').update({
          status: 'failed',
          last_error: 'token_missing',
          locked_at: null,
          locked_by: null,
        }).eq('id', job.id);
        failed += 1;
        continue;
      }

      const fcmTargets = (subscriptions ?? []).filter((s) => s.fcm_token);
      const projectId = Deno.env.get('FCM_PROJECT_ID');
      const saJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');

      if (projectId && saJson && fcmTargets.length) {
        // مسار FCM v1 المباشر.
        if (!fcmToken) fcmToken = await mintFcmAccessToken(saJson);
        let anyOk = false; let lastErr = '';
        for (const sub of fcmTargets) {
          const message = buildFcmMessage(sub.fcm_token!, notification);
          const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
            method: 'POST',
            signal: AbortSignal.timeout(15_000),
            headers: { 'Authorization': `Bearer ${fcmToken}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ message }),
          });
          const txt = await res.text();
          if (res.ok) {
            anyOk = true;
            let msgId: string | null = null;
            try { msgId = JSON.parse(txt)?.name ?? null; } catch { /* ignore */ }
            await logDelivery(supabase, job, sub.id, 'sent', msgId, null);
          } else {
            lastErr = `FCM_${res.status}:${txt.slice(0, 200)}`;
            await logDelivery(supabase, job, sub.id, 'failed', null, lastErr);
            // 404/410 = رمز غير صالح → عطّل الاشتراك.
            if (res.status === 404 || res.status === 410) {
              await supabase.from('push_subscriptions').update({ is_active: false }).eq('id', sub.id);
            }
          }
        }
        if (!anyOk) throw new Error(lastErr || 'FCM_ALL_FAILED');
        await supabase.from('notification_jobs').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }).eq('id', job.id);
        sent += 1; continue;
      }

      // Web Push (VAPID) — للمتصفحات.
      const webTargets = (subscriptions ?? []).filter((s) => s.platform === 'web' && s.endpoint);
      const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');
      if (vapidPrivateKey && webTargets.length) {
        let anyOk = false; let lastErr = '';
        for (const sub of webTargets) {
          const res = await sendWebPush(vapidPrivateKey, sub, notification);
          if (res.ok) {
            anyOk = true;
            await logDelivery(supabase, job, sub.id, 'sent', null, null);
          } else {
            lastErr = `WEB_PUSH_${res.status}:${await res.text().catch(() => '')}`;
            await logDelivery(supabase, job, sub.id, 'failed', null, lastErr);
            // 404/410 = اشتراك منتهي → عطّله.
            if (res.status === 404 || res.status === 410) {
              await supabase.from('push_subscriptions').update({ is_active: false }).eq('id', sub.id);
            }
          }
        }
        if (!anyOk) throw new Error(lastErr || 'WEB_PUSH_ALL_FAILED');
        await supabase.from('notification_jobs').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }).eq('id', job.id);
        sent += 1; continue;
      }

      // احتياط: مزوّد خارجي عام.
      const providerUrl = Deno.env.get('PUSH_PROVIDER_URL'); const providerToken = Deno.env.get('PUSH_PROVIDER_TOKEN');
      if (!providerUrl || !(subscriptions?.length)) throw new Error('NO_PUSH_PROVIDER_OR_DEVICE');
      const response = await fetch(providerUrl, {
        method: 'POST',
        signal: AbortSignal.timeout(15_000),
        headers: { 'content-type': 'application/json', ...(providerToken ? { authorization: `Bearer ${providerToken}` } : {}) },
        body: JSON.stringify({ subscriptions, notification }),
      });
      if (!response.ok) throw new Error(`PROVIDER_${response.status}`);
      await supabase.from('notification_jobs').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }).eq('id', job.id);
      sent += 1;
    } catch (err) {
      const attempts = job.attempts + 1; const terminal = attempts >= 5;
      await supabase.from('notification_jobs').update({
        status: terminal ? 'failed' : 'queued',
        available_at: new Date(Date.now() + Math.min(3600, 2 ** attempts * 60) * 1000).toISOString(),
        last_error: String(err), locked_at: null, locked_by: null,
      }).eq('id', job.id);
      failed += 1;
    }
  }
  return respond(req, { processed: ordered.length, sent, failed });
}));

// يبني رسالة FCM v1: تجربة عاجلة (شاشة كاملة/صوت/اهتزاز) عند urgent+fullScreen.
// إشعارات priority=high (الطلبات/القرارات/التصعيد) تحصل أيضًا على أولوية
// HIGH في Android لتسليم عاجل مع صوت عبر قناة الإشعار المحلي.
function buildFcmMessage(token: string, n: NotificationRow | null): Record<string, unknown> {
  const meta = (n?.metadata ?? {}) as Record<string, unknown>;
  const urgent = n?.priority === 'urgent' || meta.fullScreen === true;
  const high = urgent || n?.priority === 'high';
  const isLocationRequest = n?.entity_type === 'live_location_request';
  const deepLink = (meta.deepLink as string) ?? n?.action_url ?? '';
  const data: Record<string, string> = {
    kind: String(meta.kind ?? n?.entity_type ?? 'notification'),
    notificationId: String(n?.id ?? ''),
    entityId: String(meta.entityId ?? n?.entity_id ?? ''),
    deepLink: String(deepLink),
    requestId: String(meta.requestId ?? meta.entityId ?? n?.entity_id ?? ''),
    fullScreenIntent: (urgent && isLocationRequest) ? 'true' : 'false',
    title: String(n?.title ?? ''),
    body: String(n?.body ?? ''),
  };

  return {
    token,
    // Data-only is intentional: Android background/killed delivery must reach
    // the background isolate so it can create the full-screen notification.
    data,
    android: {
      priority: high ? 'HIGH' : 'NORMAL',
      ttl: high ? '300s' : '3600s',
    },
    apns: {
      headers: { 'apns-priority': high ? '10' : '5' },
      payload: {
        aps: {
          alert: { title: n?.title ?? '', body: n?.body ?? '' },
          sound: urgent ? { critical: 0, name: 'urgent.caf', volume: 1.0 } : 'default',
          'interruption-level': urgent ? 'time-sensitive' : (high ? 'active' : 'passive'),
          'content-available': 1,
        },
      },
    },
  };
}

async function logDelivery(
  supabase: SupabaseAdminClient, job: JobRow, subscriptionId: string | null,
  status: 'token_missing' | 'sent' | 'failed' | 'delivered', providerMessageId: string | null, errorDetail: string | null,
) {
  const nowIso = new Date().toISOString();
  await supabase.from('notification_delivery_log').insert({
    notification_id: job.notification_id,
    subscription_id: subscriptionId,
    recipient_user_id: job.recipient_user_id,
    channel: 'push',
    status,
    provider_message_id: providerMessageId,
    error_detail: errorDetail,
    attempts: job.attempts + 1,
    sent_at: status === 'sent' ? nowIso : null,
  });
}

// يصكّ access token لـ FCM v1 من JSON حساب الخدمة (OAuth2 JWT-bearer, RS256).
async function mintFcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const nowSec = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSec,
    exp: nowSec + 3600,
  };
  const enc = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const signingInput = `${enc(header)}.${enc(claim)}`;
  const keyData = pemToArrayBuffer(sa.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', keyData, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput));
  const assertion = `${signingInput}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    signal: AbortSignal.timeout(10_000),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
  });
  if (!res.ok) throw new Error(`FCM_TOKEN_${res.status}`);
  const tok = await res.json();
  return tok.access_token as string;
}

function b64url(bytes: Uint8Array): string {
  let bin = ''; for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN [^-]+-----/, '').replace(/-----END [^-]+-----/, '').replace(/\s+/g, '');
  const bin = atob(b64); const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

// يرسل إشعار Web Push عبر بروتوكول VAPID (RFC 8030).
async function sendWebPush(
  vapidPrivateKey: string,
  subscription: { endpoint: string; p256dh_key: string; auth_key: string },
  notification: { id: string; title: string | null; body: string | null; action_url: string | null; priority: string | null; metadata: Record<string, unknown> | null; entity_id: string | null; entity_type: string | null } | null,
): Promise<Response> {
  const payload = JSON.stringify({
    title: notification?.title ?? 'أحلى شباب',
    body: notification?.body ?? 'إشعار جديد',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    data: {
      notificationId: notification?.id,
      entityId: notification?.entity_id,
      entityType: notification?.entity_type,
      actionUrl: notification?.action_url,
      metadata: notification?.metadata,
    },
    actions: [{ action: 'open', title: 'فتح' }, { action: 'dismiss', title: 'تجاهل' }],
    requireInteraction: notification?.priority === 'urgent',
    tag: notification?.id ?? 'default',
    dir: 'rtl',
    lang: 'ar',
    vibrate: [200, 100, 200],
    timestamp: Date.now(),
  });

  const endpoint = subscription.endpoint;
  const p256dh = subscription.p256dh_key;
  const auth = subscription.auth_key;

  const vapidHeaders = await createVapidHeaders(vapidPrivateKey, endpoint);

  return fetch(endpoint, {
    method: 'POST',
    signal: AbortSignal.timeout(15_000),
    headers: {
      'Content-Type': 'application/json',
      'Content-Encoding': 'aes128gcm',
      'TTL': '86400',
      ...vapidHeaders,
    },
    body: await encryptWebPushPayload(payload, p256dh, auth),
  });
}

// ينشئ رؤوس VAPID Authorization + Crypto-Key.
async function createVapidHeaders(vapidPrivateKeyPem: string, endpoint: string): Promise<Record<string, string>> {
  const url = new URL(endpoint);
  const audience = `${url.protocol}//${url.host}`;

  const vapidPublicKey = await deriveVapidPublicKey(vapidPrivateKeyPem);

  const header = { alg: 'ES256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    aud: audience,
    exp: now + 86400,
    sub: `mailto:admin@ahla-shabab.org`,
  };

  const enc = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const signingInput = `${enc(header)}.${enc(claims)}`;

  const privateKeyData = pemToArrayBuffer(vapidPrivateKeyPem);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', privateKeyData, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, cryptoKey, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${b64url(new Uint8Array(sig))}`;

  return {
    Authorization: `vapid t=${jwt}, k=${b64url(vapidPublicKey)}`,
    'Crypto-Key': `p256ecdsa=${b64url(vapidPublicKey)}`,
  };
}

// يستخرج المفتاح العام (SPKI) من المفتاح الخاص PKCS#8.
async function deriveVapidPublicKey(vapidPrivateKeyPem: string): Promise<Uint8Array> {
  const privateKeyData = pemToArrayBuffer(vapidPrivateKeyPem);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', privateKeyData, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'],
  );
  const spki = await crypto.subtle.exportKey('spki', cryptoKey);
  // SPKI = 0x30 0x59 0x30 0x13 0x06 0x07 0x2a 0x86 0x48 0xce 0x3d 0x02 0x01 0x06 0x08 0x2a 0x86 0x48 0xce 0x3d 0x03 0x01 0x07 0x03 0x42 0x00 + 65 bytes uncompressed public key
  const full = new Uint8Array(spki);
  // نأخذ الـ 65 بايت الأخيرة (uncompressed P-256 public key: 0x04 + 32B X + 32B Y)
  return full.slice(-65);
}

// يشفّر الحمولة بـ AES-128-GCM لمعيار Web Push.
async function encryptWebPushPayload(
  payload: string,
  p256dhBase64: string,
  authBase64: string,
): Promise<ArrayBuffer> {
  const dh = base64urlToBuffer(p256dhBase64);
  const auth = base64urlToBuffer(authBase64);

  // ECDH: نشتق سراً مشتركاً باستخدام مفتاحنا المؤقت + مفتاح المستخدم العام.
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const localKeyPair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
  const localPublicKey = await crypto.subtle.exportKey('raw', localKeyPair.publicKey);
  const sharedSecret = await crypto.subtle.deriveBits(
    { name: 'ECDH', public: await crypto.subtle.importKey('raw', dh, { name: 'ECDH', namedCurve: 'P-256' }, false, []) },
    localKeyPair.privateKey,
    128,
  );

  // HKDF-SHA256 لاستخراج مفتاح التشفير ومفتاح المصادقة.
  const ikm = new Uint8Array(sharedSecret);
  const prk = await crypto.subtle.importKey('raw', auth, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const infoEnc = new TextEncoder().encode('Content-Encoding: aes128gcm\u0000');
  const infoAuth = new TextEncoder().encode('Content-Encoding: auth\u0000');

  const encKey = await hkdf(ikm, salt, infoEnc, 16);
  const authKey = await hkdf(ikm, salt, infoAuth, 16);

  // AES-128-GCM تشفير.
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encCryptoKey = await crypto.subtle.importKey('raw', encKey, { name: 'AES-GCM' }, false, ['encrypt']);
  const payloadBytes = new TextEncoder().encode(payload);
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, encCryptoKey, payloadBytes);

  // بناء الرسالة: salt (16) + rs (1) + id (1) + localPublicKey (65) + ciphertext
  const record = new Uint8Array(16 + 1 + 1 + 65 + new Uint8Array(ciphertext).byteLength);
  let offset = 0;
  record.set(salt, offset); offset += 16;
  record.set(new Uint8Array([0]), offset); offset += 1; // rs = 0 (no padding)
  record.set(new Uint8Array([0]), offset); offset += 1; // id = 0 (direct)
  record.set(new Uint8Array(localPublicKey), offset); offset += 65;
  record.set(new Uint8Array(ciphertext), offset);

  return record.buffer;
}

function base64urlToBuffer(str: string): Uint8Array {
  const padding = '='.repeat((4 - (str.length % 4)) % 4);
  const b64 = (str + padding).replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}

async function hkdf(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const prkKey = await crypto.subtle.importKey('raw', ikm, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const prk = await crypto.subtle.sign('HMAC', prkKey, salt);
  const prkKey2 = await crypto.subtle.importKey('raw', new Uint8Array(prk), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const okm = await crypto.subtle.sign('HMAC', prkKey2, new Uint8Array([...info, 1]));
  return new Uint8Array(okm).slice(0, length);
}

function respond(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'content-type': 'application/json' } });
}
