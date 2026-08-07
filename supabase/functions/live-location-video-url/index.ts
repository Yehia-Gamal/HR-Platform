// V17 §9: video permanently disabled — this edge function is a no-op stub.
// Kept as a stub to avoid breaking Supabase deployment config.
// Returns 410 Gone for any request.

import { json, preflight } from "../_shared/cors.ts";
import { createHandler } from "../_shared/withHandler.ts";

Deno.serve(createHandler({ functionName: "live-location-video-url", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === "OPTIONS") return preflight(req);
  return json(req, { error: "VIDEO_PERMANENTLY_DISABLED", message: "V17 §9: video verification has been permanently removed." }, 410);
}));
