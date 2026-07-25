// V17 §9: video permanently disabled — this edge function is a no-op stub.
// Kept as a stub to avoid breaking Supabase deployment config.
// Returns 410 Gone for any request.

import { json, preflight } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight(req);
  return json(req, { error: "VIDEO_PERMANENTLY_DISABLED", message: "V17 §9: video verification has been permanently removed." }, 410);
});
