// Generates server-authored WebAuthn registration/authentication options.
import { createClient } from "@supabase/supabase-js";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
} from "@simplewebauthn/server";

type AuthenticatorTransport =
  | "ble"
  | "cable"
  | "hybrid"
  | "internal"
  | "nfc"
  | "smart-card"
  | "usb";

function normalizeTransports(value: unknown): AuthenticatorTransport[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const allowed = new Set<AuthenticatorTransport>([
    "ble", "cable", "hybrid", "internal", "nfc", "smart-card", "usb",
  ]);
  const transports = value
    .filter((item): item is AuthenticatorTransport => typeof item === "string" && allowed.has(item as AuthenticatorTransport));
  return transports.length > 0 ? transports : undefined;
}
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RP_ID = Deno.env.get("WEBAUTHN_RP_ID") ?? "";
const RP_NAME = Deno.env.get("WEBAUTHN_RP_NAME") ?? "Ahla Shabab Management OS";
const ALLOWED_ORIGINS = new Set(
  (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean),
);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight(req);
  try {
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return json(req, { error: "unauthorized" }, 401);

  if (!SUPABASE_URL || !SERVICE_ROLE || !RP_ID || ALLOWED_ORIGINS.size === 0) {
    return json(req, { error: "server_not_configured" }, 500);
  }

  const origin = req.headers.get("Origin");
  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return json(req, { error: "origin_not_allowed" }, 403);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json(req, { error: "invalid_session" }, 401);

  let type: "register" | "auth" = "auth";
  try {
    const body = await req.json();
    type = body?.type === "register" ? "register" : "auth";
  } catch {
    // Authentication is the safe default.
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("employee_id")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (profileError) return json(req, { error: "profile_lookup_failed" }, 500);
  if (!profile?.employee_id) return json(req, { error: "no_employee_linked" }, 403);

  const { data: employee, error: employeeError } = await admin
    .from("employees")
    .select("full_name_ar, employee_code, is_active, is_deleted")
    .eq("id", profile.employee_id)
    .maybeSingle();
  if (employeeError) return json(req, { error: "employee_lookup_failed" }, 500);
  if (!employee || !employee.is_active || employee.is_deleted) {
    return json(req, { error: "employee_inactive" }, 403);
  }

  const oneMinuteAgo = new Date(Date.now() - 60_000).toISOString();
  const { count, error: countError } = await admin
    .from("webauthn_challenges")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userData.user.id)
    .gte("created_at", oneMinuteAgo);
  if (countError) return json(req, { error: "rate_limit_check_failed" }, 500);
  if ((count ?? 0) >= 20) return json(req, { error: "rate_limited" }, 429);

  const { data: passkeys, error: passkeyError } = await admin
    .from("passkey_credentials")
    .select("credential_id, transports")
    .eq("user_id", userData.user.id)
    .eq("employee_id", profile.employee_id)
    .eq("status", "active");
  if (passkeyError) return json(req, { error: "credential_lookup_failed" }, 500);

  const credentials = (passkeys ?? []).map((credential) => ({
    id: String(credential.credential_id),
    transports: normalizeTransports(credential.transports),
  }));

  let options;
  try {
    options = type === "register"
      ? await generateRegistrationOptions({
        rpName: RP_NAME,
        rpID: RP_ID,
        userName: userData.user.email ?? employee.employee_code ?? userData.user.id,
        userDisplayName: employee.full_name_ar ?? employee.employee_code ?? "موظف",
        userID: new TextEncoder().encode(userData.user.id),
        attestationType: "none",
        excludeCredentials: credentials,
        authenticatorSelection: {
          authenticatorAttachment: "platform",
          residentKey: "preferred",
          userVerification: "required",
        },
        supportedAlgorithmIDs: [-7, -257],
        timeout: 300_000,
      })
      : await generateAuthenticationOptions({
        rpID: RP_ID,
        allowCredentials: credentials,
        userVerification: "required",
        timeout: 300_000,
      });
  } catch (error) {
    console.error("webauthn options generation failed", error instanceof Error ? error.message : "unknown error");
    return json(req, { error: "options_generation_failed" }, 500);
  }

  const expiresAt = new Date(Date.now() + 5 * 60_000).toISOString();
  const { data: createdChallenge, error: insertError } = await admin.from("webauthn_challenges").insert({
    employee_id: profile.employee_id,
    user_id: userData.user.id,
    challenge: options.challenge,
    type,
    expires_at: expiresAt,
    relying_party_id: RP_ID,
    options_json: options,
    user_agent: req.headers.get("User-Agent")?.slice(0, 500) ?? null,
    created_by: userData.user.id,
  }).select("id").single();
  if (insertError) return json(req, { error: "challenge_create_failed" }, 500);

  return json(req, { ...options, challengeId: createdChallenge.id, expiresAt, type }, 200);
  } catch (err) {
    console.error("webauthn-challenge unhandled error", err instanceof Error ? err.message : String(err));
    return json(req, { error: "INTERNAL_ERROR" }, 500);
  }
});
