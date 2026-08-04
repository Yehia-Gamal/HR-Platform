import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// كلمة مرور موظف يضعها الإداري من لوحة الويب. تُفرض تغييرها عند أول دخول
// (must_change_password) فلا تبقى سارية بعد ذلك — نفس نهج كلمة مرور الهاتف المؤقتة.
const inputSchema = z.object({
  employeeId: z.string().uuid(),
  password: z.string().min(8).max(72),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight(req);
  try {
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

    // تعيين كلمة مرور موظف عملية حساسة — تتطلب صلاحية التعديل الحساس.
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

    // حتى لا يستطيع مشرف النطاق الواحد ضبط كلمة مرور موظف خارج نطاقه.
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

    // نضبط كلمة المرور ونُجبر التغيير عند أول دخول. لا نسجّل كلمة المرور أبدًا.
    // نستخدم GoTRUE REST API مباشرة (نمط admin-create-employee) بدلاً من
    // supabase-js updateUserById — الأخير قد يُسقط email_confirm/يفشل بصمت.
    // email_confirm: true — بدونها يبقى البريد غير مؤكد ويرفض GoTrue تسجيل الدخول
    // ("Email not confirmed") حتى مع كلمة المرور الصحيحة.
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
          password: input.password,
          email_confirm: true,
          user_metadata: {
            ...(authUser.user?.user_metadata ?? {}),
            must_change_password: true,
          },
        }),
      },
    );
    if (!updateRes.ok) {
      const rawText = await updateRes.text();
      console.error(
        "admin-set-password update failed",
        updateRes.status,
        rawText.substring(0, 300),
      );
      return json(req, { error: "password_update_failed" }, 502);
    }

    return json(req, { updated: true }, 200);
  } catch (err) {
    console.error("admin-set-password unhandled error", err instanceof Error ? err.message : String(err));
    return json(req, { error: "INTERNAL_ERROR" }, 500);
  }
});
