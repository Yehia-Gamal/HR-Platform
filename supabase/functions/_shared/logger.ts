/**
 * Structured logger for Supabase Edge Functions (Deno).
 * Emits JSON logs to stdout/stderr — collected by Supabase logs and any log drain.
 *
 * PII: employeeId/userId are NEVER emitted raw. They are hashed (FNV-1a, non-reversible)
 * into short correlation tokens so logs can be joined without exposing identities.
 *
 * Usage:
 *   import { createLogger } from "../_shared/logger.ts";
 *   const log = createLogger({ functionName: "verify-attendance-punch", version: "1.0.0" });
 *   log.info("punch verified", { employeeId, durationMs });
 *   log.error("verification failed", err, { employeeId });
 */

/** تجزئة FNV-1a غير عكسية → رمز ربط قصير بدل الـ ID الخام (منع تسريب PII). */
function correlationToken(value: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export type LogLevel = "debug" | "info" | "warning" | "error";

export interface LogContext {
  functionName: string;
  version?: string;
  environment?: string;
  requestId?: string;
  employeeId?: string;
  userId?: string;
}

export interface LogEntry {
  timestamp: string;
  level: LogLevel;
  function_name: string;
  version: string;
  environment: string;
  request_id?: string;
  employee_ref?: string;
  user_ref?: string;
  message: string;
  duration_ms?: number;
  error_name?: string;
  error_message?: string;
  error_stack?: string;
  data?: Record<string, unknown>;
}

/** مفاتيح تُعد PII وتُجزّأ تلقائياً إن مرّرها المستدعي ضمن data. */
const PII_KEYS = new Set(["employeeId", "userId", "employee_id", "user_id", "email", "phone"]);

/** يستبدل أي مفتاح PII برمز ربط مجزّأ — يشمل الكائنات والمصفوفات المتداخلة. */
function sanitizeValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitizeValue);
  if (value !== null && typeof value === "object") {
    return sanitizeExtra(value as Record<string, unknown>);
  }
  return value;
}

function sanitizeExtra(extra?: Record<string, unknown>): Record<string, unknown> | undefined {
  if (!extra) return undefined;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(extra)) {
    if (PII_KEYS.has(key)) {
      if (value != null) out[`${key}_ref`] = correlationToken(String(value));
    } else {
      out[key] = sanitizeValue(value);
    }
  }
  return out;
}

export class Logger {
  private readonly ctx: LogContext;
  private readonly env: string;

  constructor(ctx: LogContext) {
    this.ctx = ctx;
    this.env = Deno.env.get("ENVIRONMENT") ?? "production";
  }

  private buildEntry(level: LogLevel, message: string, extra?: Record<string, unknown>, error?: unknown): LogEntry {
    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      function_name: this.ctx.functionName,
      version: this.ctx.version ?? "0.0.0",
      environment: this.env,
      message,
      ...sanitizeExtra(extra),
    };

    if (this.ctx.requestId) entry.request_id = this.ctx.requestId;
    if (this.ctx.employeeId) entry.employee_ref = correlationToken(this.ctx.employeeId);
    if (this.ctx.userId) entry.user_ref = correlationToken(this.ctx.userId);

    if (error != null) {
      const isProd = this.env === "production";
      if (error instanceof Error) {
        entry.error_name = error.name;
        entry.error_message = error.message;
        if (!isProd) {
          entry.error_stack = error.stack?.split("\n").slice(0, 5).join("\n");
        }
      } else if (typeof error === "object") {
        // أخطاء Supabase/PostgREST كائنات عادية {code, message, details} — نلتقط الكود
        // (غير حساس) دائماً، ونكتم الرسالة الخام في الإنتاج لأنها قد تحمل PII.
        const e = error as { code?: unknown; message?: unknown };
        if (e.code != null) entry.error_name = String(e.code);
        if (e.message != null) {
          entry.error_message = isProd ? "[redacted-nonprod-only]" : String(e.message);
        }
      } else {
        entry.error_message = isProd ? "[redacted-nonprod-only]" : String(error);
      }
    }

    return entry;
  }

  private emit(entry: LogEntry): void {
    const line = JSON.stringify(entry);
    if (entry.level === "error") {
      console.error(line);
    } else if (entry.level === "warning") {
      console.warn(line);
    } else {
      console.log(line);
    }
  }

  debug(message: string, data?: Record<string, unknown>): void {
    if (this.env === "production") return;
    this.emit(this.buildEntry("debug", message, data));
  }

  info(message: string, data?: Record<string, unknown>): void {
    this.emit(this.buildEntry("info", message, data));
  }

  warning(message: string, data?: Record<string, unknown>): void {
    this.emit(this.buildEntry("warning", message, data));
  }

  error(message: string, error?: unknown, data?: Record<string, unknown>): void {
    this.emit(this.buildEntry("error", message, { ...data }, error));
  }

  /** Wrap an async operation with duration tracking */
  async timed<T>(operation: string, fn: () => Promise<T>, data?: Record<string, unknown>): Promise<T> {
    const start = Date.now();
    try {
      const result = await fn();
      const duration = Date.now() - start;
      this.info(`${operation} completed`, { ...data, duration_ms: duration });
      return result;
    } catch (err) {
      const duration = Date.now() - start;
      this.error(`${operation} failed`, err, { ...data, duration_ms: duration });
      throw err;
    }
  }

  /** Create a child logger with additional context */
  child(extra: Partial<LogContext>): Logger {
    return new Logger({ ...this.ctx, ...extra });
  }
}

export function createLogger(ctx: LogContext): Logger {
  return new Logger(ctx);
}
