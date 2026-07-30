import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SIGNED_TTL_SECONDS = 120;
const inputSchema = z.object({ requestId: z.string().uuid() });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight(req);
  if (req.method !== "POST") return json(req, { error: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE || !PUBLISHABLE_KEY) {
    return json(req, { error: "SERVER_CONFIGURATION" }, 500);
  }
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json(req, { error: "unauthorized" }, 401);

  // حد حجم الجسم — UUID واحد فقط، 1 كيلوبايت كافٍ.
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > 1_024) return json(req, { error: "PAYLOAD_TOO_LARGE" }, 413);

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
});
