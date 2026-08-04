import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { json, preflight } from "../_shared/cors.ts";
import { normalizePhone } from "../_shared/phone.ts";

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
  // رابط الصورة: يجب أن يكون https فقط — نرفض data:/file:/javascript:/blob:
  // (z.url() وحده يقبلها). التحقق الخادمي في DB يوفّر طبقة ثانية.
  photoUrl: z
    .string()
    .url()
    .max(1000)
    .refine((value) => /^https:\/\//i.test(value), {
      message: "photoUrl must be an https URL",
    })
    .optional(),
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
  sendInvite: z.boolean().default(false),
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

  const { data: canCreate, error: permissionError } = await userClient.rpc("has_permission", {
    p_code: "people.employee.create",
  });
  if (permissionError) return json(req, { error: "permission_check_failed" }, 500);
  if (canCreate !== true) return json(req, { error: "forbidden" }, 403);

  // ─── Rate limit: 10 إنشاءات في الدقيقة لكل مستخدم ───
  const oneMinuteAgo = new Date(Date.now() - 60_000).toISOString();
  const { count: recentCount, error: rlError } = await admin
    .from("employees")
    .select("id", { count: "exact", head: true })
    .eq("created_by", userData.user.id)
    .gte("created_at", oneMinuteAgo);
  if (rlError) return json(req, { error: "rate_limit_check_failed" }, 500);
  if ((recentCount ?? 0) >= 10) {
    return json(req, { error: "too_many_requests", retryAfterSeconds: 60 }, 429);
  }

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

  // ─── إنشاء حساب Auth مع استعادة تلقائية من اليتيم (orphan recovery) ───
  // إذا فشل الإنشاء لأن البريد موجود مسبقًا (من محاولة سابقة فاشلة)،
  // نحذف الحساب اليتيم ونعيد المحاولة مرة واحدة.
  // يستخدم GoTRUE REST API مباشرة لتجنب مشاكل supabase-js مع صيغ المفاتيح الجديدة.
  const tryCreateAuthUser = async (): Promise<{
    data: { user: { id: string; email?: string } | null };
    error: { message: string; status?: number } | null;
  }> => {
    if (input.sendInvite) {
      const result = await admin.auth.admin.inviteUserByEmail(normalizedEmail, {
        redirectTo: INVITE_REDIRECT,
        data: userMetadata,
      });
      return result as { data: { user: { id: string; email?: string } | null }; error: { message: string; status?: number } | null };
    }

    // استدعاء GoTRUE REST API مباشرة
    const password = inaccessibleRandomPassword();
    const reqBody = {
      email: normalizedEmail,
      password,
      // الحساب يُنشأ بواسطة إداري مصادَق يحق له إنشاء الموظف — نؤكد البريد فوراً.
      // بدون هذا، يستطيع الموظف تعيين كلمة مرور عبر رابط الاسترداد (إعادة الدعوة)
      // لكن تسجيل الدخول لاحقاً يفشل لأن GoTrue يرفض "Email not confirmed".
      email_confirm: true,
      user_metadata: userMetadata,
    };
    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SERVICE_ROLE,
      },
      body: JSON.stringify(reqBody),
    });
    const rawText = await res.text();
    let body: Record<string, unknown> | null = null;
    try { body = JSON.parse(rawText); } catch { /* not JSON */ }
    const createdUserId = typeof body?.id === "string" ? body.id : null;
    const createdUserEmail = typeof body?.email === "string" ? body.email : undefined;
    if (!res.ok || !createdUserId) {
      return {
        data: { user: null },
        error: {
          message: rawText.substring(0, 500),
          status: res.status,
        },
      };
    }
    return {
      data: { user: { id: createdUserId, email: createdUserEmail } },
      error: null,
    };
  };

  const isDuplicateError = (err: { message?: string; status?: number } | null): boolean => {
    if (!err) return false;
    const msg = (err.message ?? "").toLowerCase();
    return msg.includes("already") || msg.includes("registered") ||
      msg.includes("exists") || msg.includes("duplicate") ||
      msg.includes("unique") || (err as { status?: number }).status === 422;
  };

  let { data: created, error: createError } = await tryCreateAuthUser();

  // استعادة من حساب يتيم: حذف ثم إعادة إنشاء
  if (createError && isDuplicateError(createError)) {
    console.error("auth.createUser duplicate detected — attempting orphan recovery", {
      message: createError.message,
      status: (createError as { status?: number }).status,
    });

    // البحث عن الحساب اليتيم عبر GoTrue Admin REST API
    const listRes = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?filter=email%20eq%20%22${encodeURIComponent(normalizedEmail)}%22&page=1&per_page=1`,
      { headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE } },
    );
    const listBody = await listRes.json().catch(() => null);
    const existingUsers = listBody?.users ?? [];

    if (existingUsers.length > 0) {
      const orphanId = existingUsers[0].id;
      // تأكد أنه يتيم فعلاً (ليس لديه سجل موظف)
      const { data: empRow } = await admin
        .from("employees")
        .select("id")
        .eq("user_id", orphanId)
        .eq("is_deleted", false)
        .maybeSingle();

      if (empRow) {
        // الحساب مربوط بموظف فعلي — ليس يتيم
        return json(req, { error: "account_already_exists" }, 409);
      }

      // حذف اليتيم وإعادة المحاولة
      console.error("deleting orphaned auth user for recovery", { orphanId });
      await admin.auth.admin.deleteUser(orphanId).catch(() => undefined);
      ({ data: created, error: createError } = await tryCreateAuthUser());
    }
  }

  if (createError || !created?.user) {
    console.error("auth.createUser failed", {
      message: createError?.message,
      status: (createError as { status?: number })?.status,
      name: (createError as { name?: string })?.name,
    });
    if (isDuplicateError(createError)) {
      return json(req, { error: "account_already_exists" }, 409);
    }
    return json(req, { error: "account_create_failed" }, 500);
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
    if (deleteError) {
      console.error("orphaned auth user cleanup failed", { code: (deleteError as { code?: string })?.code });
    }
    return json(req, { error: errorCode }, 500);
  }

  const result = provisioned as { employeeId?: string; userId?: string } | null;
  return json(req, {
    employeeId: result?.employeeId,
    userId: result?.userId ?? userId,
    invitationSent: input.sendInvite,
  }, 201);
  } catch (err) {
    console.error("admin-create-employee unhandled error", err instanceof Error ? err.message : String(err));
    return json(req, { error: "INTERNAL_ERROR" }, 500);
  }
});
