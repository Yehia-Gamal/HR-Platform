import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";
import { createHandler } from "../_shared/withHandler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// تعديل البريد الإلكتروني لحساب موظف من لوحة الإدارة. البريد يعيش في
// auth.users (وليس في جدول employees)، لذا يُنفَّذ التغيير بصلاحية
// service_role عبر GoTrue Admin REST API مع تأكيد البريد فوراً كي لا يفشل
// تسجيل الدخول برسالة "Email not confirmed".
const inputSchema = z.object({
  employeeId: z.string().uuid(),
  email: z.string().email(),
});

Deno.serve(createHandler({ functionName: "admin-update-email", version: "1.0.0" }, async (req, ctx) => {
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

  // تغيير بريد الدخول عملية حساسة — تتطلب صلاحية التعديل الحساس.
  const { data: canManage, error: permissionError } = await userClient.rpc("has_permission", {
    p_code: "people.employee.update_sensitive",
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
  const normalizedEmail = input.email.trim().toLowerCase();

  // حتى لا يستطيع مشرف النطاق الواحد تعديل بريد موظف خارج نطاقه.
  const { data: canAccess, error: scopeError } = await userClient.rpc("can_access_employee", {
    p_employee_id: input.employeeId,
    p_code: "people.employee.update_sensitive",
  });
  if (scopeError) return json(req, { error: "permission_check_failed" }, 500);
  if (canAccess !== true) return json(req, { error: "forbidden" }, 403);

  // Resolve the auth user linked to this employee (profiles.id === auth.users.id).
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id")
    .eq("employee_id", input.employeeId)
    .maybeSingle();
  if (profileError) return json(req, { error: "lookup_failed" }, 500);
  if (!profile?.id) return json(req, { error: "no_linked_account" }, 404);

  const { data: authUser, error: getUserError } = await admin.auth.admin.getUserById(profile.id);
  if (getUserError || !authUser.user) return json(req, { error: "account_lookup_failed" }, 404);

  // لا حاجة لأي تغيير إذا كان البريد الحالي مطابقاً.
  if ((authUser.user.email ?? "").toLowerCase() === normalizedEmail) {
    return json(req, { updated: false, unchanged: true }, 200);
  }

  // التأكد أن البريد الجديد غير مستخدم من حساب آخر — عبر GoTrue Admin REST API.
  const listRes = await fetch(
    `${SUPABASE_URL}/auth/v1/admin/users?filter=email%20eq%20%22${encodeURIComponent(normalizedEmail)}%22&page=1&per_page=1`,
    { headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE } },
  );
  const listBody = await listRes.json().catch(() => null);
  const existingUsers: Array<{ id: string }> = listBody?.users ?? [];
  const conflict = existingUsers.find((u) => u.id !== profile.id);
  if (conflict) return json(req, { error: "email_already_exists" }, 409);

  // تحديث بريد الحساب مع تأكيده فوراً (نمط admin-create-employee / admin-set-password).
  const updateRes = await fetch(
    `${SUPABASE_URL}/auth/v1/admin/users/${profile.id}`,
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        "apikey": SERVICE_ROLE,
        "Authorization": `Bearer ${SERVICE_ROLE}`,
      },
      body: JSON.stringify({
        email: normalizedEmail,
        email_confirm: true,
        user_metadata: {
          ...(authUser.user?.user_metadata ?? {}),
        },
      }),
    },
  );
  if (!updateRes.ok) {
    const rawText = await updateRes.text();
    ctx.log.error(
      "admin-update-email update failed",
      undefined,
      { status: updateRes.status, body: rawText.substring(0, 300) },
    );
    return json(req, { error: "email_update_failed" }, 502);
  }

  // سجل التدقيق (نفس توقيع update_employee_admin).
  await admin.rpc("log_audit_event", {
    p_event_type: "employee.email_updated",
    p_category: "data",
    p_severity: "info",
    p_target_table: "employees",
    p_target_id: input.employeeId,
    p_summary_ar: "تعديل البريد الإلكتروني",
    p_description: "تغيير بريد حساب الدخول من لوحة الإدارة",
    p_metadata: {
      actor: userData.user.id,
      before: authUser.user.email ?? null,
      after: normalizedEmail,
      employee_id: input.employeeId,
    },
  });

  return json(req, { updated: true, email: normalizedEmail }, 200);
}));
