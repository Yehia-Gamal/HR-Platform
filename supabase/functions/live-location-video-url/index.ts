// live-location-video-url: يوقّع رابطًا قصير الصلاحية لفيديو تحقق الموقع.
// المسار: يتحقق من JWT المستدعي → يعيد التحقق من الصلاحية عبر RPC
// can_view_live_location_video (بسياق RLS للمستخدم) → يوقّع الرابط بخدمة
// الخدمة (service role) → يسجّل صف signed_url في سجل الوصول → يعيد الرابط.
//
// لا يُسلَّم رابط عام، ولا يُوقَّع دون إعادة فحص صلاحية العرض.

import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SIGNED_TTL_SECONDS = 120; // صلاحية قصيرة جدًا

const inputSchema = z.object({ videoId: z.string().uuid() });

Deno.serve(async (req) => {
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

  // عميل بسياق المستخدم (RLS): يعيد التحقق من صلاحية العرض.
  const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) return json(req, { error: "unauthorized" }, 401);

  // البوابة: تعيد مسار التخزين إن كان مسموحًا، وإلا null.
  const { data: gate, error: gateError } = await userClient.rpc(
    "can_view_live_location_video",
    { p_video_id: body.videoId },
  );
  if (gateError) return json(req, { error: "GATE_FAILED" }, 500);
  if (!gate || !gate.storagePath) return json(req, { error: "FORBIDDEN" }, 403);

  // توقيع الرابط بخدمة الخدمة (يتطلب service role).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const { data: signed, error: signError } = await admin.storage
    .from(gate.bucket ?? "live-location-videos")
    .createSignedUrl(gate.storagePath, SIGNED_TTL_SECONDS);
  if (signError || !signed?.signedUrl) return json(req, { error: "SIGN_FAILED" }, 500);

  // سجل وصول signed_url (بسياق المستخدم لضبط actor عبر RLS المسموح).
  await admin.from("live_location_video_access_logs").insert({
    video_id: body.videoId,
    actor_user_id: userData.user.id,
    action: "signed_url",
  });

  return json(req, { url: signed.signedUrl, expiresInSeconds: SIGNED_TTL_SECONDS });
});
