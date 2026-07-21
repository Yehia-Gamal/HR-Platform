import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Redirect to the web "mobile redirect" page which then opens the Flutter app
// via the ahlashabab:// scheme. Works on both mobile and desktop.
const DEFAULT_INVITE_REDIRECT =
  "https://ahla-shabab-management-os.vercel.app/mobile-redirect";
const INVITE_REDIRECT =
  Deno.env.get("APP_INVITE_REDIRECT_URL")?.trim() || DEFAULT_INVITE_REDIRECT;

const inputSchema = z.object({ employeeId: z.string().uuid() });

Deno.serve(async (req) => {
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

  const { error: inviteError } = await admin.auth.resetPasswordForEmail(
    authUser.user.email.toLowerCase(),
    { redirectTo: INVITE_REDIRECT },
  );
  if (inviteError) return json(req, { error: "invite_send_failed" }, 502);

  return json(req, { invitationSent: true, email: authUser.user.email }, 200);
});
