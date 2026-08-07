/**
 * Wrapper موحّد لـ Supabase Edge Functions (Deno).
 *
 * يوفر:
 *  - Logger منظّم (JSON, PII-hashed, leveled) عبر _shared/logger.ts
 *  - Request ID تلقائي (من header أو UUID مولّد)
 *  - try/catch أخير يلتقط أي خطأ غير معالج ويسجّله ويُرجع 500
 *  - x-request-id header في كل استجابة لمتابعة الطلبات
 *
 * الاستخدام:
 *   import { createHandler } from "../_shared/withHandler.ts";
 *
 *   Deno.serve(createHandler(
 *     { functionName: "verify-attendance-punch", version: "1.0.0" },
 *     async (req, log) => {
 *       if (req.method === "OPTIONS") return preflight(req);
 *       // ... منطق الدالة ...
 *       log.info("punch verified", { durationMs });
 *       return json(req, { ok: true });
 *     },
 *   ));
 */

import { createLogger, type Logger } from "./logger.ts";
import { json, preflight } from "./cors.ts";

export { createLogger };
export type { Logger };

export interface HandlerContext {
  requestId: string;
  log: Logger;
}

export type EdgeHandler = (
  req: Request,
  ctx: HandlerContext,
) => Promise<Response>;

interface HandlerOptions {
  functionName: string;
  version?: string;
}

/**
 * يلفّ handler الـ edge function بـ try/catch + logger + requestId.
 */
export function createHandler(
  opts: HandlerOptions,
  handler: EdgeHandler,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const requestId =
      req.headers.get("x-request-id") ||
      crypto.randomUUID();

    const log = createLogger({
      functionName: opts.functionName,
      version: opts.version ?? "1.0.0",
      requestId,
      // employeeId/userId يُضبط لاحقاً داخل الـ handler عند توفّر السياق
    });

    const start = Date.now();

    try {
      const res = await handler(req, { requestId, log });

      // إضافة x-request-id header للسماح للعميل بمتابعة الطلب
      const newHeaders = new Headers(res.headers);
      newHeaders.set("x-request-id", requestId);
      const duration = Date.now() - start;
      log.debug("request completed", {
        status: res.status,
        duration_ms: duration,
      });
      return new Response(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers: newHeaders,
      });
    } catch (err) {
      const duration = Date.now() - start;
      log.error("unhandled error", err, {
        duration_ms: duration,
      });

      const res = json(req, {
        error: "INTERNAL_ERROR",
        request_id: requestId,
      }, 500);

      // إضافة x-request-id حتى في الأخطاء
      const newHeaders = new Headers(res.headers);
      newHeaders.set("x-request-id", requestId);
      return new Response(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers: newHeaders,
      });
    }
  };
}
