import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * أدوار الصلاحيات المرتفعة — تتطابق مع `ELEVATED_EMPLOYEE_ROLES` في `admin-create-employee`.
 * لا يُسمح بتعيين كلمة مرور أو تعديل بريد أو إعادة إرسال دعوة لحساب يحمل أياً منها
 * (أو يحمل دوراً بـ `is_full_access = true`) إلا إذا كان المنفِّذ نفسه `full_access`
 * (أو يعدّل حسابه الشخصي في نطاق الصلاحيات). يمنع ذلك تصعيد الصلاحيات (Privilege Escalation)
 * من مدير موارد بشرية على مستوى المؤسسة إلى حساب الأدمن الكامل أو الإدارة التنفيذية.
 */
export const ELEVATED_TARGET_ROLES = new Set([
  "hr-specialist",
  "hr-manager",
  "executive-director",
  "executive",
  "committee-member",
  "committee-chair",
  "committee-secretary",
]);

export interface TargetPrivilegeVerdict {
  allowed: boolean;
  reason?: "permission_check_failed" | "protected_account_forbidden";
}

/**
 * يتحقق أن المنفِّذ مخوَّل لإدارة بيانات اعتماد الحساب المستهدف (`targetUserId`).
 */
export async function checkTargetAccountPrivilege(
  userClient: SupabaseClient,
  adminClient: SupabaseClient,
  actorUserId: string,
  targetUserId: string,
): Promise<TargetPrivilegeVerdict> {
  // إذا كان المنفِّذ هو صاحب الحساب نفسه فلا يُعد تصعيداً للغير، لكننا نترك
  // الفحص للتحقق من الأدوار المحمية عند استهداف حساب آخر.
  if (actorUserId === targetUserId) {
    return { allowed: true };
  }

  const nowIso = new Date().toISOString();
  const { data: targetRoles, error: rolesError } = await adminClient
    .from("user_roles")
    .select("effective_from, effective_to, roles(slug, is_full_access)")
    .eq("user_id", targetUserId);

  if (rolesError) {
    return { allowed: false, reason: "permission_check_failed" };
  }

  const activeProtected = (targetRoles ?? []).some((row) => {
    const r = row as {
      effective_from?: string | null;
      effective_to?: string | null;
      roles?: { slug?: string | null; is_full_access?: boolean | null } | Array<{ slug?: string | null; is_full_access?: boolean | null }> | null;
    };
    if (r.effective_from && r.effective_from > nowIso) return false;
    if (r.effective_to && r.effective_to <= nowIso) return false;
    const roleObj = Array.isArray(r.roles) ? r.roles[0] : r.roles;
    if (!roleObj) return false;
    return roleObj.is_full_access === true || (typeof roleObj.slug === "string" && ELEVATED_TARGET_ROLES.has(roleObj.slug));
  });

  if (!activeProtected) {
    return { allowed: true };
  }

  const { data: callerIsFullAccess, error: fullAccessError } = await userClient.rpc("current_is_full_access");
  if (fullAccessError) {
    return { allowed: false, reason: "permission_check_failed" };
  }
  if (callerIsFullAccess !== true) {
    return { allowed: false, reason: "protected_account_forbidden" };
  }

  return { allowed: true };
}
