import { createClient } from '@supabase/supabase-js';
import { corsHeaders } from '../_shared/cors.ts';
import { timingSafeEqual } from '../_shared/secret.ts';
import { createHandler } from "../_shared/withHandler.ts";

type OutboxRow = {
  id: string;
  integration_id: string | null;
  event_type: string;
  idempotency_key: string;
  payload: Record<string, unknown>;
  headers: Record<string, string>;
  attempts: number;
  max_attempts: number;
  correlation_id: string | null;
};

type IntegrationRow = {
  id: string;
  slug: string;
  status: string;
  is_enabled: boolean;
  webhook_url: string | null;
};

Deno.serve(createHandler({ functionName: "integration-outbox-worker", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return respond(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (!await timingSafeEqual(req.headers.get('x-cron-secret'), cronSecret)) {
    return respond(req, { error: 'UNAUTHORIZED' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return respond(req, { error: 'SERVER_CONFIGURATION' }, 500);
  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const worker = crypto.randomUUID();
  const now = new Date().toISOString();

  const { data: candidates, error: loadError } = await supabase
    .from('integration_outbox')
    .select('id,integration_id,event_type,idempotency_key,payload,headers,attempts,max_attempts,correlation_id')
    .in('status', ['pending', 'retrying'])
    .lte('next_attempt_at', now)
    .order('created_at', { ascending: true })
    .limit(50);
  if (loadError) return respond(req, { error: 'OUTBOX_LOAD_FAILED' }, 500);

  let delivered = 0;
  let failed = 0;
  let skipped = 0;
  for (const candidate of (candidates ?? []) as OutboxRow[]) {
    const { data: lock } = await supabase
      .from('integration_outbox')
      .update({ status: 'processing', locked_at: now, locked_by: worker, attempts: candidate.attempts + 1 })
      .eq('id', candidate.id)
      .in('status', ['pending', 'retrying'])
      .select('id')
      .maybeSingle();
    if (!lock) { skipped += 1; continue; }

    const started = performance.now();
    try {
      if (!candidate.integration_id) throw new Error('INTEGRATION_NOT_CONFIGURED');
      const { data: integration, error: integrationError } = await supabase
        .from('integrations')
        .select('id,slug,status,is_enabled,webhook_url')
        .eq('id', candidate.integration_id)
        .maybeSingle();
      if (integrationError || !integration) throw new Error('INTEGRATION_NOT_FOUND');
      const config = integration as IntegrationRow;
      if (!config.is_enabled || config.status !== 'active' || !config.webhook_url) throw new Error('INTEGRATION_INACTIVE');

      // SSRF protection: only allow HTTPS URLs to public hosts.
      // Block private/link-local IPs, cloud metadata endpoints, and non-HTTPS.
      if (!isAllowedWebhookUrl(config.webhook_url)) throw new Error('WEBHOOK_URL_BLOCKED');

      const tokenName = `INTEGRATION_TOKEN_${config.slug.toUpperCase().replace(/[^A-Z0-9]/g, '_')}`;
      const token = Deno.env.get(tokenName) ?? Deno.env.get('INTEGRATION_WEBHOOK_TOKEN');
      const response = await fetch(config.webhook_url, {
        method: 'POST',
        redirect: 'error',
        signal: AbortSignal.timeout(15_000),
        headers: {
          'content-type': 'application/json',
          'x-idempotency-key': candidate.idempotency_key,
          'x-event-type': candidate.event_type,
          'x-correlation-id': candidate.correlation_id ?? candidate.id,
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...sanitizeHeaders(candidate.headers),
        },
        body: JSON.stringify(candidate.payload),
      });
      const responseText = (await response.text()).slice(0, 2048);
      if (!response.ok) throw new Error(`WEBHOOK_${response.status}:${responseText}`);

      await supabase.from('integration_outbox').update({
        status: 'delivered', delivered_at: new Date().toISOString(), last_error: null,
        locked_at: null, locked_by: null,
      }).eq('id', candidate.id);
      await supabase.from('integration_logs').insert({
        integration_id: config.id, direction: 'outbound', operation: candidate.event_type,
        status: 'success', http_status: response.status, response_payload: { preview: responseText },
        duration_ms: Math.round(performance.now() - started), correlation_id: candidate.correlation_id ?? candidate.id,
      });
      delivered += 1;
    } catch (error) {
      const attempts = candidate.attempts + 1;
      const terminal = attempts >= candidate.max_attempts;
      const delaySeconds = Math.min(21_600, Math.max(60, 2 ** Math.min(attempts, 10) * 30));
      const message = String(error).slice(0, 2000);
      await supabase.from('integration_outbox').update({
        status: terminal ? 'dead_letter' : 'retrying',
        next_attempt_at: new Date(Date.now() + delaySeconds * 1000).toISOString(),
        last_error: message, locked_at: null, locked_by: null,
      }).eq('id', candidate.id);
      if (candidate.integration_id) {
        await supabase.from('integration_logs').insert({
          integration_id: candidate.integration_id, direction: 'outbound', operation: candidate.event_type,
          status: terminal ? 'failed' : 'retrying', error_message: message,
          duration_ms: Math.round(performance.now() - started), correlation_id: candidate.correlation_id ?? candidate.id,
        });
      }
      failed += 1;
    }
  }

  return respond(req, { processed: (candidates ?? []).length, delivered, failed, skipped, worker, completedAt: new Date().toISOString() });
}));

/**
 * SSRF protection: only allow HTTPS URLs pointing to public (non-private) hosts.
 * Blocks cloud metadata endpoints (169.254.x.x), private RFC-1918 ranges,
 * localhost, and non-HTTPS schemes.
 */
function isAllowedWebhookUrl(raw: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return false;
  }
  if (parsed.protocol !== 'https:') return false;
  const host = parsed.hostname.toLowerCase();
  // Block localhost variants
  if (host === 'localhost' || host === '0.0.0.0') return false;
  // Block cloud metadata endpoint (AWS/GCP/Azure link-local)
  if (host === '169.254.169.254' || host === 'metadata.google.internal') return false;
  // Block IPv6 private/reserved ranges (brackets stripped by URL parser)
  if (host.startsWith('[') || host === '::1') return false;
  const v6 = host.replace(/^\[|\]$/g, '');
  if (/^(fc|fd)[0-9a-f]{2}:/i.test(v6)) return false;          // fc00::/7 unique-local
  if (/^fe[89ab][0-9a-f]:/i.test(v6)) return false;             // fe80::/10 link-local
  if (/^::ffff:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/i.test(v6)) return false; // IPv4-mapped
  if (v6 === '::' || v6 === '::1') return false;                // loopback / unspecified
  // Block private/reserved IPv4 ranges
  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4) {
    const [, a, b] = ipv4.map(Number);
    if (a === 10) return false;                         // 10.0.0.0/8
    if (a === 127) return false;                        // 127.0.0.0/8 loopback
    if (a === 172 && b >= 16 && b <= 31) return false;  // 172.16.0.0/12
    if (a === 192 && b === 168) return false;            // 192.168.0.0/16
    if (a === 169 && b === 254) return false;            // 169.254.0.0/16 link-local
    if (a === 0 || a >= 224) return false;               // 0.0.0.0/8, multicast, reserved
  }
  return true;
}

function sanitizeHeaders(value: Record<string, string> | null | undefined) {
  const result: Record<string, string> = {};
  const denied = new Set(['authorization', 'cookie', 'host', 'content-length']);
  for (const [key, raw] of Object.entries(value ?? {})) {
    if (!denied.has(key.toLowerCase()) && typeof raw === 'string' && raw.length <= 1000) result[key] = raw;
  }
  return result;
}

function respond(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'content-type': 'application/json; charset=utf-8' } });
}
