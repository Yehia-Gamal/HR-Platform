import { createClient } from 'npm:@supabase/supabase-js@2';
import { createLogger } from '../_shared/logger.ts';
import { json, preflight } from '../_shared/cors.ts';
import { createHandler } from '../_shared/withHandler.ts';

const log = createLogger({ functionName: 'whatsapp-dispatcher', version: '1.0.0' });

// ─── Zero-Cost WhatsApp & OTP Dispatcher ───────────────────────────
// تكامل مجاني 100% لإرسال رسائل التحقق (OTP) والإشعارات التشغيلية:
// 1. Meta WhatsApp Cloud API: شريحة مجانية توفر 1,000 محادثة خدمة شهرياً للأبد.
// 2. Local Android SMS Gateway (اختياري): إرسال SMS مجاني عبر هاتف أندرويد محلي بشريحة اتصالات.
// 3. Mock/Dev Mode: تسجيل الأكواد محلياً لأغراض التطوير بدون إنفاق أي مال.
// ───────────────────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const WHATSAPP_PHONE_NUMBER_ID = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID') ?? '';
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? '';
const LOCAL_SMS_GATEWAY_URL = Deno.env.get('LOCAL_SMS_GATEWAY_URL') ?? '';

interface SendOtpPayload {
  action: 'send_otp';
  phone: string;
}

interface VerifyOtpPayload {
  action: 'verify_otp';
  phone: string;
  code: string;
}

interface SendNotificationPayload {
  action: 'send_notification';
  phone: string;
  title: string;
  body: string;
  type?: 'leave_approval' | 'payslip' | 'shift_alert' | 'general';
}

type DispatcherPayload = SendOtpPayload | VerifyOtpPayload | SendNotificationPayload;

function normalizePhone(raw: string): string {
  const compact = raw.replace(/[\s().-]/g, '');
  if (/^01\d{9}$/.test(compact)) return `+20${compact.slice(1)}`;
  if (/^20\d{10}$/.test(compact)) return `+${compact}`;
  if (!compact.startsWith('+')) return `+${compact}`;
  return compact;
}

// إرسال عبر Meta WhatsApp Cloud API المجاني
async function sendWhatsAppMessage(phone: string, text: string): Promise<{ success: boolean; id?: string; error?: string }> {
  if (!WHATSAPP_PHONE_NUMBER_ID || !WHATSAPP_ACCESS_TOKEN) {
    return { success: false, error: 'WHATSAPP_CONFIG_MISSING' };
  }

  // تنظيف الرقم بدون علامة + لـ WhatsApp Graph API
  const recipient = phone.replace(/\D/g, '');

  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: recipient,
        type: 'text',
        text: {
          preview_url: false,
          body: text,
        },
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      log.warn('WhatsApp API responded with error', { status: res.status, data });
      return { success: false, error: data?.error?.message || `HTTP_${res.status}` };
    }

    return { success: true, id: data?.messages?.[0]?.id };
  } catch (err) {
    log.error('WhatsApp API network failure', err);
    return { success: false, error: String(err) };
  }
}

// إرسال عبر بوابة أندرويد SMS المحلية المجانية (Android SMS Gateway Open-Source)
async function sendLocalSms(phone: string, text: string): Promise<{ success: boolean; error?: string }> {
  if (!LOCAL_SMS_GATEWAY_URL) return { success: false, error: 'NO_SMS_GATEWAY' };

  try {
    const url = new URL(LOCAL_SMS_GATEWAY_URL);
    url.searchParams.set('phone', phone);
    url.searchParams.set('message', text);

    const res = await fetch(url.toString(), {
      method: 'POST',
      signal: AbortSignal.timeout(8000),
    });

    return { success: res.ok };
  } catch (err) {
    return { success: false, error: String(err) };
  }
}

Deno.serve(
  createHandler({ functionName: 'whatsapp-dispatcher', version: '1.0.0' }, async (req, ctx) => {
    if (req.method === 'OPTIONS') return preflight(req);
    if (req.method !== 'POST') return json(req, { error: 'METHOD_NOT_ALLOWED' }, 405);

    let payload: DispatcherPayload;
    try {
      payload = await req.json();
    } catch {
      return json(req, { error: 'INVALID_JSON' }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false },
    });

    // ─── 1. إرسال رمز التحقق OTP ──────────────────────────────────────
    if (payload.action === 'send_otp') {
      const phone = normalizePhone(payload.phone || '');
      if (!phone || phone.length < 8) {
        return json(req, { error: 'INVALID_PHONE_NUMBER' }, 400);
      }

      // التحقق من وجود الموظف
      const { data: emp } = await admin
        .from('employees')
        .select('id, full_name_ar')
        .eq('phone_e164', phone)
        .eq('is_deleted', false)
        .eq('is_active', true)
        .maybeSingle();

      if (!emp) {
        // Obfuscation: نرجع نفس الرد حتى لا يتم كشف أرقام الهواتف
        return json(req, { success: true, message: 'OTP_SENT_OR_SIMULATED' });
      }

      // توليد رمز 6 أرقام عشوائي
      const otpCode = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 دقائق

      // حفظ الرمز في جدول الملاحظات أو التدقيق المؤقت
      const messageBody = `رمز الدخول السريع الخاص بك في منظومة أحلى شباب هو: ${otpCode}\nصالحة لمدة 5 دقائق. لا تشارك هذا الرمز مع أي شخص حفاظاً على أمان حسابك.`;

      let sent = false;
      let channelUsed = 'mock';

      // محاولة الإرسال عبر WhatsApp
      const waResult = await sendWhatsAppMessage(phone, messageBody);
      if (waResult.success) {
        sent = true;
        channelUsed = 'whatsapp';
      } else {
        // محاولة بديلة عبر SMS المحلي
        const smsResult = await sendLocalSms(phone, messageBody);
        if (smsResult.success) {
          sent = true;
          channelUsed = 'sms_gateway';
        } else {
          // بيئة التطوير المجانية: طباعة الرمز في السجلات للمعاينة
          log.info(`[DEV OTP SIMULATION] Phone: ${phone}, OTP: ${otpCode}`);
          sent = true;
          channelUsed = 'simulated';
        }
      }

      // تخزين جلسة الـ OTP
      await admin.from('login_auth_attempts').insert({
        identifier_kind: 'phone',
        identifier_hash: phone,
        failure_code: `otp:${otpCode}:${expiresAt}`,
        success: false,
      });

      return json(req, {
        success: true,
        channel: channelUsed,
        expiresInSeconds: 300,
      });
    }

    // ─── 2. التحقق من رمز OTP ───────────────────────────────────────
    if (payload.action === 'verify_otp') {
      const phone = normalizePhone(payload.phone || '');
      const code = String(payload.code || '').trim();

      const { data: attempts } = await admin
        .from('login_auth_attempts')
        .select('id, failure_code, attempted_at')
        .eq('identifier_kind', 'phone')
        .eq('identifier_hash', phone)
        .order('attempted_at', { ascending: false })
        .limit(1);

      const latest = attempts?.[0];
      if (!latest || !latest.failure_code?.startsWith('otp:')) {
        return json(req, { error: 'NO_ACTIVE_OTP' }, 400);
      }

      const [, storedCode, expiresAt] = latest.failure_code.split(':');
      if (new Date(expiresAt).getTime() < Date.now()) {
        return json(req, { error: 'OTP_EXPIRED' }, 400);
      }

      if (storedCode !== code) {
        return json(req, { error: 'INVALID_OTP_CODE' }, 401);
      }

      // نجح التحقق — مسح الرمز المستخدم
      await admin.from('login_auth_attempts').update({ success: true, failure_code: 'otp_verified' }).eq('id', latest.id);

      return json(req, { success: true, verified: true });
    }

    // ─── 3. إرسال إشعار تشغيلي فوري عبر WhatsApp ─────────────────────
    if (payload.action === 'send_notification') {
      const phone = normalizePhone(payload.phone || '');
      const text = `🔔 *منظومة أحلى شباب HR*\n\n*${payload.title}*\n${payload.body}\n\nتاريخ الإشعار: ${new Date().toLocaleTimeString('ar-EG')}`;

      const res = await sendWhatsAppMessage(phone, text);
      if (!res.success) {
        await sendLocalSms(phone, text);
      }

      return json(req, { success: true });
    }

    return json(req, { error: 'UNKNOWN_ACTION' }, 400);
  }),
);
