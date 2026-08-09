// Verifies a WebAuthn assertion and records attendance through the server-only RPC.
import { createLogger } from "../_shared/logger.ts";
import { createClient } from "@supabase/supabase-js";
import { verifyAuthenticationResponse } from "@simplewebauthn/server";

type AuthenticationResponse = Parameters<typeof verifyAuthenticationResponse>[0]["response"];
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
import { createHandler } from "../_shared/withHandler.ts";
const log = createLogger({ functionName: "verify-attendance-punch", version: "1.0.0" });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RP_ID = Deno.env.get("WEBAUTHN_RP_ID") ?? "";
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((value) => value.trim()).filter(Boolean);
const MAX_BODY_BYTES = 256 * 1024;

function b64urlToBytes(value: string): Uint8Array<ArrayBuffer> {
  let source = value.replace(/-/g, "+").replace(/_/g, "/");
  source += "=".repeat((4 - source.length % 4) % 4);
  const binary = atob(source);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function validateCoordinates(latitude: unknown, longitude: unknown, accuracy: unknown): string | null {
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90) return "invalid_latitude";
  if (typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) return "invalid_longitude";
  if (typeof accuracy !== "number" || !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 10_000) return "invalid_accuracy";
  return null;
}

// Defense-in-depth mirror of the finalize_verified_attendance selfie-path guard.
// The RPC is the authoritative check (it holds employee_id); this rejects obviously
// malformed paths early. Returns the validated path, or null if absent/blank.
// Throws a string error code (caught by the caller) on a malformed non-empty path.
function validateSelfiePath(value: unknown, employeeId: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw "invalid_selfie_path";
  if (value.length === 0) return null;
  // JS `$` (without /m) also matches just before a trailing "\n", so anchor with
  // an explicit control-char reject to keep parity with the DB check, whose POSIX
  // `$` binds to the true string end.
  const pattern = new RegExp(`^${employeeId}/[0-9]{4}/[A-Za-z0-9._-]+$`);
  if (
    value.length > 512 ||
    /[\x00-\x1f\x7f]/.test(value) ||
    value.includes("\\") ||
    value.includes("://") ||
    value.includes("..") ||
    !pattern.test(value)
  ) {
    throw "invalid_selfie_path";
  }
  return value;
}

Deno.serve(createHandler({ functionName: "verify-attendance-punch", version: "1.0.0" }, async (req, ctx) => {
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

  // Rate limit: 6 distinct punch operations per 60s per employee. Normal usage
  // is 2/day (check-in + check-out); the headroom covers legitimate transport
  // retries, which reuse the same operation_id and so are NOT counted twice.
  // Counts only requests that reached finalize_verified_attendance (rows are
  // inserted there), not pre-finalize failures — the WebAuthn verify path is
  // guarded upstream by the per-user webauthn-challenge limit (20/min).
  {
    const rlWindow = new Date(Date.now() - 60_000).toISOString();
    const { count: rlCount, error: rlError } = await admin
      .from("attendance_punch_attempts")
      .select("operation_id", { count: "exact", head: true })
      .eq("employee_id", profile.employee_id)
      .gte("created_at", rlWindow);
    if (rlError) return json(req, { error: "rate_limit_check_failed" }, 500);
    if ((rlCount ?? 0) >= 6) {
      return json(req, { error: "too_many_attempts", retryAfterSeconds: 60 }, 429);
    }
  }

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return json(req, { error: "bad_request" }, 400);
  }

  const eventType = String(input.eventType ?? input.event_type ?? "").toUpperCase();
  if (eventType !== "CHECK_IN" && eventType !== "CHECK_OUT") {
    return json(req, { error: "invalid_event_type" }, 400);
  }
  const latitude = input.latitude;
  const longitude = input.longitude;
  const accuracy = input.accuracyMeters ?? input.accuracy_meters;
  const coordinateError = validateCoordinates(latitude, longitude, accuracy);
  if (coordinateError) return json(req, { error: coordinateError }, 400);
  // علم الموقع المزيف من نظام تشغيل الجهاز؛ يُمرَّر للخادم للمراجعة الإلزامية.
  const isMockLocation = input.isMock === true || input.is_mock === true;
  const operationId = String(input.operationId ?? input.operation_id ?? "");
  const correlationId = String(input.correlationId ?? input.correlation_id ?? operationId);
  const challengeId = String(input.challengeId ?? input.challenge_id ?? "");
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(operationId) || !uuidPattern.test(correlationId) || !uuidPattern.test(challengeId)) {
    return json(req, { error: "invalid_operation_context" }, 400);
  }

  // مسار السيلفي (إن وُجد) يجب أن يكون مفتاح كائن مقيَّداً بمجلّد الموظف نفسه
  // <employee_id>/<yyyy>/<اسم_الملف> — نرفض المخططات والمسارات المطلقة والاجتياز
  // ومجلّد موظف آخر قبل الوصول إلى قاعدة البيانات (دفاع في العمق؛ الـ RPC هو المرجع).
  let rawSelfiePath: string | null;
  try {
    rawSelfiePath = validateSelfiePath(input.selfiePath, String(profile.employee_id));
  } catch {
    return json(req, { error: "invalid_selfie_path", correlationId }, 400);
  }

  // A transport retry after commit must return the stored result without
  // re-verifying or trying to consume the already-used WebAuthn challenge.
  const { data: priorAttempt, error: priorAttemptError } = await admin
    .from("attendance_punch_attempts")
    .select("challenge_id, employee_id, user_id, status, result")
    .eq("operation_id", operationId)
    .maybeSingle();
  if (priorAttemptError) {
    return json(req, { error: "operation_lookup_failed", correlationId }, 500);
  }
  if (priorAttempt) {
    if (priorAttempt.employee_id !== profile.employee_id ||
        priorAttempt.user_id !== userData.user.id ||
        priorAttempt.challenge_id !== challengeId) {
      return json(req, { error: "operation_conflict", correlationId }, 409);
    }
    if ((priorAttempt.status === "completed" || priorAttempt.status === "rejected") && priorAttempt.result) {
      const replay = { ...(priorAttempt.result as Record<string, unknown>), replayed: true };
      return json(req, replay, priorAttempt.status === "completed" ? 200 : 400);
    }
  }

  const response = (input.response ?? input.assertion) as Record<string, unknown> | undefined;
  const credentialId = String(response?.id ?? response?.rawId ?? "");
  if (!response || !credentialId) return json(req, { error: "assertion_required" }, 400);

  const { data: credential, error: credentialError } = await admin
    .from("passkey_credentials")
    .select("id, credential_id, public_key, status, employee_id, user_id, sign_count, transports, device_label")
    .eq("credential_id", credentialId)
    .eq("employee_id", profile.employee_id)
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (credentialError) return json(req, { error: "credential_lookup_failed" }, 500);
  if (!credential) return json(req, { error: "credential_not_found" }, 403);
  if (credential.status !== "active") return json(req, { error: "credential_disabled" }, 403);

  // The device registry is the canonical revocation boundary. A stale active
  // passkey row must never bypass a blocked/revoked employee device.
  const { data: device, error: deviceError } = await admin
    .from("employee_devices")
    .select("id, status")
    .eq("employee_id", profile.employee_id)
    .eq("user_id", userData.user.id)
    .eq("credential_id", credentialId)
    .maybeSingle();
  if (deviceError) return json(req, { error: "device_lookup_failed" }, 500);

  // Auto-provision the device row if the credential is active but the device
  // row is missing (pre-0073 passkeys or migration edge cases). The device
  // is only blocked/revoked when an explicit admin action created a revoked row.
  if (!device) {
    const deviceHash = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(credentialId),
    );
    const hashHex = Array.from(new Uint8Array(deviceHash))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    const { error: provisionError } = await admin
      .from("employee_devices")
      .upsert({
        employee_id: profile.employee_id,
        user_id: userData.user.id,
        device_identifier_hash: hashHex,
        credential_id: credentialId,
        public_key: credential.public_key,
        device_name: credential.device_label || "هاتف الموظف",
        platform: "android",
        status: "pending",
        registered_at: new Date().toISOString(),
        metadata: {
          serverVerified: true,
          autoProvisioned: "verify_attendance_punch",
          passkeyCredentialId: credential.id,
        },
      }, { onConflict: "employee_id,device_identifier_hash" });
    if (provisionError) {
      ctx.log.error("auto-provision employee_devices failed", provisionError);
      return json(req, { error: "device_provision_failed" }, 500);
    }
    // الجهاز أُنشئ بحالة pending — يجب اعتماده من المسؤول أولاً.
    return json(req, { error: "device_pending_approval", correlationId }, 403);
  } else if (device.status !== "active") {
    const errorCode = device.status === "pending" ? "device_pending_approval" : "device_not_active";
    return json(req, { error: errorCode }, 403);
  }

  const { data: challenge, error: challengeError } = await admin
    .from("webauthn_challenges")
    .select("id, challenge, relying_party_id")
    .eq("id", challengeId)
    .eq("user_id", userData.user.id)
    .eq("employee_id", profile.employee_id)
    .eq("type", "auth")
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
    verification = await verifyAuthenticationResponse({
      response: response as unknown as AuthenticationResponse,
      expectedChallenge: challenge.challenge,
      expectedOrigin: expectedOrigins,
      expectedRPID: challenge.relying_party_id ?? RP_ID,
      requireUserVerification: true,
      credential: {
        id: credential.credential_id,
        publicKey: b64urlToBytes(credential.public_key),
        counter: Number(credential.sign_count ?? 0),
        transports: normalizeTransports(credential.transports),
      },
    });
  } catch (error) {
    ctx.log.error("attendance assertion verification failed", error);
    return json(req, { error: "assertion_verification_failed" }, 403);
  }
  if (!verification.verified) return json(req, { error: "assertion_not_verified" }, 403);

  const { data: result, error: rpcError } = await admin.rpc("finalize_verified_attendance", {
    p_operation_id: operationId,
    p_correlation_id: correlationId,
    p_challenge_id: challenge.id,
    p_credential_id: credential.id,
    p_employee_id: profile.employee_id,
    p_user_id: userData.user.id,
    p_event_type: eventType,
    p_latitude: latitude,
    p_longitude: longitude,
    p_accuracy_meters: accuracy,
    p_new_sign_count: verification.authenticationInfo.newCounter,
    p_selfie_path: rawSelfiePath,
    p_is_mock: isMockLocation,
  });
  if (rpcError) {
    ctx.log.error("finalize_verified_attendance failed", rpcError, { correlationId });
    return json(req, { error: "record_failed", correlationId }, 500);
  }
  const finalized = result as Record<string, unknown>;
  if (finalized?.ok !== true) {
    return json(req, finalized, 400);
  }
  return json(req, finalized, 200);
}));
