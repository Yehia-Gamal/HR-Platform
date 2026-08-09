import { createClient } from '@supabase/supabase-js';
import { createLogger } from "../_shared/logger.ts";
import { corsHeaders } from '../_shared/cors.ts';
import { timingSafeEqual } from '../_shared/secret.ts';
import { createHandler } from '../_shared/withHandler.ts';
const log = createLogger({ functionName: "retention-cleanup", version: "1.0.0" });

type Candidate = { video_id: string; storage_bucket: string; storage_path: string };

Deno.serve(createHandler({ functionName: 'retention-cleanup', version: '1.0.0' }, async (req, ctx) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return respond(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const configuredSecret = Deno.env.get('CRON_SECRET');
  if (!await timingSafeEqual(req.headers.get('x-cron-secret'), configuredSecret)) {
    return respond(req, { error: 'UNAUTHORIZED' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return respond(req, { error: 'SERVER_CONFIGURATION' }, 500);

  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { data, error } = await supabase.rpc('list_retention_video_candidates', { p_limit: 100 });
  if (error) return respond(req, { error: 'LOAD_CANDIDATES_FAILED' }, 500);

  let deleted = 0;
  const failures: Array<{ id: string; reason: string }> = [];
  for (const item of (data ?? []) as Candidate[]) {
    try {
      const { error: storageError } = await supabase.storage
        .from(item.storage_bucket || 'live-location-videos')
        .remove([item.storage_path]);
      if (storageError) throw storageError;
      const { error: markError } = await supabase.rpc('mark_retention_video_deleted', {
        p_video_id: item.video_id,
        p_reason: 'retention_expired',
      });
      if (markError) throw markError;
      deleted += 1;
    } catch (error) {
      failures.push({ id: item.video_id, reason: String(error) });
    }
  }

  // Map snapshots share the same strict 24-hour retention boundary as videos.
  const snapshotCutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: snapshots, error: snapshotLoadError } = await supabase
    .from('location_request_responses')
    .select('id,map_snapshot_storage_path,metadata')
    .not('map_snapshot_storage_path', 'is', null)
    .lt('captured_at', snapshotCutoff)
    .limit(100);
  let deletedSnapshots = 0;
  if (!snapshotLoadError) {
    for (const snapshot of snapshots ?? []) {
      try {
        const path = snapshot.map_snapshot_storage_path as string;
        const { error: removeError } = await supabase.storage
          .from('live-location-map-snapshots')
          .remove([path]);
        if (removeError) throw removeError;
        const { error: markError } = await supabase
          .from('location_request_responses')
          .update({
            map_snapshot_storage_path: null,
            metadata: {
              ...((snapshot.metadata ?? {}) as Record<string, unknown>),
              mapSnapshotDeletedAt: new Date().toISOString(),
              mapSnapshotDeleteReason: 'retention_expired',
            },
          })
          .eq('id', snapshot.id);
        if (markError) throw markError;
        deletedSnapshots += 1;
      } catch (error) {
        failures.push({ id: String(snapshot.id), reason: `map_snapshot:${String(error)}` });
      }
    }
  }

  const { data: cleanup, error: cleanupError } = await supabase.rpc(
    'cleanup_expired_ephemeral_records',
    { p_batch: 1000 },
  );

  const { data: expiredBreakGlass, error: breakGlassError } = await supabase.rpc(
    'expire_break_glass_access',
  );

  const loginCutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { count: removedLoginAttempts, error: loginCleanupError } = await supabase
    .from('login_auth_attempts')
    .delete({ count: 'exact' })
    .lt('attempted_at', loginCutoff);

  return respond(req, {
    candidates: (data ?? []).length,
    deleted,
    mapSnapshots: snapshotLoadError
      ? { error: 'MAP_SNAPSHOT_LOAD_FAILED' }
      : { candidates: snapshots?.length ?? 0, deleted: deletedSnapshots },
    failures,
    ephemeralCleanup: cleanupError ? { error: 'EPHEMERAL_CLEANUP_FAILED' } : cleanup,
    expiredBreakGlass: breakGlassError ? { error: 'BREAK_GLASS_EXPIRY_FAILED' } : expiredBreakGlass,
    loginAttemptCleanup: loginCleanupError ? { error: 'LOGIN_ATTEMPT_CLEANUP_FAILED' } : { removed: removedLoginAttempts ?? 0 },
    completedAt: new Date().toISOString(),
  }, failures.length ? 207 : 200);
}));

function respond(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'content-type': 'application/json; charset=utf-8' },
  });
}
