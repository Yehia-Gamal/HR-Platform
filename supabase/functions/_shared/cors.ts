// CORS helper — origin مقفل على النطاقات المسموحة فقط (لا wildcard).
const ALLOWED = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter(Boolean);

const DEV = ["development", "dev", "local"].includes(
  (Deno.env.get("SUPABASE_ENV") ?? Deno.env.get("DENO_ENV") ?? "").toLowerCase(),
);
const DEV_ORIGINS = [
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "http://localhost:4173",
  "http://127.0.0.1:4173",
  "http://localhost:4174",
  "http://127.0.0.1:4174",
];
const DEFAULT_ORIGINS = [
  "https://ahla-shabab-management-os.vercel.app",
];
const ALLOWED_ORIGINS = new Set([
  ...(ALLOWED.length > 0 ? ALLOWED : DEFAULT_ORIGINS),
  ...(DEV ? DEV_ORIGINS : []),
]);

export function corsHeaders(req: Request, methods = "POST, OPTIONS"): Record<string, string> {
  const origin = req.headers.get("Origin");
  return {
    ...(origin && ALLOWED_ORIGINS.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers":
        "Content-Type, Authorization, apikey, x-client-info, x-request-id, x-cron-secret",
    "Access-Control-Allow-Methods": methods,
    "Access-Control-Max-Age": "86400",
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json; charset=utf-8" },
  });
}

export function preflight(req: Request): Response {
  return new Response("ok", { headers: corsHeaders(req) });
}
