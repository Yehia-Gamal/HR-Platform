import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";
import { createHandler } from "../_shared/withHandler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SIGNED_TTL_SECONDS = 120;
// Rate limit: 30 signed-URL generations per actor per 60s. Guards against a
// single authorized user mass-generating snapshot URLs (enumeration/abuse).
const RL_WINDOW_MS = 60_000;
const RL_LIMIT = 30;
const RL_RETRY_AFTER_SECONDS = 60;
const inputSchema = z.object({ requestId: z.string().uuid() });

Deno.serve(createHandler({ functionName: "live-location-map-url", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === "OPTIONS") return preflight(req);
  if (req.method !== "POST") return json(req, { error: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE || !PUBLISHABLE_KEY) {
    return json(req, { error: "SERVER_CONFIGURATION" }, 500);
  }
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json(req, { error: "unauthorized" }, 401);

  let body: z.infer<typeof inputSchema>;
  try {
    body = inputSchema.parse(await req.json());
  } catch {
    return json(req, { error: "INVALID_INPUT" }, 400);
  }

  const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) return json(req, { error: "unauthorized" }, 401);
  const { data: gate, error: gateError } = await userClient.rpc(
    "can_view_live_location_map_snapshot",
    { p_request_id: body.requestId },
  );
  if (gateError) return json(req, { error: "GATE_FAILED" }, 500);
  if (!gate?.storagePath) return json(req, { error: "FORBIDDEN" }, 403);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

  // Rate limit: RL_LIMIT signed-URL generations per actor per RL_WINDOW_MS.
  // Runs on the service-role client (the access-log table has RLS revoked from
  // authenticated) and before the createSignedUrl call. Filtered to
  // action="signed_url" so 'view' events do not consume the budget.
  const rlWindow = new Date(Date.now() - RL_WINDOW_MS).toISOString();
  const { count: rlCount, error: rlError } = await admin
    .from("live_location_map_access_logs")
    .select("id", { count: "exact", head: true })
    .eq("actor_user_id", userData.user.id)
    .eq("action", "signed_url")
    .gte("created_at", rlWindow);
  if (rlError) return json(req, { error: "rate_limit_check_failed" }, 500);
  if ((rlCount ?? 0) >= RL_LIMIT) {
    return json(req, { error: "too_many_attempts", retryAfterSeconds: RL_RETRY_AFTER_SECONDS }, 429);
  }

  const { data: signed, error: signError } = await admin.storage
    .from(gate.bucket ?? "live-location-map-snapshots")
    .createSignedUrl(gate.storagePath, SIGNED_TTL_SECONDS);
  if (signError || !signed?.signedUrl) return json(req, { error: "SIGN_FAILED" }, 500);

  await admin.from("live_location_map_access_logs").insert({
    response_id: gate.responseId,
    request_id: body.requestId,
    actor_user_id: userData.user.id,
    action: "signed_url",
  });
  return json(req, { url: signed.signedUrl, expiresInSeconds: SIGNED_TTL_SECONDS });
}));
