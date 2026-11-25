import { createClient } from 'npm:@supabase/supabase-js@2';
import { createLogger } from '../_shared/logger.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { createHandler } from '../_shared/withHandler.ts';

const log = createLogger({ functionName: 'push-subscribe', version: '1.0.0' });

interface SubscribeBody {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

Deno.serve(
  createHandler({ functionName: 'push-subscribe', version: '1.0.0' }, async (req, ctx) => {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders(req, 'POST, DELETE, OPTIONS') });
    }
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return respond(req, { error: 'UNAUTHORIZED' }, 401);

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY');
    if (!url || !anonKey) return respond(req, { error: 'SERVER_CONFIGURATION' }, 500);

    const supabase = createClient(url, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userErr,
    } = await supabase.auth.getUser();
    if (userErr || !user) return respond(req, { error: 'UNAUTHORIZED' }, 401);

    if (req.method === 'POST') {
      const body = (await req.json()) as SubscribeBody;
      let validEndpoint = false;
      try {
        validEndpoint = typeof body?.endpoint === 'string' && new URL(body.endpoint).protocol === 'https:';
      } catch {
        validEndpoint = false;
      }
      if (!validEndpoint || !body?.keys?.p256dh || !body?.keys?.auth) {
        return respond(req, { error: 'INVALID_SUBSCRIPTION' }, 400);
      }

      const { error } = await supabase.from('push_subscriptions').upsert(
        {
          user_id: user.id,
          endpoint: body.endpoint,
          p256dh_key: body.keys.p256dh,
          auth_key: body.keys.auth,
          platform: 'web',
          is_active: true,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,endpoint' },
      );

      if (error) {
        await log.error('Upsert subscription failed', { error: error.message, userId: user.id });
        return respond(req, { error: 'DB_ERROR' }, 500);
      }
      return respond(req, { success: true });
    }

    if (req.method === 'DELETE') {
      const body = (await req.json()) as { endpoint: string };
      if (!body?.endpoint) return respond(req, { error: 'MISSING_ENDPOINT' }, 400);

      const { error } = await supabase.from('push_subscriptions').update({ is_active: false }).eq('user_id', user.id).eq('endpoint', body.endpoint);

      if (error) {
        await log.error('Deactivate subscription failed', { error: error.message, userId: user.id });
        return respond(req, { error: 'DB_ERROR' }, 500);
      }
      return respond(req, { success: true });
    }

    return respond(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  }),
);

function respond(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'content-type': 'application/json' } });
}
