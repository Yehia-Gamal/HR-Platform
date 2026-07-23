import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLISHABLE_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Where the activation email link should redirect after Supabase verifies the
// token. Points to the web "mobile redirect" page which then tries to open the
// Flutter app via the ahlashabab:// custom scheme. This two-step approach works
// whether the user opens the email on mobile (app opens) or desktop (fallback
// message shown). APP_INVITE_REDIRECT_URL overrides for local/custom setups.
const DEFAULT_INVITE_REDIRECT =
  "https://ahla-shabab-management-os.vercel.app/mobile-redirect";
const INVITE_REDIRECT =
  Deno.env.get("APP_INVITE_REDIRECT_URL")?.trim() || DEFAULT_INVITE_REDIRECT;

const nullableUuid = z.string().uuid().nullish();
const inputSchema = z.object({
  fullNameAr: z.string().trim().min(3).max(160),
  fullNameEn: z.string().trim().max(160).optional(),
  employeeCode: z.string().trim().min(2).max(50).optional(),
  email: z.string().email(),
  // هاتف مصري محلي (01…) أو دولي E.164 (+20…).
  phoneE164: z.string().trim().regex(/^(01\d{9}|\+[1-9]\d{7,14})$/),
  roleSlug: z.string().trim().min(2),
  jobTitleName: z.string().trim().max(160).optional(),
  photoUrl: z.string().url().max(1000).optional(),
  managerEmployeeId: nullableUuid,
  departmentId: nullableUuid,
  teamId: nullableUuid,
  branchId: nullableUuid,
  workSiteId: nullableUuid,
  jobTitleId: nullableUuid,
  positionId: nullableUuid,
  gradeId: nullableUuid,
  employmentTypeId: nullableUuid,
  hireDate: z.string().date().optional(),
  sendInvite: z.boolean().default(true),
});

type Input = z.infer<typeof inputSchema>;

const STANDARD_EMPLOYEE_ROLES = new Set([
  "employee",
  "direct-manager",
  "department-manager",
  "branch-manager",
  "operations-officer",
  "operations-manager",
  "operations-manager-1",
  "operations-manager-2",
]);

const ELEVATED_EMPLOYEE_ROLES = new Set([
  "hr-specialist",
  "hr-manager",
  "executive-director",
  "executive",
  "committee-member",
  "committee-chair",
  "committee-secretary",
]);

const ALLOWED_EMPLOYEE_ROLES = new Set([
  ...STANDARD_EMPLOYEE_ROLES,
  ...ELEVATED_EMPLOYEE_ROLES,
]);

function inaccessibleRandomPassword(): string {
  // The value is never returned or logged. Two UUIDs provide enough entropy,
  // while the fixed character classes satisfy common password policies.
  return `Cdx!9-${crypto.randomUUID()}-${crypto.randomUUID()}-aZ`;
}

// تطبيع الهاتف إلى صيغة E.164: المحلي المصري 01XXXXXXXXX ← ‎+20XXXXXXXXX.
// الأرقام الدولية تُترك كما هي. يضمن ثبات ux_employees_phone_e164_active.
function normalizePhone(raw: string): string {
  const trimmed = raw.trim();
  if (/^01\d{9}$/.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

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

  const { data: canCreate, error: permissionError } = await userClient.rpc("has_permission", {
    p_code: "people.employee.create",
  });
  if (permissionError) return json(req, { error: "permission_check_failed" }, 500);
  if (canCreate !== true) return json(req, { error: "forbidden" }, 403);

  let input: Input;
  try {
    input = inputSchema.parse(await req.json());
  } catch (error) {
    return json(req, {
      error: "validation_failed",
      details: error instanceof z.ZodError ? error.issues : undefined,
    }, 400);
  }

  const phoneE164 = normalizePhone(input.phoneE164);
  // كود الموظف: صريح إن وُجد، وإلا يُشتق من الهاتف المطبّع (فريد بطبيعته).
  const employeeCode = input.employeeCode?.trim() || phoneE164;

  if (!ALLOWED_EMPLOYEE_ROLES.has(input.roleSlug)) {
    return json(req, { error: "role_not_allowed" }, 400);
  }

  const { data: targetRole, error: targetRoleError } = await admin
    .from("roles")
    .select("id,slug,is_full_access")
    .eq("slug", input.roleSlug)
    .maybeSingle();
  if (targetRoleError) return json(req, { error: "role_validation_failed" }, 500);
  if (!targetRole || targetRole.is_full_access === true) {
    return json(req, { error: "protected_role_not_allowed" }, 403);
  }

  if (ELEVATED_EMPLOYEE_ROLES.has(input.roleSlug)) {
    const { data: callerIsFullAccess, error: fullAccessError } = await userClient
      .rpc("current_is_full_access");
    if (fullAccessError) return json(req, { error: "role_authorization_failed" }, 500);
    if (callerIsFullAccess !== true) {
      return json(req, { error: "role_assignment_forbidden" }, 403);
    }
  }

  const userMetadata = {
    full_name_ar: input.fullNameAr,
    employee_code: employeeCode,
    must_change_password: true,
  };

  const normalizedEmail = input.email.toLowerCase();
  const { data: created, error: createError } = input.sendInvite
    ? await admin.auth.admin.inviteUserByEmail(normalizedEmail, {
      redirectTo: INVITE_REDIRECT,
      data: userMetadata,
    })
    : await admin.auth.admin.createUser({
      email: normalizedEmail,
      password: inaccessibleRandomPassword(),
      email_confirm: false,
      user_metadata: userMetadata,
    });

  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes("already") ?? false;
    return json(req, { error: duplicate ? "account_already_exists" : "account_create_failed" }, duplicate ? 409 : 500);
  }

  const userId = created.user.id;
  const { data: provisioned, error: provisionError } = await admin.rpc("provision_employee_record", {
    p_actor_user_id: userData.user.id,
    p_user_id: userId,
    p_full_name_ar: input.fullNameAr,
    p_full_name_en: input.fullNameEn ?? null,
    p_employee_code: employeeCode,
    p_phone_e164: phoneE164,
    p_role_slug: input.roleSlug,
    p_manager_employee_id: input.managerEmployeeId ?? null,
    p_department_id: input.departmentId ?? null,
    p_team_id: input.teamId ?? null,
    p_branch_id: input.branchId ?? null,
    p_work_site_id: input.workSiteId ?? null,
    p_job_title_id: input.jobTitleId ?? null,
    p_position_id: input.positionId ?? null,
    p_grade_id: input.gradeId ?? null,
    p_employment_type_id: input.employmentTypeId ?? null,
    p_hire_date: input.hireDate ?? null,
    p_invitation_pending: input.sendInvite,
    p_job_title_name: input.jobTitleName ?? null,
    p_photo_url: input.photoUrl ?? null,
  });

  if (provisionError) {
    // تحديد نوع الخطأ من رسالة PostgreSQL لإرجاع رمز مفهوم للواجهة.
    const msg = (provisionError as { message?: string })?.message ?? "";
    let errorCode = "employee_provision_failed";
    if (/phone.*already|phone_e164/i.test(msg) || (msg.includes("23505") && msg.includes("phone")))
      errorCode = "phone_already_exists";
    else if (/employee.code.*already|employee_code/i.test(msg) || msg.includes("23505"))
      errorCode = "employee_code_already_exists";
    else if (/unknown.role/i.test(msg)) errorCode = "role_not_allowed";
    else if (/manager.*not.*active/i.test(msg)) errorCode = "manager_not_active";

    // محاولة تنظيف حساب المصادقة اليتيم — إعادة محاولة واحدة عند الفشل.
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      await admin.auth.admin.deleteUser(userId).catch(() => undefined);
    }
    return json(req, { error: errorCode, orphanedUserId: deleteError ? userId : undefined }, 500);
  }

  const result = provisioned as { employeeId?: string; userId?: string } | null;
  return json(req, {
    employeeId: result?.employeeId,
    userId: result?.userId ?? userId,
    invitationSent: input.sendInvite,
  }, 201);
});
