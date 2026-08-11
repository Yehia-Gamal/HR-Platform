// Verifies a native/Web WebAuthn registration response and persists only the public credential.
import { createLogger } from "../_shared/logger.ts";
import { createClient } from "@supabase/supabase-js";
import { verifyRegistrationResponse } from "@simplewebauthn/server";

type RegistrationResponse = Parameters<typeof verifyRegistrationResponse>[0]["response"];
import { json, preflight } from "../_shared/cors.ts";
import { createHandler } from "../_shared/withHandler.ts";
const log = createLogger({ functionName: "passkey-register", version: "1.0.0" });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RP_ID = Deno.env.get("WEBAUTHN_RP_ID") ?? "";
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((value) => value.trim()).filter(Boolean);
const MAX_BODY_BYTES = 256 * 1024;

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const value of bytes) binary += String.fromCharCode(value);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

Deno.serve(createHandler({ functionName: "passkey-register", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === "OPTIONS") return preflight(req);
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return json(req, { error: "unauthorized" }, 401);

  if (!SUPABASE_URL || !SERVICE_ROLE || !RP_ID || ALLOWED_ORIGINS.length === 0) {
    return json(req, { error: "server_not_configured" }, 500);
  }
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > MAX_BODY_BYTES) return json(req, { error: "payload_too_large" }, 413);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json(req, { error: "invalid_session" }, 401);

  const { data: profile, error: profileError } = await admin
    .from("profiles").select("employee_id").eq("id", userData.user.id).maybeSingle();
  if (profileError) return json(req, { error: "profile_lookup_failed" }, 500);
  if (!profile?.employee_id) return json(req, { error: "no_employee_linked" }, 403);

  // Rate limit: 5 successful passkey registrations per user per 5 minutes.
  // Rows land here only on success (via activate_verified_passkey_device), so
  // this is a defense-in-depth cap on mass device enrollment from a hijacked
  // session — not a verify-flood throttle. Flooding of the verify path is
  // already bounded upstream by the webauthn-challenge issuance limit (20/min)
  // plus the valid-unused-unexpired-challenge + WebAuthn verification gate.
  const rlWindow = new Date(Date.now() - 5 * 60_000).toISOString();
  const { count: recentRegistrations, error: rlError } = await admin
    .from("passkey_credentials")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userData.user.id)
    .gte("created_at", rlWindow);
  if (rlError) return json(req, { error: "rate_limit_check_failed" }, 500);
  if ((recentRegistrations ?? 0) >= 5) {
    return json(req, { error: "too_many_attempts", retryAfterSeconds: 300 }, 429);
  }

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return json(req, { error: "bad_request" }, 400);
  }
  const response = (input.response ?? input) as Record<string, unknown>;
  const credentialId = String(response.id ?? "");
  if (!credentialId) return json(req, { error: "credential_response_required" }, 400);

  const { data: challenge, error: challengeError } = await admin
    .from("webauthn_challenges")
    .select("id, challenge, options_json, relying_party_id")
    .eq("user_id", userData.user.id)
    .eq("employee_id", profile.employee_id)
    .eq("type", "register")
    .is("used_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (challengeError) return json(req, { error: "challenge_lookup_failed" }, 500);
  if (!challenge) return json(req, { error: "challenge_invalid_or_used" }, 400);

  // Android APK-key-hash origins must be explicitly configured alongside the
  // approved HTTPS origin; never trust an origin copied from clientDataJSON.
  const expectedOrigins = [...ALLOWED_ORIGINS];

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: response as unknown as RegistrationResponse,
      expectedChallenge: challenge.challenge,
      expectedOrigin: expectedOrigins,
      expectedRPID: challenge.relying_party_id ?? RP_ID,
      requireUserVerification: true,
    });
  } catch (error) {
    // استخراج الـ origin الفعلي من clientDataJSON لتسهيل التشخيص —
    // على أندرويد يكون بصيغة android:apk-key-hash-sha256:... أو android:apk-key-hash:...
    let actualOrigin = "unknown";
    try {
      const inner = (response as Record<string, unknown>).response as Record<string, unknown> | undefined;
      const cdj = inner?.clientDataJSON ?? (response as Record<string, unknown>).clientDataJSON;
      if (typeof cdj === "string") {
        let src = cdj.replace(/-/g, "+").replace(/_/g, "/");
        src += "=".repeat((4 - src.length % 4) % 4);
        const parsed = JSON.parse(atob(src));
        actualOrigin = parsed?.origin ?? "missing";
      }
    } catch { /* تعذر تحليل clientDataJSON */ }
    console.error("passkey registration verification failed", {
      error: error instanceof Error ? error.message : "unknown error",
      actualOrigin,
      expectedOrigins,
    });
    return json(req, { error: "registration_verification_failed" }, 403);
  }
  if (!verification.verified || !verification.registrationInfo) {
    return json(req, { error: "registration_not_verified" }, 403);
  }

  const { data: consumed, error: consumeError } = await admin
    .from("webauthn_challenges")
    .update({ used_at: new Date().toISOString() })
    .eq("id", challenge.id)
    .is("used_at", null)
    .select("id");
  if (consumeError) return json(req, { error: "challenge_consume_failed" }, 500);
  if (!consumed || consumed.length !== 1) return json(req, { error: "challenge_already_used" }, 409);

  const info = verification.registrationInfo;
  const credential = info.credential;
  const webauthnUserId = String((challenge.options_json as Record<string, unknown> | null)?.user
    ? ((challenge.options_json as { user?: { id?: string } }).user?.id ?? "")
    : "");

  // One database transaction creates the credential and activates the matching
  // employee_devices row. The RPC is service-role only and is reached only after
  // SimpleWebAuthn has verified origin, RP ID, challenge and user verification.
  const { data: saved, error: saveError } = await admin.rpc(
    "activate_verified_passkey_device",
    {
      p_employee_id: profile.employee_id,
      p_user_id: userData.user.id,
      p_credential_id: credential.id,
      p_public_key: bytesToBase64Url(credential.publicKey),
      p_sign_count: credential.counter,
      p_transports: credential.transports ?? [],
      p_device_label: typeof input.deviceLabel === "string"
        ? input.deviceLabel.slice(0, 120)
        : "هاتف الموظف",
      p_webauthn_user_id: webauthnUserId,
      p_credential_device_type: info.credentialDeviceType,
      p_credential_backed_up: info.credentialBackedUp,
    },
  );
  if (saveError) {
    if (saveError.code === "23505") return json(req, { error: "credential_already_registered" }, 409);
    ctx.log.error("passkey credential save failed", saveError, { code: saveError.code });
    return json(req, { error: "credential_save_failed" }, 500);
  }

  return json(req, { ok: true, verified: true, credential: saved }, 201);
}));
