import type { SupabaseClient } from "@supabase/supabase-js";
import { corsHeaders, json } from "./cors.ts";

export interface SensitiveOpQuotaParams {
  opType: "set_password" | "update_email";
  actorId: string;
  employeeId: string;
  maxCount?: number;
  windowSeconds?: number;
}

export interface AuthInviteQuotaParams {
  employeeId: string;
  sentBy: string;
  email: string;
  windowSeconds?: number;
}

function tooManyRequestsResponse(req: Request, retryAfterSeconds: number): Response {
  return new Response(
    JSON.stringify({ error: "too_many_requests", retryAfterSeconds }),
    {
      status: 429,
      headers: {
        ...corsHeaders(req),
        "Content-Type": "application/json; charset=utf-8",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

/**
 * يتحقق ويحجز حصة عملية إدارة حساسة ذرياً عبر دالة SQL محمية بـ advisory lock.
 * يُعيد `null` عند السماح، أو `Response` (429 / 500) عند الرفض أو الخطأ.
 */
export async function enforceSensitiveOpQuota(
  req: Request,
  adminClient: SupabaseClient,
  params: SensitiveOpQuotaParams,
): Promise<Response | null> {
  const windowSeconds = params.windowSeconds ?? 300;
  const { data: allowed, error } = await adminClient.rpc(
    "consume_admin_sensitive_op_quota",
    {
      p_actor_id: params.actorId,
      p_op_type: params.opType,
      p_employee_id: params.employeeId,
      p_max_count: params.maxCount ?? 5,
      p_window_seconds: windowSeconds,
    },
  );
  if (error) return json(req, { error: "rate_limit_check_failed" }, 500);
  if (allowed !== true) return tooManyRequestsResponse(req, windowSeconds);
  return null;
}

/**
 * يتحقق ويحجز حصة إعادة إرسال دعوة التفعيل ذرياً (دعوة واحدة لكل موظف/دقيقة).
 * يُعيد `null` عند السماح، أو `Response` (429 / 500) عند الرفض أو الخطأ.
 */
export async function enforceAuthInviteQuota(
  req: Request,
  adminClient: SupabaseClient,
  params: AuthInviteQuotaParams,
): Promise<Response | null> {
  const windowSeconds = params.windowSeconds ?? 60;
  const { data: allowed, error } = await adminClient.rpc(
    "consume_auth_invite_quota",
    {
      p_employee_id: params.employeeId,
      p_sent_by: params.sentBy,
      p_email: params.email,
      p_window_seconds: windowSeconds,
    },
  );
  if (error) return json(req, { error: "rate_limit_check_failed" }, 500);
  if (allowed !== true) return tooManyRequestsResponse(req, windowSeconds);
  return null;
}
