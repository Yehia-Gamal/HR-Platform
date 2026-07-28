import { createClient } from '@supabase/supabase-js';
import { corsHeaders } from '../_shared/cors.ts';
import { timingSafeEqual } from '../_shared/secret.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const cronSecret = Deno.env.get('CRON_SECRET');
  const cron = req.headers.get('x-cron-secret');
  if (!await timingSafeEqual(cron, cronSecret)) return json(req, { error: 'UNAUTHORIZED' }, 401);
  const url = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json(req, { error: 'SERVER_CONFIGURATION' }, 500);
  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { data: queued, error } = await supabase.rpc('queue_due_scheduled_reports', { p_now: new Date().toISOString() });
  if (error) { console.error('queue_due_scheduled_reports failed', error.message); return json(req, { error: 'QUEUE_FAILED' }, 500); }
  const { data: runs } = await supabase.from('report_runs').select('id,report_type,audience_snapshot').eq('status', 'queued').limit(20);
  let completed = 0; let failed = 0;
  for (const run of runs ?? []) {
    try {
      await supabase.from('report_runs').update({ status: 'running', started_at: new Date().toISOString(), attempts: 1 }).eq('id', run.id).eq('status', 'queued');
      const summary = { generatedAt: new Date().toISOString(), reportType: run.report_type, audience: run.audience_snapshot, note: 'Structured report payload. PDF rendering may be connected through a trusted renderer.' };
      const { error: completeError } = await supabase.from('report_runs').update({ status: 'completed', completed_at: new Date().toISOString(), result_summary: summary }).eq('id', run.id);
      if (!completeError) completed += 1; else failed += 1;
    } catch {
      await supabase.from('report_runs').update({ status: 'failed', completed_at: new Date().toISOString() }).eq('id', run.id).catch(() => {});
      failed += 1;
    }
  }
  return json(req, { queued: queued ?? 0, completed, failed });
});

function json(req: Request, body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'content-type': 'application/json' } }); }
