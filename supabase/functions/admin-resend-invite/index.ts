import { createClient } from "@supabase/supabase-js";
import { createLogger } from "../_shared/logger.ts";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";
import { generateSecureTemporaryPassword } from "../_shared/phone.ts";
import { createHandler } from "../_shared/withHandler.ts";
const log = createLogger({ functionName: "admin-resend-invite", version: "1.0.0" });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Redirect to the web "mobile redirect" page which then opens the Flutter app
// via the ahlashabab:// scheme. Works on both mobile and desktop.
const DEFAULT_INVITE_REDIRECT =
  "https://ahla-shabab-management-os.vercel.app/mobile-redirect";
const INVITE_REDIRECT =
  Deno.env.get("APP_INVITE_REDIRECT_URL")?.trim() || DEFAULT_INVITE_REDIRECT;

import { adminResendInviteInputSchema } from "../_shared/contracts.ts";

const inputSchema = adminResendInviteInputSchema;

Deno.serve(createHandler({ functionName: "admin-resend-invite", version: "1.0.0" }, async (req, ctx) => {
  if (req.method === "OPTIONS") return preflight(req);
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !PUBLISHABLE_KEY || !SERVICE_ROLE) {
    return json(req, { error: "server_not_configured" }, 500);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json(req, { error: "unauthorized" }, 401);

  const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json(req, { error: "invalid_session" }, 401);

  // Re-sending an activation link is a create-employee capability.
  const { data: canManage, error: permissionError } = await userClient.rpc("has_permission", {
    p_code: "people.employee.create",
  });
  if (permissionError) return json(req, { error: "permission_check_failed" }, 500);
  if (canManage !== true) return json(req, { error: "forbidden" }, 403);

  let input: z.infer<typeof inputSchema>;
  try {
    input = inputSchema.parse(await req.json());
  } catch (error) {
    return json(req, {
      error: "validation_failed",
      details: error instanceof z.ZodError ? error.issues : undefined,
    }, 400);
  }

  // Resolve the auth user linked to this employee (profiles.id === auth.users.id).
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id")
    .eq("employee_id", input.employeeId)
    .maybeSingle();
  if (profileError) return json(req, { error: "lookup_failed" }, 500);
  if (!profile?.id) return json(req, { error: "no_linked_account" }, 404);

  const { data: authUser, error: getUserError } = await admin.auth.admin.getUserById(profile.id);
  if (getUserError || !authUser.user?.email) return json(req, { error: "account_email_missing" }, 404);

  // إصلاح الحسابات القديمة: بعضها أُنشئ بـ email_confirm=false (قبل إصلاح
  // admin-create-employee). دون تأكيد البريد، يستطيع الموظف تعيين كلمة مرور
  // من رابط الاسترداد لكن تسجيل الدخول لاحقاً يفشل ("Email not confirmed").
  // نؤكد البريد الآن كي ينجح الدخول بعد تعيين كلمة المرور.
  //
  // كلمة مرور مؤقتة عشوائية آمنة تُمرَّر للموظف عبر رابط البريد فقط — لا
  // نشتقها من رقم الهاتف (كان ذلك قابلاً للتخمين من أي مسرِّب بيانات).
  // تُجبر على التغيير عند أول دخول عبر must_change_password فلا تبقى سارية.
  const password = generateSecureTemporaryPassword();
  const { error: confirmError } = await admin.auth.admin.updateUserById(profile.id, {
    email_confirm: true,
    password,
    user_metadata: {
      ...(authUser.user?.user_metadata ?? {}),
    },
    // SEC: must_change_password في app_metadata (server-only) — لا يستطيع الموظف تجاوزها بـ updateUser
    app_metadata: { must_change_password: true },
  });
  if (confirmError) {
    ctx.log.error("admin-resend-invite email_confirm update failed", confirmError);
  }

  // Rate limit: at most one invite per employee per 60 seconds.
  const { data: recentInvite, error: recentError } = await admin
    .from("auth_invite_log")
    .select("created_at")
    .eq("employee_id", input.employeeId)
    .gte("created_at", new Date(Date.now() - 60_000).toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (recentError) {
    // جدول auth_invite_log مطلوب (mig 0193) — إذا فشل الاستعلام نرفض بدل التجاهل.
    return json(req, { error: "rate_limit_check_failed" }, 500);
  }
  if (recentInvite) {
    return json(req, { error: "too_many_requests", retryAfterSeconds: 60 }, 429);
  }

  const { error: inviteError } = await admin.auth.resetPasswordForEmail(
    authUser.user.email.toLowerCase(),
    { redirectTo: INVITE_REDIRECT },
  );
  if (inviteError) return json(req, { error: "invite_send_failed" }, 502);

  // Record the invite so the rate-limit check above can actually block repeats.
  const { error: logError } = await admin.from("auth_invite_log").insert({
    employee_id: input.employeeId,
    sent_by: userData.user.id,
    email: authUser.user.email.toLowerCase(),
  });
  if (logError) {
    // الدعوة أُرسلت بنجاح لكن التسجيل فشل — نُبلغ بالخطأ للتتبع.
    ctx.log.error("auth_invite_log insert failed", logError);
  }

  return json(req, { invitationSent: true, email: authUser.user.email }, 200);
}));
