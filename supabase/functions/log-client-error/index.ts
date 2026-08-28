// يستقبل تقارير الأخطاء من واجهة الويب ويكتبها في observability_events.
// بديل داخلي لـ Sentry عند عدم توفّر DSN — كل الأخطاء تُخزّن في قاعدة البيانات.
import { createClient } from '@supabase/supabase-js';
import { json, preflight } from '../_shared/cors.ts';
import { createHandler } from '../_shared/withHandler.ts';
import { z } from 'zod';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const PUBLISHABLE_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const inputSchema = z.object({
  level: z.enum(['debug', 'info', 'warning', 'error', 'critical']).default('error'),
  source: z.string().trim().max(200).default('web:admin'),
  eventType: z.string().trim().max(100).default('error'),
  message: z.string().trim().min(1).max(2000),
  errorName: z.string().trim().max(300).optional(),
  errorStack: z.string().trim().max(5000).optional(),
  requestId: z.string().trim().max(100).optional(),
  route: z.string().trim().max(500).optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

Deno.serve(
  createHandler({ functionName: 'log-client-error', version: '1.0.0' }, async (req, ctx) => {
    if (req.method === 'OPTIONS') return preflight(req);
    if (req.method !== 'POST') return json(req, { error: 'method_not_allowed' }, 405);

    if (!SUPABASE_URL || !SERVICE_ROLE || !PUBLISHABLE_KEY) {
      return json(req, { error: 'server_not_configured' }, 500);
    }

    // نتحقق من هوية المستخدم عبر publishable key + Authorization header
    const authorization = req.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return json(req, { error: 'unauthorized' }, 401);

    const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json(req, { error: 'invalid_session' }, 401);

    // Rate limit: 30 تقرير خطأ لكل مستخدم في الدقيقة (يمنع حلقة أخطاء لا نهائية)
    const oneMinuteAgo = new Date(Date.now() - 60_000).toISOString();
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { count: recentCount, error: rlError } = await admin
      .from('observability_events')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userData.user.id)
      .gte('created_at', oneMinuteAgo);
    if (rlError) return json(req, { error: 'rate_limit_check_failed' }, 500);
    if ((recentCount ?? 0) >= 30) {
      return json(req, { error: 'too_many_errors', retryAfterSeconds: 60 }, 429);
    }

    let input: z.infer<typeof inputSchema>;
    try {
      input = inputSchema.parse(await req.json());
    } catch (error) {
      return json(
        req,
        {
          error: 'validation_failed',
          details: error instanceof z.ZodError ? error.issues : undefined,
        },
        400,
      );
    }

    // نكتب الحدث عبر service_role (جدول observability_events يمنع INSERT على authenticated)
    const { error: insertError } = await admin.from('observability_events').insert({
      level: input.level,
      source: input.source,
      event_type: input.eventType,
      message: input.message,
      error_name: input.errorName ?? null,
      error_stack: input.errorStack ?? null,
      request_id: input.requestId ?? null,
      user_id: userData.user.id,
      metadata: {
        ...input.metadata,
        route: input.route,
      },
    });

    if (insertError) {
      ctx.log.error('observability_events insert failed', insertError);
      return json(req, { error: 'insert_failed' }, 500);
    }

    return json(req, { ok: true }, 200);
  }),
);
